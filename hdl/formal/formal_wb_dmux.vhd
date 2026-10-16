-- The data bus decoder with checks of its ports, for SymbiYosys. Every
-- input is free, so the solver plays every master and every slave that
-- keep to the decoder's interface contracts, with three slaves.
--
-- THEORY OF OPERATION
-- p_owed counts, for each slave, the requests it accepted and has not yet
-- acknowledged, and m_owed counts those of the master. The assumptions are
-- the contracts of src/wb_dmux.vhd: STB only with CYC, and a slave's ACK
-- only while CYC is high and the slave owes one. The assertions:
-- - A slave's STB is high only with the master's CYC and STB, and only
--   when sel_i names the slave.
-- - No slave gets STB while another owes an ACK, so at most one slave
--   owes ACKs at any time.
-- - The master's request is accepted exactly when a slave accepts it, so
--   each request reaches one slave, and no slave gets a request that the
--   master did not make.
-- - The master's ACK is the ACK of the slave that owes ACKs, with that
--   slave's data, and the master is owed one then. The master is owed as
--   many ACKs as the slaves owe together, and no more than G_MAX_PENDING.
-- Since all the requests in flight go to one slave, which answers them in
-- order, the master gets its ACKs in the order of its requests.
-- The covers show a request that waits for another slave's ACKs, the most
-- ACKs owed, and a switch from one slave to another.
--
-- RESET
-- The first cycle is a reset.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

entity formal_wb_dmux is
   generic (
      G_SLAVES      : positive := 3;
      G_MAX_PENDING : positive := 3
   );
   port (
      clk_i     : in  std_logic;
      rst_i     : in  std_logic;
      sel_i     : in  std_logic_vector(1 downto 0);
      m_cyc_i   : in  std_logic;
      m_stb_i   : in  std_logic;
      s_stall_i : in  std_logic_vector(G_SLAVES - 1 downto 0);
      s_ack_i   : in  std_logic_vector(G_SLAVES - 1 downto 0);
      s_data_i  : in  std_logic_vector(32 * G_SLAVES - 1 downto 0)
   );
end entity formal_wb_dmux;

architecture synthesis of formal_wb_dmux is

   subtype t_count is natural range 0 to G_MAX_PENDING + 1;

   type t_counts is array (0 to G_SLAVES - 1) of t_count;

   signal sel     : natural range 0 to G_SLAVES - 1;
   signal m_stall : std_logic;
   signal m_ack   : std_logic;
   signal m_data  : std_logic_vector(31 downto 0);
   signal s_stb   : std_logic_vector(G_SLAVES - 1 downto 0);

   signal m_accept : std_logic;
   signal s_accept : std_logic_vector(G_SLAVES - 1 downto 0);
   signal owed     : t_counts := (others => 0);
   signal m_owed   : t_count  := 0;
   signal owing    : std_logic_vector(G_SLAVES - 1 downto 0);
   signal owed_sum : natural range 0 to G_SLAVES * (G_MAX_PENDING + 1);
   -- The ACK and the data of the slave that owes ACKs
   signal owner_ack : std_logic;
   signal owner_dat : std_logic_vector(31 downto 0);

begin

   sel <= to_integer(sel_i) when to_integer(sel_i) < G_SLAVES else
          0;

   m_accept <= m_cyc_i and m_stb_i and not m_stall;
   s_accept <= s_stb and not s_stall_i;


   p_comb : process (all)
      variable sum_v : natural range 0 to G_SLAVES * (G_MAX_PENDING + 1);
   begin
      sum_v     := 0;
      owner_ack <= '0';
      owner_dat <= (others => '0');
      for i in 0 to G_SLAVES - 1 loop
         sum_v := sum_v + owed(i);
         if owed(i) /= 0 then
            owing(i)  <= '1';
            owner_ack <= s_ack_i(i);
            owner_dat <= s_data_i(32 * i + 31 downto 32 * i);
         else
            owing(i) <= '0';
         end if;
      end loop;
      owed_sum <= sum_v;
   end process p_comb;


   p_owed : process (clk_i)
   begin
      if rising_edge(clk_i) then
         for i in 0 to G_SLAVES - 1 loop
            if s_accept(i) = '1' and s_ack_i(i) = '0' and owed(i) <= G_MAX_PENDING then
               owed(i) <= owed(i) + 1;
            elsif s_accept(i) = '0' and s_ack_i(i) = '1' then
               owed(i) <= owed(i) - 1;
            end if;
         end loop;

         if m_accept = '1' and m_ack = '0' and m_owed <= G_MAX_PENDING then
            m_owed <= m_owed + 1;
         elsif m_accept = '0' and m_ack = '1' and m_owed /= 0 then
            m_owed <= m_owed - 1;
         end if;

         if rst_i = '1' or m_cyc_i = '0' then
            owed   <= (others => 0);
            m_owed <= 0;
         end if;
      end if;
   end process p_owed;


   -- psl default clock is rising_edge(clk_i);
   -- psl f_initial_reset : assume rst_i;

   -- The master and the slaves
   -- psl f_sel : assume always to_integer(sel_i) < G_SLAVES;
   -- psl f_stb_cyc : assume always m_stb_i -> m_cyc_i;

   -- psl f_accept : assert always m_accept = (or s_accept);
   -- psl f_ack : assert always m_ack = owner_ack;
   -- psl f_ack_owed : assert always m_ack -> m_owed /= 0;
   -- psl f_data : assert always m_ack -> m_data = owner_dat;
   -- psl f_owed : assert always m_owed = owed_sum;
   -- psl f_max_pending : assert always m_owed <= G_MAX_PENDING;

   gen_slave : for i in 0 to G_SLAVES - 1 generate
      -- psl f_ack_slave : assume always s_ack_i(i) -> (m_cyc_i = '1' and owing(i) = '1');
      -- psl f_stb : assert always s_stb(i) -> (m_cyc_i = '1' and m_stb_i = '1' and sel = i);
      -- psl f_alone : assert always s_stb(i) -> owed_sum = owed(i);
      -- psl f_one_owner : assert always owing(i) -> owed_sum = owed(i);
   end generate gen_slave;

   -- psl c_wait : cover {m_stb_i and m_stall and not s_stall_i(sel)};
   -- psl c_full : cover {m_owed = G_MAX_PENDING};
   -- psl c_switch : cover {s_accept(0) = '1' and rst_i = '0'; [*1 to inf]; s_accept(1) = '1'};


   i_wb_dmux : entity work.wb_dmux
      generic map (
         G_SLAVES      => G_SLAVES,
         G_MAX_PENDING => G_MAX_PENDING
      )
      port map (
         clk_i     => clk_i,
         rst_i     => rst_i,
         sel_i     => sel,
         m_cyc_i   => m_cyc_i,
         m_stb_i   => m_stb_i,
         m_stall_o => m_stall,
         m_ack_o   => m_ack,
         m_data_o  => m_data,
         s_stb_o   => s_stb,
         s_stall_i => s_stall_i,
         s_ack_i   => s_ack_i,
         s_data_i  => s_data_i
      ); -- i_wb_dmux

end architecture synthesis;
