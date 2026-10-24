-- PREPARE of the pipelined core (MICROARCH.md §3, §5.2, §5.3).
--
-- THEORY OF OPERATION
-- PREPARE holds one micro-operation in prep_r. It tests the condition of
-- the instruction when no older micro-operation in WRITE may still change
-- SR, and must before it issues a data read. It forms the value or the
-- address of each operand field from the registers in WRITE's state
-- (MICROARCH.md §7.4): the sums R + c and R - 1 of the modes that need
-- them, and the shift count reduced for the shifter. A field whose value
-- is a plain register that the micro-operation in WRITE writes now gets
-- WRITE's last value instead, in WRITE; a field that needs an adder on
-- such a register, or whose address a read needs, waits a cycle. It loads
-- each data read of the micro-operation into the request register,
-- rd_stb_r and rd_addr_r, which holds it on the data bus until the bus
-- accepts it, but only when the instruction is certain to run
-- (MICROARCH.md §5.3). Then it passes the micro-operation to WRITE, with
-- what it found out: the condition, the values, and whether the
-- instruction has made a data read (committed) and been counted on
-- instret_o (counted).
--
-- An instruction with a data read is counted in the cycle the bus accepts
-- its last read, count_o.
--
-- The registers are prep_r, the request register, and what PREPARE knows
-- of the current instruction. ready_o, valid_o, uop_o, load_o,
-- first_read_o, and count_o depend combinationally on the state of WRITE
-- and on the bus in the same cycle: a micro-operation moves on in the
-- cycle WRITE frees itself, and a read is loaded in the cycle the bus
-- accepts the store that waits in DBUS. No read is loaded while a store
-- will wait in DBUS in the next cycle, so that the two are never on the
-- bus together (src/pipe_dbus.vhd, a): none while an older store retires
-- into DBUS now. A waiting store counts among the requests in flight, of
-- which there may be no more than C_MAX_OUT (src/pipe_dbus.vhd, b).
--
-- Both micro-operation ports are valid/ready handshakes: a micro-operation
-- moves in a cycle with valid and ready both high, and valid does not
-- depend on ready. ready_o depends on ready_i.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) w_i is WRITE's state, and done_i, flush_i, ready_i, take_nmi_i, and
--    take_irq_i are WRITE's decisions in the same cycle.
-- b) tag_cnt_i counts the data bus requests accepted and not acknowledged.
-- c) WRITE neither flushes nor takes an interrupt while the instruction in
--    PREPARE has made a data read.
-- d) st_valid_i is '1' while a store or a vector read of WRITE waits in
--    DBUS, and st_acc_i when the bus accepts it. WRITE queues a store only
--    from a store micro-operation of its own, and a vector read only during
--    an interrupt entry, and either only while no read waits in the request
--    register.
--
-- RESET
-- Synchronous. It empties the stage and drops the request.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use work.nice_pkg.all;
   use work.pipe_pkg.all;
   use work.trace_pkg.all;

entity pipe_prepare is
   generic (
      -- Adds the properties of a formal proof.
      G_FORMAL : boolean := false
   );
   port (
      clk_i        : in  std_logic;
      rst_i        : in  std_logic;

      -- From DECODE
      valid_i      : in  std_logic;
      uop_i        : in  t_uop;
      ready_o      : out std_logic;

      -- WRITE's state and decisions
      w_i          : in  t_write;
      done_i       : in  std_logic;
      flush_i      : in  std_logic;
      ready_i      : in  std_logic;   -- WRITE takes uop_o
      take_nmi_i   : in  std_logic;
      take_irq_i   : in  std_logic;

      -- The interrupt requests and the pause (MICROARCH.md §5.3, rule 4)
      nmi_valid_i  : in  std_logic;
      irq_valid_i  : in  std_logic;
      pause_i      : in  std_logic;

      -- To WRITE
      valid_o      : out std_logic;
      uop_o        : out t_uop;
      first_read_o : out std_logic;   -- The first data read of an instruction
      prep_o       : out t_uop;       -- prep_r, for the check of stores into fetched code

      -- The data read, held until the bus accepts it
      dbus_stall_i : in  std_logic;
      tag_cnt_i    : in  natural range 0 to C_MAX_OUT;
      st_valid_i   : in  std_logic;   -- A store or vector read waits in DBUS
      st_acc_i     : in  std_logic;   -- The bus accepts it now
      rd_stb_o     : out std_logic;
      rd_addr_o    : out std_logic_vector(31 downto 0);
      load_o       : out std_logic;   -- A data read is loaded now

      -- Counts an instruction on instret_o
      count_o      : out std_logic
   );
