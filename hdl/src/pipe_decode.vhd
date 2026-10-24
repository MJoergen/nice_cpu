-- DECODE of the pipelined core (MICROARCH.md §3, §4).
--
-- THEORY OF OPERATION
-- DECODE takes one whole instruction from FETCH, when all its words are
-- present and it has room: into dec_r, the instruction it splits into
-- micro-operations (src/pipe_pkg.vhd), one per cycle, for PREPARE, or
-- into dec_q, the one after it, which moves up when dec_r frees. For
-- "MOVE R15, c" and "ADD R15, R15, c" with condition "always" it
-- redirects FETCH at once (MICROARCH.md §5.4), as it takes them.
--
-- The splitting goes on whenever skid_r is empty, whether PREPARE takes
-- the micro-operation or not. One that PREPARE does not take waits in
-- skid_r, and goes to PREPARE from there, before any other. So the
-- enables of dec_r, dec_q, and skid_r come from DECODE's own registers,
-- not from PREPARE's decisions against WRITE in the same cycle
-- (MICROARCH.md §3). It costs no cycle: PREPARE gets a micro-operation in
-- every cycle it can take one, as long as DECODE has one.
--
-- The registers are dec_r, dec_q, the micro-operation to split off next,
-- skid_r, and the id of the next instruction. consume_o, redirect_o, and
-- target_o depend combinationally on the words from FETCH and on dec_q
-- alone, so that the path from WRITE's decisions ends here and not in
-- FETCH. The port to PREPARE is a valid/ready handshake: a
-- micro-operation moves on in a cycle with valid_o and ready_i both high,
-- so in the cycle the next stage frees itself. valid_o depends on flush_i,
-- and not on ready_i.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) PREPARE takes uop_o at the end of a cycle with valid_o and ready_i
--    both high.
-- b) flush_i empties the stage, and wins over everything else.
--
-- RESET
-- Synchronous. It empties the stage.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use work.nice_pkg.all;
   use work.pipe_pkg.all;
   use work.trace_pkg.all;

entity pipe_decode is
   generic (
      -- Adds the properties of a formal proof.
      G_FORMAL : boolean := false
   );
   port (
      clk_i      : in  std_logic;
      rst_i      : in  std_logic;

      -- From FETCH (src/pipe_fetch.vhd)
      f_addr_i   : in  std_logic_vector(31 downto 0);
      f_words_i  : in  t_words4;
      f_count_i  : in  natural range 0 to 4;
      -- The words that DECODE takes
      consume_o  : out natural range 0 to 4;
      -- A jump that DECODE resolves, and its target
      redirect_o : out std_logic;
      target_o   : out std_logic_vector(31 downto 0);

      -- WRITE empties the pipeline.
      flush_i    : in  std_logic;

      -- To PREPARE
      valid_o    : out std_logic;
      ready_i    : in  std_logic;
      uop_o      : out t_uop;
      -- The instructions in dec_r, dec_q, and skid_r, for the check of
      -- stores into fetched code
      inst_o     : out t_inst;
      inst2_o    : out t_inst;
      skid_o     : out t_inst;

      -- For the fetch statistics: DECODE is free, but the words of the
      -- next instruction are not all there; or they are, but DECODE is busy
      starve_o   : out std_logic;
      blocked_o  : out std_logic
   );
end entity pipe_decode;

architecture synthesis of pipe_decode is

   -- Taking an instruction into dec_r
   signal d_inst  : t_inst;
   signal d_ok    : std_logic;
   signal d_load  : std_logic;
   signal d_early : std_logic;
   signal d_dest  : std_logic_vector(31 downto 0);
   signal id_r    : std_logic_vector(2 downto 0);

   -- The address after an instruction of each length, summed in parallel
   -- with the read of its words, so that the length only picks one
   type t_nexts is array (1 to 4) of std_logic_vector(31 downto 0);

   signal d_next : t_nexts;

   -- Splitting it into micro-operations
   signal dec_r       : t_inst;      -- The instruction being split
   signal dec_q       : t_inst;      -- The one after it, waiting
   signal seq_kind_r  : t_kind;
   signal seq_first_r : std_logic;
   signal seq_uop     : t_uop;
   signal seq_adv     : std_logic;   -- The micro-operation is split off now
   signal dec_free    : std_logic;

   -- The micro-operation that PREPARE did not take, and what goes to it
   signal skid_r    : t_uop;
   signal out_uop   : t_uop;
   signal out_valid : std_logic;
   signal out_emit  : std_logic;   -- PREPARE takes out_uop

