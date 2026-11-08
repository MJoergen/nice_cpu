-- Formal properties of the ports of a core, for SymbiYosys: the checkers
-- of its two buses and its two interrupt ports, and the rules of a stopped
-- core (MICROARCH.md §6.1). Both cores have these ports, so
-- formal_multicycle and formal_pipeline share it. It watches the ports and
-- drives nothing.
--
-- THEORY OF OPERATION
-- A wb_master_check watches each bus, and a handshake_check each interrupt
-- port. Besides their assertions: the core goes quiet when it halts or
-- pauses, and stays quiet until reset or until it goes on; regs_i does not
-- change while paused, but for a write on reg_we_i, reg_idx_i, and
-- reg_data_i in a cycle with pause_i at '1', which is in regs_i the next
-- cycle with the rules of ISA.md §4.3; and once the core goes on, it reports a step on
-- retire_i, or makes a wait step on wstep_i, before it pauses again. A
-- wait step (ISA.md §7.5) comes only while waiting_i is '1', and so with
-- no request valid, and reports nothing, takes nothing, and neither pauses
-- nor halts. G_BREAKS breakpoints, with free
-- addresses and enable bits: the core pauses without pause_i only when R15
-- was an enabled breakpoint, or after a step that hit a watchpoint, which
-- wch_hit_i shows, and then stays paused until pause_i has been '1'. The
-- hits hold while the core is paused, and are gone once it goes on
-- (doc/DEBUG.md §6). The covers show a step reported, a store, a halt, a pause, a step
-- after a pause, a pause at a breakpoint, a step after a register write,
-- two wait steps, and a wait step after a pause.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) The first cycle is a reset, so the registers here start from it.

library ieee;
   use ieee.std_logic_1164.all;

   use ieee.numeric_std_unsigned.all;

   use work.nice_pkg.all;
   use work.trace_pkg.all;

entity core_check is
   generic (
      -- The most requests that wait for their ACK on each bus
      G_IBUS_PENDING : positive := 1;
      G_DBUS_PENDING : positive := 1;
      -- The breakpoints of the core
      G_BREAKS       : natural  := 2
   );
   port (
      clk_i        : in  std_logic;
      rst_i        : in  std_logic;
      ibus_cyc_i   : in  std_logic;
      ibus_stb_i   : in  std_logic;
      ibus_stall_i : in  std_logic;
      ibus_ack_i   : in  std_logic;
      ibus_addr_i  : in  std_logic_vector(30 downto 0);
      dbus_cyc_i   : in  std_logic;
      dbus_stb_i   : in  std_logic;
      dbus_stall_i : in  std_logic;
      dbus_ack_i   : in  std_logic;
      dbus_we_i    : in  std_logic;
      dbus_addr_i  : in  std_logic_vector(31 downto 0);
      dbus_data_i  : in  std_logic_vector(31 downto 0);
      nmi_valid_i  : in  std_logic;
      nmi_ready_i  : in  std_logic;
      nmi_vector_i : in  std_logic_vector(7 downto 0);
      irq_valid_i  : in  std_logic;
      irq_ready_i  : in  std_logic;
      irq_vector_i : in  std_logic_vector(7 downto 0);
      pause_i      : in  std_logic;
      paused_i     : in  std_logic;
      halted_i     : in  std_logic;
      reason_i     : in  t_halt;
      retire_i     : in  t_retire;
      wstep_i      : in  std_logic;
      waiting_i    : in  std_logic;
      regs_i       : in  t_regs;
      brk_addr_i   : in  t_brk_addrs;
      brk_en_i     : in  std_logic_vector(C_BREAKS_MAX - 1 downto 0);
      reg_we_i     : in  std_logic;
      reg_idx_i    : in  std_logic_vector(3 downto 0);
      reg_data_i   : in  std_logic_vector(31 downto 0);
      -- The watchpoints that the step before a pause hit
      wch_hit_i    : in  std_logic_vector(C_WATCHES_MAX - 1 downto 0) := (others => '0');

      -- The requests that wait for their ACK on each bus, for the
      -- invariants of a particular core
      ibus_wait_o  : out natural range 0 to G_IBUS_PENDING + 1;
      dbus_wait_o  : out natural range 0 to G_DBUS_PENDING + 1;
      -- paused_i rose while pause_i was '0' in the cycle before: a pause of
      -- the core's own
      own_o        : out boolean
   );
