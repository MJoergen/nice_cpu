-- The parts of the ISA that both cores share: the fields of an instruction
-- word, the register value rule, the ALU, and the shifter.
--
-- THEORY OF OPERATION
-- Each function is combinational and follows one section of ISA.md:
--
--   regval        §4.3, the value of a register after a write
--   field         §2.1, an operand field
--   const_fields  §2.3, the fields that take a constant word
--   alu           §5.1, with carry and overflow
--   shift         §5.2, in the closed forms given there
--
-- The shifter reduces its count as MICROARCH.md §7.3 describes. A core can
-- reduce it ahead of the shift, with shift_count, and keep the reduction
-- out of the shift's path.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

package nice_pkg is

   -- SR bits (ISA.md §1.3)
   constant C_SR_I   : natural := 31;
   constant C_SR_E   : natural := 30;
   constant C_SR_V   : natural := 29;
   constant C_SR_N   : natural := 28;
   constant C_SR_Z   : natural := 27;
   constant C_SR_C   : natural := 26;
   constant C_SR_X   : natural := 25;
   constant C_SR_ONE : natural := 24;

   -- The flags an instruction with M = 1 rewrites (ISA.md §6).
   constant C_FLAG_MASK : std_logic_vector(31 downto 0) := X"3E000000";

   -- The result of an operation, with carry and overflow for the flags.
   type t_result is record
      r : std_logic_vector(31 downto 0);
      c : std_logic;
      v : std_logic;
   end record t_result;

   function to_sl(b : boolean) return std_logic;

   -- Whether the instruction is a control instruction (ISA.md §5.3).
   function is_ctrl(iw : std_logic_vector(31 downto 0)) return boolean;

   -- The value of register x after a write of v (ISA.md §4.3).
   function regval(x : natural range 0 to 15;
                   v : std_logic_vector(31 downto 0)) return std_logic_vector;

   -- The operand field i of an instruction word: 0 = dest, 1 = s0, 2 = s1.
   function field(iw : std_logic_vector(31 downto 0);
                  i  : natural range 0 to 2) return std_logic_vector;

   -- The fields that take a constant word (ISA.md §2.3). None for control
   -- instructions.
   function const_fields(iw : std_logic_vector(31 downto 0)) return std_logic_vector;

   -- The condition of an instruction word, tested against sr (ISA.md §3).
   function condition(iw : std_logic_vector(31 downto 0);
                      sr : std_logic_vector(31 downto 0)) return std_logic;

   -- ISA.md §5.1. cin is already 0 if the instruction's C bit is clear.
   function alu(op  : std_logic_vector(3 downto 0);
                s0  : std_logic_vector(31 downto 0);
                s1  : std_logic_vector(31 downto 0);
                cin : std_logic) return t_result;

   -- The reduced counts of a shift count n (MICROARCH.md §7.3). The 32-bit
   -- rotations take bits 4..0 of n directly.
   type t_shift_count is record
      m33 : natural range 0 to 32;   -- n mod 33
      sat : natural range 0 to 33;   -- n saturated to 33
      nz  : std_logic;               -- '1' if n /= 0
   end record t_shift_count;

   -- n mod 33, for the rotations through C: the sum of its digits with
   -- alternating signs, plus 99, and then a table of that sum.
   function mod33_sum(n : std_logic_vector(31 downto 0)) return natural;

   function mod33_of_sum(sum : natural range 0 to 255) return natural;

   function mod33(n : std_logic_vector(31 downto 0)) return natural;

   -- Without mod33, m33 is 0: the multicycle core computes it in a state of
   -- its own, and shift_prep does not use it.
   function shift_count(n          : std_logic_vector(31 downto 0);
                        with_mod33 : boolean := true) return t_shift_count;

   -- ISA.md §5.2. c is the C flag. The carry of the result is the C flag
   -- after the shift, before M is applied. cnt is shift_count(n).
   function shift(op  : std_logic_vector(3 downto 0);
                  s0  : std_logic_vector(31 downto 0);
                  n   : std_logic_vector(31 downto 0);
                  c   : std_logic;
                  cnt : t_shift_count) return t_result;

   -- The same, with the counts reduced in the shift.
   function shift(op : std_logic_vector(3 downto 0);
                  s0 : std_logic_vector(31 downto 0);
                  n  : std_logic_vector(31 downto 0);
                  c  : std_logic) return t_result;

   -- The shift k of a prepared C<C or C>C, from the count mod 33, for a
   -- stage that has only that.
   function rot33_k(op  : std_logic_vector(3 downto 0);
                    m33 : natural range 0 to 32) return natural;

   -- A shift prepared ahead of the shifter (MICROARCH.md §7.3). Every shift
   -- of ISA.md §5.2 is a window of 33 bits, the result and the bit for C,
   -- taken from a vector of 66 bits built from s0, C, and the fill bit,
   -- after a right shift by k. The kind of vector, the shift, and how C is
   -- found depend only on the operation and the count, so a core can
   -- compute them a stage early, and the shifter itself has no count
   -- reduction and no reverse in its path.
   type t_tsel is (T_LFILL, T_RFILL, T_ROT33, T_ROT32);
   type t_fsel is (FILL_0, FILL_1, FILL_C);
   type t_csel is (C_ZERO, C_WIN, C_RIGHT, C_ROTL, C_ROTR);

   type t_shift_prep is record
      k    : natural range 0 to 33;   -- The right shift of the vector
      tsel : t_tsel;                  -- The vector to build
      fsel : t_fsel;                  -- Its fill bit
      csel : t_csel;                  -- Where C comes from
      sat  : natural range 0 to 33;   -- n saturated to 33, for C_RIGHT
      nz   : std_logic;               -- '1' if n /= 0, for C_ROTL and C_ROTR
   end record t_shift_prep;

   constant C_SHIFT_PREP_NONE : t_shift_prep := (
      k    => 0,
      tsel => T_LFILL,
      fsel => FILL_0,
      csel => C_ZERO,
      sat  => 0,
      nz   => '0'
   );

   -- With with_mod33 false, the count mod 33 is left out, and the result
   -- is wrong for C<C and C>C: for a stage that cannot afford it.
   function shift_prep(op         : std_logic_vector(3 downto 0);
                       n          : std_logic_vector(31 downto 0);
                       with_mod33 : boolean := true) return t_shift_prep;

   -- ISA.md §5.2, from a prepared shift. The same result as shift.
   function shift_fast(s0 : std_logic_vector(31 downto 0);
                       c  : std_logic;
                       p  : t_shift_prep) return t_result;

   -- SR after an instruction with M = 1 and result res (ISA.md §6).
   function flags(sr  : std_logic_vector(31 downto 0);
                  res : t_result) return std_logic_vector;

