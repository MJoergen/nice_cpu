-- The fetch statistics of MICROARCH.md §8.1: 48 words of I/O with counters
-- of what FETCH and DECODE of the pipelined core do in each cycle, so that
-- the size of FETCH's buffer can be judged.
--
--   0x10  FS_CTRL      0x15  FS_STALL     0x1A  FS_MIN       0x1D-0x1F  read 0
--   0x11  FS_CYCLES    0x16  FS_PAIRS     0x1B  FS_MAX       0x20-0x3F  FS_HIST + n
--   0x12  FS_STARVE    0x17  FS_WORDS     0x1C  FS_HELD_MAX
--   0x13  FS_BLOCKED   0x18  FS_JUMPS
--   0x14  FS_FULL      0x19  FS_FLUSHES
--
-- THEORY OF OPERATION
-- The counters count in the cycles in which the run bit of FS_CTRL is 1
-- and run_i is high. A system drives run_i with "the core is running", as
-- it drives that of perf.vhd, so that the counters stop while the core is
-- held or has halted. In each cycle counted, FS_CYCLES and FS_HIST + count
-- count one, and each other counter counts the events of events_i in that
-- cycle. FS_MIN and FS_MAX follow the smallest and largest count, and
-- FS_HELD_MAX the largest held. All counters are 32 bits wide and wrap.
--
-- A write to FS_CTRL sets the run bit to bit 0 of the value written. If
-- bit 1 is set, it also clears the counters: FS_MIN to 31, and every other
-- to 0. Either takes effect from the next cycle. A read of FS_CTRL returns
-- the run bit. A read of any other word returns it as it is in the cycle
-- the read is accepted.
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
--    decodes 0xFFFFFF50-0xFFFFFF7F, and wb_addr_i is bits 5..0 of the
--    address.
-- b) events_i describes one cycle of the core, and is C_FETCH_EVENTS_NONE
--    for a core without FETCH and DECODE.
-- c) run_i is low while the core is held or halted. It defaults to '1'.
--
-- RESET
-- Synchronous. It clears the counters, sets the run bit, and drops any ACK
-- owed.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;
   use ieee.numeric_std.to_unsigned;

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

      -- What FETCH and DECODE did in this cycle
      events_i   : in  t_fetch_events;

      wb_cyc_i   : in  std_logic;
      wb_stb_i   : in  std_logic;
      wb_stall_o : out std_logic;
      wb_ack_o   : out std_logic                     := '0';
      wb_we_i    : in  std_logic;
      wb_addr_i  : in  std_logic_vector(5 downto 0);
      wb_data_i  : in  std_logic_vector(31 downto 0);
      wb_data_o  : out std_logic_vector(31 downto 0) := (others => '0')
   );
end entity fetch_stats;

architecture synthesis of fetch_stats is

   -- The counters, in the order of their addresses from 0x11
   constant C_CYCLES  : natural := 0;
   constant C_STARVE  : natural := 1;
   constant C_BLOCKED : natural := 2;
   constant C_FULL    : natural := 3;
   constant C_STALL   : natural := 4;
   constant C_PAIRS   : natural := 5;
   constant C_WORDS   : natural := 6;
   constant C_JUMPS   : natural := 7;
   constant C_FLUSHES : natural := 8;
   constant C_COUNTS  : natural := 9;

   type t_counts is array (natural range <>) of std_logic_vector(31 downto 0);

   signal accept : std_logic;

