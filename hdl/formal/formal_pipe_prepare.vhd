-- PREPARE of the pipelined core, for SymbiYosys. Every input is free, so
-- the solver plays every DECODE, WRITE, and data bus that keep to the
-- assumptions in src/pipe_prepare.vhd.
--
-- THEORY OF OPERATION
-- The properties are in pipe_prepare itself, under G_FORMAL, because
-- their assumptions and invariants name its registers. The record inputs,
-- the micro-operation from DECODE and WRITE's state, are free signals
-- here (anyseq), since the top level has only plain ports.
--
-- RESET
-- The first cycle is a reset.

library ieee;
   use ieee.std_logic_1164.all;

   use work.pipe_pkg.all;

entity formal_pipe_prepare is
   port (
      clk_i        : in  std_logic;
      rst_i        : in  std_logic;
      emit_i       : in  std_logic;
      done_i       : in  std_logic;
      flush_i      : in  std_logic;
      accept_i     : in  std_logic;
      take_nmi_i   : in  std_logic;
      take_irq_i   : in  std_logic;
      nmi_valid_i  : in  std_logic;
      irq_valid_i  : in  std_logic;
      dbus_stall_i : in  std_logic;
      tag_cnt_i    : in  natural range 0 to C_MAX_OUT
   );
end entity formal_pipe_prepare;

architecture synthesis of formal_pipe_prepare is

   signal uop        : t_uop;
   signal w          : t_write;
   signal ready      : std_logic;
   signal move       : std_logic;
   signal uop_out    : t_uop;
   signal first_read : std_logic;
   signal prep       : t_uop;
   signal rd_stb     : std_logic;
   signal rd_addr    : std_logic_vector(31 downto 0);
   signal load       : std_logic;
   signal count      : std_logic;

   attribute anyseq : boolean;
   attribute anyseq of uop : signal is true;
   attribute anyseq of w   : signal is true;

begin

   -- psl default clock is rising_edge(clk_i);
   -- psl f_initial_reset : assume rst_i;


   i_pipe_prepare : entity work.pipe_prepare
      generic map (
         G_FORMAL => true
      )
      port map (
         clk_i        => clk_i,
         rst_i        => rst_i,
         emit_i       => emit_i,
         uop_i        => uop,
         ready_o      => ready,
         w_i          => w,
         done_i       => done_i,
         flush_i      => flush_i,
         accept_i     => accept_i,
         take_nmi_i   => take_nmi_i,
         take_irq_i   => take_irq_i,
         nmi_valid_i  => nmi_valid_i,
         irq_valid_i  => irq_valid_i,
         move_o       => move,
         uop_o        => uop_out,
         first_read_o => first_read,
         prep_o       => prep,
         dbus_stall_i => dbus_stall_i,
         tag_cnt_i    => tag_cnt_i,
         rd_stb_o     => rd_stb,
         rd_addr_o    => rd_addr,
         load_o       => load,
         count_o      => count
      ); -- i_pipe_prepare

end architecture synthesis;
