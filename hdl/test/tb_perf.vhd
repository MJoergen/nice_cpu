-- A self-checking test of src/perf.vhd.
--
-- THEORY OF OPERATION
-- The counters start at G_RESET = 0x00000000_FFFFFFF0, so that their low
-- words wrap early in the test. The checks:
-- * Reads accepted n cycles apart see cycle counts n apart.
-- * The instruction counter counts the cycles with instret_i high.
-- * The cycle counter stops while run_i is low, and the instruction counter
--   does not depend on it.
-- * A read of a high word returns the snapshot that the last read of the
--   low word took, also when the low word has wrapped since. The two
--   counters have a snapshot each.
-- * The microsecond counter, at G_CLK_HZ = 1500000, counts 2 microseconds
--   in 3 cycles, exactly, and also stops while run_i is low.
-- * The spare words read 0, and writes change nothing.
-- * Reset sets the counters and the snapshots to G_RESET.
-- The run stops with status 0 when every check passes, and 1 at the first
-- that fails.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use std.env.all;

entity tb_perf is
end entity tb_perf;

architecture simulation of tb_perf is

   constant C_RESET : std_logic_vector(63 downto 0) := X"00000000_FFFFFFF0";

   constant C_CYCLE_LO : natural := 0;
   constant C_CYCLE_HI : natural := 1;
   constant C_INSTR_LO : natural := 2;
   constant C_INSTR_HI : natural := 3;
   constant C_TIME_LO  : natural := 4;
   constant C_TIME_HI  : natural := 5;

   signal clk : std_logic;
   signal rst : std_logic := '1';

   signal instret  : std_logic                     := '0';
   signal run      : std_logic                     := '1';
   signal cyc      : std_logic                     := '0';
   signal stb      : std_logic                     := '0';
   signal stall    : std_logic;
   signal ack      : std_logic;
   signal we       : std_logic                     := '0';
   signal addr     : std_logic_vector(3 downto 0)  := (others => '0');
   signal data_out : std_logic_vector(31 downto 0) := (others => '0');
   signal data_in  : std_logic_vector(31 downto 0);

