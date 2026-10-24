-- The pipelined NICE core of doc/MICROARCH.md. It has the ports of the
-- multi-cycle core, src/multicycle.vhd, and reports the same steps. Its
-- one more port, stats_o, reports what FETCH and DECODE do in each cycle,
-- for the fetch statistics, src/fetch_stats.vhd.
--
-- THEORY OF OPERATION
-- The pipeline (MICROARCH.md §3), one entity for each part:
--
--   FETCH     src/pipe_fetch.vhd. Reads pairs of words ahead into a
--             buffer, and presents up to four of them.
--   DECODE    src/pipe_decode.vhd. Takes one whole instruction into
--             dec_r. Redirects FETCH at once for a jump it can resolve.
--             Splits the instruction in dec_r into micro-operations
--             (src/pipe_pkg.vhd), one per cycle, into prep_r, through
--             skid_r when PREPARE cannot take one.
--   PREPARE   src/pipe_prepare.vhd. Tests the condition, and issues the
--             data reads of the micro-operation in prep_r. Then passes it
--             to w_r.uop.
--   WRITE     src/pipe_write.vhd. Runs the micro-operation in w_r.uop:
--             computes the result, writes the registers, issues the
--             store, and updates the flags. Takes interrupts, runs the
--             control instructions, and flushes the pipeline.
--   DBUS      src/pipe_dbus.vhd. The data bus port, with the tags and the
--             read data of the requests in flight.
--
-- This entity connects them, and checks the invariants below in
-- simulation. Some of the signals between the parts are combinational,
-- as each part's header says: PREPARE decides on a read with WRITE's
-- decisions of the same cycle.
--
-- Each stage holds one item, and passes it on when the next stage is free
-- or frees itself in the same cycle. DECODE to PREPARE and PREPARE to
-- WRITE are valid/ready handshakes: a micro-operation moves in a cycle
-- with valid and ready both high, and valid does not depend on ready. A
-- flush and WRITE's checks act beside them. DECODE splits off a
-- micro-operation whether PREPARE takes it or not, and keeps one it does
-- not take in skid_r, so that its registers do not wait on PREPARE's
-- decisions.
--
-- REGISTERS. WRITE is the only stage that writes the registers, and it does
-- so in program order. So the registers it holds, w_r.regs, are the
-- architectural registers once every older micro-operation has retired.
-- WRITE reads them directly: every older micro-operation has retired when
-- one reaches it. PREPARE reads them too, for the address of a data read,
-- and waits while the micro-operation in WRITE will still write the
-- register it needs (MICROARCH.md §4, "s1 can depend on s0's side
-- effect"). So no value needs a bypass, and DECODE reads no register. R0 is
-- 0, R14 is SR, and R15 is the address of the next instruction, except
-- after a side effect on R15 earlier in the same instruction (ISA.md §4.3),
-- which WRITE records in w_r.jump.
--
-- THE CONDITION (MICROARCH.md §5.2) is tested once per instruction, against
-- SR before it. PREPARE tests it when no older micro-operation in WRITE may
-- still change SR, and must, before it issues a data read. Otherwise WRITE
-- tests it, at the instruction's first micro-operation. A skipped
-- instruction's micro-operations pass through WRITE with no effect.
--
-- DATA ACCESSES (MICROARCH.md §5.3) are exact and in order. PREPARE loads a
-- data read into a request register, rd_stb_r and rd_addr_r, only when the
-- instruction is certain to run: its condition is true; the older
-- micro-operation in WRITE, if any, will not jump, halt, or store into
-- fetched code, and has issued its store; no interrupt may be taken before
-- the instruction; every older instruction has been counted on
-- instret_o; and no store will wait in DBUS in the next cycle. WRITE puts
-- its stores and its vector reads into DBUS's register, which drives the
-- bus from the next cycle on, until the bus accepts them. A store into
-- memory retires when it goes into the register, and one into the I/O
-- range when the bus accepts it. The two never compete: WRITE issues an
-- access only when every read that PREPARE loaded is on the bus or done.
-- The ACKs come back in order. A FIFO of tags tells
-- reads from writes, and a FIFO holds the data of reads that WRITE has not
-- used yet. FETCH makes no new request while a store waits in DBUS that
-- WRITE's check of fetched code (MICROARCH.md §5.5) did not cover.
--
-- CONTROL FLOW (MICROARCH.md §5.4). WRITE flushes every younger stage and
-- redirects FETCH after an instruction that wrote R15, after RTI, at the
-- start and end of an interrupt entry or INT, after a halt, and after a
-- store into a word that is fetched but not retired (MICROARCH.md §5.5).
-- Those words are the range that pipe_fetch reports and the instructions in
-- dec_r, dec_q, skid_r, and prep_r. DECODE redirects FETCH itself for
-- "MOVE R15, c" and "ADD R15, R15, c" with condition "always". WRITE then
-- does not flush. WRITE's redirect reaches FETCH a cycle after its flush,
-- from w_redir_r and w_target_r. DECODE drops what it takes in that cycle,
-- and halted_o waits until FETCH has no request left, so that a halted
-- core requests nothing.
--
-- INTERRUPTS (MICROARCH.md §6) are taken in WRITE before an instruction,
-- as soon as ISA.md §7.1 allows: before the instruction's first
-- micro-operation runs, if no data read of it is issued yet. PREPARE
-- issues no read while a request is pending that could be taken first.
--
-- INSTRET. An instruction is counted on instret_o when its last
-- micro-operation retires, or, if it reads memory, in the cycle the bus
-- accepts its last data read, which may wait on the bus. The performance
-- counters return a count from before that cycle's, and PREPARE loads a
-- younger read only then. So a read of INSTR_LO (SYSTEM.md §3) counts every
-- older instruction, and not its own. The two ways never fall in one
-- cycle.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) The bus slaves acknowledge every request, in order. On the data bus, a
--    write accepted in one cycle is seen by an instruction fetch accepted
--    in a later cycle.
-- b) A device holds nmi_valid_i or irq_valid_i, and the vector, stable until
--    the core raises the matching ready.
-- c) nmi_ready_o and irq_ready_o depend combinationally on nmi_valid_i and
--    irq_valid_i, so a device must not make valid depend combinationally on
--    ready.
--
-- RESET
-- Synchronous. It sets the state of ISA.md §8.1, empties the pipeline, and
-- drops any bus request. Memory is not changed.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use work.nice_pkg.all;
   use work.pipe_pkg.all;
   use work.trace_pkg.all;

