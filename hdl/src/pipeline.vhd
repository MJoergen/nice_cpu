-- The pipelined NICE core of doc/MICROARCH.md. It has the ports of the
-- multi-cycle core, src/multicycle.vhd, and reports the same steps.
--
-- THEORY OF OPERATION
-- The pipeline (MICROARCH.md §3):
--
--   FETCH, ICACHE  src/pipe_fetch.vhd. Reads pairs of words ahead, and
--                  presents up to four of them.
--   DECODE         Takes one whole instruction from ICACHE into dec_r.
--                  Redirects FETCH at once for a jump it can resolve.
--   SEQUENCER      Splits the instruction in dec_r into micro-operations
--                  (src/pipe_pkg.vhd), one per cycle, into prep_r.
--   PREPARE        Tests the condition, and issues the data reads of the
--                  micro-operation in prep_r. Then passes it to w_r.uop.
--   WRITE          Runs the micro-operation in w_r.uop: computes the
--                  result, writes the registers, issues the store, and
--                  updates the flags. Takes interrupts, runs the control
--                  instructions, and flushes the pipeline.
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
-- younger read only then. So a read of INSTR_LO (ISA.md §8.5) counts every
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
      -- interrupt entry, for the instruction counter (ISA.md §8.5)
      instret_o    : out std_logic;

      -- One report per step, for sim/trace.vhd
      retire_o     : out t_retire
   );
end entity pipeline;

architecture synthesis of pipeline is

   -- Data bus requests in flight, the ACKs owed
   constant C_MAX_OUT : natural := 4;

   type t_wmode is (RUN_ST, VEC_ST, HALTED_ST);

   type t_words is array (natural range <>) of std_logic_vector(31 downto 0);

   -- The state of WRITE
   type t_write is record
      uop        : t_uop;
      mode       : t_wmode;
      regs       : t_regs;
      in_service : std_logic;
      after_rti  : std_logic;
      saved_pc   : std_logic_vector(31 downto 0);
      saved_sr   : std_logic_vector(31 downto 0);
      halt       : t_halt;
      cond       : std_logic;                       -- The condition of the instruction
      mid        : std_logic;                       -- Part of an instruction has retired
      jump       : std_logic;                       -- The instruction has written R15
      s0val      : std_logic_vector(31 downto 0);   -- s0, from S0 or S1
      s1val      : std_logic_vector(31 downto 0);   -- s1, from S1
      busy       : std_logic;                       -- An access waits on the bus
      vec        : std_logic_vector(7 downto 0);    -- In VEC_ST: the vector
      vec_intr   : std_logic;                       -- An interrupt, not INT
      vec_nmi    : std_logic;
      vec_issued : std_logic;                       -- The vector read is on its way
      commits    : natural range 0 to 3;            -- Committed instructions in flight
      rep        : t_retire;                        -- The report, but its registers
   end record t_write;

   -- The value of a source field that is not in memory (ISA.md §4.1).
   function src_value(m : std_logic_vector(2 downto 0);
                      x : natural range 0 to 15;
                      b : std_logic_vector(31 downto 0);
                      c : std_logic_vector(31 downto 0)) return std_logic_vector is
   begin
      case m is
         when "001"  => return regval(x, b - 1);
         when "011"  => return b + c;
         when others => return b;
      end case;
   end function src_value;

   -- The address of a memory operand, source or destination, before any
   -- side effect of its own (ISA.md §4.1 and §4.2).
   function mem_addr(m : std_logic_vector(2 downto 0);
                     x : natural range 0 to 15;
                     b : std_logic_vector(31 downto 0);
                     c : std_logic_vector(31 downto 0)) return std_logic_vector is
   begin
      case m is
         when "101"         => return regval(x, b - 1);
         when "011" | "111" => return b + c;
         when others        => return b;
      end case;
   end function mem_addr;

   -- a lies in the range lo to hi - 1, modulo 2^32.
   function in_range(a  : std_logic_vector(31 downto 0);
                     lo : std_logic_vector(31 downto 0);
                     hi : std_logic_vector(31 downto 0)) return boolean is
   begin
      return a - lo < hi - lo;
   end function in_range;

   function popcount(v : std_logic_vector) return natural is
      variable res_v : natural := 0;
   begin
      for i in v'range loop
         if v(i) = '1' then
            res_v := res_v + 1;
         end if;
      end loop;
      return res_v;
   end function popcount;

   -- FETCH and ICACHE
   signal f_addr     : std_logic_vector(31 downto 0);
   signal f_end      : std_logic_vector(31 downto 0);
   signal f_words    : t_words4;
   signal f_count    : natural range 0 to 4;
   signal f_consume  : natural range 0 to 4;
   signal f_redirect : std_logic;
   signal f_target   : std_logic_vector(31 downto 0);
   signal f_stop     : std_logic;

   -- DECODE
   signal d_inst  : t_inst;
   signal d_ok    : std_logic;
   signal d_load  : std_logic;
   signal d_early : std_logic;
   signal d_dest  : std_logic_vector(31 downto 0);
   signal id_r    : std_logic_vector(2 downto 0);

   -- SEQUENCER
   signal dec_r       : t_inst;
   signal seq_kind_r  : t_kind;
   signal seq_first_r : std_logic;
   signal seq_uop     : t_uop;
   signal seq_emit    : std_logic;
   signal dec_free    : std_logic;

   -- PREPARE
   signal prep_r        : t_uop;
   signal p_loaded_r    : natural range 0 to 2;   -- Reads of prep_r loaded
   signal p_ck_r        : std_logic;              -- The instruction's condition is known
   signal p_cv_r        : std_logic;              -- and is this
   signal p_committed_r : std_logic;
   signal p_counted_r   : std_logic;
   signal p_out         : t_uop;
   signal p_load        : std_logic;
   signal p_first_read  : std_logic;
   signal p_last_read   : std_logic;
   signal p_addr        : std_logic_vector(31 downto 0);
   signal p_move        : std_logic;
   signal rd_last_r     : std_logic;              -- rd_stb_r is its instruction's last read
   signal rd_count      : std_logic;              -- Counts that instruction on instret_o

   -- The data bus
   signal rd_stb_r  : std_logic;
   signal rd_addr_r : std_logic_vector(31 downto 0);
   signal tags_r    : std_logic_vector(0 to C_MAX_OUT - 1);   -- '1' for a write
   signal tag_cnt_r : natural range 0 to C_MAX_OUT;
   signal rq_r      : t_words(0 to C_MAX_OUT - 1);            -- Read data not used yet
   signal rq_cnt_r  : natural range 0 to C_MAX_OUT;
   signal dbus_stb  : std_logic;
   signal accept    : std_logic;
   signal ack_read  : std_logic;

   -- WRITE
   signal w_r        : t_write;
   signal w_n        : t_write;
   signal w_done     : std_logic;                      -- The micro-operation in WRITE retires
   signal w_flush    : std_logic;
   signal w_target   : std_logic_vector(31 downto 0);
   signal w_accept   : std_logic;                      -- WRITE takes the micro-operation in PREPARE
   signal w_req      : std_logic;
   signal w_we       : std_logic;
   signal w_addr     : std_logic_vector(31 downto 0);
   signal w_data     : std_logic_vector(31 downto 0);
   signal w_pop      : natural range 0 to 2;
   signal w_instret  : std_logic;
   signal take_nmi   : std_logic;
   signal take_irq   : std_logic;
   signal reads_owed : natural range 0 to C_MAX_OUT;   -- Reads accepted, without their ACK

