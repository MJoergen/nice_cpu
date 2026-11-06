-- The performance counters of SYSTEM.md §3: 32 words of I/O with a 64-bit
-- cycle counter, a 64-bit instruction counter, a 64-bit counter of
-- microseconds, and the 64-bit counters of five events of the program.
--
--   0  CYCLE_LO   2  INSTR_LO   4  TIME_LO    0A  READ_LO    0C  STORE_LO
--   1  CYCLE_HI   3  INSTR_HI   5  TIME_HI    0B  READ_HI    0D  STORE_HI
--   0E  SKIP_LO   10  JUMP_LO   12  INTR_LO   6-9, 14-1F  read 0
--   0F  SKIP_HI   11  JUMP_HI   13  INTR_HI
--
-- THEORY OF OPERATION
-- The cycle counter counts the clock cycles after reset in which run_i is
-- high. A system drives run_i with "the core is running", so that the counter
-- stops while the core is paused or halted, as the emulator's does at a halt. The instruction
-- counter counts the cycles in which instret_i is high, and the core raises
-- it once for each instruction that completes.
--
-- The microsecond counter counts in the same cycles as the cycle counter.
-- An accumulator adds 1000000 in each such cycle. When the sum reaches
-- G_CLK_HZ, the clock frequency in hertz, the counter counts one
-- microsecond and the accumulator keeps the sum less G_CLK_HZ. So the
-- counter is exact for any frequency of 1 MHz or more, whether or not it
-- is a multiple of 1 MHz: after N cycles it holds the integer part of
-- N * 1000000 / G_CLK_HZ.
--
-- The event counters count what the program does. The read counter and the
-- store counter count the data reads and the stores that the core's data
-- bus accepts. The skip, jump, and interrupt counters count the steps that
-- the core reports on retire_i: a skipped instruction, one that writes R15
-- (writes_r15 of nice_pkg), and an interrupt entry or INT, but no step
-- that halts. A core reports a step no later than the cycle in which it
-- counts its instruction on instret_i, and issues no read of a younger
-- instruction before then, so a read of a counter counts what came before
-- it, as a read of INSTR_LO does.
--
-- A read of a low word returns the low word of its counter as it is in the
-- cycle the read is accepted, and copies the whole counter into the
-- counter's snapshot in the same cycle. A read of a high word returns the
-- high word of the snapshot. So two reads, low then high, give the 64-bit
-- value at the first read, even when the low word wraps in between.
--
-- The port is a pipelined Wishbone slave. It never stalls, and it
-- acknowledges each request in the cycle after it accepts it. Writes are
-- ignored.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) STB is high only for requests to the counters: the bus decoder decodes
--    the address bits above bit 4.
-- b) instret_i is high for one cycle per completed instruction.
-- c) run_i is low while the core is held, paused, or halted: a system drives
--    it with "not paused_o and not halted_o" of the core, and low too while
--    it holds the core. It defaults to '1'.
-- d) retire_i is the core's retire_o, and dbus_stb_i, dbus_we_i, and
--    dbus_stall_i are the core's own data bus, before any other master,
--    such as a debug link, joins it. They default to no events.
--
-- RESET
-- Synchronous. It sets all counters and snapshots to G_RESET, which
-- is 0 except in tests, as SYSTEM.md §3 requires, clears the accumulator,
-- and drops any ACK owed.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use work.nice_pkg.all;
   use work.trace_pkg.all;

entity perf is
   generic (
      -- The counters' value after reset. SYSTEM.md §3 wants 0. A test sets
      -- it near a wrap of the low word.
      G_RESET  : std_logic_vector(63 downto 0) := (others => '0');
      -- The frequency of clk_i in hertz, at least 1000000. It sets the
      -- rate of the microsecond counter.
      G_CLK_HZ : natural range 1000000 to 500000000 := 100000000
   );
   port (
      clk_i        : in  std_logic;
      rst_i        : in  std_logic;

      -- High for one cycle when an instruction completes
      instret_i    : in  std_logic;

      -- High in each cycle that the cycle counter counts
      run_i        : in  std_logic := '1';

      -- The core's report of each step, and its data bus requests
      retire_i     : in  t_retire  := C_RETIRE_NONE;
      dbus_stb_i   : in  std_logic := '0';
      dbus_we_i    : in  std_logic := '0';
      dbus_stall_i : in  std_logic := '0';

      wb_cyc_i     : in  std_logic;
      wb_stb_i     : in  std_logic;
      wb_stall_o   : out std_logic;
      wb_ack_o     : out std_logic := '0';
      wb_we_i      : in  std_logic;
      wb_addr_i    : in  std_logic_vector(4 downto 0);
      wb_data_i    : in  std_logic_vector(31 downto 0);
      wb_data_o    : out std_logic_vector(31 downto 0) := (others => '0')
   );
