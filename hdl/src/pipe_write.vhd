-- WRITE of the pipelined core (MICROARCH.md §3, §5, §6, §7).
--
-- THEORY OF OPERATION
-- WRITE holds the architectural state: the registers, SR, PC, and the
-- hidden state of ISA.md §1.4. It runs the micro-operation in w_r.uop when
-- its read data has come: it computes the result, writes the registers,
-- puts a store into DBUS's register, and updates the flags. A store
-- into the I/O range waits in WRITE, w_r.busy, until the bus accepts it
-- (MICROARCH.md §5.3). It takes interrupts before an instruction,
-- runs the control instructions, and flushes the pipeline (see
-- src/pipeline.vhd). Its state is the record w_r (t_write), which PREPARE
-- reads too.
--
-- The registers are w_r. The other outputs depend combinationally on w_r
-- and on the inputs of the same cycle: the store and the vector read go
-- into DBUS's register, a flush reaches every stage at once, and the
-- report of a step comes in the cycle it retires, with the
-- registers it leaves (retire_o), as the trace writer's contract asks
-- (src/trace_pkg.vhd).
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) uop_i is PREPARE's micro-operation, which WRITE takes when move_i is
--    '1'. move_i is '1' only when accept_o is.
-- b) rq_i, rq_cnt_i, and ack_read_i give the read data that has come, in
--    order.
-- c) A device holds nmi_valid_i or irq_valid_i, and the vector, stable
--    until WRITE raises the matching take.
-- d) st_valid_i is '1' while a store or a vector read waits in DBUS's
--    register, and st_acc_i when the bus accepts it.
--
-- RESET
-- Synchronous. It sets the state of ISA.md §8.1.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use work.nice_pkg.all;
   use work.pipe_pkg.all;
   use work.trace_pkg.all;

entity pipe_write is
   port (
      clk_i        : in  std_logic;
      rst_i        : in  std_logic;

      -- From PREPARE
      move_i       : in  std_logic;
      uop_i        : in  t_uop;
      first_read_i : in  std_logic;
      rd_stb_i     : in  std_logic;
      accept_o     : out std_logic;   -- WRITE takes PREPARE's micro-operation

      -- The words fetched but not retired (MICROARCH.md §5.5)
      f_addr_i     : in  std_logic_vector(31 downto 0);
      f_blk_i      : in  std_logic_vector(31 downto 5);   -- Lags f_addr_i by a cycle
      dec_i        : in  t_inst;
      dec2_i       : in  t_inst;
      skid_i       : in  t_inst;
      prep_i       : in  t_uop;

      -- The data bus (src/pipe_dbus.vhd)
      rq_i         : in  t_words(0 to C_MAX_OUT - 1);
      rq_cnt_i     : in  natural range 0 to C_MAX_OUT;
      ack_read_i   : in  std_logic;
      dbus_data_i  : in  std_logic_vector(31 downto 0);
      pop_o        : out natural range 0 to 2;

      -- The store or the vector read, into DBUS's register
      -- (src/pipe_dbus.vhd)
      st_valid_i   : in  std_logic;
      st_acc_i     : in  std_logic;
      st_o         : out std_logic;
      st_we_o      : out std_logic;   -- '1' for a store, '0' for a vector read
      st_addr_o    : out std_logic_vector(31 downto 0);
      st_data_o    : out std_logic_vector(31 downto 0);

      -- Interrupt requests
      nmi_valid_i  : in  std_logic;
      nmi_vector_i : in  std_logic_vector(7 downto 0);
      irq_valid_i  : in  std_logic;
      irq_vector_i : in  std_logic_vector(7 downto 0);
      take_nmi_o   : out std_logic;
      take_irq_o   : out std_logic;

      -- WRITE's state, and its decisions in this cycle
      state_o      : out t_write;
      done_o       : out std_logic;   -- The micro-operation in WRITE retires
      flush_o      : out std_logic;   -- Empties the pipeline
      target_o     : out std_logic_vector(31 downto 0);
      instret_o    : out std_logic;
      retire_o     : out t_retire
   );
end entity pipe_write;

