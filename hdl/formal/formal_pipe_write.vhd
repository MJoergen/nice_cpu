-- WRITE of the pipelined core, for SymbiYosys. Every input is free, so the
-- solver plays every PREPARE, data bus, and interrupt source, whether or not
-- they keep to the interface contracts of src/pipe_write.vhd: the
-- properties here need none of them, but that the micro-operation PREPARE
-- moves on agrees with its instruction word, as PREPARE's proof asserts
-- (f_out_decoded in src/pipe_prepare.vhd).
--
-- THEORY OF OPERATION
-- A halted WRITE stays halted until reset, and makes no store, vector
-- read, interrupt entry, or micro-operation accept in the meantime. With
-- the properties of PREPARE (f_rd_run) and the definition of halted_o in
-- src/pipeline.vhd, which waits until no bus cycle is open, that is why
-- a halted core makes no data access, for every cycle and not only for the
-- first ones of pipeline.sby. A paused WRITE makes none of them either,
-- for every pause, as pause_i is free. And once it leaves PAUSED_ST, it
-- reports a step on retire_o before it pauses again (MICROARCH.md §6.1),
-- since it does not pause while w_r.after_go is '1', and only a report
-- clears that. WRITE pauses without pause_i only on the breakpoint flag
-- of the next instruction, in its own micro-operation or, while it holds
-- none, in PREPARE's; and it then stays paused until pause_i has been
-- '1' (doc/DEBUG.md §6). It takes an interrupt only when one is
-- requested, never in a reset, and never two at once, which is what
-- handshake_check asserts of the core's ready outputs in formal_pipeline,
-- here for every cycle. The record inputs are free signals here (anyseq),
-- since the top level has only plain ports.
--
-- It also proves the assumptions about WRITE that PREPARE's proof makes
-- with its model registers, with the same model: while WRITE runs, it
-- holds what PREPARE moved on, until it retires it or flushes; SR changes
-- only while WRITE holds a micro-operation that may change it, or with a
-- flush, an interrupt entry, or a reset; WRITE's condition likewise, while
-- it holds an instruction's first, or else to the condition of the one it
-- holds, as PREPARE found it; and WRITE leaves RUN_ST only with a flush,
-- an interrupt entry, or a reset. Each change can come in a cycle before
-- the micro-operation retires: a micro-operation that takes two cycles
-- writes its result and its condition in the first. And WRITE clears only
-- the valid bit of a micro-operation it drops, and keeps the one of INT
-- through VEC_ST, so the first holds only in RUN_ST.
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
      valid_i      : in  std_logic;
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
      f_blk_i      : in  std_logic_vector(31 downto 5);
      pause_i      : in  std_logic
   );
end entity formal_pipe_write;

