-- DBUS of the pipelined core, for SymbiYosys. Every input is free, so the
-- solver plays every slave on the data bus, and every PREPARE and WRITE
-- that keep to the interface contracts of src/pipe_dbus.vhd.
--
-- THEORY OF OPERATION
-- The properties are in pipe_dbus itself, under G_FORMAL, because their
-- invariants name its registers. They say that each ACK is taken for a
-- read exactly when its request was one, and that the read data reach
-- WRITE in the order of their ACKs, none lost. A wb_master_check watches
-- the bus port. Its count of requests in flight must be the tag count of
-- pipe_dbus, which ties the two together for k-induction.
--
-- The covers show four requests in flight, and the FIFO of read data full.
--
-- RESET
-- The first cycle is a reset.

library ieee;
   use ieee.std_logic_1164.all;

   use work.pipe_pkg.all;

entity formal_pipe_dbus is
   port (
      clk_i        : in  std_logic;
      rst_i        : in  std_logic;
      rd_stb_i     : in  std_logic;
      rd_addr_i    : in  std_logic_vector(31 downto 0);
      w_req_i      : in  std_logic;
      w_we_i       : in  std_logic;
      w_addr_i     : in  std_logic_vector(31 downto 0);
      w_data_i     : in  std_logic_vector(31 downto 0);
      w_pop_i      : in  natural range 0 to 2;
      dbus_stall_i : in  std_logic;
      dbus_ack_i   : in  std_logic;
      dbus_data_i  : in  std_logic_vector(31 downto 0)
   );
end entity formal_pipe_dbus;

architecture synthesis of formal_pipe_dbus is

   signal rq         : t_words(0 to C_MAX_OUT - 1);
   signal rq_cnt     : natural range 0 to C_MAX_OUT;
   signal ack_read   : std_logic;
   signal tag_cnt    : natural range 0 to C_MAX_OUT;
   signal reads_owed : natural range 0 to C_MAX_OUT;
   signal dbus_cyc   : std_logic;
   signal dbus_stb   : std_logic;
   signal dbus_we    : std_logic;
   signal dbus_addr  : std_logic_vector(31 downto 0);
   signal dbus_data  : std_logic_vector(31 downto 0);
   signal pending    : natural range 0 to C_MAX_OUT + 1;

begin

   -- psl default clock is rising_edge(clk_i);
   -- psl f_initial_reset : assume rst_i;
   -- The range of the port, which synthesis does not keep
   -- psl f_pop_range : assume always w_pop_i <= 2;

   -- psl f_pending : assert always rst_i = '0' -> pending = tag_cnt;

   -- psl c_four : cover {tag_cnt = C_MAX_OUT and rst_i = '0'};
   -- psl c_full : cover {rq_cnt = C_MAX_OUT and rst_i = '0'};


   i_pipe_dbus : entity work.pipe_dbus
      generic map (
         G_FORMAL => true
      )
      port map (
         clk_i        => clk_i,
         rst_i        => rst_i,
         rd_stb_i     => rd_stb_i,
         rd_addr_i    => rd_addr_i,
         w_req_i      => w_req_i,
         w_we_i       => w_we_i,
         w_addr_i     => w_addr_i,
         w_data_i     => w_data_i,
         w_pop_i      => w_pop_i,
         rq_o         => rq,
         rq_cnt_o     => rq_cnt,
         ack_read_o   => ack_read,
         tag_cnt_o    => tag_cnt,
         reads_owed_o => reads_owed,
         dbus_cyc_o   => dbus_cyc,
         dbus_stb_o   => dbus_stb,
         dbus_stall_i => dbus_stall_i,
         dbus_ack_i   => dbus_ack_i,
         dbus_we_o    => dbus_we,
         dbus_addr_o  => dbus_addr,
         dbus_data_o  => dbus_data,
         dbus_data_i  => dbus_data_i
      ); -- i_pipe_dbus


   i_wb_master_check : entity work.wb_master_check
      generic map (
         G_MAX_PENDING => C_MAX_OUT
      )
      port map (
         clk_i     => clk_i,
         rst_i     => rst_i,
         cyc_i     => dbus_cyc,
         stb_i     => dbus_stb,
         stall_i   => dbus_stall_i,
         ack_i     => dbus_ack_i,
         we_i      => dbus_we,
         addr_i    => dbus_addr,
         data_i    => dbus_data,
         pending_o => pending
      ); -- i_wb_master_check

end architecture synthesis;
