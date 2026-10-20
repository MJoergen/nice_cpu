-- The pipelined core with the checkers of its bus and interrupt ports, for
-- SymbiYosys. Every input is free, so the solver tries every slave, every
-- interrupt source, and every instruction stream that keeps to the
-- checkers' assumptions.
--
-- THEORY OF OPERATION
-- Besides the checkers' assertions, the core's own, in its process
-- p_check, hold here: no two instructions counted on instret_o in one
-- cycle, no read of PREPARE on the bus together with an access of WRITE,
-- and no flush while a data read waits to be issued or its data is owed.
-- The last is the data access rule of MICROARCH.md §9: every data read
-- belongs to an instruction that retires. So do the properties of FETCH
-- under G_FORMAL, and a halted core makes no request, as
-- formal_multicycle asserts of the multi-cycle core. The pipeline is too
-- deep for k-induction without many invariants, so pipeline.sby checks a
-- bounded number of cycles from reset.
--
-- RESET
-- The first cycle is a reset, so the core starts from the state of
-- ISA.md §8.1.

library ieee;
   use ieee.std_logic_1164.all;

   use work.trace_pkg.all;

entity formal_pipeline is
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
end entity formal_pipeline;

architecture synthesis of formal_pipeline is

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
   signal ibus_wait : natural range 0 to 9;
   signal dbus_wait : natural range 0 to 5;

begin

   -- psl default clock is rising_edge(clk_i);
   -- psl f_initial_reset : assume rst_i;

   -- A halted core makes no data access, and no new instruction fetch: a
   -- request still on the instruction bus is one the bus stalled before
   -- the halt (src/pipe_fetch.vhd, f_stop).
   -- psl f_halt_dbus : assert always (rst_i = '0' and halted = '1') -> dbus_stb = '0';
   -- psl f_halt_ibus : assert always (rst_i = '0' and halted = '1' and ibus_stb = '1') ->
   --    (prev(ibus_stb) = '1' and prev(ibus_stall_i) = '1');

   -- How deep the bounded check must go to see an instruction retire, a
   -- store, and a halt.
   -- psl c_retire : cover {retire.valid = '1' and rst_i = '0'};
   -- psl c_store : cover {dbus_stb = '1' and dbus_we = '1' and rst_i = '0'};
   -- psl c_halt : cover {halted = '1' and rst_i = '0'};


   i_pipeline : entity work.pipeline
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
         retire_o     => retire,
         stats_o      => open
      ); -- i_pipeline


   i_ibus_check : entity work.wb_master_check
      generic map (
         G_MAX_PENDING => 8,
         G_ADDR_SIZE   => 31,
         G_DATA_SIZE   => 64,
         G_READ_ONLY   => true
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
      generic map (
         G_MAX_PENDING => 4
      )
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
