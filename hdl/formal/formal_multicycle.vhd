-- The multi-cycle core with the checkers of its bus and interrupt ports,
-- for SymbiYosys. Every input is free, so the solver tries every slave,
-- every interrupt source, and every instruction stream that keeps to the
-- checkers' assumptions.
--
-- RESET
-- The first cycle is a reset, so the core starts from the state of
-- ISA.md §8.1.

library ieee;
   use ieee.std_logic_1164.all;

   use work.trace_pkg.all;

entity formal_multicycle is
   port (
      clk_i        : in  std_logic;
      rst_i        : in  std_logic;
      ibus_stall_i : in  std_logic;
      ibus_ack_i   : in  std_logic;
      ibus_data_i  : in  std_logic_vector(63 downto 0);
      dbus_stall_i : in  std_logic;
      dbus_ack_i   : in  std_logic;
      dbus_data_i  : in  std_logic_vector(31 downto 0);
      nmi_valid_i  : in  std_logic;
      nmi_vector_i : in  std_logic_vector(7 downto 0);
      irq_valid_i  : in  std_logic;
      irq_vector_i : in  std_logic_vector(7 downto 0)
   );
end entity formal_multicycle;

architecture synthesis of formal_multicycle is

   signal ibus_cyc  : std_logic;
   signal ibus_stb  : std_logic;
   signal ibus_addr : std_logic_vector(30 downto 0);
   signal dbus_cyc  : std_logic;
   signal dbus_stb  : std_logic;
   signal dbus_we   : std_logic;
   signal dbus_addr : std_logic_vector(31 downto 0);
   signal dbus_data : std_logic_vector(31 downto 0);
   signal nmi_ready : std_logic;
   signal irq_ready : std_logic;
   signal halted    : std_logic;
   signal instret   : std_logic;
   signal retire    : t_retire;
   signal ibus_wait : natural range 0 to 2;
   signal dbus_wait : natural range 0 to 2;

begin

   -- psl default clock is rising_edge(clk_i);
   -- psl f_initial_reset : assume rst_i;

   -- The core makes one request at a time, and holds CYC until its ACK. So
   -- a request waits for its ACK exactly while CYC is high and STB low.
   -- psl f_ibus_wait : assert always rst_i = '0' ->
   --    (ibus_wait = 1) = (ibus_cyc = '1' and ibus_stb = '0');
   -- psl f_dbus_wait : assert always rst_i = '0' ->
   --    (dbus_wait = 1) = (dbus_cyc = '1' and dbus_stb = '0');


   i_multicycle : entity work.multicycle
      generic map (
         G_FORMAL => true
      )
      port map (
         clk_i        => clk_i,
         rst_i        => rst_i,
         ibus_cyc_o   => ibus_cyc,
         ibus_stb_o   => ibus_stb,
         ibus_stall_i => ibus_stall_i,
         ibus_ack_i   => ibus_ack_i,
         ibus_addr_o  => ibus_addr,
         ibus_data_i  => ibus_data_i,
         dbus_cyc_o   => dbus_cyc,
         dbus_stb_o   => dbus_stb,
         dbus_stall_i => dbus_stall_i,
         dbus_ack_i   => dbus_ack_i,
         dbus_we_o    => dbus_we,
         dbus_addr_o  => dbus_addr,
         dbus_data_o  => dbus_data,
         dbus_data_i  => dbus_data_i,
         nmi_valid_i  => nmi_valid_i,
         nmi_ready_o  => nmi_ready,
         nmi_vector_i => nmi_vector_i,
         irq_valid_i  => irq_valid_i,
         irq_ready_o  => irq_ready,
         irq_vector_i => irq_vector_i,
         halted_o     => halted,
         instret_o    => instret,
         retire_o     => retire
      ); -- i_multicycle


   i_ibus_check : entity work.wb_master_check
      generic map (
         G_ADDR_SIZE => 31,
         G_DATA_SIZE => 64,
         G_READ_ONLY => true
      )
      port map (
         clk_i     => clk_i,
         rst_i     => rst_i,
         cyc_i     => ibus_cyc,
         stb_i     => ibus_stb,
         stall_i   => ibus_stall_i,
         ack_i     => ibus_ack_i,
         we_i      => '0',
         addr_i    => ibus_addr,
         data_i    => (others => '0'),
         pending_o => ibus_wait
      ); -- i_ibus_check


   i_dbus_check : entity work.wb_master_check
      port map (
         clk_i     => clk_i,
         rst_i     => rst_i,
         cyc_i     => dbus_cyc,
         stb_i     => dbus_stb,
         stall_i   => dbus_stall_i,
         ack_i     => dbus_ack_i,
         we_i      => dbus_we,
         addr_i    => dbus_addr,
         data_i    => dbus_data,
         pending_o => dbus_wait
      ); -- i_dbus_check


   i_nmi_check : entity work.handshake_check
      generic map (
         G_DATA_SIZE => 8
      )
      port map (
         clk_i   => clk_i,
         rst_i   => rst_i,
         valid_i => nmi_valid_i,
         ready_i => nmi_ready,
         data_i  => nmi_vector_i
      ); -- i_nmi_check


   i_irq_check : entity work.handshake_check
      generic map (
         G_DATA_SIZE => 8
      )
      port map (
         clk_i   => clk_i,
         rst_i   => rst_i,
         valid_i => irq_valid_i,
         ready_i => irq_ready,
         data_i  => irq_vector_i
      ); -- i_irq_check

end architecture synthesis;
