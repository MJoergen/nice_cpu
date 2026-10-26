-- Formal properties of a pipelined Wishbone B4 slave port that never
-- stalls and answers in the next cycle, for SymbiYosys. It watches the
-- port and drives nothing.
--
-- THEORY OF OPERATION
-- The devices with registers only (the timer, the performance counters,
-- and the fetch statistics) answer every request in the cycle after it.
-- The checker asserts that the port never stalls, that ACK is high exactly
-- in the cycle after one with CYC and STB high, and that it is low after a
-- reset. So each request gets one ACK, in order. It assumes nothing.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- None.

library ieee;
   use ieee.std_logic_1164.all;

entity wb_slave_check is
   port (
      clk_i   : in  std_logic;
      rst_i   : in  std_logic;
      cyc_i   : in  std_logic;
      stb_i   : in  std_logic;
      stall_i : in  std_logic;
      ack_i   : in  std_logic
   );
end entity wb_slave_check;

architecture synthesis of wb_slave_check is

begin

   -- psl default clock is rising_edge(clk_i);

   -- psl f_no_stall : assert always not stall_i;
   -- psl f_ack : assert always
   --    {not rst_i} |=> {ack_i = (prev(cyc_i) and prev(stb_i))};
   -- psl f_ack_reset : assert always rst_i |=> not ack_i;

end architecture synthesis;
