-- FETCH of the pipelined core (MICROARCH.md §3): a Wishbone
-- master on the 64-bit instruction bus, and a buffer of the words it has
-- read, which presents up to four of them to DECODE.
--
-- THEORY OF OPERATION
-- FETCH reads aligned pairs of words, one request per cycle, as far ahead
-- as the buffer has room. A request for pair p returns word 2p in bits
-- 31..0 and word 2p + 1 in bits 63..32. The requests are pipelined: several
-- may wait for their ACKs, which come back in order.
--
-- The buffer is a ring of C_DEPTH words. Its oldest word is at the address
-- addr_o. words_o(0 to count_o - 1) are the words at addr_o onwards, at
-- most four of them, which is the longest instruction (ISA.md §2). DECODE
-- takes the first consume_i of them at the end of the cycle.
--
-- A redirect empties the buffer and starts again at redirect_addr_i. The
-- requests still waiting for their ACKs belong to the old stream, so their
-- words are dropped as they arrive. A request that the bus stalls at that
-- moment must stay on the bus until it is accepted (Wishbone), so it is
-- dropped in the same way. If the new address is odd, the first pair's
-- low word is dropped too.
--
-- FETCH issues a request only while the buffer has room for every word
-- that may still arrive, counting those it will drop. So no ACK is ever
-- refused, and at most C_DEPTH / 2 requests are in flight.
--
-- The words read so far, and those still to arrive, lie in at most
-- C_DEPTH words from addr_o on, modulo 2^32. The core compares each store
-- with them, to find stores into fetched code (MICROARCH.md §5.5). The
-- range may hold words not in the buffer yet, which is safe.
--
-- stats_o reports the buffer's words, and the room held for the requests
-- in flight, in each cycle, for the fetch statistics (MICROARCH.md §8.1).
-- It leaves the stall to the pipeline, which sees the bus stall alone.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) The bus slave acknowledges every request, in order.
-- b) consume_i is at most count_o.
--
-- RESET
-- Synchronous. It empties the buffer, drops any request, and starts at
-- address 0 (ISA.md §8.1).

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use work.nice_pkg.all;
   use work.pipe_pkg.all;

entity pipe_fetch is
   generic (
      -- Adds the invariants that a formal proof needs.
      G_FORMAL : boolean := false
   );
   port (
      clk_i           : in  std_logic;
      rst_i           : in  std_logic;

      -- Instruction bus: read only
      ibus_cyc_o      : out std_logic;
      ibus_stb_o      : out std_logic;
      ibus_stall_i    : in  std_logic;
      ibus_ack_i      : in  std_logic;
      ibus_addr_o     : out std_logic_vector(30 downto 0);
      ibus_data_i     : in  std_logic_vector(63 downto 0);

      -- Start again at redirect_addr_i
      redirect_i      : in  std_logic;
      redirect_addr_i : in  std_logic_vector(31 downto 0);
      -- No new requests, for example after a halt
      stop_i          : in  std_logic;

      -- The words for DECODE, and the 32-word block after the one that
      -- held addr_o a cycle ago, for the check of stores into fetched code
      addr_o          : out std_logic_vector(31 downto 0);
      blk_o           : out std_logic_vector(31 downto 5);
      words_o         : out t_words4;
      count_o         : out natural range 0 to 4;
      consume_i       : in  natural range 0 to 4;
      -- One past the last word fetched or being fetched

      -- For the fetch statistics: the fields of FETCH, the rest 0
      stats_o         : out t_fetch_events
   );
end entity pipe_fetch;

