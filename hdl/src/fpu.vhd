-- The floating-point unit, FPU, of SYSTEM.md §11: eight words of I/O
-- over a stack of up to 16 binary64 values, which a program pushes,
-- commands, and reads.
--
--   0  X_LO   2  X_S   4  CMD      6  REL
--   1  X_HI   3  X_W   5  STATUS   7  reads 0
--
-- THEORY OF OPERATION
-- The stack is a ring of 16 values with the index of X and the depth. A
-- push writes the slot after X, which on a full stack holds the deepest
-- value, so that the push drops it, as §11.4 asks. A missing operand reads
-- as the canonical NaN. Each cycle writes at most one slot, and reads
-- three, X, Y, and the copy of PICK, so that synthesis can map the ring to
-- distributed RAM.
--
-- A command pops its operands into registers, as §11.4 says, computes its
-- results, and pushes them, one in a cycle. The arithmetic is that of
-- src/fpu_unit.vhd, one operation at a time: a state starts an operation,
-- and UWAIT_ST waits for it and goes on to the state named in RET. The
-- sequences of SYSTEM.md §11.3 are chains of such states:
-- * ROUND32 rounds through the short format and back. The S bit is the
--   unit's input SHORT, which rounds the exact result once.
-- * ISQRT is SQRT toward zero, then INTEGRAL toward zero.
-- * SCALE2 and SCALE10 convert X with FTOI and clamp it. SCALE10 then
--   multiplies or divides by an exact power of ten, or multiplies pairs
--   of values by Dekker's steps, with MULERR for the error of a product.
-- * DIGITS takes the binary exponent with ILOGB, and from it the decimal
--   exponent e = ceil((E + 1) log10 2), which a 32-bit constant gives
--   exactly for every binary64 value. That e is the largest that can give
--   n digits, so the loop of the model, SCALE10, NEAREST, and a comparison
--   with 10^(n-1), lowering e until there are n digits, ends with the
--   model's e. The digits go to BCD by shifting and adding 3 to each digit
--   of 5 or more, then left to the top.
-- * FROMBCD multiplies by 10 and adds a digit, 16 times, then UTOF.
-- * The word operators convert their operands with FTOW, compute in 32
--   bits, IDIV and MOD with a restoring divider of the magnitudes, and
--   convert back with ITOF.
-- The class of X, REL, and the views X_LO and X_HI are logic on the stack,
-- read at once. X_S and X_W are operations of the unit: a read of them
-- waits for it.
--
-- The port is a pipelined Wishbone slave, as src/mpu.vhd is. A request is
-- acknowledged in the cycle after it is accepted, unless it is a read of
-- X_S or X_W, or arrives while a command runs. A command runs after its
-- write is acknowledged. A request accepted while it runs, but a read of
-- CMD, waits in a register with STALL high, so that no other is accepted,
-- and is served when the command ends. A read of X_S or X_W is
-- acknowledged when the unit ends, with STALL high until then. A write of
-- X_S or X_W is acknowledged at once, and its push, an operation of the
-- unit, runs as a command does.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) The master holds STB and the request while STALL is high.
-- b) STB is high only for requests to the FPU: the bus decoder decodes the
--    address. The FPU is at 0xFFFFFF88-0xFFFFFF8F, so the offset is
--    address bits 2..0.
--
-- FORMAL
-- With G_FORMAL, a free stand-in replaces the arithmetic unit: it ends an
-- operation in any cycle after its start, with any result and any flags,
-- and formal/formal_fpu.vhd proves the bus for every command. With
-- G_STACK too, the master writes only the commands of the stack and
-- neither X_S nor X_W, and the assertions below say that the stack is
-- that of a model of §11.4. The model shifts its values, X first. It
-- keeps each request it sees accepted, and applies it when the FPU takes
-- it: in IDLE_ST, at once or from the register where it waited. So it is
-- ahead only while a command runs. It must match whenever no command
-- runs: the depth, the flags, and each value. The invariants that make
-- that inductive say that the request that waits is the one the model
-- kept, which states a command of the stack passes through, and that
-- STALL is high exactly while a request waits or a read waits for the
-- unit.
--
-- RESET
-- Reset empties the stack, clears the flags, and ends a command.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

library work;
   use work.fpu_pkg.all;

entity fpu is
   generic (
      G_FORMAL : boolean := false;
      G_STACK  : boolean := false
   );
   port (
      clk_i      : in  std_logic;
      rst_i      : in  std_logic;

      wb_cyc_i   : in  std_logic;
      wb_stb_i   : in  std_logic;
      wb_stall_o : out std_logic;
      wb_ack_o   : out std_logic := '0';
      wb_we_i    : in  std_logic;
      wb_addr_i  : in  std_logic_vector(2 downto 0);
      wb_data_i  : in  std_logic_vector(31 downto 0);
      wb_data_o  : out std_logic_vector(31 downto 0) := (others => '0')
   );
end entity fpu;

