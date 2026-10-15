-- The timer with checks of its ports, for SymbiYosys. Every input is free,
-- so the solver tries every bus master, every tick, and every core that
-- takes the timer's requests at any time.
--
-- THEORY OF OPERATION
-- The interrupt port is the source side of the core's valid/ready port,
-- which formal_multicycle checks from the other side with
-- handshake_check: once VALID is high, it stays high, with the vector
-- unchanged, until READY takes the request. The bus port acknowledges each
-- accepted request in the next cycle, and nothing else. The covers show
-- that a request is raised and taken, and that one waits while the timer
-- counts on.
--
-- RESET
-- The first cycle is a reset.

library ieee;
   use ieee.std_logic_1164.all;

entity formal_timer is
   port (
      clk_i       : in  std_logic;
      rst_i       : in  std_logic;
      tick_i      : in  std_logic;
      wb_cyc_i    : in  std_logic;
      wb_stb_i    : in  std_logic;
      wb_we_i     : in  std_logic;
      wb_addr_i   : in  std_logic_vector(3 downto 0);
      wb_data_i   : in  std_logic_vector(31 downto 0);
      irq_ready_i : in  std_logic
   );
end entity formal_timer;

architecture synthesis of formal_timer is

   signal wb_stall   : std_logic;
   signal wb_ack     : std_logic;
   signal wb_data    : std_logic_vector(31 downto 0);
   signal irq_valid  : std_logic;
   signal irq_vector : std_logic_vector(7 downto 0);

begin

   -- psl default clock is rising_edge(clk_i);
   -- psl f_initial_reset : assume rst_i;

   -- The interrupt port
   -- psl f_valid_hold : assert always
   --    {irq_valid and not irq_ready_i and not rst_i} |=>
   --    {rst_i = '1' or (irq_valid = '1' and stable(irq_vector))};
   -- psl f_valid_reset : assert always rst_i |=> not irq_valid;

   -- The bus port
   -- psl f_no_stall : assert always not wb_stall;
   -- psl f_ack : assert always
   --    {not rst_i} |=> {wb_ack = (prev(wb_cyc_i) and prev(wb_stb_i))};
   -- psl f_ack_reset : assert always rst_i |=> not wb_ack;

   -- psl c_take : cover {irq_valid and irq_ready_i};
   -- psl c_wait : cover {irq_valid and not irq_ready_i and tick_i;
   --    irq_valid and not irq_ready_i and tick_i;
   --    irq_valid and irq_ready_i};


   i_timer : entity work.timer
      port map (
         clk_i        => clk_i,
         rst_i        => rst_i,
         tick_i       => tick_i,
         wb_cyc_i     => wb_cyc_i,
         wb_stb_i     => wb_stb_i,
         wb_stall_o   => wb_stall,
         wb_ack_o     => wb_ack,
         wb_we_i      => wb_we_i,
         wb_addr_i    => wb_addr_i,
         wb_data_i    => wb_data_i,
         wb_data_o    => wb_data,
         irq_valid_o  => irq_valid,
         irq_ready_i  => irq_ready_i,
         irq_vector_o => irq_vector
      ); -- i_timer

end architecture synthesis;
