-- The SD card controller's registers with checks of their ports, for
-- SymbiYosys. Every input is free, so the solver tries every bus master
-- that holds a stalled request, every engine that keeps the contract of
-- sd_regs, and every card that comes and goes.
--
-- THEORY OF OPERATION
-- f_running follows the engine: it is set by start_o, and cleared by
-- done_i or abort_o. The engine raises done_i only while it runs, and
-- writes the buffer only then, as contract c) of sd_regs says. The
-- assertions on the engine port: no command starts while one runs, the
-- command, its slot, and its sector stay as they are while it runs, and
-- busy_o is high from the start to the end, but in the cycle of abort_o.
--
-- With G_HOLD_ACK, f_owed counts the requests accepted and not yet
-- acknowledged. The assertions say that at most one is owed, that an ACK
-- comes only when one is owed, that STALL is high exactly while one waits,
-- and that every request but a write of SD_CSR is acknowledged in the next
-- cycle. Without it, wb_slave_check says that the port never stalls and
-- acknowledges each request in the next cycle. The covers show a held
-- command that ends with its ACK, a Write that runs on through a reset,
-- and a Read that reset abandons.
--
-- RESET
-- The first cycle is a reset.

library ieee;
   use ieee.std_logic_1164.all;

entity formal_sd_regs is
   generic (
      G_HOLD_ACK : boolean := true
   );
   port (
      clk_i      : in  std_logic;
      rst_i      : in  std_logic;
      wb_cyc_i   : in  std_logic;
      wb_stb_i   : in  std_logic;
      wb_we_i    : in  std_logic;
      wb_addr_i  : in  std_logic_vector(3 downto 0);
      wb_data_i  : in  std_logic_vector(31 downto 0);
      present_i  : in  std_logic_vector(1 downto 0);
      wp_i       : in  std_logic_vector(1 downto 0);
      done_i     : in  std_logic;
      error_i    : in  std_logic_vector(3 downto 0);
      last_i     : in  std_logic_vector(31 downto 0);
      type_i     : in  std_logic_vector(1 downto 0);
      buf_addr_i : in  std_logic_vector(8 downto 0);
      buf_we_i   : in  std_logic;
      buf_data_i : in  std_logic_vector(7 downto 0)
   );
end entity formal_sd_regs;

architecture synthesis of formal_sd_regs is

   signal wb_stall : std_logic;
   signal wb_ack   : std_logic;
   signal wb_data  : std_logic_vector(31 downto 0);
   signal busy     : std_logic;
   signal start    : std_logic;
   signal abandon  : std_logic;
   signal cmd      : std_logic_vector(1 downto 0);
   signal slot     : std_logic_vector(3 downto 0);
   signal lba      : std_logic_vector(31 downto 0);
   signal buf_data : std_logic_vector(7 downto 0);

   signal accept    : std_logic;
   signal fast      : std_logic;                 -- A request that never waits
   signal f_running : std_logic            := '0';
   signal f_owed    : natural range 0 to 2 := 0;

begin

   accept <= wb_cyc_i and wb_stb_i and not wb_stall;
   fast   <= '0' when wb_we_i = '1' and wb_addr_i = X"0" else
             '1';


   p_track : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if start = '1' then
            f_running <= '1';
         elsif done_i = '1' or abandon = '1' then
            f_running <= '0';
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
   -- psl f_engine : assume always (done_i or buf_we_i) -> f_running;
   -- psl f_engine_late : assume always start -> not done_i;

   -- psl f_one_command : assert always start -> not f_running;
   -- psl f_busy : assert always f_running = ((busy and not start) or abandon);
   -- psl f_command_holds : assert always
   --    {f_running and not start} |-> {stable(cmd) and stable(slot) and stable(lba)};

   -- psl c_write_reset : cover {start = '1' and cmd = "10"; rst_i; (not rst_i)[*2]; done_i};
   -- psl c_read_abort : cover {start = '1' and cmd = "01"; rst_i; abandon};


   gen_hold : if G_HOLD_ACK generate

      -- psl f_hold : assume always
      --    {wb_cyc_i and wb_stb_i and wb_stall and not rst_i} |=>
      --    {wb_cyc_i = '1' and wb_stb_i = '1' and stable(wb_we_i) and stable(wb_addr_i) and
      --     stable(wb_data_i)};

      -- psl f_owed_max : assert always f_owed <= 1;
      -- psl f_ack_owed : assert always wb_ack -> f_owed = 1;
      -- psl f_stall : assert always wb_stall = '1' -> (f_owed = 1 and wb_ack = '0');
      -- psl f_stall_wait : assert always (f_owed = 1 and wb_ack = '0') -> wb_stall = '1';
      -- psl f_fast : assert always {accept and fast and not rst_i} |=> {wb_ack};
      -- psl f_ack_reset : assert always rst_i |=> not wb_ack and not wb_stall;

      -- psl c_held : cover {start and wb_stall; wb_stall[*2]; done_i; wb_ack};

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

   end generate gen_hold;


   i_sd_regs : entity work.sd_regs
      generic map (
         G_SLOTS    => 2,
         G_HOLD_ACK => G_HOLD_ACK
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
         wb_data_o  => wb_data,
         present_i  => present_i,
         wp_i       => wp_i,
         busy_o     => busy,
         start_o    => start,
         abort_o    => abandon,
         cmd_o      => cmd,
         slot_o     => slot,
         lba_o      => lba,
         done_i     => done_i,
         error_i    => error_i,
         last_i     => last_i,
         type_i     => type_i,
         buf_addr_i => buf_addr_i,
         buf_we_i   => buf_we_i,
         buf_data_i => buf_data_i,
         buf_data_o => buf_data
      ); -- i_sd_regs

end architecture synthesis;
