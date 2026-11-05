-- The port for Ethernet frames with checks of its ports, for SymbiYosys.
-- Every input is free, so the solver tries every bus master that holds a
-- stalled request, and every station that keeps the contract of
-- eth_regs.
--
-- THEORY OF OPERATION
-- f_sending follows a frame sent: it is set by tx_start_o and cleared by
-- tx_done_i, which the station raises only while one is sent, and not in
-- the cycle of tx_start_o. The assertions on the station's port: busy_o
-- is high from tx_start_o to tx_done_i, no frame is sent while one is,
-- and its length is 14 to 1514 and holds while it
-- is sent. On "enabled": enable_o comes with it, a write of ETH_CSR with
-- bit 0 at 0 clears it, and so does reset.
--
-- With G_HOLD_ACK, f_owed counts the requests accepted and not yet
-- acknowledged. The assertions say that at most one is owed, that an ACK
-- comes only when one is owed, that STALL is high exactly while one waits,
-- and that every request but a write of ETH_CSR or ETH_TX_LEN is
-- acknowledged in the next cycle. A reset does not come while a request
-- waits, as in the simulation, which resets only at the start. Without
-- G_HOLD_ACK, wb_slave_check says that the port never stalls and
-- acknowledges each request in the next cycle, and a reset may come
-- while a frame is sent, which goes on. The covers show a held send and a
-- held enable that end with their ACK, and a send that runs on through a
-- reset.
--
-- eth_regs's G_FORMAL proves the invariants that the induction needs: the
-- held ACK of a write that enabled lasts from enable_o to enable_done_i,
-- that of a send while busy, and the queue holds at most 4 frames. With
-- G_HOLD_ACK, it assumes that the station raises enable_done_i only for
-- an enable_o it serves, and asserts that no enable_o comes meanwhile.
--
-- RESET
-- The first cycle is a reset.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

entity formal_eth_regs is
   generic (
      G_HOLD_ACK : boolean := true
   );
   port (
      clk_i         : in  std_logic;
      rst_i         : in  std_logic;
      wb_cyc_i      : in  std_logic;
      wb_stb_i      : in  std_logic;
      wb_we_i       : in  std_logic;
      wb_addr_i     : in  std_logic_vector(3 downto 0);
      wb_data_i     : in  std_logic_vector(31 downto 0);
      enable_done_i : in  std_logic;
      rx_start_i    : in  std_logic;
      rx_we_i       : in  std_logic;
      rx_addr_i     : in  std_logic_vector(8 downto 0);
      rx_data_i     : in  std_logic_vector(31 downto 0);
      rx_done_i     : in  std_logic;
      rx_len_i      : in  std_logic_vector(10 downto 0);
      tx_addr_i     : in  std_logic_vector(8 downto 0);
      tx_done_i     : in  std_logic
   );
end entity formal_eth_regs;

architecture synthesis of formal_eth_regs is

   signal wb_stall : std_logic;
   signal wb_ack   : std_logic;
   signal wb_data  : std_logic_vector(31 downto 0);
   signal enabled  : std_logic;
   signal enable   : std_logic;
   signal tx_start : std_logic;
   signal busy     : std_logic;
   signal tx_len   : std_logic_vector(10 downto 0);
   signal tx_data  : std_logic_vector(31 downto 0);

   signal accept     : std_logic;
   signal disable    : std_logic;                 -- A write of 0 to "enabled"
   signal fast       : std_logic;                 -- A request that never waits
   signal f_sending  : std_logic            := '0';
   signal f_owed     : natural range 0 to 2 := 0;

