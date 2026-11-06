-- The performance counters with checks of their port, for SymbiYosys.
-- Every input is free, so the solver tries every bus master and every core
-- that raises instret_i, reports a step, or makes a data access at any
-- time.
--
-- THEORY OF OPERATION
-- The wrapper models the counters of SYSTEM.md §3: a 64-bit counter of
-- every cycle, a 64-bit counter of the cycles with instret_i high, a 64-bit
-- counter of microseconds, and a snapshot of each, which a read of its low
-- word takes. The clock is 1.5 MHz, C_CLK_HZ, so the microsecond counter
-- must count two microseconds in every three cycles with run_i high: the
-- model counts those cycles modulo 3 and has no accumulator, so the proof
-- also checks the arithmetic of perf's, which subtracts 1500000 from
-- 2000000 and from 1500000 in turn. The model counts the events of
-- SYSTEM.md §3 too: the data reads and stores that the core's bus accepts,
-- and of the steps reported that do not halt, the skipped ones, those that
-- write R15, and the interrupt entries and INTs. Its rule for a jump is
-- spelled out from the bits of the instruction word, apart from
-- writes_r15 of nice_pkg, which perf uses. f_expect is what a
-- read accepted in this cycle must return: the low word of a counter, the
-- high word of its snapshot, or 0 for a spare word. wb_slave_check says
-- that the port never stalls and acknowledges each request in the next
-- cycle and nothing else, and f_data that the data of a read's ACK is
-- f_expect of the cycle it was accepted. So a read of CYCLE_HI after one
-- of CYCLE_LO returns the high word of the counter at the time of the read
-- of CYCLE_LO, also when the low word wrapped in between. Writes are not
-- in the model, so the assertions also say that writes change nothing.
-- The covers show a read of each word, and a read of CYCLE_HI after the
-- low word wrapped; the cover task sets G_RESET near a wrap for that.
--
-- RESET
-- The first cycle is a reset.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use work.trace_pkg.all;

entity formal_perf is
   generic (
      G_RESET : std_logic_vector(63 downto 0) := (others => '0')
   );
   port (
      clk_i     : in  std_logic;
      rst_i     : in  std_logic;
      instret_i : in  std_logic;
      run_i     : in  std_logic;
      -- A step reported on retire_i, and one that halts
      r_valid_i : in  std_logic;
      r_intr_i  : in  std_logic;
      r_skip_i  : in  std_logic;
      r_halt_i  : in  std_logic;
      r_iw_i    : in  std_logic_vector(31 downto 0);
      -- The core's data bus
      d_stb_i   : in  std_logic;
      d_we_i    : in  std_logic;
      d_stall_i : in  std_logic;
      wb_cyc_i  : in  std_logic;
      wb_stb_i  : in  std_logic;
      wb_we_i   : in  std_logic;
      wb_addr_i : in  std_logic_vector(4 downto 0);
      wb_data_i : in  std_logic_vector(31 downto 0)
   );
end entity formal_perf;

architecture synthesis of formal_perf is

   -- The clock frequency: two microseconds in every three cycles.
   constant C_CLK_HZ : natural := 1500000;

   signal wb_stall : std_logic;
   signal wb_ack   : std_logic;
   signal wb_data  : std_logic_vector(31 downto 0);

   signal f_read     : std_logic;
   signal f_cycles   : std_logic_vector(63 downto 0) := G_RESET;
   signal f_instrs   : std_logic_vector(63 downto 0) := G_RESET;
   signal f_cyc_snap : std_logic_vector(63 downto 0) := G_RESET;
   signal f_ins_snap : std_logic_vector(63 downto 0) := G_RESET;
   signal f_micros   : std_logic_vector(63 downto 0) := G_RESET;
   signal f_mic_snap : std_logic_vector(63 downto 0) := G_RESET;

   -- The events: data reads, stores, skips, jumps, and interrupts
   type t_events is array (0 to 4) of std_logic_vector(63 downto 0);

   signal f_ev      : std_logic_vector(0 to 4);
   signal f_ev_cnt  : t_events := (others => G_RESET);
   signal f_ev_snap : t_events := (others => G_RESET);
   signal retire    : t_retire;
   -- The cycles with run_i high so far, modulo 3. The first of each three
   -- counts no microsecond, the other two one each.
   signal f_phase  : natural range 0 to 2 := 0;
   signal f_expect : std_logic_vector(31 downto 0);
   signal f_last_r : std_logic_vector(31 downto 0) := (others => '0');
   -- The low word of the cycle counter wrapped since the last read of it.
   signal f_wrap_r : std_logic                     := '0';

