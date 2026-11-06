-- The fetch statistics of MICROARCH.md §8.1: 32 words of I/O with counters
-- of what the pipelined core does in each cycle, so that a programmer can
-- see where the cycles of a program go.
--
--   0x00  FS_CTRL      0x03  FS_DSTALL    0x08-0x0C  FS_FLUSH + n   0x1F  reads 0
--   0x01  FS_CYCLES    0x04  FS_JUMPS     0x10-0x1E  FS_CAUSE + n
--   0x02  FS_ISTALL    0x05-0x07, 0x0D-0x0F  read 0
--
-- THEORY OF OPERATION
-- The counters count in the cycles in which the run bit of FS_CTRL is 1
-- and run_i is high. A system drives run_i with "the core is running", as
-- it drives that of perf.vhd, so that the counters stop while the core is
-- held, paused, or halted. In each cycle counted, FS_CYCLES and
-- FS_CAUSE + cause count one, FS_ISTALL, FS_DSTALL, and FS_JUMPS count
-- the events of events_i in that cycle, and FS_FLUSH + fwhy counts a
-- flush. So the causes sum to FS_CYCLES. All counters are 32 bits wide
-- and wrap.
--
-- A write to FS_CTRL sets the run bit to bit 0 of the value written. If
-- bit 1 is set, it also clears the counters to 0. Either takes effect from
-- the next cycle. A read of FS_CTRL returns the run bit. A read of any
-- other word returns it as it is in the cycle the read is accepted.
--
-- With G_ENABLE false, there are no counters, and every read returns 0.
-- The address range then stays as it is, as MICROARCH.md §8.1 says.
--
-- The port is a pipelined Wishbone slave. It never stalls, and it
-- acknowledges each request in the cycle after it accepts it. Writes to
-- words other than FS_CTRL are ignored.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) STB is high only for requests to the statistics: the bus decoder
--    decodes 0xFFFFFF60-0xFFFFFF7F, and wb_addr_i is bits 4..0 of the
--    address.
-- b) events_i describes one cycle of the core, and is C_FETCH_EVENTS_NONE
--    for a core without the pipeline's stages.
-- c) run_i is low while the core is held, paused, or halted: a system drives
--    it with "not paused_o and not halted_o" of the core, and low too while
--    it holds the core. It defaults to '1'.
--
-- RESET
-- Synchronous. It clears the counters, sets the run bit, and drops any ACK
-- owed.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use work.pipe_pkg.all;

entity fetch_stats is
   generic (
      -- False leaves out the counters.
      G_ENABLE : boolean := true;
      -- Adds the properties and invariants of formal/fetch_stats.sby.
      G_FORMAL : boolean := false
   );
   port (
      clk_i      : in  std_logic;
      rst_i      : in  std_logic;
      -- The core is running
      run_i      : in  std_logic                     := '1';

      -- What the core did in a cycle
      events_i   : in  t_fetch_events;

      wb_cyc_i   : in  std_logic;
      wb_stb_i   : in  std_logic;
      wb_stall_o : out std_logic;
      wb_ack_o   : out std_logic                     := '0';
      wb_we_i    : in  std_logic;
      wb_addr_i  : in  std_logic_vector(4 downto 0);
      wb_data_i  : in  std_logic_vector(31 downto 0);
      wb_data_o  : out std_logic_vector(31 downto 0) := (others => '0')
   );
end entity fetch_stats;

architecture synthesis of fetch_stats is

   -- The control register, the counters in the order of their addresses
   -- from 0x01, and the first word of each group of bins
   constant C_CTRL   : natural := 16#00#;
   constant C_CYCLES : natural := 0;
   constant C_ISTALL : natural := 1;
   constant C_DSTALL : natural := 2;
   constant C_JUMPS  : natural := 3;
   constant C_COUNTS : natural := 4;
   constant C_FLUSH  : natural := 16#08#;
   constant C_CAUSE  : natural := 16#10#;

   type t_counts is array (natural range <>) of std_logic_vector(31 downto 0);

   signal accept : std_logic;