begin

   accept  <= wb_cyc_i and wb_stb_i and not wb_stall;
   disable <= accept and wb_we_i and not wb_data_i(0) when wb_addr_i = X"0" else
              '0';
   fast    <= '0' when wb_we_i = '1' and (wb_addr_i = X"0" or wb_addr_i = X"2") else
              '1';


   p_track : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if tx_start = '1' then
            f_sending <= '1';
         elsif tx_done_i = '1' then
            f_sending <= '0';
         end if;
         if accept = '1' and wb_ack = '0' and f_owed < 2 then
            f_owed <= f_owed + 1;
         elsif accept = '0' and wb_ack = '1' and f_owed > 0 then
            f_owed <= f_owed - 1;
         end if;
         if rst_i = '1' then
            f_owed <= 0;
         end if;
      end if;
   end process p_track;

   -- psl default clock is rising_edge(clk_i);
   -- psl f_initial_reset : assume rst_i;
   -- psl f_station : assume always tx_done_i -> f_sending;
   -- psl f_station_late : assume always tx_start -> not tx_done_i;

   -- psl f_busy : assert always f_sending = (busy and not tx_start);
   -- psl f_one_send : assert always tx_start -> not f_sending;
   -- psl f_len : assert always tx_start -> (tx_len >= 14 and tx_len <= 1514);
   -- psl f_len_holds : assert always {f_sending and not tx_done_i} |=> {stable(tx_len)};
   -- psl f_enable_on : assert always enable -> enabled;
   -- psl f_disable : assert always {disable and not rst_i} |=> {not enabled};
   -- psl f_reset : assert always rst_i |=> not enabled and not enable;

   -- psl c_enable : cover {enable; enable_done_i; wb_ack};
   -- psl c_send : cover {tx_start; tx_done_i};


   gen_hold : if G_HOLD_ACK generate

      -- psl f_hold : assume always
      --    {wb_cyc_i and wb_stb_i and wb_stall and not rst_i} |=>
      --    {wb_cyc_i = '1' and wb_stb_i = '1' and stable(wb_we_i) and stable(wb_addr_i) and
      --     stable(wb_data_i)};
      -- psl f_no_reset_held : assume always wb_stall -> not rst_i;

      -- psl f_owed_max : assert always f_owed <= 1;
      -- psl f_ack_owed : assert always wb_ack -> f_owed = 1;
      -- psl f_stall : assert always wb_stall = '1' -> (f_owed = 1 and wb_ack = '0');
      -- psl f_stall_wait : assert always (f_owed = 1 and wb_ack = '0') -> wb_stall = '1';
      -- psl f_fast : assert always {accept and fast and not rst_i} |=> {wb_ack};
      -- psl f_ack_reset : assert always rst_i |=> not wb_ack and not wb_stall;

      -- psl c_held_send : cover {tx_start and wb_stall; wb_stall[*2]; tx_done_i; wb_ack};
      -- psl c_held_enable : cover {enable and wb_stall; wb_stall[*2]; enable_done_i; wb_ack};

   else generate

      i_wb_slave_check : entity work.wb_slave_check
         port map (
            clk_i   => clk_i,
            rst_i   => rst_i,
            cyc_i   => wb_cyc_i,
            stb_i   => wb_stb_i,
            stall_i => wb_stall,
            ack_i   => wb_ack
         ); -- i_wb_slave_check

      -- psl c_send_reset : cover {tx_start; rst_i; (not rst_i)[*2]; tx_done_i};

   end generate gen_hold;


   i_eth_regs : entity work.eth_regs
      generic map (
         G_HOLD_ACK => G_HOLD_ACK,
         G_FORMAL   => true
      )
      port map (
         clk_i         => clk_i,
         rst_i         => rst_i,
         wb_cyc_i      => wb_cyc_i,
         wb_stb_i      => wb_stb_i,
         wb_stall_o    => wb_stall,
         wb_ack_o      => wb_ack,
         wb_we_i       => wb_we_i,
         wb_addr_i     => wb_addr_i,
         wb_data_i     => wb_data_i,
         wb_data_o     => wb_data,
         enabled_o     => enabled,
         enable_o      => enable,
         enable_done_i => enable_done_i,
         rx_start_i    => rx_start_i,
         rx_we_i       => rx_we_i,
         rx_addr_i     => rx_addr_i,
         rx_data_i     => rx_data_i,
         rx_done_i     => rx_done_i,
         rx_len_i      => rx_len_i,
         tx_start_o    => tx_start,
         busy_o        => busy,
         tx_len_o      => tx_len,
         tx_addr_i     => tx_addr_i,
         tx_data_o     => tx_data,
         tx_done_i     => tx_done_i
      ); -- i_eth_regs

end architecture synthesis;
