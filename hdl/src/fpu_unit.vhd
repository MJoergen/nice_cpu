-- The arithmetic unit of the FPU of SYSTEM.md §11: one operation of
-- src/fpu_pkg.vhd at a time, on values of an IEEE 754 binary format with
-- G_EBITS bits of exponent and G_FBITS of fraction, binary64 in the FPU.
-- The widths are generics so that tb_fpu_unit can check every pair of
-- values of a small format against emulator/test/fpu_model.py.
--
-- THEORY OF OPERATION
-- The unit unpacks its operands into a sign, an exponent, and a
-- significand of P = G_FBITS + 1 bits whose top bit is 1, which takes a
-- cycle per operand, and a few more for a subnormal one, whose fraction is
-- shifted left until its top bit is 1. The special operands, NaNs,
-- infinities, and zeros, give their results at once, as the model's
-- cases do.
--
-- A finite result is formed in the accumulator ACC of N bits, N at least
-- P + 4, with the exponent E of its top bit. It need not be exact: the
-- bits that a step drops are ORed into bit 0 of ACC, the sticky bit, which
-- is far enough below the bit that the rounding looks at, the guard bit,
-- that no later shift of one bit brings it there. A shift of more than one
-- bit to the left happens only to an exact value. Then ACC is normalized,
-- shifted left until its top bit is 1, and rounded. Each shift moves 16,
-- 4, or 1 bit in a cycle, so that a shifter is a row of 4:1 multiplexers,
-- and a shift of k bits takes at most 3 + 3 + 3 cycles for k < 64.
--
-- The rounding takes a grid: the main format, the short format, binary32
-- in the FPU, or the whole numbers. A result below the smallest normal
-- exponent of the grid is first shifted right to it, which makes it a
-- subnormal, or on the grid of the whole numbers puts the units in the
-- last place kept. Then P bits, or the short format's precision, are kept,
-- and the guard bit and the sticky bits decide the increment.
--
-- * ADD and SUB shift the significand of the smaller operand right by the
--   difference of the exponents, then add or subtract.
-- * MUL multiplies the significands G_CHUNK bits of B at a time, a product
--   of P by G_CHUNK bits in each cycle, registered before it is added, so
--   that synthesis can map it to DSP blocks. Of the 2P bits of the product,
--   the top N go to ACC and the rest to the sticky bit.
-- * MULERR is SCALE10's fma(A, B, -p), where p is the product rounded. If
--   the exact product is in the normal range, p drops its low P bits, and
--   the error is those bits, or their distance to the next unit if p was
--   rounded up, exact in P bits, which are then rounded. Below the normal
--   range the error is less than half the smallest subnormal, so it rounds
--   to a zero, whose sign is that of the error: the rounding of the product
--   tells it.
-- * DIV is a restoring division, a bit of the quotient in each cycle, P + 2
--   bits, with a remainder that is not 0 in the sticky bit.
-- * SQRT takes the root of the significand, shifted left by 1 if the
--   exponent is odd, 2 bits of it in each of P + 1 steps, with the
--   remainder in the sticky bit, which rounds as the exact root does.
-- * FMOD subtracts the significand of B from that of A, shifted, for each
--   bit of the difference of their exponents, as long division does, and
--   keeps the remainder, which is exact.
-- * INTEGRAL rounds on the grid of the whole numbers, and rounds the
--   result again, exactly, in the main format.
-- * The conversions to an integer shift the significand right until the
--   units are in bit 0, without a sticky bit, and saturate.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) START is high for one cycle, while BUSY is low. The operands, the
--    operation, the rounding mode, and K are taken in that cycle.
-- b) G_EBITS >= 3, G_FBITS >= 2, and the short format is no wider than the
--    main one in either field.
--
-- RESET
-- Reset ends an operation. DONE stays low, and BUSY goes low.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

library work;
   use work.fpu_pkg.all;

entity fpu_unit is
   generic (
      G_EBITS  : natural := 11;
      G_FBITS  : natural := 52;
      G_SEBITS : natural := 8;
      G_SFBITS : natural := 23;
      G_CHUNK  : natural := 17
   );
   port (
      clk_i    : in  std_logic;
      rst_i    : in  std_logic;

      start_i  : in  std_logic;
      op_i     : in  t_fpu_op;
      rnd_i    : in  t_fpu_rnd;
      a_i      : in  std_logic_vector(G_EBITS + G_FBITS downto 0);
      b_i      : in  std_logic_vector(G_EBITS + G_FBITS downto 0);
      k_i      : in  std_logic_vector(15 downto 0);

      busy_o   : out std_logic;
      done_o   : out std_logic;
      result_o : out std_logic_vector(G_EBITS + G_FBITS downto 0);
      flags_o  : out std_logic_vector(2 downto 0)
   );
end entity fpu_unit;

