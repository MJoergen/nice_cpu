-- The math unit, MPU, of DEVICES.md §2: 32 words of I/O that multiply and
-- divide 32-bit integers, signed and unsigned, and count their bits, and
-- divide 64-bit integers and take their square root.
--
--   0  A        3  SMUL_HI  6  SDIV_Q   9  UDIV_R   12  POPCNT
--   1  B        4  UMUL_LO  7  SDIV_R   10  CLZ     13-15  read 0
--   2  SMUL_LO  5  UMUL_HI  8  UDIV_Q   11  CTZ
--
--   16, 17  C            22, 23  SDIV64_R     28  ISQRT64_Q
--   18, 19  D            24, 25  UDIV64_Q     29, 30  ISQRT64_R
--   20, 21  SDIV64_Q     26, 27  UDIV64_R     31  reads 0
--
-- THEORY OF OPERATION
-- A write to A or B starts a new computation. Three units run side by side:
-- * A multiplier forms the unsigned product of A and B in two cycles. It is
--   the * operator, followed by two registers, so that synthesis can map it
--   to DSP blocks and move the registers into them. The signed product has
--   the same low word. Its high word is the unsigned one, minus B if A is
--   negative, and minus A if B is negative, and the second register holds
--   it too.
-- * A restoring divider divides A by B, unsigned, one bit per cycle.
-- * A second one divides |A| by |B|. The signed quotient is negated when
--   A and B differ in sign, and the signed remainder when A is negative.
-- A divider takes 8 steps in one cycle when it can tell that they all
-- give quotient bits of 0: when the remainder, shifted left by 8 bits, with
-- the next 8 bits of the dividend shifted in, is still less than the
-- divisor. That skips the leading zeros of the quotient, of which there are
-- many when the dividend is small or the divisor large, and any run of 8
-- zeros after them. A division takes 1 cycle to start, then 32 cycles at
-- most, and 4 at least.
-- A restoring divider with B = 0 gives Q = 0xFFFFFFFF and R = A, which is
-- what DEVICES.md §2 asks for, except for the signed quotient with A < 0,
-- which is set to 0xFFFFFFFF on its own. -2^31 / -1 needs no special case:
-- |A| / |B| = 0x80000000, and negating it gives 0x80000000 again.
--
-- The bit counts of A, CLZ, CTZ, and POPCNT, are registered from A in each
-- cycle, and a read of one waits for the multiplier's count, which covers
-- the cycle after A changes. CLZ and CTZ are priority encoders, and POPCNT
-- a tree of five adds, so that none of them is a long chain.
--
-- A write to C or D starts a computation of C / D in the same way, with two
-- 64-bit dividers, which takes 65 cycles at most. It also starts the square
-- root of C, which takes 2 bits of C in each of 32 steps, so 33 cycles: the
-- remainder, shifted left by 2 with the next 2 bits shifted in, is
-- compared with 4Q + 1, and if it is not less, 4Q + 1 is subtracted and the
-- next bit of Q is 1. Q has 32 bits, and the remainder, at most 2Q, 33. The
-- two halves of the MPU are independent: a write to one half does not
-- restart the other.
--
-- The port is a pipelined Wishbone slave. It acknowledges each request in
-- the cycle after it accepts it, except a read of a result while the unit
-- that computes it runs. That read is acknowledged in the cycle after the
-- unit ends, and STALL is high until then, so that no other request
-- is accepted in between. A read of an operand or a spare word never waits.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) The master holds STB and the request while STALL is high.
-- b) STB is high only for requests to the MPU: the bus decoder decodes the
--    address. The MPU is at 0xFFFFFF20-0xFFFFFF3F, so the offset is
--    address bits 4..0.
--
-- RESET
-- Synchronous. It sets A, B, C, and D to 0, as DEVICES.md §2 requires, and drops
-- any ACK owed.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

entity mpu is
   generic (
      -- Adds the properties and invariants of formal/mpu.sby.
      G_FORMAL : boolean := false
   );
   port (
      clk_i      : in  std_logic;
      rst_i      : in  std_logic;

      wb_cyc_i   : in  std_logic;
      wb_stb_i   : in  std_logic;
      wb_stall_o : out std_logic;
      wb_ack_o   : out std_logic := '0';
      wb_we_i    : in  std_logic;
      wb_addr_i  : in  std_logic_vector(4 downto 0);
      wb_data_i  : in  std_logic_vector(31 downto 0);
      wb_data_o  : out std_logic_vector(31 downto 0) := (others => '0')
   );
end entity mpu;

