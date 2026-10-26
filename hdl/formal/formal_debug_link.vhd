-- The debug link with checks of its ports, for SymbiYosys. Every input is
-- free, so the solver plays every host, every program, every core, and
-- every Wishbone slave that keep to the contracts of src/debug_link.vhd.
--
-- THEORY OF OPERATION
-- The assumptions are the contracts: the slave of wb_master_check, and a
-- core whose halt ends only by a reset, by hold_o or by rst_i, and whose
-- pause lasts as long as pause_o and hold_o allow (contract e). The core
-- may pause at any time, also with pause_o low, as at a breakpoint. Such a
-- pause lasts until pause_o has been high. The link has two breakpoints.
-- The assertions:
-- - The Wishbone master keeps to the pipelined rules of wb_master_check,
--   with one access at a time. It works only while hold_o, halted_i, or
--   paused_i is high, and never while clear_o is high (contracts a and f).
-- - con_in_valid_o is high only for one cycle in three, only while the
--   program ran, and only while free_i was not 0 the cycle before, which
--   is two cycles before the strobe's byte reaches free_i (contract d).
-- - clear_o stays high until clear_done_i (contract f).
-- - tx_valid_o stays high, with tx_data_o unchanged, until tx_ready_i,
--   and a console byte taken is the next byte out.
-- - eoi_o rises only after rx_break_i, and falls only at a start, when
--   hold_o falls, or at reset (DEBUG.md §7).
-- - With G_HAS_ROM false, rom_hide_o is always 1.
-- The properties that name the registers of debug_link are there, under
-- G_FORMAL: the framing of the output, so that nothing comes between the
-- bytes of a packet, no answer during a clear, why rx_ready_o is low
-- (contract c), when hold_o and rom_hide_o change (DEBUG.md §6), and the
-- invariants that make the proof inductive, and the breakpoints: their
-- registers, and the stop of the core's own, which raises pause_o. The invariant f_wb_owed here
-- ties the count of wb_master_check to the master.
-- The covers show a write to the memory, a console byte for the program,
-- and the end of a clear; those of wb_master_check a stalled write, and
-- those of debug_link an `h`, an `o`, and the `p` of a stop of the core's
-- own. A `p` of a request needs a whole `W` of the control register first,
-- about 80 cycles, and a read of the memory needs a whole `R` and the start
-- of its answer, about 90 cycles, deeper than the cover task looks, so
-- tb_debug_link shows them instead.
--
-- NOT PROVEN
-- That console bytes the host sends after a halt are dropped (DEBUG.md §1):
-- f_strobe looks at hold_d and eoi_d, not at halted_i, so only
-- tb_debug_link checks the drop after a halt. Contract (e) is an assumption
-- here, and the pipelined core meets it only as formal_pipe_write and
-- tb_link show.
--
-- RESET
-- The first cycle is a reset.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use work.trace_pkg.all;

entity formal_debug_link is
   generic (
      G_HAS_ROM   : boolean := true;
      G_BOOT_HELD : boolean := false
   );
   port (
      clk_i         : in  std_logic;
      rst_i         : in  std_logic;
      rx_valid_i    : in  std_logic;
      rx_data_i     : in  std_logic_vector(7 downto 0);
      rx_break_i    : in  std_logic;
      tx_ready_i    : in  std_logic;
      con_valid_i   : in  std_logic;
      con_data_i    : in  std_logic_vector(7 downto 0);
      free_i        : in  std_logic_vector(15 downto 0);
      clear_done_i  : in  std_logic;
      halted_i      : in  std_logic;
      halt_reason_i : in  std_logic_vector(2 downto 0);
      paused_i      : in  std_logic;
      regs_i        : in  std_logic_vector(511 downto 0);
      wb_stall_i    : in  std_logic;
      wb_ack_i      : in  std_logic;
      wb_data_i     : in  std_logic_vector(31 downto 0)
   );
end entity formal_debug_link;

