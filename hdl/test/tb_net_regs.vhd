-- A self-checking test of src/net_regs.vhd.
--
-- THEORY OF OPERATION
-- The checks:
-- * After reset, NET_IP reads 0, the MAC address 02:4E:49:43:45:00, and
--   the other words what their inputs hold, or 0.
-- * The counts and NET_STATUS follow their inputs: bit 31 the connection,
--   bits 15..0 the port, and bits 30..16 read 0.
-- * A write sets the IP address, bits 15..0 of NET_MAC_HI, and NET_MAC_LO,
--   and ip_o and mac_o show them. wr_o is high for one cycle after each,
--   and not after a write to another word.
-- * Writes to the other words change nothing.
-- * Reset sets the addresses back.
-- The run stops with status 0 when every check passes, and 1 at the first
-- that fails.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use std.env.all;

entity tb_net_regs is
end entity tb_net_regs;

architecture simulation of tb_net_regs is

   constant C_IP      : natural := 0;
   constant C_MAC_HI  : natural := 1;
   constant C_MAC_LO  : natural := 2;
   constant C_RX_GOOD : natural := 3;
   constant C_RX_BAD  : natural := 4;
   constant C_TX      : natural := 5;
   constant C_STATUS  : natural := 6;

   signal clk : std_logic;
   signal rst : std_logic := '1';

   signal cyc       : std_logic                     := '0';
   signal stb       : std_logic                     := '0';
   signal stall     : std_logic;
   signal ack       : std_logic;
   signal we        : std_logic                     := '0';
   signal addr      : std_logic_vector(3 downto 0)  := (others => '0');
   signal data_out  : std_logic_vector(31 downto 0) := (others => '0');
   signal data_in   : std_logic_vector(31 downto 0);
   signal rx_good   : std_logic_vector(31 downto 0) := X"00000011";
   signal rx_bad    : std_logic_vector(31 downto 0) := X"00000022";
   signal tx        : std_logic_vector(31 downto 0) := X"00000033";
   signal connected : std_logic                     := '0';
   signal port_in   : std_logic_vector(15 downto 0) := X"119E";
   signal ip        : std_logic_vector(31 downto 0);
   signal mac       : std_logic_vector(47 downto 0);
   signal wr        : std_logic;

begin

   p_clk : process
   begin
      clk <= '1', '0' after 5 ns;
      wait for 10 ns;
   end process p_clk;


   i_net_regs : entity work.net_regs
      port map (
         clk_i       => clk,
         rst_i       => rst,
         wb_cyc_i    => cyc,
         wb_stb_i    => stb,
         wb_stall_o  => stall,
         wb_ack_o    => ack,
         wb_we_i     => we,
         wb_addr_i   => addr,
         wb_data_i   => data_out,
         wb_data_o   => data_in,
         rx_good_i   => rx_good,
         rx_bad_i    => rx_bad,
         tx_i        => tx,
         connected_i => connected,
         port_i      => port_in,
         ip_o        => ip,
         mac_o       => mac,
         wr_o        => wr
      ); -- i_net_regs


   p_test : process

      procedure fail(msg : string) is
      begin
         report "tb_net_regs: " & msg
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

      -- A write, and whether wr_o is high in the cycle after it, and low
      -- in the next.
      procedure write_word(a : natural; d : std_logic_vector(31 downto 0); strobe : std_logic) is
         variable q_v : std_logic_vector(31 downto 0);
      begin
         access_word('1', a, d, q_v);
         if wr /= strobe then
            fail("wr_o is " & std_logic'image(wr) & " after a write of word " & integer'image(a));
         end if;
         wait until rising_edge(clk);
         wait for 1 ns;
         if wr /= '0' then
            fail("wr_o is high for more than one cycle");
         end if;
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

      procedure check_out(want_ip : std_logic_vector(31 downto 0);
                          want_mac : std_logic_vector(47 downto 0); what : string) is
      begin
         if ip /= want_ip or mac /= want_mac then
            fail(what & ": ip_o = " & to_hstring(ip) & ", mac_o = " & to_hstring(mac));
         end if;
      end procedure check_out;

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

      check(C_IP, X"00000000", "after reset");
      check(C_MAC_HI, X"0000024E", "after reset");
      check(C_MAC_LO, X"49434500", "after reset");
      check(C_RX_GOOD, X"00000011", "the input");
      check(C_RX_BAD, X"00000022", "the input");
      check(C_TX, X"00000033", "the input");
      check(C_STATUS, X"0000119E", "not connected");
      for i in 7 to 15 loop
         check(i, X"00000000", "a spare word");
      end loop;
      check_out(X"00000000", X"024E49434500", "after reset");
      if wr /= '0' then
         fail("wr_o is high after reset");
      end if;

      connected <= '1';
      port_in   <= X"FFFF";
      check(C_STATUS, X"8000FFFF", "connected");

      write_word(C_IP, X"C0A80141", '1');
      check(C_IP, X"C0A80141", "the IP address");
      write_word(C_MAC_HI, X"ABCD1234", '1');
      check(C_MAC_HI, X"00001234", "bits 15..0");
      write_word(C_MAC_LO, X"56789ABC", '1');
      check(C_MAC_LO, X"56789ABC", "the MAC address");
      check_out(X"C0A80141", X"123456789ABC", "after writes");

      for i in 3 to 15 loop
         write_word(i, X"DEADBEEF", '0');
      end loop;
      check(C_RX_GOOD, X"00000011", "after writes");
      check(C_RX_BAD, X"00000022", "after writes");
      check(C_TX, X"00000033", "after writes");
      check(C_STATUS, X"8000FFFF", "after writes");
      for i in 7 to 15 loop
         check(i, X"00000000", "a spare word after writes");
      end loop;
      check_out(X"C0A80141", X"123456789ABC", "after writes to the other words");

      rst <= '1';
      clocks(1);
      rst <= '0';
      check(C_IP, X"00000000", "after a second reset");
      check(C_MAC_HI, X"0000024E", "after a second reset");
      check(C_MAC_LO, X"49434500", "after a second reset");
      check_out(X"00000000", X"024E49434500", "after a second reset");

      report "tb_net_regs: all checks passed";
      stop(0);
   end process p_test;

end architecture simulation;