architecture synthesis of mpu is

   constant C_STEPS   : natural := 32;
   constant C_STEPS64 : natural := 64;
   constant C_SQSTEPS : natural := 32;

   -- The steps a divider skips at once.
   constant C_SKIP : natural := 8;

   subtype t_count is natural range 0 to C_STEPS64;

   signal a_r : std_logic_vector(31 downto 0) := (others => '0');
   signal b_r : std_logic_vector(31 downto 0) := (others => '0');

   -- A write to A or B was accepted, and the divisions start next cycle.
   signal start_r : std_logic := '1';

   -- The multiplier: the product of A and B, the same delayed by a cycle,
   -- and the high word of the signed product. A write to A or B sets
   -- mul_count_r to the cycles until they hold its product.
   signal mul_count_r : natural range 0 to 2         := 2;
   signal mul_r       : std_logic_vector(63 downto 0) := (others => '0');
   signal prod_r      : std_logic_vector(63 downto 0) := (others => '0');
   signal smul_hi_r   : std_logic_vector(31 downto 0) := (others => '0');

   -- The bit counts of A, as it was in the cycle before.
   signal clz_r : std_logic_vector(5 downto 0) := "100000";
   signal ctz_r : std_logic_vector(5 downto 0) := "100000";
   signal pop_r : std_logic_vector(5 downto 0) := (others => '0');

   -- The two dividers. The quotient register starts as the dividend, which
   -- shifts out to the left as the quotient shifts in. The count is the
   -- steps still to run, and sdiv_r holds |B|.
   signal uquo_r   : std_logic_vector(31 downto 0) := (others => '0');
   signal urem_r   : std_logic_vector(31 downto 0) := (others => '0');
   signal ucount_r : t_count                       := 0;
   signal squo_r   : std_logic_vector(31 downto 0) := (others => '0');
   signal srem_r   : std_logic_vector(31 downto 0) := (others => '0');
   signal scount_r : t_count                       := 0;
   signal sdiv_r   : std_logic_vector(31 downto 0) := (others => '0');

   -- The 64-bit half: the operands, and the same two dividers, 64 bits wide.
   signal c_r        : std_logic_vector(63 downto 0) := (others => '0');
   signal d_r        : std_logic_vector(63 downto 0) := (others => '0');
   signal start64_r  : std_logic                     := '1';
   signal uquo64_r   : std_logic_vector(63 downto 0) := (others => '0');
   signal urem64_r   : std_logic_vector(63 downto 0) := (others => '0');
   signal ucount64_r : t_count                       := 0;
   signal squo64_r   : std_logic_vector(63 downto 0) := (others => '0');
   signal srem64_r   : std_logic_vector(63 downto 0) := (others => '0');
   signal scount64_r : t_count                       := 0;
   signal sdiv64_r   : std_logic_vector(63 downto 0) := (others => '0');

   -- The square root of C: the bits of C still to come, shifting out to
   -- the left, the root so far, the remainder, and the steps to go.
   signal sqx_r     : std_logic_vector(63 downto 0) := (others => '0');
   signal sqq_r     : std_logic_vector(31 downto 0) := (others => '0');
   signal sqrem_r   : std_logic_vector(33 downto 0) := (others => '0');
   signal sqcount_r : natural range 0 to C_SQSTEPS  := 0;

   -- A read of a result waits for the computation.
   signal wait_r      : std_logic                    := '0';
   signal wait_addr_r : std_logic_vector(4 downto 0) := (others => '0');

   signal mul_busy    : std_logic;
   signal udiv_busy   : std_logic;
   signal sdiv_busy   : std_logic;
   signal udiv64_busy : std_logic;
   signal sdiv64_busy : std_logic;
   signal sqrt_busy   : std_logic;
   signal accept      : std_logic;

   -- The functions below take vectors of any width N, indexed N-1 downto 0.

   -- The number of leading and trailing 0 bits of x, 32 for 0.
   pure function count_lz(x : std_logic_vector(31 downto 0)) return std_logic_vector is
   begin
      for i in 31 downto 0 loop
         if x(i) = '1' then
            return to_stdlogicvector(31 - i, 6);
         end if;
      end loop;
      return to_stdlogicvector(32, 6);
   end function count_lz;

   pure function count_tz(x : std_logic_vector(31 downto 0)) return std_logic_vector is
   begin
      for i in 0 to 31 loop
         if x(i) = '1' then
            return to_stdlogicvector(i, 6);
         end if;
      end loop;
      return to_stdlogicvector(32, 6);
   end function count_tz;

   -- The number of 1 bits of x, in fields of 2, 4, 8, 16, and 32 bits.
   pure function count_ones(x : std_logic_vector(31 downto 0)) return std_logic_vector is
      variable v_v : std_logic_vector(31 downto 0);
   begin
      v_v := x - ((x srl 1) and X"55555555");
      v_v := (v_v and X"33333333") + ((v_v srl 2) and X"33333333");
      v_v := (v_v + (v_v srl 4)) and X"0F0F0F0F";
      v_v := v_v + (v_v srl 8);
      v_v := v_v + (v_v srl 16);
      return v_v(5 downto 0);
   end function count_ones;

   -- One step of the square root, on the remainder, the root, and the next
   -- 2 bits of the radicand. It returns the new remainder & root.
   pure function sqrt_step(rem_in : std_logic_vector(33 downto 0);
                           q      : std_logic_vector(31 downto 0);
                           bits   : std_logic_vector(1 downto 0)) return std_logic_vector is
      variable shifted_v : std_logic_vector(35 downto 0) := rem_in & bits;
      variable trial_v   : std_logic_vector(35 downto 0) := "00" & q & "01";
   begin
      if shifted_v >= trial_v then
         shifted_v := shifted_v - trial_v;
         return shifted_v(33 downto 0) & q(30 downto 0) & '1';
      end if;
      return shifted_v(33 downto 0) & q(30 downto 0) & '0';
   end function sqrt_step;

   pure function absolute(x : std_logic_vector) return std_logic_vector is
   begin
      if x(x'high) = '1' then
         return 0 - x;
      end if;
      return x;
   end function absolute;

   -- One step of a restoring divider, on the remainder and the
   -- quotient register. It returns the new remainder & quotient register.
   pure function divide_step(rem_in : std_logic_vector;
                             quo_in : std_logic_vector;
                             d      : std_logic_vector) return std_logic_vector is
      constant C_N       : natural := rem_in'length;
      variable shifted_v : std_logic_vector(C_N downto 0) := rem_in & quo_in(C_N - 1);
   begin
      if shifted_v >= ('0' & d) then
         shifted_v := shifted_v - ('0' & d);
         return shifted_v(C_N - 1 downto 0) & quo_in(C_N - 2 downto 0) & '1';
      end if;
      return shifted_v(C_N - 1 downto 0) & quo_in(C_N - 2 downto 0) & '0';
   end function divide_step;

   -- Whether the next C_SKIP steps of a divider all give quotient bits of 0.
   -- The remainder only grows while they do, so it is enough that it is
   -- still less than d after the last of them.
   pure function can_skip(rem_in : std_logic_vector;
                          quo_in : std_logic_vector;
                          d      : std_logic_vector) return boolean is
      constant C_N : natural := rem_in'length;
   begin
      return rem_in(C_N - 1 downto C_N - C_SKIP) = 0 and
             rem_in(C_N - C_SKIP - 1 downto 0) & quo_in(C_N - 1 downto C_N - C_SKIP) < d;
   end function can_skip;

   -- The signed quotient and remainder, from the quotient and remainder of
   -- |n| / |d|.
   pure function signed_quo(quo, n, d : std_logic_vector) return std_logic_vector is
   begin
      if d = 0 then
         return (quo'range => '1');
      elsif (n(n'high) xor d(d'high)) = '1' then
         return 0 - quo;
      end if;
      return quo;
   end function signed_quo;

   pure function signed_rem(rem_in, n : std_logic_vector) return std_logic_vector is
   begin
      if n(n'high) = '1' then
         return 0 - rem_in;
      end if;
      return rem_in;
   end function signed_rem;

   -- The 64-bit value of the word pair 16 + 2k, 17 + 2k.
   impure function result64(k : std_logic_vector(2 downto 0)) return std_logic_vector is
   begin
      case k is
         when "000"  => return c_r;
         when "001"  => return d_r;
         when "010"  => return signed_quo(squo64_r, c_r, d_r);
         when "011"  => return signed_rem(srem64_r, c_r);
         when "100"  => return uquo64_r;
         when "101"  => return urem64_r;
         when "110"  => return sqrem_r(31 downto 0) & sqq_r;
         when others => return (63 downto 2 => '0') & sqrem_r(33 downto 32);
      end case;
   end function result64;

   -- Whether a read of word addr must wait for a computation.
   impure function must_wait(addr : std_logic_vector(4 downto 0)) return boolean is
   begin
      case to_integer(addr) is
         when 2 to 5   => return mul_busy = '1';
         when 6 | 7    => return sdiv_busy = '1';
         when 8 | 9    => return udiv_busy = '1';
         when 10 to 12 => return mul_busy = '1';
         when 20 to 23 => return sdiv64_busy = '1';
         when 24 to 27 => return udiv64_busy = '1';
         when 28 to 30 => return sqrt_busy = '1';
         when others   => return false;
      end case;
   end function must_wait;

   -- The value of word addr, once the computation has ended.
   impure function result(addr : std_logic_vector(4 downto 0)) return std_logic_vector is
      variable w_v : std_logic_vector(63 downto 0);
   begin
      if addr(4) = '1' then
         w_v := result64(addr(3 downto 1));
         if addr(0) = '1' then
            return w_v(63 downto 32);
         end if;
         return w_v(31 downto 0);
      end if;

      case addr(3 downto 0) is
         when X"0" =>
            return a_r;

         when X"1" =>
            return b_r;

         when X"2" | X"4" =>
            return prod_r(31 downto 0);

         when X"3" =>
            return smul_hi_r;

         when X"5" =>
            return prod_r(63 downto 32);

         when X"6" =>
            return signed_quo(squo_r, a_r, b_r);

         when X"7" =>
            return signed_rem(srem_r, a_r);

         when X"8" =>
            return uquo_r;

         when X"9" =>
            return urem_r;

         when X"A" =>
            return X"000000" & "00" & clz_r;

         when X"B" =>
            return X"000000" & "00" & ctz_r;

         when X"C" =>
            return X"000000" & "00" & pop_r;

         when others =>
            return X"00000000";
      end case;
   end function result;

begin

   mul_busy    <= '1' when mul_count_r /= 0 else '0';
   udiv_busy   <= '1' when start_r = '1' or ucount_r /= 0 else '0';
   sdiv_busy   <= '1' when start_r = '1' or scount_r /= 0 else '0';
   udiv64_busy <= '1' when start64_r = '1' or ucount64_r /= 0 else '0';
   sdiv64_busy <= '1' when start64_r = '1' or scount64_r /= 0 else '0';
   sqrt_busy   <= '1' when start64_r = '1' or sqcount_r /= 0 else '0';
   accept      <= wb_cyc_i and wb_stb_i and not wait_r;
   wb_stall_o  <= wait_r;


   p_multiply : process (clk_i)
      variable hi_v : std_logic_vector(31 downto 0);
   begin
      if rising_edge(clk_i) then
         mul_r  <= a_r * b_r;
         prod_r <= mul_r;

         hi_v := mul_r(63 downto 32);
         if a_r(31) = '1' then
            hi_v := hi_v - b_r;
         end if;
         if b_r(31) = '1' then
            hi_v := hi_v - a_r;
         end if;
         smul_hi_r <= hi_v;

         clz_r <= count_lz(a_r);
         ctz_r <= count_tz(a_r);
         pop_r <= count_ones(a_r);

         if mul_count_r /= 0 then
            mul_count_r <= mul_count_r - 1;
         end if;

         -- p_compute keeps the rest of the bus decoding.
         if accept = '1' and wb_we_i = '1' and wb_addr_i(4 downto 1) = "0000" then
            mul_count_r <= 2;
         end if;

         if rst_i = '1' then
            mul_count_r <= 2;
         end if;
      end if;
   end process p_multiply;


   p_compute : process (clk_i)

      -- One cycle of a divider: C_SKIP steps, one step, or none.
      procedure divide(signal rem_s   : inout std_logic_vector;
                       signal quo_s   : inout std_logic_vector;
                       signal count_s : inout t_count;
                       d              : std_logic_vector) is
         constant C_N    : natural := rem_s'length;
         constant C_ZERO : std_logic_vector(C_SKIP - 1 downto 0) := (others => '0');
         variable step_v : std_logic_vector(2 * C_N - 1 downto 0);
      begin
         if count_s >= C_SKIP and can_skip(rem_s, quo_s, d) then
            rem_s   <= rem_s(C_N - C_SKIP - 1 downto 0) & quo_s(C_N - 1 downto C_N - C_SKIP);
            quo_s   <= quo_s(C_N - C_SKIP - 1 downto 0) & C_ZERO;
            count_s <= count_s - C_SKIP;
         elsif count_s /= 0 then
            step_v  := divide_step(rem_s, quo_s, d);
            rem_s   <= step_v(2 * C_N - 1 downto C_N);
            quo_s   <= step_v(C_N - 1 downto 0);
            count_s <= count_s - 1;
         end if;
      end procedure divide;

      variable sq_v : std_logic_vector(65 downto 0);

   begin
      if rising_edge(clk_i) then
         if start_r = '1' then
            uquo_r   <= a_r;
            urem_r   <= (others => '0');
            ucount_r <= C_STEPS;
            squo_r   <= absolute(a_r);
            srem_r   <= (others => '0');
            scount_r <= C_STEPS;
            sdiv_r   <= absolute(b_r);
            start_r  <= '0';
         else
            divide(urem_r, uquo_r, ucount_r, b_r);
            divide(srem_r, squo_r, scount_r, sdiv_r);
         end if;

         if start64_r = '1' then
            uquo64_r   <= c_r;
            urem64_r   <= (others => '0');
            ucount64_r <= C_STEPS64;
            squo64_r   <= absolute(c_r);
            srem64_r   <= (others => '0');
            scount64_r <= C_STEPS64;
            sdiv64_r   <= absolute(d_r);
            sqx_r      <= c_r;
            sqq_r      <= (others => '0');
            sqrem_r    <= (others => '0');
            sqcount_r  <= C_SQSTEPS;
            start64_r  <= '0';
         else
            divide(urem64_r, uquo64_r, ucount64_r, d_r);
            divide(srem64_r, squo64_r, scount64_r, sdiv64_r);
            if sqcount_r /= 0 then
               sq_v      := sqrt_step(sqrem_r, sqq_r, sqx_r(63 downto 62));
               sqrem_r   <= sq_v(65 downto 32);
               sqq_r     <= sq_v(31 downto 0);
               sqx_r     <= sqx_r(61 downto 0) & "00";
               sqcount_r <= sqcount_r - 1;
            end if;
         end if;

         if accept = '1' and wb_we_i = '1' then
            -- A table of the writable words, one line each.
-- vsg_off sequential_007
            case to_integer(wb_addr_i) is
               when 0      => a_r <= wb_data_i; start_r <= '1';
               when 1      => b_r <= wb_data_i; start_r <= '1';
               when 16     => c_r(31 downto 0)  <= wb_data_i; start64_r <= '1';
               when 17     => c_r(63 downto 32) <= wb_data_i; start64_r <= '1';
               when 18     => d_r(31 downto 0)  <= wb_data_i; start64_r <= '1';
               when 19     => d_r(63 downto 32) <= wb_data_i; start64_r <= '1';
               when others => null;
            end case;
-- vsg_on sequential_007
         end if;

         if rst_i = '1' then
            a_r        <= (others => '0');
            b_r        <= (others => '0');
            c_r        <= (others => '0');
            d_r        <= (others => '0');
            start_r    <= '1';
            ucount_r   <= 0;
            scount_r   <= 0;
            start64_r  <= '1';
            ucount64_r <= 0;
            scount64_r <= 0;
            sqcount_r  <= 0;
         end if;
      end if;
   end process p_compute;


   p_bus : process (clk_i)
   begin
      if rising_edge(clk_i) then
         wb_ack_o <= '0';

         if wait_r = '1' and not must_wait(wait_addr_r) then
            wb_ack_o  <= '1';
            wb_data_o <= result(wait_addr_r);
            wait_r    <= '0';
         end if;

         if accept = '1' then
            if wb_we_i = '1' then
               wb_ack_o <= '1';
            elsif must_wait(wb_addr_i) then
               wait_r      <= '1';
               wait_addr_r <= wb_addr_i;
            else
               wb_ack_o  <= '1';
               wb_data_o <= result(wb_addr_i);
            end if;
         end if;

         if rst_i = '1' then
            wb_ack_o <= '0';
            wait_r   <= '0';
         end if;
      end if;
   end process p_bus;


   -- The proof of formal/mpu.sby. f_a to f_d are the operands as the bus
   -- wrote them. When the data of a read is set, for its ACK in the next
   -- cycle, it must be the operand or 0, or the result of a unit, and that
   -- unit must have computed it from the operands as they are now.
   --
   -- The multiplier: f_ma and f_mb are the operands that mul_r is the
   -- product of, and f_pa and f_pb those of prod_r and smul_hi_r. So a read
   -- of a product gets the product of A and B as they were when the read
   -- was accepted. That the signed correction computes the signed product
   -- is proven by hand in hdl/README.md: Yices and Boolector cannot compare
   -- two 32-bit multipliers.
   --
   -- The dividers: each has the loop invariant of a restoring divider of n
   -- by d, N bits wide. After k of its N steps, the quotient register holds
   -- the N - k dividend bits still to come above the k quotient bits found
   -- so far, and the k dividend bits shifted out, p, equal m + rem, with
   -- rem < d. The ghosts f_*q, f_*p, and f_*m hold q, p, and m as numbers,
   -- 2N bits wide. m is q times d, which the ghost forms as the divider
   -- finds the bits of q, by shift and add: twice m, plus d if the new bit
   -- is 1. So the solver needs no multiplier, which it could not handle;
   -- that shift and add multiplies is proven by hand in hdl/README.md. A
   -- skip of 8 steps keeps the invariant, as 8 steps that each give a
   -- quotient bit of 0 would. When the divider ends, k = N, so A = Q * B + R with R < B, and
   -- the signed results follow from those of |A| / |B|.
   --
   -- The bit counts: clz_r, ctz_r, and pop_r are those of f_ma, which is A
   -- delayed by a cycle, so once the multiplier's count is 0 they are
   -- those of A. A read of CLZ or CTZ must give a count n with a 1 at the
   -- bit it names and only 0 bits beyond it, and POPCNT the sum of the bits
   -- of A, one at a time, not in the fields of count_ones.
   --
   -- The square root: after k of its 32 steps, sqx_r holds the bits of C
   -- still to come, and the 2k bits shifted out, p, equal m + rem, with
   -- rem <= 2Q and Q < 2^k. The ghosts f_sqp and f_sqm hold p and m. m is
   -- Q squared, which the ghost forms as the root finds the bits of Q:
   -- 4m, plus 4Q + 1 if the new bit is 1, since (2Q + 1)^2 = 4Q^2 + 4Q + 1.
   -- That shift and add squares is proven by hand in hdl/README.md, as for
   -- the dividers. When the root ends, p = C, so C = Q^2 + R with
   -- R <= 2Q, which is C < (Q + 1)^2: Q = floor(sqrt(C)).
   --
   -- A read waits until its unit ends, and f_age_r counts the cycles it
   -- has waited.

   gen_formal : if G_FORMAL generate
      signal f_a : std_logic_vector(31 downto 0) := (others => '0');
      signal f_b : std_logic_vector(31 downto 0) := (others => '0');
      signal f_c : std_logic_vector(63 downto 0) := (others => '0');
      signal f_d : std_logic_vector(63 downto 0) := (others => '0');

      signal f_ma : std_logic_vector(31 downto 0) := (others => '0');
      signal f_mb : std_logic_vector(31 downto 0) := (others => '0');
      signal f_pa : std_logic_vector(31 downto 0) := (others => '0');
      signal f_pb : std_logic_vector(31 downto 0) := (others => '0');

      signal f_uq   : std_logic_vector(63 downto 0)  := (others => '0');
      signal f_up   : std_logic_vector(63 downto 0)  := (others => '0');
      signal f_um   : std_logic_vector(63 downto 0)  := (others => '0');
      signal f_sq   : std_logic_vector(63 downto 0)  := (others => '0');
      signal f_sp   : std_logic_vector(63 downto 0)  := (others => '0');
      signal f_sm   : std_logic_vector(63 downto 0)  := (others => '0');
      signal f_uq64 : std_logic_vector(127 downto 0) := (others => '0');
      signal f_up64 : std_logic_vector(127 downto 0) := (others => '0');
      signal f_um64 : std_logic_vector(127 downto 0) := (others => '0');
      signal f_sq64 : std_logic_vector(127 downto 0) := (others => '0');
      signal f_sp64 : std_logic_vector(127 downto 0) := (others => '0');
      signal f_sm64 : std_logic_vector(127 downto 0) := (others => '0');
      signal f_sqp  : std_logic_vector(63 downto 0)  := (others => '0');
      signal f_sqm  : std_logic_vector(65 downto 0)  := (others => '0');

      signal f_latch  : std_logic;                       -- The data of a read is set
      signal f_word   : std_logic_vector(4 downto 0);    -- The word it reads
      signal f_expect : std_logic_vector(31 downto 0);   -- What it must be
      signal f_last_r : std_logic_vector(31 downto 0) := (others => '0');
      signal f_left   : natural range 0 to C_STEPS64 + 1;
      signal f_bound  : natural range 0 to C_STEPS64;
      signal f_age_r  : natural range 0 to C_STEPS64 + 1 := 0;

      signal f_mul_ok    : boolean;
      signal f_udiv_ok   : boolean;
      signal f_sdiv_ok   : boolean;
      signal f_udiv64_ok : boolean;
      signal f_sdiv64_ok : boolean;
      signal f_uinv      : boolean;
      signal f_sinv      : boolean;
      signal f_uinv64    : boolean;
      signal f_sinv64    : boolean;
      signal f_bits_ok   : boolean;
      signal f_bits_held : boolean;
      signal f_sqrt_ok   : boolean;
      signal f_sqinv     : boolean;

      pure function zext(x : std_logic_vector;
                         n : natural) return std_logic_vector is
         variable r_v : std_logic_vector(n - 1 downto 0) := (others => '0');
      begin
         r_v(x'length - 1 downto 0) := x;
         return r_v;
      end function zext;

      -- The loop invariant of a divider of n by d, N bits wide, with count
      -- steps to go, and its ghosts gq, gp, and gm.
      pure function div_inv(n      : std_logic_vector;
                            d      : std_logic_vector;
                            quo    : std_logic_vector;
                            rem_in : std_logic_vector;
                            gq     : std_logic_vector;
                            gp     : std_logic_vector;
                            gm     : std_logic_vector;
                            count  : t_count) return boolean is
         constant C_N    : natural := n'length;
         constant C_ONES : std_logic_vector(C_N - 1 downto 0) := (others => '1');
         variable k_v    : natural range 0 to C_STEPS64;
         variable mask_v : std_logic_vector(C_N - 1 downto 0);
         variable rem_v  : std_logic_vector(2 * C_N - 1 downto 0);
      begin
         if count > C_N then
            return false;
         end if;
         k_v    := C_N - count;
         mask_v := C_ONES srl count;
         rem_v  := zext(rem_in, 2 * C_N);
         -- The registers hold what the ghosts say.
         if gq /= zext(quo and mask_v, 2 * C_N) or gp /= zext(n srl count, 2 * C_N) or
            (quo srl k_v) /= ((n sll k_v) srl k_v) then
            return false;
         end if;
         -- p = m + rem, without a wrap
         if gp /= gm + rem_v or gm > gp then
            return false;
         end if;
         -- With d = 0, each quotient bit is 1 and m = 0. Otherwise rem < d,
         -- and bounds on q that the signed results need.
         if d = 0 then
            return (quo and mask_v) = mask_v and gm = 0;
         elsif d = 1 then
            return rem_in < d and gm = gq;
         end if;
         return rem_in < d and gq + gq <= gm;
      end function div_inv;

      -- DEVICES.md §2 on the bit counts of a: n leading 0 bits, then a 1,
      -- or n = 32 for a = 0; the same from the other end; and the 1 bits.
      pure function clz_ok(a : std_logic_vector(31 downto 0); n : std_logic_vector) return boolean is
      begin
         if n > 32 then
            return false;
         elsif n = 32 then
            return a = 0;
         end if;
         return a(31 - to_integer(n)) = '1' and (a srl (32 - to_integer(n))) = 0;
      end function clz_ok;

      pure function ctz_ok(a : std_logic_vector(31 downto 0); n : std_logic_vector) return boolean is
      begin
         if n > 32 then
            return false;
         elsif n = 32 then
            return a = 0;
         end if;
         return a(to_integer(n)) = '1' and (a sll (32 - to_integer(n))) = 0;
      end function ctz_ok;

      pure function ones(a : std_logic_vector(31 downto 0)) return std_logic_vector is
         variable n_v : std_logic_vector(5 downto 0) := (others => '0');
      begin
         for i in 0 to 31 loop
            n_v := n_v + a(i);
         end loop;
         return n_v;
      end function ones;

      -- The loop invariant of the square root of c, with count steps to go,
      -- and its ghosts gp and gm.
      pure function sqrt_inv(c      : std_logic_vector(63 downto 0);
                             x      : std_logic_vector(63 downto 0);
                             q      : std_logic_vector(31 downto 0);
                             rem_in : std_logic_vector(33 downto 0);
                             gp     : std_logic_vector(63 downto 0);
                             gm     : std_logic_vector(65 downto 0);
                             count  : natural) return boolean is
         variable k_v : natural range 0 to C_SQSTEPS;
      begin
         if count > C_SQSTEPS then
            return false;
         end if;
         k_v := C_SQSTEPS - count;
         -- The registers hold what the ghost says, and Q < 2^k.
         if x /= (c sll (2 * k_v)) or gp /= (c srl (2 * count)) or (q srl k_v) /= 0 then
            return false;
         end if;
         -- p = m + rem, without a wrap, and rem <= 2Q
         if zext(gp, 66) /= gm + zext(rem_in, 66) or gm > zext(gp, 66) then
            return false;
         end if;
         return rem_in <= ("0" & q & "0");
      end function sqrt_inv;

      -- DEVICES.md §2 on the unsigned quotient q and remainder r of a / b,
      -- given m, q times b.
      pure function udiv_ok(a : std_logic_vector;
                            b : std_logic_vector;
                            q : std_logic_vector;
                            r : std_logic_vector;
                            m : std_logic_vector) return boolean is
         constant C_N : natural := a'length;
      begin
         if b = 0 then
            return q = (q'range => '1') and r = a;
         end if;
         return zext(a, 2 * C_N) = m + zext(r, 2 * C_N) and r < b;
      end function udiv_ok;

      -- The same on a signed quotient and remainder, given m, |q| times
      -- |b|: rounded toward zero, the remainder with the sign of the
      -- dividend, so that the magnitudes divide as unsigned numbers, and
      -- the special cases.
      pure function sdiv_ok(a : std_logic_vector;
                            b : std_logic_vector;
                            q : std_logic_vector;
                            r : std_logic_vector;
                            m : std_logic_vector) return boolean is
         constant C_N   : natural := a'length;
         constant C_MIN : std_logic_vector(C_N - 1 downto 0) := '1' & (C_N - 2 downto 0 => '0');
      begin
         if b = 0 then
            return q = (q'range => '1') and r = a;
         elsif a = C_MIN and b = (b'range => '1') then
            return q = C_MIN and r = 0;
         end if;
         return zext(absolute(a), 2 * C_N) = m + zext(absolute(r), 2 * C_N) and
                absolute(r) < absolute(b) and
                (r = 0 or r(C_N - 1) = a(C_N - 1)) and
                (q = 0 or q(C_N - 1) = (a(C_N - 1) xor b(C_N - 1)));
      end function sdiv_ok;

   begin

      p_shadow : process (clk_i)

         -- The ghosts of one cycle of a divider, as divide does it.
         procedure ghost(signal gq_s : inout std_logic_vector;
                         signal gp_s : inout std_logic_vector;
                         signal gm_s : inout std_logic_vector;
                         rem_in      : std_logic_vector;
                         quo         : std_logic_vector;
                         count       : t_count;
                         d           : std_logic_vector) is
            constant C_N    : natural := rem_in'length;
            constant C_ZERO : std_logic_vector(C_SKIP - 1 downto 0) := (others => '0');
            variable step_v : std_logic_vector(2 * C_N - 1 downto 0);
            variable q_v    : std_logic_vector(0 downto 0);
            variable p_v    : std_logic_vector(0 downto 0);
         begin
            if count >= C_SKIP and can_skip(rem_in, quo, d) then
               gq_s <= gq_s(2 * C_N - C_SKIP - 1 downto 0) & C_ZERO;
               gp_s <= gp_s(2 * C_N - C_SKIP - 1 downto 0) & quo(C_N - 1 downto C_N - C_SKIP);
               gm_s <= gm_s(2 * C_N - C_SKIP - 1 downto 0) & C_ZERO;
            elsif count /= 0 then
               step_v := divide_step(rem_in, quo, d);
               q_v(0) := step_v(0);
               p_v(0) := quo(C_N - 1);
               gq_s   <= gq_s + gq_s + q_v;
               gp_s   <= gp_s + gp_s + p_v;
               if step_v(0) = '1' then
                  gm_s <= gm_s + gm_s + zext(d, 2 * C_N);
               else
                  gm_s <= gm_s + gm_s;
               end if;
            end if;
         end procedure ghost;

         variable sq_v : std_logic_vector(65 downto 0);

      begin
         if rising_edge(clk_i) then
            f_ma <= a_r;
            f_mb <= b_r;
            f_pa <= f_ma;
            f_pb <= f_mb;

            if start_r = '1' then
               f_uq <= (others => '0');
               f_up <= (others => '0');
               f_um <= (others => '0');
               f_sq <= (others => '0');
               f_sp <= (others => '0');
               f_sm <= (others => '0');
            else
               ghost(f_uq, f_up, f_um, urem_r, uquo_r, ucount_r, b_r);
               ghost(f_sq, f_sp, f_sm, srem_r, squo_r, scount_r, sdiv_r);
            end if;

            if start64_r = '1' then
               f_uq64 <= (others => '0');
               f_up64 <= (others => '0');
               f_um64 <= (others => '0');
               f_sq64 <= (others => '0');
               f_sp64 <= (others => '0');
               f_sm64 <= (others => '0');
            else
               ghost(f_uq64, f_up64, f_um64, urem64_r, uquo64_r, ucount64_r, d_r);
               ghost(f_sq64, f_sp64, f_sm64, srem64_r, squo64_r, scount64_r, sdiv64_r);
            end if;

            if start64_r = '1' then
               f_sqp <= (others => '0');
               f_sqm <= (others => '0');
            elsif sqcount_r /= 0 then
               sq_v  := sqrt_step(sqrem_r, sqq_r, sqx_r(63 downto 62));
               f_sqp <= f_sqp(61 downto 0) & sqx_r(63 downto 62);
               if sq_v(0) = '1' then
                  f_sqm <= (f_sqm(63 downto 0) & "00") + zext(sqq_r & "01", 66);
               else
                  f_sqm <= f_sqm(63 downto 0) & "00";
               end if;
            end if;

            if accept = '1' and wb_we_i = '1' then
               -- A table of the writable words, one line each.
-- vsg_off sequential_007
               case to_integer(wb_addr_i) is
                  when 0      => f_a <= wb_data_i;
                  when 1      => f_b <= wb_data_i;
                  when 16     => f_c(31 downto 0)  <= wb_data_i;
                  when 17     => f_c(63 downto 32) <= wb_data_i;
                  when 18     => f_d(31 downto 0)  <= wb_data_i;
                  when 19     => f_d(63 downto 32) <= wb_data_i;
                  when others => null;
               end case;
-- vsg_on sequential_007
            end if;

            f_last_r <= f_expect;
            if wait_r = '1' then
               f_age_r <= f_age_r + 1;
            else
               f_age_r <= 0;
            end if;

            if rst_i = '1' then
               f_a <= (others => '0');
               f_b <= (others => '0');
               f_c <= (others => '0');
               f_d <= (others => '0');
            end if;
         end if;
      end process p_shadow;


      p_expect : process (all)
      begin
         if wait_r = '1' then
            f_word  <= wait_addr_r;
            f_latch <= '0' when must_wait(wait_addr_r) else '1';
         else
            f_word  <= wb_addr_i;
            f_latch <= '0' when must_wait(wb_addr_i) else accept and not wb_we_i;
         end if;

         case to_integer(f_word) is
            when 0        => f_expect <= f_a;
            when 1        => f_expect <= f_b;
            when 2 to 12  => f_expect <= result(f_word);
            when 16       => f_expect <= f_c(31 downto 0);
            when 17       => f_expect <= f_c(63 downto 32);
            when 18       => f_expect <= f_d(31 downto 0);
            when 19       => f_expect <= f_d(63 downto 32);
            when 20 to 30 => f_expect <= result(f_word);
            when others   => f_expect <= (others => '0');
         end case;

         -- The cycles until the unit of a waiting read ends, at most
         case to_integer(wait_addr_r) is
            when 2 to 5 | 10 to 12 =>
               f_left  <= mul_count_r;
               f_bound <= 2;

            when 6 | 7 =>
               f_left  <= scount_r + C_STEPS + 1 when start_r = '1' else scount_r;
               f_bound <= C_STEPS;

            when 8 | 9 =>
               f_left  <= ucount_r + C_STEPS + 1 when start_r = '1' else ucount_r;
               f_bound <= C_STEPS;

            when 20 to 23 =>
               f_left  <= scount64_r + C_STEPS64 + 1 when start64_r = '1' else scount64_r;
               f_bound <= C_STEPS64;

            when 28 to 30 =>
               f_left  <= sqcount_r + C_SQSTEPS + 1 when start64_r = '1' else sqcount_r;
               f_bound <= C_SQSTEPS;

            when others =>
               f_left  <= ucount64_r + C_STEPS64 + 1 when start64_r = '1' else ucount64_r;
               f_bound <= C_STEPS64;
         end case;
      end process p_expect;

      f_mul_ok    <= (mul_count_r = 2 or (f_ma = a_r and f_mb = b_r)) and
                     (mul_count_r /= 0 or (f_pa = a_r and f_pb = b_r));
      f_udiv_ok   <= udiv_ok(f_a, f_b, result("01000"), result("01001"), f_um);
      f_sdiv_ok   <= sdiv_ok(f_a, f_b, result("00110"), result("00111"), f_sm) and
                     (f_b = 0 or zext(absolute(result("00110")), 64) = f_sq);
      f_udiv64_ok <= udiv_ok(f_c, f_d, uquo64_r, urem64_r, f_um64);
      f_sdiv64_ok <= sdiv_ok(f_c, f_d, result64("010"), result64("011"), f_sm64) and
                     (f_d = 0 or zext(absolute(result64("010")), 128) = f_sq64);
      f_bits_ok   <= clz_ok(f_a, clz_r) and ctz_ok(f_a, ctz_r) and pop_r = ones(f_a);
      f_bits_held <= clz_r = count_lz(f_ma) and ctz_r = count_tz(f_ma) and pop_r = count_ones(f_ma);
      f_sqrt_ok   <= zext(f_c, 66) = f_sqm + zext(sqrem_r, 66) and sqrem_r <= ("0" & sqq_r & "0");
      f_sqinv     <= start64_r = '1' or sqrt_inv(c_r, sqx_r, sqq_r, sqrem_r, f_sqp, f_sqm, sqcount_r);
      f_uinv      <= start_r = '1' or div_inv(a_r, b_r, uquo_r, urem_r, f_uq, f_up, f_um, ucount_r);
      f_sinv      <= start_r = '1' or
                     (sdiv_r = absolute(b_r) and
                      div_inv(absolute(a_r), sdiv_r, squo_r, srem_r, f_sq, f_sp, f_sm, scount_r));
      f_uinv64    <= start64_r = '1' or
                     div_inv(c_r, d_r, uquo64_r, urem64_r, f_uq64, f_up64, f_um64, ucount64_r);
      f_sinv64    <= start64_r = '1' or
                     (sdiv64_r = absolute(d_r) and
                      div_inv(absolute(c_r), sdiv64_r, squo64_r, srem64_r, f_sq64, f_sp64, f_sm64,
                              scount64_r));

      -- psl default clock is rising_edge(clk_i);

      -- The data of each read, and the unit's operands
      -- psl f_data : assert always
      --    {f_latch and not rst_i} |=> {wb_ack_o = '1' and wb_data_o = f_last_r};
      -- psl f_mul : assert always
      --    (f_latch = '1' and f_word >= 2 and f_word <= 5) -> (f_pa = f_a and f_pb = f_b);
      -- psl f_udiv : assert always
      --    (f_latch = '1' and (f_word = 8 or f_word = 9)) ->
      --    (f_udiv_ok and zext(uquo_r, 64) = f_uq);
      -- psl f_sdiv : assert always
      --    (f_latch = '1' and (f_word = 6 or f_word = 7)) -> f_sdiv_ok;
      -- psl f_udiv64 : assert always
      --    (f_latch = '1' and f_word >= 24 and f_word <= 27) ->
      --    (f_udiv64_ok and zext(uquo64_r, 128) = f_uq64);
      -- psl f_sdiv64 : assert always
      --    (f_latch = '1' and f_word >= 20 and f_word <= 23) -> f_sdiv64_ok;
      -- psl f_bits : assert always
      --    (f_latch = '1' and f_word >= 10 and f_word <= 12) -> f_bits_ok;
      -- psl f_sqrt : assert always
      --    (f_latch = '1' and f_word >= 28 and f_word <= 30) -> f_sqrt_ok;

      -- A read waits no longer than its unit takes
      -- psl f_age : assert always wait_r = '1' -> f_age_r + f_left <= f_bound;
      -- psl c_long : cover {wait_r = '1' and wait_addr_r = 9 and f_age_r = C_STEPS - 1};
      -- psl c_long64 : cover {wait_r = '1' and wait_addr_r = 20 and f_age_r = C_STEPS64 - 1};
      -- psl c_sqrt : cover {wait_r = '1' and wait_addr_r = 28 and f_age_r = C_SQSTEPS - 1};

      -- The invariants
      -- psl f_operands : assert always
      --    rst_i = '0' -> (a_r = f_a and b_r = f_b and c_r = f_c and d_r = f_d);
      -- psl f_mul_inv : assert always rst_i = '0' -> f_mul_ok;
      -- psl f_udiv_inv : assert always rst_i = '0' -> f_uinv;
      -- psl f_sdiv_inv : assert always rst_i = '0' -> f_sinv;
      -- psl f_udiv64_inv : assert always rst_i = '0' -> f_uinv64;
      -- psl f_sdiv64_inv : assert always rst_i = '0' -> f_sinv64;
      -- psl f_bits_inv : assert always f_bits_held;
      -- psl f_sqrt_inv : assert always rst_i = '0' -> f_sqinv;
      -- psl f_wait : assert always
      --    wait_r = '1' -> (start_r = '0' and start64_r = '0' and
      --                     ((wait_addr_r >= 2 and wait_addr_r <= 12) or
      --                      (wait_addr_r >= 20 and wait_addr_r <= 30)));
   end generate gen_formal;

end architecture synthesis;
