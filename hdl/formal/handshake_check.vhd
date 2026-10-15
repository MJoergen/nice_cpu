-- Formal properties of a valid/ready port that takes requests, in the style
-- of the AXI handshake, for SymbiYosys. It watches the port and drives
-- nothing.
--
-- THEORY OF OPERATION
-- A request is taken in a cycle with VALID and READY both high. The checker
-- assumes the source side of the handshake: once VALID is high, it stays
-- high, with DATA unchanged, until the request is taken. It asserts that the
-- port raises READY only for a request, and only outside reset. The cover
-- shows that a request can be taken.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) The source may drop VALID in a cycle with rst_i high.

library ieee;
   use ieee.std_logic_1164.all;

entity handshake_check is
   generic (
      G_DATA_SIZE : positive
   );
   port (
      clk_i   : in  std_logic;
      rst_i   : in  std_logic;
      valid_i : in  std_logic;
      ready_i : in  std_logic;
      data_i  : in  std_logic_vector(G_DATA_SIZE - 1 downto 0)
   );
end entity handshake_check;

architecture synthesis of handshake_check is

begin

   -- psl default clock is rising_edge(clk_i);

   -- The source
   -- psl f_valid_hold : assume always
   --    {valid_i and not ready_i and not rst_i} |=>
   --    {rst_i = '1' or (valid_i = '1' and stable(data_i))};

   -- The port
   -- psl f_ready_valid : assert always ready_i -> valid_i;
   -- psl f_ready_reset : assert always rst_i -> not ready_i;

   -- psl c_take : cover {valid_i and ready_i};

end architecture synthesis;
