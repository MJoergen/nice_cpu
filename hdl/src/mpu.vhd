-- The math unit, MPU, of ISA.md §8.4: 32 words of I/O that multiply and
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
-- A write to A or B starts a new computation, which takes 33 cycles. Three
-- units run side by side, one bit per cycle:
-- * A shift-and-add multiplier forms the unsigned product of A and B. The
--   signed product has the same low word. Its high word is the unsigned
--   one, minus B if A is negative, and minus A if B is negative.
-- * A restoring divider divides A by B, unsigned.
-- * A second one divides |A| by |B|. The signed quotient is negated when
--   A and B differ in sign, and the signed remainder when A is negative.
-- A restoring divider with B = 0 gives Q = 0xFFFFFFFF and R = A, which is
-- what ISA.md §8.4 asks for, except for the signed quotient with A < 0,
-- which is set to 0xFFFFFFFF on its own. -2^31 / -1 needs no special case:
-- |A| / |B| = 0x80000000, and negating it gives 0x80000000 again.
--
-- A write to C or D starts a computation of C / D in the same way, with two
-- 64-bit dividers, which takes 65 cycles. The two halves of the MPU are
-- independent: a write to one half does not restart the other.
--
-- The port is a pipelined Wishbone slave. It acknowledges each request in
-- the cycle after it accepts it, except a read of a result while a
-- computation runs. That read is acknowledged in the cycle after the
-- computation ends, and STALL is high until then, so that no other request
-- is accepted in between. A read of an operand or a spare word never waits.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) The master holds STB and the request while STALL is high.
-- b) STB is high only for requests to the MPU: the bus decoder decodes the
--    address. Offsets 0-15 are at 0xFFFFFF10-0xFFFFFF1F, and 16-31 at
--    0xFFFFFF20-0xFFFFFF2F, so the offset is address bit 5 & bits 3..0.
--
-- RESET
-- Synchronous. It sets A, B, C, and D to 0, as ISA.md §8.4 requires, and drops
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

   signal a_r : std_logic_vector(31 downto 0) := (others => '0');
   signal b_r : std_logic_vector(31 downto 0) := (others => '0');

   -- A write to A or B was accepted, and the computation starts next cycle.
   signal start_r : std_logic                  := '1';
   -- The steps still to run.
   signal count_r : natural range 0 to C_STEPS := 0;

   -- The multiplier. The high word holds the partial sum. The low word
   -- starts as B, which shifts out to the right as the product shifts in.
   signal prod_r : std_logic_vector(63 downto 0) := (others => '0');

   -- The two dividers. The quotient register starts as the dividend, which
   -- shifts out to the left as the quotient shifts in.
   signal uquo_r : std_logic_vector(31 downto 0) := (others => '0');
   signal urem_r : std_logic_vector(31 downto 0) := (others => '0');
   signal squo_r : std_logic_vector(31 downto 0) := (others => '0');
   signal srem_r : std_logic_vector(31 downto 0) := (others => '0');

   -- The 64-bit half: the operands, and the same two dividers, 64 bits wide.
   signal c_r       : std_logic_vector(63 downto 0) := (others => '0');
   signal d_r       : std_logic_vector(63 downto 0) := (others => '0');
   signal start64_r : std_logic                    := '1';
   signal count64_r : natural range 0 to C_STEPS64 := 0;
   signal uquo64_r  : std_logic_vector(63 downto 0) := (others => '0');
   signal urem64_r  : std_logic_vector(63 downto 0) := (others => '0');
   signal squo64_r  : std_logic_vector(63 downto 0) := (others => '0');
   signal srem64_r  : std_logic_vector(63 downto 0) := (others => '0');

   -- A read of a result waits for the computation.
   signal wait_r      : std_logic                    := '0';
   signal wait_addr_r : std_logic_vector(4 downto 0) := (others => '0');

   signal busy   : std_logic;
   signal busy64 : std_logic;
   signal accept : std_logic;

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
      return (busy = '1' and addr >= 2 and addr <= 9) or
             (busy64 = '1' and addr >= 20 and addr <= 27);
   end function must_wait;

   -- The value of word addr, once the computation has ended.
   impure function result(addr : std_logic_vector(4 downto 0)) return std_logic_vector is
      variable hi_v : std_logic_vector(31 downto 0);
      variable w_v  : std_logic_vector(63 downto 0);
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
            hi_v := prod_r(63 downto 32);
            if a_r(31) = '1' then
               hi_v := hi_v - b_r;
            end if;
            if b_r(31) = '1' then
               hi_v := hi_v - a_r;
            end if;
            return hi_v;

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

   busy       <= '1' when start_r = '1' or count_r /= 0 else '0';
   busy64     <= '1' when start64_r = '1' or count64_r /= 0 else '0';
   accept     <= wb_cyc_i and wb_stb_i and not wait_r;
   wb_stall_o <= wait_r;


   p_compute : process (clk_i)
      variable sum_v : std_logic_vector(32 downto 0);
      variable div_v   : std_logic_vector(63 downto 0);
      variable div64_v : std_logic_vector(127 downto 0);
   begin
      if rising_edge(clk_i) then
         if start_r = '1' then
            prod_r  <= X"00000000" & b_r;
            uquo_r  <= a_r;
            urem_r  <= (others => '0');
            squo_r  <= absolute(a_r);
            srem_r  <= (others => '0');
            count_r <= C_STEPS;
            start_r <= '0';
         elsif count_r /= 0 then
            sum_v := '0' & prod_r(63 downto 32);
            if prod_r(0) = '1' then
               sum_v := sum_v + a_r;
            end if;
            prod_r <= sum_v & prod_r(31 downto 1);

            div_v  := divide_step(urem_r, uquo_r, b_r);
            urem_r <= div_v(63 downto 32);
            uquo_r <= div_v(31 downto 0);

            div_v  := divide_step(srem_r, squo_r, absolute(b_r));
            srem_r <= div_v(63 downto 32);
            squo_r <= div_v(31 downto 0);

            count_r <= count_r - 1;
         end if;

         if start64_r = '1' then
            uquo64_r  <= c_r;
            urem64_r  <= (others => '0');
            squo64_r  <= absolute(c_r);
            srem64_r  <= (others => '0');
            count64_r <= C_STEPS64;
            start64_r <= '0';
         elsif count64_r /= 0 then
            div64_v  := divide_step(urem64_r, uquo64_r, d_r);
            urem64_r <= div64_v(127 downto 64);
            uquo64_r <= div64_v(63 downto 0);

            div64_v  := divide_step(srem64_r, squo64_r, absolute(d_r));
            srem64_r <= div64_v(127 downto 64);
            squo64_r <= div64_v(63 downto 0);

            count64_r <= count64_r - 1;
         end if;

         if accept = '1' and wb_we_i = '1' then
            case to_integer(wb_addr_i) is
               when 0      => a_r <= wb_data_i; start_r <= '1';
               when 1      => b_r <= wb_data_i; start_r <= '1';
               when 16     => c_r(31 downto 0)  <= wb_data_i; start64_r <= '1';
               when 17     => c_r(63 downto 32) <= wb_data_i; start64_r <= '1';
               when 18     => d_r(31 downto 0)  <= wb_data_i; start64_r <= '1';
               when 19     => d_r(63 downto 32) <= wb_data_i; start64_r <= '1';
               when others => null;
            end case;
         end if;

         if rst_i = '1' then
            a_r       <= (others => '0');
            b_r       <= (others => '0');
            c_r       <= (others => '0');
            d_r       <= (others => '0');
            start_r   <= '1';
            count_r   <= 0;
            start64_r <= '1';
            count64_r <= 0;
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
