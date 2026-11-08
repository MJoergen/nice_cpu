-- A self-checking test of src/tod.vhd, the clock of the time of day.
--
-- THEORY OF OPERATION
-- The clock runs at G_CLK_HZ = 2 MHz, so it counts one microsecond in
-- every second cycle. A write of CLOCK_USEC clears the accumulator, so
-- after a write of v at one clock edge, reads accepted at the next edges
-- return v, v, v + 1, v + 1, and so on. The checks:
-- * After reset, every word reads 0.
-- * Writes of the seconds stage them, and change neither the clock nor
--   the snapshot.
-- * A write of CLOCK_USEC sets the clock to the staged seconds and sets
--   "set". The clock counts one microsecond in two cycles.
-- * A read of CLOCK_USEC takes the snapshot of the seconds, which the
--   reads of CLOCK_SEC_LO and CLOCK_SEC_HI return, and a second ends
--   after 999999.
-- * A write of CLOCK_STATUS clears "set".
-- * A write of CLOCK_USEC of 1000000 or more sets 999999.
-- * The seconds wrap from 2^64 - 1 to 0.
-- * A count of many cycles gives one microsecond per two cycles.
-- * Reset sets the clock, the snapshot, the staged seconds, and "set" to 0.
-- The run stops with status 0 when every check passes, and 1 at the first
-- that fails.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use std.env.all;

entity tb_tod is
end entity tb_tod;

architecture simulation of tb_tod is

   constant C_USEC   : natural := 0;
   constant C_SEC_LO : natural := 1;
   constant C_SEC_HI : natural := 2;
   constant C_STATUS : natural := 3;

   signal clk : std_logic;
   signal rst : std_logic := '1';

   signal cyc      : std_logic                     := '0';
   signal stb      : std_logic                     := '0';
   signal stall    : std_logic;
   signal ack      : std_logic;
   signal we       : std_logic                     := '0';
   signal addr     : std_logic_vector(1 downto 0)  := (others => '0');
   signal data_out : std_logic_vector(31 downto 0) := (others => '0');
   signal data_in  : std_logic_vector(31 downto 0);

begin

   p_clk : process
   begin
      clk <= '1', '0' after 5 ns;
      wait for 10 ns;
   end process p_clk;


   i_tod : entity work.tod
      generic map (
         G_CLK_HZ => 2000000
      )
      port map (
         clk_i      => clk,
         rst_i      => rst,
         wb_cyc_i   => cyc,
         wb_stb_i   => stb,
         wb_stall_o => stall,
         wb_ack_o   => ack,
         wb_we_i    => we,
         wb_addr_i  => addr,
         wb_data_i  => data_out,
         wb_data_o  => data_in
      ); -- i_tod


   p_test : process

      procedure fail(msg : string) is
      begin
         report "tb_tod: " & msg
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
         addr     <= to_slv(a, 2);
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

      procedure check_usec(want : natural; what : string) is
      begin
         check(C_USEC, to_slv(want, 32), what);
      end procedure check_usec;

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

      check_usec(0, "after reset");
      check(C_SEC_LO, X"00000000", "after reset");
      check(C_SEC_HI, X"00000000", "after reset");
      check(C_STATUS, X"00000000", "after reset");

      -- Staging changes neither the snapshot nor "set".
      write_word(C_SEC_LO, X"12345678");
      write_word(C_SEC_HI, X"00000009");
      check(C_SEC_LO, X"00000000", "the snapshot after staging");
      check(C_SEC_HI, X"00000000", "the snapshot after staging");
      check(C_STATUS, X"00000000", "after staging");

      -- Set to 0x9_12345678 s 999998 us. The reads see 999998, then the
      -- seconds of that read, then 999999, then the next second.
      write_word(C_USEC, to_slv(999998, 32));
      check_usec(999998, "right after the write");
      check(C_SEC_LO, X"12345678", "the seconds set");
      check(C_SEC_HI, X"00000009", "the seconds set");
      check_usec(999999, "two cycles on");
      check(C_SEC_LO, X"12345678", "the snapshot at 999999");
      check_usec(0, "four cycles on");
      check(C_SEC_LO, X"12345679", "the next second");
      check(C_SEC_HI, X"00000009", "the next second");
      check(C_STATUS, X"00000001", "after the set");

      write_word(C_STATUS, X"00000001");
      check(C_STATUS, X"00000000", "after a write of the status");

      -- 0xFFFFFFFF sets 999999, with the seconds still staged.
      write_word(C_USEC, X"FFFFFFFF");
      check_usec(999999, "the most");
      check(C_SEC_LO, X"12345678", "the seconds still staged");
      check(C_STATUS, X"00000001", "set again");

      -- The wrap of the seconds.
      write_word(C_SEC_LO, X"FFFFFFFF");
      write_word(C_SEC_HI, X"FFFFFFFF");
      write_word(C_USEC, to_slv(999999, 32));
      check_usec(999999, "the last microsecond");
      check(C_SEC_HI, X"FFFFFFFF", "the last second");
      check_usec(0, "after the wrap");
      check(C_SEC_HI, X"00000000", "after the wrap");
      check(C_SEC_LO, X"00000000", "after the wrap");

      -- 19 cycles after the write, a read accepted at the 20th edge sees
      -- the counts at edges 2, 4, ..., 18.
      write_word(C_USEC, X"00000000");
      clocks(19);
      check_usec(9, "after 20 cycles");
      clocks(1999);
      check_usec(1009, "after 2020 cycles");

      -- Reset clears everything, the staged seconds too.
      rst <= '1';
      clocks(1);
      rst <= '0';
      check_usec(0, "after a second reset");
      check(C_SEC_LO, X"00000000", "after a second reset");
      check(C_STATUS, X"00000000", "after a second reset");
      write_word(C_USEC, X"00000005");
      check_usec(5, "set after the reset");
      check(C_SEC_LO, X"00000000", "the staged seconds after the reset");
      check(C_SEC_HI, X"00000000", "the staged seconds after the reset");

      report "tb_tod: all checks passed";
      stop(0);
   end process p_test;

end architecture simulation;
