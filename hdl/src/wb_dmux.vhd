-- The data bus decoder of MICROARCH.md §8: one pipelined Wishbone B4
-- master, G_SLAVES slaves, and the ACKs kept in the order of the requests.
--
-- THEORY OF OPERATION
-- The instantiator decodes the address into sel_i, the index of the slave
-- that the request goes to, so this unit holds no address map. It passes
-- STB on to that slave, and the slave's STALL back. CYC, WE, ADDR, and the
-- write data go from the master to every slave directly, past this unit.
--
-- Each slave answers its requests in order, but two slaves answer at their
-- own pace: the math unit holds the ACK of a read for up to 65 cycles. So
-- a request to slave s is passed on only while no other slave owes an ACK.
-- Otherwise the master sees STALL, and the slave sees no STB. All the
-- requests in flight then go to one slave, owner_r, and its ACKs come back
-- in the order of the requests. count_r counts the ACKs that owner_r owes,
-- at most G_MAX_PENDING, beyond which the master sees STALL too. The ACK
-- and the read data go back from owner_r alone.
--
-- The forward path is combinational: STB and STALL pass in the cycle the
-- master raises its request, with no cycle of latency, so a store accepted
-- in cycle c reaches the memory in cycle c, before an instruction fetch
-- accepted in cycle c + 1. The choice of whether a request may pass
-- depends on count_r and owner_r only, not on this cycle's ACK, so no
-- path runs from a slave's ACK to a slave's STB. A request to another
-- slave thus waits one cycle after the last ACK it waits for.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) The master raises STB only with CYC, as Wishbone requires. Dropping
--    CYC abandons the requests in flight, and their ACKs are not passed on.
-- b) Each slave sends ACK only while CYC is high, and only for a request
--    it accepted, in the order of its requests. An ACK from a slave that
--    owes none is ignored.
-- c) A slave's ACK comes in a cycle after the one that accepted its
--    request, never in the same cycle.
--
-- RESET
-- Synchronous. It forgets the ACKs owed.

library ieee;
   use ieee.std_logic_1164.all;

entity wb_dmux is
   generic (
      G_SLAVES      : positive;
      -- The most ACKs owed at a time
      G_MAX_PENDING : positive := 4
   );
   port (
      clk_i     : in  std_logic;
      rst_i     : in  std_logic;

      -- The slave that the master's request goes to, from its address
      sel_i     : in  natural range 0 to G_SLAVES - 1;

      -- The master
      m_cyc_i   : in  std_logic;
      m_stb_i   : in  std_logic;
      m_stall_o : out std_logic;
      m_ack_o   : out std_logic;
      m_data_o  : out std_logic_vector(31 downto 0);

      -- The slaves, slave i in bit i, and in bits 32 * i + 31 .. 32 * i
      s_stb_o   : out std_logic_vector(G_SLAVES - 1 downto 0);
      s_stall_i : in  std_logic_vector(G_SLAVES - 1 downto 0);
      s_ack_i   : in  std_logic_vector(G_SLAVES - 1 downto 0);
      s_data_i  : in  std_logic_vector(32 * G_SLAVES - 1 downto 0)
   );
end entity wb_dmux;

architecture synthesis of wb_dmux is

   signal owner_r : natural range 0 to G_SLAVES - 1  := 0;
   signal count_r : natural range 0 to G_MAX_PENDING := 0;

   signal allow  : std_logic;
   signal accept : std_logic;
   signal ack    : std_logic;

begin

   allow <= '1' when count_r = 0 or (owner_r = sel_i and count_r < G_MAX_PENDING) else
            '0';


   p_stb : process (all)
   begin
      s_stb_o        <= (others => '0');
      s_stb_o(sel_i) <= m_cyc_i and m_stb_i and allow;
   end process p_stb;


   m_stall_o <= not allow or s_stall_i(sel_i);
   accept    <= m_cyc_i and m_stb_i and allow and not s_stall_i(sel_i);
   ack       <= s_ack_i(owner_r) when count_r /= 0 else
                '0';
   m_ack_o   <= ack;
   m_data_o  <= s_data_i(32 * owner_r + 31 downto 32 * owner_r);


   p_count : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if accept = '1' then
            owner_r <= sel_i;
         end if;

         if m_cyc_i = '0' then
            count_r <= 0;
         elsif accept = '1' and ack = '0' then
            count_r <= count_r + 1;
         elsif accept = '0' and ack = '1' then
            count_r <= count_r - 1;
         end if;

         if rst_i = '1' then
            count_r <= 0;
         end if;
      end if;
   end process p_count;

end architecture synthesis;
