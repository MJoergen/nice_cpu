-- The functions that both cores share, src/nice_pkg.vhd, and the block
-- compares of src/pipe_pkg.vhd, checked against ISA.md and MICROARCH.md
-- for every input, for SymbiYosys.
--
-- THEORY OF OPERATION
-- The functions are combinational, so every input is free in every cycle,
-- and a proof of depth 1 covers every value. The assertions:
-- * The shift of ISA.md §5.2, written as the loop that "repeats n times",
--   run for n up to C_LOOP, gives what shift gives (f_loop). Beyond that,
--   shift gives for n what it gives for a smaller count that the loop
--   would give the same for: 33 for a fixed fill, where nothing changes
--   after 33 steps (f_fill); n - 32 for a 32-bit rotation (f_rot32); and
--   n - 33 for a rotation through C (f_rot33), which checks the digit sum
--   of mod33. So shift follows §5.2 for every count, by descent, since the
--   closed forms of §5.2 say the same of the loop.
-- * shift_fast of shift_prep, the shifter of the pipelined core, gives
--   what shift gives (f_fast), also when WRITE prepares the count in two
--   steps, without the count mod 33 and then with it, as src/pipe_write.vhd
--   does for a count it must reduce itself (f_late).
-- * The ALU with its one adder gives what the operations of ISA.md §5.1
--   give, written out one by one with the carry and overflow rules of
--   that section (f_alu), and flags sets the five flags of ISA.md §6 and
--   nothing else (f_flags).
-- * The block compares of MICROARCH.md §5.5, which WRITE uses to find a
--   store into fetched code: a word within 16 of FETCH's oldest word lies
--   in the block of that word, in the block after the one that word was in
--   a cycle ago, or in the one after that (f_near_fetch); and a word within
--   4 of an instruction's address lies in its block or the next
--   (f_near_inst). FETCH's oldest word moves by at most four words a cycle,
--   which pipe_fetch asserts (f_blk).
-- The covers show that the assertions see the large counts and the ends of
-- the ranges.
--
-- RESET
-- None: nothing here holds state.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use work.nice_pkg.all;
   use work.pipe_pkg.all;

entity formal_nice_pkg is
   port (
      clk_i  : in  std_logic;
      -- A shift
      op_i   : in  std_logic_vector(3 downto 0);
      s0_i   : in  std_logic_vector(31 downto 0);
      n_i    : in  std_logic_vector(31 downto 0);
      c_i    : in  std_logic;
      -- An ALU operation, and SR for the flags
      s1_i   : in  std_logic_vector(31 downto 0);
      cin_i  : in  std_logic;
      sr_i   : in  std_logic_vector(31 downto 0);
      -- A store's address, FETCH's oldest word and block, and an instruction
      a_i    : in  std_logic_vector(31 downto 0);
      head_i : in  std_logic_vector(31 downto 0);
      blk_i  : in  std_logic_vector(31 downto 5);
      addr_i : in  std_logic_vector(31 downto 0)
   );
end entity formal_nice_pkg;

architecture synthesis of formal_nice_pkg is

   -- The loop of ISA.md §5.2 is run for counts up to two rounds of the
   -- 33-bit rotation.
   constant C_LOOP : natural := 66;

   -- Only 011, 100, 101, and 111 send the bit shifted out to C.
   function to_c(op : std_logic_vector(3 downto 0)) return boolean is
   begin
      return op(2 downto 0) = "011" or op(2 downto 0) = "100" or
             op(2 downto 0) = "101" or op(2 downto 0) = "111";
   end function to_c;

   -- ISA.md §5.2, exactly as written: "Repeat n times", with the fill bit
   -- of the table, and C as the eight shifts that write it leave it, or 0.
   function shift_loop(op : std_logic_vector(3 downto 0);
                       s0 : std_logic_vector(31 downto 0);
                       n  : natural range 0 to C_LOOP;
                       c  : std_logic) return t_result is
      variable d_v    : std_logic_vector(31 downto 0) := s0;
      variable c_v    : std_logic                     := c;
      variable out_v  : std_logic;
      variable fill_v : std_logic;
      variable res_v  : t_result;
   begin
      for i in 1 to C_LOOP loop
         if i <= n then
            if op(3) = '1' then
               out_v := d_v(0);
            else
               out_v := d_v(31);
            end if;
            case op(2 downto 0) is
               when "000" | "011" => fill_v := '0';
               when "001" | "100" => fill_v := '1';
               when "010" | "101" => fill_v := c_v;
               when others        => fill_v := out_v;
            end case;
            if op(3) = '1' then
               d_v := fill_v & d_v(31 downto 1);
            else
               d_v := d_v(30 downto 0) & fill_v;
            end if;
            if to_c(op) then
               c_v := out_v;
            end if;
         end if;
      end loop;
      res_v.r := d_v;
      res_v.v := '0';
      if to_c(op) then
         res_v.c := c_v;
      else
         res_v.c := '0';
      end if;
      return res_v;
   end function shift_loop;

   -- ISA.md §5.1, each operation on its own, with 33-bit arithmetic for
   -- the carry and the borrow, and the sign rules for the overflow.
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
      r_v := (others => '0');
      case op is
         when "0001" =>
            -- SUB: s0 - s1 - cin, a borrow, and the overflow of a subtraction
            b_v     := '0' & s1;
            r_v     := a_v - b_v - cin;
            res_v.v := (s0(31) xor s1(31)) and (s0(31) xor r_v(31));
         when "0010" =>
            -- MDBL: s0 + (s0 AND s1) + cin
            b_v     := '0' & (s0 and s1);
            r_v     := a_v + b_v + cin;
            res_v.v := not (s0(31) xor b_v(31)) and (s0(31) xor r_v(31));
         when "0011" =>
            -- ADD: s0 + s1 + cin
            b_v     := '0' & s1;
            r_v     := a_v + b_v + cin;
            res_v.v := not (s0(31) xor s1(31)) and (s0(31) xor r_v(31));
         when "0100" =>
            -- DBL: s0 + s0 + cin
            b_v     := '0' & s0;
            r_v     := a_v + b_v + cin;
            res_v.v := s0(31) xor r_v(31);
         when "0101" =>
            -- DEC: s0 - 1, with V only for the most negative s0
            r_v     := a_v - 1;
            res_v.v := to_sl(s0 = X"80000000");
         when others =>
            null;
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

   signal n_small  : natural range 0 to 127;
   signal got      : t_result;
   signal ref_loop : t_result;
   signal got_fast : t_result;
   signal got_late : t_result;
   signal got_alu  : t_result;
   signal ref_alu  : t_result;
   signal got_sr   : std_logic_vector(31 downto 0);
   signal head_blk : std_logic_vector(31 downto 5);