begin

   redirect_o <= d_load and d_early;
   target_o   <= d_dest;
   valid_o    <= out_valid;
   uop_o      <= out_uop;
   inst_o     <= dec_r;
   inst2_o    <= dec_q;

   p_skid_inst : process (all)
   begin
      skid_o       <= skid_r.inst;
      skid_o.valid <= skid_r.valid;
   end process p_skid_inst;


   gen_next : for i in 1 to 4 generate
      d_next(i) <= f_addr_i + i;
   end generate gen_next;


   p_decode : process (all)
      variable inst_v  : t_inst;
      variable cf_v    : std_logic_vector(0 to 2);
      variable k_v     : natural range 1 to 4;
      variable len_v   : natural range 1 to 4;
      variable iw_v    : std_logic_vector(31 downto 0);
      variable early_v : std_logic;
      variable dest_v  : std_logic_vector(31 downto 0);
   begin
      iw_v           := f_words_i(0);
      cf_v           := const_fields(iw_v);
      len_v          := inst_len(iw_v);
      inst_v         := C_INST_NONE;
      inst_v.valid   := '1';
      inst_v.id      := id_r;
      inst_v.addr    := f_addr_i;
      inst_v.blk     := next_block(f_addr_i, 2);
      inst_v.next_pc := d_next(len_v);
      inst_v.iw      := iw_v;
      k_v            := 1;
      for i in 0 to 2 loop
         if cf_v(i) = '1' then
            inst_v.consts(i) := f_words_i(k_v);
            k_v              := minimum(k_v + 1, 3);
         end if;
         inst_v.m(i) := mode(iw_v, i);
         inst_v.x(i) := reg(iw_v, i);
      end loop;
      inst_v.side  := to_sl(side(iw_v, 1)) & to_sl(side(iw_v, 2));
      inst_v.ctrl  := to_sl(is_ctrl(iw_v));
      inst_v.shift := iw_v(27) and not inst_v.ctrl;
      inst_v.op    := iw_v(24 downto 21);
      inst_v.mbit  := iw_v(25);
      inst_v.cbit  := iw_v(26);

      -- The jumps that DECODE redirects FETCH for (MICROARCH.md §5.4),
      -- early_form of src/pipe_pkg.vhd: "MOVE R15, c" and "ADD R15, R15,
      -- c", and a conditional "ADD R15, R15, c" with c negative, which it
      -- predicts taken. They read no register but R15, and nothing changes
      -- R15 before them in the instruction. Each is two words, the
      -- constant the second, so the target is c or the address plus 2
      -- plus c, with one adder after the words.
      early_v := to_sl(early_form(iw_v, f_words_i(1)));
      dest_v  := f_words_i(1);
      if early_v = '1' and iw_v(24 downto 21) = "0011" then
         dest_v := d_next(2) + f_words_i(1);
      end if;
      inst_v.early := early_v;
      d_early      <= early_v;
      d_dest       <= dest_v;

      d_inst <= inst_v;
      d_ok   <= '1' when f_count_i >= len_v else '0';
   end process p_decode;

   -- An instruction is taken when the second slot is free, so that
   -- consume_o depends on nothing downstream of DECODE. A flush drops it
   -- again, below.
   d_load    <= d_ok and not dec_q.valid;
   starve_o  <= not d_ok and not dec_q.valid and not flush_i and not rst_i;
   blocked_o <= d_ok and dec_q.valid and not flush_i and not rst_i;
   consume_o <= inst_len(f_words_i(0)) when d_load = '1' else 0;


   -- The micro-operation to emit, with what each stage after DECODE needs
   -- to know of it decoded here, from registers, so that the stages'
   -- paths start from registers (MICROARCH.md §7.4). The shift count of a
   -- constant is prepared here too.
   p_seq_uop : process (all)
      variable uop_v : t_uop;
   begin
      uop_v          := C_UOP_NONE;
      uop_v.valid    := dec_r.valid;
      uop_v.inst     := dec_r;
      uop_v.kind     := seq_kind_r;
      uop_v.first    := seq_first_r;
      uop_v.last     := is_last(seq_kind_r);
      uop_v.wreg     := uop_wreg(dec_r.iw, seq_kind_r);
      uop_v.reads    := uop_reads(dec_r.iw, seq_kind_r);
      uop_v.store    := to_sl(uop_store(dec_r.iw, seq_kind_r));
      uop_v.may_sr   := to_sl(uop_may_sr(dec_r.iw, seq_kind_r));
      uop_v.may_jump := to_sl(uop_may_jump(dec_r.iw, seq_kind_r));
      uop_v.cnt      := shift_prep(dec_r.op, dec_r.consts(2));
      seq_uop        <= uop_v;
   end process p_seq_uop;

   seq_adv  <= dec_r.valid and not skid_r.valid;
   dec_free <= not dec_r.valid or (seq_adv and seq_uop.last);

   -- To PREPARE: the micro-operation in skid_r, else the one split off now
   out_uop   <= skid_r when skid_r.valid = '1' else seq_uop;
   out_valid <= (skid_r.valid or dec_r.valid) and not flush_i;
   out_emit  <= out_valid and ready_i;


   p_seq : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if seq_adv = '1' then
            seq_kind_r  <= next_kind(dec_r.iw, seq_kind_r);
            seq_first_r <= '0';
            if seq_uop.last = '1' then
               dec_r.valid <= '0';
            end if;
         end if;

         -- The next instruction moves up when dec_r frees: from dec_q, or
         -- straight from FETCH. Else a new one waits in dec_q.
         if dec_free = '1' then
            if dec_q.valid = '1' then
               dec_r       <= dec_q;
               seq_kind_r  <= first_kind(dec_q.iw);
               seq_first_r <= '1';
               dec_q.valid <= '0';
            elsif d_load = '1' then
               dec_r       <= d_inst;
               seq_kind_r  <= first_kind(d_inst.iw);
               seq_first_r <= '1';
            end if;
         elsif d_load = '1' then
            dec_q <= d_inst;
         end if;
         if d_load = '1' then
            id_r <= id_r + 1;
         end if;

         -- skid_r takes each micro-operation split off while it is empty,
         -- and keeps it if PREPARE does not take it.
         if skid_r.valid = '0' then
            skid_r <= seq_uop;
         end if;
         skid_r.valid <= (skid_r.valid or seq_adv) and not ready_i;

         if flush_i = '1' then
            dec_r.valid  <= '0';
            dec_q.valid  <= '0';
            skid_r.valid <= '0';
         end if;

         if rst_i = '1' then
            dec_r       <= C_INST_NONE;
            dec_q       <= C_INST_NONE;
            skid_r      <= C_UOP_NONE;
            seq_kind_r  <= UOP_OP;
            seq_first_r <= '0';
            id_r        <= (others => '0');
         end if;
      end if;
   end process p_seq;


   -- The formal properties (formal/formal_pipe_decode.vhd). Every input is
   -- free: the words and their count from FETCH, with the count at most
   -- four, PREPARE's ready, and WRITE's flush. The assertions are what
   -- the proof of PREPARE assumes of DECODE (src/pipe_prepare.vhd, f_emit
   -- to f_decoded): a micro-operation is emitted only when PREPARE takes
   -- it and no flush comes; the micro-operations of an instruction come
   -- in order, the first marked first and the last marked last, each
   -- with the same instruction, and the instructions emitted since the
   -- last flush have consecutive ids; and the fields of each agree with
   -- its instruction word, next_pc and the block among them. They also
   -- say what DECODE takes from FETCH: no more words than are there, and
   -- a whole instruction or nothing, with its constant words in the order
   -- dest, s0, s1 (ISA.md §2.3); and what it redirects FETCH to: the
   -- target of MOVE R15, c or ADD R15, R15, c (MICROARCH.md §5.4), and
   -- only as it takes such an instruction. The invariants after them tie
   -- dec_r, dec_q, and the id counter to the last micro-operation split
   -- off, and skid_r to it and to the last one emitted, so that
   -- k-induction proves it all for every cycle.

   gen_formal : if G_FORMAL generate
      signal f_open  : std_logic := '0';   -- The last emitted micro-operation was not its instruction's last
      signal f_since : std_logic := '0';   -- An instruction was emitted since the last flush
      signal f_inst  : t_inst;             -- The instruction of the last emitted micro-operation
      signal f_kind  : t_kind;             -- Its kind
      -- The same for the last micro-operation split off
      signal g_open  : std_logic := '0';
      signal g_since : std_logic := '0';
      signal g_inst  : t_inst;
      signal g_kind  : t_kind;

      -- The first constant word of an instruction, which decides whether
      -- DECODE predicts a conditional jump.
      function first_const(inst : t_inst) return std_logic_vector is
      begin
         for i in 0 to 2 loop
            if const_fields(inst.iw)(i) = '1' then
               return inst.consts(i);
            end if;
         end loop;
         return X"00000000";
      end function first_const;

      -- The fields of an instruction that DECODE fills in agree with its
      -- word: those that decoded_ok checks, and next_pc, the block, and
      -- whether DECODE resolves it.
      function inst_ok(inst : t_inst) return boolean is
         variable iw_v : std_logic_vector(31 downto 0);
         variable ok_v : boolean;
      begin
         iw_v := inst.iw;
         ok_v := inst.next_pc = inst.addr + inst_len(iw_v) and
                 inst.blk = next_block(inst.addr, 2) and
                 inst.side = to_sl(side(iw_v, 1)) & to_sl(side(iw_v, 2)) and
                 inst.ctrl = to_sl(is_ctrl(iw_v)) and
                 inst.shift = (iw_v(27) and not to_sl(is_ctrl(iw_v))) and
                 inst.op = iw_v(24 downto 21) and
                 inst.mbit = iw_v(25) and
                 inst.cbit = iw_v(26) and
                 inst.early = to_sl(early_form(iw_v, first_const(inst)));
         for i in 0 to 2 loop
            if inst.m(i) /= mode(iw_v, i) or inst.x(i) /= reg(iw_v, i) then
               ok_v := false;
            end if;
         end loop;
         return ok_v;
      end function inst_ok;

      -- The constant word of field i of the instruction in f_words_i(0),
      -- counted in the order dest, s0, s1 (ISA.md §2.3).
      function const_word(words : t_words4;
                          i     : natural range 0 to 2) return std_logic_vector is
         variable cf_v : std_logic_vector(0 to 2);
         variable k_v  : natural range 1 to 3 := 1;
      begin
         cf_v := const_fields(words(0));
         for j in 0 to 2 loop
            if j < i and cf_v(j) = '1' then
               k_v := k_v + 1;
            end if;
         end loop;
         return words(k_v);
      end function const_word;

      -- The target of an early jump, from ISA.md §4.1 and §4.3: c for MOVE
      -- R15, c, and R15 + c for ADD R15, R15, c, where R15 reads as the
      -- next instruction's address.
      function early_target(addr  : std_logic_vector(31 downto 0);
                            words : t_words4) return std_logic_vector is
      begin
         if words(0)(24 downto 21) = "0000" then
            return words(1);
         end if;
         return addr + 2 + words(1);
      end function early_target;

   begin

      p_model : process (clk_i)
      begin
         if rising_edge(clk_i) then
            if out_emit = '1' then
               f_open  <= not out_uop.last;
               f_since <= '1';
               f_inst  <= out_uop.inst;
               f_kind  <= out_uop.kind;
            end if;
            if seq_adv = '1' then
               g_open  <= not seq_uop.last;
               g_since <= '1';
               g_inst  <= dec_r;
               g_kind  <= seq_kind_r;
            end if;
            if rst_i = '1' or flush_i = '1' then
               f_open  <= '0';
               f_since <= '0';
               g_open  <= '0';
               g_since <= '0';
            end if;
         end if;
      end process p_model;

      -- psl default clock is rising_edge(clk_i);

      -- FETCH
      -- psl f_count_range : assume always f_count_i <= 4;

      -- What PREPARE assumes of DECODE
      -- psl f_emit : assert always (rst_i = '0' and out_valid = '1') ->
      --    (out_uop.valid = '1' and flush_i = '0');
      -- psl f_last : assert always (rst_i = '0' and out_emit = '1') ->
      --    out_uop.last = is_last(out_uop.kind);
      -- psl f_next_uop : assert always (rst_i = '0' and out_emit = '1' and f_open = '1') ->
      --    (out_uop.first = '0' and out_uop.inst = f_inst and
      --     out_uop.kind = next_kind(f_inst.iw, f_kind));
      -- psl f_new_inst : assert always (rst_i = '0' and out_emit = '1' and f_open = '0') ->
      --    (out_uop.first = '1' and out_uop.kind = first_kind(out_uop.inst.iw) and
      --     (f_since = '0' or out_uop.inst.id = f_inst.id + 1));
      -- psl f_decoded : assert always (rst_i = '0' and out_emit = '1') ->
      --    (decoded_ok(out_uop) and inst_ok(out_uop.inst));

      -- What DECODE takes from FETCH, and the constant words it keeps
      -- psl f_take : assert always rst_i = '0' ->
      --    (consume_o <= f_count_i and (consume_o = 0 or consume_o = inst_len(f_words_i(0))));
      -- psl f_load : assert always (rst_i = '0' and d_load = '1') ->
      --    (d_inst.addr = f_addr_i and d_inst.iw = f_words_i(0) and inst_ok(d_inst));

      gen_consts : for i in 0 to 2 generate
         -- psl f_const : assert always (rst_i = '0' and d_load = '1' and const_fields(f_words_i(0))(i) = '1') ->
         --    d_inst.consts(i) = const_word(f_words_i, i);
      end generate gen_consts;

      -- The jumps DECODE resolves
      -- psl f_redirect : assert always (rst_i = '0' and d_load = '1') ->
      --    (d_early = to_sl(early_form(f_words_i(0), f_words_i(1))));
      -- psl f_target : assert always (rst_i = '0' and redirect_o = '1') ->
      --    (consume_o = 2 and d_dest = early_target(f_addr_i, f_words_i));

      -- A flush empties the stage
      -- psl f_flushed : assert always {flush_i and not rst_i} |=>
      --    {rst_i = '1' or (dec_r.valid = '0' and dec_q.valid = '0' and skid_r.valid = '0')};

      -- The instructions held: skid_r's is reported
      -- psl f_skid_o : assert always rst_i = '0' ->
      --    (skid_o.valid = skid_r.valid and (skid_r.valid = '0' or skid_o.addr = skid_r.inst.addr));

      -- The invariants
      -- psl f_inv_mid : assert always (rst_i = '0' and dec_r.valid = '1' and seq_first_r = '0') ->
      --    (g_open = '1' and dec_r = g_inst and seq_kind_r = next_kind(g_inst.iw, g_kind));
      -- psl f_inv_open : assert always (rst_i = '0' and g_open = '1') ->
      --    (dec_r.valid = '1' and seq_first_r = '0' and g_since = '1' and is_last(g_kind) = '0');
      -- psl f_inv_first : assert always (rst_i = '0' and dec_r.valid = '1' and seq_first_r = '1') ->
      --    (seq_kind_r = first_kind(dec_r.iw) and (g_since = '0' or dec_r.id = g_inst.id + 1));
      -- psl f_inv_queue : assert always (rst_i = '0' and dec_q.valid = '1') ->
      --    (dec_r.valid = '1' and dec_q.id = dec_r.id + 1);
      -- psl f_inv_id : assert always rst_i = '0' ->
      --    ((dec_r.valid = '1' and id_r = dec_r.id + 1 + to_nat(dec_q.valid)) or
      --     (dec_r.valid = '0' and (g_since = '0' or id_r = g_inst.id + 1)));
      -- psl f_inv_insts : assert always rst_i = '0' ->
      --    ((dec_r.valid = '0' or inst_ok(dec_r)) and (dec_q.valid = '0' or inst_ok(dec_q)) and
      --     (g_since = '0' or inst_ok(g_inst)));

      -- skid_r holds the last micro-operation split off, and it follows
      -- the last one emitted. While it is empty, the two are the same.
      -- The cases of f_open are assertions of their own, as GHDL 4.1, in
      -- CI, cannot synthesize them as "f_open = '0' or ..." in one.
      -- psl f_inv_skid : assert always (rst_i = '0' and skid_r.valid = '1') ->
      --    (g_since = '1' and skid_r.inst = g_inst and skid_r.kind = g_kind and
      --     skid_r.last = is_last(g_kind) and g_open = not skid_r.last and
      --     decoded_ok(skid_r) and inst_ok(skid_r.inst));
      -- psl f_inv_skid_open : assert always
      --    (rst_i = '0' and skid_r.valid = '1' and f_open = '1') ->
      --    (skid_r.first = '0' and g_inst = f_inst and g_kind = next_kind(f_inst.iw, f_kind));
      -- psl f_inv_skid_new : assert always
      --    (rst_i = '0' and skid_r.valid = '1' and f_open = '0') ->
      --    (skid_r.first = '1' and skid_r.kind = first_kind(skid_r.inst.iw) and
      --     (f_since = '0' or skid_r.inst.id = f_inst.id + 1));
      -- psl f_inv_same : assert always (rst_i = '0' and skid_r.valid = '0') ->
      --    (f_open = g_open and f_since = g_since and
      --     (g_since = '0' or (f_inst = g_inst and f_kind = g_kind)));

      -- psl c_three : cover {out_emit = '1' and inst_len(out_uop.inst.iw) = 4};
      -- psl c_queue : cover {dec_q.valid = '1' and out_emit = '1' and out_uop.first = '0'};
      -- psl c_skid : cover {skid_r.valid = '1' and dec_q.valid = '1' and out_emit = '1'};
      -- psl c_redirect : cover {redirect_o = '1' and dec_r.valid = '1'};
      -- psl c_flush : cover {flush_i = '1' and dec_q.valid = '1' and rst_i = '0'};
   end generate gen_formal;

end architecture synthesis;