begin

   ---------------------------------------------------------------------------
   -- FETCH and ICACHE
   ---------------------------------------------------------------------------

   f_redirect <= w_flush or (d_load and d_early);
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
         words_o         => f_words,
         count_o         => f_count,
         consume_i       => f_consume,
         end_o           => f_end
      ); -- i_pipe_fetch


   ---------------------------------------------------------------------------
   -- DECODE
   ---------------------------------------------------------------------------

   p_decode : process (all)
      variable inst_v  : t_inst;
      variable cf_v    : std_logic_vector(0 to 2);
      variable k_v     : natural range 1 to 4;
      variable len_v   : natural range 1 to 4;
      variable iw_v    : std_logic_vector(31 downto 0);
      variable early_v : std_logic;
      variable dest_v  : std_logic_vector(31 downto 0);
   begin
      iw_v           := f_words(0);
      cf_v           := const_fields(iw_v);
      len_v          := inst_len(iw_v);
      inst_v         := C_INST_NONE;
      inst_v.valid   := '1';
      inst_v.id      := id_r;
      inst_v.addr    := f_addr;
      inst_v.next_pc := f_addr + len_v;
      inst_v.iw      := iw_v;
      k_v            := 1;
      for i in 0 to 2 loop
         if cf_v(i) = '1' then
            inst_v.consts(i) := f_words(k_v);
            k_v              := minimum(k_v + 1, 3);
         end if;
      end loop;

      -- The jumps that DECODE resolves (MICROARCH.md §5.4): condition
      -- "always", an ALU instruction, and the destination R15 in mode 000.
      -- "MOVE R15, c" with s1 unused, and "ADD R15, R15, c" or
      -- "ADD R15, c, R15" without the C bit. They read no register but R15,
      -- and nothing changes R15 before them in the instruction.
      early_v := '0';
      dest_v  := inst_v.consts(1);
      if iw_v(31 downto 27) = "00000" and field(iw_v, 0) = "0001111" then
         if iw_v(26 downto 21) = "000000" and field(iw_v, 1) = "0110000" and
            field(iw_v, 2) = "0000000" then
            early_v := '1';
         elsif iw_v(26) = '0' and iw_v(24 downto 21) = "0011" then
            if field(iw_v, 1) = "0001111" and field(iw_v, 2) = "0110000" then
               early_v := '1';
               dest_v  := inst_v.next_pc + inst_v.consts(2);
            elsif field(iw_v, 1) = "0110000" and field(iw_v, 2) = "0001111" then
               early_v := '1';
               dest_v  := inst_v.next_pc + inst_v.consts(1);
            end if;
         end if;
      end if;
      inst_v.early := early_v;
      d_early      <= early_v;
      d_dest       <= dest_v;

      d_inst <= inst_v;
      d_ok   <= '1' when f_count >= len_v else '0';
   end process p_decode;

   d_load    <= d_ok and dec_free and not w_flush;
   f_consume <= inst_len(f_words(0)) when d_load = '1' else 0;


   ---------------------------------------------------------------------------
   -- SEQUENCER
   ---------------------------------------------------------------------------

   p_seq_uop : process (all)
      variable uop_v : t_uop;
   begin
      uop_v       := C_UOP_NONE;
      uop_v.valid := dec_r.valid;
      uop_v.inst  := dec_r;
      uop_v.kind  := seq_kind_r;
      uop_v.first := seq_first_r;
      uop_v.last  := is_last(seq_kind_r);
      seq_uop     <= uop_v;
   end process p_seq_uop;

   seq_emit <= dec_r.valid and (not prep_r.valid or p_move) and not w_flush;
   dec_free <= not dec_r.valid or (seq_emit and seq_uop.last);


   p_seq : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if seq_emit = '1' then
            seq_kind_r  <= next_kind(dec_r.iw, seq_kind_r);
            seq_first_r <= '0';
            if seq_uop.last = '1' then
               dec_r.valid <= '0';
            end if;
         end if;

         if d_load = '1' then
            dec_r       <= d_inst;
            seq_kind_r  <= first_kind(d_inst.iw);
            seq_first_r <= '1';
            id_r        <= id_r + 1;
         end if;

         if w_flush = '1' then
            dec_r.valid <= '0';
         end if;

         if rst_i = '1' then
            dec_r       <= C_INST_NONE;
            seq_kind_r  <= UOP_OP;
            seq_first_r <= '0';
            id_r        <= (others => '0');
         end if;
      end if;
   end process p_seq;


   ---------------------------------------------------------------------------
   -- PREPARE
   ---------------------------------------------------------------------------

   p_prepare : process (all)
      variable u_v       : t_uop;
      variable wu_v      : t_uop;
      variable older_v   : boolean;   -- WRITE holds an older instruction
      variable ck_v      : std_logic;
      variable cv_v      : std_logic;
      variable rd_v      : std_logic_vector(1 to 2);
      variable nr_v      : natural range 0 to 2;
      variable f_v       : natural range 1 to 2;
      variable x_v       : natural range 0 to 15;
      variable b_v       : std_logic_vector(31 downto 0);
      variable busy_v    : boolean;   -- WRITE will still write the base
      variable older_ok  : boolean;
      variable intr_ok   : boolean;
      variable bus_ok    : boolean;
      variable started_v : boolean;
      variable load_v    : std_logic;
      variable irq_v     : boolean;
   begin
      u_v     := prep_r;
      wu_v    := w_r.uop;
      older_v := wu_v.valid = '1' and wu_v.inst.id /= u_v.inst.id;

      -- The condition (ISA.md §3), against SR before the instruction
      ck_v := '0';
      cv_v := condition(u_v.inst.iw, w_r.regs(14));
      if u_v.first = '1' then
         if w_r.mode = RUN_ST and
            not (wu_v.valid = '1' and uop_may_sr(wu_v.inst.iw, wu_v.kind)) then
            ck_v := '1';
         end if;
      elsif p_ck_r = '1' then
         ck_v := '1';
         cv_v := p_cv_r;
      elsif wu_v.valid = '0' and w_r.mode = RUN_ST then
         -- The instruction's first micro-operation has retired.
         ck_v := '1';
         cv_v := w_r.cond;
      end if;

      -- The next read to load: s0, then s1
      rd_v := uop_reads(u_v.inst.iw, u_v.kind);
      nr_v := popcount(rd_v);
      if p_loaded_r = 0 and rd_v(1) = '1' then
         f_v := 1;
      else
         f_v := 2;
      end if;
      x_v := reg(u_v.inst.iw, f_v);
      if x_v = 15 then
         b_v := w_r.regs(15) when not older_v and w_r.jump = '1' else u_v.inst.next_pc;
      else
         b_v := w_r.regs(x_v);
      end if;
      p_addr <= mem_addr(mode(u_v.inst.iw, f_v), x_v, b_v, u_v.inst.consts(f_v));

      busy_v := wu_v.valid = '1' and x_v /= 0 and
                ((x_v = 14 and uop_may_sr(wu_v.inst.iw, wu_v.kind)) or
                 (x_v /= 14 and uop_wreg(wu_v.inst.iw, wu_v.kind) = x_v));

      -- The older micro-operation in WRITE will not jump, halt, or store
      -- into fetched code, and is counted on instret_o. Either it retires
      -- now, or it has made its reads and makes no store.
      older_ok := not older_v or (w_done = '1' and w_flush = '0') or
                  (not uop_store(wu_v.inst.iw, wu_v.kind) and
                   not uop_may_jump(wu_v.inst.iw, wu_v.kind) and
                   w_r.jump = '0' and wu_v.counted = '1');

      -- No interrupt may be taken before this instruction (MICROARCH.md
      -- §5.3, rule 4). None can be if the instruction has made a data read
      -- or begun to retire, or follows RTI directly.
      started_v := not older_v and
                   ((wu_v.valid = '1' and wu_v.first = '0') or (wu_v.valid = '0' and w_r.mid = '1'));
      irq_v     := irq_valid_i = '1' and w_r.in_service = '0' and
                   (w_r.regs(14)(C_SR_E) = '1' or
                    (wu_v.valid = '1' and uop_may_sr(wu_v.inst.iw, wu_v.kind)));
      intr_ok   := started_v or p_committed_r = '1' or (not older_v and w_r.after_rti = '1') or
                   not ((nmi_valid_i = '1' and w_r.in_service = '0') or irq_v);

      bus_ok := (rd_stb_r = '0' or dbus_stall_i = '0') and
                tag_cnt_r + to_nat(rd_stb_r) < C_MAX_OUT;

      load_v := '0';
      if u_v.valid = '1' and ck_v = '1' and cv_v = '1' and p_loaded_r < nr_v and
         older_ok and intr_ok and not busy_v and bus_ok and
         w_r.mode = RUN_ST and w_flush = '0' and take_nmi = '0' and take_irq = '0' then
         load_v := '1';
      end if;
      p_load       <= load_v;
      p_first_read <= load_v and not p_committed_r;
      p_last_read  <= '0';
      if load_v = '1' and p_loaded_r + 1 = nr_v and not later_reads(u_v.inst.iw, u_v.kind) then
         p_last_read <= '1';
      end if;

      -- The micro-operation may go on when its reads are loaded, or it has
      -- none, or its condition is false.
      p_move <= '0';
      if u_v.valid = '1' and w_accept = '1' then
         if nr_v = 0 or (ck_v = '1' and (cv_v = '0' or p_loaded_r + to_nat(load_v) = nr_v)) then
            p_move <= '1';
         end if;
      end if;

      u_v.cond_known := ck_v;
      u_v.cond_val   := cv_v;
      u_v.committed  := p_committed_r or load_v;
      u_v.counted    := p_counted_r;
      if load_v = '1' and p_loaded_r + 1 = nr_v and not later_reads(u_v.inst.iw, u_v.kind) then
         u_v.counted := '1';
      end if;
      p_out <= u_v;
   end process p_prepare;


   p_prepare_reg : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if dbus_stall_i = '0' then
            rd_stb_r <= '0';
         end if;

         if p_load = '1' then
            rd_stb_r      <= '1';
            rd_addr_r     <= p_addr;
            rd_last_r     <= p_last_read;
            p_loaded_r    <= p_loaded_r + 1;
            p_committed_r <= '1';
            if p_last_read = '1' then
               p_counted_r <= '1';
            end if;
         end if;

         if p_move = '1' then
            p_loaded_r <= 0;
            if prep_r.first = '1' then
               p_ck_r <= p_out.cond_known;
               p_cv_r <= p_out.cond_val;
            end if;
            if prep_r.last = '1' then
               p_ck_r        <= '0';
               p_committed_r <= '0';
               p_counted_r   <= '0';
            end if;
            prep_r.valid <= '0';
         end if;

         if seq_emit = '1' then
            prep_r <= seq_uop;
         end if;

         if w_flush = '1' then
            prep_r.valid  <= '0';
            p_loaded_r    <= 0;
            p_ck_r        <= '0';
            p_committed_r <= '0';
            p_counted_r   <= '0';
         end if;

         if rst_i = '1' then
            prep_r        <= C_UOP_NONE;
            p_loaded_r    <= 0;
            p_ck_r        <= '0';
            p_cv_r        <= '0';
            p_committed_r <= '0';
            p_counted_r   <= '0';
            rd_stb_r      <= '0';
            rd_last_r     <= '0';
         end if;
      end if;
   end process p_prepare_reg;


   ---------------------------------------------------------------------------
   -- The data bus
   ---------------------------------------------------------------------------

   dbus_stb    <= rd_stb_r or w_req;
   dbus_stb_o  <= dbus_stb;
   dbus_cyc_o  <= '1' when dbus_stb = '1' or tag_cnt_r > 0 else '0';
   dbus_we_o   <= w_we when w_req = '1' else '0';
   dbus_addr_o <= w_addr when w_req = '1' else rd_addr_r;
   dbus_data_o <= w_data;
   accept      <= dbus_stb and not dbus_stall_i;
   ack_read    <= dbus_ack_i and not tags_r(0);


   p_dbus : process (clk_i)
      variable tags_v : std_logic_vector(0 to C_MAX_OUT);
      variable tcnt_v : natural range 0 to C_MAX_OUT + 1;
      variable rq_v   : t_words(0 to C_MAX_OUT);
      variable rcnt_v : natural range 0 to C_MAX_OUT + 1;
   begin
      if rising_edge(clk_i) then
         -- The tag of each accepted request, oldest first
         tags_v := tags_r & '0';
         tcnt_v := tag_cnt_r;
         if dbus_ack_i = '1' then
            tags_v := tags_v(1 to C_MAX_OUT) & '0';
            tcnt_v := tcnt_v - 1;
         end if;
         if accept = '1' then
            tags_v(tcnt_v) := w_we and w_req;
            tcnt_v         := tcnt_v + 1;
         end if;
         tags_r    <= tags_v(0 to C_MAX_OUT - 1);
         tag_cnt_r <= tcnt_v;

         -- The read data, oldest first, less what WRITE uses now
         rq_v   := rq_r & X"00000000";
         rcnt_v := rq_cnt_r;
         if ack_read = '1' then
            rq_v(rcnt_v) := dbus_data_i;
            rcnt_v       := rcnt_v + 1;
         end if;
         case w_pop is
            when 1 =>
               rq_v   := rq_v(1 to C_MAX_OUT) & X"00000000";
               rcnt_v := rcnt_v - 1;
            when 2 =>
               rq_v   := rq_v(2 to C_MAX_OUT) & X"00000000" & X"00000000";
               rcnt_v := rcnt_v - 2;
            when others =>
               null;
         end case;
         rq_r     <= rq_v(0 to C_MAX_OUT - 1);
         rq_cnt_r <= rcnt_v;

         if rst_i = '1' then
            tag_cnt_r <= 0;
            rq_cnt_r  <= 0;
         end if;
      end if;
   end process p_dbus;


   p_owed : process (all)
      variable owed_v : natural range 0 to C_MAX_OUT;
   begin
      owed_v := 0;
      for i in 0 to C_MAX_OUT - 1 loop
         if i < tag_cnt_r and tags_r(i) = '0' then
            owed_v := owed_v + 1;
         end if;
      end loop;
      reads_owed <= owed_v;
   end process p_owed;


   ---------------------------------------------------------------------------
   -- WRITE
   ---------------------------------------------------------------------------

   p_write : process (all)
      variable n_v     : t_write;
      variable u_v     : t_uop;
      variable iw_v    : std_logic_vector(31 downto 0);
      variable cond_v  : std_logic;
      variable data_v  : t_words(0 to 1);
      variable avail_v : natural range 0 to C_MAX_OUT + 1;
      variable rd_v    : std_logic_vector(1 to 2);
      variable nr_v    : natural range 0 to 2;
      variable k_v     : natural range 0 to 2;
      variable base_v  : t_fields;
      variable x_v     : natural range 0 to 15;
      variable m_v     : std_logic_vector(2 downto 0);
      variable v0_v    : std_logic_vector(31 downto 0);
      variable v1_v    : std_logic_vector(31 downto 0);
      variable res_v   : t_result;
      variable a_v     : std_logic_vector(31 downto 0);
      variable wreg_v  : natural range 0 to 15;
      variable wval_v  : std_logic_vector(31 downto 0);
      variable store_v : boolean;
      variable done_v  : boolean;
      variable flush_v : boolean;
      variable halt_v  : t_halt;
      variable rti_v   : boolean;
      variable bound_v : boolean;
      variable room_v  : boolean;
   begin
      n_v         := w_r;
      n_v.rep     := C_RETIRE_NONE;
      u_v         := w_r.uop;
      iw_v        := u_v.inst.iw;
      w_req       <= '0';
      w_we        <= '0';
      w_addr      <= (others => '0');
      w_data      <= (others => '0');
      w_pop       <= 0;
      w_instret   <= '0';
      w_flush     <= '0';
      w_target    <= w_r.regs(15);
      take_nmi    <= '0';
      take_irq    <= '0';
      done_v      := false;
      flush_v     := false;
      halt_v      := HALT_NONE;
      rti_v       := false;
      store_v     := false;
      res_v       := (r => (others => '0'), c => '0', v => '0');
      a_v         := (others => '0');
      v0_v        := (others => '0');
      v1_v        := (others => '0');
      base_v      := (others => (others => '0'));
      x_v         := 0;
      m_v         := "000";
      k_v         := 0;
      rd_v        := "00";
      nr_v        := 0;
      wreg_v      := 0;
      wval_v      := (others => '0');

      -- The read data, from the FIFO or straight from the bus
      avail_v   := rq_cnt_r + to_nat(ack_read);
      data_v(0) := rq_r(0) when rq_cnt_r >= 1 else dbus_data_i;
      data_v(1) := rq_r(1) when rq_cnt_r >= 2 else dbus_data_i;

      -- Room on the data bus for an access of WRITE's own
      room_v := rd_stb_r = '0' and tag_cnt_r < C_MAX_OUT;

      -- The condition (ISA.md §3)
      if u_v.cond_known = '1' then
         cond_v := u_v.cond_val;
      elsif u_v.first = '1' then
         cond_v := condition(iw_v, w_r.regs(14));
      else
         cond_v := w_r.cond;
      end if;

      -- An instruction boundary where ISA.md §7.1 allows an interrupt, and
      -- no data access of the next instruction has begun.
      bound_v := w_r.mode = RUN_ST and rst_i = '0' and w_r.commits = 0 and w_r.mid = '0' and
                 w_r.busy = '0' and (u_v.valid = '0' or u_v.first = '1') and
                 w_r.in_service = '0' and w_r.after_rti = '0';

      if bound_v and nmi_valid_i = '1' then
         take_nmi     <= '1';
         n_v.vec      := nmi_vector_i;
         n_v.vec_nmi  := '1';
      elsif bound_v and irq_valid_i = '1' and w_r.regs(14)(C_SR_E) = '1' then
         take_irq     <= '1';
         n_v.vec      := irq_vector_i;
         n_v.vec_nmi  := '0';
      end if;

      if bound_v and (nmi_valid_i = '1' or (irq_valid_i = '1' and w_r.regs(14)(C_SR_E) = '1')) then
         -- ISA.md §7.2. The micro-operation in WRITE has not begun, so it
         -- goes with the rest of the pipeline.
         n_v.mode       := VEC_ST;
         n_v.vec_intr   := '1';
         n_v.vec_issued := '0';
         n_v.uop.valid  := '0';
         flush_v        := true;
      elsif w_r.mode = VEC_ST then
         -- The vector table entry is at VBASE * 256 + v.
         if w_r.vec_issued = '0' then
            if room_v then
               w_req          <= '1';
               w_addr         <= w_r.regs(14)(23 downto 0) & w_r.vec;
               n_v.busy       := dbus_stall_i;
               n_v.vec_issued := not dbus_stall_i;
            end if;
         elsif avail_v >= 1 then
            w_pop        <= 1;
            n_v.saved_pc := w_r.regs(15) when w_r.vec_intr = '1' else u_v.inst.next_pc;
            n_v.saved_sr := w_r.regs(14);
            n_v.in_service    := '1';
            n_v.regs(14)(C_SR_I) := '1';
            n_v.regs(15) := data_v(0);
            n_v.mode     := RUN_ST;
            n_v.uop.valid := '0';
            flush_v      := true;

            n_v.rep.valid  := '1';
            n_v.rep.intr   := w_r.vec_intr;
            n_v.rep.nmi    := w_r.vec_nmi;
            n_v.rep.vector := w_r.vec;
            n_v.rep.addr   := u_v.inst.addr;
            n_v.rep.iw     := iw_v;
            if w_r.vec_intr = '0' then
               -- INT is an instruction.
               w_instret     <= not u_v.counted;
               n_v.after_rti := '0';
            end if;
         end if;
      elsif w_r.mode = RUN_ST and u_v.valid = '1' then
         wreg_v := 0;
         wval_v := (others => '0');

         -- The base register of each field (ISA.md §4.3)
         for i in 0 to 2 loop
            x_v := reg(iw_v, i);
            if x_v = 15 then
               base_v(i) := w_r.regs(15) when u_v.first = '0' and w_r.jump = '1' else
                            u_v.inst.next_pc;
            else
               base_v(i) := w_r.regs(x_v);
            end if;
         end loop;

         if cond_v = '0' then
            done_v := true;
         elsif u_v.kind = UOP_CTRL then
            -- ISA.md §5.3
            done_v := true;
            if iw_v(20 downto 8) /= 0 or (iw_v(25 downto 21) /= "00010" and iw_v(7 downto 0) /= 0) then
               halt_v := HALT_RESERVED;
            else
               case iw_v(25 downto 21) is
                  when "00000" =>
                     halt_v := HALT_HALT;

                  when "00001" =>
                     if w_r.in_service = '0' then
                        halt_v := HALT_RTI_OUTSIDE_ISR;
                     else
                        -- ISA.md §7.4
                        n_v.regs(14)   := regval(14, w_r.saved_sr);
                        n_v.regs(15)   := w_r.saved_pc;
                        n_v.in_service := '0';
                        rti_v          := true;
                     end if;

                  when "00010" =>
                     if w_r.in_service = '1' then
                        halt_v := HALT_NESTED_INT;
                     else
                        n_v.mode       := VEC_ST;
                        n_v.vec        := iw_v(7 downto 0);
                        n_v.vec_intr   := '0';
                        n_v.vec_nmi    := '0';
                        n_v.vec_issued := '0';
                        flush_v        := true;
                        done_v         := false;
                     end if;

                  when others =>
                     halt_v := HALT_RESERVED;
               end case;
            end if;
         else
            rd_v := uop_reads(iw_v, u_v.kind);
            nr_v := popcount(rd_v);
            if avail_v >= nr_v then
               done_v := true;
               w_pop  <= nr_v;
               k_v    := 0;

               case u_v.kind is
                  when UOP_S0 =>
                     -- ISA.md §4.1, s0 with its side effect
                     x_v := reg(iw_v, 1);
                     m_v := mode(iw_v, 1);
                     if m_v(2) = '1' then
                        v0_v := data_v(0);
                     else
                        v0_v := src_value(m_v, x_v, base_v(1), u_v.inst.consts(1));
                     end if;
                     n_v.s0val := v0_v;
                     wreg_v    := x_v;
                     wval_v    := base_v(1) - 1 when m_v(0) = '1' else base_v(1) + 1;

                  when UOP_S1 =>
                     -- s0, unless S0 had it, then s1 with its side effect
                     if not side(iw_v, 1) then
                        m_v := mode(iw_v, 1);
                        if m_v(2) = '1' then
                           n_v.s0val := data_v(0);
                           k_v       := 1;
                        else
                           n_v.s0val := src_value(m_v, reg(iw_v, 1), base_v(1), u_v.inst.consts(1));
                        end if;
                     end if;
                     x_v := reg(iw_v, 2);
                     m_v := mode(iw_v, 2);
                     if m_v(2) = '1' then
                        n_v.s1val := data_v(k_v);
                     else
                        n_v.s1val := src_value(m_v, x_v, base_v(2), u_v.inst.consts(2));
                     end if;
                     wreg_v := x_v;
                     wval_v := base_v(2) - 1 when m_v(0) = '1' else base_v(2) + 1;

                  when others =>
                     -- ISA.md §5, steps 5 to 8
                     if side(iw_v, 1) or side(iw_v, 2) then
                        v0_v := w_r.s0val;
                     elsif mode(iw_v, 1)(2) = '1' then
                        v0_v := data_v(0);
                        k_v  := 1;
                     else
                        v0_v := src_value(mode(iw_v, 1), reg(iw_v, 1), base_v(1), u_v.inst.consts(1));
                     end if;
                     if side(iw_v, 2) then
                        v1_v := w_r.s1val;
                     elsif mode(iw_v, 2)(2) = '1' then
                        v1_v := data_v(k_v);
                     else
                        v1_v := src_value(mode(iw_v, 2), reg(iw_v, 2), base_v(2), u_v.inst.consts(2));
                     end if;

                     if iw_v(27) = '1' then
                        res_v := shift(iw_v(24 downto 21), v0_v, v1_v, w_r.regs(14)(C_SR_C));
                     else
                        res_v := alu(iw_v(24 downto 21), v0_v, v1_v, iw_v(26) and w_r.regs(14)(C_SR_C));
                     end if;

                     -- The destination (ISA.md §4.2)
                     x_v := reg(iw_v, 0);
                     m_v := mode(iw_v, 0);
                     a_v := mem_addr(m_v, x_v, base_v(0), u_v.inst.consts(0));
                     case m_v is
                        when "000" =>
                           wreg_v := x_v;
                           wval_v := res_v.r;
                        when "001" =>
                           wreg_v := x_v;
                           wval_v := regval(x_v, res_v.r) - 1;
                        when "010" =>
                           wreg_v := x_v;
                           wval_v := regval(x_v, res_v.r) + 1;
                        when "101" =>
                           wreg_v := x_v;
                           wval_v := a_v;
                        when "110" =>
                           wreg_v := x_v;
                           wval_v := base_v(0) + 1;
                        when others =>
                           null;
                     end case;
                     store_v := m_v(2) = '1' or m_v = "011";
               end case;

               -- The register write
               if wreg_v /= 0 then
                  n_v.regs(wreg_v) := regval(wreg_v, wval_v);
                  if wreg_v = 15 then
                     n_v.jump := '1';
                  end if;
               end if;

               -- The flags (ISA.md §6), after the destination
               if u_v.kind = UOP_OP and iw_v(25) = '1' and
                  not (reg(iw_v, 0) = 14 and mode(iw_v, 0)(2) = '0' and mode(iw_v, 0) /= "011") then
                  n_v.regs(14) := flags(n_v.regs(14), res_v);
               end if;

               -- The store, held on the bus until it is accepted
               if store_v then
                  done_v := false;
                  if room_v then
                     w_req  <= '1';
                     w_we   <= '1';
                     w_addr <= a_v;
                     w_data <= res_v.r;
                     if dbus_stall_i = '0' then
                        done_v := true;
                     end if;
                  end if;
                  if not done_v then
                     w_pop <= 0;
                  end if;
                  n_v.busy := to_sl(room_v and dbus_stall_i = '1');

                  -- A store into a word fetched but not retired
                  if done_v and (in_range(a_v, f_addr, f_end) or
                     (dec_r.valid = '1' and in_range(a_v, dec_r.addr, dec_r.next_pc)) or
                     (prep_r.valid = '1' and in_range(a_v, prep_r.inst.addr, prep_r.inst.next_pc))) then
                     flush_v := true;
                  end if;
                  n_v.rep.mem_we   := '1';
                  n_v.rep.mem_addr := a_v;
                  n_v.rep.mem_data := res_v.r;
               end if;
            end if;
         end if;

         if done_v then
            n_v.uop.valid := '0';
            n_v.busy      := '0';
            if u_v.first = '1' then
               n_v.cond := cond_v;
            end if;
            if u_v.last = '0' then
               n_v.mid := '1';
            else
               -- The instruction retires.
               n_v.rep.valid   := '1';
               n_v.rep.addr    := u_v.inst.addr;
               n_v.rep.iw      := iw_v;
               n_v.rep.skipped := not cond_v;
               n_v.rep.halt    := halt_v;
               if cond_v = '0' then
                  n_v.rep.mem_we := '0';
               end if;
               w_instret <= not u_v.counted;

               if not rti_v and n_v.jump = '0' then
                  n_v.regs(15) := u_v.inst.next_pc;
               end if;
               if rti_v or (n_v.jump = '1' and u_v.inst.early = '0') then
                  flush_v := true;
               end if;
               if halt_v /= HALT_NONE then
                  n_v.halt := halt_v;
                  n_v.mode := HALTED_ST;
                  flush_v  := true;
               end if;
               n_v.after_rti := to_sl(rti_v);
               n_v.mid       := '0';
               n_v.jump      := '0';
               if u_v.committed = '1' then
                  n_v.commits := n_v.commits - 1;
               end if;
            end if;
         else
            -- Nothing changes until the micro-operation retires, but a
            -- move to VEC_ST and the bus state.
            n_v.regs  := w_r.regs;
            n_v.s0val := w_r.s0val;
            n_v.s1val := w_r.s1val;
            n_v.jump  := w_r.jump;
            n_v.in_service := w_r.in_service;
            n_v.rep        := C_RETIRE_NONE;
         end if;
      end if;

      -- A first data read of an instruction commits it.
      if p_first_read = '1' then
         n_v.commits := n_v.commits + 1;
      end if;

      -- WRITE takes the next micro-operation when it is free.
      if (w_r.uop.valid = '0' or done_v) and not flush_v and n_v.mode = RUN_ST and
         not (bound_v and (nmi_valid_i = '1' or (irq_valid_i = '1' and w_r.regs(14)(C_SR_E) = '1'))) then
         w_accept <= '1';
      else
         w_accept <= '0';
      end if;
      if p_move = '1' then
         n_v.uop := p_out;
      end if;

      w_done   <= to_sl(done_v);
      w_flush  <= to_sl(flush_v);
      w_target <= n_v.regs(15);
      w_n      <= n_v;
   end process p_write;


   p_write_reg : process (clk_i)
   begin
      if rising_edge(clk_i) then
         w_r <= w_n;

         if rst_i = '1' then
            w_r.uop        <= C_UOP_NONE;
            w_r.mode       <= RUN_ST;
            w_r.regs       <= C_REGS_RESET;
            w_r.in_service <= '0';
            w_r.after_rti  <= '0';
            w_r.halt       <= HALT_NONE;
            w_r.cond       <= '0';
            w_r.mid        <= '0';
            w_r.jump       <= '0';
            w_r.busy       <= '0';
            w_r.vec_issued <= '0';
            w_r.commits    <= 0;
            w_r.rep        <= C_RETIRE_NONE;
         end if;
      end if;
   end process p_write_reg;


   nmi_ready_o <= take_nmi;
   irq_ready_o <= take_irq;
   halted_o    <= '1' when w_r.mode = HALTED_ST else '0';
   -- An instruction with a data read is counted in the cycle the bus
   -- accepts its last read. The counter returns its value from before the
   -- count for that read, and every younger read is accepted later.
   rd_count  <= rd_stb_r and not dbus_stall_i and rd_last_r;
   instret_o <= rd_count or w_instret;


   -- The report of the step, in the cycle it retires, with the registers it
   -- leaves. So an interrupt source that counts the steps sees each one as
   -- soon as it can.
   p_retire : process (all)
   begin
      retire_o      <= w_n.rep;
      retire_o.regs <= w_n.regs;
   end process p_retire;


   -- The invariants that the theory of operation above relies on.
   p_check : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if rst_i = '0' then
            assert not (rd_count = '1' and w_instret = '1')
               report "pipeline: two instructions counted in one cycle"
               severity failure;
            assert not (rd_stb_r = '1' and w_req = '1')
               report "pipeline: a read of PREPARE and an access of WRITE on the bus at once"
               severity failure;
            assert not (w_flush = '1' and (rd_stb_r = '1' or p_load = '1'))
               report "pipeline: a flush while a data read is waiting to be issued"
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
