-- FETCH and ICACHE of the pipelined core (MICROARCH.md §3): a Wishbone
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
-- The words read so far, and those still to arrive, lie in one range,
-- addr_o to end_o - 1, modulo 2^32. The core compares each store with it,
-- to find stores into fetched code (MICROARCH.md §5.5). The range may hold
-- words not in the buffer yet, which is safe.
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

      -- The words for DECODE
      addr_o          : out std_logic_vector(31 downto 0);
      words_o         : out t_words4;
      count_o         : out natural range 0 to 4;
      consume_i       : in  natural range 0 to 4;
      -- One past the last word fetched or being fetched
      end_o           : out std_logic_vector(31 downto 0)
   );
end entity pipe_fetch;

architecture synthesis of pipe_fetch is

   constant C_DEPTH : natural := 16;

   type t_ring is array (0 to C_DEPTH - 1) of std_logic_vector(31 downto 0);

   signal ring_r  : t_ring;
   signal rd_r    : natural range 0 to C_DEPTH - 1;        -- Oldest word
   signal count_r : natural range 0 to C_DEPTH;
   signal head_r  : std_logic_vector(31 downto 0);         -- Its address
   signal end_r   : std_logic_vector(31 downto 0);

   signal stb_r     : std_logic                     := '0';
   signal req_r     : std_logic_vector(30 downto 0);         -- The pair on the bus
   signal pair_r    : std_logic_vector(30 downto 0);         -- The next pair to request
   signal pending_r : natural range 0 to C_DEPTH / 2 := 0;      -- Requests without their ACK
   signal drop_r    : natural range 0 to C_DEPTH / 2;        -- Of those, to drop
   signal odd_r     : std_logic;                             -- Drop the next low word

   signal load : std_logic;

begin

   ibus_cyc_o  <= '1' when pending_r > 0 else '0';
   ibus_stb_o  <= stb_r;
   ibus_addr_o <= req_r;

   addr_o  <= head_r;
   end_o   <= end_r;
   count_o <= minimum(count_r, 4);

   gen_words : for i in 0 to 3 generate
      words_o(i) <= ring_r((rd_r + i) mod C_DEPTH);
   end generate gen_words;

   -- A new request, when the bus can take it and every word that may still
   -- arrive has room.
   load <= '1' when rst_i = '0' and redirect_i = '0' and stop_i = '0' and
                    (stb_r = '0' or ibus_stall_i = '0') and
                    count_r + 2 * pending_r + 2 <= C_DEPTH else
           '0';


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
            end_r     <= (pair_r & '0') + 2;
            pending_v := pending_v + 1;
         end if;

         rd_r      <= (rd_r + consume_i) mod C_DEPTH;
         head_r    <= head_r + consume_i;
         count_r   <= count_v;
         pending_r <= pending_v;

         if redirect_i = '1' then
            -- Every request still in flight belongs to the old stream.
            drop_r  <= pending_v;
            count_r <= 0;
            head_r  <= redirect_addr_i;
            end_r   <= redirect_addr_i;
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
            end_r     <= (others => '0');
            req_r     <= (others => '0');
            pair_r    <= (others => '0');
            odd_r     <= '0';
         end if;
      end if;
   end process p_fetch;

end architecture synthesis;