architecture synthesis of fpu is

   subtype t_word64 is std_logic_vector(63 downto 0);

   type t_words64 is array (natural range <>) of t_word64;

   constant C_QNAN : t_word64 := X"7FF8000000000000";
   constant C_ONE  : t_word64 := X"3FF0000000000000";
   constant C_MONE : t_word64 := X"BFF0000000000000";

   -- The flags, bits 11..8 of STATUS.
   constant C_INVALID  : natural := 0;
   constant C_DIVZERO  : natural := 1;
   constant C_OVERFLOW : natural := 2;
   constant C_STACK    : natural := 3;

   -- ceil(log10 2 * 2^32): ceil((E + 1) * C_LOG10_2 / 2^32) is the smallest
   -- e with 10^e >= 2^(E + 1), for every E from -1074 to 1023.
   constant C_LOG10_2 : signed(31 downto 0) := to_signed(1292913987, 32);
   constant C_CEIL    : signed(47 downto 0) := shift_left(to_signed(1, 48), 32) - 1;

   -- CONST n, the binary64 value nearest each number of §11.3.
   constant C_CONSTS : t_words64(0 to 15) := (
      X"0000000000000000", -- 0
      X"3FF0000000000000", -- 1
      X"4024000000000000", -- 10
      X"400921FB54442D18", -- pi
      X"4005BF0A8B145769", -- e
      X"3FE62E42FEFA39EF", -- ln 2
      X"40026BB1BBB55516", -- ln 10
      X"3FD34413509F79FF", -- log10 2
      X"3FD45F306DC9C883", -- 1/pi
      X"3FB999999999999A", -- 1/10
      X"3FF921FB54442D18", -- pi/2
      X"401921FB54442D18", -- 2 pi
      X"3FF71547652B82FE", -- log2 e
      X"3FDBCB7B1526E50E", -- log10 e
      X"400A934F0979A371", -- log2 10
      X"3FF6A09E667F3BCD"  -- sqrt 2
   );

   -- 10^k for k from 0 to 22, each exact.
   constant C_TENS : t_words64(0 to 22) := (
      X"3FF0000000000000", -- 10^0
      X"4024000000000000", -- 10^1
      X"4059000000000000", -- 10^2
      X"408F400000000000", -- 10^3
      X"40C3880000000000", -- 10^4
      X"40F86A0000000000", -- 10^5
      X"412E848000000000", -- 10^6
      X"416312D000000000", -- 10^7
      X"4197D78400000000", -- 10^8
      X"41CDCD6500000000", -- 10^9
      X"4202A05F20000000", -- 10^10
      X"42374876E8000000", -- 10^11
      X"426D1A94A2000000", -- 10^12
      X"42A2309CE5400000", -- 10^13
      X"42D6BCC41E900000", -- 10^14
      X"430C6BF526340000", -- 10^15
      X"4341C37937E08000", -- 10^16
      X"4376345785D8A000", -- 10^17
      X"43ABC16D674EC800", -- 10^18
      X"43E158E460913D00", -- 10^19
      X"4415AF1D78B58C40", -- 10^20
      X"444B1AE4D6E2EF50", -- 10^21
      X"4480F0CF064DD592"  -- 10^22
   );

   -- The high parts of 10^(2^i), i from 0 to 8.
   constant C_TEN_HI : t_words64(0 to 8) := (
      X"4024000000000000", -- i = 0
      X"4059000000000000", -- i = 1
      X"40C3880000000000", -- i = 2
      X"4197D78400000000", -- i = 3
      X"4341C37937E08000", -- i = 4
      X"4693B8B5B5056E17", -- i = 5
      X"4D384F03E93FF9F5", -- i = 6
      X"5A827748F9301D32", -- i = 7
      X"75154FDD7F73BF3C"  -- i = 8
   );

   -- The high parts of 10^(-2^i), i from 0 to 8.
   constant C_TENTH_HI : t_words64(0 to 8) := (
      X"3FB999999999999A", -- i = 0
      X"3F847AE147AE147B", -- i = 1
      X"3F1A36E2EB1C432D", -- i = 2
      X"3E45798EE2308C3A", -- i = 3
      X"3C9CD2B297D889BC", -- i = 4
      X"3949F623D5A8A733", -- i = 5
      X"32A50FFD44F4A73D", -- i = 6
      X"255BBA08CF8C979D", -- i = 7
      X"0AC8062864AC6F43"  -- i = 8
   );

   -- The low parts of 10^(2^i), i from 0 to 8.
   constant C_TEN_LO : t_words64(0 to 8) := (
      X"0000000000000000", -- i = 0
      X"0000000000000000", -- i = 1
      X"0000000000000000", -- i = 2
      X"0000000000000000", -- i = 3
      X"0000000000000000", -- i = 4
      X"C333107F00000000", -- i = 5
      X"C9C2AC340948E389", -- i = 6
      X"D72901CC86649E4A", -- i = 7
      X"F1A7222446FE4670"  -- i = 8
   );

   -- The low parts of 10^(-2^i), i from 0 to 8.
   constant C_TENTH_LO : t_words64(0 to 8) := (
      X"BC5999999999999A", -- i = 0
      X"BC0EB851EB851EB8", -- i = 1
      X"BBB6A161E4F765FE", -- i = 2
      X"BAD03023DF2D4C94", -- i = 3
      X"3925B4C2EBE68799", -- i = 4
      X"B5EA2CC10F3892D4", -- i = 5
      X"2F3A53F2398D747B", -- i = 6
      X"A1FAFA9C1A60497D", -- i = 7
      X"07539FA911155FF0"  -- i = 8
   );

   type t_state is (
      IDLE_ST, UWAIT_ST, VIEW_ST, WPUSH_ST, CMD_ST, PUSH_ST, ARITH_ST, RESULT_ST, LONG_ST,
      ISQRT_ST, SCALE_ST, SCALE2_ST, SCALE10_ST, S10_ST, S10_SMALL_ST, S10_LOOP_ST,
      MP1_ST, MP2_ST, MP3_ST, MP4_ST, MP5_ST, MP6_ST, MP7_ST, MP8_ST, MP9_ST, MP10_ST,
      S10_FIN_ST, DIGITS_ST, DLOG_ST, DLOOP_ST, DSCALE_ST, DNEAR_ST, DINT_ST, BCD_ST,
      ALIGN_ST, DPUSH_ST, FROMBCD_ST, UTOF_ST, WORD_ST, WORDY_ST, WORDX_ST, IDIV_ST, WORD_END_ST
   );

   -- The stack.
   signal ram_r   : t_words64(0 to 15);
   signal top_r   : unsigned(3 downto 0)       := (others => '0');
   signal depth_r : natural range 0 to 16      := 0;
   signal flags_r : std_logic_vector(3 downto 0) := (others => '0');

   -- X, Y, and the copy of PICK, with the canonical NaN for a value that
   -- is not there.
   signal x_val : t_word64;
   signal y_val : t_word64;
   signal pick  : t_word64;

   -- The port: a request that waits, and STALL.
   signal accept      : std_logic;
   signal wait_r      : std_logic := '0';
   signal pend_r      : std_logic := '0';
   signal pend_we_r   : std_logic;
   signal pend_addr_r : std_logic_vector(2 downto 0);
   signal pend_data_r : std_logic_vector(31 downto 0);

   signal state_r : t_state := IDLE_ST;
   signal ret_r   : t_state := IDLE_ST;

   -- The command, its operands, and its results.
   signal num_r    : std_logic_vector(7 downto 0);
   signal n_r      : natural range 0 to 255;
   signal sbit_r   : std_logic;
   signal x_r      : t_word64;
   signal y_r      : t_word64;
   signal res_r    : t_word64;
   signal res2_r   : t_word64;
   signal npush_r  : natural range 0 to 2;
   signal cflags_r : std_logic_vector(2 downto 0);
   signal noovf_r  : std_logic;

   -- The arithmetic unit.
   signal u_start  : std_logic := '0';
   signal u_op     : t_fpu_op;
   signal u_rnd    : t_fpu_rnd;
   signal u_short  : std_logic;
   signal u_a      : t_word64;
   signal u_b      : t_word64;
   signal u_k      : std_logic_vector(15 downto 0);
   signal u_busy   : std_logic;
   signal u_done   : std_logic;
   signal u_result : t_word64;
   signal u_flags  : std_logic_vector(2 downto 0);

   -- SCALE10: Y, the count and its sign, the bit of the count, the pair
   -- r, the pair of the table, the steps of Dekker's product, and the
   -- state to go on with.
   signal s10_y_r   : t_word64;
   signal s10_neg_r : std_logic;
   signal s10_k_r   : unsigned(9 downto 0);
   signal s10_i_r   : natural range 0 to 11;
   signal s10_res_r : t_word64;
   signal s10_ret_r : t_state := SCALE10_ST;
   signal rh_r      : t_word64;
   signal rl_r      : t_word64;
   signal bh_r      : t_word64;
   signal bl_r      : t_word64;
   signal p_r       : t_word64;
   signal e_r       : t_word64;
   signal h_r       : t_word64;

   -- DIGITS: n, e, |X|, and the conversion to BCD.
   signal dexp_r : signed(15 downto 0);
   signal ax_r   : t_word64;
   signal bin_r  : unsigned(63 downto 0);
   signal bcd_r  : unsigned(63 downto 0);
   signal cnt_r  : natural range 0 to 63;

   -- The word operators, and FROMBCD's sum.
   signal wy_r  : signed(31 downto 0);
   signal wx_r  : signed(31 downto 0);
   signal dq_r  : unsigned(31 downto 0);
   signal dr_r  : unsigned(32 downto 0);
   signal sum_r : unsigned(63 downto 0);

   function bool_to_int(b : boolean) return natural is
   begin
      if b then
         return 1;
      end if;
      return 0;
   end function bool_to_int;

   function bool_to_sl(b : boolean) return std_logic is
   begin
      if b then
         return '1';
      end if;
      return '0';
   end function bool_to_sl;

   function f_exp(v : t_word64) return unsigned is
   begin
      return unsigned(v(62 downto 52));
   end function f_exp;

   function f_nan(v : t_word64) return boolean is
   begin
      return f_exp(v) = 2047 and unsigned(v(51 downto 0)) /= 0;
   end function f_nan;

   function f_snan(v : t_word64) return boolean is
   begin
      return f_nan(v) and v(51) = '0';
   end function f_snan;

   function f_inf(v : t_word64) return boolean is
   begin
      return f_exp(v) = 2047 and unsigned(v(51 downto 0)) = 0;
   end function f_inf;

   function f_zero(v : t_word64) return boolean is
   begin
      return unsigned(v(62 downto 0)) = 0;
   end function f_zero;

   -- Whether a binary32 value w is a binary64 value by moving its bits:
   -- a normal value, an infinity, or a zero. A NaN and a subnormal value
   -- go through the unit.
   function short_direct(w : std_logic_vector(31 downto 0)) return boolean is
   begin
      return (w(30 downto 23) /= X"00" and w(30 downto 23) /= X"FF") or
             unsigned(w(30 downto 0)) = 0 or
             (w(30 downto 23) = X"FF" and unsigned(w(22 downto 0)) = 0);
   end function short_direct;

   -- That binary64 value.
   function widen(w : std_logic_vector(31 downto 0)) return t_word64 is
   begin
      if unsigned(w(30 downto 0)) = 0 then
         return w(31) & (62 downto 0 => '0');
      elsif w(30 downto 23) = X"FF" then
         return w(31) & "11111111111" & (51 downto 0 => '0');
      end if;
      return w(31) & std_logic_vector(resize(unsigned(w(30 downto 23)), 11) + 896) &
             w(22 downto 0) & (28 downto 0 => '0');
   end function widen;

   -- Whether a binary64 value v is a binary32 value by moving its bits, the
   -- other way.
   function long_direct(v : t_word64) return boolean is
   begin
      return unsigned(v(62 downto 0)) = 0 or
             (f_exp(v) = 2047 and unsigned(v(51 downto 0)) = 0) or
             (f_exp(v) >= 897 and f_exp(v) <= 1150 and unsigned(v(28 downto 0)) = 0);
   end function long_direct;

   -- That binary32 value.
   function narrow(v : t_word64) return std_logic_vector is
   begin
      if unsigned(v(62 downto 0)) = 0 then
         return v(63) & (30 downto 0 => '0');
      elsif f_exp(v) = 2047 then
         return v(63) & X"FF" & (22 downto 0 => '0');
      end if;
      return v(63) & std_logic_vector(resize(f_exp(v) - 896, 8)) & v(51 downto 29);
   end function narrow;

   -- Y compared with X: -1, 0, or 1, and 2 if either is a NaN. -0 = +0.
   function f_cmp(y : t_word64;
                  x : t_word64) return integer is
      variable my_v : unsigned(62 downto 0);
      variable mx_v : unsigned(62 downto 0);
   begin
      if f_nan(y) or f_nan(x) then
         return 2;
      end if;
      my_v := unsigned(y(62 downto 0));
      mx_v := unsigned(x(62 downto 0));
      if my_v = 0 and mx_v = 0 then
         return 0;
      end if;
      if y(63) /= x(63) then
         if y(63) = '1' then
            return -1;
         end if;
         return 1;
      end if;
      if my_v = mx_v then
         return 0;
      end if;
      if (my_v < mx_v) = (y(63) = '0') then
         return -1;
      end if;
      return 1;
   end function f_cmp;

   -- Whether a finite v is whole: its fraction has as many trailing zeros
   -- as it has bits below the point.
   function f_whole(v : t_word64) return boolean is
      variable tz_v : natural range 0 to 52;
      variable e_v  : integer;
   begin
      if f_exp(v) = 2047 then
         return false;
      end if;
      if f_zero(v) then
         return true;
      end if;
      e_v := to_integer(f_exp(v)) - 1023;
      if e_v < 0 then
         return false;
      end if;
      tz_v := 52;
      for i in 51 downto 0 loop
         if v(i) = '1' then
            tz_v := i;
         end if;
      end loop;
      return tz_v + e_v >= 52;
   end function f_whole;

   -- Whether v, rounded toward zero, is a signed 32-bit integer.
   function f_fits(v : t_word64) return boolean is
      variable e_v : integer;
   begin
      if f_exp(v) = 2047 then
         return false;
      end if;
      e_v := to_integer(f_exp(v)) - 1023;
      if e_v < 31 then
         return true;
      end if;
      -- Only values from -2^31 down to above -2^31 - 1 have e = 31 and fit.
      return e_v = 31 and v(63) = '1' and unsigned(v(51 downto 21)) = 0;
   end function f_fits;

   -- The class of v, bits 21..16 of STATUS.
   function f_class(v : t_word64) return std_logic_vector is
      variable c_v : std_logic_vector(5 downto 0);
   begin
      c_v(0) := v(63);
      c_v(1) := bool_to_sl(f_zero(v));
      c_v(2) := bool_to_sl(f_inf(v));
      c_v(3) := bool_to_sl(f_nan(v));
      c_v(4) := bool_to_sl(f_whole(v));
      c_v(5) := bool_to_sl(f_fits(v));
      return c_v;
   end function f_class;

   -- The magnitude of a count of SCALE10, at most 1023.
   function magnitude(k : integer) return unsigned is
   begin
      if k < 0 then
         return to_unsigned(-k, 10);
      end if;
      return to_unsigned(k, 10);
   end function magnitude;

   -- The commands of §11.3: whether a number is one, the values it pops,
   -- the bits of n it uses, and whether S applies.
   type t_info is record
      valid : boolean;
      pops  : natural range 0 to 2;
      nmask : std_logic_vector(7 downto 0);
      s_ok  : boolean;
   end record t_info;

   function info(num : std_logic_vector(7 downto 0)) return t_info is
   begin
      case num is
         when X"00" | X"02" | X"05" =>
            return (true, 0, X"00", false);
         when X"01" =>
            return (true, 0, X"01", false);
         when X"03" | X"06" | X"30" =>
            return (true, 0, X"FF", false);
         when X"10" | X"11" | X"12" | X"13" =>
            return (true, 2, X"00", true);
         when X"14" =>
            return (true, 1, X"00", true);
         when X"04" | X"17" | X"18" | X"1D" | X"38" | X"39" |
              X"60" | X"61" | X"62" | X"64" | X"65" | X"66" | X"67" =>
            return (true, 2, X"00", false);
         when X"1C" =>
            return (true, 2, X"07", false);
         when X"3A" =>
            return (true, 1, X"FF", false);
         when X"15" | X"16" | X"19" | X"1A" | X"1B" | X"20" | X"21" | X"22" | X"23" | X"24" |
              X"28" | X"29" | X"2A" | X"2B" | X"3B" | X"3C" | X"3D" | X"63" =>
            return (true, 1, X"00", false);
         when others =>
            return (false, 0, X"00", false);
      end case;
   end function info;

