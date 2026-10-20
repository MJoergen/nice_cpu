-- Types and decode functions of the pipelined core (MICROARCH.md §3, §4).
--
-- THEORY OF OPERATION
-- DECODE turns an instruction into a t_inst, and splits it into
-- one to three micro-operations, each a t_uop (MICROARCH.md §4):
--
--   UOP_S0    s0 has a side effect on a register other than R0. Reads s0
--             if it is in memory, and writes the register.
--   UOP_S1    The same for s1. Reads s0 first, if it is a memory operand
--             that no UOP_S0 reads, then s1 if it is in memory.
--   UOP_OP    Reads the memory sources not read yet, computes the result,
--             writes the destination, and updates the flags.
--   UOP_CTRL  A control instruction.
--
-- A micro-operation makes at most one register write: the side effect of
-- its field, or the destination. The functions below give what each
-- micro-operation reads and writes, from the instruction word alone.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use work.nice_pkg.all;
   use work.trace_pkg.all;

package pipe_pkg is

   type t_words4 is array (0 to 3) of std_logic_vector(31 downto 0);

   -- One word per operand field: 0 = dest, 1 = s0, 2 = s1.
   type t_fields is array (0 to 2) of std_logic_vector(31 downto 0);

   type t_modes is array (0 to 2) of std_logic_vector(2 downto 0);

   type t_regnums is array (0 to 2) of natural range 0 to 15;

   type t_kind is (UOP_S0, UOP_S1, UOP_OP, UOP_CTRL);

   -- A decoded instruction. DECODE fills in what follows from the
   -- instruction word alone, once, so that the later stages start from
   -- registers (MICROARCH.md §7.4).
   type t_inst is record
      valid   : std_logic;
      id      : std_logic_vector(2 downto 0);    -- Tells instructions in flight apart
      addr    : std_logic_vector(31 downto 0);   -- Of the instruction word
      blk     : std_logic_vector(31 downto 2);   -- The 4-word block after addr's
      next_pc : std_logic_vector(31 downto 0);   -- After the constant words
      iw      : std_logic_vector(31 downto 0);
      consts  : t_fields;                        -- The constant word of each field
      early   : std_logic;                       -- DECODE has redirected FETCH to it
      m       : t_modes;                         -- The mode of each field
      x       : t_regnums;                       -- The register of each field
      side    : std_logic_vector(1 to 2);        -- The source has a side effect
      ctrl    : std_logic;                       -- A control instruction
      shift   : std_logic;                       -- A shift, else an ALU operation
      op      : std_logic_vector(3 downto 0);    -- The operation
      mbit    : std_logic;                       -- Writes the flags
      cbit    : std_logic;                       -- Takes the carry in
   end record t_inst;

   constant C_INST_NONE : t_inst := (
      valid   => '0',
      id      => (others => '0'),
      addr    => (others => '0'),
      blk     => (others => '0'),
      next_pc => (others => '0'),
      iw      => (others => '0'),
      consts  => (others => (others => '0')),
      early   => '0',
      m       => (others => (others => '0')),
      x       => (others => 0),
      side    => "00",
      ctrl    => '0',
      shift   => '0',
      op      => (others => '0'),
      mbit    => '0',
      cbit    => '0'
   );

   -- Where WRITE takes a field's value or address from (MICROARCH.md
   -- §7.4): the value PREPARE formed, the value WRITE wrote last, which
   -- the micro-operation before this one writes to the field's register,
   -- or SR, which WRITE keeps.
   type t_src is (SRC_VAL, SRC_LAST, SRC_SR);

   type t_srcs is array (0 to 2) of t_src;

   -- A micro-operation. DECODE fills in the fields down to cnt, for the
   -- kind of micro-operation, and PREPARE the rest.
   type t_uop is record
      valid      : std_logic;
      inst       : t_inst;
      kind       : t_kind;
      first      : std_logic;                    -- The instruction's first
      last       : std_logic;                    -- The instruction's last
      wreg       : natural range 0 to 15;        -- The register it writes, or 0
      reads      : std_logic_vector(1 to 2);     -- The sources it reads from memory
      store      : std_logic;                    -- It writes memory
      may_sr     : std_logic;                    -- It may change SR
      may_jump   : std_logic;                    -- It may write R15, or is a control instruction
      cnt        : t_shift_prep;                 -- The shift count, from the constant
      cond_known : std_logic;                    -- PREPARE has tested the condition
      cond_val   : std_logic;                    -- Its result
      committed  : std_logic;                    -- The instruction has made a data read
      counted    : std_logic;                    -- The instruction is in instret
      val        : t_fields;                     -- The value or address of each field
      src        : t_srcs;                       -- Where WRITE takes it from
      cnt_late   : std_logic;                    -- WRITE must prepare the shift count itself
   end record t_uop;

   constant C_UOP_NONE : t_uop := (
      valid      => '0',
      inst       => C_INST_NONE,
      kind       => UOP_OP,
      first      => '0',
      last       => '0',
      wreg       => 0,
      reads      => "00",
      store      => '0',
      may_sr     => '0',
      may_jump   => '0',
      cnt        => C_SHIFT_PREP_NONE,
      cond_known => '0',
      cond_val   => '0',
      committed  => '0',
      counted    => '0',
      val        => (others => (others => '0')),
      src        => (others => SRC_VAL),
      cnt_late   => '0'
   );

   -- What FETCH and DECODE did in one cycle, for the fetch statistics,
   -- src/fetch_stats.vhd (MICROARCH.md §8.1)
   type t_fetch_events is record
      count   : natural range 0 to 31;           -- Words in FETCH's buffer
      held    : natural range 0 to 31;           -- Those, and room held for the requests in flight
      starve  : std_logic;                       -- DECODE is free, and waits for words
      blocked : std_logic;                       -- An instruction is ready, and DECODE is busy
      full    : std_logic;                       -- FETCH could request, but lacks room
      stall   : std_logic;                       -- The instruction bus stalls a request
      pair    : std_logic;                       -- A pair of words arrives
      words   : natural range 0 to 4;            -- Words that DECODE takes
      jump    : std_logic;                       -- DECODE redirects FETCH
      flush   : std_logic;                       -- WRITE flushes and redirects FETCH
   end record t_fetch_events;

   constant C_FETCH_EVENTS_NONE : t_fetch_events := (
      count   => 0,
      held    => 0,
      starve  => '0',
      blocked => '0',
      full    => '0',
      stall   => '0',
      pair    => '0',
      words   => 0,
      jump    => '0',
      flush   => '0'
   );

   function to_sl(b : boolean) return std_logic;

   function to_nat(b : std_logic) return natural;

   function to_nat(b : boolean) return natural;

   function mode(iw : std_logic_vector(31 downto 0);
                 i  : natural range 0 to 2) return std_logic_vector;

   function reg(iw : std_logic_vector(31 downto 0);
                i  : natural range 0 to 2) return natural;

   function is_ctrl(iw : std_logic_vector(31 downto 0)) return boolean;

   -- The number of words of the instruction (ISA.md §2.3)
   function inst_len(iw : std_logic_vector(31 downto 0)) return natural;

   -- Source i (1 or 2) has a side effect on a register other than R0.
   function side(iw : std_logic_vector(31 downto 0);
                 i  : natural range 1 to 2) return boolean;

   -- The first micro-operation of an instruction, and the one after k.
   function first_kind(iw : std_logic_vector(31 downto 0)) return t_kind;

   function next_kind(iw : std_logic_vector(31 downto 0);
                      k  : t_kind) return t_kind;

   function is_last(k : t_kind) return std_logic;

   -- The sources that micro-operation k reads from memory, s0 in bit 1 and
   -- s1 in bit 2.
   function uop_reads(iw : std_logic_vector(31 downto 0);
                      k  : t_kind) return std_logic_vector;

   -- A micro-operation after k reads memory.
   function later_reads(iw : std_logic_vector(31 downto 0);
                        k  : t_kind) return boolean;

   -- The register that micro-operation k writes, or 0. Control
   -- instructions write R14 and R15 in other ways.
   function uop_wreg(iw : std_logic_vector(31 downto 0);
                     k  : t_kind) return natural;

   -- Micro-operation k writes memory.
   function uop_store(iw : std_logic_vector(31 downto 0);
                      k  : t_kind) return boolean;

   -- Micro-operation k may change SR.
   function uop_may_sr(iw : std_logic_vector(31 downto 0);
                       k  : t_kind) return boolean;

   -- Micro-operation k may write R15, or is a control instruction, which
   -- may jump or halt.
   function uop_may_jump(iw : std_logic_vector(31 downto 0);
                         k  : t_kind) return boolean;

   -- Data bus requests in flight, the ACKs owed
   constant C_MAX_OUT : natural := 4;

   type t_words is array (natural range <>) of std_logic_vector(31 downto 0);

   type t_wmode is (RUN_ST, VEC_ST, HALTED_ST, PAUSED_ST);

   -- The state of WRITE
   type t_write is record
      uop        : t_uop;
      mode       : t_wmode;
      regs       : t_regs;
      in_service : std_logic;
      after_rti  : std_logic;
      after_go   : std_logic;                       -- The first instruction after a pause
      saved_pc   : std_logic_vector(31 downto 0);
      saved_sr   : std_logic_vector(31 downto 0);
      halt       : t_halt;
      cond       : std_logic;                       -- The condition of the instruction
      mid        : std_logic;                       -- Part of an instruction has retired
      jump       : std_logic;                       -- The instruction has written R15
      s0val      : std_logic_vector(31 downto 0);   -- s0, from S0 or S1
      s1val      : std_logic_vector(31 downto 0);   -- s1, from S1
      busy       : std_logic;                       -- An access waits on the bus
      last       : std_logic_vector(31 downto 0);   -- The value written last (MICROARCH.md §7.4)
      cnt_step   : natural range 0 to 2;            -- How far the shift count is prepared
      m33sum     : natural range 0 to 255;          -- Its digit sum, for the count mod 33
      exec_done  : std_logic;                       -- The result is written; the retire is next
      cnt        : t_shift_prep;                    -- The shift count WRITE prepared itself
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
                      c : std_logic_vector(31 downto 0)) return std_logic_vector;

   -- The address of a memory operand, source or destination, before any
   -- side effect of its own (ISA.md §4.1 and §4.2).
   function mem_addr(m : std_logic_vector(2 downto 0);
                     x : natural range 0 to 15;
                     b : std_logic_vector(31 downto 0);
                     c : std_logic_vector(31 downto 0)) return std_logic_vector;

   -- a lies in the aligned block of 2^bits words that holds lo, or in the
   -- block after it, whose number the caller computed ahead. That covers
   -- the 2^bits words from lo on, with no subtraction: two equality
   -- compares, and safe where the range is known to be no longer
   -- (MICROARCH.md §5.5).
   function near(a       : std_logic_vector(31 downto 0);
                 lo      : std_logic_vector(31 downto 0);
                 lo_next : std_logic_vector;
                 bits    : natural) return boolean;

   -- The number of the block after the one that holds lo.
   function next_block(lo   : std_logic_vector(31 downto 0);
                       bits : natural) return std_logic_vector;

   function popcount(v : std_logic_vector) return natural;

   -- The fields that DECODE fills in agree with the instruction word and
   -- the kind, for the checks in simulation and the formal proofs.
   function decoded_ok(u : t_uop) return boolean;

