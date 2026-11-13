-- The console's receive interrupt of DEVICES.md §1.9: one word of I/O,
-- CONSOLE_IRQ, that raises an interrupt request when input comes.
--
--   bits 7..0  the vector v   bit 8  the enable   bits 31..9  read 0
--
-- THEORY OF OPERATION
-- The system tells the unit about its console's input with two signals.
-- entered_i is high for one cycle when a byte enters the input while no
-- byte waits, or when the input ends. waits_i is high while a byte waits
-- or the input has ended. A board drives them from its input FIFO; the
-- simulation memory, whose read waits for its byte, raises entered_i in
-- the cycle a read takes a byte, as the next byte or the end enters then,
-- and holds waits_i high.
--
-- While the enable is 1, the unit raises a request on its valid/ready
-- port, with the vector v, in the cycle after entered_i, and in the cycle
-- after a write that sets the enable from 0 to 1 while waits_i is high. A
-- write in the cycle of entered_i takes effect first, so the request has
-- the enable and the vector written.
--
-- A request stays raised, with its vector, until the core takes it with
-- irq_ready_i. A new request raised before then merges with it, as ISA.md
-- §7.1 says, and the raised request keeps its vector. A write of the
-- enable to 0 leaves a raised request as it is. While no request is
-- raised, irq_ready_i has no effect.
--
-- The port is a pipelined Wishbone slave of one word. It never stalls, and
-- it acknowledges each request in the cycle after it accepts it. A read
-- returns the word as it is in the cycle the read is accepted.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) STB is high only for requests to CONSOLE_IRQ: the bus decoder decodes
--    every address bit.
-- b) entered_i is high for one cycle for each byte that enters an empty
--    input, and for the end of the input. A system drops the input that
--    comes while the core is held or has halted (DEVICES.md §8), and then
--    raises no entered_i for it.
--
-- RESET
-- Synchronous. It sets the vector and the enable to 0, drops a raised
-- request, and drops any ACK owed.

library ieee;
   use ieee.std_logic_1164.all;

entity console_irq is
   port (
      clk_i        : in  std_logic;
      rst_i        : in  std_logic;

      -- The console's input: a byte or the end entered, and one waits
      entered_i    : in  std_logic;
      waits_i      : in  std_logic;

      wb_cyc_i     : in  std_logic;
      wb_stb_i     : in  std_logic;
      wb_stall_o   : out std_logic;
      wb_ack_o     : out std_logic                     := '0';
      wb_we_i      : in  std_logic;
      wb_data_i    : in  std_logic_vector(31 downto 0);
      wb_data_o    : out std_logic_vector(31 downto 0) := (others => '0');

      -- Interrupt request, for the core's IRQ port
      irq_valid_o  : out std_logic                     := '0';
      irq_ready_i  : in  std_logic;
      irq_vector_o : out std_logic_vector(7 downto 0)  := (others => '0')
   );
end entity console_irq;

architecture synthesis of console_irq is

   signal vector_r : std_logic_vector(7 downto 0) := (others => '0');
   signal enable_r : std_logic                    := '0';

   signal accept : std_logic;

begin

   accept     <= wb_cyc_i and wb_stb_i;
   wb_stall_o <= '0';


   p_console_irq : process (clk_i)
      variable vector_v : std_logic_vector(7 downto 0);
      variable enable_v : std_logic;
      variable raise_v  : std_logic;
   begin
      if rising_edge(clk_i) then
         wb_ack_o <= accept;

         if accept = '1' and wb_we_i = '0' then
            wb_data_o <= X"00000" & "000" & enable_r & vector_r;
         end if;

         if irq_ready_i = '1' then
            irq_valid_o <= '0';
         end if;

         -- A write takes effect before the input of its own cycle.
         vector_v := vector_r;
         enable_v := enable_r;
         raise_v  := '0';
         if accept = '1' and wb_we_i = '1' then
            vector_v := wb_data_i(7 downto 0);
            enable_v := wb_data_i(8);
            raise_v  := enable_v and not enable_r and waits_i;
         end if;
         raise_v := raise_v or (enable_v and entered_i);

         -- A request still raised keeps its vector.
         if raise_v = '1' and (irq_valid_o = '0' or irq_ready_i = '1') then
            irq_valid_o  <= '1';
            irq_vector_o <= vector_v;
         end if;

         vector_r <= vector_v;
         enable_r <= enable_v;

         if rst_i = '1' then
            wb_ack_o     <= '0';
            vector_r     <= (others => '0');
            enable_r     <= '0';
            irq_valid_o  <= '0';
            irq_vector_o <= (others => '0');
         end if;
      end if;
   end process p_console_irq;

end architecture synthesis;
