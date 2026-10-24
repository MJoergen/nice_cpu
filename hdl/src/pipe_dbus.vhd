-- DBUS, the data bus port of the pipelined core (MICROARCH.md §5.3).
--
-- THEORY OF OPERATION
-- Two stages make data accesses: PREPARE its reads, from a request
-- register that holds each until the bus accepts it; and WRITE its stores
-- and its vector reads, through the register st_r here. WRITE puts an
-- access into st_r, which drives the bus from the next cycle on, until the
-- bus accepts it (MICROARCH.md §5.3). So no path runs from WRITE's
-- decisions to the bus. The two never compete (see src/pipeline.vhd). The
-- bus is pipelined Wishbone, and the ACKs come
-- back in order. A FIFO of tags, one for each request accepted and not yet
-- acknowledged, tells reads from writes. A second FIFO holds the data of
-- the reads that WRITE has not used yet. WRITE may also use the data of a
-- read in the cycle its ACK comes, ack_read_o, if it only goes into a
-- register (MICROARCH.md §5.3).
--
-- The registers are the two FIFOs and st_r. The bus outputs and ack_read_o
-- depend combinationally on st_r, on PREPARE's read, and on the bus. DAT_O
-- is 0 for a read, so that it stays unchanged while the bus stalls a read,
-- as wb_master_check asks.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) rd_stb_i is never '1' while an access waits in st_r (st_valid_o).
-- b) WRITE pops no more data than has come, and makes no read when
--    C_MAX_OUT are in flight; PREPARE neither.
-- c) A read is accepted only when the read data not used yet and the reads
--    owed, less what WRITE pops in that cycle, are fewer than C_MAX_OUT.
--    Else its data would find no room.
-- d) WRITE queues an access, st_i, only when st_r is empty or the bus
--    accepts its access in that cycle (st_acc_o).
--
-- RESET
-- Synchronous. It empties the FIFOs and st_r.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use work.nice_pkg.all;
   use work.pipe_pkg.all;
   use work.trace_pkg.all;

