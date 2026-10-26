-- Runs a program on a core, and writes its trace in the format of
-- "niceemu --trace", so that the two can be compared with diff.
--
-- THEORY OF OPERATION
-- G_CORE names the core: "pipeline" for src/pipeline.vhd, "multicycle" for
-- src/multicycle.vhd. Every core has the same ports, so the rest of the
-- testbench serves them all. Only
-- the pipelined core has stats_o, for the fetch statistics.
-- The core runs on the memory model, sim/wb_mem.vhd, which loads G_BIN_FILE.
-- Its console reads the bytes of G_INPUT_FILE, as the emulator's --input
-- does, or none if it is "".
-- The data bus decoder, src/wb_dmux.vhd, sends 0xFFFFFF10-0xFFFFFF1F to
-- the timer, src/timer.vhd (SYSTEM.md §4), 0xFFFFFF20-0xFFFFFF3F to the
-- math unit, src/mpu.vhd (SYSTEM.md §2), 0xFFFFFF40-0xFFFFFF4F to the
-- performance counters, src/perf.vhd (SYSTEM.md §3), 0xFFFFFF50-0xFFFFFF7F
-- to the fetch statistics, src/fetch_stats.vhd (MICROARCH.md §8.1), and
-- the rest to the memory model. It keeps the ACKs in order for a core with several
-- requests in flight (MICROARCH.md §8). It holds no address map: the
-- address compare that names the slave, dbus_sel, is here.
-- The trace writer, sim/trace.vhd, prints each step the core reports.
--
-- G_FETCH_STATS is the generic G_ENABLE of the fetch statistics. Only the
-- pipelined core reports the events they count; with the multi-cycle core
-- they count only cycles. With G_FETCH_STATS false, their 48 words at
-- 0xFFFFFF50 read 0 and ignore writes, as in the emulator (SYSTEM.md §3).
--
-- With G_CYCLE_COUNTER false, CYCLE_LO and CYCLE_HI at 0xFFFFFF40 and
-- 0xFFFFFF41, and TIME_LO and TIME_HI at 0xFFFFFF44 and 0xFFFFFF45, are
-- memory, as with the emulator's --no-cycle-counter. The core's cycle count
-- depends on the memory's stalls, so a program that reads it or the time
-- could not be compared with the emulator otherwise.
--
-- G_INTERRUPTS takes the emulator's interrupt options, for example
-- "--nmi 2:1 --irq 2:2", and the interrupt source p_intr raises the same
-- requests. A request for step S is raised once S steps have been reported,
-- that is, before step S, as in the emulator. A request of the same kind
-- that is raised while one is pending merges with it and leaves its vector,
-- as the emulator merges them (ISA.md §7.1). The multi-cycle core takes requests only
-- between steps, so its trace matches the emulator's exactly.
--
-- With G_INTR_DELAY = N, each request is raised N cycles later instead, so
-- that a sweep can make it arrive anywhere within an instruction. The core
-- may then take it a step later than the emulator, and only
-- test/irq_compare.py, which reads the log below, can judge the run. The
-- step it is logged for is then the one after the last reported, since
-- the core may have begun that one.
--
-- With G_INTR_LOG, p_intr writes a line to that file for each request it
-- raises, "raised S nmi V" or "raised S irq V", where S is the number of
-- steps reported before, and V the vector in hex. When the core takes its
-- request, with ready, it writes "accepted nmi" or "accepted irq". That
-- takes every request of the kind raised before, as they merge. When the
-- core then reports the interrupt entry, it writes "taken S nmi V" or
-- "taken S irq V", where S is the number of that step, counting from 0, as
-- the trace does. The timer's requests are in the log too, as IRQs: each
-- one that it raises while none of its own waits, with S the number of
-- ticks before, which is the step the emulator's timer raises it for, and
-- V the vector the core will take with it. test/irq_compare.py then runs
-- the emulator with --no-timer-irq, so that its timer raises none itself.
-- test/irq_compare.py reads the log, for cores that take a request later
-- than the step it was raised for (MICROARCH.md §9).
--
-- With G_RETIRE_LOG, p_retire_log writes a line to that file for each
-- step the core reports: the cycle it is reported in, counting from the
-- first cycle after reset, and the address of the instruction in hex, or
-- "intr" for an interrupt entry. bench/pipecycles.py --retires compares
-- the cycles with its model's, step by step.
--
-- The timer counts the steps, as the emulator's does: its tick is the
-- core's instret_o, and the report of each interrupt entry. A data read of
-- TIMER_COUNT must see the ticks of every older instruction, and the
-- pipelined core raises instret_o in time for that, but may report a step
-- later (src/pipeline.vhd). Its request and the IRQ of p_intr reach the core
-- as one request, with the vector of the one raised first (p_intr's, when
-- both are raised in the same cycle), and the core's ready takes both.
-- That is how the emulator merges a request of the timer with one from
-- --irq.
--
-- With G_PAUSE = P, p_pause raises pause_i (MICROARCH.md §6.1) in a random
-- P percent of the cycles, from G_SEED, so that the core pauses and goes
-- on at random boundaries, and often runs a single step. With
-- G_PAUSE_HOLD = H > 0 as well, a pause starts in a random P percent of
-- the cycles, and pause_i stays '1' until the core has paused, and then
-- for a random 0 to H - 1 cycles more. So interrupt requests come during a
-- real pause, and are taken when the core goes on. A pause must not change
-- what the core does, so the trace stays that of the emulator. The core's
-- cycle count does change, so such a run needs G_CYCLE_COUNTER false or a
-- program that does not read it.
--
-- With G_SINGLE_STEP, p_pause holds pause_i at '1' through reset and after,
-- and lowers it for one cycle each time the core has paused, so that the
-- core runs one step at a time. Each such pulse must run exactly one step,
-- and the trace must still be the emulator's. With G_PATCH_STEP = S too,
-- p_pause writes the word G_PATCH_DATA, in hex, to G_PATCH_ADDR through the
-- data bus while the core is paused after S steps, as a debugger would.
-- The core holds the buses idle then, and does not see the write's ACK.
-- That changes the program, so such a run is compared with a hand-checked
-- trace, not with the emulator's.
--
-- G_BREAK_AT lists the addresses of breakpoints, in hex, between blanks,
-- at most 8 (doc/DEBUG.md §6). The core gets them all enabled, and
-- G_BREAKS = their number. When the core stops at one, with paused_o
-- '1' while pause_i is '0', p_pause raises pause_i for a cycle and then
-- lowers it, so the core goes on, as the debug link does after an `x`.
-- With G_BREAK_LOG, it writes a line to that file at each such stop:
-- "stop" and R0-R15 in hex, as test/break_stops.py writes them for the
-- emulator. A stop is not a step, so the trace stays the emulator's. With
-- G_PAUSE or G_SINGLE_STEP, the pauses that those raise go on from the
-- stops too, and a pause at a breakpoint is not logged.
--
-- p_stopped checks that the core is quiet while paused_o or halted_o is
-- '1', that its registers do not change while it is paused, and that
-- halt_reason_o is the reason of the step that halted it, and HALT_NONE
-- before.
--
-- The run ends when the trace writer has printed the end of the run. The
-- simulation goes on for a few cycles, so that the core's own checks see
-- it halted, and then stops with the emulator's exit status.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;
   use ieee.math_real.floor;
   use ieee.math_real.uniform;

   use std.env.all;
   use std.textio.all;

   use work.pipe_pkg.all;
   use work.trace_pkg.all;

