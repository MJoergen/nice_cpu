-- FETCH of the pipelined core, for SymbiYosys. Every input is
-- free, so the solver plays every slave on the instruction bus, every
-- redirect, and every DECODE that takes no more words than it is offered.
--
-- THEORY OF OPERATION
-- The properties are in pipe_fetch itself, under G_FORMAL, because their
-- invariants name its registers. The memory holds a free but constant
-- value at a free but constant address, and any value elsewhere, in every
-- ACK. The assertions say that DECODE sees that value whenever it sees
-- that address: the words come from the addresses that addr_o names, in
-- order, also after a redirect, a redirect to an odd address, and a
-- redirect with requests still in flight, whose words must be dropped.
-- They also check the bus port, as formal/wb_master_check.vhd does, and
-- that the words lie in the range that its end register closes.
--
-- The covers show a redirect to an odd address followed by words, and
-- four words presented at once.
--
-- RESET
-- The first cycle is a reset.

library ieee;
   use ieee.std_logic_1164.all;

   use work.pipe_pkg.all;

entity formal_pipe_fetch is
   port (
      clk_i           : in  std_logic;
      rst_i           : in  std_logic;
      ibus_stall_i    : in  std_logic;
      ibus_ack_i      : in  std_logic;
      ibus_data_i     : in  std_logic_vector(63 downto 0);
      redirect_i      : in  std_logic;
      redirect_addr_i : in  std_logic_vector(31 downto 0);
      stop_i          : in  std_logic;
      consume_i       : in  natural range 0 to 4
   );
end entity formal_pipe_fetch;

architecture synthesis of formal_pipe_fetch is

   signal ibus_cyc  : std_logic;
   signal ibus_stb  : std_logic;
   signal ibus_addr : std_logic_vector(30 downto 0);
   signal addr      : std_logic_vector(31 downto 0);
   signal words     : t_words4;
   signal count     : natural range 0 to 4;
   signal odd       : std_logic := '0';   -- The last redirect was to an odd address

begin

   p_odd : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if redirect_i = '1' then
            odd <= redirect_addr_i(0);
         end if;
         if rst_i = '1' then
            odd <= '0';
         end if;
      end if;
   end process p_odd;


   -- psl default clock is rising_edge(clk_i);
   -- psl f_initial_reset : assume rst_i;
   -- psl f_consume : assume always consume_i <= count;

   -- psl c_odd : cover {odd = '1' and count > 0 and rst_i = '0'};
   -- psl c_four : cover {count = 4 and rst_i = '0'};


   i_pipe_fetch : entity work.pipe_fetch
      generic map (
         G_FORMAL => true
      )
      port map (
         clk_i           => clk_i,
         rst_i           => rst_i,
         ibus_cyc_o      => ibus_cyc,
         ibus_stb_o      => ibus_stb,
         ibus_stall_i    => ibus_stall_i,
         ibus_ack_i      => ibus_ack_i,
         ibus_addr_o     => ibus_addr,
         ibus_data_i     => ibus_data_i,
         redirect_i      => redirect_i,
         redirect_addr_i => redirect_addr_i,
         stop_i          => stop_i,
         addr_o          => addr,
         words_o         => words,
         count_o         => count,
         consume_i       => consume_i,
         stats_o         => open
      ); -- i_pipe_fetch

end architecture synthesis;
