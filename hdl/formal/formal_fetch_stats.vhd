-- The fetch statistics with checks of their port, for SymbiYosys. Every
-- input is free, so the solver tries every bus master and every report of
-- FETCH and DECODE.
--
-- THEORY OF OPERATION
-- Two devices share the inputs: one with G_ENABLE true, whose properties
-- and invariants are in fetch_stats itself, under G_FORMAL, because they
-- name its counters, and one with G_ENABLE false. The assertions here say
-- that each port never stalls and acknowledges each accepted request in
-- the next cycle and nothing else, as formal_timer states it, and that
-- every read of the device without counters returns 0. The one assumption
-- is that the buffer holds no more words than FETCH holds room for, words
-- in flight included, which is what count and held of t_fetch_events mean.
-- The covers show a read of a histogram bin after a stop and a start, and
-- a read of FS_MIN after some cycles counted.
--
-- RESET
-- The first cycle is a reset.

library ieee;
   use ieee.std_logic_1164.all;

   use work.pipe_pkg.all;

entity formal_fetch_stats is
   port (
      clk_i     : in  std_logic;
      rst_i     : in  std_logic;
      count_i   : in  natural range 0 to 31;
      held_i    : in  natural range 0 to 31;
      starve_i  : in  std_logic;
      blocked_i : in  std_logic;
      full_i    : in  std_logic;
      stall_i   : in  std_logic;
      pair_i    : in  std_logic;
      words_i   : in  natural range 0 to 4;
      jump_i    : in  std_logic;
      flush_i   : in  std_logic;
      wb_cyc_i  : in  std_logic;
      wb_stb_i  : in  std_logic;
      wb_we_i   : in  std_logic;
      wb_addr_i : in  std_logic_vector(5 downto 0);
      wb_data_i : in  std_logic_vector(31 downto 0)
   );
end entity formal_fetch_stats;

architecture synthesis of formal_fetch_stats is

   signal events    : t_fetch_events;
   signal stall_on  : std_logic;
   signal ack_on    : std_logic;
   signal data_on   : std_logic_vector(31 downto 0);
   signal stall_off : std_logic;
   signal ack_off   : std_logic;
   signal data_off  : std_logic_vector(31 downto 0);
   signal accept    : std_logic;
   signal f_run     : std_logic := '1';   -- The run bit last written
   signal f_stops   : natural range 0 to 2 := 0;

begin

   events <=
   (
      count   => count_i,
      held    => held_i,
      starve  => starve_i,
      blocked => blocked_i,
      full    => full_i,
      stall   => stall_i,
      pair    => pair_i,
      words   => words_i,
      jump    => jump_i,
      flush   => flush_i
   );

   accept <= wb_cyc_i and wb_stb_i;


   -- Counts a stop, then a start, for the cover.
   p_run : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if accept = '1' and wb_we_i = '1' and wb_addr_i = "010000" then
            f_run <= wb_data_i(0);
            if wb_data_i(1) = '0' and wb_data_i(0) /= f_run and f_stops < 2 then
               f_stops <= f_stops + 1;
            end if;
         end if;
         if rst_i = '1' then
            f_run   <= '1';
            f_stops <= 0;
         end if;
      end if;
   end process p_run;


   -- psl default clock is rising_edge(clk_i);
   -- psl f_initial_reset : assume rst_i;
   -- psl f_held : assume always count_i <= held_i;

   -- psl f_no_stall : assert always not stall_on and not stall_off;
   -- psl f_ack : assert always
   --    {not rst_i} |=> {ack_on = (prev(wb_cyc_i) and prev(wb_stb_i)) and ack_on = ack_off};
   -- psl f_ack_reset : assert always rst_i |=> not ack_on and not ack_off;
   -- psl f_off : assert always data_off = X"00000000";

   -- psl c_restart : cover {accept = '1' and wb_we_i = '0' and wb_addr_i = "100011" and
   --    f_stops = 2 and rst_i = '0'; data_on /= X"00000000"};
   -- psl c_min_max : cover {accept = '1' and wb_we_i = '0' and wb_addr_i = "011010" and
   --    rst_i = '0'; data_on = X"00000002"};


   i_fetch_stats_on : entity work.fetch_stats
      generic map (
         G_ENABLE => true,
         G_FORMAL => true
      )
      port map (
         clk_i      => clk_i,
         rst_i      => rst_i,
         events_i   => events,
         wb_cyc_i   => wb_cyc_i,
         wb_stb_i   => wb_stb_i,
         wb_stall_o => stall_on,
         wb_ack_o   => ack_on,
         wb_we_i    => wb_we_i,
         wb_addr_i  => wb_addr_i,
         wb_data_i  => wb_data_i,
         wb_data_o  => data_on
      ); -- i_fetch_stats_on


   i_fetch_stats_off : entity work.fetch_stats
      generic map (
         G_ENABLE => false
      )
      port map (
         clk_i      => clk_i,
         rst_i      => rst_i,
         events_i   => events,
         wb_cyc_i   => wb_cyc_i,
         wb_stb_i   => wb_stb_i,
         wb_stall_o => stall_off,
         wb_ack_o   => ack_off,
         wb_we_i    => wb_we_i,
         wb_addr_i  => wb_addr_i,
         wb_data_i  => wb_data_i,
         wb_data_o  => data_off
      ); -- i_fetch_stats_off

end architecture synthesis;
