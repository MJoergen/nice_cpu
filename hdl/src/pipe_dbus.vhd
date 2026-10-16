-- The data bus port of the pipelined core (MICROARCH.md §5.3).
--
-- THEORY OF OPERATION
-- Two stages make data accesses: PREPARE its reads, from a request
-- register that holds each until the bus accepts it, and WRITE its stores
-- and vector reads, straight onto the bus. The two never compete (see
-- src/pipeline.vhd). The bus is pipelined Wishbone, and the ACKs come back
-- in order. A FIFO of tags, one for each request accepted and not yet
-- acknowledged, tells reads from writes. A second FIFO holds the data of
-- the reads that WRITE has not used yet. WRITE may also use the data of a
-- read in the cycle its ACK comes, ack_read_o.
--
-- The registers are the two FIFOs. The bus outputs and ack_read_o depend
-- combinationally on the requests of PREPARE and WRITE and on the bus.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) rd_stb_i and w_req_i are never '1' together.
-- b) WRITE pops no more data than has come, and makes no request when
--    C_MAX_OUT are in flight; PREPARE neither.
--
-- RESET
-- Synchronous. It empties the FIFOs.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use work.nice_pkg.all;
   use work.pipe_pkg.all;
   use work.trace_pkg.all;

entity pipe_dbus is
   port (
      clk_i        : in  std_logic;
      rst_i        : in  std_logic;

      -- The read of PREPARE
      rd_stb_i     : in  std_logic;
      rd_addr_i    : in  std_logic_vector(31 downto 0);

      -- The access of WRITE, and the read data it uses now
      w_req_i      : in  std_logic;
      w_we_i       : in  std_logic;
      w_addr_i     : in  std_logic_vector(31 downto 0);
      w_data_i     : in  std_logic_vector(31 downto 0);
      w_pop_i      : in  natural range 0 to 2;

      -- The read data that WRITE has not used yet, oldest first
      rq_o         : out t_words(0 to C_MAX_OUT - 1);
      rq_cnt_o     : out natural range 0 to C_MAX_OUT;
      ack_read_o   : out std_logic;   -- The ACK of a read, with its data on dbus_data_i
      -- The requests accepted and not acknowledged, and the reads of them
      tag_cnt_o    : out natural range 0 to C_MAX_OUT;
      reads_owed_o : out natural range 0 to C_MAX_OUT;

      -- Data bus: read and write
      dbus_cyc_o   : out std_logic;
      dbus_stb_o   : out std_logic;
      dbus_stall_i : in  std_logic;
      dbus_ack_i   : in  std_logic;
      dbus_we_o    : out std_logic;
      dbus_addr_o  : out std_logic_vector(31 downto 0);
      dbus_data_o  : out std_logic_vector(31 downto 0);
      dbus_data_i  : in  std_logic_vector(31 downto 0)
   );
end entity pipe_dbus;

architecture synthesis of pipe_dbus is

   signal rd_stb_r  : std_logic;
   signal rd_addr_r : std_logic_vector(31 downto 0);
   signal w_req     : std_logic;
   signal w_we      : std_logic;
   signal w_addr    : std_logic_vector(31 downto 0);
   signal w_data    : std_logic_vector(31 downto 0);
   signal w_pop     : natural range 0 to 2;

   signal tags_r     : std_logic_vector(0 to C_MAX_OUT - 1);   -- '1' for a write
   signal tag_cnt_r  : natural range 0 to C_MAX_OUT;
   signal rq_r       : t_words(0 to C_MAX_OUT - 1);            -- Read data not used yet
   signal rq_cnt_r   : natural range 0 to C_MAX_OUT;
   signal dbus_stb   : std_logic;
   signal accept     : std_logic;
   signal ack_read   : std_logic;
   signal reads_owed : natural range 0 to C_MAX_OUT;

begin

   rd_stb_r  <= rd_stb_i;
   rd_addr_r <= rd_addr_i;
   w_req     <= w_req_i;
   w_we      <= w_we_i;
   w_addr    <= w_addr_i;
   w_data    <= w_data_i;
   w_pop     <= w_pop_i;

   rq_o         <= rq_r;
   rq_cnt_o     <= rq_cnt_r;
   ack_read_o   <= ack_read;
   tag_cnt_o    <= tag_cnt_r;
   reads_owed_o <= reads_owed;

   dbus_stb    <= rd_stb_r or w_req;
   dbus_stb_o  <= dbus_stb;
   dbus_cyc_o  <= '1' when dbus_stb = '1' or tag_cnt_r > 0 else '0';
   dbus_we_o   <= w_we when w_req = '1' else '0';
   dbus_addr_o <= w_addr when w_req = '1' else rd_addr_r;
   dbus_data_o <= w_data;
   accept      <= dbus_stb and not dbus_stall_i;
   ack_read    <= dbus_ack_i and not tags_r(0);


   p_dbus : process (clk_i)
      variable tags_v : std_logic_vector(0 to C_MAX_OUT);
      variable tcnt_v : natural range 0 to C_MAX_OUT + 1;
      variable rq_v   : t_words(0 to C_MAX_OUT);
      variable rcnt_v : natural range 0 to C_MAX_OUT + 1;
   begin
      if rising_edge(clk_i) then
         -- The tag of each accepted request, oldest first
         tags_v := tags_r & '0';
         tcnt_v := tag_cnt_r;
         if dbus_ack_i = '1' then
            tags_v := tags_v(1 to C_MAX_OUT) & '0';
            tcnt_v := tcnt_v - 1;
         end if;
         if accept = '1' then
            tags_v(tcnt_v) := w_we and w_req;
            tcnt_v         := tcnt_v + 1;
         end if;
         tags_r    <= tags_v(0 to C_MAX_OUT - 1);
         tag_cnt_r <= tcnt_v;

         -- The read data, oldest first, less what WRITE uses now
         rq_v   := rq_r & X"00000000";
         rcnt_v := rq_cnt_r;
         if ack_read = '1' then
            rq_v(rcnt_v) := dbus_data_i;
            rcnt_v       := rcnt_v + 1;
         end if;
         case w_pop is
            when 1 =>
               rq_v   := rq_v(1 to C_MAX_OUT) & X"00000000";
               rcnt_v := rcnt_v - 1;
            when 2 =>
               rq_v   := rq_v(2 to C_MAX_OUT) & X"00000000" & X"00000000";
               rcnt_v := rcnt_v - 2;
            when others =>
               null;
         end case;
         rq_r     <= rq_v(0 to C_MAX_OUT - 1);
         rq_cnt_r <= rcnt_v;

         if rst_i = '1' then
            tag_cnt_r <= 0;
            rq_cnt_r  <= 0;
         end if;
      end if;
   end process p_dbus;


   p_owed : process (all)
      variable owed_v : natural range 0 to C_MAX_OUT;
   begin
      owed_v := 0;
      for i in 0 to C_MAX_OUT - 1 loop
         if i < tag_cnt_r and tags_r(i) = '0' then
            owed_v := owed_v + 1;
         end if;
      end loop;
      reads_owed <= owed_v;
   end process p_owed;

end architecture synthesis;
