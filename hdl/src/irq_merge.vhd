-- The merge of two sources of IRQ into the core's one IRQ port, in the
-- order of DEVICES.md §4: the timer's source first, then the console's.
--
-- THEORY OF OPERATION
-- The core sees a request while either source raises one. Its vector is
-- the first source's while that one raises a request, and else the
-- second's. The core's ready goes to the source whose vector it sees, so
-- each source holds its own request until the core takes that one, and
-- the requests of the two never merge (ISA.md §7.1).
--
-- So the vector may change while the core's valid stays high: when the
-- first source raises a request while the second's waits, the core sees
-- the first's from then on. The cores take the vector of the cycle of
-- ready, and allow that for IRQ (src/pipeline.vhd, contract b).
--
-- All paths are combinational, so a request reaches the core in the cycle
-- the source raises it, as without the merge.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) Each source holds its valid, and its vector, until its ready, and
--    its valid does not depend combinationally on its ready.
--
-- RESET
-- None: the unit has no state.

library ieee;
   use ieee.std_logic_1164.all;

entity irq_merge is
   port (
      -- The first source, the timer's
      first_valid_i   : in  std_logic;
      first_ready_o   : out std_logic;
      first_vector_i  : in  std_logic_vector(7 downto 0);

      -- The second source, the console's
      second_valid_i  : in  std_logic;
      second_ready_o  : out std_logic;
      second_vector_i : in  std_logic_vector(7 downto 0);

      -- The core's IRQ port
      irq_valid_o     : out std_logic;
      irq_ready_i     : in  std_logic;
      irq_vector_o    : out std_logic_vector(7 downto 0)
   );
end entity irq_merge;

architecture synthesis of irq_merge is

begin

   irq_valid_o    <= first_valid_i or second_valid_i;
   irq_vector_o   <= first_vector_i when first_valid_i = '1' else
                     second_vector_i;
   first_ready_o  <= irq_ready_i and first_valid_i;
   second_ready_o <= irq_ready_i and second_valid_i and not first_valid_i;

end architecture synthesis;
