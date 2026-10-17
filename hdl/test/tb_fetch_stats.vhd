-- A self-checking test of src/fetch_stats.vhd.
--
-- THEORY OF OPERATION
-- The test drives events_i by hand, one cycle at a time, and reads the
-- counters while they are stopped. The checks:
-- * After reset the counters run, and FS_CTRL reads 1.
-- * A write of 2 to FS_CTRL clears the counters and stops them: every word
--   reads 0, except FS_MIN, which reads 31.
-- * A write of 3 clears them and starts them from the next cycle. Each
--   cycle until the write that stops them, that one's included, counts
--   once in FS_CYCLES and in FS_HIST + count, and each counter counts its
--   events. FS_MIN, FS_MAX, and FS_HELD_MAX follow count and held.
-- * Stopped counters keep their values, and writes to other words change
--   nothing. A write of 1 starts them again without clearing them.
-- * A second instance, with G_ENABLE false, acknowledges every request and
--   reads 0.
-- The run stops with status 0 when every check passes, and 1 at the first
-- that fails.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use std.env.all;

   use work.pipe_pkg.all;

entity tb_fetch_stats is
end entity tb_fetch_stats;

architecture simulation of tb_fetch_stats is

   constant C_CTRL     : natural := 16#10#;
   constant C_CYCLES   : natural := 16#11#;
   constant C_STARVE   : natural := 16#12#;
   constant C_BLOCKED  : natural := 16#13#;
   constant C_FULL     : natural := 16#14#;
   constant C_STALL    : natural := 16#15#;
   constant C_PAIRS    : natural := 16#16#;
   constant C_WORDS    : natural := 16#17#;
   constant C_JUMPS    : natural := 16#18#;
   constant C_FLUSHES  : natural := 16#19#;
   constant C_MIN      : natural := 16#1A#;
   constant C_MAX      : natural := 16#1B#;
   constant C_HELD_MAX : natural := 16#1C#;
   constant C_HIST     : natural := 16#20#;

   signal clk : std_logic;
   signal rst : std_logic := '1';

   signal events   : t_fetch_events                := C_FETCH_EVENTS_NONE;
   signal cyc      : std_logic                     := '0';
   signal stb      : std_logic_vector(0 to 1)      := "00";
   signal stall    : std_logic_vector(0 to 1);
   signal ack      : std_logic_vector(0 to 1);
   signal we       : std_logic                     := '0';
   signal addr     : std_logic_vector(5 downto 0)  := (others => '0');
   signal data_out : std_logic_vector(31 downto 0) := (others => '0');
   signal data_on  : std_logic_vector(31 downto 0);
   signal data_off : std_logic_vector(31 downto 0);

