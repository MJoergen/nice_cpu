-- The multi-cycle core with the checkers of its bus and interrupt ports,
-- for SymbiYosys. Every input is free, so the solver tries every slave,
-- every interrupt source, every pause, and every instruction stream that
-- keeps to the checkers' assumptions.
--
-- THEORY OF OPERATION
-- core_check holds the checkers and the rules of a stopped core: the core
-- goes quiet when it halts or pauses, and stays quiet until reset or until
-- it goes on; regs_o does not change while paused; and once the core goes
-- on, it reports a step on retire_o before it pauses again (MICROARCH.md
-- §6.1). The last holds as the core does not pause while after_go is '1',
-- and only a report clears that. Two breakpoints, with free addresses and
-- enable bits: the core pauses without pause_i only when R15 was an
-- enabled breakpoint, and then stays paused until pause_i has been '1'.
-- The two assertions here tie the checkers' counts to the core's buses,
-- for the k-induction, and the cover shows a go on from a breakpoint.
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
      irq_vector_i : in  std_logic_vector(7 downto 0);
      pause_i      : in  std_logic;
      brk_addr_i   : in  t_brk_addrs;
      brk_en_i     : in  std_logic_vector(C_BREAKS_MAX - 1 downto 0)
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
   signal paused    : std_logic;
   signal halted    : std_logic;
   signal reason    : t_halt;
   signal instret   : std_logic;
   signal retire    : t_retire;
   signal regs      : t_regs;
   signal ibus_wait : natural range 0 to 2;
   signal dbus_wait : natural range 0 to 2;
   signal own       : boolean;

   constant C_BREAKS : natural := 2;

begin

   -- psl default clock is rising_edge(clk_i);
   -- psl f_initial_reset : assume rst_i;

   -- The core makes one request at a time, and holds CYC until its ACK. So
   -- a request waits for its ACK exactly while CYC is high and STB low.
   -- psl f_ibus_wait : assert always rst_i = '0' ->
   --    (ibus_wait = 1) = (ibus_cyc = '1' and ibus_stb = '0');
   -- psl f_dbus_wait : assert always rst_i = '0' ->
   --    (dbus_wait = 1) = (dbus_cyc = '1' and dbus_stb = '0');

   -- psl c_brk_go : cover {own; (paused = '1')[*]; paused = '0' and rst_i = '0'};


   i_multicycle : entity work.multicycle
      generic map (
         G_FORMAL => true,
         G_BREAKS => C_BREAKS
      )
      port map (
         clk_i         => clk_i,
         rst_i         => rst_i,
         ibus_cyc_o    => ibus_cyc,
         ibus_stb_o    => ibus_stb,
         ibus_stall_i  => ibus_stall_i,
         ibus_ack_i    => ibus_ack_i,
         ibus_addr_o   => ibus_addr,
         ibus_data_i   => ibus_data_i,
         dbus_cyc_o    => dbus_cyc,
         dbus_stb_o    => dbus_stb,
         dbus_stall_i  => dbus_stall_i,
         dbus_ack_i    => dbus_ack_i,
         dbus_we_o     => dbus_we,
         dbus_addr_o   => dbus_addr,
         dbus_data_o   => dbus_data,
         dbus_data_i   => dbus_data_i,
         nmi_valid_i   => nmi_valid_i,
         nmi_ready_o   => nmi_ready,
         nmi_vector_i  => nmi_vector_i,
         irq_valid_i   => irq_valid_i,
         irq_ready_o   => irq_ready,
         irq_vector_i  => irq_vector_i,
         pause_i       => pause_i,
         paused_o      => paused,
         brk_addr_i    => brk_addr_i,
         brk_en_i      => brk_en_i,
         halted_o      => halted,
         halt_reason_o => reason,
         instret_o     => instret,
         regs_o        => regs,
         retire_o      => retire
      ); -- i_multicycle


   i_core_check : entity work.core_check
      generic map (
         G_IBUS_PENDING => 1,
         G_DBUS_PENDING => 1,
         G_BREAKS       => C_BREAKS
      )
      port map (
         clk_i        => clk_i,
         rst_i        => rst_i,
         ibus_cyc_i   => ibus_cyc,
         ibus_stb_i   => ibus_stb,
         ibus_stall_i => ibus_stall_i,
         ibus_ack_i   => ibus_ack_i,
         ibus_addr_i  => ibus_addr,
         dbus_cyc_i   => dbus_cyc,
         dbus_stb_i   => dbus_stb,
         dbus_stall_i => dbus_stall_i,
         dbus_ack_i   => dbus_ack_i,
         dbus_we_i    => dbus_we,
         dbus_addr_i  => dbus_addr,
         dbus_data_i  => dbus_data,
         nmi_valid_i  => nmi_valid_i,
         nmi_ready_i  => nmi_ready,
         nmi_vector_i => nmi_vector_i,
         irq_valid_i  => irq_valid_i,
         irq_ready_i  => irq_ready,
         irq_vector_i => irq_vector_i,
         pause_i      => pause_i,
         paused_i     => paused,
         halted_i     => halted,
         reason_i     => reason,
         retire_i     => retire,
         regs_i       => regs,
         brk_addr_i   => brk_addr_i,
         brk_en_i     => brk_en_i,
         ibus_wait_o  => ibus_wait,
         dbus_wait_o  => dbus_wait,
         own_o        => own
      ); -- i_core_check

end architecture synthesis;
