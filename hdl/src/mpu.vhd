-- The math unit, MPU, of ISA.md §8.4: 16 words of I/O that multiply and
-- divide 32-bit integers, signed and unsigned.
--
--   0  A        3  SMUL_HI  6  SDIV_Q   9  UDIV_R
--   1  B        4  UMUL_LO  7  SDIV_R   10-15  read 0
--   2  SMUL_LO  5  UMUL_HI  8  UDIV_Q
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
-- The port is a pipelined Wishbone slave. It acknowledges each request in
-- the cycle after it accepts it, except a read of a result while a
-- computation runs. That read is acknowledged in the cycle after the
-- computation ends, and STALL is high until then, so that no other request
-- is accepted in between. A read of A, B, or a spare word never waits.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) The master holds STB and the request while STALL is high.
-- b) STB is high only for requests to the MPU: the bus decoder decodes the
--    address bits above bit 3.
--
-- RESET
-- Synchronous. It sets A and B to 0, as ISA.md §8.4 requires, and drops
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
      wb_addr_i  : in  std_logic_vector(3 downto 0);
      wb_data_i  : in  std_logic_vector(31 downto 0);
      wb_data_o  : out std_logic_vector(31 downto 0) := (others => '0')
   );
end entity mpu;

architecture synthesis of mpu is

   constant C_STEPS : natural := 32;

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

   -- A read of a result waits for the computation.
   signal wait_r      : std_logic                    := '0';
   signal wait_addr_r : std_logic_vector(3 downto 0) := (others => '0');

   signal busy   : std_logic;
   signal accept : std_logic;

   pure function absolute(x : std_logic_vector(31 downto 0)) return std_logic_vector is
   begin
      if x(31) = '1' then
         return 0 - x;
      end if;
      return x;
   end function absolute;

   -- One step of a restoring divider, on the remainder and the
   -- quotient register. It returns the new remainder & quotient register.
   pure function divide_step(rem_in : std_logic_vector(31 downto 0);
                             quo_in : std_logic_vector(31 downto 0);
                             d      : std_logic_vector(31 downto 0)) return std_logic_vector is
      variable shifted_v : std_logic_vector(32 downto 0) := rem_in & quo_in(31);
   begin
      if shifted_v >= ('0' & d) then
         shifted_v := shifted_v - ('0' & d);
         return shifted_v(31 downto 0) & quo_in(30 downto 0) & '1';
      end if;
      return shifted_v(31 downto 0) & quo_in(30 downto 0) & '0';
   end function divide_step;

   -- The value of word addr, once the computation has ended.
   impure function result(addr : std_logic_vector(3 downto 0)) return std_logic_vector is
      variable hi_v : std_logic_vector(31 downto 0);
   begin
      case addr is
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
            if b_r = 0 then
               return X"FFFFFFFF";
            elsif (a_r(31) xor b_r(31)) = '1' then
               return 0 - squo_r;
            end if;
            return squo_r;

         when X"7" =>
            if a_r(31) = '1' then
               return 0 - srem_r;
            end if;
            return srem_r;

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
   accept     <= wb_cyc_i and wb_stb_i and not wait_r;
   wb_stall_o <= wait_r;


   p_compute : process (clk_i)
      variable sum_v : std_logic_vector(32 downto 0);
      variable div_v : std_logic_vector(63 downto 0);
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

         if accept = '1' and wb_we_i = '1' then
            case wb_addr_i is
               when X"0"   => a_r <= wb_data_i; start_r <= '1';
               when X"1"   => b_r <= wb_data_i; start_r <= '1';
               when others => null;
            end case;
         end if;

         if rst_i = '1' then
            a_r     <= (others => '0');
            b_r     <= (others => '0');
            start_r <= '1';
            count_r <= 0;
         end if;
      end if;
   end process p_compute;


   p_bus : process (clk_i)
   begin
      if rising_edge(clk_i) then
         wb_ack_o <= '0';

         if wait_r = '1' and busy = '0' then
            wb_ack_o  <= '1';
            wb_data_o <= result(wait_addr_r);
            wait_r    <= '0';
         end if;

         if accept = '1' then
            if wb_we_i = '1' then
               wb_ack_o <= '1';
            elsif busy = '1' and wb_addr_i >= 2 and wb_addr_i <= 9 then
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