begin

   p_clk : process
   begin
      clk <= '1', '0' after 5 ns;
      wait for 10 ns;
   end process p_clk;


   i_perf : entity work.perf
      generic map (
         G_RESET  => C_RESET,
         G_CLK_HZ => 1500000
      )
      port map (
         clk_i      => clk,
         rst_i      => rst,
         instret_i  => instret,
         run_i      => run,
         wb_cyc_i   => cyc,
         wb_stb_i   => stb,
         wb_stall_o => stall,
         wb_ack_o   => ack,
         wb_we_i    => we,
         wb_addr_i  => addr,
         wb_data_i  => data_out,
         wb_data_o  => data_in
      ); -- i_perf


   p_test : process
      variable first_v  : std_logic_vector(31 downto 0);
      variable second_v : std_logic_vector(31 downto 0);

      procedure fail(msg : string) is
      begin
         report "tb_perf: " & msg
            severity error;
         stop(1);
      end procedure fail;

      -- A request, accepted at the next clock edge. Right after that edge,
      -- the signals still hold the values the counters saw at it, and ACK
      -- is high.
      procedure access_word(w : std_logic; a : natural; d : std_logic_vector(31 downto 0);
                            q : out std_logic_vector(31 downto 0)) is
      begin
         cyc      <= '1';
         stb      <= '1';
         we       <= w;
         addr     <= to_slv(a, 4);
         data_out <= d;
         wait until rising_edge(clk);
         if stall /= '0' then
            fail("STALL is high");
         end if;
         stb <= '0';
         cyc <= '0';
         wait for 1 ns;
         if ack /= '1' then
            fail("no ACK in the cycle after the request");
         end if;
         q := data_in;
      end procedure access_word;

      procedure read_word(a : natural; q : out std_logic_vector(31 downto 0)) is
      begin
         access_word('0', a, X"00000000", q);
      end procedure read_word;

      procedure check(a : natural; want : std_logic_vector(31 downto 0); what : string) is
         variable got_v : std_logic_vector(31 downto 0);
      begin
         read_word(a, got_v);
         if got_v /= want then
            fail(what & ": word " & integer'image(a) & " = " & to_hstring(got_v) &
                 ", expected " & to_hstring(want));
         end if;
      end procedure check;

      procedure clocks(n : natural) is
      begin
         for i in 1 to n loop
            wait until rising_edge(clk);
         end loop;
      end procedure clocks;

      procedure instructions(n : natural) is
      begin
         instret <= '1';
         clocks(n);
         instret <= '0';
      end procedure instructions;

   begin
      clocks(2);
      rst <= '0';

      -- Reset, and no snapshot yet: the high words are those of G_RESET.
      -- The first read is at the first edge after reset.
      check(C_INSTR_HI, X"00000000", "after reset");
      check(C_INSTR_LO, X"FFFFFFF0", "after reset");
      check(C_CYCLE_HI, X"00000000", "after reset");
      check(C_CYCLE_LO, X"FFFFFFF3", "the fourth edge after reset");

      -- The cycle counter wraps its low word between the reads of the low
      -- and the high word. The high word comes from the snapshot.
      read_word(C_CYCLE_LO, first_v);
      if first_v /= X"FFFFFFF4" then
         fail("the next cycle reads " & to_hstring(first_v));
      end if;
      clocks(20);
      check(C_CYCLE_HI, X"00000000", "the snapshot before the wrap");
      read_word(C_CYCLE_LO, first_v);
      if first_v /= X"0000000A" then -- 0xFFFFFFF4 + 20 + 2
         fail("after the wrap, the low word is " & to_hstring(first_v));
      end if;
      check(C_CYCLE_HI, X"00000001", "the snapshot after the wrap");

      -- Reads n cycles apart differ by n.
      read_word(C_CYCLE_LO, first_v);
      clocks(9);
      read_word(C_CYCLE_LO, second_v);
      if second_v - first_v /= 10 then
         fail("reads 10 cycles apart differ by " & to_hstring(second_v - first_v));
      end if;

      -- The instruction counter counts the cycles with instret_i high, and
      -- its low word wraps.
      instructions(3);
      read_word(C_INSTR_LO, first_v);
      if first_v /= X"FFFFFFF3" then
         fail("3 instructions read " & to_hstring(first_v));
      end if;
      instructions(20);
      -- The cycle counter's snapshot is its own.
      check(C_CYCLE_HI, X"00000001", "the cycle snapshot after instruction reads");
      check(C_INSTR_HI, X"00000000", "the instruction snapshot before the wrap");
      check(C_INSTR_LO, X"00000007", "23 instructions");
      check(C_INSTR_HI, X"00000001", "the instruction snapshot after the wrap");

      -- With run_i low the cycle counter stands still, and resumes with it.
      read_word(C_CYCLE_LO, first_v);
      run <= '0';
      clocks(50);
      read_word(C_CYCLE_LO, second_v);
      if second_v - first_v /= 1 then -- only the cycle after the first read's edge counts
         fail("the cycle counter moved by " & to_hstring(second_v - first_v) & " with run_i low");
      end if;
      read_word(C_CYCLE_LO, first_v);
      if first_v /= second_v then
         fail("the cycle counter moved between reads with run_i low");
      end if;
      run <= '1';
      clocks(5);
      read_word(C_CYCLE_LO, second_v);
      if second_v - first_v < 5 then
         fail("the cycle counter did not resume with run_i high");
      end if;

      -- The spare words read 0, and writes change nothing.
      for i in 6 to 15 loop
         check(i, X"00000000", "a spare word");
      end loop;
      for i in 0 to 15 loop
         access_word('1', i, X"DEADBEEF", first_v);
      end loop;
      check(C_INSTR_HI, X"00000001", "the snapshot after writes");
      check(C_INSTR_LO, X"00000007", "the counter after writes");
      read_word(C_CYCLE_LO, first_v);
      read_word(C_CYCLE_LO, second_v);
      if second_v - first_v /= 1 then
         fail("the cycle counter after writes");
      end if;

      -- Reset sets the counters and the snapshots back to G_RESET.
      rst <= '1';
      clocks(1);
      rst <= '0';
      check(C_INSTR_HI, X"00000000", "the snapshot after a second reset");
      check(C_INSTR_LO, X"FFFFFFF0", "the counter after a second reset");
      check(C_CYCLE_HI, X"00000000", "the snapshot after a second reset");

      -- The microsecond counter, from a clean start. G_CLK_HZ = 1500000 makes
      -- 2 microseconds in 3 cycles, and G_RESET puts the low word 16 below a
      -- wrap, 24 cycles away.
      check(C_TIME_HI, X"00000000", "the time snapshot after reset");
      read_word(C_TIME_LO, first_v);
      if first_v(31 downto 4) /= X"FFFFFFF" then
         fail("the time just after reset is " & to_hstring(first_v));
      end if;
      clocks(40);
      check(C_TIME_HI, X"00000000", "the time snapshot before the wrap");
      read_word(C_TIME_LO, first_v);
      if first_v(31 downto 8) /= X"000000" then
         fail("the time after the wrap is " & to_hstring(first_v));
      end if;
      check(C_TIME_HI, X"00000001", "the time snapshot after the wrap");

      -- 30 cycles are exactly 20 microseconds, whatever the phase.
      read_word(C_TIME_LO, first_v);
      clocks(29);
      read_word(C_TIME_LO, second_v);
      if second_v - first_v /= 20 then
         fail("reads 30 cycles apart differ by " & to_hstring(second_v - first_v) & " us");
      end if;

      -- With run_i low the time stands still, and it resumes.
      read_word(C_TIME_LO, first_v);
      run <= '0';
      clocks(50);
      read_word(C_TIME_LO, second_v);
      if second_v - first_v > 2 then -- at most the cycles up to the read's edge count
         fail("the time moved by " & to_hstring(second_v - first_v) & " with run_i low");
      end if;
      read_word(C_TIME_LO, first_v);
      if first_v /= second_v then
         fail("the time moved between reads with run_i low");
      end if;
      run <= '1';
      clocks(30);
      read_word(C_TIME_LO, second_v);
      if second_v - first_v < 20 then
         fail("the time did not resume with run_i high");
      end if;

      -- Writes change nothing.
      access_word('1', C_TIME_LO, X"DEADBEEF", first_v);
      access_word('1', C_TIME_HI, X"DEADBEEF", first_v);
      check(C_TIME_HI, X"00000001", "the time snapshot after writes");

      report "tb_perf: all checks passed";
      stop(0);
   end process p_test;

end architecture simulation;