end package pipe_pkg;

package body pipe_pkg is

   function to_sl(b : boolean) return std_logic is
   begin
      if b then
         return '1';
      else
         return '0';
      end if;
   end function to_sl;

   function to_nat(b : std_logic) return natural is
   begin
      if b = '1' then
         return 1;
      else
         return 0;
      end if;
   end function to_nat;

   function to_nat(b : boolean) return natural is
   begin
      if b then
         return 1;
      else
         return 0;
      end if;
   end function to_nat;

   function mode(iw : std_logic_vector(31 downto 0);
                 i  : natural range 0 to 2) return std_logic_vector is
      variable f_v   : std_logic_vector(6 downto 0);
      variable res_v : std_logic_vector(2 downto 0);
   begin
      f_v   := field(iw, i);
      res_v := f_v(6 downto 4);
      return res_v;
   end function mode;

   function reg(iw : std_logic_vector(31 downto 0);
                i  : natural range 0 to 2) return natural is
      variable f_v : std_logic_vector(6 downto 0);
   begin
      f_v := field(iw, i);
      return to_integer(f_v(3 downto 0));
   end function reg;

   function is_ctrl(iw : std_logic_vector(31 downto 0)) return boolean is
   begin
      return iw(27 downto 26) = "11";
   end function is_ctrl;

   function inst_len(iw : std_logic_vector(31 downto 0)) return natural is
      variable cf_v  : std_logic_vector(0 to 2);
      variable res_v : natural range 1 to 4 := 1;
   begin
      cf_v := const_fields(iw);
      for i in 0 to 2 loop
         if cf_v(i) = '1' then
            res_v := res_v + 1;
         end if;
      end loop;
      return res_v;
   end function inst_len;

   function side(iw : std_logic_vector(31 downto 0);
                 i  : natural range 1 to 2) return boolean is
      variable m_v : std_logic_vector(2 downto 0);
   begin
      m_v := mode(iw, i);
      return not is_ctrl(iw) and reg(iw, i) /= 0 and
             (m_v = "001" or m_v = "010" or m_v = "101" or m_v = "110");
   end function side;

   function first_kind(iw : std_logic_vector(31 downto 0)) return t_kind is
   begin
      if is_ctrl(iw) then
         return UOP_CTRL;
      elsif side(iw, 1) then
         return UOP_S0;
      elsif side(iw, 2) then
         return UOP_S1;
      else
         return UOP_OP;
      end if;
   end function first_kind;

   function next_kind(iw : std_logic_vector(31 downto 0);
                      k  : t_kind) return t_kind is
   begin
      if k = UOP_S0 and side(iw, 2) then
         return UOP_S1;
      else
         return UOP_OP;
      end if;
   end function next_kind;

   function is_last(k : t_kind) return std_logic is
   begin
      if k = UOP_OP or k = UOP_CTRL then
         return '1';
      else
         return '0';
      end if;
   end function is_last;

   function uop_reads(iw : std_logic_vector(31 downto 0);
                      k  : t_kind) return std_logic_vector is
      variable mem0_v : std_logic;
      variable mem1_v : std_logic;
      variable res_v  : std_logic_vector(1 to 2) := "00";
   begin
      mem0_v := mode(iw, 1)(2);
      mem1_v := mode(iw, 2)(2);
      case k is
         when UOP_S0 =>
            res_v(1) := mem0_v;
         when UOP_S1 =>
            if not side(iw, 1) then
               res_v(1) := mem0_v;
            end if;
            res_v(2) := mem1_v;
         when UOP_OP =>
            if not side(iw, 1) and not side(iw, 2) then
               res_v(1) := mem0_v;
            end if;
            if not side(iw, 2) then
               res_v(2) := mem1_v;
            end if;
         when UOP_CTRL =>
            null;
      end case;
      return res_v;
   end function uop_reads;

   function later_reads(iw : std_logic_vector(31 downto 0);
                        k  : t_kind) return boolean is
   begin
      case k is
         when UOP_S0 =>
            return (side(iw, 2) and uop_reads(iw, UOP_S1) /= "00") or uop_reads(iw, UOP_OP) /= "00";
         when UOP_S1 =>
            return uop_reads(iw, UOP_OP) /= "00";
         when others =>
            return false;
      end case;
   end function later_reads;

   function uop_wreg(iw : std_logic_vector(31 downto 0);
                     k  : t_kind) return natural is
      variable m_v : std_logic_vector(2 downto 0);
   begin
      case k is
         when UOP_S0 =>
            return reg(iw, 1);
         when UOP_S1 =>
            return reg(iw, 2);
         when UOP_OP =>
            m_v := mode(iw, 0);
            if m_v = "011" or m_v = "100" or m_v = "111" then
               return 0;
            else
               return reg(iw, 0);
            end if;
         when UOP_CTRL =>
            return 0;
      end case;
   end function uop_wreg;

   function uop_store(iw : std_logic_vector(31 downto 0);
                      k  : t_kind) return boolean is
      variable m_v : std_logic_vector(2 downto 0);
   begin
      m_v := mode(iw, 0);
      return k = UOP_OP and (m_v(2) = '1' or m_v = "011");
   end function uop_store;

   function uop_may_sr(iw : std_logic_vector(31 downto 0);
                       k  : t_kind) return boolean is
   begin
      return k = UOP_CTRL or uop_wreg(iw, k) = 14 or (k = UOP_OP and iw(25) = '1');
   end function uop_may_sr;

   function uop_may_jump(iw : std_logic_vector(31 downto 0);
                         k  : t_kind) return boolean is
   begin
      return k = UOP_CTRL or uop_wreg(iw, k) = 15;
   end function uop_may_jump;

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

   function near(a       : std_logic_vector(31 downto 0);
                 lo      : std_logic_vector(31 downto 0);
                 lo_next : std_logic_vector;
                 bits    : natural) return boolean is
   begin
      return a(31 downto bits) = lo(31 downto bits) or a(31 downto bits) = lo_next;
   end function near;

   function next_block(lo   : std_logic_vector(31 downto 0);
                       bits : natural) return std_logic_vector is
      variable res_v : std_logic_vector(31 downto bits);
   begin
      res_v := lo(31 downto bits) + 1;
      return res_v;
   end function next_block;

   function decoded_ok(u : t_uop) return boolean is
      variable iw_v : std_logic_vector(31 downto 0);
      variable ok_v : boolean;
   begin
      iw_v := u.inst.iw;
      ok_v := u.wreg = uop_wreg(iw_v, u.kind) and
              u.reads = uop_reads(iw_v, u.kind) and
              u.store = to_sl(uop_store(iw_v, u.kind)) and
              u.may_sr = to_sl(uop_may_sr(iw_v, u.kind)) and
              u.may_jump = to_sl(uop_may_jump(iw_v, u.kind)) and
              u.inst.side = to_sl(side(iw_v, 1)) & to_sl(side(iw_v, 2)) and
              u.inst.ctrl = to_sl(is_ctrl(iw_v)) and
              u.inst.shift = (iw_v(27) and not to_sl(is_ctrl(iw_v))) and
              u.inst.op = iw_v(24 downto 21) and
              u.inst.mbit = iw_v(25) and
              u.inst.cbit = iw_v(26);
      for i in 0 to 2 loop
         if u.inst.m(i) /= mode(iw_v, i) or u.inst.x(i) /= reg(iw_v, i) then
            ok_v := false;
         end if;
      end loop;
      return ok_v;
   end function decoded_ok;

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

end package body pipe_pkg;
