-- The timer of SYSTEM.md §4: 16 words of I/O that raise an interrupt request
-- once every P cycles.
--
--   0  TIMER_PERIOD   1  TIMER_COUNT   2  TIMER_VECTOR   3-15  read 0
--
-- THEORY OF OPERATION
-- While the period P is not 0, the counter decreases by one in each cycle
-- with tick_i high, the cycle of a write to TIMER_PERIOD included. When it
-- reaches 0, the timer raises a request on its valid/ready port, with the
-- vector as it is at that time, and loads P into the counter again. A write
-- to TIMER_PERIOD sets both P and the counter.
--
-- A request stays raised, with its vector, until the core takes it with
-- irq_ready_i. A new request raised before then merges with it, as ISA.md
-- §7.1 says, and the raised request keeps its vector. Stopping the timer
-- leaves a raised request as it is. While no request is raised, irq_ready_i
-- has no effect, so the core's ready may go to more than one device.
--
-- The port is a pipelined Wishbone slave. It never stalls, and it
-- acknowledges each request in the cycle after it accepts it. A read
-- returns the word as it is in the cycle the read is accepted.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) STB is high only for requests to the timer: the bus decoder decodes
--    the address bits above bit 3.
-- b) tick_i is high once per cycle that the timer counts. A system ties it
--    to '1', so that the timer counts clock cycles. The tests raise it once
--    per step of the core, so that it counts as the emulator does.
--
-- RESET
-- Synchronous. It sets P, the counter, and the vector to 0, drops a raised
-- request, and drops any ACK owed.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

entity timer is
   port (
      clk_i        : in  std_logic;
      rst_i        : in  std_logic;

      -- High in each cycle that the timer counts
      tick_i       : in  std_logic;

      wb_cyc_i     : in  std_logic;
      wb_stb_i     : in  std_logic;
      wb_stall_o   : out std_logic;
      wb_ack_o     : out std_logic                     := '0';
      wb_we_i      : in  std_logic;
      wb_addr_i    : in  std_logic_vector(3 downto 0);
      wb_data_i    : in  std_logic_vector(31 downto 0);
      wb_data_o    : out std_logic_vector(31 downto 0) := (others => '0');

      -- Interrupt request, for the core's IRQ port
      irq_valid_o  : out std_logic                     := '0';
      irq_ready_i  : in  std_logic;
      irq_vector_o : out std_logic_vector(7 downto 0)  := (others => '0')
   );
end entity timer;

architecture synthesis of timer is

   signal period_r : std_logic_vector(31 downto 0) := (others => '0');
   signal count_r  : std_logic_vector(31 downto 0) := (others => '0');
   signal vector_r : std_logic_vector(7 downto 0)  := (others => '0');

   signal accept : std_logic;

begin

   accept     <= wb_cyc_i and wb_stb_i;
   wb_stall_o <= '0';


   p_timer : process (clk_i)
      variable period_v : std_logic_vector(31 downto 0);
      variable count_v  : std_logic_vector(31 downto 0);
      variable vector_v : std_logic_vector(7 downto 0);
   begin
      if rising_edge(clk_i) then
         wb_ack_o <= accept;

         if accept = '1' and wb_we_i = '0' then
            case wb_addr_i is
               when X"0"   => wb_data_o <= period_r;
               when X"1"   => wb_data_o <= count_r;
               when X"2"   => wb_data_o <= X"000000" & vector_r;
               when others => wb_data_o <= (others => '0');
            end case;
         end if;

         if irq_ready_i = '1' then
            irq_valid_o <= '0';
         end if;

         -- A write takes effect before the count of its own cycle.
         period_v := period_r;
         count_v  := count_r;
         vector_v := vector_r;
         if accept = '1' and wb_we_i = '1' then
            case wb_addr_i is
               when X"0" =>
                  period_v := wb_data_i;
                  count_v  := wb_data_i;

               when X"2" =>
                  vector_v := wb_data_i(7 downto 0);

               when others =>
                  null;
            end case;
         end if;

         if tick_i = '1' and period_v /= 0 then
            count_v := count_v - 1;
            if count_v = 0 then
               count_v := period_v;
               -- A request still raised keeps its vector.
               if irq_valid_o = '0' or irq_ready_i = '1' then
                  irq_valid_o  <= '1';
                  irq_vector_o <= vector_v;
               end if;
            end if;
         end if;

         period_r <= period_v;
         count_r  <= count_v;
         vector_r <= vector_v;

         if rst_i = '1' then
            wb_ack_o     <= '0';
            period_r     <= (others => '0');
            count_r      <= (others => '0');
            vector_r     <= (others => '0');
            irq_valid_o  <= '0';
            irq_vector_o <= (others => '0');
         end if;
      end if;
   end process p_timer;

end architecture synthesis;
