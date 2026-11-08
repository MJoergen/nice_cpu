-- The clock of the time of day with checks of its port, for SymbiYosys.
-- Every input is free, so the solver tries every bus master at any time.
--
-- THEORY OF OPERATION
-- wb_slave_check watches the bus port, which acknowledges each request in
-- the next cycle, and nothing else. The data of each ACK is checked
-- against the word read: CLOCK_USEC returns at most 999999, and
-- CLOCK_STATUS 0 or 1. tod.vhd itself asserts that the microseconds
-- never reach 1000000 (f_usec). G_CLK_HZ is 1000000, so the clock counts
-- in every cycle, and the covers show a second end and the clock set.
--
-- RESET
-- The first cycle is a reset.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

entity formal_tod is
   port (
      clk_i     : in  std_logic;
      rst_i     : in  std_logic;
      wb_cyc_i  : in  std_logic;
      wb_stb_i  : in  std_logic;
      wb_we_i   : in  std_logic;
      wb_addr_i : in  std_logic_vector(1 downto 0);
      wb_data_i : in  std_logic_vector(31 downto 0)
   );
end entity formal_tod;

architecture synthesis of formal_tod is

   signal wb_stall : std_logic;
   signal wb_ack   : std_logic;
   signal wb_data  : std_logic_vector(31 downto 0);

   -- The read accepted in the cycle before, if any, and its word
   signal read_r : std_logic                    := '0';
   signal addr_r : std_logic_vector(1 downto 0) := "00";

begin

   p_read : process (clk_i)
   begin
      if rising_edge(clk_i) then
         read_r <= wb_cyc_i and wb_stb_i and not wb_we_i and not rst_i;
         addr_r <= wb_addr_i;
      end if;
   end process p_read;

   -- psl default clock is rising_edge(clk_i);
   -- psl f_initial_reset : assume rst_i;

   -- psl f_usec_read : assert always
   --    (read_r = '1' and addr_r = "00") -> wb_data <= 999999;
   -- psl f_status_read : assert always
   --    (read_r = '1' and addr_r = "11") -> wb_data(31 downto 1) = 0;

   -- psl c_second : cover {read_r = '1' and addr_r = "01" and wb_data = 1};
   -- psl c_set : cover {read_r = '1' and addr_r = "11" and wb_data = 1};


   i_tod : entity work.tod
      generic map (
         G_CLK_HZ => 1000000
      )
      port map (
         clk_i      => clk_i,
         rst_i      => rst_i,
         wb_cyc_i   => wb_cyc_i,
         wb_stb_i   => wb_stb_i,
         wb_stall_o => wb_stall,
         wb_ack_o   => wb_ack,
         wb_we_i    => wb_we_i,
         wb_addr_i  => wb_addr_i,
         wb_data_i  => wb_data_i,
         wb_data_o  => wb_data
      ); -- i_tod


   i_wb_slave_check : entity work.wb_slave_check
      port map (
         clk_i   => clk_i,
         rst_i   => rst_i,
         cyc_i   => wb_cyc_i,
         stb_i   => wb_stb_i,
         stall_i => wb_stall,
         ack_i   => wb_ack
      ); -- i_wb_slave_check

end architecture synthesis;