entity tb_core is
   generic (
      G_CORE          : string   := "pipeline";
      G_BIN_FILE      : string;
      G_TRACE_FILE    : string;
      G_INPUT_FILE    : string   := "";
      G_TRACE         : boolean  := true;
      G_MAX_STEPS     : positive := 100_000_000;
      G_INTERRUPTS    : string   := "";
      G_INTR_LOG      : string   := "";
      G_RETIRE_LOG    : string   := "";
      -- Each request is raised this many cycles after its step allows.
      G_INTR_DELAY    : natural  := 0;
      G_CYCLE_COUNTER : boolean  := true;
      G_FETCH_STATS   : boolean  := true;
      -- The memory's stall rate in percent, and its seed (sim/wb_mem.vhd).
      G_STALL         : natural  := 0;
      G_SEED          : positive := 1;
      -- The pauses, and a write to memory while paused (above)
      G_PAUSE         : natural  := 0;
      G_PAUSE_HOLD    : natural  := 0;
      G_SINGLE_STEP   : boolean  := false;
      G_PATCH_STEP    : integer  := -1;
      G_PATCH_ADDR    : natural  := 0;
      G_PATCH_DATA    : string   := "00000000";
      -- The breakpoints, and the log of the stops at them (above)
      G_BREAK_AT      : string   := "";
      G_BREAK_LOG     : string   := ""
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
      variable res_v    : t_requests(0 to 1023);
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
         assert count_v <= res_v'high
            report "tb_core: more than 1024 requests in G_INTERRUPTS"
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

   -- A word in hex, for G_PATCH_DATA
   function hex_word(s : string) return std_logic_vector is
      variable res_v   : std_logic_vector(31 downto 0) := (others => '0');
      variable digit_v : natural;
   begin
      for i in s'range loop
         case s(i) is
            when '0' to '9' => digit_v := character'pos(s(i)) - character'pos('0');
            when 'a' to 'f' => digit_v := character'pos(s(i)) - character'pos('a') + 10;
            when 'A' to 'F' => digit_v := character'pos(s(i)) - character'pos('A') + 10;
            when others     =>
               assert false
                  report "tb_core: bad hex digit in " & s
                  severity failure;
         end case;
         res_v := res_v(27 downto 0) & to_slv(digit_v, 4);
      end loop;
      return res_v;
   end function hex_word;

   type t_breaks is record
      count : natural range 0 to C_BREAKS_MAX;
      addrs : t_brk_addrs;
   end record t_breaks;

   -- The addresses of G_BREAK_AT, and their number
   function parse_breaks(s : string) return t_breaks is
      variable res_v   : t_breaks := (count => 0, addrs => (others => (others => '0')));
      variable pos_v   : positive := s'low;
      variable start_v : positive;
   begin
      while pos_v <= s'high loop
         if s(pos_v) = ' ' then
            pos_v := pos_v + 1;
         else
            start_v := pos_v;
            while pos_v <= s'high and s(pos_v) /= ' ' loop
               pos_v := pos_v + 1;
            end loop;
            assert res_v.count < C_BREAKS_MAX
               report "tb_core: more than 8 breakpoints in G_BREAK_AT"
               severity failure;
            res_v.addrs(res_v.count) := hex_word(s(start_v to pos_v - 1));
            res_v.count              := res_v.count + 1;
         end if;
      end loop;
      return res_v;
   end function parse_breaks;

   constant C_BREAKS : t_breaks := parse_breaks(G_BREAK_AT);

   signal clk : std_logic;
   signal rst : std_logic;

   signal ibus_cyc   : std_logic;
   signal ibus_stb   : std_logic;
   signal ibus_stall : std_logic;
   signal ibus_ack   : std_logic;
   signal ibus_addr  : std_logic_vector(30 downto 0);
   signal ibus_data  : std_logic_vector(63 downto 0);

   -- The core's side of the data bus, and p_pause's write while paused,
   -- which takes the bus while patch_cyc is '1'
   signal core_cyc      : std_logic;
   signal core_stb      : std_logic;
   signal core_stall    : std_logic;
   signal core_ack      : std_logic;
   signal core_we       : std_logic;
   signal core_addr     : std_logic_vector(31 downto 0);
   signal core_data_out : std_logic_vector(31 downto 0);
   signal patch_cyc     : std_logic := '0';
   signal patch_stb     : std_logic := '0';

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
   constant C_STATS  : natural := 4;
   constant C_SLAVES : natural := 5;

   signal dbus_sel    : natural range 0 to C_SLAVES - 1;
   signal slave_stb   : std_logic_vector(C_SLAVES - 1 downto 0);
   signal slave_stall : std_logic_vector(C_SLAVES - 1 downto 0);
   signal slave_ack   : std_logic_vector(C_SLAVES - 1 downto 0);
   signal slave_data  : std_logic_vector(32 * C_SLAVES - 1 downto 0);

   signal timer_valid  : std_logic;
   signal timer_vector : std_logic_vector(7 downto 0);
   signal instret      : std_logic;
   signal fetch_events : t_fetch_events := C_FETCH_EVENTS_NONE;

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

   signal pause       : std_logic := '0';
   signal paused      : std_logic;
   signal halted      : std_logic;
   signal halt_reason : t_halt;
   signal retire      : t_retire;
   signal regs        : t_regs;
   signal tick        : std_logic;
   signal done        : std_logic;
   signal status      : natural;

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
         generic map (
            G_BREAKS => C_BREAKS.count
         )
         port map (
            clk_i         => clk,
            rst_i         => rst,
            ibus_cyc_o    => ibus_cyc,
            ibus_stb_o    => ibus_stb,
            ibus_stall_i  => ibus_stall,
            ibus_ack_i    => ibus_ack,
            ibus_addr_o   => ibus_addr,
            ibus_data_i   => ibus_data,
            dbus_cyc_o    => core_cyc,
            dbus_stb_o    => core_stb,
            dbus_stall_i  => core_stall,
            dbus_ack_i    => core_ack,
            dbus_we_o     => core_we,
            dbus_addr_o   => core_addr,
            dbus_data_o   => core_data_out,
            dbus_data_i   => dbus_data_in,
            nmi_valid_i   => nmi_valid,
            nmi_ready_o   => nmi_ready,
            nmi_vector_i  => nmi_vector,
            irq_valid_i   => core_irq_valid,
            irq_ready_o   => irq_ready,
            irq_vector_i  => core_irq_vector,
            pause_i       => pause,
            paused_o      => paused,
            brk_addr_i    => C_BREAKS.addrs,
            brk_en_i      => (others => '1'),
            halted_o      => halted,
            halt_reason_o => halt_reason,
            instret_o     => instret,
            regs_o        => regs,
            retire_o      => retire
         ); -- i_multicycle

   elsif G_CORE = "pipeline" generate

      i_pipeline : entity work.pipeline
         generic map (
            G_BREAKS => C_BREAKS.count
         )
         port map (
            clk_i         => clk,
            rst_i         => rst,
            ibus_cyc_o    => ibus_cyc,
            ibus_stb_o    => ibus_stb,
            ibus_stall_i  => ibus_stall,
            ibus_ack_i    => ibus_ack,
            ibus_addr_o   => ibus_addr,
            ibus_data_i   => ibus_data,
            dbus_cyc_o    => core_cyc,
            dbus_stb_o    => core_stb,
            dbus_stall_i  => core_stall,
            dbus_ack_i    => core_ack,
            dbus_we_o     => core_we,
            dbus_addr_o   => core_addr,
            dbus_data_o   => core_data_out,
            dbus_data_i   => dbus_data_in,
            nmi_valid_i   => nmi_valid,
            nmi_ready_o   => nmi_ready,
            nmi_vector_i  => nmi_vector,
            irq_valid_i   => core_irq_valid,
            irq_ready_o   => irq_ready,
            irq_vector_i  => core_irq_vector,
            pause_i       => pause,
            paused_o      => paused,
            brk_addr_i    => C_BREAKS.addrs,
            brk_en_i      => (others => '1'),
            halted_o      => halted,
            halt_reason_o => halt_reason,
            instret_o     => instret,
            regs_o        => regs,
            retire_o      => retire,
            stats_o       => fetch_events
         ); -- i_pipeline

   else generate

      -- A core without a branch above
      assert false
         report "tb_core: unknown core " & G_CORE
         severity failure;

   end generate gen_core;


   dbus_cyc      <= patch_cyc or core_cyc;
   dbus_stb      <= patch_stb when patch_cyc = '1' else core_stb;
   dbus_we       <= '1' when patch_cyc = '1' else core_we;
   dbus_addr     <= to_slv(G_PATCH_ADDR, 32) when patch_cyc = '1' else core_addr;
   dbus_data_out <= hex_word(G_PATCH_DATA) when patch_cyc = '1' else core_data_out;
   core_stall    <= dbus_stall or patch_cyc;
   core_ack      <= dbus_ack and not patch_cyc;


   dbus_sel <= C_MPU when dbus_addr(31 downto 5) = X"FFFFFF" & "001" else
               C_PERF when dbus_addr(31 downto 4) = X"FFFFFF4" and
                           (G_CYCLE_COUNTER or (dbus_addr(3 downto 1) /= "000" and
                                                dbus_addr(3 downto 1) /= "010")) else
               C_TIMER when dbus_addr(31 downto 4) = X"FFFFFF1" else
               C_STATS when dbus_addr(31 downto 6) = X"FFFFFF" & "01" and
                            dbus_addr(5 downto 4) /= "00" else
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


   tick <= instret or (retire.valid and retire.intr);

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
         tick_i       => tick,
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


   i_fetch_stats : entity work.fetch_stats
      generic map (
         G_ENABLE => G_FETCH_STATS
      )
      port map (
         clk_i      => clk,
         rst_i      => rst,
         events_i   => fetch_events,
         wb_cyc_i   => dbus_cyc,
         wb_stb_i   => slave_stb(C_STATS),
         wb_stall_o => slave_stall(C_STATS),
         wb_ack_o   => slave_ack(C_STATS),
         wb_we_i    => dbus_we,
         wb_addr_i  => dbus_addr(5 downto 0),
         wb_data_i  => dbus_data_out,
         wb_data_o  => slave_data(32 * C_STATS + 31 downto 32 * C_STATS)
      ); -- i_fetch_stats


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
      -- The cycles until each request is raised, or -1
      type     t_waits is array (C_REQUESTS'range) of integer;
      variable wait_v : t_waits := (others => -1);
      -- A request of this kind was raised in this cycle already
      variable nmi_set_v : boolean;
      variable irq_set_v : boolean;
      -- The timer's ticks, and whether its last request still waits
      variable ticks_v       : natural := 0;
      variable timer_waits_v : boolean := false;

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
         -- A new request of the timer. It merges with one of p_intr that
         -- waits, and the core then takes that one's vector, since that
         -- one was raised first.
         if timer_valid = '1' and not timer_waits_v then
            if irq_valid = '1' then
               log("raised", ticks_v, false, irq_vector);
            else
               log("raised", ticks_v, false, timer_vector);
            end if;
         end if;
         timer_waits_v := timer_valid = '1' and irq_ready = '0';
         if tick = '1' then
            ticks_v := ticks_v + 1;
         end if;

         if irq_ready = '1' then
            if irq_valid = '1' or timer_valid = '1' then
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

         nmi_set_v := false;
         irq_set_v := false;
         for i in C_REQUESTS'range loop
            if wait_v(i) > 0 then
               wait_v(i) := wait_v(i) - 1;
            end if;
            if C_REQUESTS(i).step = steps_v and (rst = '1' or retire.valid = '1') then
               wait_v(i) := G_INTR_DELAY;
            end if;
            -- No request after the end of the run, which the trace has
            -- printed already.
            if wait_v(i) = 0 and done = '0' then
               wait_v(i) := -1;
               -- A request that comes late may find step steps_v begun, so
               -- it is raised for the step after.
               if G_INTR_DELAY = 0 then
                  log("raised", steps_v, C_REQUESTS(i).nmi, C_REQUESTS(i).vector);
               else
                  log("raised", steps_v + 1, C_REQUESTS(i).nmi, C_REQUESTS(i).vector);
               end if;
               -- A request that finds one of its kind pending merges with it
               -- and leaves its vector. The timer's request is one of the
               -- IRQs.
               if C_REQUESTS(i).nmi then
                  if not nmi_set_v and (nmi_valid = '0' or nmi_ready = '1') then
                     nmi_valid  <= '1';
                     nmi_vector <= C_REQUESTS(i).vector;
                  end if;
                  nmi_set_v := true;
               else
                  if not irq_set_v and (irq_valid = '0' or irq_ready = '1') and
                     (timer_valid = '0' or irq_ready = '1') then
                     irq_valid  <= '1';
                     irq_vector <= C_REQUESTS(i).vector;
                  end if;
                  irq_set_v := true;
               end if;
            end if;
         end loop;
      end if;
   end process p_intr;


   p_pause : process (clk)
      variable seed1_v   : positive := G_SEED;
      variable seed2_v   : positive := 7;
      variable r_v       : real;
      variable steps_v   : natural  := 0;       -- The steps reported
      variable since_v   : natural  := 0;       -- The steps since the last pulse
      variable pulse_v   : boolean  := false;
      variable hold_v    : natural  := 0;
      variable patched_v : boolean  := false;
      variable going_v   : boolean  := false;   -- Going on from a stop
      file     log_f     : text;
      variable log_v     : boolean  := false;   -- log_f is open
      variable l         : line;
   begin
      if rising_edge(clk) then
         if retire.valid = '1' then
            steps_v := steps_v + 1;
            since_v := since_v + 1;
         end if;

         -- The write to memory: one request, then its ACK
         if dbus_stall = '0' then
            patch_stb <= '0';
         end if;
         if dbus_ack = '1' then
            patch_cyc <= '0';
         end if;

         if G_SINGLE_STEP then
            pause <= '1';
            if paused = '1' and pause = '1' and patch_cyc = '0' then
               assert not pulse_v or since_v = 1
                  report "tb_core: a pulse of pause_i ran " & integer'image(since_v) & " steps"
                  severity failure;
               if steps_v = G_PATCH_STEP and not patched_v then
                  patch_cyc <= '1';
                  patch_stb <= '1';
                  patched_v := true;
               else
                  pause   <= '0';
                  pulse_v := true;
                  since_v := 0;
               end if;
            end if;
         elsif G_PAUSE > 0 then
            uniform(seed1_v, seed2_v, r_v);
            if G_PAUSE_HOLD = 0 then
               pause <= '1' when r_v * 100.0 < real(G_PAUSE) else '0';
            elsif pause = '0' then
               if r_v * 100.0 < real(G_PAUSE) then
                  pause  <= '1';
                  uniform(seed1_v, seed2_v, r_v);
                  hold_v := natural(floor(r_v * real(G_PAUSE_HOLD)));
               end if;
            elsif paused = '1' then
               if hold_v = 0 then
                  pause <= '0';
               else
                  hold_v := hold_v - 1;
               end if;
            end if;
         elsif C_BREAKS.count > 0 then
            -- A stop at a breakpoint: pause_i '1' for a cycle, and then '0'
            -- until the core has gone on
            if pause = '1' then
               pause   <= '0';
               going_v := true;
            elsif paused = '0' then
               going_v := false;
            elsif not going_v then
               pause <= '1';
               if G_BREAK_LOG /= "" then
                  if not log_v then
                     file_open(log_f, G_BREAK_LOG, write_mode);
                     log_v := true;
                  end if;
                  write(l, string'("stop"));
                  for i in regs'range loop
                     write(l, " " & to_hstring(regs(i)));
                  end loop;
                  writeline(log_f, l);
                  flush(log_f);
               end if;
            end if;
         end if;
      end if;
   end process p_pause;


   p_stopped : process (clk)
      variable halt_v   : t_halt    := HALT_NONE;   -- The reason of the last step reported
      variable paused_v : std_logic := '0';         -- paused_o a cycle ago
      variable regs_v   : t_regs;
   begin
      if rising_edge(clk) then
         if rst = '0' then
            assert not ((paused = '1' or halted = '1') and
                        (ibus_cyc = '1' or ibus_stb = '1' or core_cyc = '1' or core_stb = '1'))
               report "tb_core: a bus cycle while the core is paused or halted"
               severity failure;
            assert not (paused = '1' and halted = '1')
               report "tb_core: paused_o and halted_o at once"
               severity failure;
            assert not (paused = '1' and paused_v = '1' and regs /= regs_v)
               report "tb_core: the registers changed while the core was paused"
               severity failure;
            assert (halted = '1' and halt_reason = halt_v) or (halted = '0' and halt_reason = HALT_NONE)
               report "tb_core: halt_reason_o is " & t_halt'image(halt_reason)
               severity failure;
         end if;
         if retire.valid = '1' then
            halt_v := retire.halt;
         end if;
         if rst = '1' then
            halt_v := HALT_NONE;
         end if;
         paused_v := paused;
         regs_v   := regs;
      end if;
   end process p_stopped;


   -- regs_o holds the registers of a step from the cycle after its report.
   p_regs : process (clk)
      variable retire_v : t_retire := C_RETIRE_NONE;
   begin
      if rising_edge(clk) then
         assert retire_v.valid = '0' or regs = retire_v.regs
            report "tb_core: regs_o is not the registers of the step reported before"
            severity failure;
         retire_v := retire;
         if rst = '1' then
            retire_v.valid := '0';
         end if;
      end if;
   end process p_regs;


   p_retire_log : process (clk)
      file     log_f      : text;
      variable log_open_v : boolean := false;
      variable cycle_v    : natural := 0;
      variable l          : line;
   begin
      if rising_edge(clk) and rst = '0' and G_RETIRE_LOG /= "" then
         if retire.valid = '1' then
            if not log_open_v then
               file_open(log_f, G_RETIRE_LOG, write_mode);
               log_open_v := true;
            end if;
            write(l, integer'image(cycle_v) & " ");
            if retire.intr = '1' then
               write(l, string'("intr"));
            else
               write(l, to_hstring(retire.addr));
            end if;
            writeline(log_f, l);
            if retire.halt /= HALT_NONE then
               flush(log_f);
            end if;
         end if;
         cycle_v := cycle_v + 1;
      end if;
   end process p_retire_log;


   p_finish : process
   begin
      wait until done = '1';
      for i in 1 to 4 loop
         wait until rising_edge(clk);
      end loop;
      stop(status);
   end process p_finish;


   p_watchdog : process
      variable idle_v : natural := 0;
   begin
      wait until rising_edge(clk);
      if rst = '1' or retire.valid = '1' or paused = '1' then
         idle_v := 0;
      else
         idle_v := idle_v + 1;
         assert idle_v < C_STEP_TIMEOUT
            report "tb_core: no step for " & integer'image(C_STEP_TIMEOUT) & " cycles"
            severity failure;
      end if;
   end process p_watchdog;

end architecture simulation;
