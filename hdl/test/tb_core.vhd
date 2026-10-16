-- Runs a program on a core, and writes its trace in the format of
-- "niceemu --trace", so that the two can be compared with diff.
--
-- THEORY OF OPERATION
-- G_CORE names the core: "multicycle" for src/multicycle.vhd. Every core
-- has the same ports, so the rest of the testbench serves them all.
-- The core runs on the memory model, sim/wb_mem.vhd, which loads G_BIN_FILE.
-- Its console reads the bytes of G_INPUT_FILE, as the emulator's --input
-- does, or none if it is "".
-- The data bus decoder, src/wb_dmux.vhd, sends 0xFFFFFF10-0xFFFFFF1F to
-- the performance counters, src/perf.vhd (ISA.md §8.5), 0xFFFFFF20-
-- 0xFFFFFF3F to the math unit, src/mpu.vhd (ISA.md §8.4), 0xFFFFFF40-
-- 0xFFFFFF4F to the timer, src/timer.vhd (ISA.md §8.6), and the rest to the
-- memory model. It keeps the ACKs in order for a core with several
-- requests in flight (MICROARCH.md §8). It holds no address map: the
-- address compare that names the slave, dbus_sel, is here.
-- The trace writer, sim/trace.vhd, prints each step the core reports.
--
-- With G_CYCLE_COUNTER false, CYCLE_LO and CYCLE_HI at 0xFFFFFF10 and
-- 0xFFFFFF11 are memory, as with the emulator's --no-cycle-counter. The
-- core's cycle count depends on the memory's stalls, so a program that
-- reads it could not be compared with the emulator otherwise.
--
-- G_INTERRUPTS takes the emulator's interrupt options, for example
-- "--nmi 2:1 --irq 2:2", and the interrupt source p_intr raises the same
-- requests. A request for step S is raised once S steps have been reported,
-- that is, before step S, as in the emulator. A request of the same kind
-- that is raised while one is pending replaces its vector, as the emulator
-- merges them (ISA.md §7.1). The core takes requests only between steps, so
-- the trace matches the emulator's exactly.
--
-- With G_INTR_LOG, p_intr writes a line to that file for each request it
-- raises, "raised S nmi V" or "raised S irq V", where S is the number of
-- steps reported before, and V the vector in hex. When the core takes its
-- request, with ready, it writes "accepted nmi" or "accepted irq". That
-- takes every request of the kind raised before, as they merge. When the
-- core then reports the interrupt entry, it writes "taken S nmi V" or
-- "taken S irq V", where S is the number of that step, counting from 0, as
-- the trace does. An IRQ that only the timer raised is not in the log.
-- test/irq_compare.py reads the log, for cores that take a request later
-- than the step it was raised for (MICROARCH.md §9).
--
-- The timer counts the steps, as the emulator's does: its tick is the
-- core's report of a step. Its request and the IRQ of p_intr reach the core
-- as one request, with the vector of p_intr's when both are raised, and the
-- core's ready takes both. That is how the emulator merges a request of the
-- timer with one from --irq.
--
-- The run ends when the trace writer has printed the end of the run. The
-- simulation then stops with the emulator's exit status.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use std.env.all;
   use std.textio.all;

   use work.trace_pkg.all;

entity tb_core is
   generic (
      G_CORE          : string   := "multicycle";
      G_BIN_FILE      : string;
      G_TRACE_FILE    : string;
      G_INPUT_FILE    : string   := "";
      G_TRACE         : boolean  := true;
      G_MAX_STEPS     : positive := 100_000_000;
      G_INTERRUPTS    : string   := "";
      G_INTR_LOG      : string   := "";
      G_CYCLE_COUNTER : boolean  := true;
      -- The memory's stall rate in percent, and its seed (sim/wb_mem.vhd).
      G_STALL         : natural  := 0;
      G_SEED          : positive := 1
   );
end entity tb_core;