entity pipeline is
   generic (
      -- Adds the invariants that a formal proof needs.
      G_FORMAL : boolean := false
   );
   port (
      clk_i        : in  std_logic;
      rst_i        : in  std_logic;

      -- Instruction bus: read only
      ibus_cyc_o   : out std_logic;
      ibus_stb_o   : out std_logic;
      ibus_stall_i : in  std_logic;
      ibus_ack_i   : in  std_logic;
      ibus_addr_o  : out std_logic_vector(30 downto 0);
      ibus_data_i  : in  std_logic_vector(63 downto 0);

      -- Data bus: read and write
      dbus_cyc_o   : out std_logic;
      dbus_stb_o   : out std_logic;
      dbus_stall_i : in  std_logic;
      dbus_ack_i   : in  std_logic;
      dbus_we_o    : out std_logic;
      dbus_addr_o  : out std_logic_vector(31 downto 0);
      dbus_data_o  : out std_logic_vector(31 downto 0);
      dbus_data_i  : in  std_logic_vector(31 downto 0);

      -- Interrupt requests
      nmi_valid_i  : in  std_logic;
      nmi_ready_o  : out std_logic;
      nmi_vector_i : in  std_logic_vector(7 downto 0);
      irq_valid_i  : in  std_logic;
      irq_ready_o  : out std_logic;
      irq_vector_i : in  std_logic_vector(7 downto 0);

      -- '1' once the core has halted (ISA.md §1.4)
      halted_o     : out std_logic;

      -- '1' for one cycle for each completed instruction, but not for an
      -- interrupt entry, for the instruction counter (SYSTEM.md §3)
      instret_o    : out std_logic;

      -- R0-R15 as the core holds them, from registers, for a monitor that
      -- shows them. In the cycle after a step is reported on retire_o, they
      -- are the registers of that report.
      regs_o       : out t_regs;

      -- One report per step, for sim/trace.vhd
      retire_o     : out t_retire;

      -- What FETCH and DECODE did in each cycle, for the fetch statistics,
      -- src/fetch_stats.vhd (MICROARCH.md §8.1). The multi-cycle core has no
      -- such port.
      stats_o      : out t_fetch_events
   );
