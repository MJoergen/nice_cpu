-- The pipelined NICE core of doc/MICROARCH.md. It has the ports of the
-- multi-cycle core, src/multicycle.vhd, and reports the same steps. Its
-- one more port, stats_o, reports what FETCH and DECODE do in each cycle,
-- for the fetch statistics, src/fetch_stats.vhd, and when PREPARE waits
-- to issue a data read, for the testbench.
--
-- THEORY OF OPERATION
-- The pipeline (MICROARCH.md §3), one entity for each part:
--
--   FETCH     src/pipe_fetch.vhd. Reads pairs of words ahead into a
--             buffer, and presents up to four of them.
--   DECODE    src/pipe_decode.vhd. Takes one whole instruction into
--             dec_r. Redirects FETCH at once for a jump it can resolve.
--             Splits the instruction in dec_r into micro-operations
--             (src/pipe_pkg.vhd), one per cycle, into prep_r.
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
-- decisions of the same cycle, and WRITE drives its stores onto the bus.
--
-- Each stage holds one item, and passes it on when the next stage is free
-- or frees itself in the same cycle.
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
-- the instruction; and every older instruction has been counted on
-- instret_o. WRITE issues stores and vector reads straight onto the bus,
-- and holds them there while the bus stalls them. The two never compete:
-- WRITE issues an access only when every read that PREPARE loaded is on the
-- bus or done. The ACKs come back in order. A FIFO of tags tells reads from
-- writes, and a FIFO holds the data of reads that WRITE has not used yet.
--
-- CONTROL FLOW (MICROARCH.md §5.4). WRITE flushes every younger stage and
-- redirects FETCH after an instruction that wrote R15, after RTI, at the
-- start and end of an interrupt entry or INT, after a halt, and after a
-- store into a word that is fetched but not retired (MICROARCH.md §5.5).
-- Those words are the range that pipe_fetch reports and the instructions in
-- dec_r and prep_r. DECODE redirects FETCH itself for "MOVE R15, c" and
-- "ADD R15, R15, c" with condition "always". WRITE then does not flush.
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

   -- DECODE
   signal d_redirect : std_logic;
   signal d_dest     : std_logic_vector(31 downto 0);
   signal dec_r      : t_inst;
   signal dec_q      : t_inst;
   signal seq_uop    : t_uop;
   signal seq_emit   : std_logic;
   signal d_starve   : std_logic;
   signal d_blocked  : std_logic;

   -- PREPARE
   signal p_ready      : std_logic;
   signal prep_r       : t_uop;
   signal p_out        : t_uop;
   signal p_load       : std_logic;
   signal p_first_read : std_logic;
   signal p_move       : std_logic;
   signal rd_stb_r     : std_logic;
   signal rd_addr_r    : std_logic_vector(31 downto 0);
   signal rd_count     : std_logic;   -- Counts an instruction on instret_o
   signal p_wait_sr    : std_logic;
   signal p_wait_wr    : std_logic;

   -- DBUS
   signal rq_r       : t_words(0 to C_MAX_OUT - 1);
   signal rq_cnt_r   : natural range 0 to C_MAX_OUT;
   signal ack_read   : std_logic;
   signal tag_cnt_r  : natural range 0 to C_MAX_OUT;
   signal reads_owed : natural range 0 to C_MAX_OUT;   -- Reads accepted, without their ACK

   -- WRITE
   signal w_r       : t_write;
   signal w_done    : std_logic;   -- The micro-operation in WRITE retires
   signal w_flush   : std_logic;
   signal w_target  : std_logic_vector(31 downto 0);
   signal w_accept  : std_logic;   -- WRITE takes the micro-operation in PREPARE
   signal w_req     : std_logic;
   signal w_we      : std_logic;
   signal w_addr    : std_logic_vector(31 downto 0);
   signal w_data    : std_logic_vector(31 downto 0);
   signal w_pop     : natural range 0 to 2;
   signal w_instret : std_logic;
   signal take_nmi  : std_logic;
   signal take_irq  : std_logic;