begin

   accept     <= wb_cyc_i and wb_stb_i;
   wb_stall_o <= '0';


   gen_enable : if G_ENABLE generate
      signal run_r   : std_logic := '1';
      signal count_r : t_counts(0 to C_COUNTS - 1);
      signal hist_r  : t_counts(0 to 31);
      signal min_r   : natural range 0 to 31;
      signal max_r   : natural range 0 to 31;
      signal held_r  : natural range 0 to 31;
   begin

      p_count : process (clk_i)

         procedure add(i : natural;
                       n : natural) is
         begin
            count_r(i) <= count_r(i) + n;
         end procedure add;

         procedure add(i : natural;
                       b : std_logic) is
         begin
            if b = '1' then
               count_r(i) <= count_r(i) + 1;
            end if;
         end procedure add;

      begin
         if rising_edge(clk_i) then
            if run_r = '1' and run_i = '1' then
               add(C_CYCLES, 1);
               add(C_STARVE, events_i.starve);
               add(C_BLOCKED, events_i.blocked);
               add(C_FULL, events_i.full);
               add(C_STALL, events_i.stall);
               add(C_PAIRS, events_i.pair);
               add(C_WORDS, events_i.words);
               add(C_JUMPS, events_i.jump);
               add(C_FLUSHES, events_i.flush);
               hist_r(events_i.count) <= hist_r(events_i.count) + 1;
               min_r                  <= minimum(min_r, events_i.count);
               max_r                  <= maximum(max_r, events_i.count);
               held_r                 <= maximum(held_r, events_i.held);
            end if;

            if accept = '1' and wb_we_i = '1' and wb_addr_i = "010000" then
               run_r <= wb_data_i(0);
               if wb_data_i(1) = '1' then
                  count_r <= (others => (others => '0'));
                  hist_r  <= (others => (others => '0'));
                  min_r   <= 31;
                  max_r   <= 0;
                  held_r  <= 0;
               end if;
            end if;

            if rst_i = '1' then
               run_r   <= '1';
               count_r <= (others => (others => '0'));
               hist_r  <= (others => (others => '0'));
               min_r   <= 31;
               max_r   <= 0;
               held_r  <= 0;
            end if;
         end if;
      end process p_count;


      p_bus : process (clk_i)
         variable n_v : natural range 0 to 63;
      begin
         if rising_edge(clk_i) then
            wb_ack_o <= accept;

            if accept = '1' and wb_we_i = '0' then
               n_v       := to_integer(wb_addr_i);
               wb_data_o <= (others => '0');
               if n_v = 16#10# then
                  wb_data_o(0) <= run_r;
               elsif n_v >= 16#11# and n_v < 16#11# + C_COUNTS then
                  wb_data_o <= count_r(n_v - 16#11#);
               elsif n_v = 16#1A# then
                  wb_data_o <= std_logic_vector(to_unsigned(min_r, 32));
               elsif n_v = 16#1B# then
                  wb_data_o <= std_logic_vector(to_unsigned(max_r, 32));
               elsif n_v = 16#1C# then
                  wb_data_o <= std_logic_vector(to_unsigned(held_r, 32));
               elsif n_v >= 16#20# then
                  wb_data_o <= hist_r(n_v - 16#20#);
               end if;
            end if;

            if rst_i = '1' then
               wb_ack_o <= '0';
            end if;
         end if;
      end process p_bus;


      -- The proof of formal/fetch_stats.sby. The invariants tie the
      -- counters to each other: the histogram sums to FS_CYCLES, FS_MIN is
      -- at most FS_MAX once a cycle has counted, and FS_MAX is at most
      -- FS_HELD_MAX, given that no more words are in the buffer than are
      -- held. Each holds after reset and a clear, and each cycle counted
      -- keeps it, so k-induction proves them in one step. The other
      -- assertions say what each cycle does to the counters, and that a
      -- read returns the word as it is in the cycle the read is accepted.

      gen_formal : if G_FORMAL generate
         signal f_sum     : std_logic_vector(31 downto 0);
         signal f_ctrl    : std_logic;                       -- A write to FS_CTRL
         signal f_expect  : std_logic_vector(31 downto 0);   -- What a read returns
         signal f_same    : std_logic;                       -- The counters did not change
         signal f_zero    : std_logic;                       -- The counters are clear
         signal f_last_r  : std_logic_vector(31 downto 0);
         signal f_count_r : t_counts(0 to C_COUNTS - 1);
         signal f_hist_r  : t_counts(0 to 31);
         signal f_min_r   : natural range 0 to 31;
         signal f_max_r   : natural range 0 to 31;
         signal f_held_r  : natural range 0 to 31;
         signal f_bin_r   : natural range 0 to 31;
         -- A binary tree over the histogram: node n has the children 2n
         -- and 2n + 1, and nodes 16 to 31 have the bins as children. Each
         -- node counts the cycles counted with the count in its subtree.
         signal f_tree_r : t_counts(1 to 31);
      begin

         -- The sum of the bins, added in the order of the tree below
         p_sum : process (all)
            variable sum_v : t_counts(1 to 63);
         begin
            sum_v(32 to 63) := hist_r;
            for n in 31 downto 1 loop
               sum_v(n) := sum_v(2 * n) + sum_v(2 * n + 1);
            end loop;
            f_sum <= sum_v(1);
         end process p_sum;

         f_ctrl <= '1' when accept = '1' and wb_we_i = '1' and wb_addr_i = "010000" else
                   '0';
         f_same <= '1' when count_r = f_count_r and hist_r = f_hist_r and min_r = f_min_r and
                            max_r = f_max_r and held_r = f_held_r else
                   '0';
         f_zero <= '1' when count_r = (count_r'range => X"00000000") and
                             hist_r = (hist_r'range => X"00000000") and
                             min_r = 31 and max_r = 0 and held_r = 0 else
                    '0';


         p_expect : process (all)
            variable n_v : natural range 0 to 63;
         begin
            n_v := to_integer(wb_addr_i);
            case n_v is
               when 16#10#           => f_expect <= (0 => run_r, others => '0');
               when 16#11# to 16#19# => f_expect <= count_r(n_v - 16#11#);
               when 16#1A#           => f_expect <= std_logic_vector(to_unsigned(min_r, 32));
               when 16#1B#           => f_expect <= std_logic_vector(to_unsigned(max_r, 32));
               when 16#1C#           => f_expect <= std_logic_vector(to_unsigned(held_r, 32));
               when 16#20# to 16#3F# => f_expect <= hist_r(n_v - 16#20#);
               when others           => f_expect <= (others => '0');
            end case;
         end process p_expect;


         p_prev : process (clk_i)
         begin
            if rising_edge(clk_i) then
               f_last_r  <= f_expect;
               f_count_r <= count_r;
               f_hist_r  <= hist_r;
               f_min_r   <= min_r;
               f_max_r   <= max_r;
               f_held_r  <= held_r;
               f_bin_r   <= events_i.count;

               if run_r = '1' and run_i = '1' then
                  for n in 1 to 31 loop
                     for d in 1 to 5 loop
                        if (32 + events_i.count) / 2 ** d = n then
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

         -- The invariants
         -- psl f_hist_sum : assert always rst_i = '0' -> f_sum = count_r(C_CYCLES);
         -- psl f_root : assert always rst_i = '0' -> f_tree_r(1) = count_r(C_CYCLES);

         gen_tree : for n in 1 to 15 generate
            -- psl f_node : assert always rst_i = '0' ->
            --    f_tree_r(n) = f_tree_r(2 * n) + f_tree_r(2 * n + 1);
         end generate gen_tree;

         gen_leaves : for n in 16 to 31 generate
            -- psl f_leaf : assert always rst_i = '0' ->
            --    f_tree_r(n) = hist_r(2 * n - 32) + hist_r(2 * n - 31);
         end generate gen_leaves;

         -- psl f_min_max : assert always
         --    rst_i = '0' -> (count_r(C_CYCLES) /= 0 -> min_r <= max_r);
         -- psl f_max_held : assert always rst_i = '0' -> max_r <= held_r;

         -- A cycle counted adds one to FS_CYCLES and to the histogram's
         -- bin of its count. Stopped counters keep their values, whether
         -- the run bit or run_i stops them, and a write of 1 to FS_CTRL
         -- starts them without a clear.
         -- psl f_cycle : assert always
         --    {run_r and run_i and not (f_ctrl and wb_data_i(1)) and not rst_i} |=>
         --    {count_r(C_CYCLES) = f_count_r(C_CYCLES) + 1 and
         --     hist_r(f_bin_r) = f_hist_r(f_bin_r) + 1};
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