architecture synthesis of pipe_fetch is

   constant C_DEPTH : natural := 16;

   type t_ring is array (0 to C_DEPTH - 1) of std_logic_vector(31 downto 0);

   signal ring_r  : t_ring;
   signal rd_r    : natural range 0 to C_DEPTH - 1;        -- Oldest word
   signal count_r : natural range 0 to C_DEPTH;
   signal head_r  : std_logic_vector(31 downto 0);         -- Its address
   signal blk_r   : std_logic_vector(31 downto 5);         -- The block after its block, a cycle late

   signal stb_r     : std_logic                     := '0';
   signal req_r     : std_logic_vector(30 downto 0);            -- The pair on the bus
   signal pair_r    : std_logic_vector(30 downto 0);            -- The next pair to request
   signal pending_r : natural range 0 to C_DEPTH / 2 := 0;      -- Requests without their ACK
   signal drop_r    : natural range 0 to C_DEPTH / 2;           -- Of those, to drop
   signal odd_r     : std_logic;                                -- Drop the next low word

   signal load : std_logic;
   signal room : std_logic;
   signal want : std_logic;

   -- head_r after DECODE takes 1 to 4 words, computed ahead so that
   -- consume_i only picks one
   type t_heads is array (1 to 4) of std_logic_vector(31 downto 0);

   signal head_next : t_heads;