begin

   n_small  <= to_integer(n_i(6 downto 0));
   got      <= shift(op_i, s0_i, n_i, c_i);
   ref_loop <= shift_loop(op_i, s0_i, minimum(n_small, C_LOOP), c_i);
   got_fast <= shift_fast(s0_i, c_i, shift_prep(op_i, n_i));
   got_alu  <= alu(op_i, s0_i, s1_i, cin_i);
   ref_alu  <= alu_ref(op_i, s0_i, s1_i, cin_i);
   got_sr   <= flags(sr_i, got_alu);
   head_blk <= head_i(31 downto 5);


   -- The count as WRITE prepares it in a cycle of its own: without the
   -- count mod 33 first, and then, for a rotation through C, from the
   -- digit sum.
   p_late : process (all)
      variable p_v : t_shift_prep;
   begin
      p_v := shift_prep(op_i, n_i, false);
      if op_i(2 downto 0) = "101" then
         p_v.k := rot33_k(op_i, mod33_of_sum(mod33_sum(n_i)));
      end if;
      got_late <= shift_fast(s0_i, c_i, p_v);
   end process p_late;


   -- psl default clock is rising_edge(clk_i);

   -- The shifter against ISA.md §5.2
   -- psl f_loop : assert always n_i <= C_LOOP -> got = ref_loop;
   -- psl f_fill : assert always (op_i(2) = '0' or op_i(1 downto 0) = "00") and n_i >= 33 ->
   --    got = shift(op_i, s0_i, X"00000021", c_i);
   -- psl f_rot32 : assert always (op_i(2 downto 1) = "11" and n_i >= 64) ->
   --    got = shift(op_i, s0_i, n_i - 32, c_i);
   -- psl f_rot33 : assert always (op_i(2 downto 0) = "101" and n_i >= 33) ->
   --    got = shift(op_i, s0_i, n_i - 33, c_i);

   -- The pipelined core's shifter against the multi-cycle core's
   -- psl f_fast : assert always got_fast = got;
   -- psl f_late : assert always got_late = got;

   -- The ALU against ISA.md §5.1, and the flags against §6
   -- psl f_alu : assert always got_alu = ref_alu;
   -- psl f_flags_x : assert always got_sr(C_SR_X) = to_sl(got_alu.r = X"FFFFFFFF");
   -- psl f_flags_z : assert always got_sr(C_SR_Z) = to_sl(got_alu.r = X"00000000");
   -- psl f_flags_n : assert always got_sr(C_SR_N) = got_alu.r(31);
   -- psl f_flags_c : assert always got_sr(C_SR_C) = got_alu.c;
   -- psl f_flags_v : assert always got_sr(C_SR_V) = got_alu.v;
   -- psl f_flags_rest : assert always
   --    (got_sr and not C_FLAG_MASK) = (sr_i and not C_FLAG_MASK);

   -- The block compares of MICROARCH.md §5.5
   -- psl f_near_fetch : assert always
   --    ((head_blk = blk_i or head_blk + 1 = blk_i) and a_i - head_i < 16) ->
   --    (near(a_i, head_i, blk_i, 5) or a_i(31 downto 5) = blk_i + 1);
   -- psl f_near_inst : assert always
   --    (a_i - addr_i < 4) -> near(a_i, addr_i, next_block(addr_i, 2), 2);

   -- psl c_rot33 : cover {op_i(2 downto 0) = "101" and n_i > C_LOOP};
   -- psl c_fill : cover {op_i(2 downto 0) = "000" and n_i(31) = '1'};
   -- psl c_rot32 : cover {op_i(2 downto 0) = "111" and n_i = 64};
   -- psl c_carry : cover {op_i = "0011" and got_alu.c = '1' and got_alu.v = '1'};
   -- psl c_fetch : cover {a_i - head_i = 15 and head_blk = blk_i and
   --    a_i(31 downto 5) = blk_i + 1};
   -- psl c_inst : cover {a_i - addr_i = 3 and a_i(31 downto 2) /= addr_i(31 downto 2)};

end architecture synthesis;
