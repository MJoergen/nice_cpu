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
-- The data bus decoder, src/wb_dmux.vhd, sends 0xFFFFFF20-0xFFFFFF3F to
-- the math unit, src/mpu.vhd (DEVICES.md §2), 0xFFFFFF40-0xFFFFFF5F to the
-- performance counters, src/perf.vhd (DEVICES.md §3), but for
-- 0xFFFFFF46-0xFFFFFF49, the clock of the time of day, src/tod.vhd
-- (DEVICES.md §10), 0xFFFFFF60-0xFFFFFF7F
-- to the fetch statistics, src/fetch_stats.vhd (MICROARCH.md §8.1),
-- 0xFFFFFF88-0xFFFFFF8F to the FPU, src/fpu.vhd (DEVICES.md §11),
-- 0xFFFFFFA0-0xFFFFFFAF to the SD card controller, src/sd_regs.vhd
-- (DEVICES.md §5), 0xFFFFFFB0-0xFFFFFFBF to the network station,
-- src/net_regs.vhd (DEVICES.md §6), 0xFFFFFFC0-0xFFFFFFCF to the port for
-- Ethernet frames, src/eth_regs.vhd (DEVICES.md §7), and the rest to the
-- memory model. The station has no link over TCP, so its counts and status
-- read 0, as in the emulator without --link. The port's station is
-- sim/eth_sim.vhd, with the frames of G_ETH_IN_FILE, and the frames sent
-- written to G_ETH_OUT_FILE, as the emulator's --eth-in and --eth-out, or
-- none for "". The port holds the ACK of the writes that give frames, so
-- the core reads the queue as in the emulator. The controller's
-- engine is sim/sd_sim.vhd, with the images G_SD0_FILE and G_SD1_FILE, as
-- the emulator's --sd0 and --sd1, or none for "". It holds the ACK of a
-- command until the command ends, so the core never sees busy. It keeps the ACKs in order for a core with several
-- requests in flight (MICROARCH.md §8). It holds no address map: the
-- address compare that names the slave, dbus_sel, is here.
-- The trace writer, sim/trace.vhd, prints each step the core reports.
--
-- When the pipelined core halts, the testbench prints to the standard
-- output the cycles from reset, and the cycles in which a data read
-- waited only for its condition (S) or for an older micro-operation (W)
-- (src/pipe_prepare.vhd). It charges them to the micro-operation in
-- PREPARE, and when that goes on to WRITE, or is dropped by a flush, to
-- one of two sums: "Read waits: C cycles; went on: S for
-- the condition, W for an older micro-operation; dropped: S, W". Only the
-- waits of those that went on could be saved by reading early.
--
-- G_FETCH_STATS is the generic G_ENABLE of the fetch statistics. Only the
-- pipelined core reports the events they count; with the multi-cycle core
-- every cycle counts as OTHER. With G_FETCH_STATS false, their 32 words at
-- 0xFFFFFF60 read 0 and ignore writes, as in the emulator (DEVICES.md §3).
--
-- With G_FPU false, the FPU's eight words are memory, as with the
-- emulator's --no-fpu.
--
-- With G_CYCLE_COUNTER false, CYCLE_LO and CYCLE_HI at 0xFFFFFF40 and
-- 0xFFFFFF41, TIME_LO and TIME_HI at 0xFFFFFF44 and 0xFFFFFF45, and the
-- clock of the time of day at 0xFFFFFF46-0xFFFFFF49 are memory, as with
-- the emulator's --no-cycle-counter. The core's cycle count
-- depends on the memory's stalls, so a program that reads it or the time
-- could not be compared with the emulator otherwise.
--
-- With G_RETIRE_LOG, p_retire_log writes a line to that file for each
-- step the core reports: the cycle it is reported in, counting from the
-- first cycle after reset, and the address of the instruction in hex. A
-- third field gives the cycles since the line before, one letter each,
-- from the core's stats_o: the cause of the cycle (MICROARCH.md §8.1), "a"
-- for cause 0 to "n" for cause 13, and after it an upper-case letter, "A"
-- for cause 0 to "D" for cause 3, when the cycle flushes. stats_o reports
-- a cycle two cycles late, so the letters of a line lag its cycles by two.
-- The multi-cycle core reports cause 13, OTHER, in every cycle.
-- bench/pipecycles.py --retires compares the cycles with its model's, step
-- by step, and --causes sums the causes of each phase of the benchmark.
--
-- With G_PAUSE = P, p_pause raises pause_i (MICROARCH.md §6.1) in a random
-- P percent of the cycles, from G_SEED, so that the core pauses and goes
-- on at random boundaries, and often runs a single step. With
-- G_PAUSE_HOLD = H > 0 as well, a pause starts in a random P percent of
-- the cycles, and pause_i stays '1' until the core has paused, and then
-- for a random 0 to H - 1 cycles more. A pause must not change
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
-- G_WATCH_AT lists watchpoints, at most 4, each an address in hex and the
-- kinds it watches, r, w, or rw, such as "1Fw 20rw" (doc/DEBUG.md §6). The
-- core gets them all enabled, and G_WATCHES = their number. The core
-- stops after a step that hits one as at a breakpoint, and p_pause goes on
-- from it the same way. The log line of a stop after a hit adds "w", the
-- lowest number that hit, and the address of the hit, as
-- test/break_stops.py writes them for a `w`.
--
-- p_stopped checks that the core is quiet while paused_o or halted_o is
-- '1', that its registers do not change while it is paused, and that
-- halt_reason_o is the reason of the step that halted it, and HALT_NONE
-- before.
--
-- p_counters checks that the cycle counter counts the cycles in which neither
-- paused_o nor halted_o is '1', which is how a system drives run_i of the
-- counters (MICROARCH.md §8).
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
      G_SD0_FILE      : string   := "";
      G_SD1_FILE      : string   := "";
      G_ETH_IN_FILE   : string   := "";
      G_ETH_OUT_FILE  : string   := "";
      G_TRACE         : boolean  := true;
      G_MAX_STEPS     : positive := 100_000_000;
      G_RETIRE_LOG    : string   := "";
      G_CYCLE_COUNTER : boolean  := true;
      G_FETCH_STATS   : boolean  := true;
      G_FPU           : boolean  := true;
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
      G_BREAK_LOG     : string   := "";
      -- The watchpoints (above)
      G_WATCH_AT      : string   := ""
   );