begin

   ibus_cyc_o  <= '1' when pending_r > 0 else '0';
   ibus_stb_o  <= stb_r;
   ibus_addr_o <= req_r;

   addr_o  <= head_r;
   blk_o   <= blk_r;
   count_o <= minimum(count_r, 4);

   gen_words : for i in 0 to 3 generate
      words_o(i) <= ring_r((rd_r + i) mod C_DEPTH);
   end generate gen_words;

   gen_heads : for i in 1 to 4 generate
      head_next(i) <= head_r + i;
   end generate gen_heads;

   -- A new request, when the bus can take it and every word that may still
   -- arrive has room.
   room <= '1' when count_r + 2 * pending_r + 2 <= C_DEPTH else
           '0';
   want <= '1' when rst_i = '0' and redirect_i = '0' and stop_i = '0' and
                    (stb_r = '0' or ibus_stall_i = '0') else
           '0';
   load <= want and room;


   p_stats : process (all)
      variable stats_v : t_fetch_events;
   begin
      stats_v       := C_FETCH_EVENTS_NONE;
      stats_v.count := count_r;
      stats_v.held  := count_r + 2 * pending_r;
      stats_v.full  := want and not room;
      stats_v.pair  := ibus_ack_i;
      stats_o       <= stats_v;
   end process p_stats;


   p_fetch : process (clk_i)
      variable count_v   : natural range 0 to C_DEPTH;
      variable pending_v : natural range 0 to C_DEPTH / 2;
      variable wr_v      : natural range 0 to C_DEPTH - 1;
   begin
      if rising_edge(clk_i) then
         count_v   := count_r - consume_i;
         pending_v := pending_r;

         if ibus_stall_i = '0' then
            stb_r <= '0';
         end if;

         -- The ACK of the oldest request
         if ibus_ack_i = '1' then
            pending_v := pending_v - 1;
            if drop_r > 0 then
               drop_r <= drop_r - 1;
            else
               wr_v := (rd_r + count_r) mod C_DEPTH;
               if odd_r = '1' then
                  ring_r(wr_v) <= ibus_data_i(63 downto 32);
                  count_v      := count_v + 1;
                  odd_r        <= '0';
               else
                  ring_r(wr_v)                     <= ibus_data_i(31 downto 0);
                  ring_r((wr_v + 1) mod C_DEPTH)   <= ibus_data_i(63 downto 32);
                  count_v                          := count_v + 2;
               end if;
            end if;
         end if;

         if load = '1' then
            stb_r     <= '1';
            req_r     <= pair_r;
            pair_r    <= pair_r + 1;
            pending_v := pending_v + 1;
         end if;

         rd_r      <= (rd_r + consume_i) mod C_DEPTH;
         if consume_i /= 0 then
            head_r <= head_next(consume_i);
         end if;
         -- The block after head_r's, a cycle late, from the register
         -- alone: head_r moves by at most four words a cycle, so the
         -- block after the current one is this or the one after it, and
         -- WRITE compares with both. In the cycle after a redirect it is
         -- stale, and a store may retire then, but this buffer is empty
         -- and every request in flight is dropped (f_redirect), so the
         -- first pair of the new stream is accepted after the store and
         -- sees it, and its block is head_r's (MICROARCH.md §5.5).
         blk_r <= next_block(head_r, 5);
         count_r   <= count_v;
         pending_r <= pending_v;

         if redirect_i = '1' then
            -- Every request still in flight belongs to the old stream.
            drop_r  <= pending_v;
            count_r <= 0;
            head_r  <= redirect_addr_i;
            pair_r  <= redirect_addr_i(31 downto 1);
            odd_r   <= redirect_addr_i(0);
         end if;

         if rst_i = '1' then
            stb_r     <= '0';
            pending_r <= 0;
            drop_r    <= 0;
            count_r   <= 0;
            rd_r      <= 0;
            head_r    <= (others => '0');
            blk_r     <= (others => '0');
            req_r     <= (others => '0');
            pair_r    <= (others => '0');
            odd_r     <= '0';
         end if;
      end if;
   end process p_fetch;


   -- The proof of formal/pipe_fetch.sby. The memory holds the value f_v at
   -- the address f_a, both free but constant, and any value elsewhere. The
   -- assertions say that DECODE only ever sees f_v at f_a, and that the
   -- bus port keeps to pipelined Wishbone. The invariants tie the buffer
   -- and the requests in flight to the addresses, so that k-induction can
   -- prove it all for every cycle.

   gen_formal : if G_FORMAL generate
      type t_hits is array (natural range <>) of std_logic;

      signal f_a : std_logic_vector(31 downto 0);
      signal f_v : std_logic_vector(31 downto 0);
      -- For each request in flight, oldest first: it reads the pair of f_a.
      signal f_hits : t_hits(0 to C_DEPTH / 2);
      signal f_live : natural range 0 to C_DEPTH / 2;   -- Requests not dropped
      signal f_good : std_logic;                         -- An ACK holds f_v
      signal end_r  : std_logic_vector(31 downto 0);     -- addr_o to end_r - 1 holds the words

      attribute anyconst : boolean;
      attribute anyconst of f_a : signal is true;
      attribute anyconst of f_v : signal is true;
   begin
      f_live <= pending_r - drop_r when drop_r <= pending_r else 0;
      f_good <= '1' when (f_a(0) = '0' and ibus_data_i(31 downto 0) = f_v) or
                         (f_a(0) = '1' and ibus_data_i(63 downto 32) = f_v) else
                '0';


      p_end : process (clk_i)
      begin
         if rising_edge(clk_i) then
            if load = '1' then
               end_r <= (pair_r & '0') + 2;
            end if;
            if redirect_i = '1' then
               end_r <= redirect_addr_i;
            end if;
            if rst_i = '1' then
               end_r <= (others => '0');
            end if;
         end if;
      end process p_end;

      p_hits : process (clk_i)
         variable hits_v : t_hits(0 to C_DEPTH / 2 + 1);
         variable n_v    : natural range 0 to C_DEPTH / 2 + 1;
      begin
         if rising_edge(clk_i) then
            hits_v := f_hits & '0';
            n_v    := pending_r;
            if ibus_ack_i = '1' and n_v > 0 then
               hits_v := hits_v(1 to C_DEPTH / 2 + 1) & '0';
               n_v    := n_v - 1;
            end if;
            if load = '1' and n_v <= C_DEPTH / 2 then
               hits_v(n_v) := '1' when pair_r = f_a(31 downto 1) else '0';
            end if;
            f_hits <= hits_v(0 to C_DEPTH / 2);
         end if;
      end process p_hits;

      -- psl default clock is rising_edge(clk_i);

      -- The slave: an ACK only for a request accepted, and the memory
      -- psl f_ack : assume always ibus_ack_i -> pending_r > to_nat(stb_r);
      -- psl f_memory : assume always (ibus_ack_i and f_hits(0)) -> f_good;

      -- The port, as formal/wb_master_check.vhd checks it from outside
      -- psl f_stb : assert always rst_i = '0' -> (stb_r = '1' -> pending_r >= 1);
      -- psl f_stall_hold : assert always
      --    {stb_r and ibus_stall_i and not rst_i} |=> {rst_i = '1' or (stb_r = '1' and stable(req_r))};
      -- psl f_cyc_hold : assert always
      --    {pending_r > to_nat(stb_r) and ibus_ack_i = '0' and rst_i = '0'} |=> {pending_r > 0};
      -- psl f_cyc_accept : assert always
      --    {stb_r and not ibus_stall_i and not rst_i} |=> {rst_i = '1' or pending_r > 0};
      -- psl f_reset : assert always {rst_i} |=> {pending_r = 0 and stb_r = '0'};

      -- After a redirect, no word is held and no request is of the new
      -- stream, so a store in that cycle is seen (MICROARCH.md §5.5)
      -- psl f_redirect : assert always
      --    {redirect_i and not rst_i} |=>
      --    {rst_i = '1' or (count_r = 0 and drop_r = pending_r)};

      -- A stop, the halt of pipeline.vhd, makes no new request: one on the
      -- bus stays only while it is stalled
      -- psl f_stop : assert always
      --    {stop_i and not (stb_r and ibus_stall_i) and not rst_i} |=> {rst_i = '1' or stb_r = '0'};

      -- The oldest word moves by at most four words a cycle, so its block
      -- is the one before blk_r or blk_r itself, and WRITE's compare with
      -- those and the next covers the range (MICROARCH.md §5.5,
      -- formal/formal_nice_pkg.vhd); and the range is at most C_DEPTH
      -- words
      -- psl f_blk : assert always {not redirect_i and not rst_i} |=>
      --    {rst_i = '1' or head_r(31 downto 5) = blk_r - 1 or head_r(31 downto 5) = blk_r};
      -- psl f_span : assert always rst_i = '0' -> end_r - head_r <= C_DEPTH;

      -- The invariants
      -- psl f_drop : assert always rst_i = '0' -> drop_r <= pending_r;
      -- psl f_room : assert always rst_i = '0' -> count_r + 2 * pending_r <= C_DEPTH;
      -- psl f_next : assert always rst_i = '0' ->
      --    ((pair_r - f_live) & odd_r) = head_r + count_r;
      -- psl f_odd : assert always rst_i = '0' -> (odd_r = '1' -> count_r = 0);
      -- psl f_end : assert always rst_i = '0' ->
      --    end_r = (pair_r & '0') + to_nat(odd_r = '1' and f_live = 0);
      -- psl f_req : assert always rst_i = '0' ->
      --    ((stb_r = '1' and f_live > 0) -> req_r = pair_r - 1);

      gen_hits : for i in 0 to C_DEPTH / 2 - 1 generate
         -- psl f_hit : assert always (rst_i = '0' and i < f_live) ->
         --    f_hits(minimum(drop_r + i, C_DEPTH / 2)) = to_sl(pair_r - f_live + i = f_a(31 downto 1));
      end generate gen_hits;

      gen_ring : for j in 0 to C_DEPTH - 1 generate
         -- psl f_ring : assert always (rst_i = '0' and j < count_r and head_r + j = f_a) ->
         --    ring_r((rd_r + j) mod C_DEPTH) = f_v;
      end generate gen_ring;

      -- What DECODE sees, and the range of fetched words

      gen_f_words : for i in 0 to 3 generate
         -- psl f_word : assert always (rst_i = '0' and i < count_o and head_r + i = f_a) ->
         --    words_o(i) = f_v;
      end generate gen_f_words;

      -- psl f_range : assert always rst_i = '0' -> end_r - head_r >= count_r;
   end generate gen_formal;

end architecture synthesis;