architecture synthesis of pipe_write is

   signal p_move       : std_logic;
   signal p_out        : t_uop;
   signal p_first_read : std_logic;
   signal rd_stb_r     : std_logic;
   signal f_addr       : std_logic_vector(31 downto 0);
   signal f_blk        : std_logic_vector(31 downto 5);
   signal dec_r        : t_inst;
   signal dec2_r       : t_inst;
   signal skid_r       : t_inst;
   signal prep_r       : t_uop;
   signal rq_r         : t_words(0 to C_MAX_OUT - 1);
   signal rq_cnt_r     : natural range 0 to C_MAX_OUT;
   signal ack_read     : std_logic;

   signal w_r       : t_write;
   signal w_n       : t_write;
   signal w_done    : std_logic;
   signal w_flush   : std_logic;
   signal w_target  : std_logic_vector(31 downto 0);
   signal w_accept  : std_logic;
   signal w_pop     : natural range 0 to 2;
   signal w_st      : std_logic;
   signal w_st_we   : std_logic;
   signal w_st_addr : std_logic_vector(31 downto 0);
   signal w_st_data : std_logic_vector(31 downto 0);
   signal w_instret : std_logic;
   signal take_nmi  : std_logic;
   signal take_irq  : std_logic;

begin

   p_move       <= move_i;
   p_out        <= uop_i;
   p_first_read <= first_read_i;
   rd_stb_r     <= rd_stb_i;
   f_addr       <= f_addr_i;
   f_blk        <= f_blk_i;
   dec_r        <= dec_i;
   dec2_r       <= dec2_i;
   skid_r       <= skid_i;
   prep_r       <= prep_i;
   rq_r         <= rq_i;
   rq_cnt_r     <= rq_cnt_i;
   ack_read     <= ack_read_i;

   accept_o   <= w_accept;
   pop_o      <= w_pop;
   st_o       <= w_st;
   st_we_o    <= w_st_we;
   st_addr_o  <= w_st_addr;
   st_data_o  <= w_st_data;
   take_nmi_o <= take_nmi;
   take_irq_o <= take_irq;
   state_o    <= w_r;
   done_o     <= w_done;
   flush_o    <= w_flush;
   target_o   <= w_target;
   instret_o  <= w_instret;


   p_write : process (all)
      variable n_v      : t_write;
      variable u_v      : t_uop;
      variable iw_v     : std_logic_vector(31 downto 0);
      variable cond_v   : std_logic;
      variable data_v   : t_words(0 to 1);
      variable avail_v  : natural range 0 to C_MAX_OUT + 1;
      variable byp_v    : boolean;   -- The micro-operation may take its read data from the bus
      variable bdata_v  : t_words(0 to 1);
      variable bavail_v : natural range 0 to C_MAX_OUT + 1;
      variable b0_v     : std_logic_vector(31 downto 0);
      variable b1_v     : std_logic_vector(31 downto 0);
      variable fres_v   : t_result;  -- The result for the flags
      variable rd_v     : std_logic_vector(1 to 2);
      variable nr_v     : natural range 0 to 2;
      variable k_v      : natural range 0 to 2;
      variable base_v   : t_fields;
      variable x_v      : natural range 0 to 15;
      variable m_v      : std_logic_vector(2 downto 0);
      variable v0_v     : std_logic_vector(31 downto 0);
      variable v1_v     : std_logic_vector(31 downto 0);
      variable cnt_v    : t_shift_prep;
      variable res_v    : t_result;
      variable a_v      : std_logic_vector(31 downto 0);
      variable wreg_v   : natural range 0 to 15;
      variable wval_v   : std_logic_vector(31 downto 0);
      variable target_v : std_logic_vector(31 downto 0);
      variable store_v  : boolean;
      variable adjust_v : boolean;   -- The destination is adjusted by one after the result
      variable hit_v    : boolean;   -- The store lies in fetched code
      variable two_v    : boolean;   -- The micro-operation needs a second cycle after this
      variable done_v   : boolean;
      variable flush_v  : boolean;
      variable halt_v   : t_halt;
      variable rti_v    : boolean;
      variable bound_v  : boolean;
      variable room_v   : boolean;
   begin
      n_v         := w_r;
      n_v.rep     := C_RETIRE_NONE;
      u_v         := w_r.uop;
      iw_v        := u_v.inst.iw;
      w_pop       <= 0;
      w_st        <= '0';
      w_st_we     <= '1';
      w_instret   <= '0';
      w_flush     <= '0';
      take_nmi    <= '0';
      take_irq    <= '0';
      done_v      := false;
      flush_v     := false;
      halt_v      := HALT_NONE;
      rti_v       := false;
      store_v     := false;
      adjust_v    := false;
      two_v       := false;
      res_v       := (r => (others => '0'), c => '0', v => '0');
      fres_v      := res_v;
      a_v         := (others => '0');
      v0_v        := (others => '0');
      v1_v        := (others => '0');
      x_v         := 0;
      m_v         := "000";
      k_v         := 0;
      rd_v        := "00";
      nr_v        := 0;
      wreg_v      := 0;
      wval_v      := (others => '0');
      -- The redirect target: R15 if an earlier micro-operation of the
      -- instruction wrote it, else the next instruction, for the refetch
      -- after a store into fetched code. A jump by this micro-operation
      -- sets it below.
      target_v    := w_r.regs(15) when w_r.jump = '1' else u_v.inst.next_pc;

      -- The read data, from DBUS's FIFO, so that no path runs from the bus
      -- through the ALU, the shifter, the store, or a jump.
      avail_v   := rq_cnt_r;
      data_v(0) := rq_r(0);
      data_v(1) := rq_r(1);

      -- A micro-operation whose read data only goes into a register may take
      -- it straight from the bus, in the cycle its ACK comes: s0 and s1 with
      -- a side effect, and a MOVE into a register other than R15
      -- (MICROARCH.md §5.3).
      byp_v      := u_v.kind = UOP_S0 or u_v.kind = UOP_S1 or
                    (u_v.kind = UOP_OP and u_v.inst.op = "0000" and u_v.inst.shift = '0' and
                      u_v.inst.m(0) = "000" and u_v.inst.x(0) /= 15);
      bavail_v   := rq_cnt_r + to_nat(ack_read) when byp_v else rq_cnt_r;
      bdata_v(0) := rq_r(0) when rq_cnt_r >= 1 else dbus_data_i;
      bdata_v(1) := rq_r(1) when rq_cnt_r >= 2 else dbus_data_i;

      -- Room in DBUS's register for WRITE's vector read
      room_v := rd_stb_r = '0' and (st_valid_i = '0' or st_acc_i = '1');

      -- The condition (ISA.md §3). A micro-operation in a later cycle of
      -- its own keeps the condition of its first, since it may have
      -- changed the flags itself.
      if u_v.cond_known = '1' then
         cond_v := u_v.cond_val;
      elsif u_v.first = '1' and w_r.exec_done = '0' and w_r.cnt_step = 0 then
         cond_v := condition(iw_v, w_r.regs(14));
      else
         cond_v := w_r.cond;
      end if;

      -- The value or address of each field, as PREPARE formed it, or the
      -- value written last, or SR (MICROARCH.md §7.4)
      for i in 0 to 2 loop
         case u_v.src(i) is
            when SRC_LAST => base_v(i) := w_r.last;
            when SRC_SR   => base_v(i) := w_r.regs(14);
            when others   => base_v(i) := u_v.val(i);
         end case;
      end loop;

      -- The value written last, for the next micro-operation: the register
      -- this one writes, as it is, unless this one writes it below.
      n_v.last := w_r.regs(u_v.wreg);

      -- The destination address of a store, and whether it lies in a word
      -- fetched but not retired (MICROARCH.md §5.5): FETCH holds at most
      -- 16 words from f_addr on, and an instruction at most 4. Decided
      -- here, from the operand alone, so that the flush depends on as
      -- little as possible.
      a_v   := base_v(0);
      hit_v := near(a_v, f_addr, f_blk, 5) or a_v(31 downto 5) = f_blk + 1 or
               (dec_r.valid = '1' and near(a_v, dec_r.addr, dec_r.blk, 2)) or
               (dec2_r.valid = '1' and near(a_v, dec2_r.addr, dec2_r.blk, 2)) or
               (skid_r.valid = '1' and near(a_v, skid_r.addr, skid_r.blk, 2)) or
               (prep_r.valid = '1' and near(a_v, prep_r.inst.addr, prep_r.inst.blk, 2));

      -- An instruction boundary where ISA.md §7.1 allows an interrupt, and
      -- no data access of the next instruction has begun.
      bound_v := w_r.mode = RUN_ST and rst_i = '0' and w_r.commits = 0 and w_r.mid = '0' and
                 w_r.busy = '0' and w_r.cnt_step = 0 and w_r.exec_done = '0' and
                 (u_v.valid = '0' or u_v.first = '1') and
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
         -- The vector table entry is at VBASE * 256 + v. Its read goes into
         -- DBUS's register, which drives the bus from the next cycle on.
         if w_r.vec_issued = '0' then
            if room_v then
               w_st           <= '1';
               w_st_we        <= '0';
               a_v            := w_r.regs(14)(23 downto 0) & w_r.vec;
               n_v.vec_issued := '1';
            end if;
         elsif avail_v >= 1 then
            w_pop        <= 1;
            n_v.saved_pc := w_r.regs(15) when w_r.vec_intr = '1' else u_v.inst.next_pc;
            n_v.saved_sr := w_r.regs(14);
            n_v.in_service    := '1';
            n_v.regs(14)(C_SR_I) := '1';
            n_v.regs(15) := data_v(0);
            target_v     := data_v(0);
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
                        target_v       := w_r.saved_pc;
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
            rd_v := u_v.reads;
            nr_v := popcount(rd_v);
            if w_r.exec_done = '1' then
               -- The second cycle of a register destination adjusted by
               -- one, or of a jump to a computed target: the result is
               -- in the register and in w_r.last.
               done_v := true;
               x_v    := u_v.inst.x(0);
               m_v    := u_v.inst.m(0);
               if m_v = "001" then
                  wreg_v := x_v;
                  wval_v := w_r.last - 1;
               elsif m_v = "010" then
                  wreg_v := x_v;
                  wval_v := w_r.last + 1;
               end if;
               target_v := regval(15, wval_v) when wreg_v = 15 else w_r.regs(15);
               if wreg_v /= 0 then
                  n_v.regs(wreg_v) := regval(wreg_v, wval_v);
                  n_v.last         := regval(wreg_v, wval_v);
               end if;
            elsif bavail_v >= nr_v then
               -- The sources (ISA.md §4.1): from memory, from S0 and S1 for
               -- the operation, or as PREPARE formed them
               if rd_v(1) = '1' then
                  v0_v := data_v(0);
                  k_v  := 1;
               elsif u_v.kind = UOP_OP and (u_v.inst.side(1) = '1' or u_v.inst.side(2) = '1') then
                  v0_v := w_r.s0val;
               else
                  v0_v := base_v(1);
               end if;
               if rd_v(2) = '1' then
                  v1_v := data_v(k_v);
               elsif u_v.kind = UOP_OP and u_v.inst.side(2) = '1' then
                  v1_v := w_r.s1val;
               else
                  v1_v := base_v(2);
               end if;
               -- The same, for a micro-operation that may take them from the bus
               b0_v := bdata_v(0) when rd_v(1) = '1' else v0_v;
               b1_v := bdata_v(k_v) when rd_v(2) = '1' else v1_v;

               if u_v.cnt_late = '1' and w_r.cnt_step /= 2 then
                  -- The first cycle of a shift whose count PREPARE could not
                  -- reduce: reduce it from the count as it is now, and
                  -- leave the read data for the next cycle. A rotation
                  -- through C takes a second cycle for the count mod 33.
                  if w_r.cnt_step = 0 then
                     n_v.cnt      := shift_prep(u_v.inst.op, v1_v, false);
                     n_v.m33sum   := mod33_sum(v1_v);
                     n_v.cnt_step := 1 when u_v.inst.op(2 downto 0) = "101" else 2;
                     n_v.cond     := cond_v;
                  else
                     n_v.cnt.k    := rot33_k(u_v.inst.op, mod33_of_sum(w_r.m33sum));
                     n_v.cnt_step := 2;
                  end if;
               else
                  done_v := true;
                  w_pop  <= nr_v;
                  cnt_v  := w_r.cnt when u_v.cnt_late = '1' else u_v.cnt;

                  case u_v.kind is
                     when UOP_S0 =>
                        -- s0 with its side effect
                        x_v       := u_v.inst.x(1);
                        m_v       := u_v.inst.m(1);
                        n_v.s0val := b0_v;
                        wreg_v    := x_v;
                        wval_v    := base_v(1) when m_v(0) = '1' else base_v(1) + 1;

                     when UOP_S1 =>
                        -- s0, unless S0 had it, then s1 with its side effect
                        if u_v.inst.side(1) = '0' then
                           n_v.s0val := b0_v;
                        end if;
                        x_v       := u_v.inst.x(2);
                        m_v       := u_v.inst.m(2);
                        n_v.s1val := b1_v;
                        wreg_v    := x_v;
                        wval_v    := base_v(2) when m_v(0) = '1' else base_v(2) + 1;

                     when others =>
                        -- ISA.md §5, steps 5 to 8
                        if u_v.inst.shift = '1' then
                           res_v := shift_fast(v0_v, w_r.regs(14)(C_SR_C), cnt_v);
                        else
                           res_v := alu(u_v.inst.op, v0_v, v1_v, u_v.inst.cbit and w_r.regs(14)(C_SR_C));
                        end if;

                        -- The destination (ISA.md §4.2)
                        x_v := u_v.inst.x(0);
                        m_v := u_v.inst.m(0);
                        case m_v is
                           when "000" =>
                              wreg_v := x_v;
                              wval_v := res_v.r;
                              -- A jump: a MOVE's target is its source, ready
                              -- now; any other is ready a cycle later. MOVE
                              -- is opcode 0000 of the ALU class only: the
                              -- shift 0<0 has the same opcode.
                              if x_v = 15 then
                                 target_v := v0_v;
                                 two_v    := u_v.inst.op /= "0000" or u_v.inst.shift = '1';
                              end if;
                           when "001" | "010" =>
                              wreg_v   := x_v;
                              wval_v   := res_v.r;
                              adjust_v := x_v /= 0;
                              two_v    := adjust_v;
                           when "101" =>
                              wreg_v := x_v;
                              wval_v := a_v;
                           when "110" =>
                              wreg_v := x_v;
                              wval_v := a_v + 1;
                           when others =>
                              null;
                        end case;
                        -- A side effect on R15 is the jump's target; else a
                        -- flush after this store refetches the next instruction.
                        if (m_v = "101" or m_v = "110") and x_v = 15 then
                           target_v := regval(15, wval_v);
                        end if;
                        store_v := u_v.store = '1';

                        -- A MOVE into a register writes its source as it
                        -- comes from the bus; the store and the jump above
                        -- never take it.
                        fres_v := res_v;
                        if byp_v then
                           fres_v := (r => b0_v, c => '0', v => '0');
                           wval_v := b0_v;
                        end if;
                  end case;

                  -- The register write. Whether it is R15, which starts a
                  -- flush, comes from the decoded field, so that the flush
                  -- does not wait for the write mux.
                  if wreg_v /= 0 then
                     n_v.regs(wreg_v) := regval(wreg_v, wval_v);
                     n_v.last         := regval(wreg_v, wval_v);
                  end if;
                  if u_v.wreg = 15 then
                     n_v.jump := '1';
                  end if;

                  -- The flags (ISA.md §6), after the destination
                  if u_v.kind = UOP_OP and u_v.inst.mbit = '1' and
                     not (u_v.inst.x(0) = 14 and u_v.inst.m(0)(2) = '0' and u_v.inst.m(0) /= "011") then
                     n_v.regs(14) := flags(n_v.regs(14), fres_v);
                  end if;

                  -- The store, into DBUS's register when it is free
                  -- or frees itself now. A store into memory retires then.
                  -- One into the I/O range retires when the bus accepts it,
                  -- so that a device sees it in the cycle of its step, as
                  -- the timer's count of steps needs (SYSTEM.md §4).
                  if store_v then
                     done_v := false;
                     if w_r.busy = '1' then
                        done_v := st_acc_i = '1';
                     elsif rd_stb_r = '0' and (st_valid_i = '0' or st_acc_i = '1') then
                        w_st   <= '1';
                        done_v := a_v(31 downto 8) /= X"FFFFFF";
                        n_v.busy := to_sl(not done_v);
                     end if;
                     if not done_v then
                        w_pop <= 0;
                     end if;

                     -- A store into a word fetched but not retired
                     if done_v and hit_v then
                        flush_v := true;
                     end if;
                     n_v.rep.mem_we   := '1';
                     n_v.rep.mem_addr := a_v;
                     n_v.rep.mem_data := res_v.r;
                  end if;

                  if two_v then
                     -- The result is written now; the micro-operation
                     -- retires in the next cycle.
                     done_v         := false;
                     n_v.exec_done  := '1';
                     n_v.cond       := cond_v;
                  end if;
               end if;
            end if;
         end if;

         if done_v then
            n_v.uop.valid := '0';
            n_v.busy      := '0';
            n_v.cnt_step  := 0;
            n_v.exec_done := '0';
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
            -- move to VEC_ST, the bus state, and the result of a first
            -- cycle.
            if w_r.exec_done = '0' and not two_v then
               n_v.regs  := w_r.regs;
               n_v.last  := w_r.last;
               n_v.jump  := w_r.jump;
            end if;
            n_v.s0val := w_r.s0val;
            n_v.s1val := w_r.s1val;
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

      -- The address and data of the store or the vector read, which DBUS
      -- takes when w_st is '1'
      w_st_addr <= a_v;
      w_st_data <= res_v.r;

      w_done   <= to_sl(done_v);
      w_flush  <= to_sl(flush_v);
      w_target <= target_v;
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
            w_r.cnt_step   <= 0;
            w_r.exec_done  <= '0';
            w_r.vec_issued <= '0';
            w_r.commits    <= 0;
            w_r.rep        <= C_RETIRE_NONE;
         end if;
      end if;
   end process p_write_reg;


   -- The report of the step, in the cycle it retires, with the registers it
   -- leaves. So an interrupt source that counts the steps sees each one as
   -- soon as it can.
   p_retire : process (all)
   begin
      retire_o      <= w_n.rep;
      retire_o.regs <= w_n.regs;
   end process p_retire;

end architecture synthesis;