begin

   f_read <= wb_cyc_i and wb_stb_i and not wb_we_i;

   -- The events of this cycle, from the bits of the instruction word
   p_ev : process (all)
      variable ctrl_v : boolean;
      variable jump_v : boolean;
      variable step_v : boolean;
   begin
      ctrl_v := r_iw_i(27 downto 26) = "11";
      if ctrl_v then
         jump_v := r_iw_i(25 downto 21) = "00001";
      else
         -- dest in mode 000, 001, 010, 101, or 110; s0 or s1 in mode 001,
         -- 010, 101, or 110; register 15 in each
         jump_v := (r_iw_i(17 downto 14) = "1111" and
                    (r_iw_i(20 downto 18) = "000" or r_iw_i(20 downto 18) = "001" or
                       r_iw_i(20 downto 18) = "010" or r_iw_i(20 downto 18) = "101" or
                       r_iw_i(20 downto 18) = "110")) or
                   (r_iw_i(10 downto 7) = "1111" and
                     (r_iw_i(13 downto 11) = "001" or r_iw_i(13 downto 11) = "010" or
                        r_iw_i(13 downto 11) = "101" or r_iw_i(13 downto 11) = "110")) or
                   (r_iw_i(3 downto 0) = "1111" and
                     (r_iw_i(6 downto 4) = "001" or r_iw_i(6 downto 4) = "010" or
                        r_iw_i(6 downto 4) = "101" or r_iw_i(6 downto 4) = "110"));
      end if;
      step_v := r_valid_i = '1' and r_halt_i = '0';

      f_ev    <= "00000";
      f_ev(0) <= d_stb_i and not d_stall_i and not d_we_i;
      f_ev(1) <= d_stb_i and not d_stall_i and d_we_i;
      if step_v and r_intr_i = '0' then
         if r_skip_i = '1' then
            f_ev(2) <= '1';
         elsif jump_v then
            f_ev(3) <= '1';
         end if;
      end if;
      if step_v and (r_intr_i = '1' or
                     (r_skip_i = '0' and ctrl_v and r_iw_i(25 downto 21) = "00010")) then
         f_ev(4) <= '1';
      end if;
   end process p_ev;

   -- The retire report of the free inputs
   p_retire : process (all)
   begin
      retire         <= C_RETIRE_NONE;
      retire.valid   <= r_valid_i;
      retire.intr    <= r_intr_i;
      retire.skipped <= r_skip_i;
      retire.iw      <= r_iw_i;
      if r_halt_i = '1' then
         retire.halt <= HALT_RESERVED;
      end if;
   end process p_retire;

   with wb_addr_i select f_expect <=
      f_cycles(31 downto 0) when "00000",
      f_cyc_snap(63 downto 32) when "00001",
      f_instrs(31 downto 0) when "00010",
      f_ins_snap(63 downto 32) when "00011",
      f_micros(31 downto 0) when "00100",
      f_mic_snap(63 downto 32) when "00101",
      f_ev_cnt(0)(31 downto 0) when "01010",
      f_ev_snap(0)(63 downto 32) when "01011",
      f_ev_cnt(1)(31 downto 0) when "01100",
      f_ev_snap(1)(63 downto 32) when "01101",
      f_ev_cnt(2)(31 downto 0) when "01110",
      f_ev_snap(2)(63 downto 32) when "01111",
      f_ev_cnt(3)(31 downto 0) when "10000",
      f_ev_snap(3)(63 downto 32) when "10001",
      f_ev_cnt(4)(31 downto 0) when "10010",
      f_ev_snap(4)(63 downto 32) when "10011",
      X"00000000" when others;


   p_model : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if run_i = '1' then
            f_cycles <= f_cycles + 1;
            if f_phase = 0 then
               f_phase <= 1;
            else
               f_phase  <= (f_phase + 1) mod 3;
               f_micros <= f_micros + 1;
            end if;
         end if;
         if instret_i = '1' then
            f_instrs <= f_instrs + 1;
         end if;
         for i in 0 to 4 loop
            if f_ev(i) = '1' then
               f_ev_cnt(i) <= f_ev_cnt(i) + 1;
            end if;
         end loop;
         if run_i = '1' and f_cycles(31 downto 0) = X"FFFFFFFF" then
            f_wrap_r <= '1';
         end if;

         if f_read = '1' then
            f_last_r <= f_expect;
            if wb_addr_i = "00000" then
               f_cyc_snap <= f_cycles;
               f_wrap_r   <= '0';
            end if;
            if wb_addr_i = "00010" then
               f_ins_snap <= f_instrs;
            end if;
            if wb_addr_i = "00100" then
               f_mic_snap <= f_micros;
            end if;
            for i in 0 to 4 loop
               if to_integer(wb_addr_i) = 10 + 2 * i then
                  f_ev_snap(i) <= f_ev_cnt(i);
               end if;
            end loop;
         end if;

         if rst_i = '1' then
            f_cycles   <= G_RESET;
            f_instrs   <= G_RESET;
            f_cyc_snap <= G_RESET;
            f_ins_snap <= G_RESET;
            f_micros   <= G_RESET;
            f_mic_snap <= G_RESET;
            f_ev_cnt   <= (others => G_RESET);
            f_ev_snap  <= (others => G_RESET);
            f_phase    <= 0;
            f_wrap_r   <= '0';
         end if;
      end if;
   end process p_model;


   -- psl default clock is rising_edge(clk_i);
   -- psl f_initial_reset : assume rst_i;

   -- psl f_data : assert always
   --    {f_read and not rst_i} |=> {wb_data = f_last_r};

   -- psl c_cycle_hi : cover {f_read = '1' and wb_addr_i = "00001" and f_cyc_snap /= G_RESET};
   -- psl c_instr_hi : cover {f_read = '1' and wb_addr_i = "00011" and f_ins_snap /= G_RESET};
   -- psl c_time_hi : cover {f_read = '1' and wb_addr_i = "00101" and f_mic_snap /= G_RESET};
   -- psl c_read_hi : cover {f_read = '1' and wb_addr_i = "01011" and f_ev_snap(0) /= G_RESET};
   -- psl c_store_hi : cover {f_read = '1' and wb_addr_i = "01101" and f_ev_snap(1) /= G_RESET};
   -- psl c_skip_hi : cover {f_read = '1' and wb_addr_i = "01111" and f_ev_snap(2) /= G_RESET};
   -- psl c_jump_hi : cover {f_read = '1' and wb_addr_i = "10001" and f_ev_snap(3) /= G_RESET};
   -- psl c_intr_hi : cover {f_read = '1' and wb_addr_i = "10011" and f_ev_snap(4) /= G_RESET};
   -- psl c_wrap : cover {f_read = '1' and wb_addr_i = "00001" and f_wrap_r = '1' and
   --    f_cyc_snap(31 downto 0) /= X"00000000"};


   i_perf : entity work.perf
      generic map (
         G_RESET  => G_RESET,
         G_CLK_HZ => C_CLK_HZ
      )
      port map (
         clk_i        => clk_i,
         rst_i        => rst_i,
         instret_i    => instret_i,
         run_i        => run_i,
         retire_i     => retire,
         dbus_stb_i   => d_stb_i,
         dbus_we_i    => d_we_i,
         dbus_stall_i => d_stall_i,
         wb_cyc_i     => wb_cyc_i,
         wb_stb_i     => wb_stb_i,
         wb_stall_o   => wb_stall,
         wb_ack_o     => wb_ack,
         wb_we_i      => wb_we_i,
         wb_addr_i    => wb_addr_i,
         wb_data_i    => wb_data_i,
         wb_data_o    => wb_data
      ); -- i_perf


   i_wb_slave_check : entity work.wb_slave_check
      port map (
         clk_i   => clk_i,
         rst_i   => rst_i,
         cyc_i   => wb_cyc_i,
         stb_i   => wb_stb_i,
         stall_i => wb_stall,
         ack_i   => wb_ack
      ); -- i_wb_slave_check

end architecture synthesis;