begin

   accept     <= wb_cyc_i and wb_stb_i and not wait_r;
   wb_stall_o <= wait_r;

   x_val <= ram_r(to_integer(top_r)) when depth_r >= 1 else C_QNAN;
   y_val <= ram_r(to_integer(top_r - 1)) when depth_r >= 2 else C_QNAN;
   pick  <= ram_r(to_integer(top_r - n_r mod 16)) when n_r < depth_r else C_QNAN;


   gen_unit : if not G_FORMAL generate

      i_fpu_unit : entity work.fpu_unit
         port map (
            clk_i    => clk_i,
            rst_i    => rst_i,
            start_i  => u_start,
            op_i     => u_op,
            rnd_i    => u_rnd,
            short_i  => u_short,
            a_i      => u_a,
            b_i      => u_b,
            k_i      => u_k,
            busy_o   => u_busy,
            done_o   => u_done,
            result_o => u_result,
            flags_o  => u_flags
         ); -- i_fpu_unit

   end generate gen_unit;

   gen_formal : if G_FORMAL generate
      signal f_busy   : std_logic := '0';
      signal f_end    : std_logic;
      signal f_result : t_word64;
      signal f_flags  : std_logic_vector(2 downto 0);

      attribute anyseq : boolean;
      attribute anyseq of f_end    : signal is true;
      attribute anyseq of f_result : signal is true;
      attribute anyseq of f_flags  : signal is true;

      -- The model: the values, X first, the depth, and the flags.
      signal f_stk   : t_words64(0 to 15);
      signal f_dep   : natural range 0 to 16      := 0;
      signal f_flg   : std_logic_vector(3 downto 0) := (others => '0');
      signal f_req   : std_logic_vector(35 downto 0);   -- we, addr, data
      signal f_match : boolean;
      signal f_quiet : boolean;
      signal f_view  : boolean;
      signal f_cmd   : boolean;
   begin

      -- The stand-in for the unit.
      u_busy   <= f_busy;
      u_done   <= f_busy and f_end;
      u_result <= f_result;
      u_flags  <= f_flags;

      p_unit : process (clk_i)
      begin
         if rising_edge(clk_i) then
            if u_start = '1' then
               f_busy <= '1';
            elsif f_end = '1' then
               f_busy <= '0';
            end if;
            if rst_i = '1' then
               f_busy <= '0';
            end if;
         end if;
      end process p_unit;

      p_model : process (clk_i)
         variable stk_v : t_words64(0 to 15);
         variable dep_v : natural range 0 to 16;
         variable flg_v : std_logic_vector(3 downto 0);
         variable n_v   : natural range 0 to 255;
         variable x_v   : t_word64;
         variable y_v   : t_word64;
         variable req_v : std_logic_vector(35 downto 0);

         procedure mpush(v : t_word64) is
         begin
            stk_v := v & stk_v(0 to 14);
            if dep_v = 16 then
               flg_v(C_STACK) := '1';
            else
               dep_v := dep_v + 1;
            end if;
         end procedure mpush;

         procedure mpop(k : natural) is
         begin
            for i in 1 to 16 loop
               if i <= k then
                  stk_v := stk_v(1 to 15) & C_QNAN;
               end if;
            end loop;
            if k > dep_v then
               flg_v(C_STACK) := '1';
               dep_v          := 0;
            else
               dep_v := dep_v - k;
            end if;
         end procedure mpop;

         -- Value i, or the canonical NaN and the fault if it is missing.
         procedure mget(i : natural;
                        v : out t_word64) is
         begin
            v := C_QNAN;
            for j in 0 to 15 loop
               if j = i and j < dep_v then
                  v := stk_v(j);
               end if;
            end loop;
            if i >= dep_v then
               flg_v(C_STACK) := '1';
            end if;
         end procedure mget;

      begin
         if rising_edge(clk_i) then
            stk_v := f_stk;
            dep_v := f_dep;
            flg_v := f_flg;
            req_v := wb_we_i & wb_addr_i & wb_data_i;
            if pend_r = '1' then
               req_v := f_req;
            end if;
            n_v   := to_integer(unsigned(req_v(15 downto 8)));
            if state_r = IDLE_ST and (pend_r = '1' or accept = '1') and req_v(35) = '1' then
               case req_v(34 downto 32) is
                  when "000" =>
                     mpush(X"00000000" & req_v(31 downto 0));
                  when "001" =>
                     if dep_v = 0 then
                        flg_v(C_STACK) := '1';
                     else
                        stk_v(0)(63 downto 32) := req_v(31 downto 0);
                     end if;
                  when "101" =>
                     flg_v := req_v(11 downto 8);
                  when "100" =>
                     case req_v(7 downto 0) is
                        when X"00" =>
                           flg_v(C_INVALID) := flg_v(C_INVALID) or bool_to_sl(n_v /= 0);
                        when X"01" =>
                           if n_v > 1 then
                              flg_v(C_INVALID) := '1';
                           else
                              dep_v := 0;
                              if n_v = 1 then
                                 flg_v := (others => '0');
                              end if;
                           end if;
                        when X"02" | X"05" =>
                           if n_v /= 0 then
                              flg_v(C_INVALID) := '1';
                           else
                              mget(bool_to_int(req_v(2) = '1'), x_v);
                              mpush(x_v);
                           end if;
                        when X"03" =>
                           if n_v = 0 then
                              mpop(1);
                           else
                              mpop(n_v);
                           end if;
                        when X"04" =>
                           if n_v /= 0 then
                              flg_v(C_INVALID) := '1';
                           else
                              mget(0, x_v);
                              mget(1, y_v);
                              mpop(2);
                              -- The fault of a missing operand is mpop's.
                              mpush(x_v);
                              mpush(y_v);
                           end if;
                        when others =>
                           mget(n_v, x_v);
                           mpush(x_v);
                     end case;
                  when others =>
                     null;
               end case;
            end if;
            f_stk <= stk_v;
            f_dep <= dep_v;
            f_flg <= flg_v;
            if accept = '1' then
               f_req <= wb_we_i & wb_addr_i & wb_data_i;
            end if;
            if rst_i = '1' then
               f_dep <= 0;
               f_flg <= (others => '0');
            end if;
         end if;
      end process p_model;

      f_match <= depth_r = f_dep and flags_r = f_flg and
                 (f_dep < 1 or ram_r(to_integer(top_r)) = f_stk(0)) and
                 (f_dep < 2 or ram_r(to_integer(top_r - 1)) = f_stk(1)) and
                 (f_dep < 3 or ram_r(to_integer(top_r - 2)) = f_stk(2)) and
                 (f_dep < 4 or ram_r(to_integer(top_r - 3)) = f_stk(3)) and
                 (f_dep < 5 or ram_r(to_integer(top_r - 4)) = f_stk(4)) and
                 (f_dep < 6 or ram_r(to_integer(top_r - 5)) = f_stk(5)) and
                 (f_dep < 7 or ram_r(to_integer(top_r - 6)) = f_stk(6)) and
                 (f_dep < 8 or ram_r(to_integer(top_r - 7)) = f_stk(7)) and
                 (f_dep < 9 or ram_r(to_integer(top_r - 8)) = f_stk(8)) and
                 (f_dep < 10 or ram_r(to_integer(top_r - 9)) = f_stk(9)) and
                 (f_dep < 11 or ram_r(to_integer(top_r - 10)) = f_stk(10)) and
                 (f_dep < 12 or ram_r(to_integer(top_r - 11)) = f_stk(11)) and
                 (f_dep < 13 or ram_r(to_integer(top_r - 12)) = f_stk(12)) and
                 (f_dep < 14 or ram_r(to_integer(top_r - 13)) = f_stk(13)) and
                 (f_dep < 15 or ram_r(to_integer(top_r - 14)) = f_stk(14)) and
                 (f_dep < 16 or ram_r(to_integer(top_r - 15)) = f_stk(15));

      -- No command runs.
      f_view  <= (state_r = UWAIT_ST and ret_r = VIEW_ST) or state_r = VIEW_ST;
      f_quiet <= state_r = IDLE_ST or f_view;

      -- The states of a command of the stack.
      f_cmd <= state_r = CMD_ST or (state_r = ARITH_ST and num_r = X"04") or
               (state_r = PUSH_ST and num_r = X"04" and npush_r >= 1 and cflags_r = "000");

      -- psl default clock is rising_edge(clk_i);

      -- psl f_state_ok : assert always
      --    state_r <= t_state'high and ret_r <= t_state'high and
      --    (s10_ret_r = SCALE10_ST or s10_ret_r = DSCALE_ST);
      -- psl f_depth_ok : assert always depth_r <= 16 and f_dep <= 16;
      -- psl f_wait : assert always wait_r = '1' <-> (pend_r = '1' or f_view);
      -- psl f_view_alone : assert always f_view -> pend_r = '0';
      -- psl f_pend : assert always
      --    pend_r = '1' -> f_req = pend_we_r & pend_addr_r & pend_data_r;
      -- psl f_ack_view : assert always f_view -> wb_ack_o = '0';

      gen_stack : if G_STACK generate
         -- psl f_stack : assert always f_quiet -> f_match;
         -- psl f_states : assert always f_quiet or f_cmd;
         -- psl f_pend_stack : assert always
         --    (pend_r = '1' and pend_we_r = '1') ->
         --    (pend_addr_r /= "010" and pend_addr_r /= "011" and
         --     (pend_addr_r /= "100" or
         --      (unsigned(pend_data_r(31 downto 16)) = 0 and
         --       unsigned(pend_data_r(7 downto 0)) <= 6)));
         -- psl f_cmd_num : assert always
         --    state_r = CMD_ST -> (unsigned(num_r) <= 6 or num_r = X"FF");
      end generate gen_stack;

   end generate gen_formal;


   p_main : process (clk_i)
      variable we_v    : boolean;
      variable waddr_v : unsigned(3 downto 0);
      variable wdata_v : t_word64;
      variable info_v  : t_info;
      variable num_v   : std_logic_vector(7 downto 0);
      variable n_v     : natural range 0 to 255;
      variable c_v     : integer;
      variable k_v     : integer;
      variable prod_v  : signed(47 downto 0);
      variable bcd_v   : unsigned(63 downto 0);
      variable wr_v    : signed(32 downto 0);
      variable ok_v    : boolean;
      variable tr_v    : unsigned(32 downto 0);

      -- Starts an operation of the unit, and goes to ret when it ends.
      procedure ucall(op  : t_fpu_op;
                      a   : t_word64;
                      b   : t_word64;
                      ret : t_state) is
      begin
         u_start <= '1';
         u_op    <= op;
         u_rnd   <= RND_EVEN;
         u_short <= '0';
         u_a     <= a;
         u_b     <= b;
         ret_r   <= ret;
         state_r <= UWAIT_ST;
      end procedure ucall;

      -- Pushes v: the slot after X, which on a full stack is the deepest.
      procedure push(v : t_word64) is
      begin
         we_v    := true;
         waddr_v := top_r + 1;
         wdata_v := v;
         top_r   <= top_r + 1;
         if depth_r = 16 then
            flags_r(C_STACK) <= '1';
         else
            depth_r <= depth_r + 1;
         end if;
      end procedure push;

      -- Pops k values, or as many as there are, with the stack fault.
      procedure pop(k : natural) is
      begin
         if k > depth_r then
            flags_r(C_STACK) <= '1';
            top_r            <= top_r - depth_r mod 16;
            depth_r          <= 0;
         else
            top_r   <= top_r - k mod 16;
            depth_r <= depth_r - k;
         end if;
      end procedure pop;

      -- Ends a command: its flags, and its results pushed.
      procedure finish(r1 : t_word64;
                       r2 : t_word64;
                       np : natural;
                       fl : std_logic_vector(2 downto 0)) is
      begin
         res_r    <= r1;
         res2_r   <= r2;
         npush_r  <= np;
         cflags_r <= fl;
         state_r  <= PUSH_ST;
      end procedure finish;

      -- Serves a request: at once, or by starting the unit.
      procedure serve(we   : std_logic;
                      addr : std_logic_vector(2 downto 0);
                      data : std_logic_vector(31 downto 0)) is
         variable status_v : std_logic_vector(31 downto 0);
         variable rel_v    : integer;
      begin
         if we = '1' then
            wb_ack_o <= '1';
            wait_r   <= '0';
            case addr is
               when "000" =>
                  push(X"00000000" & data);
               when "001" =>
                  if depth_r = 0 then
                     flags_r(C_STACK) <= '1';
                  else
                     we_v    := true;
                     waddr_v := top_r;
                     wdata_v := data & x_val(31 downto 0);
                  end if;
               when "010" =>
                  if short_direct(data) then
                     push(widen(data));
                  else
                     ucall(OP_FROMSHORT, X"00000000" & data, C_QNAN, WPUSH_ST);
                  end if;
               when "011" =>
                  ucall(OP_ITOF, std_logic_vector(resize(signed(data), 64)), C_QNAN, WPUSH_ST);
               when "100" =>
                  num_r   <= data(7 downto 0);
                  n_r     <= to_integer(unsigned(data(15 downto 8)));
                  sbit_r  <= data(16);
                  state_r <= CMD_ST;
                  -- The bits 31..17 make the word not valid; CMD_ST sees
                  -- them as a number that is not defined.
                  if unsigned(data(31 downto 17)) /= 0 then
                     num_r <= X"FF";
                  end if;
               when "101" =>
                  flags_r <= data(11 downto 8);
               when others =>
                  null;
            end case;
         else
            status_v := (others => '0');
            status_v(4 downto 0)   := std_logic_vector(to_unsigned(depth_r, 5));
            status_v(11 downto 8)  := flags_r;
            status_v(21 downto 16) := f_class(x_val);
            rel_v := f_cmp(y_val, x_val);
            case addr is
               when "000" => wb_data_o <= x_val(31 downto 0);
               when "001" => wb_data_o <= x_val(63 downto 32);
               when "101" => wb_data_o <= status_v;
               when "110" => wb_data_o <= std_logic_vector(to_signed(rel_v, 32));
               when others => wb_data_o <= (others => '0');
            end case;
            if addr = "010" and long_direct(x_val) then
               wb_data_o <= narrow(x_val);
               wb_ack_o  <= '1';
               wait_r    <= '0';
            elsif addr = "010" or addr = "011" then
               -- The views through the unit: STALL stays high until it ends.
               wait_r <= '1';
               if addr = "010" then
                  ucall(OP_TOSHORT, x_val, C_QNAN, VIEW_ST);
               else
                  ucall(OP_FTOW, x_val, C_QNAN, VIEW_ST);
               end if;
            else
               wb_ack_o <= '1';
               wait_r   <= '0';
            end if;
         end if;
      end procedure serve;

   begin
      if rising_edge(clk_i) then
         we_v     := false;
         waddr_v  := (others => '0');
         wdata_v  := (others => '0');
         u_start  <= '0';
         wb_ack_o <= '0';

         -- A request while a command runs: a read of CMD at once, and
         -- any other waits.
         if accept = '1' and (state_r /= IDLE_ST or pend_r = '1') then
            if wb_we_i = '0' and wb_addr_i = "100" then
               wb_ack_o  <= '1';
               wb_data_o <= (others => '0');
            else
               pend_r      <= '1';
               pend_we_r   <= wb_we_i;
               pend_addr_r <= wb_addr_i;
               pend_data_r <= wb_data_i;
               wait_r      <= '1';
            end if;
         end if;

         case state_r is

            when IDLE_ST =>
               if pend_r = '1' then
                  pend_r <= '0';
                  serve(pend_we_r, pend_addr_r, pend_data_r);
               elsif accept = '1' then
                  serve(wb_we_i, wb_addr_i, wb_data_i);
               end if;

            when UWAIT_ST =>
               if u_done = '1' then
                  state_r <= ret_r;
               end if;

            when VIEW_ST =>
               wb_ack_o  <= '1';
               wb_data_o <= u_result(31 downto 0);
               wait_r    <= '0';
               state_r   <= IDLE_ST;

            when WPUSH_ST =>
               push(u_result);
               state_r <= IDLE_ST;

            when PUSH_ST =>
               if npush_r = 2 then
                  push(res_r);
                  res_r   <= res2_r;
                  npush_r <= 1;
               else
                  if npush_r = 1 then
                     push(res_r);
                  end if;
                  flags_r(2 downto 0) <= flags_r(2 downto 0) or cflags_r;
                  state_r             <= IDLE_ST;
               end if;

            -- A command: the word checked, the operands popped.
            when CMD_ST =>
               num_v  := num_r;
               n_v    := n_r;
               info_v := info(num_v);
               x_r    <= x_val;
               y_r    <= y_val;
               noovf_r <= '0';
               state_r <= IDLE_ST;
               if not info_v.valid or (sbit_r = '1' and not info_v.s_ok) or
                  (std_logic_vector(to_unsigned(n_v, 8)) and not info_v.nmask) /= X"00" then
                  flags_r(C_INVALID) <= '1';
               else
                  pop(info_v.pops);
                  case num_v is
                     when X"00" => null;
                     when X"01" =>
                        top_r   <= top_r;
                        depth_r <= 0;
                        if n_v = 1 then
                           flags_r <= (others => '0');
                        end if;
                     -- DUP, OVER, and PICK n: a copy, the canonical NaN
                     -- with the stack fault if the value is missing.
                     when X"02" =>
                        push(x_val);
                        if depth_r = 0 then
                           flags_r(C_STACK) <= '1';
                        end if;
                     when X"05" =>
                        push(y_val);
                        if depth_r < 2 then
                           flags_r(C_STACK) <= '1';
                        end if;
                     when X"06" =>
                        push(pick);
                        if n_v >= depth_r then
                           flags_r(C_STACK) <= '1';
                        end if;
                     when X"03" =>
                        if n_v = 0 then
                           pop(1);
                        else
                           pop(n_v);
                        end if;
                     when others =>
                        state_r <= ARITH_ST;
                  end case;
               end if;

            -- The commands on the popped operands.
            when ARITH_ST =>
               case num_r is
                  when X"04" =>
                     finish(x_r, y_r, 2, "000");
                  when X"10" | X"11" | X"12" | X"13" | X"14" =>
                     case num_r(2 downto 0) is
                        when "000"  => ucall(OP_ADD, y_r, x_r, RESULT_ST);
                        when "001"  => ucall(OP_SUB, y_r, x_r, RESULT_ST);
                        when "010"  => ucall(OP_MUL, y_r, x_r, RESULT_ST);
                        when "011"  => ucall(OP_DIV, y_r, x_r, RESULT_ST);
                        when others => ucall(OP_SQRT, x_r, x_r, RESULT_ST);
                     end case;
                     -- The S bit: the unit rounds once, to binary32.
                     u_short <= sbit_r;
                  when X"15" => finish(not x_r(63) & x_r(62 downto 0), x_r, 1, "000");
                  when X"16" => finish('0' & x_r(62 downto 0), x_r, 1, "000");
                  when X"17" | X"18" =>
                     c_v := f_cmp(y_r, x_r);
                     if c_v = 2 then
                        finish(C_QNAN, x_r, 1, "00" & bool_to_sl(f_snan(y_r) or f_snan(x_r)));
                     elsif c_v = 0 then
                        -- Equal values differ only as zeros: -0 < +0.
                        if (num_r = X"18") = (y_r(63) = '0') then
                           finish(y_r, x_r, 1, "000");
                        else
                           finish(x_r, x_r, 1, "000");
                        end if;
                     elsif (c_v > 0) = (num_r = X"18") then
                        finish(y_r, x_r, 1, "000");
                     else
                        finish(x_r, x_r, 1, "000");
                     end if;
                  when X"19" =>
                     ucall(OP_TOSHORT, x_r, x_r, LONG_ST);
                  when X"1A" =>
                     ucall(OP_SQRT, x_r, x_r, ISQRT_ST);
                     u_rnd <= RND_TRUNC;
                  when X"1B" =>
                     if f_nan(x_r) then
                        finish(C_QNAN, x_r, 1, "00" & bool_to_sl(f_snan(x_r)));
                     elsif f_zero(x_r) then
                        finish((others => '0'), x_r, 1, "000");
                     elsif x_r(63) = '1' then
                        finish(C_MONE, x_r, 1, "000");
                     else
                        finish(C_ONE, x_r, 1, "000");
                     end if;
                  when X"1C" =>
                     c_v := f_cmp(y_r, x_r);
                     if c_v = 2 then
                        finish((others => '0'), x_r, 1, "001");
                     elsif to_unsigned(n_r, 8)(c_v + 1) = '1' then
                        finish(C_MONE, x_r, 1, "000");
                     else
                        finish((others => '0'), x_r, 1, "000");
                     end if;
                  when X"1D" => ucall(OP_FMOD, y_r, x_r, RESULT_ST);
                  when X"20" | X"21" | X"22" | X"23" | X"24" =>
                     ucall(OP_INTEGRAL, x_r, x_r, RESULT_ST);
                     case num_r(2 downto 0) is
                        when "000"  => u_rnd <= RND_FLOOR;
                        when "001"  => u_rnd <= RND_CEIL;
                        when "010"  => u_rnd <= RND_TRUNC;
                        when "011"  => u_rnd <= RND_EVEN;
                        when others => u_rnd <= RND_AWAY;
                     end case;
                  when X"28" => ucall(OP_ITOF, x_r, x_r, RESULT_ST);
                  when X"29" => ucall(OP_UTOF, x_r, x_r, RESULT_ST);
                  when X"2A" => ucall(OP_FTOI, x_r, x_r, RESULT_ST);
                  when X"2B" => ucall(OP_FTOU, x_r, x_r, RESULT_ST);
                  when X"30" =>
                     if n_r < 16 then
                        finish(C_CONSTS(n_r mod 16), x_r, 1, "000");
                     else
                        finish(C_QNAN, x_r, 1, "001");
                     end if;
                  when X"38" | X"39" =>
                     -- X must be whole, or infinite, which counts as the
                     -- largest count.
                     if f_nan(x_r) or not (f_whole(x_r) or f_inf(x_r)) then
                        finish(C_QNAN, x_r, 1, "001");
                     elsif f_nan(y_r) then
                        finish(C_QNAN, x_r, 1, "00" & bool_to_sl(f_snan(y_r)));
                     elsif f_inf(y_r) or f_zero(y_r) then
                        finish(y_r, x_r, 1, "000");
                     else
                        noovf_r <= bool_to_sl(f_inf(x_r));
                        ucall(OP_FTOI, x_r, x_r, SCALE_ST);
                     end if;
                  when X"3A" => state_r <= DIGITS_ST;
                  when X"3B" =>
                     ok_v := true;
                     for i in 0 to 15 loop
                        if unsigned(x_r(4 * i + 3 downto 4 * i)) > 9 then
                           ok_v := false;
                        end if;
                     end loop;
                     if ok_v then
                        sum_r   <= (others => '0');
                        cnt_r   <= 15;
                        state_r <= FROMBCD_ST;
                     else
                        finish(C_QNAN, x_r, 1, "001");
                     end if;
                  when X"3C" => ucall(OP_GETEXP, x_r, x_r, RESULT_ST);
                  when X"3D" => ucall(OP_GETMANT, x_r, x_r, RESULT_ST);
                  when others =>
                     -- The word operators.
                     if not f_fits(x_r) or (num_r /= X"63" and not f_fits(y_r)) then
                        finish(C_QNAN, x_r, 1, "001");
                     else
                        ucall(OP_FTOW, y_r, y_r, WORDY_ST);
                     end if;
               end case;

            -- The result of the unit is the result of the command.
            when RESULT_ST =>
               finish(u_result, x_r, 1, u_flags);

            -- ROUND32: the short value, in the main format again.
            when LONG_ST =>
               cflags_r <= u_flags;
               ucall(OP_FROMSHORT, u_result, u_result, ISQRT_ST);

            -- After ROUND32, the result; after ISQRT's root, TRUNC.
            when ISQRT_ST =>
               if num_r = X"1A" and u_op = OP_SQRT then
                  cflags_r <= u_flags;
                  ucall(OP_INTEGRAL, u_result, u_result, ISQRT_ST);
                  u_rnd <= RND_TRUNC;
               elsif num_r = X"1A" then
                  finish(u_result, x_r, 1, cflags_r or u_flags);
               else
                  finish(u_result, x_r, 1, cflags_r);
               end if;

            -- SCALE2 and SCALE10: the count clamped.
            when SCALE_ST =>
               if num_r = X"38" then
                  if signed(u_result) > 2100 then
                     k_v := 2100;
                  elsif signed(u_result) < -2100 then
                     k_v := -2100;
                  else
                     k_v := to_integer(signed(u_result(15 downto 0)));
                  end if;
                  u_k <= std_logic_vector(to_signed(k_v, 16));
                  ucall(OP_SCALE2, y_r, y_r, SCALE2_ST);
               else
                  if signed(u_result) > 650 then
                     k_v := 650;
                  elsif signed(u_result) < -650 then
                     k_v := -650;
                  else
                     k_v := to_integer(signed(u_result(15 downto 0)));
                  end if;
                  s10_y_r   <= y_r;
                  s10_neg_r <= bool_to_sl(k_v < 0);
                  s10_k_r   <= magnitude(k_v);
                  s10_ret_r <= SCALE10_ST;
                  state_r   <= S10_ST;
               end if;

            when SCALE2_ST =>
               if noovf_r = '1' then
                  finish(u_result, x_r, 1, u_flags and "011");
               else
                  finish(u_result, x_r, 1, u_flags);
               end if;

            when SCALE10_ST =>
               if noovf_r = '1' then
                  finish(s10_res_r, x_r, 1, cflags_r and "011");
               else
                  finish(s10_res_r, x_r, 1, cflags_r);
               end if;

            -- SCALE10's sequence on s10_y_r, s10_k_r, and s10_neg_r, with
            -- the result in s10_res_r and the flags in cflags_r.
            when S10_ST =>
               if s10_k_r <= 22 then
                  if s10_neg_r = '1' then
                     ucall(OP_DIV, s10_y_r, C_TENS(to_integer(s10_k_r) mod 23), S10_SMALL_ST);
                  else
                     ucall(OP_MUL, s10_y_r, C_TENS(to_integer(s10_k_r) mod 23), S10_SMALL_ST);
                  end if;
               else
                  rh_r    <= s10_y_r;
                  rl_r    <= (others => '0');
                  s10_i_r <= 0;
                  state_r <= S10_LOOP_ST;
               end if;

            when S10_SMALL_ST =>
               s10_res_r <= u_result;
               cflags_r  <= u_flags;
               state_r   <= s10_ret_r;

            -- For each bit i of the count, from 0 to 8, a product with the
            -- pair of bit i, and for bit 9, two with that of bit 8.
            when S10_LOOP_ST =>
               if s10_i_r = 11 or (s10_i_r >= 9 and s10_k_r(9) = '0') then
                  ucall(OP_ADD, rh_r, rl_r, S10_FIN_ST);
               elsif s10_i_r >= 9 or s10_k_r(s10_i_r) = '1' then
                  if s10_neg_r = '1' then
                     bh_r <= C_TENTH_HI(minimum(s10_i_r, 8));
                     bl_r <= C_TENTH_LO(minimum(s10_i_r, 8));
                  else
                     bh_r <= C_TEN_HI(minimum(s10_i_r, 8));
                     bl_r <= C_TEN_LO(minimum(s10_i_r, 8));
                  end if;
                  s10_i_r <= s10_i_r + 1;
                  state_r <= MP1_ST;
               else
                  s10_i_r <= s10_i_r + 1;
               end if;

            -- Dekker's product of (rh, rl) and (bh, bl).
            when MP1_ST => ucall(OP_MUL, rh_r, bh_r, MP2_ST);
            when MP2_ST =>
               p_r <= u_result;
               if f_inf(u_result) then
                  -- The product is infinite, and so is every later one.
                  s10_res_r <= u_result;
                  cflags_r  <= "100";
                  state_r   <= s10_ret_r;
               else
                  ucall(OP_MULERR, rh_r, bh_r, MP3_ST);
               end if;
            when MP3_ST =>
               e_r <= u_result;
               ucall(OP_MUL, rh_r, bl_r, MP4_ST);
            when MP4_ST => ucall(OP_ADD, e_r, u_result, MP5_ST);
            when MP5_ST =>
               e_r <= u_result;
               ucall(OP_MUL, rl_r, bh_r, MP6_ST);
            when MP6_ST => ucall(OP_ADD, e_r, u_result, MP7_ST);
            when MP7_ST =>
               e_r <= u_result;
               ucall(OP_ADD, p_r, u_result, MP8_ST);
            when MP8_ST =>
               h_r <= u_result;
               if f_inf(u_result) then
                  s10_res_r <= u_result;
                  cflags_r  <= "100";
                  state_r   <= s10_ret_r;
               else
                  ucall(OP_SUB, u_result, p_r, MP9_ST);
               end if;
            when MP9_ST => ucall(OP_SUB, e_r, u_result, MP10_ST);
            when MP10_ST =>
               rh_r    <= h_r;
               rl_r    <= u_result;
               state_r <= S10_LOOP_ST;

            when S10_FIN_ST =>
               s10_res_r <= u_result;
               cflags_r  <= u_flags;
               state_r   <= s10_ret_r;

            -- DIGITS n.
            when DIGITS_ST =>
               if f_nan(x_r) or f_inf(x_r) or n_r = 0 or n_r > 15 then
                  finish(C_QNAN, C_QNAN, 2, "001");
               elsif f_zero(x_r) then
                  finish((others => '0'), (others => '0'), 2, "000");
               else
                  ax_r <= '0' & x_r(62 downto 0);
                  ucall(OP_ILOGB, '0' & x_r(62 downto 0), x_r, DLOG_ST);
               end if;

            when DLOG_ST =>
               -- e = ceil((E + 1) log10 2): the floor of the product
               -- plus 2^32 - 1, over 2^32.
               prod_v  := (signed(u_result(15 downto 0)) + 1) * C_LOG10_2 + C_CEIL;
               dexp_r  <= prod_v(47 downto 32);
               state_r <= DLOOP_ST;

            when DLOOP_ST =>
               s10_y_r   <= ax_r;
               k_v       := n_r - 1 - to_integer(dexp_r);
               s10_neg_r <= bool_to_sl(k_v < 0);
               s10_k_r   <= magnitude(k_v);
               s10_ret_r <= DSCALE_ST;
               state_r   <= S10_ST;

            when DSCALE_ST =>
               ucall(OP_INTEGRAL, s10_res_r, s10_res_r, DNEAR_ST);

            when DNEAR_ST =>
               -- Positive values compare as their bits do.
               if unsigned(u_result) >= unsigned(C_TENS((n_r - 1) mod 23)) then
                  ucall(OP_FTOU, u_result, u_result, DINT_ST);
               else
                  dexp_r  <= dexp_r - 1;
                  state_r <= DLOOP_ST;
               end if;

            when DINT_ST =>
               -- Fewer than 15 digits fit 50 bits: they go to the top, and
               -- 50 steps of the double dabble convert them.
               bin_r   <= shift_left(unsigned(u_result), 14);
               bcd_r   <= (others => '0');
               cnt_r   <= 49;
               state_r <= BCD_ST;

            when BCD_ST =>
               bcd_v := bcd_r;
               for i in 0 to 15 loop
                  if bcd_v(4 * i + 3 downto 4 * i) >= 5 then
                     bcd_v(4 * i + 3 downto 4 * i) := bcd_v(4 * i + 3 downto 4 * i) + 3;
                  end if;
               end loop;
               bcd_r <= bcd_v(62 downto 0) & bin_r(63);
               bin_r <= shift_left(bin_r, 1);
               if cnt_r = 0 then
                  cnt_r   <= 16 - n_r mod 16;
                  state_r <= ALIGN_ST;
               else
                  cnt_r <= cnt_r - 1;
               end if;

            -- The n digits moved to the top.
            when ALIGN_ST =>
               if cnt_r = 0 then
                  res2_r <= std_logic_vector(bcd_r);
                  ucall(OP_ITOF, std_logic_vector(resize(dexp_r, 64)), x_r, DPUSH_ST);
               else
                  bcd_r <= shift_left(bcd_r, 4);
                  cnt_r <= cnt_r - 1;
               end if;

            when DPUSH_ST =>
               finish(res2_r, u_result, 2, "000");

            -- FROMBCD: ten times the sum plus the next digit, the top one
            -- of X, which then moves up a digit.
            when FROMBCD_ST =>
               sum_r <= shift_left(sum_r, 3) + shift_left(sum_r, 1) +
                        resize(unsigned(x_r(63 downto 60)), 64);
               x_r   <= x_r(59 downto 0) & "0000";
               if cnt_r = 0 then
                  state_r <= UTOF_ST;
               else
                  cnt_r <= cnt_r - 1;
               end if;

            when UTOF_ST =>
               ucall(OP_UTOF, std_logic_vector(sum_r), x_r, WORD_END_ST);

            when WORDY_ST =>
               wy_r <= signed(u_result(31 downto 0));
               ucall(OP_FTOW, x_r, x_r, WORDX_ST);

            when WORDX_ST =>
               wx_r <= signed(u_result(31 downto 0));
               state_r <= WORD_ST;
               if num_r = X"66" or num_r = X"67" then
                  if signed(u_result(31 downto 0)) = 0 then
                     finish(C_QNAN, x_r, 1, "001");
                  else
                     dq_r    <= resize(unsigned(abs(resize(wy_r, 33))), 32);
                     dr_r    <= (others => '0');
                     cnt_r   <= 32;
                     state_r <= IDIV_ST;
                  end if;
               end if;

            -- The magnitudes divided, a bit in each step.
            when IDIV_ST =>
               if cnt_r = 0 then
                  state_r <= WORD_ST;
               else
                  tr_v := dr_r(31 downto 0) & dq_r(31);
                  if tr_v >= unsigned(abs(resize(wx_r, 33))) then
                     dr_r <= tr_v - unsigned(abs(resize(wx_r, 33)));
                     dq_r <= dq_r(30 downto 0) & '1';
                  else
                     dr_r <= tr_v;
                     dq_r <= dq_r(30 downto 0) & '0';
                  end if;
                  cnt_r <= cnt_r - 1;
               end if;

            when WORD_ST =>
               ok_v := true;
               wr_v := (others => '0');
               case num_r is
                  when X"60" => wr_v := resize(wy_r and wx_r, 33);
                  when X"61" => wr_v := resize(wy_r or wx_r, 33);
                  when X"62" => wr_v := resize(wy_r xor wx_r, 33);
                  when X"63" => wr_v := resize(not wx_r, 33);
                  when X"64" | X"65" =>
                     if wx_r < 0 then
                        ok_v := false;
                     elsif wx_r < 32 then
                        if num_r = X"64" then
                           wr_v := resize(shift_left(wy_r, to_integer(wx_r)), 33);
                        else
                           wr_v := resize(signed(shift_right(unsigned(wy_r), to_integer(wx_r))), 33);
                        end if;
                     end if;
                  when X"66" =>
                     wr_v := signed('0' & dq_r);
                     if wy_r(31) /= wx_r(31) then
                        wr_v := -wr_v;
                     end if;
                  when others =>
                     wr_v := signed(dr_r);
                     if wy_r(31) = '1' then
                        wr_v := -wr_v;
                     end if;
               end case;
               if ok_v then
                  ucall(OP_ITOF, std_logic_vector(resize(wr_v, 64)), x_r, WORD_END_ST);
               else
                  finish(C_QNAN, x_r, 1, "001");
               end if;

            when WORD_END_ST =>
               finish(u_result, x_r, 1, "000");

         end case;

         if we_v then
            ram_r(to_integer(waddr_v)) <= wdata_v;
         end if;

         if rst_i = '1' then
            state_r  <= IDLE_ST;
            depth_r  <= 0;
            top_r    <= (others => '0');
            flags_r  <= (others => '0');
            wait_r   <= '0';
            pend_r   <= '0';
            wb_ack_o <= '0';
            u_start  <= '0';
         end if;
      end if;
   end process p_main;

end architecture synthesis;

