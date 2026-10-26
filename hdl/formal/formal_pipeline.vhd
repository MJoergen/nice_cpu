-- The pipelined core with the checkers of its bus and interrupt ports, for
-- SymbiYosys. Every input is free, so the solver tries every slave, every
-- interrupt source, every pause, and every instruction stream that keeps
-- to the checkers' assumptions.
--
-- THEORY OF OPERATION
-- Besides the checkers' assertions, the core's own, in its process
-- p_check, hold here: no two instructions counted on instret_o in one
-- cycle, no read of PREPARE on the bus together with an access of WRITE,
-- and no flush while a data read waits to be issued or its data is owed.
-- The last is the data access rule of MICROARCH.md §9: every data read
-- belongs to an instruction that retires. So do the properties of FETCH
-- under G_FORMAL, and the properties of the halt and the pause that
-- formal_multicycle proves of the multi-cycle core: the core goes quiet
-- when it halts or pauses and stays quiet until reset or until it goes
-- on, regs_o does not change while paused, and once the core goes on it
-- reports a step before it pauses again. Two breakpoints, with free
-- addresses and enable bits that change only in a reset, as a change
-- while the core runs may miss an instruction (src/pipeline.vhd): the
-- core pauses without pause_i only when R15 was an enabled breakpoint,
-- and then stays paused until pause_i has been '1'; and it never runs an
-- instruction at an enabled breakpoint without a stop first, but as the
-- first step after pause_i was '1'. The pipeline is too deep for
-- k-induction without many invariants, so pipeline.sby checks a bounded
-- number of cycles from reset. formal_pipe_write proves the last for
-- every cycle at the level of WRITE.
--
-- RESET
-- The first cycle is a reset, so the core starts from the state of
-- ISA.md §8.1.

library ieee;
   use ieee.std_logic_1164.all;

   use work.nice_pkg.all;
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
      irq_vector_i : in  std_logic_vector(7 downto 0);
      pause_i      : in  std_logic;
      brk_addr_i   : in  t_brk_addrs;
      brk_en_i     : in  std_logic_vector(C_BREAKS_MAX - 1 downto 0)
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
   signal paused    : std_logic;
   signal halted    : std_logic;
   signal reason    : t_halt;
   signal instret   : std_logic;
   signal retire    : t_retire;
   signal retire_d  : t_retire := C_RETIRE_NONE;
   signal regs      : t_regs;
   signal ibus_wait : natural range 0 to 9;
   signal dbus_wait : natural range 0 to 5;

   -- The cycle before, but for a reset then: paused_o, halted_o, pause_i,
   -- and regs_o
   signal paused_d : std_logic := '0';
   signal halted_d : std_logic := '0';
   signal pause_d  : std_logic := '0';
   signal regs_d   : t_regs;

   -- paused_o has fallen, and no step has been reported since
   signal owed_r : std_logic := '0';

   constant C_BREAKS : natural := 2;

   -- The breakpoints of the cycle before
   signal brk_addr_d : t_brk_addrs;
   signal brk_en_d   : std_logic_vector(C_BREAKS_MAX - 1 downto 0);
   -- R15 was an enabled breakpoint in the cycle before
   signal hit_d      : std_logic := '0';
   -- The core paused without pause_i, and pause_i has been '0' since
   signal wait_r     : std_logic := '0';
   -- paused_o rose while pause_i was '0' in the cycle before
   signal own        : boolean;
   -- pause_i has been '1' since the last step was reported
   signal asked_r    : std_logic := '0';

   -- addr is an enabled breakpoint.
   function hit(addrs : t_brk_addrs;
                en    : std_logic_vector;
                addr  : std_logic_vector(31 downto 0)) return boolean is
   begin
      for i in 0 to C_BREAKS - 1 loop
         if en(i) = '1' and addrs(i) = addr then
            return true;
         end if;
      end loop;
      return false;
   end function hit;

