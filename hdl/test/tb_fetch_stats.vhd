-- A self-checking test of src/fetch_stats.vhd.
--
-- THEORY OF OPERATION
-- The test drives events_i by hand, one cycle at a time, and reads the
-- counters while they are stopped. The checks:
-- * After reset the counters run, and FS_CTRL reads 1.
-- * A write of 2 to FS_CTRL clears the counters and stops them: every word
--   reads 0.
-- * A write of 3 clears them and starts them from the next cycle. Each
--   cycle until the write that stops them, that one's included, counts
--   once in FS_CYCLES and in FS_CAUSE + cause, a flush in FS_FLUSH + its
--   cause, and each other counter its events.
-- * Stopped counters keep their values, and writes to other words change
--   nothing. A write of 1 starts them again without clearing them.
-- * With run_i low, no cycle counts, and FS_CTRL still reads 1. When run_i
--   is high again, the counters go on from where they stopped.
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

   constant C_CTRL   : natural := 16#00#;
   constant C_CYCLES : natural := 16#01#;
   constant C_ISTALL : natural := 16#02#;
   constant C_DSTALL : natural := 16#03#;
   constant C_JUMPS  : natural := 16#04#;
   constant C_FLUSH  : natural := 16#08#;
   constant C_CAUSE  : natural := 16#10#;

   signal clk : std_logic;
   signal rst : std_logic := '1';
   signal run : std_logic := '1';

   signal events   : t_fetch_events                := C_FETCH_EVENTS_NONE;
   signal cyc      : std_logic                     := '0';
   signal stb      : std_logic_vector(0 to 1)      := "00";
   signal stall    : std_logic_vector(0 to 1);
   signal ack      : std_logic_vector(0 to 1);
   signal we       : std_logic                     := '0';
   signal addr     : std_logic_vector(4 downto 0)  := (others => '0');
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
         run_i      => run,
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
         addr     <= to_slv(a, 5);
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
      procedure cycle(cause  : natural;
                      istall : std_logic := '0';
                      dstall : std_logic := '0';
                      jump   : std_logic := '0';
                      flush  : std_logic := '0';
                      fwhy   : natural   := 0) is
      begin
         events.cause  <= cause;
         events.istall <= istall;
         events.dstall <= dstall;
         events.jump   <= jump;
         events.flush  <= flush;
         events.fwhy   <= fwhy;
         clocks(1);
      end procedure cycle;

      -- Every cause but a and b reads 0.
      procedure check_causes(a : natural; na : natural; b : natural; nb : natural;
                             what : string) is
      begin
         for i in 0 to C_CAUSES - 1 loop
            if i = a then
               check(C_CAUSE + i, na, what);
            elsif i = b then
               check(C_CAUSE + i, nb, what);
            else
               check(C_CAUSE + i, 0, what);
            end if;
         end loop;
      end procedure check_causes;

      variable q_v : std_logic_vector(31 downto 0);

   begin
      clocks(2);
      rst <= '0';

      -- After reset the counters run.
      check(C_CTRL, 1, "after reset");

      -- Clear and stop. Every word reads 0, the spare ones too.
      write_word(C_CTRL, 2);
      check(C_CTRL, 0, "stopped");
      for i in 1 to 31 loop
         check(i, 0, "cleared");
      end loop;

      -- Clear and run, from the cycle after the write. Four cycles count:
      -- A, B, C, and C again at the write that stops the counters.
      write_word(C_CTRL, 3);
      cycle(C_CAUSE_RETIRE, istall => '1', flush => '1', fwhy => C_FLUSH_STORE);
      cycle(C_CAUSE_READ, dstall => '1', jump => '1');
      cycle(C_CAUSE_REFILL, istall => '1', flush => '1', fwhy => C_FLUSH_JUMP);
      write_word(C_CTRL, 0);
      events <= C_FETCH_EVENTS_NONE;
      clocks(5);

      check(C_CYCLES, 4, "four cycles");
      check(C_ISTALL, 3, "four cycles");
      check(C_DSTALL, 1, "four cycles");
      check(C_JUMPS, 1, "four cycles");
      for i in 0 to C_FLUSHES - 1 loop
         if i = C_FLUSH_JUMP then
            check(C_FLUSH + i, 2, "four cycles");
         elsif i = C_FLUSH_STORE then
            check(C_FLUSH + i, 1, "four cycles");
         else
            check(C_FLUSH + i, 0, "four cycles");
         end if;
      end loop;
      for i in 0 to C_CAUSES - 1 loop
         if i = C_CAUSE_REFILL then
            check(C_CAUSE + i, 2, "four cycles");
         elsif i = C_CAUSE_RETIRE or i = C_CAUSE_READ then
            check(C_CAUSE + i, 1, "four cycles");
         else
            check(C_CAUSE + i, 0, "four cycles");
         end if;
      end loop;
      for i in 5 to 7 loop
         check(i, 0, "a spare word");
      end loop;
      for i in C_FLUSH + C_FLUSHES to C_CAUSE - 1 loop
         check(i, 0, "a spare word");
      end loop;
      check(C_CAUSE + C_CAUSES, 0, "a spare word");

      -- Writes to the other words change nothing.
      for i in C_CYCLES to 31 loop
         write_word(i, 16#7FFFFFFF#);
      end loop;
      check(C_CTRL, 0, "after writes to other words");
      check(C_CYCLES, 4, "after writes to other words");
      check(C_FLUSH + C_FLUSH_JUMP, 2, "after writes to other words");
      check(C_CAUSE + C_CAUSE_REFILL, 2, "after writes to other words");

      -- Run without a clear: after the write of 1, four cycles of the
      -- cause OTHER count: the read of FS_CTRL, two more, and the write
      -- of 0.
      write_word(C_CTRL, 1);
      check(C_CTRL, 1, "running again");
      clocks(2);
      write_word(C_CTRL, 0);
      check(C_CYCLES, 8, "running again");
      check(C_ISTALL, 3, "running again");
      check(C_CAUSE + C_CAUSE_OTHER, 4, "running again");
      check(C_CAUSE + C_CAUSE_REFILL, 2, "running again");

      -- With run_i low, no cycle counts, though R is 1. When run_i is high
      -- again, three cycles of the cause OTHER count: two, and the write
      -- of 0.
      run <= '0';
      write_word(C_CTRL, 1);
      cycle(C_CAUSE_FETCH, istall => '1', jump => '1', flush => '1', fwhy => C_FLUSH_INTR);
      cycle(C_CAUSE_FETCH, dstall => '1');
      events <= C_FETCH_EVENTS_NONE;
      clocks(5);
      check(C_CTRL, 1, "run_i low");
      check(C_CYCLES, 8, "run_i low");
      check(C_ISTALL, 3, "run_i low");
      check(C_DSTALL, 1, "run_i low");
      check(C_JUMPS, 1, "run_i low");
      check(C_FLUSH + C_FLUSH_INTR, 0, "run_i low");
      check(C_CAUSE + C_CAUSE_FETCH, 0, "run_i low");
      run <= '1';
      clocks(2);
      write_word(C_CTRL, 0);
      check(C_CYCLES, 11, "run_i high again");
      check(C_CAUSE + C_CAUSE_OTHER, 7, "run_i high again");
      check(C_CAUSE + C_CAUSE_FETCH, 0, "run_i high again");

      -- Reset clears the counters and runs them: the read of FS_CTRL and
      -- the write that stops them.
      rst <= '1';
      clocks(1);
      rst <= '0';
      check(C_CTRL, 1, "after a second reset");
      write_word(C_CTRL, 0);
      check(C_CYCLES, 2, "after a second reset");
      check(C_ISTALL, 0, "after a second reset");
      check(C_FLUSH + C_FLUSH_JUMP, 0, "after a second reset");
      check_causes(C_CAUSE_OTHER, 2, C_CAUSE_OTHER, 2, "after a second reset");

      -- Without G_ENABLE, every word reads 0.
      access_word(1, '1', C_CTRL, X"00000003", q_v);
      clocks(3);
      for i in 0 to 31 loop
         check(1, i, 0, "without G_ENABLE");
      end loop;

      report "tb_fetch_stats: all checks passed";
      stop(0);
   end process p_test;

end architecture simulation;
