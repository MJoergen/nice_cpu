-- The performance counters with checks of their port, for SymbiYosys.
-- Every input is free, so the solver tries every bus master and every core
-- that raises instret_i at any time.
--
-- THEORY OF OPERATION
-- The wrapper models the counters of SYSTEM.md §3: a 64-bit counter of
-- every cycle, a 64-bit counter of the cycles with instret_i high, a 64-bit
-- counter of microseconds, and a snapshot of each, which a read of its low
-- word takes. The microsecond counter has an accumulator that adds 1000000 in
-- each cycle with run_i high, and counts a microsecond when the sum reaches
-- G_CLK_HZ; the model has the same accumulator, but the proof uses a small
-- G_CLK_HZ that is not a multiple of 1 MHz. f_expect is what a
-- read accepted in this cycle must return: the low word of a counter, the
-- high word of its snapshot, or 0 for a spare word. The assertions say that
-- the port never stalls, that it acknowledges each accepted request in the
-- next cycle and nothing else, and that the data of a read's ACK is
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

entity formal_perf is
   generic (
      G_RESET  : std_logic_vector(63 downto 0) := (others => '0');
      G_CLK_HZ : natural range 1000000 to 500000000 := 1500000
   );
   port (
      clk_i     : in  std_logic;
      rst_i     : in  std_logic;
      instret_i : in  std_logic;
      run_i     : in  std_logic;
      wb_cyc_i  : in  std_logic;
      wb_stb_i  : in  std_logic;
      wb_we_i   : in  std_logic;
      wb_addr_i : in  std_logic_vector(3 downto 0);
      wb_data_i : in  std_logic_vector(31 downto 0)
   );
end entity formal_perf;

architecture synthesis of formal_perf is

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
   signal f_frac     : natural range 0 to G_CLK_HZ - 1 := 0;
   signal f_expect   : std_logic_vector(31 downto 0);
   signal f_last_r   : std_logic_vector(31 downto 0) := (others => '0');
   -- The low word of the cycle counter wrapped since the last read of it.
   signal f_wrap_r : std_logic                     := '0';

begin

   f_read <= wb_cyc_i and wb_stb_i and not wb_we_i;

   with wb_addr_i select f_expect <=
      f_cycles(31 downto 0) when X"0",
      f_cyc_snap(63 downto 32) when X"1",
      f_instrs(31 downto 0) when X"2",
      f_ins_snap(63 downto 32) when X"3",
      f_micros(31 downto 0) when X"4",
      f_mic_snap(63 downto 32) when X"5",
      X"00000000" when others;


   p_model : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if run_i = '1' then
            f_cycles <= f_cycles + 1;
            if f_frac + 1000000 >= G_CLK_HZ then
               f_frac   <= f_frac + 1000000 - G_CLK_HZ;
               f_micros <= f_micros + 1;
            else
               f_frac <= f_frac + 1000000;
            end if;
         end if;
         if instret_i = '1' then
            f_instrs <= f_instrs + 1;
         end if;
         if run_i = '1' and f_cycles(31 downto 0) = X"FFFFFFFF" then
            f_wrap_r <= '1';
         end if;

         if f_read = '1' then
            f_last_r <= f_expect;
            if wb_addr_i = X"0" then
               f_cyc_snap <= f_cycles;
               f_wrap_r   <= '0';
            end if;
            if wb_addr_i = X"2" then
               f_ins_snap <= f_instrs;
            end if;
            if wb_addr_i = X"4" then
               f_mic_snap <= f_micros;
            end if;
         end if;

         if rst_i = '1' then
            f_cycles   <= G_RESET;
            f_instrs   <= G_RESET;
            f_cyc_snap <= G_RESET;
            f_ins_snap <= G_RESET;
            f_micros   <= G_RESET;
            f_mic_snap <= G_RESET;
            f_frac     <= 0;
            f_wrap_r   <= '0';
         end if;
      end if;
   end process p_model;


   -- psl default clock is rising_edge(clk_i);
   -- psl f_initial_reset : assume rst_i;

   -- psl f_no_stall : assert always not wb_stall;
   -- psl f_ack : assert always
   --    {not rst_i} |=> {wb_ack = (prev(wb_cyc_i) and prev(wb_stb_i))};
   -- psl f_ack_reset : assert always rst_i |=> not wb_ack;
   -- psl f_data : assert always
   --    {f_read and not rst_i} |=> {wb_data = f_last_r};

   -- psl c_cycle_hi : cover {f_read = '1' and wb_addr_i = X"1" and f_cyc_snap /= G_RESET};
   -- psl c_instr_hi : cover {f_read = '1' and wb_addr_i = X"3" and f_ins_snap /= G_RESET};
   -- psl c_time_hi : cover {f_read = '1' and wb_addr_i = X"5" and f_mic_snap /= G_RESET};
   -- psl c_wrap : cover {f_read = '1' and wb_addr_i = X"1" and f_wrap_r = '1' and
   --    f_cyc_snap(31 downto 0) /= X"00000000"};


   i_perf : entity work.perf
      generic map (
         G_RESET  => G_RESET,
         G_CLK_HZ => G_CLK_HZ
      )
      port map (
         clk_i      => clk_i,
         rst_i      => rst_i,
         instret_i  => instret_i,
         run_i      => run_i,
         wb_cyc_i   => wb_cyc_i,
         wb_stb_i   => wb_stb_i,
         wb_stall_o => wb_stall,
         wb_ack_o   => wb_ack,
         wb_we_i    => wb_we_i,
         wb_addr_i  => wb_addr_i,
         wb_data_i  => wb_data_i,
         wb_data_o  => wb_data
      ); -- i_perf

end architecture synthesis;