architecture synthesis of formal_debug_link is

   signal rx_ready     : std_logic;
   signal tx_valid     : std_logic;
   signal tx_data      : std_logic_vector(7 downto 0);
   signal con_ready    : std_logic;
   signal con_in_valid : std_logic;
   signal con_in_data  : std_logic_vector(7 downto 0);
   signal eoi          : std_logic;
   signal hold         : std_logic;
   signal pause        : std_logic;
   signal rom_hide     : std_logic;
   signal clear        : std_logic;
   signal wb_cyc       : std_logic;
   signal wb_stb       : std_logic;
   signal wb_we        : std_logic;
   signal wb_addr      : std_logic_vector(31 downto 0);
   signal wb_data      : std_logic_vector(31 downto 0);
   signal brk_addr     : t_brk_addrs;
   signal brk_en       : std_logic_vector(C_BREAKS_MAX - 1 downto 0);

   -- A console byte taken, which is the next byte out
   signal pending  : natural range 0 to 2;          -- The ACKs owed to the master
   signal con_due  : std_logic                    := '0';
   signal con_byte : std_logic_vector(7 downto 0) := (others => '0');

   -- The input state of the cycles before, for f_strobe. GHDL 4.1 of the
   -- formal job fails on prev with a count.
   signal free_nz_d        : std_logic := '0';
   signal con_in_valid_d   : std_logic := '0';
   signal con_in_valid_dd  : std_logic := '0';
   signal hold_d           : std_logic := '0';
   signal eoi_d            : std_logic := '0';

   -- The conditions of the halt and pause assumptions, one cycle before. The
   -- assumptions are plain Booleans on them: the formal job's toolchain does
   -- not apply an assume with a sequence and |=>, and induction then finds
   -- a halt that ends without a reset.
   signal halt_keep_d  : std_logic := '0';
   signal pause_keep_d : std_logic := '0';

   -- A pause of the core's own, at a breakpoint: paused_i rose while pause_o
   -- was low the cycle before, and pause_o has not been high since.
   signal paused_d : std_logic := '0';
   signal pause_d  : std_logic := '0';
   signal own_wait : std_logic;
   signal wait_r   : std_logic := '0';