architecture synthesis of formal_pipe_write is

   signal uop      : t_uop;
   signal dec      : t_inst;
   signal dec2     : t_inst;
   signal skid     : t_inst;
   signal prep     : t_uop;
   signal rq       : t_words(0 to C_MAX_OUT - 1);
   signal ready    : std_logic;
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

   -- WRITE was in PAUSED_ST in the cycle before, but for a reset then, and
   -- it has left PAUSED_ST and has reported no step since
   signal paused_d : std_logic := '0';
   signal left     : std_logic;
   signal owed_r   : std_logic := '0';

   -- The cycle before: pause_i, w.brk_wait, and the breakpoint flag of the
   -- next instruction
   signal pause_d  : std_logic := '0';
   signal wait_d   : std_logic := '0';
   signal flag     : std_logic;
   signal flag_d   : std_logic := '0';
   -- WRITE enters PAUSED_ST now
   signal enters   : std_logic;

   -- PREPARE's model of WRITE (src/pipe_prepare.vhd, p_model): the
   -- micro-operation WRITE holds, and from the cycle before, SR, the
   -- condition, and the mode, and whether each may change
   signal f_first     : std_logic := '1';
   signal f_uop       : t_uop     := C_UOP_NONE;
   signal f_sr        : std_logic_vector(31 downto 0);
   signal f_sr_free   : std_logic;
   signal f_cond      : std_logic;
   signal f_cond_free : std_logic;
   signal f_cond_set  : std_logic;
   signal f_cond_val  : std_logic;
   signal f_mode      : t_wmode;
   signal f_mode_free : std_logic;

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
   -- PREPARE's f_out_decoded
   -- psl f_decoded : assume always (rst_i = '0' and valid_i = '1') -> decoded_ok(uop);

   -- Halted WRITE makes no access to the data bus, takes no interrupt, and
   -- accepts no micro-operation.
   -- psl f_halt_quiet : assert always w.mode = HALTED_ST ->
   --    (st = '0' and take_nmi = '0' and take_irq = '0' and ready = '0');

   -- Nothing leaves the halt but a reset: not an interrupt, not a bus
   -- reply, not a micro-operation from PREPARE.
   -- psl f_halt_sticky : assert always (halted_d = '1' and rst_d = '0') -> w.mode = HALTED_ST;

   -- A paused WRITE makes no access to the data bus, takes no interrupt,
   -- and accepts no micro-operation either.
   -- psl f_pause_quiet : assert always w.mode = PAUSED_ST ->
   --    (st = '0' and take_nmi = '0' and take_irq = '0' and ready = '0');

   -- WRITE takes an interrupt only when it is requested, and one at a time,
   -- never in a reset. take_nmi_o and take_irq_o are the ready outputs of
   -- the pipelined core, so these are the assertions of
   -- formal/handshake_check.vhd, for every cycle.
   -- psl f_take_nmi : assert always take_nmi -> (nmi_valid_i = '1' and rst_i = '0');
   -- psl f_take_irq : assert always take_irq -> (irq_valid_i = '1' and rst_i = '0');
   -- psl f_take_one : assert always not (take_nmi and take_irq);

   -- Once WRITE leaves PAUSED_ST, it reports a step before it pauses
   -- again. f_go_owed and f_go_paused make it inductive.
   -- psl f_go_report : assert always (rst_i = '0' and owed_r = '1') -> w.mode /= PAUSED_ST;
   -- psl f_go_owed : assert always (rst_i = '0' and owed_r = '1') -> w.after_go = '1';
   -- psl f_go_paused : assert always (rst_i = '0' and w.mode = PAUSED_ST) -> w.after_go = '0';

   -- A pause without pause_i is at a breakpoint, and lasts until pause_i
   -- has been '1'.
   -- psl f_brk_own : assert always (rst_d = '0' and enters = '1' and pause_d = '0') ->
   --    (flag_d = '1' and w.brk_wait = '1');
   -- psl f_brk_hold : assert always (rst_i = '0' and rst_d = '0' and wait_d = '1' and pause_d = '0') ->
   --    w.mode = PAUSED_ST;
   -- psl f_brk_wait : assert always (rst_i = '0' and w.brk_wait = '1') -> w.mode = PAUSED_ST;

   -- PREPARE's assumptions about WRITE (src/pipe_prepare.vhd)
   -- psl f_takes : assert always (f_first = '0' and w.mode = RUN_ST) ->
   --    (w.uop.valid = f_uop.valid and (f_uop.valid = '0' or w.uop = f_uop));
   -- psl f_sr_stable : assert always (f_first = '0' and f_sr_free = '0') -> w.regs(14) = f_sr;
   -- psl f_cond_stable : assert always (f_first = '0' and f_cond_free = '0') ->
   --    (w.cond = f_cond or (f_cond_set = '1' and w.cond = f_cond_val));
   -- psl f_run : assert always (f_first = '0' and f_mode_free = '0' and f_mode = RUN_ST) ->
   --    w.mode = RUN_ST;
   -- The invariants that make them inductive: the micro-operation agrees
   -- with its instruction word, the second cycle of one is of an operation
   -- with a register destination, and WRITE holds none while halted or
   -- paused.
   -- psl f_wdecoded : assert always (rst_i = '0' and w.uop.valid = '1') -> decoded_ok(w.uop);
   -- psl f_exec : assert always (rst_i = '0' and w.exec_done = '1') ->
   --    (w.uop.valid = '1' and w.uop.kind = UOP_OP and w.mode = RUN_ST and
   --     (w.uop.inst.m(0) = "000" or w.uop.inst.m(0) = "001" or w.uop.inst.m(0) = "010"));
   -- psl f_idle : assert always (rst_i = '0' and (w.mode = PAUSED_ST or w.mode = HALTED_ST)) ->
   --    w.uop.valid = '0';

   -- How deep the proof must see a halt, a store, a vector read, a pause,
   -- and a step after a pause, and that INT's micro-operation stays
   -- through VEC_ST.
   -- psl c_halt : cover {w.mode = HALTED_ST and rst_i = '0'};
   -- psl c_store : cover {st = '1' and st_we = '1' and rst_i = '0'};
   -- psl c_vector : cover {st = '1' and st_we = '0' and rst_i = '0'};
   -- psl c_pause : cover {w.mode = PAUSED_ST and rst_i = '0'};
   -- psl c_go_step : cover {owed_r = '1' and retire.valid = '1' and rst_i = '0'};
   -- psl c_brk : cover {enters = '1' and pause_d = '0' and rst_i = '0'};
   -- psl c_int_keep : cover {w.mode = VEC_ST and w.uop.valid = '1' and rst_i = '0'};
   -- psl c_brk_go : cover {enters = '1' and pause_d = '0' and rst_i = '0';
   --    (w.mode = PAUSED_ST)[*]; w.mode = RUN_ST and rst_i = '0'};


   i_pipe_write : entity work.pipe_write
      port map (
         clk_i        => clk_i,
         rst_i        => rst_i,
         valid_i      => valid_i,
         uop_i        => uop,
         first_read_i => first_read_i,
         rd_stb_i     => rd_stb_i,
         ready_o      => ready,
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
         pause_i      => pause_i,
         state_o      => w,
         done_o       => done,
         flush_o      => flush,
         target_o     => target,
         instret_o    => instret,
         retire_o     => retire
      ); -- i_pipe_write


   left <= paused_d and to_sl(w.mode /= PAUSED_ST);
   enters <= not paused_d and to_sl(w.mode = PAUSED_ST);
   flag   <= w.uop.inst.brk when w.uop.valid = '1' else
             prep.valid and prep.first and prep.inst.brk;

   p_prev : process (clk_i)
   begin
      if rising_edge(clk_i) then
         halted_d <= to_sl(w.mode = HALTED_ST);
         rst_d    <= rst_i;
         paused_d <= to_sl(w.mode = PAUSED_ST) and not rst_i;
         pause_d  <= pause_i;
         wait_d   <= w.brk_wait;
         flag_d   <= flag;
         if retire.valid = '1' then
            owed_r <= '0';
         elsif left = '1' then
            owed_r <= '1';
         end if;
         if rst_i = '1' then
            owed_r <= '0';
         end if;

         f_first <= '0';
         if flush = '1' then
            f_uop <= C_UOP_NONE;
         elsif valid_i = '1' and ready = '1' then
            f_uop <= uop;
         elsif done = '1' then
            f_uop <= C_UOP_NONE;
         end if;
         f_sr        <= w.regs(14);
         f_sr_free   <= rst_i or flush or take_nmi or take_irq or
                        (w.uop.valid and w.uop.may_sr);
         f_cond      <= w.cond;
         f_cond_free <= rst_i or flush or take_nmi or take_irq or
                        (w.uop.valid and w.uop.first);
         f_cond_set  <= w.uop.valid and w.uop.cond_known;
         f_cond_val  <= w.uop.cond_val;
         f_mode      <= w.mode;
         f_mode_free <= rst_i or flush or take_nmi or take_irq;
         if rst_i = '1' then
            f_uop <= C_UOP_NONE;
         end if;
      end if;
   end process p_prev;

end architecture synthesis;