end entity pipeline;

architecture synthesis of pipeline is

   -- FETCH
   signal f_addr     : std_logic_vector(31 downto 0);
   signal f_blk      : std_logic_vector(31 downto 5);
   signal f_end      : std_logic_vector(31 downto 0);
   signal f_words    : t_words4;
   signal f_count    : natural range 0 to 4;
   signal f_consume  : natural range 0 to 4;
   signal f_redirect : std_logic;
   signal f_target   : std_logic_vector(31 downto 0);
   signal f_stop     : std_logic;
   signal f_stats    : t_fetch_events;
   signal f_stb      : std_logic;   -- FETCH's request, before f_block
   signal f_stall    : std_logic;
   signal f_redir_r  : std_logic;   -- FETCH was redirected a cycle ago
   signal w_redir_r  : std_logic;   -- WRITE flushed a cycle ago: FETCH follows now
   signal w_target_r : std_logic_vector(31 downto 0);
   signal f_hold_r   : std_logic;   -- FETCH waits for the store in DBUS
   signal f_held_r   : std_logic;   -- The bus stalled FETCH's request a cycle ago
   signal f_block    : std_logic;   -- FETCH makes no new request now

   -- DECODE
   signal d_redirect : std_logic;
   signal d_dest     : std_logic_vector(31 downto 0);
   signal d_flush    : std_logic;   -- DECODE drops what it holds and takes
   signal dec_r      : t_inst;
   signal dec_q      : t_inst;
   signal skid       : t_inst;      -- The instruction of DECODE's skid_r
   signal seq_uop    : t_uop;
   signal d_valid    : std_logic;
   signal d_starve   : std_logic;
   signal d_blocked  : std_logic;

   -- PREPARE
   signal p_ready      : std_logic;
   signal prep_r       : t_uop;
   signal p_out        : t_uop;
   signal p_load       : std_logic;
   signal p_first_read : std_logic;
   signal p_valid      : std_logic;
   signal rd_stb_r     : std_logic;
   signal rd_addr_r    : std_logic_vector(31 downto 0);
   signal rd_count     : std_logic;   -- Counts an instruction on instret_o

   -- DBUS
   signal rq_r       : t_words(0 to C_MAX_OUT - 1);
   signal rq_cnt_r   : natural range 0 to C_MAX_OUT;
   signal ack_read   : std_logic;
   signal tag_cnt_r  : natural range 0 to C_MAX_OUT;
   signal reads_owed : natural range 0 to C_MAX_OUT;   -- Reads accepted, without their ACK
   signal st_valid   : std_logic;                      -- A store waits in DBUS
   signal st_acc     : std_logic;                      -- The bus accepts it now

   -- WRITE
   signal w_r       : t_write;
   signal w_done    : std_logic;   -- The micro-operation in WRITE retires
   signal w_flush   : std_logic;
   signal w_target  : std_logic_vector(31 downto 0);
   signal w_ready   : std_logic;   -- WRITE is free for the micro-operation in PREPARE
   signal w_pop     : natural range 0 to 2;
   signal w_st      : std_logic;   -- WRITE puts a store or a vector read into DBUS
   signal w_st_we   : std_logic;   -- A store
   signal w_st_addr : std_logic_vector(31 downto 0);
   signal w_st_data : std_logic_vector(31 downto 0);
   signal w_instret : std_logic;
   signal take_nmi  : std_logic;
   signal take_irq  : std_logic;