end entity tb_core;

architecture simulation of tb_core is

   -- A step takes far fewer cycles than this, even one that waits for the
   -- FPU, whose longest command, DIGITS, takes some 3200 cycles.
   constant C_STEP_TIMEOUT : natural := 10000;

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

   type t_watches is record
      count : natural range 0 to C_WATCHES_MAX;
      addrs : t_wch_addrs;
      en    : std_logic_vector(2 * C_WATCHES_MAX - 1 downto 0);
   end record t_watches;

   -- The addresses and the kinds of G_WATCH_AT, and their number
   function parse_watches(s : string) return t_watches is
      variable res_v   : t_watches := (count => 0, addrs => (others => (others => '0')),
                                       en => (others => '0'));
      variable pos_v   : positive  := s'low;
      variable start_v : positive;
      variable end_v   : positive;
   begin
      while pos_v <= s'high loop
         if s(pos_v) = ' ' then
            pos_v := pos_v + 1;
         else
            start_v := pos_v;
            while pos_v <= s'high and s(pos_v) /= ' ' and s(pos_v) /= 'r' and s(pos_v) /= 'w' loop
               pos_v := pos_v + 1;
            end loop;
            end_v := pos_v;
            assert res_v.count < C_WATCHES_MAX
               report "tb_core: more than 4 watchpoints in G_WATCH_AT"
               severity failure;
            res_v.addrs(res_v.count) := hex_word(s(start_v to end_v - 1));
            while pos_v <= s'high and s(pos_v) /= ' ' loop
               if s(pos_v) = 'r' then
                  res_v.en(2 * res_v.count) := '1';
               elsif s(pos_v) = 'w' then
                  res_v.en(2 * res_v.count + 1) := '1';
               end if;
               pos_v := pos_v + 1;
            end loop;
            assert pos_v > end_v
               report "tb_core: a watchpoint without r or w in G_WATCH_AT"
               severity failure;
            res_v.count := res_v.count + 1;
         end if;
      end loop;
      return res_v;
   end function parse_watches;

   constant C_WATCHES : t_watches := parse_watches(G_WATCH_AT);

   signal wch_hit : std_logic_vector(C_WATCHES_MAX - 1 downto 0);
   signal wch_pc  : std_logic_vector(31 downto 0);

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
   constant C_STATS  : natural := 3;
   constant C_SD     : natural := 4;
   constant C_NET    : natural := 5;
   constant C_ETH    : natural := 6;
   constant C_TOD    : natural := 7;
   constant C_FPU    : natural := 8;
   constant C_SLAVES : natural := 9;

   signal dbus_sel    : natural range 0 to C_SLAVES - 1;
   signal slave_stb   : std_logic_vector(C_SLAVES - 1 downto 0);
   signal slave_stall : std_logic_vector(C_SLAVES - 1 downto 0);
   signal slave_ack   : std_logic_vector(C_SLAVES - 1 downto 0);
   signal slave_data  : std_logic_vector(32 * C_SLAVES - 1 downto 0);

   signal instret      : std_logic;
   signal fetch_events : t_fetch_events := C_FETCH_EVENTS_NONE;

   -- The network station's addresses, and the port for Ethernet frames
   -- with its station
   signal net_ip          : std_logic_vector(31 downto 0);
   signal net_mac         : std_logic_vector(47 downto 0);
   signal eth_enable      : std_logic;
   signal eth_enable_done : std_logic;
   signal eth_rx_start    : std_logic;
   signal eth_rx_we       : std_logic;
   signal eth_rx_addr     : std_logic_vector(8 downto 0);
   signal eth_rx_data     : std_logic_vector(31 downto 0);
   signal eth_rx_done     : std_logic;
   signal eth_rx_len      : std_logic_vector(10 downto 0);
   signal eth_tx_start    : std_logic;
   signal eth_tx_len      : std_logic_vector(10 downto 0);
   signal eth_tx_addr     : std_logic_vector(8 downto 0);
   signal eth_tx_data     : std_logic_vector(31 downto 0);
   signal eth_tx_done     : std_logic;

   -- The SD card controller and its engine
   signal sd_present   : std_logic_vector(1 downto 0);
   signal sd_wp        : std_logic_vector(1 downto 0);
   signal sd_start     : std_logic;
   signal sd_abort     : std_logic;
   signal sd_cmd       : std_logic_vector(1 downto 0);
   signal sd_slot      : std_logic_vector(3 downto 0);
   signal sd_lba       : std_logic_vector(31 downto 0);
   signal sd_done      : std_logic;
   signal sd_error     : std_logic_vector(3 downto 0);
   signal sd_last      : std_logic_vector(31 downto 0);
   signal sd_type      : std_logic_vector(1 downto 0);
   signal sd_buf_addr  : std_logic_vector(8 downto 0);
   signal sd_buf_we    : std_logic;
   signal sd_buf_wdata : std_logic_vector(7 downto 0);
   signal sd_buf_rdata : std_logic_vector(7 downto 0);

   signal console_valid : std_logic;
   signal console_data  : std_logic_vector(7 downto 0);

   signal pause       : std_logic := '0';
   signal paused      : std_logic;
   signal halted      : std_logic;
   signal run         : std_logic;   -- The core is running, for the counters
   signal halt_reason : t_halt;
   signal retire      : t_retire;
   signal regs        : t_regs;
   signal early       : natural;     -- Instructions counted, not yet reported
   signal done        : std_logic;
   signal status      : natural;

   -- The cycles from reset, and the waits of PREPARE among them: of the
   -- micro-operation in PREPARE, of those that went on, and of those
   -- dropped, each for the condition (0) and for an older one (1)
   type t_rwaits is array (0 to 1) of natural;

   signal n_cycles : natural := 0;
   signal n_held   : t_rwaits := (0, 0);
   signal n_went   : t_rwaits := (0, 0);
   signal n_drop   : t_rwaits := (0, 0);

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
            G_BREAKS  => C_BREAKS.count,
            G_WATCHES => C_WATCHES.count
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
            pause_i       => pause,
            paused_o      => paused,
            brk_addr_i    => C_BREAKS.addrs,
            brk_en_i      => (others => '1'),
            wch_addr_i    => C_WATCHES.addrs,
            wch_en_i      => C_WATCHES.en,
            wch_hit_o     => wch_hit,
            wch_pc_o      => wch_pc,
            halted_o      => halted,
            halt_reason_o => halt_reason,
            instret_o     => instret,
            regs_o        => regs,
            retire_o      => retire
         ); -- i_multicycle

   elsif G_CORE = "pipeline" generate

      i_pipeline : entity work.pipeline
         generic map (
            G_BREAKS  => C_BREAKS.count,
            G_WATCHES => C_WATCHES.count
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
            pause_i       => pause,
            paused_o      => paused,
            brk_addr_i    => C_BREAKS.addrs,
            brk_en_i      => (others => '1'),
            wch_addr_i    => C_WATCHES.addrs,
            wch_en_i      => C_WATCHES.en,
            wch_hit_o     => wch_hit,
            wch_pc_o      => wch_pc,
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
               C_TOD when G_CYCLE_COUNTER and dbus_addr(31 downto 4) = X"FFFFFF4" and
                          dbus_addr(3 downto 0) >= X"6" and dbus_addr(3 downto 0) <= X"9" else
               C_PERF when dbus_addr(31 downto 5) = X"FFFFFF" & "010" and
                           (G_CYCLE_COUNTER or (dbus_addr(4 downto 1) /= "0000" and
                                                dbus_addr(4 downto 1) /= "0010" and
                                                dbus_addr(4 downto 1) /= "0011" and
                                                dbus_addr(4 downto 1) /= "0100")) else
               C_SD when dbus_addr(31 downto 4) = X"FFFFFFA" else
               C_NET when dbus_addr(31 downto 4) = X"FFFFFFB" else
               C_ETH when dbus_addr(31 downto 4) = X"FFFFFFC" else
               C_STATS when dbus_addr(31 downto 5) = X"FFFFFF" & "011" else
               C_FPU when G_FPU and dbus_addr(31 downto 3) = X"FFFFFF8" & '1' else
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


   run <= not paused and not halted;

   -- The pipelined core counts an instruction with a data read on
   -- instret_o when the bus accepts its last read, which is before its
   -- store (src/pipeline.vhd), and reports it when the store is accepted.
   -- early counts such instructions, and none is reported before it is
   -- counted.
   p_early : process (clk)
      variable early_v : integer;
   begin
      if rising_edge(clk) then
         early_v := early;
         if instret = '1' then
            early_v := early_v + 1;
         end if;
         if retire.valid = '1' then
            early_v := early_v - 1;
         end if;
         assert early_v >= 0
            report "an instruction is reported that was not counted"
            severity failure;
         early <= early_v;
         if rst = '1' then
            early <= 0;
         end if;
      end if;
   end process p_early;

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


   i_fpu : entity work.fpu
      port map (
         clk_i      => clk,
         rst_i      => rst,
         wb_cyc_i   => dbus_cyc,
         wb_stb_i   => slave_stb(C_FPU),
         wb_stall_o => slave_stall(C_FPU),
         wb_ack_o   => slave_ack(C_FPU),
         wb_we_i    => dbus_we,
         wb_addr_i  => dbus_addr(2 downto 0),
         wb_data_i  => dbus_data_out,
         wb_data_o  => slave_data(32 * C_FPU + 31 downto 32 * C_FPU)
      ); -- i_fpu


   i_perf : entity work.perf
      port map (
         clk_i        => clk,
         rst_i        => rst,
         instret_i    => instret,
         run_i        => run,
         retire_i     => retire,
         dbus_stb_i   => core_stb,
         dbus_we_i    => core_we,
         dbus_stall_i => core_stall,
         wb_cyc_i     => dbus_cyc,
         wb_stb_i     => slave_stb(C_PERF),
         wb_stall_o   => slave_stall(C_PERF),
         wb_ack_o     => slave_ack(C_PERF),
         wb_we_i      => dbus_we,
         wb_addr_i    => dbus_addr(4 downto 0),
         wb_data_i    => dbus_data_out,
         wb_data_o    => slave_data(32 * C_PERF + 31 downto 32 * C_PERF)
      ); -- i_perf


   -- The clock of the time of day. Its reset is the testbench's one reset,
   -- which stands for the reset of the system.
   i_tod : entity work.tod
      port map (
         clk_i      => clk,
         rst_i      => rst,
         wb_cyc_i   => dbus_cyc,
         wb_stb_i   => slave_stb(C_TOD),
         wb_stall_o => slave_stall(C_TOD),
         wb_ack_o   => slave_ack(C_TOD),
         wb_we_i    => dbus_we,
         wb_addr_i  => dbus_addr(1 downto 0) xor "10",
         wb_data_i  => dbus_data_out,
         wb_data_o  => slave_data(32 * C_TOD + 31 downto 32 * C_TOD)
      ); -- i_tod


   i_fetch_stats : entity work.fetch_stats
      generic map (
         G_ENABLE => G_FETCH_STATS
      )
      port map (
         clk_i      => clk,
         rst_i      => rst,
         events_i   => fetch_events,
         run_i      => run,
         wb_cyc_i   => dbus_cyc,
         wb_stb_i   => slave_stb(C_STATS),
         wb_stall_o => slave_stall(C_STATS),
         wb_ack_o   => slave_ack(C_STATS),
         wb_we_i    => dbus_we,
         wb_addr_i  => dbus_addr(4 downto 0),
         wb_data_i  => dbus_data_out,
         wb_data_o  => slave_data(32 * C_STATS + 31 downto 32 * C_STATS)
      ); -- i_fetch_stats


   i_sd_regs : entity work.sd_regs
      generic map (
         G_SLOTS    => 2,
         G_HOLD_ACK => true
      )
      port map (
         clk_i      => clk,
         rst_i      => rst,
         wb_cyc_i   => dbus_cyc,
         wb_stb_i   => slave_stb(C_SD),
         wb_stall_o => slave_stall(C_SD),
         wb_ack_o   => slave_ack(C_SD),
         wb_we_i    => dbus_we,
         wb_addr_i  => dbus_addr(3 downto 0),
         wb_data_i  => dbus_data_out,
         wb_data_o  => slave_data(32 * C_SD + 31 downto 32 * C_SD),
         present_i  => sd_present,
         wp_i       => sd_wp,
         busy_o     => open,
         start_o    => sd_start,
         abort_o    => sd_abort,
         cmd_o      => sd_cmd,
         slot_o     => sd_slot,
         lba_o      => sd_lba,
         done_i     => sd_done,
         error_i    => sd_error,
         last_i     => sd_last,
         type_i     => sd_type,
         buf_addr_i => sd_buf_addr,
         buf_we_i   => sd_buf_we,
         buf_data_i => sd_buf_wdata,
         buf_data_o => sd_buf_rdata
      ); -- i_sd_regs


   i_net_regs : entity work.net_regs
      port map (
         clk_i       => clk,
         rst_i       => rst,
         wb_cyc_i    => dbus_cyc,
         wb_stb_i    => slave_stb(C_NET),
         wb_stall_o  => slave_stall(C_NET),
         wb_ack_o    => slave_ack(C_NET),
         wb_we_i     => dbus_we,
         wb_addr_i   => dbus_addr(3 downto 0),
         wb_data_i   => dbus_data_out,
         wb_data_o   => slave_data(32 * C_NET + 31 downto 32 * C_NET),
         rx_good_i   => (others => '0'),
         rx_bad_i    => (others => '0'),
         tx_i        => (others => '0'),
         connected_i => '0',
         port_i      => (others => '0'),
         ip_o        => net_ip,
         mac_o       => net_mac,
         wr_o        => open
      ); -- i_net_regs


   i_eth_regs : entity work.eth_regs
      generic map (
         G_HOLD_ACK => true
      )
      port map (
         clk_i         => clk,
         rst_i         => rst,
         wb_cyc_i      => dbus_cyc,
         wb_stb_i      => slave_stb(C_ETH),
         wb_stall_o    => slave_stall(C_ETH),
         wb_ack_o      => slave_ack(C_ETH),
         wb_we_i       => dbus_we,
         wb_addr_i     => dbus_addr(3 downto 0),
         wb_data_i     => dbus_data_out,
         wb_data_o     => slave_data(32 * C_ETH + 31 downto 32 * C_ETH),
         enabled_o     => open,
         enable_o      => eth_enable,
         enable_done_i => eth_enable_done,
         rx_start_i    => eth_rx_start,
         rx_we_i       => eth_rx_we,
         rx_addr_i     => eth_rx_addr,
         rx_data_i     => eth_rx_data,
         rx_done_i     => eth_rx_done,
         rx_len_i      => eth_rx_len,
         tx_start_o    => eth_tx_start,
         busy_o        => open,
         tx_len_o      => eth_tx_len,
         tx_addr_i     => eth_tx_addr,
         tx_data_o     => eth_tx_data,
         tx_done_i     => eth_tx_done
      ); -- i_eth_regs


   i_eth_sim : entity work.eth_sim
      generic map (
         G_IN_FILE  => G_ETH_IN_FILE,
         G_OUT_FILE => G_ETH_OUT_FILE
      )
      port map (
         clk_i         => clk,
         ip_i          => net_ip,
         mac_i         => net_mac,
         tcp_port_i    => (others => '0'),
         enable_i      => eth_enable,
         enable_done_o => eth_enable_done,
         rx_start_o    => eth_rx_start,
         rx_we_o       => eth_rx_we,
         rx_addr_o     => eth_rx_addr,
         rx_data_o     => eth_rx_data,
         rx_done_o     => eth_rx_done,
         rx_len_o      => eth_rx_len,
         tx_start_i    => eth_tx_start,
         tx_len_i      => eth_tx_len,
         tx_addr_o     => eth_tx_addr,
         tx_data_i     => eth_tx_data,
         tx_done_o     => eth_tx_done
      ); -- i_eth_sim


   i_sd_sim : entity work.sd_sim
      generic map (
         G_SD0_FILE => G_SD0_FILE,
         G_SD1_FILE => G_SD1_FILE
      )
      port map (
         clk_i      => clk,
         present_o  => sd_present,
         wp_o       => sd_wp,
         start_i    => sd_start,
         abort_i    => sd_abort,
         cmd_i      => sd_cmd,
         slot_i     => sd_slot,
         lba_i      => sd_lba,
         done_o     => sd_done,
         error_o    => sd_error,
         last_o     => sd_last,
         type_o     => sd_type,
         buf_addr_o => sd_buf_addr,
         buf_we_o   => sd_buf_we,
         buf_data_o => sd_buf_wdata,
         buf_data_i => sd_buf_rdata
      ); -- i_sd_sim


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
         done_o          => done,
         status_o        => status
      ); -- i_trace


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
      variable hit_v     : natural  := 0;       -- The lowest watchpoint hit
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
         elsif C_BREAKS.count > 0 or C_WATCHES.count > 0 then
            -- A stop at a breakpoint or after a watchpoint's hit: pause_i
            -- '1' for a cycle, and then '0' until the core has gone on
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
                  for i in C_WATCHES_MAX - 1 downto 0 loop
                     if wch_hit(i) = '1' then
                        hit_v := i;
                     end if;
                  end loop;
                  if wch_hit /= (wch_hit'range => '0') then
                     write(l, " w " & integer'image(hit_v) & " " & to_hstring(wch_pc));
                  end if;
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
            assert (halted = '1' and halt_reason = halt_v)
                   or (halted = '0' and halt_reason = HALT_NONE)
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


   -- The cycle counter counts the cycles after reset in which the core is
   -- running, so it stops while paused_o or halted_o is '1'.
   p_counters : process (clk)
      variable cycles_v : std_logic_vector(63 downto 0);   -- The counter
      variable count_v  : natural := 0;                    -- The cycles counted so far
   begin
      if rising_edge(clk) then
         cycles_v := << signal .tb_core.i_perf.cycles_r : std_logic_vector(63 downto 0) >>;
         assert cycles_v = to_slv(count_v, 64)
            report "tb_core: the cycle counter is " & to_string(cycles_v) & ", not "
                   & integer'image(count_v)
            severity failure;
         if rst = '1' then
            count_v := 0;
         elsif paused = '0' and halted = '0' then
            count_v := count_v + 1;
         end if;
      end if;
   end process p_counters;


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
      variable causes_v   : line;
   begin
      if rising_edge(clk) and rst = '0' and G_RETIRE_LOG /= "" then
         write(causes_v, character'val(character'pos('a') + fetch_events.cause));
         if fetch_events.flush = '1' then
            write(causes_v, character'val(character'pos('A') + fetch_events.fwhy));
         end if;
         if retire.valid = '1' then
            if not log_open_v then
               file_open(log_f, G_RETIRE_LOG, write_mode);
               log_open_v := true;
            end if;
            write(l, integer'image(cycle_v) & " " & to_hstring(retire.addr));
            write(l, string'(" ") & causes_v.all);
            deallocate(causes_v);
            writeline(log_f, l);
            if retire.halt /= HALT_NONE then
               flush(log_f);
            end if;
         end if;
         cycle_v := cycle_v + 1;
      end if;
   end process p_retire_log;


   p_waits : process (clk)
      variable held_v : t_rwaits;
   begin
      if rising_edge(clk) and rst = '0' then
         n_cycles <= n_cycles + 1;
         held_v   := n_held;
         if fetch_events.wait_sr = '1' then
            held_v(0) := held_v(0) + 1;
         end if;
         if fetch_events.wait_wr = '1' then
            held_v(1) := held_v(1) + 1;
         end if;
         -- The core reports the events two cycles late.
         if fetch_events.flush = '1' then
            n_drop <= (n_drop(0) + held_v(0), n_drop(1) + held_v(1));
            held_v := (0, 0);
         elsif fetch_events.moved = '1' then
            n_went <= (n_went(0) + held_v(0), n_went(1) + held_v(1));
            held_v := (0, 0);
         end if;
         n_held <= held_v;
      end if;
   end process p_waits;


   p_finish : process
      variable l : line;
   begin
      wait until done = '1';
      for i in 1 to 4 loop
         wait until rising_edge(clk);
      end loop;
      if G_CORE = "pipeline" then
         write(l, "Read waits: " & integer'image(n_cycles) & " cycles; went on: " &
                  integer'image(n_went(0)) & " for the condition, " &
                  integer'image(n_went(1)) & " for an older micro-operation; dropped: " &
                  integer'image(n_drop(0)) & ", " & integer'image(n_drop(1)));
         writeline(output, l);
      end if;
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
