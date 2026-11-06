-- The fetch statistics with checks of their port, for SymbiYosys. Every
-- input is free, so the solver tries every bus master, every report of
-- the core, and every run_i.
--
-- THEORY OF OPERATION
-- Two devices share the inputs: one with G_ENABLE true, whose properties
-- and invariants are in fetch_stats itself, under G_FORMAL, because they
-- name its counters, and one with G_ENABLE false. A wb_slave_check on each
-- port says that it never stalls and acknowledges each request in the
-- next cycle and nothing else, and f_off that every read of the device
-- without counters returns 0. The assumptions are the reset, and that
-- the causes are in their ranges, which their types say but their bits
-- do not.
-- The covers show a read of a cause after a stop and a start, and a read
-- of a flush cause after two flushes.
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
      run_i     : in  std_logic;
      istall_i  : in  std_logic;
      dstall_i  : in  std_logic;
      jump_i    : in  std_logic;
      flush_i   : in  std_logic;
      fwhy_i    : in  natural range 0 to C_FLUSHES - 1;
      cause_i   : in  natural range 0 to C_CAUSES - 1;
      wb_cyc_i  : in  std_logic;
      wb_stb_i  : in  std_logic;
      wb_we_i   : in  std_logic;
      wb_addr_i : in  std_logic_vector(4 downto 0);
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
      istall  => istall_i,
      dstall  => dstall_i,
      jump    => jump_i,
      flush   => flush_i,
      fwhy    => fwhy_i,
      cause   => cause_i,
      wait_sr => '0',
      wait_wr => '0',
      moved   => '0'
   );

   accept <= wb_cyc_i and wb_stb_i;


   -- Counts a stop, then a start, for the cover.
   p_run : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if accept = '1' and wb_we_i = '1' and wb_addr_i = "00000" then
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
   -- psl f_cause_range : assume always cause_i < C_CAUSES;
   -- psl f_fwhy_range : assume always fwhy_i < C_FLUSHES;

   -- psl f_off : assert always data_off = X"00000000";

   -- psl c_restart : cover {accept = '1' and wb_we_i = '0' and wb_addr_i = "10011" and
   --    f_stops = 2 and rst_i = '0'; data_on /= X"00000000"};
   -- psl c_flush_bin : cover {accept = '1' and wb_we_i = '0' and wb_addr_i = "01010" and
   --    rst_i = '0'; data_on = X"00000002"};


   i_fetch_stats_on : entity work.fetch_stats
      generic map (
         G_ENABLE => true,
         G_FORMAL => true
      )
      port map (
         clk_i      => clk_i,
         rst_i      => rst_i,
         run_i      => run_i,
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
         run_i      => run_i,
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


   i_wb_slave_check_on : entity work.wb_slave_check
      port map (
         clk_i   => clk_i,
         rst_i   => rst_i,
         cyc_i   => wb_cyc_i,
         stb_i   => wb_stb_i,
         stall_i => stall_on,
         ack_i   => ack_on
      ); -- i_wb_slave_check_on


   i_wb_slave_check_off : entity work.wb_slave_check
      port map (
         clk_i   => clk_i,
         rst_i   => rst_i,
         cyc_i   => wb_cyc_i,
         stb_i   => wb_stb_i,
         stall_i => stall_off,
         ack_i   => ack_off
      ); -- i_wb_slave_check_off

end architecture synthesis;