end package nice_pkg;

package body nice_pkg is

   function to_sl(b : boolean) return std_logic is
   begin
      if b then
         return '1';
      else
         return '0';
      end if;
   end function to_sl;

   function is_ctrl(iw : std_logic_vector(31 downto 0)) return boolean is
   begin
      return iw(27 downto 26) = "11";
   end function is_ctrl;

   function regval(x : natural range 0 to 15;
                   v : std_logic_vector(31 downto 0)) return std_logic_vector is
      variable res_v : std_logic_vector(31 downto 0) := v;
   begin
      if x = 0 then
         res_v := (others => '0');
      elsif x = 14 then
         res_v(C_SR_ONE) := '1';
      end if;
      return res_v;
   end function regval;

   function field(iw : std_logic_vector(31 downto 0);
                  i  : natural range 0 to 2) return std_logic_vector is
      constant C_LOW : natural := 14 - 7 * i;
      variable res_v : std_logic_vector(6 downto 0);
   begin
      res_v := iw(C_LOW + 6 downto C_LOW);
      return res_v;
   end function field;

   function const_fields(iw : std_logic_vector(31 downto 0)) return std_logic_vector is
      variable res_v : std_logic_vector(0 to 2) := "000";
   begin
      if not is_ctrl(iw) then
         for i in 0 to 2 loop
            if field(iw, i)(5 downto 4) = "11" then
               res_v(i) := '1';
            end if;
         end loop;
      end if;
      return res_v;
   end function const_fields;

   function condition(iw : std_logic_vector(31 downto 0);
                      sr : std_logic_vector(31 downto 0)) return std_logic is
   begin
      return sr(C_SR_ONE + to_integer(iw(30 downto 28))) xor iw(31);
   end function condition;

   -- One adder A + B + k serves the five arithmetic operations
   -- (MICROARCH.md §7.2). A subtraction adds the inverted subtrahend and
   -- inverts the carry in and out.
   function alu(op  : std_logic_vector(3 downto 0);
                s0  : std_logic_vector(31 downto 0);
                s1  : std_logic_vector(31 downto 0);
                cin : std_logic) return t_result is
      variable b_v   : std_logic_vector(31 downto 0);
      variable k_v   : std_logic;
      variable sum_v : std_logic_vector(32 downto 0);
      variable res_v : t_result := (r => (others => '0'), c => '0', v => '0');
   begin
      case op is
         when "0001" => b_v := not s1;           k_v := not cin;   -- SUB
         when "0010" => b_v := s0 and s1;        k_v := cin;       -- MDBL
         when "0100" => b_v := s0;               k_v := cin;       -- DBL
         when "0101" => b_v := (others => '1');  k_v := '0';       -- DEC
         when others => b_v := s1;               k_v := cin;       -- ADD
      end case;
      sum_v := ('0' & s0) + ('0' & b_v) + k_v;

      case op is
         when "0000" => res_v.r := s0;
         when "0110" => res_v.r := not s0;
         when "0111" => res_v.r := not (s0 or s1);
         when "1000" => res_v.r := (not s0) and s1;
         when "1001" => res_v.r := not (s0 and s1);
         when "1010" => res_v.r := s0 xor s1;
         when "1011" => res_v.r := (not s0) or s1;
         when "1100" => res_v.r := not (s0 xor s1);
         when "1101" => res_v.r := s0 and s1;
         when "1110" => res_v.r := X"00000001";
         when "1111" => res_v.r := s0 or s1;
         when others =>
            -- The arithmetic operations. C is the borrow for SUB and DEC.
            res_v.r := sum_v(31 downto 0);
            res_v.c := sum_v(32) xor to_sl(op = "0001" or op = "0101");
            res_v.v := (s0(31) xor res_v.r(31)) and (b_v(31) xor res_v.r(31));
      end case;
      return res_v;
   end function alu;

   function reverse(v : std_logic_vector(31 downto 0)) return std_logic_vector is
      variable res_v : std_logic_vector(31 downto 0);
   begin
      for i in 0 to 31 loop
         res_v(i) := v(31 - i);
      end loop;
      return res_v;
   end function reverse;

   -- A table of i mod 33, for the last step of mod33.
   type t_mod33 is array (0 to 255) of natural range 0 to 32;

   function mod33_table return t_mod33 is
      variable res_v : t_mod33;
   begin
      for i in res_v'range loop
         res_v(i) := i mod 33;
      end loop;
      return res_v;
   end function mod33_table;

   constant C_MOD33 : t_mod33 := mod33_table;

   -- n mod 33, as in doc/MICROARCH.md §7.3: 32 = -1 (mod 33), so the 5-bit
   -- digits of n count with alternating signs. 99 keeps the sum positive,
   -- and a table reduces it, instead of a chain of compares and
   -- subtractions.
   function mod33_sum(n : std_logic_vector(31 downto 0)) return natural is
      variable sum_v : integer range 0 to 255;
   begin
      sum_v := 99 + to_integer(n(4 downto 0)) - to_integer(n(9 downto 5)) +
               to_integer(n(14 downto 10)) - to_integer(n(19 downto 15)) +
               to_integer(n(24 downto 20)) - to_integer(n(29 downto 25)) +
               to_integer(n(31 downto 30));
      return sum_v;
   end function mod33_sum;

   function mod33_of_sum(sum : natural range 0 to 255) return natural is
   begin
      return C_MOD33(sum);
   end function mod33_of_sum;

   function mod33(n : std_logic_vector(31 downto 0)) return natural is
   begin
      return mod33_of_sum(mod33_sum(n));
   end function mod33;

   function rot33_k(op  : std_logic_vector(3 downto 0);
                    m33 : natural range 0 to 32) return natural is
   begin
      if op(3) = '0' then
         return 33 - m33;
      elsif m33 = 0 then
         return 33;
      else
         return m33;
      end if;
   end function rot33_k;

   function shift_count(n          : std_logic_vector(31 downto 0);
                        with_mod33 : boolean := true) return t_shift_count is
      variable res_v : t_shift_count;
   begin
      res_v.m33 := mod33(n) when with_mod33 else 0;
      res_v.sat := 33 when n > 33 else to_integer(n(5 downto 0));
      res_v.nz  := '1' when n /= 0 else '0';
      return res_v;
   end function shift_count;

   -- A right shift is the mirror image of the left shift of the same kind,
   -- so s0 is reversed before and the result after.
   function shift(op  : std_logic_vector(3 downto 0);
                  s0  : std_logic_vector(31 downto 0);
                  n   : std_logic_vector(31 downto 0);
                  c   : std_logic;
                  cnt : t_shift_count) return t_result is
      variable d_v     : std_logic_vector(31 downto 0);
      variable fill_v  : std_logic;
      variable fills_v : std_logic_vector(32 downto 0);
      variable wide_v  : std_logic_vector(65 downto 0);   -- c, d, 33 fill bits
      variable rot_v   : std_logic_vector(65 downto 0);   -- c, d, c, d
      variable res_v   : t_result := (r => (others => '0'), c => c, v => '0');
   begin
      d_v := reverse(s0) when op(3) = '1' else s0;

      case op(2 downto 0) is
         when "101" =>
            -- C<C, C>C: a 33-bit rotation of C and d, as one shift of
            -- two copies
            rot_v   := (c & d_v & c & d_v) sll cnt.m33;
            res_v.r := rot_v(64 downto 33);
            res_v.c := rot_v(65);

         when "110" | "111" =>
            -- <<<, C<<, >>>, >>C: a 32-bit rotation. C gets the bit rotated
            -- last.
            res_v.r := d_v rol to_integer(n(4 downto 0));
            if cnt.nz = '1' then
               res_v.c := res_v.r(0);
            end if;

         when others =>
            -- A fixed fill. After 33 steps, nothing changes any more.
            case op(2 downto 0) is
               when "001" | "100" => fill_v := '1';   -- 0<1, C<1
               when "010"         => fill_v := c;     -- 0<C
               when others        => fill_v := '0';   -- 0<0, C<0
            end case;
            fills_v := (others => fill_v);
            wide_v  := (c & d_v & fills_v) sll cnt.sat;
            res_v.r := wide_v(64 downto 33);
            res_v.c := wide_v(65);
      end case;

      if op(3) = '1' then
         res_v.r := reverse(res_v.r);
      end if;

      -- Only 011, 100, 101, and 111 send the bit shifted out to C.
      case op(2 downto 0) is
         when "011" | "100" | "101" | "111" => null;
         when others                         => res_v.c := '0';
      end case;

      return res_v;
   end function shift;

   function shift(op : std_logic_vector(3 downto 0);
                  s0 : std_logic_vector(31 downto 0);
                  n  : std_logic_vector(31 downto 0);
                  c  : std_logic) return t_result is
   begin
      return shift(op, s0, n, c, shift_count(n));
   end function shift;

   -- The kinds of shift of ISA.md §5.2, as a window after a right shift
   -- (the comment at t_shift_prep). With sat the count saturated to 33, m
   -- the count mod 33, and n5 its low five bits:
   -- * A fixed fill to the left: the vector is C, s0, and 33 fill bits, and
   --   k = 33 - sat. A fill to the right: 34 fill bits and s0, and k = sat.
   --   The bit for C is the one above the window to the left, and the last
   --   bit shifted out to the right, s0(sat - 1).
   -- * C<C and C>C: the vector is C, s0, C, s0, a 33-bit rotation of C and
   --   s0 twice. To the left, k = 33 - m. To the right, k = m, or 33 for
   --   m = 0. C is the bit above the window.
   -- * The 32-bit rotations: the vector is s0 twice. To the left, k = 32 -
   --   n5. To the right, k = n5. C gets the bit rotated last, if the count
   --   is not 0 and the operation sends it to C.
   function shift_prep(op         : std_logic_vector(3 downto 0);
                       n          : std_logic_vector(31 downto 0);
                       with_mod33 : boolean := true) return t_shift_prep is
      variable p_v   : t_shift_prep := C_SHIFT_PREP_NONE;
      variable m33_v : natural range 0 to 32;
      variable n5_v  : natural range 0 to 31;
      variable to_c  : boolean;
      variable cnt_v : t_shift_count;
   begin
      cnt_v   := shift_count(n, false);
      p_v.sat := cnt_v.sat;
      p_v.nz  := cnt_v.nz;
      m33_v   := mod33(n) when with_mod33 else 0;
      n5_v    := to_integer(n(4 downto 0));
      -- Only 011, 100, 101, and 111 send the bit shifted out to C.
      to_c    := op(2 downto 0) = "011" or op(2 downto 0) = "100" or
                 op(2 downto 0) = "101" or op(2 downto 0) = "111";

      case op(2 downto 0) is
         when "101" =>
            p_v.tsel := T_ROT33;
            p_v.csel := C_WIN;
            p_v.k    := rot33_k(op, m33_v);

         when "110" | "111" =>
            p_v.tsel := T_ROT32;
            if op(3) = '0' then
               p_v.k    := 32 - n5_v;
               p_v.csel := C_ROTL when to_c else C_ZERO;
            else
               p_v.k    := n5_v;
               p_v.csel := C_ROTR when to_c else C_ZERO;
            end if;

         when others =>
            case op(2 downto 0) is
               when "001" | "100" => p_v.fsel := FILL_1;   -- 0<1, C<1
               when "010"         => p_v.fsel := FILL_C;   -- 0<C
               when others        => p_v.fsel := FILL_0;   -- 0<0, C<0
            end case;
            if op(3) = '0' then
               p_v.tsel := T_LFILL;
               p_v.k    := 33 - p_v.sat;
               p_v.csel := C_WIN when to_c else C_ZERO;
            else
               p_v.tsel := T_RFILL;
               p_v.k    := p_v.sat;
               p_v.csel := C_RIGHT when to_c else C_ZERO;
            end if;
      end case;
      return p_v;
   end function shift_prep;

   function shift_fast(s0 : std_logic_vector(31 downto 0);
                       c  : std_logic;
                       p  : t_shift_prep) return t_result is
      variable fill_v : std_logic;
      variable t_v    : std_logic_vector(65 downto 0);
      variable v_v    : std_logic_vector(65 downto 0);
      variable res_v  : t_result;
   begin
      case p.fsel is
         when FILL_1 => fill_v := '1';
         when FILL_C => fill_v := c;
         when others => fill_v := '0';
      end case;

      case p.tsel is
         when T_LFILL => t_v := c & s0 & (32 downto 0 => fill_v);
         when T_RFILL => t_v := (65 downto 32 => fill_v) & s0;
         when T_ROT33 => t_v := c & s0 & c & s0;
         when T_ROT32 => t_v := "00" & s0 & s0;
      end case;
      v_v := t_v srl p.k;

      res_v.r := v_v(31 downto 0);
      res_v.v := '0';
      case p.csel is
         when C_WIN =>
            res_v.c := v_v(32);
         when C_RIGHT =>
            if p.sat = 0 then
               res_v.c := c;
            elsif p.sat = 33 then
               res_v.c := fill_v;
            else
               res_v.c := s0(p.sat - 1);
            end if;
         when C_ROTL =>
            res_v.c := res_v.r(0) when p.nz = '1' else c;
         when C_ROTR =>
            res_v.c := res_v.r(31) when p.nz = '1' else c;
         when others =>
            res_v.c := '0';
      end case;
      return res_v;
   end function shift_fast;

   function flags(sr  : std_logic_vector(31 downto 0);
                  res : t_result) return std_logic_vector is
      variable sr_v : std_logic_vector(31 downto 0);
   begin
      sr_v         := sr and not C_FLAG_MASK;
      sr_v(C_SR_X) := and res.r;
      sr_v(C_SR_Z) := nor res.r;
      sr_v(C_SR_N) := res.r(31);
      sr_v(C_SR_C) := res.c;
      sr_v(C_SR_V) := res.v;
      return sr_v;
   end function flags;

end package body nice_pkg;
