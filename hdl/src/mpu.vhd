-- The math unit, MPU, of SYSTEM.md §2: 32 words of I/O that multiply and
-- divide 32-bit integers, and divide 64-bit integers, signed and unsigned.
--
--   0  A        3  SMUL_HI  6  SDIV_Q   9  UDIV_R
--   1  B        4  UMUL_LO  7  SDIV_R   10-15  read 0
--   2  SMUL_LO  5  UMUL_HI  8  UDIV_Q
--
--   16, 17  C            22, 23  SDIV64_R     28-31  read 0
--   18, 19  D            24, 25  UDIV64_Q
--   20, 21  SDIV64_Q     26, 27  UDIV64_R
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
-- what SYSTEM.md §2 asks for, except for the signed quotient with A < 0,
-- which is set to 0xFFFFFFFF on its own. -2^31 / -1 needs no special case:
-- |A| / |B| = 0x80000000, and negating it gives 0x80000000 again.
--
-- A write to C or D starts a computation of C / D in the same way, with two
-- 64-bit dividers, which takes 65 cycles at most. The two halves of the MPU are
-- independent: a write to one half does not restart the other.
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
-- Synchronous. It sets A, B, C, and D to 0, as SYSTEM.md §2 requires, and drops
-- any ACK owed.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

entity mpu is
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

   -- A read of a result waits for the computation.
   signal wait_r      : std_logic                    := '0';
   signal wait_addr_r : std_logic_vector(4 downto 0) := (others => '0');

   signal mul_busy    : std_logic;
   signal udiv_busy   : std_logic;
   signal sdiv_busy   : std_logic;
   signal udiv64_busy : std_logic;
   signal sdiv64_busy : std_logic;
   signal accept      : std_logic;

   -- The functions below take vectors of any width N, indexed N-1 downto 0.

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
         when others => return X"0000000000000000";
      end case;
   end function result64;

   -- Whether a read of word addr must wait for a computation.
   impure function must_wait(addr : std_logic_vector(4 downto 0)) return boolean is
   begin
      case to_integer(addr) is
         when 2 to 5   => return mul_busy = '1';
         when 6 | 7    => return sdiv_busy = '1';
         when 8 | 9    => return udiv_busy = '1';
         when 20 to 23 => return sdiv64_busy = '1';
         when 24 to 27 => return udiv64_busy = '1';
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
            start64_r  <= '0';
         else
            divide(urem64_r, uquo64_r, ucount64_r, d_r);
            divide(srem64_r, squo64_r, scount64_r, sdiv64_r);
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

end architecture synthesis;