architecture simulation of tb_core is

   -- A step takes far fewer cycles than this.
   constant C_STEP_TIMEOUT : natural := 1000;

   type t_request is record
      step   : natural;
      nmi    : boolean;
      vector : std_logic_vector(7 downto 0);
   end record t_request;

   type t_requests is array (natural range <>) of t_request;

   -- Parses the emulator's options "--irq STEP:VEC" and "--nmi STEP:VEC".
   -- Numbers are decimal, or hex after 0x.
   function parse(s : string) return t_requests is
      variable res_v    : t_requests(0 to 63);
      variable count_v  : natural  := 0;
      variable pos_v    : positive := s'low;
      variable number_v : natural;

      procedure skip_blanks is
      begin
         while pos_v <= s'high and s(pos_v) = ' ' loop
            pos_v := pos_v + 1;
         end loop;
      end procedure skip_blanks;

      procedure read_number(value : out natural) is
         variable base_v  : natural := 10;
         variable value_v : natural := 0;
         variable digit_v : natural;
         variable start_v : positive;
      begin
         if pos_v + 1 <= s'high and s(pos_v to pos_v + 1) = "0x" then
            base_v := 16;
            pos_v  := pos_v + 2;
         end if;
         start_v := pos_v;
         while pos_v <= s'high loop
            case s(pos_v) is
               when '0' to '9' => digit_v := character'pos(s(pos_v)) - character'pos('0');
               when 'a' to 'f' => digit_v := character'pos(s(pos_v)) - character'pos('a') + 10;
               when 'A' to 'F' => digit_v := character'pos(s(pos_v)) - character'pos('A') + 10;
               when others     => exit;
            end case;
            assert digit_v < base_v
               report "tb_core: bad number in G_INTERRUPTS"
               severity failure;
            value_v := value_v * base_v + digit_v;
            pos_v   := pos_v + 1;
         end loop;
         assert pos_v > start_v
            report "tb_core: missing number in G_INTERRUPTS"
            severity failure;
         value := value_v;
      end procedure read_number;

   begin
      skip_blanks;
      while pos_v <= s'high loop
         assert pos_v + 5 <= s'high and
                (s(pos_v to pos_v + 5) = "--nmi " or s(pos_v to pos_v + 5) = "--irq ")
            report "tb_core: G_INTERRUPTS wants --nmi STEP:VEC or --irq STEP:VEC"
            severity failure;
         res_v(count_v).nmi := s(pos_v to pos_v + 5) = "--nmi ";
         pos_v := pos_v + 6;
         skip_blanks;
         read_number(number_v);
         res_v(count_v).step := number_v;
         assert pos_v <= s'high and s(pos_v) = ':'
            report "tb_core: G_INTERRUPTS wants STEP:VEC"
            severity failure;
         pos_v := pos_v + 1;
         read_number(number_v);
         res_v(count_v).vector := to_slv(number_v, 8);
         count_v := count_v + 1;
         skip_blanks;
      end loop;
      return res_v(0 to count_v - 1);
   end function parse;

   constant C_REQUESTS : t_requests := parse(G_INTERRUPTS);

   signal clk : std_logic;
   signal rst : std_logic;

   signal ibus_cyc   : std_logic;
   signal ibus_stb   : std_logic;
   signal ibus_stall : std_logic;
   signal ibus_ack   : std_logic;
   signal ibus_addr  : std_logic_vector(30 downto 0);
   signal ibus_data  : std_logic_vector(63 downto 0);

   signal dbus_cyc      : std_logic;
   signal dbus_stb      : std_logic;
   signal dbus_stall    : std_logic;
   signal dbus_ack      : std_logic;
   signal dbus_we       : std_logic;
   signal dbus_addr     : std_logic_vector(31 downto 0);
   signal dbus_data_out : std_logic_vector(31 downto 0);
   signal dbus_data_in  : std_logic_vector(31 downto 0);

   -- The slaves of the data bus decoder, in the order of these indices
   constant C_MEM    : natural := 0;
   constant C_MPU    : natural := 1;
   constant C_PERF   : natural := 2;
   constant C_TIMER  : natural := 3;
   constant C_SLAVES : natural := 4;

   signal dbus_sel    : natural range 0 to C_SLAVES - 1;
   signal slave_stb   : std_logic_vector(C_SLAVES - 1 downto 0);
   signal slave_stall : std_logic_vector(C_SLAVES - 1 downto 0);
   signal slave_ack   : std_logic_vector(C_SLAVES - 1 downto 0);
   signal slave_data  : std_logic_vector(32 * C_SLAVES - 1 downto 0);

   signal timer_valid  : std_logic;
   signal timer_vector : std_logic_vector(7 downto 0);
   signal instret      : std_logic;

   signal nmi_valid  : std_logic                    := '0';
   signal nmi_ready  : std_logic;
   signal nmi_vector : std_logic_vector(7 downto 0) := X"00";
   signal irq_valid  : std_logic                    := '0';
   signal irq_ready  : std_logic;
   signal irq_vector : std_logic_vector(7 downto 0) := X"00";

   signal core_irq_valid  : std_logic;
   signal core_irq_vector : std_logic_vector(7 downto 0);

   signal console_valid : std_logic;
   signal console_data  : std_logic_vector(7 downto 0);

   signal retire : t_retire;
   signal done   : std_logic;
   signal status : natural;

