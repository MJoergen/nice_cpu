-- A self-checking test of the ALU and the shifter in src/nice_pkg.vhd.
--
-- THEORY OF OPERATION
-- The pipelined core computes a shift from a prepared count, shift_prep
-- and shift_fast, where the multi-cycle core reduces the count in the
-- shift itself. The ALU of both cores shares one adder. This test checks:
-- * shift_fast of shift_prep gives what shift gives, for every operation,
--   with every count from 0 to 70, with counts near the multiples of 33 up
--   to 1353, near 2^31 and 2^32, and at each power of two, and with random
--   counts and values.
-- * The ALU gives what the operations of ISA.md §5.1 give, written here as
--   plain arithmetic and logic with no shared adder.
-- The run stops with status 0 when every check passes, and 1 at the first
-- that fails.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;
   use ieee.math_real.all;

   use std.env.all;

   use work.nice_pkg.all;

entity tb_shift is
end entity tb_shift;

architecture simulation of tb_shift is

   -- ISA.md §5.1, each operation on its own.
   function alu_ref(op  : std_logic_vector(3 downto 0);
                    s0  : std_logic_vector(31 downto 0);
                    s1  : std_logic_vector(31 downto 0);
                    cin : std_logic) return t_result is
      variable a_v   : std_logic_vector(32 downto 0);
      variable b_v   : std_logic_vector(32 downto 0);
      variable r_v   : std_logic_vector(32 downto 0);
      variable res_v : t_result := (r => (others => '0'), c => '0', v => '0');
   begin
      a_v := '0' & s0;
      case op is
         when "0001" =>
            b_v     := '0' & s1;
            r_v     := a_v - b_v - cin;
            res_v.v := (s0(31) xor s1(31)) and (s0(31) xor r_v(31));
         when "0010" =>
            b_v     := '0' & (s0 and s1);
            r_v     := a_v + b_v + cin;
            res_v.v := (s0(31) xor r_v(31)) and (b_v(31) xor r_v(31));
         when "0011" =>
            b_v     := '0' & s1;
            r_v     := a_v + b_v + cin;
            res_v.v := (s0(31) xor r_v(31)) and (s1(31) xor r_v(31));
         when "0100" =>
            b_v     := '0' & s0;
            r_v     := a_v + b_v + cin;
            res_v.v := (s0(31) xor r_v(31)) and (s0(31) xor r_v(31));
         when "0101" =>
            b_v     := '0' & X"00000001";
            r_v     := a_v - b_v;
            res_v.v := s0(31) and (s0(31) xor r_v(31));
         when others =>
            r_v := (others => '0');
      end case;
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
            res_v.r := r_v(31 downto 0);
            res_v.c := r_v(32);
      end case;
      return res_v;
   end function alu_ref;

