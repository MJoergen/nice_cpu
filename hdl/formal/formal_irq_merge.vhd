-- The merge of two sources of IRQ with checks of its ports, for
-- SymbiYosys. Every input is free, under the rules of the handshake.
--
-- THEORY OF OPERATION
-- Each source holds its valid and its vector until its ready, and the
-- core raises ready only for a request it sees. Then the core's valid
-- stays high until its ready, ready goes to one source only, the first
-- one whenever it raises a request, and the core takes the vector of the
-- source that gets the ready. The covers show the second source's request
-- passed over by the first's, and then taken.
--
-- RESET
-- The unit has none, and the rules hold from the first cycle.

library ieee;
   use ieee.std_logic_1164.all;

entity formal_irq_merge is
   port (
      clk_i           : in  std_logic;
      first_valid_i   : in  std_logic;
      first_vector_i  : in  std_logic_vector(7 downto 0);
      second_valid_i  : in  std_logic;
      second_vector_i : in  std_logic_vector(7 downto 0);
      irq_ready_i     : in  std_logic
   );
end entity formal_irq_merge;

architecture synthesis of formal_irq_merge is

   signal first_ready  : std_logic;
   signal second_ready : std_logic;
   signal irq_valid    : std_logic;
   signal irq_vector   : std_logic_vector(7 downto 0);

begin

   -- psl default clock is rising_edge(clk_i);

   -- The sources and the core
   -- psl f_first_hold : assume always
   --    {first_valid_i and not first_ready} |=>
   --    {first_valid_i = '1' and stable(first_vector_i)};
   -- psl f_second_hold : assume always
   --    {second_valid_i and not second_ready} |=>
   --    {second_valid_i = '1' and stable(second_vector_i)};
   -- psl f_core_ready : assume always irq_ready_i -> irq_valid;

   -- The merge
   -- psl f_valid_hold : assert always
   --    {irq_valid and not irq_ready_i} |=> {irq_valid};
   -- psl f_one_ready : assert always not (first_ready and second_ready);
   -- psl f_ready_taken : assert always irq_ready_i = (first_ready or second_ready);
   -- psl f_first_first : assert always first_valid_i -> not second_ready;
   -- psl f_first_vector : assert always first_ready -> irq_vector = first_vector_i;
   -- psl f_second_vector : assert always second_ready -> irq_vector = second_vector_i;

   -- psl c_passed_over : cover {second_valid_i and not first_valid_i;
   --    second_valid_i and first_valid_i and first_ready;
   --    second_ready};


   i_irq_merge : entity work.irq_merge
      port map (
         first_valid_i   => first_valid_i,
         first_ready_o   => first_ready,
         first_vector_i  => first_vector_i,
         second_valid_i  => second_valid_i,
         second_ready_o  => second_ready,
         second_vector_i => second_vector_i,
         irq_valid_o     => irq_valid,
         irq_ready_i     => irq_ready_i,
         irq_vector_o    => irq_vector
      ); -- i_irq_merge

end architecture synthesis;
