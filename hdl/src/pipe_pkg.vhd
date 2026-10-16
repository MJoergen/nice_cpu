-- Types and decode functions of the pipelined core (MICROARCH.md §3, §4).
--
-- THEORY OF OPERATION
-- DECODE turns an instruction into a t_inst. The SEQUENCER splits it into
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

package pipe_pkg is

   type t_words4 is array (0 to 3) of std_logic_vector(31 downto 0);

   -- One word per operand field: 0 = dest, 1 = s0, 2 = s1.
   type t_fields is array (0 to 2) of std_logic_vector(31 downto 0);

   type t_kind is (UOP_S0, UOP_S1, UOP_OP, UOP_CTRL);

   -- A decoded instruction
   type t_inst is record
      valid   : std_logic;
      id      : std_logic_vector(2 downto 0);    -- Tells instructions in flight apart
      addr    : std_logic_vector(31 downto 0);   -- Of the instruction word
      next_pc : std_logic_vector(31 downto 0);   -- After the constant words
      iw      : std_logic_vector(31 downto 0);
      consts  : t_fields;                        -- The constant word of each field
      early   : std_logic;                       -- DECODE has redirected FETCH to it
   end record t_inst;

   constant C_INST_NONE : t_inst := (
      valid   => '0',
      id      => (others => '0'),
      addr    => (others => '0'),
      next_pc => (others => '0'),
      iw      => (others => '0'),
      consts  => (others => (others => '0')),
      early   => '0'
   );

   -- A micro-operation
   type t_uop is record
      valid      : std_logic;
      inst       : t_inst;
      kind       : t_kind;
      first      : std_logic;                    -- The instruction's first
      last       : std_logic;                    -- The instruction's last
      cond_known : std_logic;                    -- PREPARE has tested the condition
      cond_val   : std_logic;                    -- Its result
      committed  : std_logic;                    -- The instruction has made a data read
      counted    : std_logic;                    -- The instruction is in instret
   end record t_uop;

   constant C_UOP_NONE : t_uop := (
      valid      => '0',
      inst       => C_INST_NONE,
      kind       => UOP_OP,
      first      => '0',
      last       => '0',
      cond_known => '0',
      cond_val   => '0',
      committed  => '0',
      counted    => '0'
   );

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

end package pipe_pkg;

package body pipe_pkg is

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

end package body pipe_pkg;