architecture synthesis of fpu_unit is

   constant C_W    : natural := 1 + G_EBITS + G_FBITS;
   constant C_F    : natural := G_FBITS;
   constant C_P    : natural := G_FBITS + 1;
   constant C_BIAS : integer := 2 ** (G_EBITS - 1) - 1;
   constant C_EMIN : integer := 1 - C_BIAS;
   constant C_EMAX : integer := C_BIAS;

   constant C_SW    : natural := 1 + G_SEBITS + G_SFBITS;
   constant C_SP    : natural := G_SFBITS + 1;
   constant C_SBIAS : integer := 2 ** (G_SEBITS - 1) - 1;
   constant C_SEMIN : integer := 1 - C_SBIAS;
   constant C_SEMAX : integer := C_SBIAS;

   -- The width of ACC, and of the integers of OP_ITOF and the like, which
   -- are C_W bits wide.
   constant C_N   : natural := maximum(C_W, C_P + 4);
   constant C_EW  : natural := G_EBITS + 4;
   constant C_NCH : natural := (C_P + G_CHUNK - 1) / G_CHUNK;

   -- The longest shift of a cycle: 16 bits, or 4 in a narrow unit.
   constant C_S3 : natural := 16 * boolean'pos(C_N >= 32) + 4 * boolean'pos(C_N < 32);

   subtype t_exp is signed(C_EW - 1 downto 0);

   subtype t_acc is unsigned(C_N - 1 downto 0);

   subtype t_sig is unsigned(C_P - 1 downto 0);

   -- An operand, unpacked. M has the top bit set unless the value is a zero
   -- or a subnormal one, whose top bits are 0.
   type t_unp is record
      s    : std_logic;
      e    : t_exp;
      m    : t_sig;
      zero : std_logic;
      inf  : std_logic;
      nan  : std_logic;
      snan : std_logic;
   end record t_unp;

   -- The grid of the rounding.
   type t_grid is (GRID_MAIN, GRID_SHORT, GRID_WHOLE);

   type t_state is (
      IDLE_ST, LOAD_ST, NORMA_ST, NORMB_ST, DISPATCH_ST, ALIGN_ST, SUM_ST, MUL_ST, MUL_FIN_ST,
      DIV_ST, SQRT_ST, FMOD_ST, TOINT_ST, NORM_ST, DENORM_ST, ROUND_ST, DONE_ST
   );

   function bool_to_sl(b : boolean) return std_logic is
   begin
      if b then
         return '1';
      end if;
      return '0';
   end function bool_to_sl;

   -- The value a, of a format of ebits and fbits, unpacked, with its
   -- significand at the top of the P bits.
   function unpack(a     : std_logic_vector;
                   ebits : natural;
                   fbits : natural) return t_unp is
      constant C_B   : integer := 2 ** (ebits - 1) - 1;
      variable res_v : t_unp;
      variable exp_v : unsigned(ebits - 1 downto 0);
      variable frc_v : unsigned(fbits - 1 downto 0);
   begin
      exp_v      := unsigned(a(ebits + fbits - 1 downto fbits));
      frc_v      := unsigned(a(fbits - 1 downto 0));
      res_v.s    := a(ebits + fbits);
      res_v.e    := to_signed(1 - C_B, C_EW);
      res_v.m    := (others => '0');
      res_v.zero := '0';
      res_v.inf  := '0';
      res_v.nan  := '0';
      res_v.snan := '0';
      res_v.m(C_P - 2 downto C_P - 1 - fbits) := frc_v;
      if exp_v = 0 then
         if frc_v = 0 then
            res_v.zero := '1';
         end if;
      elsif exp_v = (exp_v'range => '1') then
         if frc_v = 0 then
            res_v.inf := '1';
         else
            res_v.nan  := '1';
            res_v.snan := not frc_v(fbits - 1);
         end if;
      else
         res_v.e          := to_signed(to_integer(exp_v) - C_B, C_EW);
         res_v.m(C_P - 1) := '1';
      end if;
      return res_v;
   end function unpack;

   -- The packed values of the main format.
   function pack(s     : std_logic;
                 bexp  : natural;
                 frac  : unsigned) return std_logic_vector is
      variable res_v : std_logic_vector(C_W - 1 downto 0);
   begin
      res_v(C_W - 1)                := s;
      res_v(C_W - 2 downto C_F)     := std_logic_vector(to_unsigned(bexp, G_EBITS));
      res_v(C_F - 1 downto 0)       := std_logic_vector(frac(C_F - 1 downto 0));
      return res_v;
   end function pack;

   function inf_of(s : std_logic) return std_logic_vector is
   begin
      return pack(s, 2 ** G_EBITS - 1, to_unsigned(0, C_F));
   end function inf_of;

   function zero_of(s : std_logic) return std_logic_vector is
   begin
      return pack(s, 0, to_unsigned(0, C_F));
   end function zero_of;

   -- The canonical NaN: the quiet bit only, and the sign 0.
   function qnan return std_logic_vector is
   begin
      return pack('0', 2 ** G_EBITS - 1, shift_left(to_unsigned(1, C_F), C_F - 1));
   end function qnan;

   constant C_QNAN : std_logic_vector(C_W - 1 downto 0) := qnan;

   -- The same in the short format, in the low bits.
   function short_of(s    : std_logic;
                     bexp : natural;
                     frac : unsigned) return std_logic_vector is
      variable res_v : std_logic_vector(C_W - 1 downto 0) := (others => '0');
   begin
      res_v(C_SW - 1)                   := s;
      res_v(C_SW - 2 downto G_SFBITS)   := std_logic_vector(to_unsigned(bexp, G_SEBITS));
      res_v(G_SFBITS - 1 downto 0)      := std_logic_vector(frac(G_SFBITS - 1 downto 0));
      return res_v;
   end function short_of;

   function short_qnan return std_logic_vector is
   begin
      return short_of('0', 2 ** G_SEBITS - 1, shift_left(to_unsigned(1, G_SFBITS), G_SFBITS - 1));
   end function short_qnan;

   constant C_SQNAN : std_logic_vector(C_W - 1 downto 0) := short_qnan;

   -- Whether the operation has a second operand.
   function has_b(op : t_fpu_op) return boolean is
   begin
      return op = OP_ADD or op = OP_SUB or op = OP_MUL or op = OP_MULERR or op = OP_DIV or
             op = OP_FMOD;
   end function has_b;

   -- Whether the top k bits of v are all 0.
   function top_zero(v : unsigned;
                     k : natural) return boolean is
   begin
      return v(v'high downto v'high - k + 1) = 0;
   end function top_zero;

   -- v shifted right by k < v'length, with the bits shifted out ORed into
   -- bit 0 if jam is '1'.
   function shr_jam(v   : unsigned;
                    k   : natural;
                    jam : std_logic) return unsigned is
      variable res_v : unsigned(v'range);
   begin
      res_v := shift_right(v, k);
      if jam = '1' and k > 0 and v(v'low + k - 1 downto v'low) /= 0 then
         res_v(v'low) := '1';
      end if;
      return res_v;
   end function shr_jam;

   -- One step of a right shift by d bits: the step, and v shifted by it.
   procedure shr_step(v     : inout unsigned;
                      d     : in    integer;
                      jam   : in    std_logic;
                      step  : out   natural) is
   begin
      if d >= v'length then
         if jam = '1' and v /= 0 then
            v := to_unsigned(1, v'length);
         else
            v := to_unsigned(0, v'length);
         end if;
         step := d;
      elsif d >= C_S3 then
         v    := shr_jam(v, C_S3, jam);
         step := C_S3;
      elsif d >= 4 then
         v    := shr_jam(v, 4, jam);
         step := 4;
      else
         v    := shr_jam(v, 1, jam);
         step := 1;
      end if;
   end procedure shr_step;

   -- One step of a left shift that brings the top bit of v, which is not 0,
   -- to the top.
   procedure shl_step(v    : inout unsigned;
                      step : out   natural) is
   begin
      if v'length > C_S3 and top_zero(v, C_S3) then
         v    := shift_left(v, C_S3);
         step := C_S3;
      elsif v'length > 4 and top_zero(v, 4) then
         v    := shift_left(v, 4);
         step := 4;
      else
         v    := shift_left(v, 1);
         step := 1;
      end if;
   end procedure shl_step;

   signal state_r : t_state := IDLE_ST;
   signal op_r    : t_fpu_op;
   signal rnd_r   : t_fpu_rnd;
   signal a_r     : std_logic_vector(C_W - 1 downto 0);
   signal b_r     : std_logic_vector(C_W - 1 downto 0);
   signal k_r     : signed(15 downto 0);

   -- The unpacked operands.
   signal sa_r : std_logic;
   signal ea_r : t_exp;
   signal ma_r : t_sig;
   signal sb_r : std_logic;
   signal eb_r : t_exp;
   signal mb_r : t_sig;

   -- The result being formed: its sign, the exponent of the top bit of ACC,
   -- ACC, and the second addend of ADD.
   signal s_r   : std_logic;
   signal e_r   : t_exp;
   signal acc_r : t_acc;
   signal opb_r : t_acc;
   signal amt_r : integer range 0 to 2 ** C_EW;
   signal sub_r : std_logic;

   -- The grid and the mode of the rounding, whether the result is then
   -- MULERR's zero, and the sign of the product for it.
   signal grid_r   : t_grid;
   signal mode_r   : t_fpu_rnd;
   signal zerr_r   : std_logic;
   signal prod_s_r : std_logic;

   -- The multiplier: the step, the product of the step before, the high
   -- part of the sum so far, and the bits below it.
   signal cnt_r : integer range 0 to 2 ** C_EW;
   signal pp_r  : unsigned(C_P + G_CHUNK - 1 downto 0);
   signal hi_r  : unsigned(C_P - 1 downto 0);
   signal lo_r  : unsigned(G_CHUNK * C_NCH - 1 downto 0);

   -- The divider, the root, and FMOD: the remainder, the quotient or the
   -- root, and the bits of the radicand still to take.
   signal rem_r : unsigned(C_P + 3 downto 0);
   signal quo_r : unsigned(C_P + 1 downto 0);
   signal rad_r : unsigned(C_P downto 0);

   signal res_r   : std_logic_vector(C_W - 1 downto 0) := (others => '0');
   signal flags_r : std_logic_vector(2 downto 0)       := (others => '0');
   signal done_r  : std_logic                          := '0';

begin

   busy_o   <= '0' when state_r = IDLE_ST else '1';
   done_o   <= done_r;
   result_o <= res_r;
   flags_o  <= flags_r;


   p_fsm : process (clk_i)
      variable ua_v    : t_unp;
      variable ub_v    : t_unp;
      variable ms_v    : t_sig;
      variable step_v  : natural;
      variable acc_v   : t_acc;
      variable opb_v   : t_acc;
      variable sum_v   : unsigned(C_N downto 0);
      variable t_v     : unsigned(C_P + G_CHUNK downto 0);
      variable prod_v  : unsigned(2 * C_P - 1 downto 0);
      variable wide_v  : unsigned(2 * C_P + C_N - 1 downto 0);
      variable low_v   : unsigned(C_P downto 0);
      variable up_v    : std_logic;
      variable en_v    : integer;
      variable tr_v    : unsigned(C_P + 3 downto 0);
      variable prec_v  : natural;
      variable emin_v  : integer;
      variable kept_v  : unsigned(C_P downto 0);
      variable guard_v : std_logic;
      variable stk_v   : std_logic;
      variable inc_v   : std_logic;
      variable e2_v    : integer;
      variable m_v     : unsigned(C_N - 1 downto 0);
      variable bits_v  : natural;
      variable lim_v   : unsigned(C_N downto 0);
      variable int_v   : signed(C_N downto 0);
   begin
      if rising_edge(clk_i) then
         done_r <= '0';

         case state_r is

            when IDLE_ST =>
               if start_i = '1' then
                  op_r    <= op_i;
                  rnd_r   <= rnd_i;
                  a_r     <= a_i;
                  b_r     <= b_i;
                  k_r     <= signed(k_i);
                  flags_r <= (others => '0');
                  zerr_r  <= '0';
                  grid_r  <= GRID_MAIN;
                  mode_r  <= RND_EVEN;
                  state_r <= LOAD_ST;
               end if;

            -- The special operands, and the unpacked ones.
            when LOAD_ST =>
               if op_r = OP_FROMSHORT then
                  ua_v := unpack(a_r(C_SW - 1 downto 0), G_SEBITS, G_SFBITS);
               else
                  ua_v := unpack(a_r, G_EBITS, G_FBITS);
               end if;
               ub_v := unpack(b_r, G_EBITS, G_FBITS);
               if op_r = OP_SUB then
                  ub_v.s := not ub_v.s;
               end if;
               sa_r    <= ua_v.s;
               ea_r    <= ua_v.e;
               ma_r    <= ua_v.m;
               sb_r    <= ub_v.s;
               eb_r    <= ub_v.e;
               mb_r    <= ub_v.m;
               state_r <= NORMA_ST;

               case op_r is

                  when OP_ADD | OP_SUB =>
                     if ua_v.nan = '1' or ub_v.nan = '1' then
                        res_r                  <= C_QNAN;
                        flags_r(C_FL_INVALID)  <= ua_v.snan or ub_v.snan;
                        state_r                <= DONE_ST;
                     elsif ua_v.inf = '1' and ub_v.inf = '1' and ua_v.s /= ub_v.s then
                        res_r                  <= C_QNAN;
                        flags_r(C_FL_INVALID)  <= '1';
                        state_r                <= DONE_ST;
                     elsif ua_v.inf = '1' then
                        res_r   <= inf_of(ua_v.s);
                        state_r <= DONE_ST;
                     elsif ub_v.inf = '1' then
                        res_r   <= inf_of(ub_v.s);
                        state_r <= DONE_ST;
                     elsif ua_v.zero = '1' and ub_v.zero = '1' then
                        res_r   <= zero_of(ua_v.s and ub_v.s);
                        state_r <= DONE_ST;
                     elsif ua_v.zero = '1' then
                        res_r   <= ub_v.s & b_r(C_W - 2 downto 0);
                        state_r <= DONE_ST;
                     elsif ub_v.zero = '1' then
                        res_r   <= a_r;
                        state_r <= DONE_ST;
                     end if;

                  when OP_MUL | OP_MULERR =>
                     if ua_v.nan = '1' or ub_v.nan = '1' then
                        res_r                 <= C_QNAN;
                        flags_r(C_FL_INVALID) <= ua_v.snan or ub_v.snan;
                        state_r               <= DONE_ST;
                     elsif op_r = OP_MULERR and (ua_v.zero = '1' or ub_v.zero = '1') then
                        res_r   <= zero_of('0');
                        state_r <= DONE_ST;
                     elsif ua_v.inf = '1' or ub_v.inf = '1' then
                        if ua_v.zero = '1' or ub_v.zero = '1' then
                           res_r                 <= C_QNAN;
                           flags_r(C_FL_INVALID) <= '1';
                        else
                           res_r <= inf_of(ua_v.s xor ub_v.s);
                        end if;
                        state_r <= DONE_ST;
                     elsif ua_v.zero = '1' or ub_v.zero = '1' then
                        res_r   <= zero_of(ua_v.s xor ub_v.s);
                        state_r <= DONE_ST;
                     end if;

                  when OP_DIV =>
                     if ua_v.nan = '1' or ub_v.nan = '1' then
                        res_r                 <= C_QNAN;
                        flags_r(C_FL_INVALID) <= ua_v.snan or ub_v.snan;
                        state_r               <= DONE_ST;
                     elsif ua_v.inf = '1' then
                        if ub_v.inf = '1' then
                           res_r                 <= C_QNAN;
                           flags_r(C_FL_INVALID) <= '1';
                        else
                           res_r <= inf_of(ua_v.s xor ub_v.s);
                        end if;
                        state_r <= DONE_ST;
                     elsif ub_v.inf = '1' then
                        res_r   <= zero_of(ua_v.s xor ub_v.s);
                        state_r <= DONE_ST;
                     elsif ub_v.zero = '1' then
                        if ua_v.zero = '1' then
                           res_r                 <= C_QNAN;
                           flags_r(C_FL_INVALID) <= '1';
                        else
                           res_r                 <= inf_of(ua_v.s xor ub_v.s);
                           flags_r(C_FL_DIVZERO) <= '1';
                        end if;
                        state_r <= DONE_ST;
                     elsif ua_v.zero = '1' then
                        res_r   <= zero_of(ua_v.s xor ub_v.s);
                        state_r <= DONE_ST;
                     end if;

                  when OP_SQRT =>
                     if ua_v.nan = '1' then
                        res_r                 <= C_QNAN;
                        flags_r(C_FL_INVALID) <= ua_v.snan;
                        state_r               <= DONE_ST;
                     elsif ua_v.zero = '1' then
                        res_r   <= a_r;
                        state_r <= DONE_ST;
                     elsif ua_v.s = '1' then
                        res_r                 <= C_QNAN;
                        flags_r(C_FL_INVALID) <= '1';
                        state_r               <= DONE_ST;
                     elsif ua_v.inf = '1' then
                        res_r   <= a_r;
                        state_r <= DONE_ST;
                     end if;

                  when OP_FMOD =>
                     if ua_v.nan = '1' or ub_v.nan = '1' then
                        res_r                 <= C_QNAN;
                        flags_r(C_FL_INVALID) <= ua_v.snan or ub_v.snan;
                        state_r               <= DONE_ST;
                     elsif ua_v.inf = '1' or ub_v.zero = '1' then
                        res_r                 <= C_QNAN;
                        flags_r(C_FL_INVALID) <= '1';
                        state_r               <= DONE_ST;
                     elsif ub_v.inf = '1' or ua_v.zero = '1' then
                        res_r   <= a_r;
                        state_r <= DONE_ST;
                     end if;

                  when OP_TOSHORT =>
                     if ua_v.nan = '1' then
                        res_r                 <= C_SQNAN;
                        flags_r(C_FL_INVALID) <= ua_v.snan;
                        state_r               <= DONE_ST;
                     elsif ua_v.inf = '1' then
                        res_r   <= short_of(ua_v.s, 2 ** G_SEBITS - 1, to_unsigned(0, G_SFBITS));
                        state_r <= DONE_ST;
                     elsif ua_v.zero = '1' then
                        res_r   <= short_of(ua_v.s, 0, to_unsigned(0, G_SFBITS));
                        state_r <= DONE_ST;
                     end if;

                  when OP_FROMSHORT =>
                     if ua_v.nan = '1' then
                        res_r                 <= C_QNAN;
                        flags_r(C_FL_INVALID) <= ua_v.snan;
                        state_r               <= DONE_ST;
                     elsif ua_v.inf = '1' then
                        res_r   <= inf_of(ua_v.s);
                        state_r <= DONE_ST;
                     elsif ua_v.zero = '1' then
                        res_r   <= zero_of(ua_v.s);
                        state_r <= DONE_ST;
                     end if;

                  when OP_INTEGRAL | OP_SCALE2 | OP_GETMANT | OP_GETEXP =>
                     if ua_v.nan = '1' then
                        res_r                 <= C_QNAN;
                        flags_r(C_FL_INVALID) <= ua_v.snan;
                        state_r               <= DONE_ST;
                     elsif op_r = OP_GETEXP and ua_v.zero = '1' then
                        res_r                 <= inf_of('1');
                        flags_r(C_FL_DIVZERO) <= '1';
                        state_r               <= DONE_ST;
                     elsif op_r = OP_GETEXP and ua_v.inf = '1' then
                        res_r   <= inf_of('0');
                        state_r <= DONE_ST;
                     elsif ua_v.inf = '1' or ua_v.zero = '1' then
                        res_r   <= a_r;
                        state_r <= DONE_ST;
                     end if;

                  when OP_FTOI | OP_FTOU | OP_FTOW =>
                     if ua_v.nan = '1' or ua_v.inf = '1' then
                        -- 0 for a NaN, and an infinity saturates as a large
                        -- value does, in TOINT_ST.
                        res_r                 <= (others => '0');
                        flags_r(C_FL_INVALID) <= '1';
                        if ua_v.inf = '1' then
                           ea_r <= to_signed(C_N, C_EW);
                           ma_r <= shift_left(to_unsigned(1, C_P), C_P - 1);
                           state_r <= DISPATCH_ST;
                        else
                           state_r <= DONE_ST;
                        end if;
                     elsif ua_v.zero = '1' then
                        res_r   <= (others => '0');
                        state_r <= DONE_ST;
                     end if;

                  when OP_ITOF | OP_UTOF =>
                     if unsigned(a_r) = 0 then
                        res_r   <= zero_of('0');
                        state_r <= DONE_ST;
                     else
                        -- The magnitude, which for the smallest integer is the
                        -- negation that wraps, read as unsigned.
                        acc_v := resize(unsigned(a_r), C_N);
                        s_r   <= '0';
                        if op_r = OP_ITOF and a_r(C_W - 1) = '1' then
                           acc_v := resize(unsigned(-signed(a_r)), C_N);
                           s_r   <= '1';
                        end if;
                        acc_r   <= acc_v;
                        e_r     <= to_signed(C_N - 1, C_EW);
                        state_r <= NORM_ST;
                     end if;

                  when OP_ILOGB =>
                     null;

               end case;

            -- A subnormal operand: its significand shifted left until the
            -- top bit is 1.
            when NORMA_ST =>
               if ma_r(C_P - 1) = '1' or ma_r = 0 then
                  state_r <= NORMB_ST;
               else
                  ms_v := ma_r;
                  shl_step(ms_v, step_v);
                  ma_r <= ms_v;
                  ea_r <= ea_r - step_v;
               end if;

            when NORMB_ST =>
               if mb_r(C_P - 1) = '1' or mb_r = 0 or not has_b(op_r) then
                  state_r <= DISPATCH_ST;
               else
                  ms_v := mb_r;
                  shl_step(ms_v, step_v);
                  mb_r <= ms_v;
                  eb_r <= eb_r - step_v;
               end if;

            when DISPATCH_ST =>
               acc_v := (others => '0');
               acc_v(C_N - 1 downto C_N - C_P) := ma_r;
               acc_r <= acc_v;
               e_r   <= ea_r;
               s_r   <= sa_r;

               case op_r is

                  when OP_ADD | OP_SUB =>
                     -- ACC gets the operand of the larger magnitude.
                     opb_v := (others => '0');
                     if ea_r > eb_r or (ea_r = eb_r and ma_r >= mb_r) then
                        opb_v(C_N - 1 downto C_N - C_P) := mb_r;
                        amt_r <= to_integer(ea_r - eb_r);
                     else
                        acc_v(C_N - 1 downto C_N - C_P) := mb_r;
                        opb_v(C_N - 1 downto C_N - C_P) := ma_r;
                        acc_r <= acc_v;
                        e_r   <= eb_r;
                        s_r   <= sb_r;
                        amt_r <= to_integer(eb_r - ea_r);
                     end if;
                     opb_r   <= opb_v;
                     sub_r   <= sa_r xor sb_r;
                     state_r <= ALIGN_ST;

                  when OP_MUL | OP_MULERR =>
                     cnt_r   <= 0;
                     hi_r    <= (others => '0');
                     lo_r    <= (others => '0');
                     state_r <= MUL_ST;

                  when OP_DIV =>
                     rem_r   <= resize(ma_r, C_P + 4);
                     quo_r   <= (others => '0');
                     cnt_r   <= C_P + 2;
                     state_r <= DIV_ST;

                  when OP_SQRT =>
                     -- The radicand has two bits above the point: the
                     -- significand, shifted left by 1 if the exponent is odd.
                     if ea_r(0) = '1' then
                        rad_r <= ma_r & '0';
                     else
                        rad_r <= '0' & ma_r;
                     end if;
                     rem_r   <= (others => '0');
                     quo_r   <= (others => '0');
                     e_r     <= shift_right(ea_r, 1);
                     cnt_r   <= C_P + 1;
                     mode_r  <= rnd_r;
                     state_r <= SQRT_ST;

                  when OP_FMOD =>
                     if ea_r < eb_r then
                        res_r   <= a_r;
                        state_r <= DONE_ST;
                     else
                        rem_r   <= resize(ma_r, C_P + 4);
                        cnt_r   <= to_integer(ea_r - eb_r);
                        state_r <= FMOD_ST;
                     end if;

                  when OP_TOSHORT =>
                     grid_r  <= GRID_SHORT;
                     state_r <= NORM_ST;

                  when OP_FROMSHORT | OP_GETMANT =>
                     if op_r = OP_GETMANT then
                        e_r <= (others => '0');
                     end if;
                     state_r <= NORM_ST;

                  when OP_SCALE2 =>
                     e_r     <= ea_r + resize(k_r, C_EW);
                     state_r <= NORM_ST;

                  when OP_INTEGRAL =>
                     if ea_r >= C_F then
                        res_r   <= a_r;
                        state_r <= DONE_ST;
                     else
                        grid_r  <= GRID_WHOLE;
                        mode_r  <= rnd_r;
                        state_r <= NORM_ST;
                     end if;

                  when OP_GETEXP =>
                     if ea_r = 0 then
                        res_r   <= zero_of('0');
                        state_r <= DONE_ST;
                     else
                        acc_r   <= resize(unsigned(abs(ea_r)), C_N);
                        s_r     <= ea_r(C_EW - 1);
                        e_r     <= to_signed(C_N - 1, C_EW);
                        state_r <= NORM_ST;
                     end if;

                  when OP_ILOGB =>
                     res_r   <= std_logic_vector(resize(ea_r, C_W));
                     state_r <= DONE_ST;

                  when OP_FTOI | OP_FTOU | OP_FTOW =>
                     -- The units of the integer go to bit 0 of ACC.
                     if ea_r < 0 then
                        acc_r   <= (others => '0');
                        amt_r   <= 0;
                        state_r <= TOINT_ST;
                     elsif ea_r >= C_W then
                        -- Out of range of every width: all ones saturates.
                        amt_r                 <= 0;
                        acc_r                 <= (others => '1');
                        flags_r(C_FL_INVALID) <= '1';
                        state_r               <= TOINT_ST;
                     else
                        amt_r   <= C_N - 1 - to_integer(ea_r);
                        state_r <= TOINT_ST;
                     end if;

                  when OP_ITOF | OP_UTOF =>
                     null;

               end case;

            -- ADD: the smaller operand shifted right to the exponent of the
            -- larger.
            when ALIGN_ST =>
               if amt_r = 0 then
                  state_r <= SUM_ST;
               else
                  opb_v := opb_r;
                  shr_step(opb_v, amt_r, '1', step_v);
                  opb_r <= opb_v;
                  amt_r <= amt_r - step_v;
               end if;

            when SUM_ST =>
               if sub_r = '1' then
                  acc_v := acc_r - opb_r;
                  acc_r <= acc_v;
                  if acc_v = 0 then
                     -- x - x is +0 when rounding to nearest.
                     res_r   <= zero_of('0');
                     state_r <= DONE_ST;
                  else
                     state_r <= NORM_ST;
                  end if;
               else
                  sum_v := ('0' & acc_r) + ('0' & opb_r);
                  if sum_v(C_N) = '1' then
                     acc_r    <= sum_v(C_N downto 1);
                     acc_r(0) <= sum_v(1) or sum_v(0);
                     e_r      <= e_r + 1;
                  else
                     acc_r <= sum_v(C_N - 1 downto 0);
                  end if;
                  state_r <= NORM_ST;
               end if;

            -- MUL: in step i, the product of A and chunk i of B, from the
            -- low end, is registered, and the product of step i - 1 is
            -- added to the sum.
            when MUL_ST =>
               if cnt_r < C_NCH then
                  pp_r <= ma_r * resize(shift_right(mb_r, G_CHUNK * cnt_r), G_CHUNK);
               end if;
               if cnt_r > 0 then
                  t_v  := ('0' & resize(hi_r, C_P + G_CHUNK)) + ('0' & pp_r);
                  hi_r <= resize(shift_right(t_v, G_CHUNK), C_P);
                  lo_r <= t_v(G_CHUNK - 1 downto 0) & lo_r(lo_r'high downto G_CHUNK);
               end if;
               if cnt_r = C_NCH then
                  state_r <= MUL_FIN_ST;
               end if;
               cnt_r <= cnt_r + 1;

            when MUL_FIN_ST =>
               wide_v := resize(hi_r & lo_r, 2 * C_P + C_N);
               prod_v := wide_v(2 * C_P - 1 downto 0);
               s_r    <= sa_r xor sb_r;
               prod_s_r <= sa_r xor sb_r;
               -- The product normalized, with the exponent of its top bit.
               if prod_v(2 * C_P - 1) = '0' then
                  prod_v := shift_left(prod_v, 1);
                  en_v   := to_integer(ea_r + eb_r);
               else
                  en_v := to_integer(ea_r + eb_r) + 1;
               end if;
               if op_r = OP_MULERR and en_v >= C_EMIN then
                  low_v := resize(prod_v(C_P - 1 downto 0), C_P + 1);
                  up_v  := prod_v(C_P - 1) and
                           (prod_v(C_P) or bool_to_sl(prod_v(C_P - 2 downto 0) /= 0));
                  if up_v = '1' then
                     low_v := shift_left(to_unsigned(1, C_P + 1), C_P) - low_v;
                  end if;
                  if low_v = 0 then
                     res_r   <= zero_of('0');
                     state_r <= DONE_ST;
                  else
                     acc_v := (others => '0');
                     acc_v(C_N - 1 downto C_N - C_P) := low_v(C_P - 1 downto 0);
                     acc_r   <= acc_v;
                     e_r     <= to_signed(en_v - C_P, C_EW);
                     s_r     <= sa_r xor sb_r xor up_v;
                     state_r <= NORM_ST;
                  end if;
               else
                  wide_v := prod_v & to_unsigned(0, C_N);
                  acc_v  := wide_v(2 * C_P + C_N - 1 downto 2 * C_P);
                  if wide_v(2 * C_P - 1 downto 0) /= 0 then
                     acc_v(0) := '1';
                  end if;
                  acc_r   <= acc_v;
                  e_r     <= to_signed(en_v, C_EW);
                  zerr_r  <= bool_to_sl(op_r = OP_MULERR);
                  state_r <= NORM_ST;
               end if;

            -- DIV: P + 2 bits of the quotient of the significands, which is
            -- between 1/2 and 2, so that P + 1 of them are significant.
            when DIV_ST =>
               if cnt_r = 0 then
                  acc_v := (others => '0');
                  acc_v(C_N - 1 downto C_N - C_P - 2) := quo_r;
                  if rem_r /= 0 then
                     acc_v(0) := '1';
                  end if;
                  acc_r   <= acc_v;
                  e_r     <= ea_r - eb_r;
                  s_r     <= sa_r xor sb_r;
                  state_r <= NORM_ST;
               else
                  if rem_r >= mb_r then
                     rem_r <= shift_left(rem_r - mb_r, 1);
                     quo_r <= quo_r(C_P downto 0) & '1';
                  else
                     rem_r <= shift_left(rem_r, 1);
                     quo_r <= quo_r(C_P downto 0) & '0';
                  end if;
                  cnt_r <= cnt_r - 1;
               end if;

            -- SQRT: P + 1 bits of the root, the first of them 1, as the
            -- radicand is at least 1.
            when SQRT_ST =>
               if cnt_r = 0 then
                  acc_v := (others => '0');
                  acc_v(C_N - 1 downto C_N - C_P - 1) := quo_r(C_P downto 0);
                  if rem_r /= 0 then
                     acc_v(0) := '1';
                  end if;
                  acc_r   <= acc_v;
                  state_r <= NORM_ST;
               else
                  tr_v  := shift_left(rem_r, 2) + resize(rad_r(C_P downto C_P - 1), C_P + 4);
                  rad_r <= shift_left(rad_r, 2);
                  if tr_v >= shift_left(resize(quo_r, C_P + 4), 2) + 1 then
                     rem_r <= tr_v - (shift_left(resize(quo_r, C_P + 4), 2) + 1);
                     quo_r <= quo_r(C_P downto 0) & '1';
                  else
                     rem_r <= tr_v;
                     quo_r <= quo_r(C_P downto 0) & '0';
                  end if;
                  cnt_r <= cnt_r - 1;
               end if;

            -- FMOD: long division of the significands, which keeps only the
            -- remainder, for each bit of the difference of the exponents.
            when FMOD_ST =>
               if cnt_r = 0 then
                  if rem_r >= mb_r then
                     tr_v := rem_r - mb_r;
                  else
                     tr_v := rem_r;
                  end if;
                  if tr_v = 0 then
                     res_r   <= zero_of(sa_r);
                     state_r <= DONE_ST;
                  else
                     acc_v := (others => '0');
                     acc_v(C_N - 1 downto C_N - C_P) := tr_v(C_P - 1 downto 0);
                     acc_r   <= acc_v;
                     e_r     <= eb_r;
                     state_r <= NORM_ST;
                  end if;
               else
                  if rem_r >= mb_r then
                     rem_r <= shift_left(rem_r - mb_r, 1);
                  else
                     rem_r <= shift_left(rem_r, 1);
                  end if;
                  cnt_r <= cnt_r - 1;
               end if;

            -- A conversion to an integer: ACC shifted right until its units
            -- are in bit 0, then saturated.
            when TOINT_ST =>
               if amt_r /= 0 then
                  acc_v := acc_r;
                  shr_step(acc_v, amt_r, '0', step_v);
                  acc_r <= acc_v;
                  amt_r <= amt_r - step_v;
               else
                  if op_r = OP_FTOW then
                     bits_v := C_W / 2;
                  else
                     bits_v := C_W;
                  end if;
                  m_v := acc_r;
                  -- The largest magnitude for the sign.
                  if op_r = OP_FTOU then
                     if sa_r = '1' then
                        lim_v := (others => '0');
                     else
                        lim_v := shift_left(to_unsigned(1, C_N + 1), bits_v) - 1;
                     end if;
                  elsif sa_r = '1' then
                     lim_v := shift_left(to_unsigned(1, C_N + 1), bits_v - 1);
                  else
                     lim_v := shift_left(to_unsigned(1, C_N + 1), bits_v - 1) - 1;
                  end if;
                  if ('0' & m_v) > lim_v then
                     m_v                   := lim_v(C_N - 1 downto 0);
                     flags_r(C_FL_INVALID) <= '1';
                  end if;
                  int_v := signed('0' & m_v);
                  if sa_r = '1' then
                     int_v := -int_v;
                  end if;
                  res_r   <= std_logic_vector(int_v(C_W - 1 downto 0));
                  state_r <= DONE_ST;
               end if;

            when NORM_ST =>
               if acc_r(C_N - 1) = '1' or acc_r = 0 then
                  state_r <= DENORM_ST;
               else
                  acc_v := acc_r;
                  shl_step(acc_v, step_v);
                  acc_r <= acc_v;
                  e_r   <= e_r - step_v;
               end if;

            -- A value below the smallest normal exponent of the grid is
            -- shifted right to it.
            when DENORM_ST =>
               case grid_r is
                  when GRID_MAIN  => emin_v := C_EMIN;
                  when GRID_SHORT => emin_v := C_SEMIN;
                  when GRID_WHOLE => emin_v := C_F;
               end case;
               if acc_r /= 0 and e_r < emin_v then
                  acc_v := acc_r;
                  shr_step(acc_v, emin_v - to_integer(e_r), '1', step_v);
                  acc_r <= acc_v;
                  e_r   <= e_r + step_v;
               else
                  state_r <= ROUND_ST;
               end if;

            when ROUND_ST =>
               if grid_r = GRID_SHORT then
                  prec_v := C_SP;
               else
                  prec_v := C_P;
               end if;
               kept_v  := resize(shift_right(acc_r, C_N - prec_v), C_P + 1);
               guard_v := acc_r(C_N - prec_v - 1);
               acc_v   := shift_left(acc_r, prec_v + 1);
               stk_v   := bool_to_sl(acc_v /= 0);
               case mode_r is
                  when RND_EVEN  => inc_v := guard_v and (stk_v or kept_v(0));
                  when RND_TRUNC => inc_v := '0';
                  when RND_FLOOR => inc_v := (guard_v or stk_v) and s_r;
                  when RND_CEIL  => inc_v := (guard_v or stk_v) and not s_r;
                  when RND_AWAY  => inc_v := guard_v;
               end case;
               if inc_v = '1' then
                  kept_v := kept_v + 1;
               end if;
               e2_v   := to_integer(e_r);
               if kept_v(prec_v) = '1' then
                  kept_v := shift_right(kept_v, 1);
                  e2_v   := e2_v + 1;
               end if;
               state_r <= DONE_ST;

               case grid_r is

                  when GRID_WHOLE =>
                     -- The whole number, rounded again in the main format,
                     -- which is exact.
                     if kept_v = 0 then
                        res_r <= zero_of(s_r);
                     else
                        acc_v := (others => '0');
                        acc_v(C_N - 1 downto C_N - C_P) := kept_v(C_P - 1 downto 0);
                        acc_r   <= acc_v;
                        e_r     <= to_signed(e2_v, C_EW);
                        grid_r  <= GRID_MAIN;
                        mode_r  <= RND_EVEN;
                        state_r <= NORM_ST;
                     end if;

                  when GRID_MAIN =>
                     if e2_v > C_EMAX then
                        if mode_r = RND_TRUNC then
                           res_r <= pack(s_r, 2 ** G_EBITS - 2, (C_F - 1 downto 0 => '1'));
                        else
                           res_r                  <= inf_of(s_r);
                           flags_r(C_FL_OVERFLOW) <= '1';
                        end if;
                     elsif kept_v(C_P - 1) = '1' then
                        res_r <= pack(s_r, e2_v + C_BIAS, kept_v);
                     else
                        res_r <= pack(s_r, 0, kept_v);
                     end if;
                     if zerr_r = '1' then
                        -- MULERR below the normal range: a zero with the sign
                        -- of the error, which is that of the product if it
                        -- was rounded down, or the other if up.
                        res_r <= zero_of((guard_v or stk_v) and (prod_s_r xor inc_v));
                     end if;

                  when GRID_SHORT =>
                     if e2_v > C_SEMAX then
                        res_r <= short_of(s_r, 2 ** G_SEBITS - 1, to_unsigned(0, G_SFBITS));
                        flags_r(C_FL_OVERFLOW) <= '1';
                     elsif kept_v(C_SP - 1) = '1' then
                        res_r <= short_of(s_r, e2_v + C_SBIAS, kept_v);
                     else
                        res_r <= short_of(s_r, 0, kept_v);
                     end if;

               end case;

            when DONE_ST =>
               done_r  <= '1';
               state_r <= IDLE_ST;

         end case;

         if rst_i = '1' then
            state_r <= IDLE_ST;
            done_r  <= '0';
         end if;
      end if;
   end process p_fsm;

end architecture synthesis;