begin

   -- psl default clock is rising_edge(clk_i);
   -- psl f_initial_reset : assume rst_i;

   -- regs_o holds the registers of a step from the cycle after its report.
   -- psl f_regs : assert always retire_d.valid = '1' -> regs = retire_d.regs;

   -- A halted core has no bus cycle open, and stays halted until reset. Its
   -- reason is on halt_reason_o. The data bus part holds for every cycle by
   -- the proofs of WRITE's halt, PREPARE's f_rd_run, and the definition of
   -- halted_o; the check here is of the whole core together.
   -- psl f_halt_dbus : assert always (rst_i = '0' and halted = '1') ->
   --    (dbus_cyc = '0' and dbus_stb = '0');
   -- psl f_halt_ibus : assert always (rst_i = '0' and halted = '1') ->
   --    (ibus_cyc = '0' and ibus_stb = '0');
   -- psl f_halt_stays : assert always (rst_i = '0' and halted_d = '1') -> halted = '1';
   -- psl f_halt_reason : assert always rst_i = '0' -> ((halted = '1') = (reason /= HALT_NONE));

   -- A paused core stays paused while pause_i is '1', with no bus cycle
   -- open and the registers unchanged. It is never paused and halted.
   -- psl f_pause_quiet : assert always (rst_i = '0' and paused_d = '1' and pause_d = '1') ->
   --    (paused = '1' and ibus_cyc = '0' and ibus_stb = '0' and dbus_cyc = '0' and
   --     dbus_stb = '0');
   -- psl f_pause_regs : assert always (rst_i = '0' and paused_d = '1' and paused = '1') ->
   --    regs = regs_d;
   -- psl f_pause_halt : assert always rst_i = '0' -> not (paused = '1' and halted = '1');

   -- Once paused_o falls, a step is reported before it rises again.
   -- psl f_go_report : assert always (rst_i = '0' and owed_r = '1') -> paused = '0';

   -- The breakpoints change only in a reset.
   -- psl f_brk_stable : assume always rst_i = '0' ->
   --    (brk_addr_i(0 to C_BREAKS - 1) = brk_addr_d(0 to C_BREAKS - 1) and
   --     brk_en_i(C_BREAKS - 1 downto 0) = brk_en_d(C_BREAKS - 1 downto 0));

   -- A pause of the core's own is at a breakpoint, and lasts until pause_i
   -- has been '1'. No instruction at a breakpoint runs without a stop
   -- first, but the first after pause_i was '1'.
   own <= rst_i = '0' and paused = '1' and paused_d = '0' and pause_d = '0';
   -- psl f_brk_hit : assert always own -> hit_d = '1';
   -- psl f_brk_wait : assert always (rst_i = '0' and wait_r = '1') -> paused = '1';
   -- psl f_brk_miss : assert always
   --    (rst_i = '0' and retire.valid = '1' and retire.intr = '0' and asked_r = '0') ->
   --    not hit(brk_addr_i, brk_en_i, retire.addr);

   -- How deep the bounded check must go to see an instruction retire, a
   -- store, a halt, a pause, and a step after a pause.
   -- psl c_retire : cover {retire.valid = '1' and rst_i = '0'};
   -- psl c_store : cover {dbus_stb = '1' and dbus_we = '1' and rst_i = '0'};
   -- psl c_halt : cover {halted = '1' and rst_i = '0'};
   -- psl c_pause : cover {paused = '1' and rst_i = '0'};
   -- psl c_go_step : cover {owed_r = '1' and retire.valid = '1' and rst_i = '0'};
   -- psl c_brk : cover {own};


   i_pipeline : entity work.pipeline
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
         retire_o      => retire,
         stats_o       => open
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


   -- The step reported in the cycle before, but for one in a reset, the
   -- signals of the cycle before, and owed_r
   p_retire_d : process (clk_i)
   begin
      if rising_edge(clk_i) then
         retire_d <= retire;
         paused_d <= paused and not rst_i;
         halted_d <= halted and not rst_i;
         pause_d  <= pause_i and not rst_i;
         regs_d   <= regs;
         brk_addr_d <= brk_addr_i;
         brk_en_d   <= brk_en_i;
         hit_d      <= to_sl(hit(brk_addr_i, brk_en_i, regs(15)));
         if pause_i = '1' then
            wait_r <= '0';
         elsif own then
            wait_r <= '1';
         end if;
         if pause_i = '1' then
            asked_r <= '1';
         elsif retire.valid = '1' then
            asked_r <= '0';
         end if;
         if retire.valid = '1' then
            owed_r <= '0';
         elsif paused_d = '1' and paused = '0' then
            owed_r <= '1';
         end if;
         if rst_i = '1' then
            retire_d.valid <= '0';
            owed_r         <= '0';
            wait_r         <= '0';
            asked_r        <= '0';
         end if;
      end if;
   end process p_retire_d;

end architecture synthesis;