entity pipe_dbus is
   generic (
      -- Adds the invariants that a formal proof needs.
      G_FORMAL : boolean := false
   );
   port (
      clk_i        : in  std_logic;
      rst_i        : in  std_logic;

      -- The read of PREPARE
      rd_stb_i     : in  std_logic;
      rd_addr_i    : in  std_logic_vector(31 downto 0);

      -- The read data that WRITE uses now
      w_pop_i      : in  natural range 0 to 2;

      -- The store or vector read of WRITE, which waits in st_r until the
      -- bus accepts it
      st_i         : in  std_logic;
      st_we_i      : in  std_logic;   -- '1' for a store, '0' for a vector read
      st_addr_i    : in  std_logic_vector(31 downto 0);
      st_data_i    : in  std_logic_vector(31 downto 0);
      st_valid_o   : out std_logic;   -- An access waits in st_r
      st_acc_o     : out std_logic;   -- The bus accepts it now

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

   signal tags_r     : std_logic_vector(0 to C_MAX_OUT - 1);   -- '1' for a write
   signal tag_cnt_r  : natural range 0 to C_MAX_OUT;
   signal rq_r       : t_words(0 to C_MAX_OUT - 1);            -- Read data not used yet
   signal rq_cnt_r   : natural range 0 to C_MAX_OUT;
   signal dbus_stb   : std_logic;
   signal accept     : std_logic;
   signal ack_read   : std_logic;
   signal reads_owed : natural range 0 to C_MAX_OUT;
   signal st_valid_r : std_logic;                              -- st_r: an access waits
   signal st_we_r    : std_logic;                              -- and is a store
   signal st_addr_r  : std_logic_vector(31 downto 0);
   signal st_data_r  : std_logic_vector(31 downto 0);
   signal st_out     : std_logic;                              -- It is on the bus
   signal st_acc     : std_logic;                              -- The bus accepts it

begin

   rq_o         <= rq_r;
   rq_cnt_o     <= rq_cnt_r;
   ack_read_o   <= ack_read;
   tag_cnt_o    <= tag_cnt_r;
   reads_owed_o <= reads_owed;

   -- The access in st_r goes on the bus when fewer than C_MAX_OUT are in
   -- flight.
   st_out     <= '1' when st_valid_r = '1' and tag_cnt_r < C_MAX_OUT else '0';
   st_acc     <= st_out and not dbus_stall_i;
   st_valid_o <= st_valid_r;
   st_acc_o   <= st_acc;

   dbus_stb    <= rd_stb_i or st_out;
   dbus_stb_o  <= dbus_stb;
   dbus_cyc_o  <= '1' when dbus_stb = '1' or tag_cnt_r > 0 else '0';
   dbus_we_o   <= st_out and st_we_r;
   dbus_addr_o <= st_addr_r when st_out = '1' else rd_addr_i;
   dbus_data_o <= st_data_r when st_out = '1' and st_we_r = '1' else (others => '0');
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
            tags_v(tcnt_v) := st_out and st_we_r;
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
         case w_pop_i is
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

         -- The access of WRITE, until the bus accepts it
         if st_acc = '1' then
            st_valid_r <= '0';
         end if;
         if st_i = '1' then
            st_valid_r <= '1';
            st_we_r    <= st_we_i;
            st_addr_r  <= st_addr_i;
            st_data_r  <= st_data_i;
         end if;

         if rst_i = '1' then
            tag_cnt_r  <= 0;
            rq_cnt_r   <= 0;
            st_valid_r <= '0';
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


   -- The formal properties (formal/formal_pipe_dbus.vhd). Requests and read
   -- data are numbered modulo 8, in the order the bus accepts them and the
   -- ACKs bring them. One request, of free but constant number f_r, is
   -- followed: the assertions say that its ACK is taken for a read exactly
   -- when it was one. One read datum, of free but constant number f_n,
   -- holds a free but constant value f_v: the assertions say that WRITE
   -- finds f_v wherever rq_o holds read number f_n. The invariants tie the
   -- counts and the FIFOs to the numbers, so that k-induction can prove it
   -- all for every cycle.

   gen_formal : if G_FORMAL generate
      signal f_acc  : std_logic_vector(2 downto 0) := "000";   -- Requests accepted
      signal f_ack  : std_logic_vector(2 downto 0) := "000";   -- ACKs
      signal f_racc : std_logic_vector(2 downto 0) := "000";   -- Reads accepted
      signal f_rack : std_logic_vector(2 downto 0) := "000";   -- ACKs of reads
      signal f_pop  : std_logic_vector(2 downto 0) := "000";   -- Read data popped
      signal f_we   : std_logic;                                -- Request f_r is a write
      signal f_read : std_logic;                                -- A read is accepted now
      -- The cycle before: a reset, and a stalled request with its fields
      signal f_rst_d    : std_logic := '1';
      signal f_rd_stall : std_logic := '0';
      signal f_rd_addr  : std_logic_vector(31 downto 0);

      signal f_r : std_logic_vector(2 downto 0);
      signal f_n : std_logic_vector(2 downto 0);
      signal f_v : std_logic_vector(31 downto 0);

      attribute anyconst : boolean;
      attribute anyconst of f_r : signal is true;
      attribute anyconst of f_n : signal is true;
      attribute anyconst of f_v : signal is true;
   begin
      f_read <= accept and not (st_out and st_we_r);


      p_count : process (clk_i)
      begin
         if rising_edge(clk_i) then
            if accept = '1' then
               f_acc <= f_acc + 1;
               if f_acc = f_r then
                  f_we <= st_out and st_we_r;
               end if;
            end if;
            if f_read = '1' then
               f_racc <= f_racc + 1;
            end if;
            if dbus_ack_i = '1' then
               f_ack <= f_ack + 1;
            end if;
            if ack_read = '1' then
               f_rack <= f_rack + 1;
            end if;
            f_pop <= f_pop + w_pop_i;

            f_rst_d    <= rst_i;
            f_rd_stall <= rd_stb_i and dbus_stall_i and not rst_i;
            f_rd_addr  <= rd_addr_i;

            if rst_i = '1' then
               f_acc  <= "000";
               f_ack  <= "000";
               f_racc <= "000";
               f_rack <= "000";
               f_pop  <= "000";
            end if;
         end if;
      end process p_count;

      -- psl default clock is rising_edge(clk_i);

      -- The slave: an ACK only for a request accepted before, and the memory
      -- psl f_slave : assume always dbus_ack_i -> tag_cnt_r > 0;
      -- psl f_memory : assume always (ack_read and f_rack = f_n) -> dbus_data_i = f_v;

      -- PREPARE and WRITE: the contracts, a stalled read held, and no read
      -- in the cycle after a reset
      -- psl f_st_alone : assume always st_valid_r -> not rd_stb_i;
      -- psl f_st_room : assume always st_i -> (st_valid_r = '0' or st_acc = '1');
      -- psl f_out : assume always rd_stb_i -> tag_cnt_r < C_MAX_OUT;
      -- psl f_pops : assume always w_pop_i <= rq_cnt_r + to_nat(ack_read);
      -- psl f_rq_room : assume always f_read -> rq_cnt_r + reads_owed < C_MAX_OUT + w_pop_i;
      -- psl f_rd_hold : assume always (f_rd_stall and not rst_i) ->
      --    (rd_stb_i = '1' and rd_addr_i = f_rd_addr);
      -- psl f_quiet : assume always f_rst_d -> not rd_stb_i;

      -- The invariants
      -- psl f_tags : assert always rst_i = '0' -> tag_cnt_r = to_integer(f_acc - f_ack);
      -- psl f_owed : assert always rst_i = '0' -> reads_owed = to_integer(f_racc - f_rack);
      -- psl f_rq_cnt : assert always rst_i = '0' -> rq_cnt_r = to_integer(f_rack - f_pop);
      -- psl f_room : assert always rst_i = '0' -> rq_cnt_r + reads_owed <= C_MAX_OUT;

      gen_fifos : for i in 0 to C_MAX_OUT - 1 generate
         -- psl f_tag : assert always (rst_i = '0' and i < tag_cnt_r and f_ack + i = f_r) ->
         --    tags_r(i) = f_we;
         -- psl f_rq : assert always (rst_i = '0' and i < rq_cnt_r and f_pop + i = f_n) ->
         --    rq_r(i) = f_v;
      end generate gen_fifos;

      -- What WRITE sees: the ACK of request f_r taken for a read exactly when
      -- it is one. rq_o is rq_r, so f_rq says that WRITE finds read f_n in
      -- its place.
      -- psl f_ack_read : assert always (rst_i = '0' and dbus_ack_i = '1' and f_ack = f_r) ->
      --    ack_read = not f_we;

   end generate gen_formal;

end architecture synthesis;