begin

   p_clk : process
   begin
      clk <= '1', '0' after 5 ns;
      wait for 10 ns;
   end process p_clk;


   i_fetch_stats : entity work.fetch_stats
      port map (
         clk_i      => clk,
         rst_i      => rst,
         events_i   => events,
         wb_cyc_i   => cyc,
         wb_stb_i   => stb(0),
         wb_stall_o => stall(0),
         wb_ack_o   => ack(0),
         wb_we_i    => we,
         wb_addr_i  => addr,
         wb_data_i  => data_out,
         wb_data_o  => data_on
      ); -- i_fetch_stats


   i_fetch_stats_off : entity work.fetch_stats
      generic map (
         G_ENABLE => false
      )
      port map (
         clk_i      => clk,
         rst_i      => rst,
         events_i   => events,
         wb_cyc_i   => cyc,
         wb_stb_i   => stb(1),
         wb_stall_o => stall(1),
         wb_ack_o   => ack(1),
         wb_we_i    => we,
         wb_addr_i  => addr,
         wb_data_i  => data_out,
         wb_data_o  => data_off
      ); -- i_fetch_stats_off


   p_test : process

      procedure fail(msg : string) is
      begin
         report "tb_fetch_stats: " & msg
            severity error;
         stop(1);
      end procedure fail;

      -- A request to instance n, accepted at the next clock edge. Right
      -- after that edge, ACK is high and the read data is there.
      procedure access_word(n : natural; w : std_logic; a : natural;
                            d : std_logic_vector(31 downto 0);
                            q : out std_logic_vector(31 downto 0)) is
      begin
         cyc      <= '1';
         stb(n)   <= '1';
         we       <= w;
         addr     <= to_slv(a, 6);
         data_out <= d;
         wait until rising_edge(clk);
         if stall(n) /= '0' then
            fail("STALL is high");
         end if;
         stb(n) <= '0';
         cyc    <= '0';
         wait for 1 ns;
         if ack(n) /= '1' then
            fail("no ACK in the cycle after the request");
         end if;
         if n = 0 then
            q := data_on;
         else
            q := data_off;
         end if;
      end procedure access_word;

      procedure write_word(a : natural; d : natural) is
         variable q_v : std_logic_vector(31 downto 0);
      begin
         access_word(0, '1', a, to_slv(d, 32), q_v);
      end procedure write_word;

      procedure check(n : natural; a : natural; want : natural; what : string) is
         variable got_v : std_logic_vector(31 downto 0);
      begin
         access_word(n, '0', a, X"00000000", got_v);
         if got_v /= to_slv(want, 32) then
            fail(what & ": word " & to_hstring(to_slv(a, 8)) & " = " & to_hstring(got_v) &
                 ", expected " & to_hstring(to_slv(want, 32)));
         end if;
      end procedure check;

      procedure check(a : natural; want : natural; what : string) is
      begin
         check(0, a, want, what);
      end procedure check;

      procedure clocks(n : natural) is
      begin
         for i in 1 to n loop
            wait until rising_edge(clk);
         end loop;
      end procedure clocks;

      -- The events of one cycle
      procedure cycle(count   : natural;
                      held    : natural;
                      starve  : std_logic := '0';
                      blocked : std_logic := '0';
                      full    : std_logic := '0';
                      stalled : std_logic := '0';
                      pair    : std_logic := '0';
                      words   : natural   := 0;
                      jump    : std_logic := '0';
                      flush   : std_logic := '0') is
      begin
         events.count   <= count;
         events.held    <= held;
         events.starve  <= starve;
         events.blocked <= blocked;
         events.full    <= full;
         events.stall   <= stalled;
         events.pair    <= pair;
         events.words   <= words;
         events.jump    <= jump;
         events.flush   <= flush;
         clocks(1);
      end procedure cycle;

      -- Every word of the histogram but those of counts a and b reads 0.
      procedure check_hist(a : natural; na : natural; b : natural; nb : natural;
                           what : string) is
      begin
         for i in 0 to 31 loop
            if i = a then
               check(C_HIST + i, na, what);
            elsif i = b then
               check(C_HIST + i, nb, what);
            else
               check(C_HIST + i, 0, what);
            end if;
         end loop;
      end procedure check_hist;

      variable q_v : std_logic_vector(31 downto 0);

   begin
      clocks(2);
      rst <= '0';

      -- After reset the counters run.
      check(C_CTRL, 1, "after reset");

      -- Clear and stop.
      write_word(C_CTRL, 2);
      check(C_CTRL, 0, "stopped");
      for i in C_CYCLES to C_FLUSHES loop
         check(i, 0, "cleared");
      end loop;
      check(C_MIN, 31, "cleared");
      check(C_MAX, 0, "cleared");
      check(C_HELD_MAX, 0, "cleared");
      for i in 16#1D# to 16#1F# loop
         check(i, 0, "a spare word");
      end loop;
      check_hist(0, 0, 0, 0, "cleared");

      -- Clear and run, from the cycle after the write. Four cycles count:
      -- A, B, C, and C again at the write that stops the counters.
      write_word(C_CTRL, 3);
      cycle(5, 9, starve => '1', pair => '1');
      cycle(7, 7, blocked => '1', full => '1', stalled => '1', words => 3, jump => '1');
      cycle(2, 12, pair => '1', words => 2, flush => '1');
      write_word(C_CTRL, 0);
      events <= C_FETCH_EVENTS_NONE;
      clocks(5);

      check(C_CYCLES, 4, "four cycles");
      check(C_STARVE, 1, "four cycles");
      check(C_BLOCKED, 1, "four cycles");
      check(C_FULL, 1, "four cycles");
      check(C_STALL, 1, "four cycles");
      check(C_PAIRS, 3, "four cycles");
      check(C_WORDS, 7, "four cycles");
      check(C_JUMPS, 1, "four cycles");
      check(C_FLUSHES, 2, "four cycles");
      check(C_MIN, 2, "four cycles");
      check(C_MAX, 7, "four cycles");
      check(C_HELD_MAX, 12, "four cycles");
      for i in 0 to 31 loop
         if i = 2 then
            check(C_HIST + i, 2, "four cycles");
         elsif i = 5 or i = 7 then
            check(C_HIST + i, 1, "four cycles");
         else
            check(C_HIST + i, 0, "four cycles");
         end if;
      end loop;

      -- Writes to the other words change nothing.
      for i in C_CYCLES to 16#3F# loop
         write_word(i, 16#7FFFFFFF#);
      end loop;
      check(C_CTRL, 0, "after writes to other words");
      check(C_CYCLES, 4, "after writes to other words");
      check(C_MAX, 7, "after writes to other words");
      check(C_HIST + 2, 2, "after writes to other words");

      -- Run without a clear: after the write of 1, four cycles with no word
      -- in the buffer count: the read of FS_CTRL, two more, and the write of
      -- 0.
      write_word(C_CTRL, 1);
      check(C_CTRL, 1, "running again");
      clocks(2);
      write_word(C_CTRL, 0);
      check(C_CYCLES, 8, "running again");
      check(C_MIN, 0, "running again");
      check(C_MAX, 7, "running again");
      check(C_STARVE, 1, "running again");
      check(C_HIST, 4, "running again");
      check(C_HIST + 2, 2, "running again");
      check(C_HIST + 5, 1, "running again");

      -- Reset clears the counters and runs them: the read of FS_CTRL and
      -- the write that stops them.
      rst <= '1';
      clocks(1);
      rst <= '0';
      check(C_CTRL, 1, "after a second reset");
      write_word(C_CTRL, 0);
      check(C_CYCLES, 2, "after a second reset");
      check(C_MAX, 0, "after a second reset");
      check(C_STARVE, 0, "after a second reset");
      check_hist(0, 2, 0, 2, "after a second reset");

      -- Without G_ENABLE, every word reads 0.
      access_word(1, '1', C_CTRL, X"00000003", q_v);
      clocks(3);
      for i in 0 to 63 loop
         check(1, i, 0, "without G_ENABLE");
      end loop;

      report "tb_fetch_stats: all checks passed";
      stop(0);
   end process p_test;

end architecture simulation;
