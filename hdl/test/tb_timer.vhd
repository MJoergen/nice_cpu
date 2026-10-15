-- A self-checking test of src/timer.vhd.
--
-- THEORY OF OPERATION
-- The timer counts clock cycles, with tick_i high, except where a check
-- needs it to stop. The checks:
-- * After reset, every word reads 0 and no request is raised.
-- * The vector keeps bits 7..0 of a write. Writes to the other words
--   change nothing.
-- * With tick_i low, the counter does not move.
-- * A write of P sets the period and the counter, and the cycle of the
--   write counts. The request comes at the end of the P-th cycle.
-- * A raised request keeps its vector, also when the vector is written and
--   later requests merge with it, until ready takes it. p_handshake checks
--   this in every cycle.
-- * A write of 0 stops the timer and leaves a raised request.
-- * With P = 1 and ready high in every cycle, a new request is raised in
--   the cycle that ready takes the last one.
-- * Reset drops a raised request and sets the words to 0.
-- The run stops with status 0 when every check passes, and 1 at the first
-- that fails.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use std.env.all;

entity tb_timer is
end entity tb_timer;

architecture simulation of tb_timer is

   constant C_PERIOD : natural := 0;
   constant C_COUNT  : natural := 1;
   constant C_VECTOR : natural := 2;

   signal clk : std_logic;
   signal rst : std_logic := '1';

   signal tick       : std_logic                     := '1';
   signal cyc        : std_logic                     := '0';
   signal stb        : std_logic                     := '0';
   signal stall      : std_logic;
   signal ack        : std_logic;
   signal we         : std_logic                     := '0';
   signal addr       : std_logic_vector(3 downto 0)  := (others => '0');
   signal data_out   : std_logic_vector(31 downto 0) := (others => '0');
   signal data_in    : std_logic_vector(31 downto 0);
   signal irq_valid  : std_logic;
   signal irq_ready  : std_logic                     := '0';
   signal irq_vector : std_logic_vector(7 downto 0);

begin

   p_clk : process
   begin
      clk <= '1', '0' after 5 ns;
      wait for 10 ns;
   end process p_clk;


   i_timer : entity work.timer
      port map (
         clk_i        => clk,
         rst_i        => rst,
         tick_i       => tick,
         wb_cyc_i     => cyc,
         wb_stb_i     => stb,
         wb_stall_o   => stall,
         wb_ack_o     => ack,
         wb_we_i      => we,
         wb_addr_i    => addr,
         wb_data_i    => data_out,
         wb_data_o    => data_in,
         irq_valid_o  => irq_valid,
         irq_ready_i  => irq_ready,
         irq_vector_o => irq_vector
      ); -- i_timer


   -- The source side of the valid/ready handshake, as the core expects it:
   -- a raised request stays raised, with its vector, until it is taken.
   p_handshake : process (clk)
      variable held_v   : boolean := false;
      variable vector_v : std_logic_vector(7 downto 0);
   begin
      if rising_edge(clk) then
         if held_v and rst = '0' then
            assert irq_valid = '1' and irq_vector = vector_v
               report "tb_timer: a request changed before it was taken"
               severity failure;
         end if;
         held_v   := irq_valid = '1' and irq_ready = '0' and rst = '0';
         vector_v := irq_vector;
      end if;
   end process p_handshake;


   p_test : process

      procedure fail(msg : string) is
      begin
         report "tb_timer: " & msg
            severity error;
         stop(1);
      end procedure fail;

      -- A request, accepted at the next clock edge. Right after that edge,
      -- ACK is high and the data holds the word as it was before the edge.
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

      procedure write_word(a : natural; d : std_logic_vector(31 downto 0)) is
         variable q_v : std_logic_vector(31 downto 0);
      begin
         access_word('1', a, d, q_v);
      end procedure write_word;

      procedure check(a : natural; want : std_logic_vector(31 downto 0); what : string) is
         variable got_v : std_logic_vector(31 downto 0);
      begin
         access_word('0', a, X"00000000", got_v);
         if got_v /= want then
            fail(what & ": word " & integer'image(a) & " = " & to_hstring(got_v) &
                 ", expected " & to_hstring(want));
         end if;
      end procedure check;

      procedure check_irq(valid : std_logic; vector : std_logic_vector(7 downto 0);
                          what  : string) is
      begin
         if irq_valid /= valid then
            fail(what & ": valid is " & std_logic'image(irq_valid));
         end if;
         if valid = '1' and irq_vector /= vector then
            fail(what & ": the vector is " & to_hstring(irq_vector));
         end if;
      end procedure check_irq;

      procedure clocks(n : natural) is
      begin
         for i in 1 to n loop
            wait until rising_edge(clk);
         end loop;
         wait for 1 ns;
      end procedure clocks;

   begin
      clocks(2);
      rst <= '0';

      for i in 0 to 15 loop
         check(i, X"00000000", "after reset");
      end loop;
      check_irq('0', X"00", "after reset");

      write_word(C_VECTOR, X"00001234");
      check(C_VECTOR, X"00000034", "the vector");
      for i in 3 to 15 loop
         write_word(i, X"DEADBEEF");
      end loop;
      write_word(C_COUNT, X"DEADBEEF");
      check(C_COUNT, X"00000000", "after writes to the count");
      for i in 3 to 15 loop
         check(i, X"00000000", "a spare word after writes");
      end loop;

      -- Without ticks, the write sets the counter and nothing moves.
      tick <= '0';
      write_word(C_PERIOD, X"00000005");
      clocks(3);
      check(C_COUNT, X"00000005", "without ticks");
      check(C_PERIOD, X"00000005", "the period");
      check_irq('0', X"00", "without ticks");

      -- P = 3: the write's cycle and the next two.
      tick <= '1';
      write_word(C_PERIOD, X"00000003");
      check(C_COUNT, X"00000002", "the cycle after the write");
      check_irq('0', X"00", "two cycles of three");
      clocks(1);
      check_irq('1', X"34", "three cycles of three");
      check(C_COUNT, X"00000003", "the cycle after the request");

      -- The request waits, and keeps its vector through later requests.
      write_word(C_VECTOR, X"00000056");
      clocks(7);
      check_irq('1', X"34", "after more requests");

      -- Stopping the timer leaves the request. Ready takes it.
      write_word(C_PERIOD, X"00000000");
      check(C_COUNT, X"00000000", "after the stop");
      clocks(5);
      check_irq('1', X"34", "after the stop");
      irq_ready <= '1';
      clocks(1);
      irq_ready <= '0';
      check_irq('0', X"00", "after ready");
      clocks(5);
      check_irq('0', X"00", "stopped");

      -- P = 1: a request at the end of the write's cycle, and one in every
      -- cycle that ready takes the last.
      write_word(C_PERIOD, X"00000001");
      check_irq('1', X"56", "P = 1");
      irq_ready <= '1';
      for i in 1 to 5 loop
         clocks(1);
         check_irq('1', X"56", "P = 1 with ready");
      end loop;
      irq_ready <= '0';

      -- Reset drops the request and clears the words.
      rst <= '1';
      clocks(1);
      rst <= '0';
      check_irq('0', X"00", "after a second reset");
      check(C_PERIOD, X"00000000", "after a second reset");
      check(C_COUNT, X"00000000", "after a second reset");
      check(C_VECTOR, X"00000000", "after a second reset");
      check_irq('0', X"00", "after a second reset");

      report "tb_timer: all checks passed";
      stop(0);
   end process p_test;

end architecture simulation;
