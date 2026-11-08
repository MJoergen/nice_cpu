-- The clock of the time of day of SYSTEM.md §10: 4 words of I/O with the
-- seconds since the Unix epoch, 64 bits, and the microseconds within the
-- second.
--
--   0  CLOCK_USEC   1  CLOCK_SEC_LO   2  CLOCK_SEC_HI   3  CLOCK_STATUS
--
-- THEORY OF OPERATION
-- The clock counts in every cycle, whatever the core does, so it runs on
-- while the core is held, paused, halted, or waiting. An accumulator adds
-- 1000000 in each cycle. When the sum reaches G_CLK_HZ, the clock counts
-- one microsecond and the accumulator keeps the sum less G_CLK_HZ, as the
-- microsecond counter of src/perf.vhd does. After 999999 the microseconds
-- go to 0 and the seconds count one. The seconds wrap from 2^64 - 1 to 0.
--
-- A read of CLOCK_USEC returns the microseconds as they are in the cycle
-- the read is accepted, and copies the seconds of that cycle into the
-- snapshot, which reads of CLOCK_SEC_LO and CLOCK_SEC_HI return. So the
-- three give one time, also when a second ends between the reads.
-- CLOCK_STATUS returns "set" in bit 0.
--
-- A write of CLOCK_SEC_LO or CLOCK_SEC_HI stages that half of the
-- seconds. A write of CLOCK_USEC sets the clock to the staged seconds and
-- the microseconds written, or 999999 for a value of 1000000 or more,
-- clears the accumulator, and sets "set". It takes the place of the count
-- of its cycle. A write of CLOCK_STATUS clears "set".
--
-- The port is a pipelined Wishbone slave. It never stalls, and it
-- acknowledges each request in the cycle after it accepts it.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) STB is high only for requests to the clock, 0xFFFFFF46-0xFFFFFF49,
--    and wb_addr_i is the word within it, the address less 0xFFFFFF46.
--    The four words cross a boundary of four, so a bus decoder compares
--    bits 3..0 of the address with 6 to 9, and gives bits 1..0 xor "10".
-- b) rst_i is the reset of the system, at power-up or when the FPGA is
--    loaded, and not the reset of the core that a start over the debug
--    link gives (doc/DEBUG.md §6), which must leave the clock.
--
-- RESET
-- Synchronous. It sets the clock, the snapshot, the staged seconds, the
-- accumulator, and "set" to 0, and drops any ACK owed.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

entity tod is
   generic (
      -- The frequency of clk_i in hertz, at least 1000000. It sets the
      -- rate of the clock.
      G_CLK_HZ : natural range 1000000 to 500000000 := 100000000
   );
   port (
      clk_i      : in  std_logic;
      rst_i      : in  std_logic;

      wb_cyc_i   : in  std_logic;
      wb_stb_i   : in  std_logic;
      wb_stall_o : out std_logic;
      wb_ack_o   : out std_logic                     := '0';
      wb_we_i    : in  std_logic;
      wb_addr_i  : in  std_logic_vector(1 downto 0);
      wb_data_i  : in  std_logic_vector(31 downto 0);
      wb_data_o  : out std_logic_vector(31 downto 0) := (others => '0')
   );
end entity tod;

architecture synthesis of tod is

   constant C_USEC_MAX : std_logic_vector(19 downto 0) := to_slv(999999, 20);

   signal usec_r  : std_logic_vector(19 downto 0) := (others => '0');
   signal sec_r   : std_logic_vector(63 downto 0) := (others => '0');
   signal snap_r  : std_logic_vector(63 downto 0) := (others => '0');
   signal stage_r : std_logic_vector(63 downto 0) := (others => '0');
   signal set_r   : std_logic                     := '0';

   -- The microseconds so far in the current one, scaled by G_CLK_HZ
   signal frac_r : natural range 0 to G_CLK_HZ - 1 := 0;

   signal accept : std_logic;

begin

   accept     <= wb_cyc_i and wb_stb_i;
   wb_stall_o <= '0';

   -- The microseconds never reach 1000000. Without this the k-induction of
   -- formal/tod.sby starts from states that reset never leads to.
   -- psl default clock is rising_edge(clk_i);
   -- psl f_usec : assert always usec_r <= C_USEC_MAX;


   p_tod : process (clk_i)
      variable frac_v : natural;
   begin
      if rising_edge(clk_i) then
         wb_ack_o <= accept;

         if accept = '1' and wb_we_i = '0' then
            case wb_addr_i is
               when "00" =>
                  wb_data_o <= X"000" & usec_r;
                  snap_r    <= sec_r;

               when "01" =>
                  wb_data_o <= snap_r(31 downto 0);

               when "10" =>
                  wb_data_o <= snap_r(63 downto 32);

               when others =>
                  wb_data_o <= (0 => set_r, others => '0');
            end case;
         end if;

         frac_v := frac_r + 1000000;
         if frac_v >= G_CLK_HZ then
            frac_r <= frac_v - G_CLK_HZ;
            if usec_r = C_USEC_MAX then
               usec_r <= (others => '0');
               sec_r  <= sec_r + 1;
            else
               usec_r <= usec_r + 1;
            end if;
         else
            frac_r <= frac_v;
         end if;

         if accept = '1' and wb_we_i = '1' then
            case wb_addr_i is
               when "00" =>
                  sec_r  <= stage_r;
                  frac_r <= 0;
                  set_r  <= '1';
                  if wb_data_i > C_USEC_MAX then
                     usec_r <= C_USEC_MAX;
                  else
                     usec_r <= wb_data_i(19 downto 0);
                  end if;

               when "01" =>
                  stage_r(31 downto 0) <= wb_data_i;

               when "10" =>
                  stage_r(63 downto 32) <= wb_data_i;

               when others =>
                  set_r <= '0';
            end case;
         end if;

         if rst_i = '1' then
            wb_ack_o <= '0';
            usec_r   <= (others => '0');
            sec_r    <= (others => '0');
            snap_r   <= (others => '0');
            stage_r  <= (others => '0');
            set_r    <= '0';
            frac_r   <= 0;
         end if;
      end if;
   end process p_tod;

end architecture synthesis;