end entity perf;

architecture synthesis of perf is

   -- The counters, in the order of their low words: cycles, instructions,
   -- microseconds, data reads, stores, skips, jumps, and interrupts
   constant C_COUNTERS : natural := 8;

   type t_counters is array (0 to C_COUNTERS - 1) of std_logic_vector(63 downto 0);
   type t_snaps is array (0 to C_COUNTERS - 1) of std_logic_vector(31 downto 0);

   -- The address of each counter's low word
   type     t_addrs is array (0 to C_COUNTERS - 1) of natural;
   constant C_ADDR : t_addrs := (16#00#, 16#02#, 16#04#, 16#0A#, 16#0C#, 16#0E#, 16#10#, 16#12#);

   constant C_CYCLES : natural := 0;
   constant C_INSTRS : natural := 1;
   constant C_MICROS : natural := 2;
   constant C_READS  : natural := 3;
   constant C_STORES : natural := 4;
   constant C_SKIPS  : natural := 5;
   constant C_JUMPS  : natural := 6;
   constant C_INTRS  : natural := 7;

   signal count_r : t_counters := (others => G_RESET);
   signal snap_r  : t_snaps    := (others => G_RESET(63 downto 32));

   -- The cycle counter, which test/tb_core.vhd reads by its name
   signal cycles_r : std_logic_vector(63 downto 0);

   -- The microseconds so far in the current second, scaled by G_CLK_HZ
   signal frac_r : natural range 0 to G_CLK_HZ - 1 := 0;

   signal accept : std_logic;
   signal events : std_logic_vector(C_READS to C_INTRS);

begin

   accept     <= wb_cyc_i and wb_stb_i;
   wb_stall_o <= '0';
   cycles_r   <= count_r(C_CYCLES);


   -- The events of this cycle
   p_events : process (all)
      variable step_v : boolean;
      variable int_v  : boolean;
   begin
      step_v := retire_i.valid = '1' and retire_i.halt = HALT_NONE;
      int_v  := retire_i.skipped = '0' and is_ctrl(retire_i.iw) and
                retire_i.iw(25 downto 21) = "00010";

      events          <= (others => '0');
      events(C_READS) <= dbus_stb_i and not dbus_stall_i and not dbus_we_i;
      events(C_STORES) <= dbus_stb_i and not dbus_stall_i and dbus_we_i;
      if step_v and retire_i.intr = '0' then
         events(C_SKIPS) <= retire_i.skipped;
         events(C_JUMPS) <= to_sl(retire_i.skipped = '0' and writes_r15(retire_i.iw));
      end if;
      events(C_INTRS) <= to_sl(step_v and (retire_i.intr = '1' or int_v));
   end process p_events;


   p_count : process (clk_i)
      variable frac_v : natural;
   begin
      if rising_edge(clk_i) then
         if run_i = '1' then
            count_r(C_CYCLES) <= count_r(C_CYCLES) + 1;
            frac_v := frac_r + 1000000;
            if frac_v >= G_CLK_HZ then
               frac_r            <= frac_v - G_CLK_HZ;
               count_r(C_MICROS) <= count_r(C_MICROS) + 1;
            else
               frac_r <= frac_v;
            end if;
         end if;
         if instret_i = '1' then
            count_r(C_INSTRS) <= count_r(C_INSTRS) + 1;
         end if;
         for i in C_READS to C_INTRS loop
            if events(i) = '1' then
               count_r(i) <= count_r(i) + 1;
            end if;
         end loop;

         if rst_i = '1' then
            count_r <= (others => G_RESET);
            frac_r  <= 0;
         end if;
      end if;
   end process p_count;


   p_bus : process (clk_i)
   begin
      if rising_edge(clk_i) then
         wb_ack_o <= accept;

         if accept = '1' and wb_we_i = '0' then
            wb_data_o <= (others => '0');
            for i in 0 to C_COUNTERS - 1 loop
               if to_integer(wb_addr_i) = C_ADDR(i) then
                  wb_data_o <= count_r(i)(31 downto 0);
                  snap_r(i) <= count_r(i)(63 downto 32);
               elsif to_integer(wb_addr_i) = C_ADDR(i) + 1 then
                  wb_data_o <= snap_r(i);
               end if;
            end loop;
         end if;

         if rst_i = '1' then
            wb_ack_o <= '0';
            snap_r   <= (others => G_RESET(63 downto 32));
         end if;
      end if;
   end process p_bus;

end architecture synthesis;