begin

   p_test : process
      variable seed1_v : positive := 1;
      variable seed2_v : positive := 7;
      variable r_v     : real;
      variable op_v    : std_logic_vector(3 downto 0);
      variable s0_v    : std_logic_vector(31 downto 0);
      variable s1_v    : std_logic_vector(31 downto 0);
      variable c_v     : std_logic;
      variable ref_v   : t_result;
      variable got_v   : t_result;
      variable checks  : natural := 0;

      impure function random32 return std_logic_vector is
         variable res_v : std_logic_vector(31 downto 0);
      begin
         for i in 0 to 3 loop
            uniform(seed1_v, seed2_v, r_v);
            res_v(8 * i + 7 downto 8 * i) := to_stdlogicvector(integer(floor(r_v * 256.0)), 8);
         end loop;
         return res_v;
      end function random32;

      procedure check_shift(op : std_logic_vector(3 downto 0);
                            s0 : std_logic_vector(31 downto 0);
                            n  : std_logic_vector(31 downto 0);
                            c  : std_logic) is
      begin
         ref_v  := shift(op, s0, n, c);
         got_v  := shift_fast(s0, c, shift_prep(op, n));
         checks := checks + 1;
         if got_v.r /= ref_v.r or got_v.c /= ref_v.c then
            report "tb_shift: shift op " & to_string(op) & " s0 " & to_hstring(s0) &
                   " n " & to_hstring(n) & " c " & to_string(c) &
                   ": got " & to_hstring(got_v.r) & " C " & to_string(got_v.c) &
                   ", expected " & to_hstring(ref_v.r) & " C " & to_string(ref_v.c)
               severity failure;
         end if;
      end procedure check_shift;

      procedure check_alu(op  : std_logic_vector(3 downto 0);
                          s0  : std_logic_vector(31 downto 0);
                          s1  : std_logic_vector(31 downto 0);
                          cin : std_logic) is
      begin
         ref_v  := alu_ref(op, s0, s1, cin);
         got_v  := alu(op, s0, s1, cin);
         checks := checks + 1;
         if got_v /= ref_v then
            report "tb_shift: alu op " & to_string(op) & " s0 " & to_hstring(s0) &
                   " s1 " & to_hstring(s1) & " cin " & to_string(cin) &
                   ": got " & to_hstring(got_v.r) & " C " & to_string(got_v.c) &
                   " V " & to_string(got_v.v) &
                   ", expected " & to_hstring(ref_v.r) & " C " & to_string(ref_v.c) &
                   " V " & to_string(ref_v.v)
               severity failure;
         end if;
      end procedure check_alu;

   begin
      -- Every shift with every small count, and the counts near the
      -- multiples of 33, with a few values of s0 and both values of C.
      for op in 0 to 15 loop
         op_v := to_stdlogicvector(op, 4);
         for k in 0 to 7 loop
            case k is
               when 0      => s0_v := X"00000000";
               when 1      => s0_v := X"FFFFFFFF";
               when 2      => s0_v := X"80000001";
               when 3      => s0_v := X"12345678";
               when others => s0_v := random32;
            end case;
            for c in 0 to 1 loop
               c_v := '1' when c = 1 else '0';
               for n in 0 to 70 loop
                  check_shift(op_v, s0_v, to_stdlogicvector(n, 32), c_v);
               end loop;
               for m in 1 to 41 loop
                  for d in -1 to 1 loop
                     check_shift(op_v, s0_v, to_stdlogicvector(33 * m + d, 32), c_v);
                  end loop;
               end loop;
               for i in 0 to 31 loop
                  check_shift(op_v, s0_v, X"FFFFFFFF" - i, c_v);
                  check_shift(op_v, s0_v, X"80000000" + i, c_v);
                  s1_v    := (others => '0');
                  s1_v(i) := '1';
                  check_shift(op_v, s0_v, s1_v, c_v);
               end loop;
               for i in 0 to 199 loop
                  check_shift(op_v, s0_v, random32, c_v);
               end loop;
            end loop;
         end loop;
      end loop;

      -- Every operation of the ALU on random operands, and on the edges.
      for op in 0 to 15 loop
         op_v := to_stdlogicvector(op, 4);
         for c in 0 to 1 loop
            c_v := '1' when c = 1 else '0';
            for i in 0 to 4 loop
               for j in 0 to 4 loop
                  case i is
                     when 0      => s0_v := X"00000000";
                     when 1      => s0_v := X"FFFFFFFF";
                     when 2      => s0_v := X"80000000";
                     when 3      => s0_v := X"7FFFFFFF";
                     when others => s0_v := X"00000001";
                  end case;
                  case j is
                     when 0      => s1_v := X"00000000";
                     when 1      => s1_v := X"FFFFFFFF";
                     when 2      => s1_v := X"80000000";
                     when 3      => s1_v := X"7FFFFFFF";
                     when others => s1_v := X"00000001";
                  end case;
                  check_alu(op_v, s0_v, s1_v, c_v);
               end loop;
            end loop;
            for i in 0 to 1999 loop
               check_alu(op_v, random32, random32, c_v);
            end loop;
         end loop;
      end loop;

      report "tb_shift: all " & integer'image(checks) & " checks passed";
      stop(0);
   end process p_test;

end architecture simulation;
