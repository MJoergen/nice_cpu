-- The performance counters of SYSTEM.md §3: 16 words of I/O with a 64-bit
-- cycle counter, a 64-bit instruction counter, and a 64-bit counter of
-- microseconds.
--
--   0  CYCLE_LO   2  INSTR_LO   4  TIME_LO   6-15  read 0
--   1  CYCLE_HI   3  INSTR_HI   5  TIME_HI
--
-- THEORY OF OPERATION
-- The cycle counter counts the clock cycles after reset in which run_i is
-- high. A system drives run_i with "the core is running", so that the counter
-- stops at a halt, as the emulator's does. The instruction
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
--    the address bits above bit 3.
-- b) instret_i is high for one cycle per completed instruction.
-- c) run_i is low while the core is held or halted. It defaults to '1'.
--
-- RESET
-- Synchronous. It sets both counters and both snapshots to G_RESET, which
-- is 0 except in tests, as SYSTEM.md §3 requires, clears the accumulator,
-- and drops any ACK owed.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

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
      clk_i      : in  std_logic;
      rst_i      : in  std_logic;

      -- High for one cycle when an instruction completes
      instret_i  : in  std_logic;

      -- High in each cycle that the cycle counter counts
      run_i      : in  std_logic := '1';

      wb_cyc_i   : in  std_logic;
      wb_stb_i   : in  std_logic;
      wb_stall_o : out std_logic;
      wb_ack_o   : out std_logic := '0';
      wb_we_i    : in  std_logic;
      wb_addr_i  : in  std_logic_vector(3 downto 0);
      wb_data_i  : in  std_logic_vector(31 downto 0);
      wb_data_o  : out std_logic_vector(31 downto 0) := (others => '0')
   );
end entity perf;

architecture synthesis of perf is

   signal cycles_r      : std_logic_vector(63 downto 0) := G_RESET;
   signal cycles_snap_r : std_logic_vector(63 downto 0) := G_RESET;
   signal instrs_r      : std_logic_vector(63 downto 0) := G_RESET;
   signal instrs_snap_r : std_logic_vector(63 downto 0) := G_RESET;
   signal micros_r      : std_logic_vector(63 downto 0) := G_RESET;
   signal micros_snap_r : std_logic_vector(63 downto 0) := G_RESET;

   -- The microseconds so far in the current second, scaled by G_CLK_HZ
   signal frac_r : natural range 0 to G_CLK_HZ - 1 := 0;

   signal accept : std_logic;

begin

   accept     <= wb_cyc_i and wb_stb_i;
   wb_stall_o <= '0';


   p_count : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if run_i = '1' then
            cycles_r <= cycles_r + 1;
            if frac_r + 1000000 >= G_CLK_HZ then
               frac_r   <= frac_r + 1000000 - G_CLK_HZ;
               micros_r <= micros_r + 1;
            else
               frac_r <= frac_r + 1000000;
            end if;
         end if;
         if instret_i = '1' then
            instrs_r <= instrs_r + 1;
         end if;

         if rst_i = '1' then
            cycles_r <= G_RESET;
            instrs_r <= G_RESET;
            micros_r <= G_RESET;
            frac_r   <= 0;
         end if;
      end if;
   end process p_count;


   p_bus : process (clk_i)
   begin
      if rising_edge(clk_i) then
         wb_ack_o <= accept;

         if accept = '1' and wb_we_i = '0' then
            case wb_addr_i is
               when X"0" =>
                  wb_data_o     <= cycles_r(31 downto 0);
                  cycles_snap_r <= cycles_r;

               when X"1" =>
                  wb_data_o <= cycles_snap_r(63 downto 32);

               when X"2" =>
                  wb_data_o     <= instrs_r(31 downto 0);
                  instrs_snap_r <= instrs_r;

               when X"3" =>
                  wb_data_o <= instrs_snap_r(63 downto 32);

               when X"4" =>
                  wb_data_o     <= micros_r(31 downto 0);
                  micros_snap_r <= micros_r;

               when X"5" =>
                  wb_data_o <= micros_snap_r(63 downto 32);

               when others =>
                  wb_data_o <= (others => '0');
            end case;
         end if;

         if rst_i = '1' then
            wb_ack_o      <= '0';
            cycles_snap_r <= G_RESET;
            instrs_snap_r <= G_RESET;
            micros_snap_r <= G_RESET;
         end if;
      end if;
   end process p_bus;

end architecture synthesis;
