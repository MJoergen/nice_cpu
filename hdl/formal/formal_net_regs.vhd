-- The registers of the network station with checks of their ports, for
-- SymbiYosys. Every input is free, so the solver tries every bus master,
-- and every count and status.
--
-- THEORY OF OPERATION
-- wb_slave_check watches the bus port, which acknowledges each request in
-- the next cycle, and nothing else. The assertions say that a write to an
-- address sets it, with wr_o high in the next cycle, and that the
-- addresses change at no other time but reset. The covers show a write of
-- each address.
--
-- RESET
-- The first cycle is a reset.

library ieee;
   use ieee.std_logic_1164.all;

entity formal_net_regs is
   port (
      clk_i       : in  std_logic;
      rst_i       : in  std_logic;
      wb_cyc_i    : in  std_logic;
      wb_stb_i    : in  std_logic;
      wb_we_i     : in  std_logic;
      wb_addr_i   : in  std_logic_vector(3 downto 0);
      wb_data_i   : in  std_logic_vector(31 downto 0);
      rx_good_i   : in  std_logic_vector(31 downto 0);
      rx_bad_i    : in  std_logic_vector(31 downto 0);
      tx_i        : in  std_logic_vector(31 downto 0);
      connected_i : in  std_logic;
      port_i      : in  std_logic_vector(15 downto 0)
   );
end entity formal_net_regs;

architecture synthesis of formal_net_regs is

   signal wb_stall : std_logic;
   signal wb_ack   : std_logic;
   signal wb_data  : std_logic_vector(31 downto 0);
   signal ip       : std_logic_vector(31 downto 0);
   signal mac      : std_logic_vector(47 downto 0);
   signal wr       : std_logic;

   -- A write to the IP address, to bits 47..32 of the MAC address, to bits
   -- 31..0, or to any of them
   signal wr_ip     : std_logic;
   signal wr_mac_hi : std_logic;
   signal wr_mac_lo : std_logic;
   signal wr_any    : std_logic;

begin

   wr_ip     <= wb_cyc_i and wb_stb_i and wb_we_i when wb_addr_i = X"0" else '0';
   wr_mac_hi <= wb_cyc_i and wb_stb_i and wb_we_i when wb_addr_i = X"1" else '0';
   wr_mac_lo <= wb_cyc_i and wb_stb_i and wb_we_i when wb_addr_i = X"2" else '0';
   wr_any    <= wr_ip or wr_mac_hi or wr_mac_lo;

   -- psl default clock is rising_edge(clk_i);
   -- psl f_initial_reset : assume rst_i;

   -- psl f_ip_wr : assert always {wr_ip and not rst_i} |=> {ip = prev(wb_data_i)};
   -- psl f_mac_hi_wr : assert always {wr_mac_hi and not rst_i} |=>
   --    {mac(47 downto 32) = prev(wb_data_i(15 downto 0)) and stable(mac(31 downto 0))};
   -- psl f_mac_lo_wr : assert always {wr_mac_lo and not rst_i} |=>
   --    {mac(31 downto 0) = prev(wb_data_i) and stable(mac(47 downto 32))};
   -- psl f_ip_keep : assert always {not wr_ip and not rst_i} |=> {stable(ip)};
   -- psl f_mac_keep : assert always {not wr_mac_hi and not wr_mac_lo and not rst_i} |=> {stable(mac)};
   -- psl f_wr : assert always {not rst_i} |=> {wr = prev(wr_any)};
   -- psl f_reset : assert always rst_i |=>
   --    {ip = X"00000000" and mac = X"024E49434500" and wr = '0'};

   -- psl c_ip : cover {wr_ip and not rst_i; wr};
   -- psl c_mac : cover {wr_mac_hi and not rst_i; wr_mac_lo; wr};


   i_net_regs : entity work.net_regs
      port map (
         clk_i       => clk_i,
         rst_i       => rst_i,
         wb_cyc_i    => wb_cyc_i,
         wb_stb_i    => wb_stb_i,
         wb_stall_o  => wb_stall,
         wb_ack_o    => wb_ack,
         wb_we_i     => wb_we_i,
         wb_addr_i   => wb_addr_i,
         wb_data_i   => wb_data_i,
         wb_data_o   => wb_data,
         rx_good_i   => rx_good_i,
         rx_bad_i    => rx_bad_i,
         tx_i        => tx_i,
         connected_i => connected_i,
         port_i      => port_i,
         ip_o        => ip,
         mac_o       => mac,
         wr_o        => wr
      ); -- i_net_regs


   i_wb_slave_check : entity work.wb_slave_check
      port map (
         clk_i   => clk_i,
         rst_i   => rst_i,
         cyc_i   => wb_cyc_i,
         stb_i   => wb_stb_i,
         stall_i => wb_stall,
         ack_i   => wb_ack
      ); -- i_wb_slave_check

end architecture synthesis;