begin

   accept     <= wb_cyc_i and wb_stb_i;
   wb_stall_o <= '0';


   gen_enable : if G_ENABLE generate
      signal run_r   : std_logic := '1';
      signal count_r : t_counts(0 to C_COUNTS - 1);
      signal flush_r : t_counts(0 to C_FLUSHES - 1);
      signal cause_r : t_counts(0 to C_CAUSES - 1);
   begin

      p_count : process (clk_i)

         procedure add(i : natural;
                       b : std_logic) is
         begin
            if b = '1' then
               count_r(i) <= count_r(i) + 1;
            end if;
         end procedure add;

         procedure clear is
         begin
            count_r <= (others => (others => '0'));
            flush_r <= (others => (others => '0'));
            cause_r <= (others => (others => '0'));
         end procedure clear;

      begin
         if rising_edge(clk_i) then
            if run_r = '1' and run_i = '1' then
               add(C_CYCLES, '1');
               add(C_ISTALL, events_i.istall);
               add(C_DSTALL, events_i.dstall);
               add(C_JUMPS, events_i.jump);
               if events_i.flush = '1' then
                  flush_r(events_i.fwhy) <= flush_r(events_i.fwhy) + 1;
               end if;
               cause_r(events_i.cause) <= cause_r(events_i.cause) + 1;
            end if;

            if accept = '1' and wb_we_i = '1' and to_integer(wb_addr_i) = C_CTRL then
               run_r <= wb_data_i(0);
               if wb_data_i(1) = '1' then
                  clear;
               end if;
            end if;

            if rst_i = '1' then
               run_r <= '1';
               clear;
            end if;
         end if;
      end process p_count;


      p_bus : process (clk_i)
         variable n_v : natural range 0 to 31;
      begin
         if rising_edge(clk_i) then
            wb_ack_o <= accept;

            if accept = '1' and wb_we_i = '0' then
               n_v       := to_integer(wb_addr_i);
               wb_data_o <= (others => '0');
               if n_v = C_CTRL then
                  wb_data_o(0) <= run_r;
               elsif n_v < 1 + C_COUNTS then
                  wb_data_o <= count_r(n_v - 1);
               elsif n_v >= C_FLUSH and n_v < C_FLUSH + C_FLUSHES then
                  wb_data_o <= flush_r(n_v - C_FLUSH);
               elsif n_v >= C_CAUSE and n_v < C_CAUSE + C_CAUSES then
                  wb_data_o <= cause_r(n_v - C_CAUSE);
               end if;
            end if;

            if rst_i = '1' then
               wb_ack_o <= '0';
            end if;
         end if;
      end process p_bus;


      -- The proof of formal/fetch_stats.sby. The invariant ties the
      -- counters to each other: the causes sum to FS_CYCLES. It holds
      -- after reset and a clear, and each cycle counted keeps it, so
      -- k-induction proves it in one step. The other assertions say what
      -- each cycle does to the counters, and that a read returns the word
      -- as it is in the cycle the read is accepted.

      gen_formal : if G_FORMAL generate
         -- The causes, padded to 16 bins for the tree below
         type t_bins is array (0 to 15) of std_logic_vector(31 downto 0);

         signal f_ctrl    : std_logic;                       -- A write to FS_CTRL
         signal f_expect  : std_logic_vector(31 downto 0);   -- What a read returns
         signal f_same    : std_logic;                       -- The counters did not change
         signal f_zero    : std_logic;                       -- The counters are clear
         signal f_bins    : t_bins;
         signal f_last_r  : std_logic_vector(31 downto 0);
         signal f_count_r : t_counts(0 to C_COUNTS - 1);
         signal f_flush_r : t_counts(0 to C_FLUSHES - 1);
         signal f_cause_r : t_counts(0 to C_CAUSES - 1);
         signal f_ev_r    : t_fetch_events;
         -- A binary tree over the bins: node n has the children 2n and
         -- 2n + 1, and nodes 8 to 15 have the bins as children. Each node
         -- counts the cycles counted with a cause in its subtree.
         signal f_tree_r : t_counts(1 to 15);
      begin

         f_ctrl <= '1' when accept = '1' and wb_we_i = '1' and to_integer(wb_addr_i) = C_CTRL else
                   '0';
         f_same <= '1' when count_r = f_count_r and flush_r = f_flush_r and cause_r = f_cause_r else
                   '0';
         f_zero <= '1' when count_r = (count_r'range => X"00000000") and
                            flush_r = (flush_r'range => X"00000000") and
                            cause_r = (cause_r'range => X"00000000") else
                   '0';

         gen_bins : for n in 0 to C_CAUSES - 1 generate
            f_bins(n) <= cause_r(n);
         end generate gen_bins;

         gen_pad : for n in C_CAUSES to 15 generate
            f_bins(n) <= X"00000000";
         end generate gen_pad;


         p_expect : process (all)
            variable n_v : natural range 0 to 31;
         begin
            n_v := to_integer(wb_addr_i);
            if n_v = C_CTRL then
               f_expect <= (0 => run_r, others => '0');
            elsif n_v < 1 + C_COUNTS then
               f_expect <= count_r(n_v - 1);
            elsif n_v >= C_FLUSH and n_v < C_FLUSH + C_FLUSHES then
               f_expect <= flush_r(n_v - C_FLUSH);
            elsif n_v >= C_CAUSE and n_v < C_CAUSE + C_CAUSES then
               f_expect <= cause_r(n_v - C_CAUSE);
            else
               f_expect <= (others => '0');
            end if;
         end process p_expect;


         p_prev : process (clk_i)
         begin
            if rising_edge(clk_i) then
               f_last_r  <= f_expect;
               f_count_r <= count_r;
               f_flush_r <= flush_r;
               f_cause_r <= cause_r;
               f_ev_r    <= events_i;

               if run_r = '1' and run_i = '1' then
                  for n in 1 to 15 loop
                     for d in 1 to 4 loop
                        if (16 + events_i.cause) / 2 ** d = n then
                           f_tree_r(n) <= f_tree_r(n) + 1;
                        end if;
                     end loop;
                  end loop;
               end if;
               if rst_i = '1' or (f_ctrl = '1' and wb_data_i(1) = '1') then
                  f_tree_r <= (others => (others => '0'));
               end if;
            end if;
         end process p_prev;

         -- psl default clock is rising_edge(clk_i);

         -- The invariants. The root counts every cycle counted, and each node
         -- is the sum of its children, so the causes sum to FS_CYCLES.
         -- psl f_root : assert always rst_i = '0' -> f_tree_r(1) = count_r(C_CYCLES);

         gen_tree : for n in 1 to 7 generate
            -- psl f_node : assert always rst_i = '0' ->
            --    f_tree_r(n) = f_tree_r(2 * n) + f_tree_r(2 * n + 1);
         end generate gen_tree;

         gen_leaves : for n in 8 to 15 generate
            -- psl f_leaf : assert always rst_i = '0' ->
            --    f_tree_r(n) = f_bins(2 * n - 16) + f_bins(2 * n - 15);
         end generate gen_leaves;

         -- A cycle counted adds one to FS_CYCLES and to the bin of its
         -- cause, and a flush to the bin of its cause, and each event to
         -- its counter. Stopped counters keep their values, whether the
         -- run bit or run_i stops them, and a write of 1 to FS_CTRL starts
         -- them without a clear.
         -- psl f_cycle : assert always
         --    {run_r and run_i and not (f_ctrl and wb_data_i(1)) and not rst_i} |=>
         --    {count_r(C_CYCLES) = f_count_r(C_CYCLES) + 1 and
         --     cause_r(f_ev_r.cause) = f_cause_r(f_ev_r.cause) + 1 and
         --     count_r(C_ISTALL) = f_count_r(C_ISTALL) + to_nat(f_ev_r.istall) and
         --     count_r(C_DSTALL) = f_count_r(C_DSTALL) + to_nat(f_ev_r.dstall) and
         --     count_r(C_JUMPS) = f_count_r(C_JUMPS) + to_nat(f_ev_r.jump) and
         --     flush_r(f_ev_r.fwhy) = f_flush_r(f_ev_r.fwhy) + to_nat(f_ev_r.flush)};
         -- psl f_stopped : assert always
         --    {not run_r and not f_ctrl and not rst_i} |=> {f_same and not run_r};
         -- psl f_paused : assert always
         --    {not run_i and not f_ctrl and not rst_i} |=> {f_same = '1' and run_r = prev(run_r)};
         -- psl f_start : assert always
         --    {run_r = '0' and f_ctrl = '1' and wb_data_i(1 downto 0) = "01" and rst_i = '0'} |=>
         --    {f_same and run_r};
         -- psl f_stop : assert always
         --    {f_ctrl and not wb_data_i(0) and not rst_i} |=> {run_r = '0'};

         -- A clear and a reset
         -- psl f_clear : assert always
         --    {(f_ctrl and wb_data_i(1)) or rst_i} |=>
         --    {f_zero};
         -- psl f_reset : assert always {rst_i} |=> {run_r};

         -- A read
         -- psl f_read : assert always
         --    {accept and not wb_we_i and not rst_i} |=> {wb_data_o = f_last_r};
      end generate gen_formal;

   else generate

      p_bus : process (clk_i)
      begin
         if rising_edge(clk_i) then
            wb_ack_o  <= accept;
            wb_data_o <= (others => '0');

            if rst_i = '1' then
               wb_ack_o <= '0';
            end if;
         end if;
      end process p_bus;

   end generate gen_enable;

end architecture synthesis;