begin

   p_delay : process (clk_i)
   begin
      if rising_edge(clk_i) then
         free_nz_d       <= '1' when free_i /= X"0000" else '0';
         con_in_valid_d  <= con_in_valid;
         con_in_valid_dd <= con_in_valid_d;
         hold_d          <= hold;
         eoi_d           <= eoi;
         halt_keep_d     <= halted_i and not hold and not rst_i;
         pause_keep_d    <= paused_i and (pause or own_wait) and not hold and not rst_i;
         paused_d        <= paused_i and not rst_i;
         pause_d         <= pause and not rst_i;
         wait_r          <= own_wait and not hold and not rst_i;
      end if;
   end process p_delay;

   own_wait <= not pause and (wait_r or (paused_i and not paused_d and not pause_d));

   -- A console byte taken is the next byte out.
   p_con : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if tx_valid = '1' and tx_ready_i = '1' then
            con_due <= '0';
         end if;
         if con_valid_i = '1' and con_ready = '1' then
            con_due  <= '1';
            con_byte <= con_data_i;
         end if;

         if rst_i = '1' then
            con_due <= '0';
         end if;
      end if;
   end process p_con;


   -- psl default clock is rising_edge(clk_i);
   -- psl f_initial_reset : assume rst_i;

   -- The core: its halt ends only by a reset (contract e).
   -- psl f_halted : assume always halt_keep_d = '1' -> halted_i = '1';

   -- The pause: never with a halt, and it lasts while pause_o is high and
   -- the core is not reset, and at a breakpoint until pause_o has been high
   -- (contract e).
   -- psl f_paused_halt : assume always not (paused_i and halted_i);
   -- psl f_paused : assume always pause_keep_d = '1' -> paused_i = '1';

   -- The Wishbone master
   -- psl f_wb_hold : assert always wb_cyc -> (hold = '1' or halted_i = '1' or paused_i = '1');
   -- psl f_wb_clear : assert always clear -> not wb_cyc;
   -- The toolchain of the formal job does not apply an = between two
   -- Booleans, so each equality is two implications.
   -- psl f_wb_owed : assert always (wb_cyc = '1' and wb_stb = '0') -> pending = 1;
   -- psl f_wb_owed_back : assert always pending = 1 -> (wb_cyc = '1' and wb_stb = '0');
   -- psl f_wb_stb : assert always wb_stb = '1' -> pending = 0;

   -- The program's input
   -- psl f_strobe : assert always
   --    {not rst_i; not rst_i; con_in_valid} |->
   --    {free_nz_d = '1' and con_in_valid_d = '0' and
   --     con_in_valid_dd = '0' and hold_d = '0' and eoi_d = '0'};

   -- The clear
   -- psl f_clear : assert always
   --    {clear and not clear_done_i and not rst_i} |=> {clear};

   -- The output
   -- psl f_tx_hold : assert always
   --    {tx_valid and not tx_ready_i and not rst_i} |=>
   --    {rst_i = '1' or (tx_valid = '1' and stable(tx_data))};
   -- psl f_con_next : assert always
   --    con_due = '1' -> (tx_valid = '1' and tx_data = con_byte);

   -- The end of the input
   -- psl f_eoi_rise : assert always {not eoi; eoi} |-> {prev(rx_break_i)};
   -- psl f_eoi_fall : assert always
   --    {eoi; not eoi} |-> {prev(rst_i) = '1' or (prev(hold) = '1' and hold = '0')};

   -- psl c_write : cover {wb_cyc and wb_stb and wb_we and not wb_stall_i};
   -- psl c_strobe : cover {con_in_valid and not rst_i};
   -- psl c_clear : cover {clear and clear_done_i};

   gen_no_rom : if not G_HAS_ROM generate
      -- psl f_no_rom : assert always rom_hide = '1';
   end generate gen_no_rom;


   i_debug_link : entity work.debug_link
      generic map (
         G_TIMEOUT   => 3,
         G_HAS_ROM   => G_HAS_ROM,
         G_BOOT_HELD => G_BOOT_HELD,
         G_BREAKS    => 2,
         G_FORMAL    => true
      )
      port map (
         clk_i          => clk_i,
         rst_i          => rst_i,
         rx_valid_i     => rx_valid_i,
         rx_ready_o     => rx_ready,
         rx_data_i      => rx_data_i,
         rx_break_i     => rx_break_i,
         tx_valid_o     => tx_valid,
         tx_ready_i     => tx_ready_i,
         tx_data_o      => tx_data,
         con_valid_i    => con_valid_i,
         con_ready_o    => con_ready,
         con_data_i     => con_data_i,
         con_in_valid_o => con_in_valid,
         con_in_data_o  => con_in_data,
         free_i         => free_i,
         eoi_o          => eoi,
         hold_o         => hold,
         rom_hide_o     => rom_hide,
         clear_o        => clear,
         clear_done_i   => clear_done_i,
         halted_i       => halted_i,
         halt_reason_i  => halt_reason_i,
         pause_o        => pause,
         paused_i       => paused_i,
         regs_i         => regs_i,
         brk_addr_o     => brk_addr,
         brk_en_o       => brk_en,
         wb_cyc_o       => wb_cyc,
         wb_stb_o       => wb_stb,
         wb_stall_i     => wb_stall_i,
         wb_ack_i       => wb_ack_i,
         wb_we_o        => wb_we,
         wb_addr_o      => wb_addr,
         wb_data_o      => wb_data,
         wb_data_i      => wb_data_i
      ); -- i_debug_link


   i_wb_master_check : entity work.wb_master_check
      generic map (
         G_MAX_PENDING => 1,
         -- An `r` reads its first word after about 90 cycles.
         G_COVER_READ  => false
      )
      port map (
         clk_i     => clk_i,
         rst_i     => rst_i,
         cyc_i     => wb_cyc,
         stb_i     => wb_stb,
         stall_i   => wb_stall_i,
         ack_i     => wb_ack_i,
         we_i      => wb_we,
         addr_i    => wb_addr,
         data_i    => wb_data,
         pending_o => pending
      ); -- i_wb_master_check

end architecture synthesis;