end entity core_check;

architecture synthesis of core_check is

   signal retire_d : t_retire := C_RETIRE_NONE;

   -- The cycle before, but for a reset then: paused_i, halted_i, pause_i,
   -- and regs_i
   signal paused_d : std_logic := '0';
   signal halted_d : std_logic := '0';
   signal pause_d  : std_logic := '0';
   signal regs_d   : t_regs;
   -- regs_d with the register write of the cycle before, if the core takes
   -- it: one while paused with pause_i at '1'
   signal regs_w   : t_regs;
   -- A register write was taken, and no step has been reported since
   signal wrote_r  : std_logic := '0';

   -- paused_i has fallen, and no step has been reported since
   signal owed_r : std_logic := '0';

   -- R15 was an enabled breakpoint in the cycle before
   signal hit_d  : std_logic := '0';
   -- The core paused without pause_i, and pause_i has been '0' since
   signal wait_r : std_logic := '0';
   signal own    : boolean;
   -- wch_hit_i in the cycle before
   signal hits_d : std_logic_vector(C_WATCHES_MAX - 1 downto 0) := (others => '0');

begin

   -- psl default clock is rising_edge(clk_i);

   -- regs_i holds the registers of a step from the cycle after its report.
   -- psl f_regs : assert always retire_d.valid = '1' -> regs_i = retire_d.regs;

   -- A halted core has no bus cycle open, and stays halted until reset. Its
   -- reason is on reason_i.
   -- psl f_halt_dbus : assert always (rst_i = '0' and halted_i = '1') ->
   --    (dbus_cyc_i = '0' and dbus_stb_i = '0');
   -- psl f_halt_ibus : assert always (rst_i = '0' and halted_i = '1') ->
   --    (ibus_cyc_i = '0' and ibus_stb_i = '0');
   -- psl f_halt_stays : assert always (rst_i = '0' and halted_d = '1') -> halted_i = '1';
   -- psl f_halt_reason : assert always rst_i = '0' -> ((halted_i = '1') = (reason_i /= HALT_NONE));

   -- A paused core stays paused while pause_i is '1', with no bus cycle
   -- open and the registers unchanged. It is never paused and halted.
   -- psl f_pause_quiet : assert always (rst_i = '0' and paused_d = '1' and pause_d = '1') ->
   --    (paused_i = '1' and ibus_cyc_i = '0' and ibus_stb_i = '0' and dbus_cyc_i = '0' and
   --     dbus_stb_i = '0');
   -- psl f_pause_regs : assert always (rst_i = '0' and paused_d = '1' and paused_i = '1') ->
   --    regs_i = regs_w;
   -- psl f_pause_halt : assert always rst_i = '0' -> not (paused_i = '1' and halted_i = '1');

   -- Once paused_i falls, a step is reported, or a wait step made, before
   -- it rises again.
   -- psl f_go_report : assert always (rst_i = '0' and owed_r = '1') -> paused_i = '0';

   -- A wait step is a cycle of a wait in which nothing else happens, and
   -- the core waits only while no request is valid, and never halted.
   -- psl f_wstep : assert always (rst_i = '0' and wstep_i = '1') ->
   --    (waiting_i = '1' and retire_i.valid = '0' and paused_i = '0' and
   --     nmi_ready_i = '0' and irq_ready_i = '0');
   -- psl f_waiting : assert always (rst_i = '0' and waiting_i = '1') ->
   --    (halted_i = '0' and nmi_valid_i = '0' and irq_valid_i = '0');
   -- psl c_wstep : cover {wstep_i = '1' and rst_i = '0'; wstep_i = '1' and rst_i = '0'};
   -- psl c_go_wait : cover {paused_i = '1' and rst_i = '0'; wstep_i = '1' and rst_i = '0'};

   -- A pause of the core's own is at a breakpoint or after a hit, and
   -- lasts until pause_i has been '1'. The hits hold while paused, and the
   -- go on clears them.
   own   <= rst_i = '0' and paused_i = '1' and paused_d = '0' and pause_d = '0';
   own_o <= own;
   -- psl f_brk_hit : assert always own -> (hit_d = '1' or wch_hit_i /= (wch_hit_i'range => '0'));
   -- psl f_wch_kept : assert always (rst_i = '0' and paused_d = '1' and paused_i = '1') ->
   --    wch_hit_i = hits_d;
   -- psl f_wch_go : assert always (rst_i = '0' and paused_d = '1' and paused_i = '0') ->
   --    wch_hit_i = (wch_hit_i'range => '0');
   -- psl f_brk_wait : assert always (rst_i = '0' and wait_r = '1') -> paused_i = '1';

   -- psl c_retire : cover {retire_i.valid = '1' and rst_i = '0'};
   -- psl c_store : cover {dbus_stb_i = '1' and dbus_we_i = '1' and rst_i = '0'};
   -- psl c_halt : cover {halted_i = '1' and rst_i = '0'};
   -- psl c_pause : cover {paused_i = '1' and rst_i = '0'};
   -- psl c_go_step : cover {owed_r = '1' and retire_i.valid = '1' and rst_i = '0'};
   -- psl c_brk : cover {own};
   -- psl c_reg_step : cover {wrote_r = '1' and retire_i.valid = '1' and rst_i = '0'};


   i_ibus_check : entity work.wb_master_check
      generic map (
         G_MAX_PENDING => G_IBUS_PENDING,
         G_ADDR_SIZE   => 31,
         G_DATA_SIZE   => 64,
         G_READ_ONLY   => true
      )
      port map (
         clk_i     => clk_i,
         rst_i     => rst_i,
         cyc_i     => ibus_cyc_i,
         stb_i     => ibus_stb_i,
         stall_i   => ibus_stall_i,
         ack_i     => ibus_ack_i,
         we_i      => '0',
         addr_i    => ibus_addr_i,
         data_i    => (others => '0'),
         pending_o => ibus_wait_o
      ); -- i_ibus_check


   i_dbus_check : entity work.wb_master_check
      generic map (
         G_MAX_PENDING => G_DBUS_PENDING
      )
      port map (
         clk_i     => clk_i,
         rst_i     => rst_i,
         cyc_i     => dbus_cyc_i,
         stb_i     => dbus_stb_i,
         stall_i   => dbus_stall_i,
         ack_i     => dbus_ack_i,
         we_i      => dbus_we_i,
         addr_i    => dbus_addr_i,
         data_i    => dbus_data_i,
         pending_o => dbus_wait_o
      ); -- i_dbus_check


   i_nmi_check : entity work.handshake_check
      generic map (
         G_DATA_SIZE => 8
      )
      port map (
         clk_i   => clk_i,
         rst_i   => rst_i,
         valid_i => nmi_valid_i,
         ready_i => nmi_ready_i,
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
         ready_i => irq_ready_i,
         data_i  => irq_vector_i
      ); -- i_irq_check


   -- The step reported in the cycle before, but for one in a reset, the
   -- signals of the cycle before, owed_r, hit_d, and wait_r
   p_retire_d : process (clk_i)
   begin
      if rising_edge(clk_i) then
         retire_d <= retire_i;
         paused_d <= paused_i and not rst_i;
         halted_d <= halted_i and not rst_i;
         pause_d  <= pause_i and not rst_i;
         regs_d   <= regs_i;
         regs_w   <= regs_i;
         if reg_we_i = '1' and paused_i = '1' and pause_i = '1' then
            regs_w(to_integer(reg_idx_i)) <= regval(to_integer(reg_idx_i), reg_data_i);
            wrote_r                       <= '1';
         elsif retire_i.valid = '1' then
            wrote_r <= '0';
         end if;
         hits_d   <= wch_hit_i;
         hit_d    <= '0';
         for i in 0 to G_BREAKS - 1 loop
            if brk_en_i(i) = '1' and brk_addr_i(i) = regs_i(15) then
               hit_d <= '1';
            end if;
         end loop;
         if pause_i = '1' then
            wait_r <= '0';
         elsif own then
            wait_r <= '1';
         end if;
         if retire_i.valid = '1' or wstep_i = '1' then
            owed_r <= '0';
         elsif paused_d = '1' and paused_i = '0' then
            owed_r <= '1';
         end if;
         if rst_i = '1' then
            retire_d.valid <= '0';
            owed_r         <= '0';
            wait_r         <= '0';
            wrote_r        <= '0';
         end if;
      end if;
   end process p_retire_d;

end architecture synthesis;