begin

   p_clk : process
   begin
      clk <= '1', '0' after 5 ns;
      wait for 10 ns;
   end process p_clk;


   p_rst : process
   begin
      rst <= '1';
      wait for 100 ns;
      wait until rising_edge(clk);
      rst <= '0';
      wait;
   end process p_rst;


   gen_core : if G_CORE = "multicycle" generate

      i_multicycle : entity work.multicycle
         port map (
            clk_i        => clk,
            rst_i        => rst,
            ibus_cyc_o   => ibus_cyc,
            ibus_stb_o   => ibus_stb,
            ibus_stall_i => ibus_stall,
            ibus_ack_i   => ibus_ack,
            ibus_addr_o  => ibus_addr,
            ibus_data_i  => ibus_data,
            dbus_cyc_o   => dbus_cyc,
            dbus_stb_o   => dbus_stb,
            dbus_stall_i => dbus_stall,
            dbus_ack_i   => dbus_ack,
            dbus_we_o    => dbus_we,
            dbus_addr_o  => dbus_addr,
            dbus_data_o  => dbus_data_out,
            dbus_data_i  => dbus_data_in,
            nmi_valid_i  => nmi_valid,
            nmi_ready_o  => nmi_ready,
            nmi_vector_i => nmi_vector,
            irq_valid_i  => core_irq_valid,
            irq_ready_o  => irq_ready,
            irq_vector_i => core_irq_vector,
            halted_o     => open,
            instret_o    => instret,
            retire_o     => retire
         ); -- i_multicycle

   else generate

      -- A core without a branch above
      assert false
         report "tb_core: unknown core " & G_CORE
         severity failure;

   end generate gen_core;


   dbus_sel <= C_MPU when dbus_addr(31 downto 5) = X"FFFFFF" & "001" else
               C_PERF when dbus_addr(31 downto 4) = X"FFFFFF1" and
                           (G_CYCLE_COUNTER or dbus_addr(3 downto 1) /= "000") else
               C_TIMER when dbus_addr(31 downto 4) = X"FFFFFF4" else
               C_MEM;


   i_wb_dmux : entity work.wb_dmux
      generic map (
         G_SLAVES => C_SLAVES
      )
      port map (
         clk_i     => clk,
         rst_i     => rst,
         sel_i     => dbus_sel,
         m_cyc_i   => dbus_cyc,
         m_stb_i   => dbus_stb,
         m_stall_o => dbus_stall,
         m_ack_o   => dbus_ack,
         m_data_o  => dbus_data_in,
         s_stb_o   => slave_stb,
         s_stall_i => slave_stall,
         s_ack_i   => slave_ack,
         s_data_i  => slave_data
      ); -- i_wb_dmux


   core_irq_valid  <= irq_valid or timer_valid;
   core_irq_vector <= irq_vector when irq_valid = '1' else
                      timer_vector;


   i_wb_mem : entity work.wb_mem
      generic map (
         G_INIT_FILE  => G_BIN_FILE,
         G_INPUT_FILE => G_INPUT_FILE,
         G_STALL      => G_STALL,
         G_SEED       => G_SEED
      )
      port map (
         clk_i           => clk,
         rst_i           => rst,
         ibus_cyc_i      => ibus_cyc,
         ibus_stb_i      => ibus_stb,
         ibus_stall_o    => ibus_stall,
         ibus_ack_o      => ibus_ack,
         ibus_addr_i     => ibus_addr,
         ibus_data_o     => ibus_data,
         dbus_cyc_i      => dbus_cyc,
         dbus_stb_i      => slave_stb(C_MEM),
         dbus_stall_o    => slave_stall(C_MEM),
         dbus_ack_o      => slave_ack(C_MEM),
         dbus_we_i       => dbus_we,
         dbus_addr_i     => dbus_addr,
         dbus_data_i     => dbus_data_out,
         dbus_data_o     => slave_data(32 * C_MEM + 31 downto 32 * C_MEM),
         console_valid_o => console_valid,
         console_data_o  => console_data
      ); -- i_wb_mem


   i_mpu : entity work.mpu
      port map (
         clk_i      => clk,
         rst_i      => rst,
         wb_cyc_i   => dbus_cyc,
         wb_stb_i   => slave_stb(C_MPU),
         wb_stall_o => slave_stall(C_MPU),
         wb_ack_o   => slave_ack(C_MPU),
         wb_we_i    => dbus_we,
         wb_addr_i  => dbus_addr(4 downto 0),
         wb_data_i  => dbus_data_out,
         wb_data_o  => slave_data(32 * C_MPU + 31 downto 32 * C_MPU)
      ); -- i_mpu


   i_perf : entity work.perf
      port map (
         clk_i      => clk,
         rst_i      => rst,
         instret_i  => instret,
         wb_cyc_i   => dbus_cyc,
         wb_stb_i   => slave_stb(C_PERF),
         wb_stall_o => slave_stall(C_PERF),
         wb_ack_o   => slave_ack(C_PERF),
         wb_we_i    => dbus_we,
         wb_addr_i  => dbus_addr(3 downto 0),
         wb_data_i  => dbus_data_out,
         wb_data_o  => slave_data(32 * C_PERF + 31 downto 32 * C_PERF)
      ); -- i_perf


   i_timer : entity work.timer
      port map (
         clk_i        => clk,
         rst_i        => rst,
         tick_i       => retire.valid,
         wb_cyc_i     => dbus_cyc,
         wb_stb_i     => slave_stb(C_TIMER),
         wb_stall_o   => slave_stall(C_TIMER),
         wb_ack_o     => slave_ack(C_TIMER),
         wb_we_i      => dbus_we,
         wb_addr_i    => dbus_addr(3 downto 0),
         wb_data_i    => dbus_data_out,
         wb_data_o    => slave_data(32 * C_TIMER + 31 downto 32 * C_TIMER),
         irq_valid_o  => timer_valid,
         irq_ready_i  => irq_ready,
         irq_vector_o => timer_vector
      ); -- i_timer


   i_trace : entity work.trace
      generic map (
         G_FILE_NAME => G_TRACE_FILE,
         G_TRACE     => G_TRACE,
         G_MAX_STEPS => G_MAX_STEPS
      )
      port map (
         clk_i           => clk,
         rst_i           => rst,
         retire_i        => retire,
         console_valid_i => console_valid,
         console_data_i  => console_data,
         nmi_pending_i   => nmi_valid,
         nmi_vector_i    => nmi_vector,
         irq_pending_i   => core_irq_valid,
         irq_vector_i    => core_irq_vector,
         done_o          => done,
         status_o        => status
      ); -- i_trace


   -- The requests for step 0 are raised during reset, so that the core sees
   -- them before its first step.
   p_intr : process (clk)
      file     log_f      : text;
      variable log_open_v : boolean := false;
      variable steps_v    : natural := 0;
      -- One of p_intr's requests was taken, and its entry is not reported yet.
      variable nmi_taken_v : boolean := false;
      variable irq_taken_v : boolean := false;

      procedure log(text : string) is
         variable l : line;
      begin
         if G_INTR_LOG = "" then
            return;
         end if;
         if not log_open_v then
            file_open(log_f, G_INTR_LOG, write_mode);
            log_open_v := true;
         end if;
         write(l, text);
         writeline(log_f, l);
         flush(log_f);
      end procedure log;

      procedure log(what   : string;
                    step   : natural;
                    nmi    : boolean;
                    vector : std_logic_vector(7 downto 0)) is
      begin
         if nmi then
            log(what & " " & integer'image(step) & " nmi " & to_hstring(vector));
         else
            log(what & " " & integer'image(step) & " irq " & to_hstring(vector));
         end if;
      end procedure log;

   begin
      if rising_edge(clk) then
         if nmi_ready = '1' then
            if nmi_valid = '1' then
               log("accepted nmi");
               nmi_taken_v := true;
            end if;
            nmi_valid <= '0';
         end if;
         if irq_ready = '1' then
            if irq_valid = '1' then
               log("accepted irq");
               irq_taken_v := true;
            end if;
            irq_valid <= '0';
         end if;

         if rst = '0' and retire.valid = '1' then
            if retire.intr = '1' and retire.nmi = '1' and nmi_taken_v then
               log("taken", steps_v, true, retire.vector);
               nmi_taken_v := false;
            elsif retire.intr = '1' and retire.nmi = '0' and irq_taken_v then
               log("taken", steps_v, false, retire.vector);
               irq_taken_v := false;
            end if;
            steps_v := steps_v + 1;
         end if;

         for i in C_REQUESTS'range loop
            if C_REQUESTS(i).step = steps_v and (rst = '1' or retire.valid = '1') then
               log("raised", steps_v, C_REQUESTS(i).nmi, C_REQUESTS(i).vector);
               if C_REQUESTS(i).nmi then
                  nmi_valid  <= '1';
                  nmi_vector <= C_REQUESTS(i).vector;
               else
                  irq_valid  <= '1';
                  irq_vector <= C_REQUESTS(i).vector;
               end if;
            end if;
         end loop;
      end if;
   end process p_intr;


   p_finish : process
   begin
      wait until done = '1';
      stop(status);
   end process p_finish;


   p_watchdog : process
      variable idle_v : natural := 0;
   begin
      wait until rising_edge(clk);
      if rst = '1' or retire.valid = '1' then
         idle_v := 0;
      else
         idle_v := idle_v + 1;
         assert idle_v < C_STEP_TIMEOUT
            report "tb_core: no step for " & integer'image(C_STEP_TIMEOUT) & " cycles"
            severity failure;
      end if;
   end process p_watchdog;

end architecture simulation;
