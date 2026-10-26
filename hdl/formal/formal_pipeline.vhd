-- The pipelined core with the checkers of its bus and interrupt ports, for
-- SymbiYosys. Every input is free, so the solver tries every slave, every
-- interrupt source, every pause, and every instruction stream that keeps
-- to the checkers' assumptions.
--
-- THEORY OF OPERATION
-- core_check holds the checkers and the rules of a stopped core. Besides
-- their assertions, the core's own, in its process
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
-- every cycle at the level of WRITE. That a halted core makes no data
-- access holds for every cycle too, by the proofs of WRITE's halt,
-- PREPARE's f_rd_run, and the definition of halted_o.
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
   signal regs      : t_regs;

   constant C_BREAKS : natural := 2;

   -- The breakpoints of the cycle before
   signal brk_addr_d : t_brk_addrs;
   signal brk_en_d   : std_logic_vector(C_BREAKS_MAX - 1 downto 0);
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

   -- The breakpoints change only in a reset.
   -- psl f_brk_stable : assume always rst_i = '0' ->
   --    (brk_addr_i(0 to C_BREAKS - 1) = brk_addr_d(0 to C_BREAKS - 1) and
   --     brk_en_i(C_BREAKS - 1 downto 0) = brk_en_d(C_BREAKS - 1 downto 0));

   -- No instruction at a breakpoint runs without a stop first, but the
   -- first after pause_i was '1'.
   -- psl f_brk_miss : assert always
   --    (rst_i = '0' and retire.valid = '1' and retire.intr = '0' and asked_r = '0') ->
   --    not hit(brk_addr_i, brk_en_i, retire.addr);


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


   i_core_check : entity work.core_check
      generic map (
         G_IBUS_PENDING => 8,
         G_DBUS_PENDING => 4,
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
         ibus_wait_o  => open,
         dbus_wait_o  => open,
         own_o        => open
      ); -- i_core_check


   -- The breakpoints of the cycle before, and asked_r
   p_brk_d : process (clk_i)
   begin
      if rising_edge(clk_i) then
         brk_addr_d <= brk_addr_i;
         brk_en_d   <= brk_en_i;
         if pause_i = '1' then
            asked_r <= '1';
         elsif retire.valid = '1' then
            asked_r <= '0';
         end if;
         if rst_i = '1' then
            asked_r <= '0';
         end if;
      end if;
   end process p_brk_d;

end architecture synthesis;
