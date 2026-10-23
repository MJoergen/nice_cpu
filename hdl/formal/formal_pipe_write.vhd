-- WRITE of the pipelined core, for SymbiYosys. Every input is free, so the
-- solver plays every PREPARE, data bus, and interrupt source, whether or not
-- they keep to the interface contracts of src/pipe_write.vhd: the
-- properties here need none of them.
--
-- THEORY OF OPERATION
-- A halted WRITE stays halted until reset, and makes no store, vector
-- read, interrupt entry, or micro-operation accept in the meantime. With
-- the properties of PREPARE (f_rd_run) and the definition of halted_o in
-- src/pipeline.vhd, which waits for DBUS's register to empty, that is why
-- a halted core makes no data access, for every cycle and not only for the
-- first ones of pipeline.sby. The record inputs are free signals here
-- (anyseq), since the top level has only plain ports.
--
-- RESET
-- The first cycle is a reset.

library ieee;
   use ieee.std_logic_1164.all;

   use work.nice_pkg.all;
   use work.pipe_pkg.all;
   use work.trace_pkg.all;

entity formal_pipe_write is
   port (
      clk_i        : in  std_logic;
      rst_i        : in  std_logic;
      move_i       : in  std_logic;
      first_read_i : in  std_logic;
      rd_stb_i     : in  std_logic;
      rq_cnt_i     : in  natural range 0 to C_MAX_OUT;
      ack_read_i   : in  std_logic;
      dbus_data_i  : in  std_logic_vector(31 downto 0);
      st_valid_i   : in  std_logic;
      st_acc_i     : in  std_logic;
      nmi_valid_i  : in  std_logic;
      nmi_vector_i : in  std_logic_vector(7 downto 0);
      irq_valid_i  : in  std_logic;
      irq_vector_i : in  std_logic_vector(7 downto 0);
      f_addr_i     : in  std_logic_vector(31 downto 0);
      f_blk_i      : in  std_logic_vector(31 downto 5)
   );
end entity formal_pipe_write;

architecture synthesis of formal_pipe_write is

   signal uop      : t_uop;
   signal dec      : t_inst;
   signal dec2     : t_inst;
   signal skid     : t_inst;
   signal prep     : t_uop;
   signal rq       : t_words(0 to C_MAX_OUT - 1);
   signal accept   : std_logic;
   signal pop      : natural range 0 to 2;
   signal st       : std_logic;
   signal st_we    : std_logic;
   signal st_addr  : std_logic_vector(31 downto 0);
   signal st_data  : std_logic_vector(31 downto 0);
   signal take_nmi : std_logic;
   signal take_irq : std_logic;
   signal w        : t_write;
   signal done     : std_logic;
   signal flush    : std_logic;
   signal target   : std_logic_vector(31 downto 0);
   signal instret  : std_logic;
   signal retire   : t_retire;

   -- The cycle before: whether WRITE was halted, and whether it was reset
   signal halted_d : std_logic := '0';
   signal rst_d    : std_logic := '1';

   attribute anyseq : boolean;
   attribute anyseq of uop  : signal is true;
   attribute anyseq of dec  : signal is true;
   attribute anyseq of dec2 : signal is true;
   attribute anyseq of skid : signal is true;
   attribute anyseq of prep : signal is true;
   attribute anyseq of rq   : signal is true;

begin

   -- psl default clock is rising_edge(clk_i);
   -- psl f_initial_reset : assume rst_i;
   -- The range of the port, which synthesis does not keep
   -- psl f_cnt_range : assume always rq_cnt_i <= C_MAX_OUT;

   -- Halted WRITE makes no access to the data bus, takes no interrupt, and
   -- accepts no micro-operation.
   -- psl f_halt_quiet : assert always w.mode = HALTED_ST ->
   --    (st = '0' and take_nmi = '0' and take_irq = '0' and accept = '0');

   -- Nothing leaves the halt but a reset: not an interrupt, not a bus
   -- reply, not a micro-operation from PREPARE.
   -- psl f_halt_sticky : assert always (halted_d = '1' and rst_d = '0') -> w.mode = HALTED_ST;

   -- How deep the proof must see a halt, a store, and a vector read.
   -- psl c_halt : cover {w.mode = HALTED_ST and rst_i = '0'};
   -- psl c_store : cover {st = '1' and st_we = '1' and rst_i = '0'};
   -- psl c_vector : cover {st = '1' and st_we = '0' and rst_i = '0'};


   i_pipe_write : entity work.pipe_write
      port map (
         clk_i        => clk_i,
         rst_i        => rst_i,
         move_i       => move_i,
         uop_i        => uop,
         first_read_i => first_read_i,
         rd_stb_i     => rd_stb_i,
         accept_o     => accept,
         f_addr_i     => f_addr_i,
         f_blk_i      => f_blk_i,
         dec_i        => dec,
         dec2_i       => dec2,
         skid_i       => skid,
         prep_i       => prep,
         rq_i         => rq,
         rq_cnt_i     => rq_cnt_i,
         ack_read_i   => ack_read_i,
         dbus_data_i  => dbus_data_i,
         pop_o        => pop,
         st_valid_i   => st_valid_i,
         st_acc_i     => st_acc_i,
         st_o         => st,
         st_we_o      => st_we,
         st_addr_o    => st_addr,
         st_data_o    => st_data,
         nmi_valid_i  => nmi_valid_i,
         nmi_vector_i => nmi_vector_i,
         irq_valid_i  => irq_valid_i,
         irq_vector_i => irq_vector_i,
         take_nmi_o   => take_nmi,
         take_irq_o   => take_irq,
         state_o      => w,
         done_o       => done,
         flush_o      => flush,
         target_o     => target,
         instret_o    => instret,
         retire_o     => retire
      ); -- i_pipe_write


   p_prev : process (clk_i)
   begin
      if rising_edge(clk_i) then
         halted_d <= to_sl(w.mode = HALTED_ST);
         rst_d    <= rst_i;
      end if;
   end process p_prev;

end architecture synthesis;