begin

   ---------------------------------------------------------------------------
   -- FETCH
   ---------------------------------------------------------------------------

   f_redirect <= w_flush or d_redirect;
   f_target   <= w_target when w_flush = '1' else d_dest;
   f_stop     <= '0' when w_r.mode = RUN_ST else '1';


   i_pipe_fetch : entity work.pipe_fetch
      generic map (
         G_FORMAL => G_FORMAL
      )
      port map (
         clk_i           => clk_i,
         rst_i           => rst_i,
         ibus_cyc_o      => ibus_cyc_o,
         ibus_stb_o      => ibus_stb_o,
         ibus_stall_i    => ibus_stall_i,
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
         flush_i    => w_flush,
         ready_i    => p_ready,
         emit_o     => seq_emit,
         uop_o      => seq_uop,
         inst_o     => dec_r,
         inst2_o    => dec_q,
         starve_o   => d_starve,
         blocked_o  => d_blocked
      ); -- i_pipe_decode


   i_pipe_prepare : entity work.pipe_prepare
      port map (
         clk_i        => clk_i,
         rst_i        => rst_i,
         emit_i       => seq_emit,
         uop_i        => seq_uop,
         ready_o      => p_ready,
         w_i          => w_r,
         done_i       => w_done,
         flush_i      => w_flush,
         accept_i     => w_accept,
         take_nmi_i   => take_nmi,
         take_irq_i   => take_irq,
         nmi_valid_i  => nmi_valid_i,
         irq_valid_i  => irq_valid_i,
         move_o       => p_move,
         uop_o        => p_out,
         first_read_o => p_first_read,
         prep_o       => prep_r,
         dbus_stall_i => dbus_stall_i,
         tag_cnt_i    => tag_cnt_r,
         rd_stb_o     => rd_stb_r,
         rd_addr_o    => rd_addr_r,
         load_o       => p_load,
         count_o      => rd_count,
         wait_sr_o    => p_wait_sr,
         wait_wr_o    => p_wait_wr
      ); -- i_pipe_prepare


   i_pipe_dbus : entity work.pipe_dbus
      port map (
         clk_i        => clk_i,
         rst_i        => rst_i,
         rd_stb_i     => rd_stb_r,
         rd_addr_i    => rd_addr_r,
         w_req_i      => w_req,
         w_we_i       => w_we,
         w_addr_i     => w_addr,
         w_data_i     => w_data,
         w_pop_i      => w_pop,
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
         move_i       => p_move,
         uop_i        => p_out,
         first_read_i => p_first_read,
         rd_stb_i     => rd_stb_r,
         accept_o     => w_accept,
         f_addr_i     => f_addr,
         f_blk_i      => f_blk,
         dec_i        => dec_r,
         dec2_i       => dec_q,
         prep_i       => prep_r,
         rq_i         => rq_r,
         rq_cnt_i     => rq_cnt_r,
         ack_read_i   => ack_read,
         tag_cnt_i    => tag_cnt_r,
         dbus_stall_i => dbus_stall_i,
         dbus_data_i  => dbus_data_i,
         req_o        => w_req,
         we_o         => w_we,
         addr_o       => w_addr,
         data_o       => w_data,
         pop_o        => w_pop,
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
   halted_o    <= '1' when w_r.mode = HALTED_ST else '0';
   instret_o   <= rd_count or w_instret;


   p_stats : process (all)
      variable stats_v : t_fetch_events;
   begin
      stats_v         := f_stats;
      stats_v.starve  := d_starve;
      stats_v.blocked := d_blocked;
      stats_v.words   := f_consume;
      stats_v.jump    := d_redirect;
      stats_v.flush   := w_flush;
      stats_v.wait_sr := p_wait_sr;
      stats_v.wait_wr := p_wait_wr;
      stats_v.moved   := p_move;
      stats_o         <= stats_v;
   end process p_stats;


   -- The invariants that the theory of operation above relies on.
   p_check : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if rst_i = '0' then
            assert not (rd_count = '1' and w_instret = '1')
               report "pipeline: two instructions counted in one cycle"
               severity failure;
            assert not (seq_emit = '1' and not decoded_ok(seq_uop))
               report "pipeline: DECODE's fields disagree with the instruction word"
               severity failure;
            assert not (rd_stb_r = '1' and w_req = '1')
               report "pipeline: a read of PREPARE and an access of WRITE on the bus at once"
               severity failure;
            -- No flush or interrupt drops an instruction in PREPARE that has
            -- made a data read (src/pipe_prepare.vhd, c).
            assert not ((w_flush = '1' or take_nmi = '1' or take_irq = '1') and
                        prep_r.valid = '1' and p_out.committed = '1')
               report "pipeline: a flush or interrupt drops an instruction with a data read"
               severity failure;
            -- The data of a read finds room in DBUS (src/pipe_dbus.vhd, c).
            assert not ((rd_stb_r = '1' or (w_req = '1' and w_we = '0')) and dbus_stall_i = '0' and
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
         end if;
      end if;
   end process p_check;

end architecture synthesis;