begin

   ---------------------------------------------------------------------------
   -- FETCH
   ---------------------------------------------------------------------------

   -- WRITE's redirect reaches FETCH a cycle after its flush, from
   -- registers, so that no path runs from WRITE's decisions into FETCH's
   -- adders (MICROARCH.md §5.4). In between, FETCH goes on with the old
   -- stream, and DECODE drops what it takes from it.
   f_redirect <= w_redir_r or d_redirect;
   f_target   <= w_target_r when w_redir_r = '1' else d_dest;
   f_stop     <= '0' when w_r.mode = RUN_ST else '1';
   d_flush    <= w_flush or w_redir_r;

   -- WRITE checks a store against the words that FETCH holds and will
   -- request in the next cycle (MICROARCH.md §5.5), but the store reaches
   -- memory a cycle or more later, from DBUS. So FETCH puts no new request
   -- on the bus while the store waits there after that cycle, or after a
   -- redirect in the cycle the store was queued, the one before, or the
   -- one after, for WRITE's own flush, which the check did not see. A
   -- request that the bus stalls stays on it: it was in FETCH's range when
   -- WRITE checked the store. A vector read in the register holds FETCH
   -- too, but FETCH is stopped during an interrupt entry anyway.
   f_block    <= f_hold_r and st_valid and not f_held_r;
   ibus_stb_o <= f_stb and not f_block;
   f_stall    <= ibus_stall_i or f_block;

   p_hold : process (clk_i)
   begin
      if rising_edge(clk_i) then
         f_redir_r  <= f_redirect;
         w_redir_r  <= w_flush;
         w_target_r <= w_target;
         f_hold_r   <= (st_valid and not st_acc) or
                       (w_st and (w_flush or f_redirect or f_redir_r));
         f_held_r  <= f_stb and not f_block and ibus_stall_i;
         if rst_i = '1' then
            f_redir_r <= '0';
            w_redir_r <= '0';
            f_hold_r  <= '0';
            f_held_r  <= '0';
         end if;
      end if;
   end process p_hold;


   i_pipe_fetch : entity work.pipe_fetch
      generic map (
         G_FORMAL => G_FORMAL
      )
      port map (
         clk_i           => clk_i,
         rst_i           => rst_i,
         ibus_cyc_o      => ibus_cyc_o,
         ibus_stb_o      => f_stb,
         ibus_stall_i    => f_stall,
         ibus_ack_i      => ibus_ack_i,
         ibus_addr_o     => ibus_addr_o,
         ibus_data_i     => ibus_data_i,
         redirect_i      => f_redirect,
         redirect_addr_i => f_target,
         stop_i          => f_stop,
         addr_o          => f_addr,
         blk_o           => f_blk,
         words_o         => f_words,
         count_o         => f_count,
         consume_i       => f_consume,
         end_o           => f_end,
         stats_o         => f_stats
      ); -- i_pipe_fetch


   i_pipe_decode : entity work.pipe_decode
      port map (
         clk_i      => clk_i,
         rst_i      => rst_i,
         f_addr_i   => f_addr,
         f_words_i  => f_words,
         f_count_i  => f_count,
         consume_o  => f_consume,
         redirect_o => d_redirect,
         target_o   => d_dest,
         flush_i    => d_flush,
         valid_o    => d_valid,
         ready_i    => p_ready,
         uop_o      => seq_uop,
         inst_o     => dec_r,
         inst2_o    => dec_q,
         skid_o     => skid,
         starve_o   => d_starve,
         blocked_o  => d_blocked
      ); -- i_pipe_decode


   i_pipe_prepare : entity work.pipe_prepare
      port map (
         clk_i        => clk_i,
         rst_i        => rst_i,
         valid_i      => d_valid,
         uop_i        => seq_uop,
         ready_o      => p_ready,
         w_i          => w_r,
         done_i       => w_done,
         flush_i      => w_flush,
         ready_i      => w_ready,
         take_nmi_i   => take_nmi,
         take_irq_i   => take_irq,
         nmi_valid_i  => nmi_valid_i,
         irq_valid_i  => irq_valid_i,
         valid_o      => p_valid,
         uop_o        => p_out,
         first_read_o => p_first_read,
         prep_o       => prep_r,
         dbus_stall_i => dbus_stall_i,
         tag_cnt_i    => tag_cnt_r,
         st_valid_i   => st_valid,
         st_acc_i     => st_acc,
         rd_stb_o     => rd_stb_r,
         rd_addr_o    => rd_addr_r,
         load_o       => p_load,
         count_o      => rd_count
      ); -- i_pipe_prepare


   i_pipe_dbus : entity work.pipe_dbus
      port map (
         clk_i        => clk_i,
         rst_i        => rst_i,
         rd_stb_i     => rd_stb_r,
         rd_addr_i    => rd_addr_r,
         w_pop_i      => w_pop,
         st_i         => w_st,
         st_we_i      => w_st_we,
         st_addr_i    => w_st_addr,
         st_data_i    => w_st_data,
         st_valid_o   => st_valid,
         st_acc_o     => st_acc,
         rq_o         => rq_r,
         rq_cnt_o     => rq_cnt_r,
         ack_read_o   => ack_read,
         tag_cnt_o    => tag_cnt_r,
         reads_owed_o => reads_owed,
         dbus_cyc_o   => dbus_cyc_o,
         dbus_stb_o   => dbus_stb_o,
         dbus_stall_i => dbus_stall_i,
         dbus_ack_i   => dbus_ack_i,
         dbus_we_o    => dbus_we_o,
         dbus_addr_o  => dbus_addr_o,
         dbus_data_o  => dbus_data_o,
         dbus_data_i  => dbus_data_i
      ); -- i_pipe_dbus


   i_pipe_write : entity work.pipe_write
      port map (
         clk_i        => clk_i,
         rst_i        => rst_i,
         valid_i      => p_valid,
         uop_i        => p_out,
         first_read_i => p_first_read,
         rd_stb_i     => rd_stb_r,
         ready_o      => w_ready,
         f_addr_i     => f_addr,
         f_blk_i      => f_blk,
         dec_i        => dec_r,
         dec2_i       => dec_q,
         skid_i       => skid,
         prep_i       => prep_r,
         rq_i         => rq_r,
         rq_cnt_i     => rq_cnt_r,
         ack_read_i   => ack_read,
         dbus_data_i  => dbus_data_i,
         pop_o        => w_pop,
         st_valid_i   => st_valid,
         st_acc_i     => st_acc,
         st_o         => w_st,
         st_we_o      => w_st_we,
         st_addr_o    => w_st_addr,
         st_data_o    => w_st_data,
         nmi_valid_i  => nmi_valid_i,
         nmi_vector_i => nmi_vector_i,
         irq_valid_i  => irq_valid_i,
         irq_vector_i => irq_vector_i,
         take_nmi_o   => take_nmi,
         take_irq_o   => take_irq,
         state_o      => w_r,
         done_o       => w_done,
         flush_o      => w_flush,
         target_o     => w_target,
         instret_o    => w_instret,
         retire_o     => retire_o
      ); -- i_pipe_write


   nmi_ready_o <= take_nmi;
   irq_ready_o <= take_irq;
   -- Once FETCH has no request left, so that a halted core makes no new
   -- request on either bus. FETCH may make one in the cycle of the halt,
   -- before WRITE's redirect reaches it, and its wait for a store in DBUS
   -- may hold one back.
   halted_o  <= '1' when w_r.mode = HALTED_ST and st_valid = '0' and f_stb = '0' else '0';
   instret_o <= rd_count or w_instret;
   regs_o    <= w_r.regs;


   p_stats : process (all)
      variable stats_v : t_fetch_events;
   begin
      stats_v         := f_stats;
      -- Only the bus's stalls, not FETCH's waits for a store in DBUS
      stats_v.stall   := f_stb and not f_block and ibus_stall_i;
      stats_v.starve  := d_starve;
      stats_v.blocked := d_blocked;
      stats_v.words   := f_consume;
      stats_v.jump    := d_redirect;
      stats_v.flush   := w_flush;
      stats_o         <= stats_v;
   end process p_stats;


   -- The invariants that the theory of operation above relies on.
   p_check : process (clk_i)
      variable stb_v    : std_logic := '0';   -- The instruction bus a cycle ago
      variable stall_v  : std_logic := '0';
      variable st_may_v : std_logic := '0';   -- An access could wait in DBUS now
   begin
      if rising_edge(clk_i) then
         if rst_i = '0' then
            assert not (rd_count = '1' and w_instret = '1')
               report "pipeline: two instructions counted in one cycle"
               severity failure;
            assert not (d_valid = '1' and p_ready = '1' and not decoded_ok(seq_uop))
               report "pipeline: DECODE's fields disagree with the instruction word"
               severity failure;
            assert not (st_valid = '1' and rd_stb_r = '1')
               report "pipeline: a read of PREPARE and an access of WRITE on the bus at once"
               severity failure;
            assert not (w_st = '1' and st_valid = '1' and st_acc = '0')
               report "pipeline: an access queued while DBUS's register is full"
               severity failure;
            -- No flush or interrupt drops an instruction in PREPARE that has
            -- made a data read (src/pipe_prepare.vhd, c).
            assert not ((w_flush = '1' or take_nmi = '1' or take_irq = '1') and
                        prep_r.valid = '1' and p_out.committed = '1')
               report "pipeline: a flush or interrupt drops an instruction with a data read"
               severity failure;
            -- The data of a read finds room in DBUS (src/pipe_dbus.vhd, c).
            assert not (dbus_stb_o = '1' and dbus_we_o = '0' and dbus_stall_i = '0' and
                        rq_cnt_r + reads_owed >= C_MAX_OUT + w_pop)
               report "pipeline: a read accepted without room for its data"
               severity failure;
            assert not ((w_flush = '1' or take_nmi = '1' or take_irq = '1') and
                        (rd_stb_r = '1' or p_load = '1'))
               report "pipeline: a flush or interrupt while a data read is waiting to be issued"
               severity failure;
            -- The ids tell an older instruction in WRITE from an earlier
            -- micro-operation of the one in PREPARE (src/pipe_prepare.vhd):
            -- a new instruction never has the id of the one in WRITE.
            assert not (prep_r.valid = '1' and prep_r.first = '1' and w_r.uop.valid = '1' and
                        prep_r.inst.id = w_r.uop.inst.id)
               report "pipeline: a new instruction in PREPARE has the id of the one in WRITE"
               severity failure;
            -- Every data read belongs to an instruction that retires
            -- (MICROARCH.md §9): no flush leaves read data behind, counting
            -- the data that WRITE takes from the bus in the same cycle.
            assert not (w_flush = '1' and
                        (rq_cnt_r + to_nat(ack_read) /= w_pop or reads_owed /= to_nat(ack_read)))
               report "pipeline: a flush with read data owed"
               severity failure;
            -- A halted core makes no new instruction fetch: a request still
            -- on the bus is one the bus stalled before (formal_pipeline,
            -- f_halt_ibus). FETCH may still make one after the halt, so
            -- halted_o waits until it has none.
            assert not (halted_o = '1' and ibus_stb_o = '1' and not (stb_v = '1' and stall_v = '1'))
               report "pipeline: a new instruction fetch after a halt"
               severity failure;
            -- PREPARE's assumptions about WRITE and DBUS that need no model
            -- (src/pipe_prepare.vhd, f_accept and f_st_queue). The others
            -- are checked only by the tests and the bounded check.
            assert not (w_ready = '1' and w_flush = '1')
               report "pipeline: WRITE takes a micro-operation and flushes at once"
               severity failure;
            -- An access waits in DBUS only if one was queued or held a cycle ago
            assert not (st_valid = '1' and st_may_v = '0')
               report "pipeline: an access waits in DBUS that nothing queued"
               severity failure;
         end if;
         stb_v    := ibus_stb_o;
         stall_v  := ibus_stall_i;
         st_may_v := not rst_i and ((st_valid and not st_acc) or
                                    (w_r.uop.valid and w_r.uop.store and not rd_stb_r) or
                                    (to_sl(w_r.mode = VEC_ST) and not rd_stb_r));
      end if;
   end process p_check;

end architecture synthesis;
