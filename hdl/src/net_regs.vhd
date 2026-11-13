-- The registers of the network station of DEVICES.md §6: 16 words of I/O
-- that hold the station's IP and MAC addresses, and show its counts of
-- frames and the state of the debug link over TCP.
--
--   0  NET_IP        1  NET_MAC_HI    2  NET_MAC_LO    3  NET_RX_GOOD
--   4  NET_RX_BAD    5  NET_TX        6  NET_STATUS    7-15  read 0
--
-- THEORY OF OPERATION
-- NET_IP, NET_MAC_HI, and NET_MAC_LO are registers that a write sets, and
-- that drive ip_o and mac_o. NET_MAC_HI keeps bits 15..0 of a write. The
-- other words read their inputs, or 0, and ignore writes. wr_o is high in
-- the cycle after a write to an address, with ip_o and mac_o already
-- showing the new value, so that a board's station can break a connection
-- or a reply then, as DEVICES.md §6 says.
--
-- The port is a pipelined Wishbone slave. It never stalls, and it
-- acknowledges each request in the cycle after it accepts it. A read
-- returns the word as it is in the cycle the read is accepted.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) STB is high only for requests to the station: the bus decoder decodes
--    the address bits above bit 3.
-- b) rst_i is the reset of the system, not the reset that a start of the
--    processor gives the other devices (DEBUG.md §6), as the station keeps
--    its addresses across a start.
-- c) The counts and the status inputs are in the clock domain of clk_i. A
--    system without them ties them to 0, as the emulator reads 0 there.
--
-- RESET
-- Synchronous. It sets the IP address to 0, and the MAC address to G_MAC,
-- 02:4E:49:43:45:00 by default, and drops any ACK owed and wr_o.

library ieee;
   use ieee.std_logic_1164.all;

entity net_regs is
   generic (
      G_MAC : std_logic_vector(47 downto 0) := X"024E49434500"
   );
   port (
      clk_i       : in  std_logic;
      rst_i       : in  std_logic;

      wb_cyc_i    : in  std_logic;
      wb_stb_i    : in  std_logic;
      wb_stall_o  : out std_logic;
      wb_ack_o    : out std_logic                     := '0';
      wb_we_i     : in  std_logic;
      wb_addr_i   : in  std_logic_vector(3 downto 0);
      wb_data_i   : in  std_logic_vector(31 downto 0);
      wb_data_o   : out std_logic_vector(31 downto 0) := (others => '0');

      -- The counts of frames: good ones received, bad or dropped ones
      -- received, and ones sent
      rx_good_i   : in  std_logic_vector(31 downto 0);
      rx_bad_i    : in  std_logic_vector(31 downto 0);
      tx_i        : in  std_logic_vector(31 downto 0);

      -- The debug link over TCP: a host is connected, and its port
      connected_i : in  std_logic;
      port_i      : in  std_logic_vector(15 downto 0);

      -- The addresses, and a write to one of them
      ip_o        : out std_logic_vector(31 downto 0);
      mac_o       : out std_logic_vector(47 downto 0);
      wr_o        : out std_logic                     := '0'
   );
end entity net_regs;

architecture synthesis of net_regs is

   signal ip_r  : std_logic_vector(31 downto 0) := (others => '0');
   signal mac_r : std_logic_vector(47 downto 0) := G_MAC;

   signal accept : std_logic;

begin

   accept     <= wb_cyc_i and wb_stb_i;
   wb_stall_o <= '0';
   ip_o       <= ip_r;
   mac_o      <= mac_r;


   p_regs : process (clk_i)
   begin
      if rising_edge(clk_i) then
         wb_ack_o <= accept;
         wr_o     <= '0';

         if accept = '1' and wb_we_i = '0' then
            case wb_addr_i is
               when X"0"   => wb_data_o <= ip_r;
               when X"1"   => wb_data_o <= X"0000" & mac_r(47 downto 32);
               when X"2"   => wb_data_o <= mac_r(31 downto 0);
               when X"3"   => wb_data_o <= rx_good_i;
               when X"4"   => wb_data_o <= rx_bad_i;
               when X"5"   => wb_data_o <= tx_i;
               when X"6"   => wb_data_o <= connected_i & "000" & X"000" & port_i;
               when others => wb_data_o <= (others => '0');
            end case;
         end if;

         if accept = '1' and wb_we_i = '1' then
            case wb_addr_i is
               when X"0" =>
                  ip_r <= wb_data_i;
                  wr_o <= '1';

               when X"1" =>
                  mac_r(47 downto 32) <= wb_data_i(15 downto 0);
                  wr_o                <= '1';

               when X"2" =>
                  mac_r(31 downto 0) <= wb_data_i;
                  wr_o               <= '1';

               when others =>
                  null;
            end case;
         end if;

         if rst_i = '1' then
            wb_ack_o <= '0';
            wr_o     <= '0';
            ip_r     <= (others => '0');
            mac_r    <= G_MAC;
         end if;
      end if;
   end process p_regs;

end architecture synthesis;