end entity pipe_prepare;

architecture synthesis of pipe_prepare is

   signal seq_uop   : t_uop;
   signal seq_valid : std_logic;
   signal seq_emit  : std_logic;   -- PREPARE takes DECODE's micro-operation
   signal w_r       : t_write;
   signal w_done    : std_logic;
   signal w_flush   : std_logic;
   signal w_accept  : std_logic;
   signal take_nmi  : std_logic;
   signal take_irq  : std_logic;
   signal tag_cnt_r : natural range 0 to C_MAX_OUT;

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
   signal p_valid       : std_logic;              -- The micro-operation may go on
   signal p_ready       : std_logic;
   signal p_move        : std_logic;              -- WRITE takes it
   signal rd_stb_r      : std_logic;
   signal rd_addr_r     : std_logic_vector(31 downto 0);
   signal rd_last_r     : std_logic;              -- rd_stb_r is its instruction's last read

begin

   seq_uop   <= uop_i;
   seq_valid <= valid_i;
   w_r       <= w_i;
   w_done    <= done_i;
   w_flush   <= flush_i;
   w_accept  <= ready_i;
   take_nmi  <= take_nmi_i;
   take_irq  <= take_irq_i;
   tag_cnt_r <= tag_cnt_i;

   p_move   <= p_valid and w_accept;
   p_ready  <= not prep_r.valid or p_move;
   seq_emit <= seq_valid and p_ready;

   ready_o      <= p_ready;
   valid_o      <= p_valid;
   uop_o        <= p_out;
   first_read_o <= p_first_read;
   prep_o       <= prep_r;
   rd_stb_o     <= rd_stb_r;
   rd_addr_o    <= rd_addr_r;
   load_o       <= p_load;

   -- An instruction with a data read is counted in the cycle the bus
   -- accepts its last read. The counter returns its value from before the
   -- count for that read, and every younger read is accepted later.
   count_o <= rd_stb_r and not dbus_stall_i and rd_last_r;


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
      variable m_v       : std_logic_vector(2 downto 0);
      variable base_v    : t_fields;  -- The base register of each field
      variable val_v     : t_fields;  -- Its value or address
      variable src_v     : t_srcs;
      variable plain_v   : boolean;   -- The field's value is its base
      variable rdaddr_v  : boolean;   -- The field is the address of a read
      variable wr_v      : boolean;   -- WRITE will still write the base
      variable used_v    : boolean;   -- The micro-operation needs the field
      variable busy_v    : boolean;   -- A field it needs is not ready
      variable late_v    : std_logic;
      variable cnt_v     : t_shift_prep;
      variable quiet_v   : boolean;   -- and will not jump, store, or be counted late
      variable older_ok  : boolean;
      variable intr_ok   : boolean;
      variable bus_ok    : boolean;
      variable store_v   : boolean;   -- WRITE puts a store on the bus now
      variable started_v : boolean;
      variable load_v    : std_logic;
      variable irq_v     : boolean;
      variable pause_ok  : boolean;
   begin
      u_v     := prep_r;
      wu_v    := w_r.uop;
      older_v := wu_v.valid = '1' and wu_v.inst.id /= u_v.inst.id;

      -- The condition (ISA.md §3), against SR before the instruction
      ck_v := '0';
      cv_v := condition(u_v.inst.iw, w_r.regs(14));
      if u_v.first = '1' then
         if w_r.mode = RUN_ST and not (wu_v.valid = '1' and wu_v.may_sr = '1') then
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

      -- The value or address of each field (ISA.md §4.1 and §4.2), from
      -- the registers as WRITE holds them. A field whose value is its base
      -- register, and whose register the micro-operation in WRITE writes
      -- now, takes WRITE's last value instead (MICROARCH.md §7.4). A field
      -- that needs an adder on such a register, or whose address a read
      -- needs, waits until WRITE has written it.
      rd_v   := u_v.reads;
      nr_v   := popcount(rd_v);
      busy_v := false;
      for i in 0 to 2 loop
         x_v := u_v.inst.x(i);
         m_v := u_v.inst.m(i);
         if x_v = 15 then
            base_v(i) := w_r.regs(15) when not older_v and w_r.jump = '1' else u_v.inst.next_pc;
         else
            base_v(i) := w_r.regs(x_v);
         end if;
         case m_v is
            when "001" | "101"  => val_v(i) := regval(x_v, base_v(i) - 1);
            when "011" | "111"  => val_v(i) := base_v(i) + u_v.inst.consts(i);
            when others         => val_v(i) := base_v(i);
         end case;
         plain_v := m_v(1 downto 0) = "00" or m_v(1 downto 0) = "10";
         -- R15 is this instruction's next address whatever an older
         -- instruction wrote to it: a jump flushes this one, and a
         -- skipped or early jump leaves it. Only an earlier
         -- micro-operation of the same instruction can change it.
         wr_v    := wu_v.valid = '1' and x_v /= 0 and (x_v /= 15 or not older_v) and
                    ((x_v = 14 and wu_v.may_sr = '1') or (x_v /= 14 and wu_v.wreg = x_v));
         -- A read address is needed here, so it never comes from WRITE.
         rdaddr_v := m_v(2) = '1' and i /= 0;
         if plain_v and not rdaddr_v and x_v = 14 then
            src_v(i) := SRC_SR;
         elsif plain_v and not rdaddr_v and wr_v then
            src_v(i) := SRC_LAST;
         else
            src_v(i) := SRC_VAL;
         end if;
         case u_v.kind is
            when UOP_S0   => used_v := i = 1;
            when UOP_S1   => used_v := i = 2 or (i = 1 and u_v.inst.side(1) = '0');
            when UOP_OP   => used_v := (i = 0 and m_v /= "000" and m_v /= "001" and m_v /= "010") or
                                       (i = 1 and u_v.inst.side(1) = '0') or
                                       (i = 2 and u_v.inst.side(2) = '0');
            when UOP_CTRL => used_v := false;
         end case;
         if used_v and wr_v and src_v(i) = SRC_VAL then
            busy_v := true;
         end if;
      end loop;

      -- The shift count, reduced here from a constant (by DECODE) or a
      -- register, or by WRITE in a cycle of its own when it comes from
      -- memory, through an adder, or from WRITE's last value or SR, or
      -- is a rotation through C by a register, whose count mod 33 this
      -- stage cannot afford (MICROARCH.md §7.3).
      m_v   := u_v.inst.m(2);
      x_v   := u_v.inst.x(2);
      cnt_v := shift_prep(u_v.inst.op, base_v(2), false);
      if m_v = "011" and x_v = 0 then
         cnt_v := u_v.cnt;
      end if;
      late_v := '0';
      if m_v(2) = '1' or u_v.inst.side(2) = '1' or src_v(2) /= SRC_VAL or
         (x_v /= 0 and (m_v = "001" or m_v = "011")) or
         (u_v.inst.op(2 downto 0) = "101" and not (m_v = "011" and x_v = 0)) then
         late_v := u_v.inst.shift;
      end if;

      -- The next read to load: s0, then s1
      if p_loaded_r = 0 and rd_v(1) = '1' then
         f_v := 1;
      else
         f_v := 2;
      end if;
      p_addr <= val_v(f_v);

      -- The older micro-operation in WRITE will not jump, halt, or store
      -- into fetched code, and is counted on instret_o. Either it retires
      -- now, or it has made its reads and makes no store.
      quiet_v  := wu_v.store = '0' and wu_v.may_jump = '0' and w_r.jump = '0' and
                  wu_v.counted = '1';
      older_ok := not older_v or (w_done = '1' and w_flush = '0') or quiet_v;

      -- No interrupt may be taken before this instruction (MICROARCH.md
      -- §5.3, rule 4). None can be if the instruction has made a data read
      -- or begun to retire, or follows RTI directly.
      started_v := not older_v and
                   ((wu_v.valid = '1' and wu_v.first = '0') or (wu_v.valid = '0' and w_r.mid = '1'));
      irq_v     := irq_valid_i = '1' and w_r.in_service = '0' and
                   (w_r.regs(14)(C_SR_E) = '1' or (wu_v.valid = '1' and wu_v.may_sr = '1'));
      intr_ok   := started_v or p_committed_r = '1' or (not older_v and w_r.after_rti = '1') or
                   not ((nmi_valid_i = '1' and w_r.in_service = '0') or irq_v);
      -- Nor a pause (MICROARCH.md §6.1), but before the first step after
      -- one. The instruction after RTI is not exempt, as the core pauses
      -- after RTI too (hdl/ASSUMPTIONS.md, item 19).
      pause_ok  := started_v or p_committed_r = '1' or (not older_v and w_r.after_go = '1') or
                   pause_i = '0';

      -- The bus takes the read when C_MAX_OUT will not be in flight, and no
      -- store waits in DBUS in the next cycle: none waits that the bus does
      -- not accept now, and an older micro-operation queues none now.
      store_v := older_v and w_done = '1' and wu_v.store = '1';
      bus_ok  := (rd_stb_r = '0' or dbus_stall_i = '0') and not store_v and
                 (st_valid_i = '0' or st_acc_i = '1') and
                 tag_cnt_r + to_nat(rd_stb_r) + to_nat(st_valid_i) < C_MAX_OUT;

      load_v := '0';
      if u_v.valid = '1' and ck_v = '1' and cv_v = '1' and p_loaded_r < nr_v and
         older_ok and intr_ok and pause_ok and not busy_v and bus_ok and
         w_r.mode = RUN_ST and w_flush = '0' and take_nmi = '0' and take_irq = '0' then
         load_v := '1';
      end if;
      p_load       <= load_v;
      p_first_read <= load_v and not p_committed_r;
      p_last_read  <= '0';
      if load_v = '1' and p_loaded_r + 1 = nr_v and not later_reads(u_v.inst.iw, u_v.kind) then
         p_last_read <= '1';
      end if;

      -- The micro-operation may go on when its values are ready and its
      -- reads are loaded, or it has none, or its condition is false.
      p_valid <= '0';
      if u_v.valid = '1' then
         if (ck_v = '1' and cv_v = '0') or
            (not busy_v and (nr_v = 0 or (ck_v = '1' and p_loaded_r + to_nat(load_v) = nr_v))) then
            p_valid <= '1';
         end if;
      end if;

      u_v.cond_known := ck_v;
      u_v.cond_val   := cv_v;
      u_v.committed  := p_committed_r or load_v;
      u_v.counted    := p_counted_r;
      if load_v = '1' and p_loaded_r + 1 = nr_v and not later_reads(u_v.inst.iw, u_v.kind) then
         u_v.counted := '1';
      end if;
      u_v.val      := val_v;
      u_v.src      := src_v;
      u_v.cnt      := cnt_v;
      u_v.cnt_late := late_v;
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


   -- The formal properties (formal/formal_pipe_prepare.vhd). The
   -- assumptions model DECODE and WRITE as far as PREPARE relies on them:
   -- - DECODE emits only when PREPARE is ready, and the micro-operations
   --   of each instruction in order, with a new id for each instruction,
   --   and the fields it decodes agree with the instruction word.
   -- - WRITE takes what PREPARE moves on. SR changes only when WRITE
   --   retires a micro-operation that may change it, and WRITE's condition
   --   of the instruction only when it retires an instruction's first.
   --   WRITE leaves RUN_ST only with a flush or an interrupt.
   -- - WRITE neither flushes nor takes an interrupt while PREPARE holds an
   --   instruction that has made a data read (contract c), or has a read
   --   on the bus or about to be loaded.
   -- - The data bus requests in flight grow only by PREPARE's read, or the
   --   store or vector read that waits in DBUS, when there is room.
   -- The assertions say that the read request keeps to the bus (held
   -- while stalled, and never with C_MAX_OUT requests in flight), that a
   -- micro-operation makes no more reads than it has, and all of them
   -- before it moves on unless its condition is false, and that PREPARE
   -- never finds the condition false of an instruction that has made a
   -- data read (the data access rule of MICROARCH.md §5.3). The invariants
   -- after them make it all inductive.

   gen_formal : if G_FORMAL generate
      signal f_first     : std_logic := '1';   -- The first cycle
      signal f_uop       : t_uop     := C_UOP_NONE;   -- WRITE's next micro-operation
      signal f_sr        : std_logic_vector(31 downto 0);
      signal f_sr_free   : std_logic;          -- SR may change now
      signal f_cond      : std_logic;
      signal f_cond_free : std_logic;          -- WRITE's condition may change now
      signal f_mode      : t_wmode;
      signal f_mode_free : std_logic;          -- The mode may change now
      signal f_tag       : natural range 0 to C_MAX_OUT + 1;
      signal f_rd_stall  : std_logic;          -- and was stalled
      signal f_rd_addr   : std_logic_vector(31 downto 0);
      signal f_st_may    : std_logic := '0';   -- An access may wait in DBUS now
      signal f_open      : std_logic := '0';   -- DECODE is in an instruction
      signal f_inst      : t_inst;             -- and this one
      signal f_kind      : t_kind;             -- The kind of its last micro-operation
      signal f_nr        : natural range 0 to 2;
   begin
      f_nr <= popcount(uop_reads(prep_r.inst.iw, prep_r.kind));


      p_model : process (clk_i)
      begin
         if rising_edge(clk_i) then
            f_first <= '0';

            if w_flush = '1' then
               f_uop <= C_UOP_NONE;
            elsif p_move = '1' then
               f_uop <= p_out;
            elsif w_done = '1' then
               f_uop <= C_UOP_NONE;
            else
               f_uop <= w_r.uop;
            end if;

            f_sr        <= w_r.regs(14);
            f_sr_free   <= rst_i or w_flush or take_nmi or take_irq or
                           (w_done and w_r.uop.valid and w_r.uop.may_sr);
            f_cond      <= w_r.cond;
            f_cond_free <= rst_i or w_flush or take_nmi or take_irq or
                           (w_done and w_r.uop.valid and w_r.uop.first);
            f_mode      <= w_r.mode;
            f_mode_free <= rst_i or w_flush or take_nmi or take_irq;

            f_rd_stall <= rd_stb_r and dbus_stall_i and not rst_i;
            f_rd_addr  <= rd_addr_r;
            -- PREPARE's read, or else, when there is room, the store or
            -- vector read that waits in DBUS
            f_tag      <= tag_cnt_r + to_nat((rd_stb_r = '1' and dbus_stall_i = '0') or
                                             (rd_stb_r = '0' and tag_cnt_r < C_MAX_OUT and
                                                st_valid_i = '1'));
            -- The access that waits, and has not been accepted, or a store
            -- or vector read that WRITE queues now
            f_st_may   <= not rst_i and ((st_valid_i and not st_acc_i) or
                                         (w_r.uop.valid and w_r.uop.store and not rd_stb_r) or
                                         (to_sl(w_r.mode = VEC_ST) and not rd_stb_r));

            if seq_emit = '1' then
               f_open <= not seq_uop.last;
               f_inst <= seq_uop.inst;
               f_kind <= seq_uop.kind;
            end if;

            if rst_i = '1' or w_flush = '1' then
               f_uop  <= C_UOP_NONE;
               f_open <= '0';
            end if;
         end if;
      end process p_model;

      -- psl default clock is rising_edge(clk_i);

      -- DECODE
      -- psl f_emit : assume always seq_valid -> seq_uop.valid;
      -- psl f_last : assume always seq_emit -> seq_uop.last = is_last(seq_uop.kind);
      -- psl f_next_uop : assume always (seq_emit and f_open) ->
      --    (seq_uop.first = '0' and seq_uop.inst = f_inst and
      --     seq_uop.kind = next_kind(f_inst.iw, f_kind));
      -- psl f_new_inst : assume always (seq_emit and not f_open) ->
      --    (seq_uop.first = '1' and seq_uop.inst.id /= f_inst.id and
      --     seq_uop.kind = first_kind(seq_uop.inst.iw));
      -- psl f_decoded : assume always seq_emit -> decoded_ok(seq_uop);

      -- WRITE
      -- psl f_takes : assume always f_first = '0' -> w_r.uop = f_uop;
      -- psl f_sr_stable : assume always (f_first = '0' and f_sr_free = '0') -> w_r.regs(14) = f_sr;
      -- psl f_cond_stable : assume always (f_first = '0' and f_cond_free = '0') ->
      --    w_r.cond = f_cond;
      -- psl f_run : assume always (f_first = '0' and f_mode_free = '0' and f_mode = RUN_ST) ->
      --    w_r.mode = RUN_ST;
      -- psl f_keep : assume always (w_flush or take_nmi or take_irq) -> not p_committed_r;
      -- psl f_keep_read : assume always (w_flush or take_nmi or take_irq) -> not (rd_stb_r or p_load);
      -- psl f_accept : assume always w_accept -> not w_flush;

      -- DBUS: requests in flight, PREPARE's read among them, and the store
      -- that waits
      -- psl f_tags : assume always tag_cnt_r <= C_MAX_OUT;
      -- psl f_tag_grow : assume always f_first = '0' -> tag_cnt_r <= f_tag;
      -- psl f_st_acc : assume always
      --    st_acc_i = (st_valid_i and to_sl(tag_cnt_r < C_MAX_OUT) and not dbus_stall_i);
      -- psl f_st_queue : assume always st_valid_i -> f_st_may;

      -- The read request
      -- psl f_rd_hold : assert always (f_rd_stall and not rst_i) ->
      --    (rd_stb_r = '1' and rd_addr_r = f_rd_addr);
      -- psl f_rd_room : assert always (rst_i = '0' and rd_stb_r = '1') -> tag_cnt_r < C_MAX_OUT;
      -- psl f_rd_alone : assert always rst_i = '0' -> not (rd_stb_r = '1' and st_valid_i = '1');
      -- A read is on the bus only while the core runs: a halted core
      -- makes no data read
      -- psl f_rd_run : assert always (rst_i = '0' and rd_stb_r = '1') -> w_r.mode = RUN_ST;

      -- The reads of a micro-operation
      -- psl f_none_loaded : assert always (rst_i = '0' and prep_r.valid = '0') -> p_loaded_r = 0;
      -- psl f_loaded : assert always (rst_i = '0' and prep_r.valid = '1') -> p_loaded_r <= f_nr;
      -- psl f_all_read : assert always (rst_i = '0' and p_move = '1' and p_out.cond_val = '1') ->
      --    p_loaded_r + to_nat(p_load) = f_nr;

      -- The data access rule
      -- psl f_committed : assert always
      --    (rst_i = '0' and prep_r.valid = '1' and p_committed_r = '1' and
      --     p_out.cond_known = '1') ->
      --    p_out.cond_val = '1';

      -- The invariants that make it inductive. An instruction that has made
      -- a data read runs in RUN_ST. PREPARE knows its condition as true,
      -- or it is the first micro-operation, still here, whose condition
      -- holds on SR, which no micro-operation in WRITE may change, or its
      -- first micro-operation has retired with the condition true.
      -- psl f_inv_prep : assert always (rst_i = '0' and prep_r.valid = '1') ->
      --    (prep_r.inst = f_inst and prep_r.kind = f_kind and
      --     prep_r.last = is_last(prep_r.kind) and
      --     f_open = not prep_r.last and
      --     (prep_r.first = '0' or prep_r.kind = first_kind(prep_r.inst.iw)));
      -- psl f_inv_decoded : assert always (rst_i = '0' and prep_r.valid = '1') ->
      --    decoded_ok(prep_r);
      -- psl f_inv_wdecoded : assert always (rst_i = '0' and f_uop.valid = '1') ->
      --    decoded_ok(f_uop);
      -- WRITE holds an earlier micro-operation of the instruction in
      -- prep_r, or the last of the instruction before it.
      -- psl f_inv_same : assert always
      --    (rst_i = '0' and prep_r.valid = '1' and w_r.uop.valid = '1' and
      --     w_r.uop.inst.id = prep_r.inst.id) -> (w_r.uop.last = '0' and prep_r.first = '0');
      -- psl f_inv_older : assert always
      --    (rst_i = '0' and prep_r.valid = '1' and w_r.uop.valid = '1' and
      --     w_r.uop.inst.id /= prep_r.inst.id) -> (w_r.uop.last = '1' and prep_r.first = '1');
      -- psl f_inv_write : assert always
      --    (rst_i = '0' and prep_r.valid = '0' and w_r.uop.valid = '1') ->
      --    (w_r.uop.inst.id = f_inst.id and w_r.uop.last = not f_open);
      -- psl f_inv_wkind : assert always (rst_i = '0' and w_r.uop.valid = '1') ->
      --    w_r.uop.last = is_last(w_r.uop.kind);
      -- psl f_inv_ck_inst : assert always (rst_i = '0' and p_ck_r = '1') ->
      --    ((prep_r.valid = '1' and prep_r.first = '0') or (prep_r.valid = '0' and f_open = '1'));
      -- psl f_inv_open : assert always (rst_i = '0' and p_committed_r = '1') ->
      --    (f_open = '1' or prep_r.valid = '1');
      -- psl f_inv_run : assert always (rst_i = '0' and p_committed_r = '1') -> w_r.mode = RUN_ST;
      -- psl f_inv_ck : assert always (rst_i = '0' and p_committed_r = '1' and p_ck_r = '1') ->
      --    p_cv_r = '1';
      -- psl f_inv_first : assert always
      --    (rst_i = '0' and p_committed_r = '1' and prep_r.valid = '1' and prep_r.first = '1') ->
      --    (condition(prep_r.inst.iw, w_r.regs(14)) = '1' and
      --     not (w_r.uop.valid = '1' and w_r.uop.may_sr = '1'));
      -- psl f_inv_retired : assert always
      --    (rst_i = '0' and p_committed_r = '1' and p_ck_r = '0' and
      --     not (prep_r.valid = '1' and prep_r.first = '1')) ->
      --    (w_r.cond = '1' and not (w_r.uop.valid = '1' and w_r.uop.first = '1'));

      -- psl c_two : cover {rst_i = '0' and p_load = '1' and p_loaded_r = 1};
      -- psl c_stall : cover {f_rd_stall = '1' and rst_i = '0'};
      -- psl c_move : cover {rst_i = '0' and p_move = '1' and p_out.committed = '1' and
      --    p_out.last = '1'};
   end generate gen_formal;

end architecture synthesis;
