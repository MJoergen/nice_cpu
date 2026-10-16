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
-- The shifter reduces its count as MICROARCH.md §7.3 describes.

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

   -- ISA.md §5.2. c is the C flag. The carry of the result is the C flag
   -- after the shift, before M is applied.
   function shift(op : std_logic_vector(3 downto 0);
                  s0 : std_logic_vector(31 downto 0);
                  n  : std_logic_vector(31 downto 0);
                  c  : std_logic) return t_result;

   -- SR after an instruction with M = 1 and result res (ISA.md §6).
   function flags(sr  : std_logic_vector(31 downto 0);
                  res : t_result) return std_logic_vector;

end package nice_pkg;

package body nice_pkg is

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
      if iw(27 downto 26) /= "11" then
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

   function add(a   : std_logic_vector(31 downto 0);
                b   : std_logic_vector(31 downto 0);
                cin : std_logic) return t_result is
      variable sum_v : std_logic_vector(32 downto 0);
      variable res_v : t_result;
   begin
      sum_v   := ('0' & a) + ('0' & b) + cin;
      res_v.r := sum_v(31 downto 0);
      res_v.c := sum_v(32);
      res_v.v := (a(31) xor res_v.r(31)) and (b(31) xor res_v.r(31));
      return res_v;
   end function add;

   function sub(a   : std_logic_vector(31 downto 0);
                b   : std_logic_vector(31 downto 0);
                cin : std_logic) return t_result is
      variable diff_v : std_logic_vector(32 downto 0);
      variable res_v  : t_result;
   begin
      diff_v  := ('0' & a) - ('0' & b) - cin;
      res_v.r := diff_v(31 downto 0);
      res_v.c := diff_v(32);                  -- The borrow
      res_v.v := (a(31) xor b(31)) and (a(31) xor res_v.r(31));
      return res_v;
   end function sub;

   function alu(op  : std_logic_vector(3 downto 0);
                s0  : std_logic_vector(31 downto 0);
                s1  : std_logic_vector(31 downto 0);
                cin : std_logic) return t_result is
      variable res_v : t_result := (r => (others => '0'), c => '0', v => '0');
   begin
      case op is
         when "0000" => res_v.r := s0;
         when "0001" => res_v   := sub(s0, s1, cin);
         when "0010" => res_v   := add(s0, s0 and s1, cin);
         when "0011" => res_v   := add(s0, s1, cin);
         when "0100" => res_v   := add(s0, s0, cin);
         when "0101" => res_v   := sub(s0, X"00000001", '0');
         when "0110" => res_v.r := not s0;
         when "0111" => res_v.r := not (s0 or s1);
         when "1000" => res_v.r := (not s0) and s1;
         when "1001" => res_v.r := not (s0 and s1);
         when "1010" => res_v.r := s0 xor s1;
         when "1011" => res_v.r := (not s0) or s1;
         when "1100" => res_v.r := not (s0 xor s1);
         when "1101" => res_v.r := s0 and s1;
         when "1110" => res_v.r := X"00000001";
         when others => res_v.r := s0 or s1;
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

   -- n mod 33, as in doc/MICROARCH.md §7.3: 32 = -1 (mod 33), so the 5-bit
   -- digits of n count with alternating signs. 99 keeps the sum positive.
   function mod33(n : std_logic_vector(31 downto 0)) return natural is
      variable sum_v : integer range 0 to 255;
   begin
      sum_v := 99 + to_integer(n(4 downto 0)) - to_integer(n(9 downto 5)) +
               to_integer(n(14 downto 10)) - to_integer(n(19 downto 15)) +
               to_integer(n(24 downto 20)) - to_integer(n(29 downto 25)) +
               to_integer(n(31 downto 30));

      for i in 1 to 5 loop
         if sum_v >= 33 then
            sum_v := sum_v - 33;
         end if;
      end loop;

      return sum_v;
   end function mod33;

   -- A right shift is the mirror image of the left shift of the same kind,
   -- so s0 is reversed before and the result after.
   function shift(op : std_logic_vector(3 downto 0);
                  s0 : std_logic_vector(31 downto 0);
                  n  : std_logic_vector(31 downto 0);
                  c  : std_logic) return t_result is
      variable d_v     : std_logic_vector(31 downto 0);
      variable fill_v  : std_logic;
      variable fills_v : std_logic_vector(32 downto 0);
      variable wide_v  : std_logic_vector(65 downto 0);   -- c, d, 33 fill bits
      variable rot_v   : std_logic_vector(32 downto 0);   -- c, d
      variable m_v     : natural range 0 to 33;           -- The reduced count
      variable res_v   : t_result := (r => (others => '0'), c => c, v => '0');
   begin
      d_v := reverse(s0) when op(3) = '1' else s0;

      case op(2 downto 0) is
         when "101" =>
            -- C<C, C>C: a 33-bit rotation of C and d
            m_v     := mod33(n);
            rot_v   := ((c & d_v) sll m_v) or ((c & d_v) srl (33 - m_v));
            res_v.r := rot_v(31 downto 0);
            res_v.c := rot_v(32);

         when "110" | "111" =>
            -- <<<, C<<, >>>, >>C: a 32-bit rotation. C gets the bit rotated
            -- last.
            res_v.r := d_v rol to_integer(n(4 downto 0));
            if n /= 0 then
               res_v.c := res_v.r(0);
            end if;

         when others =>
            -- A fixed fill. After 33 steps, nothing changes any more.
            case op(2 downto 0) is
               when "001" | "100" => fill_v := '1';   -- 0<1, C<1
               when "010"         => fill_v := c;     -- 0<C
               when others        => fill_v := '0';   -- 0<0, C<0
            end case;
            m_v     := 33 when n > 33 else to_integer(n(5 downto 0));
            fills_v := (others => fill_v);
            wide_v  := (c & d_v & fills_v) sll m_v;
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
