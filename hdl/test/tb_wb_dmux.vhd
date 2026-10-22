-- A self-checking test of src/wb_dmux.vhd, the data bus decoder.
--
-- THEORY OF OPERATION
-- A random master sends C_REQUESTS requests to three slaves, with the
-- slave chosen at random, and the same as the last one half of the time.
-- It holds a stalled request, as Wishbone requires. Its address is the
-- number of the request, and it goes to the slaves past the decoder, as in
-- a system. Each slave answers its requests in order, with the data
-- X"0s" & address, where s is the slave's index. The slaves differ:
-- - Slave 0 stalls in 30% of the cycles and acknowledges a request in the
--   next cycle, as the memory does.
-- - Slave 1 stalls in 20% of the cycles and acknowledges a request in each
--   cycle with a chance of 15%, so its ACKs come slowly.
-- - Slave 2 stalls while it owes an ACK, and acknowledges a request in each
--   cycle with a chance of 5%, as the math unit does with a read.
-- The checks, in every cycle:
-- * Each ACK reaches the master in the order of its requests, with the
--   data of the slave and the request that it answers.
-- * The master gets no ACK it is not owed, and is owed no more than
--   G_MAX_PENDING.
-- * A slave's STB is high only with the master's, and only when the
--   select names the slave. No slave gets STB while another owes an ACK.
-- * A request that may pass is not stalled: with no ACK owed by another
--   slave and the slave not stalling, the master's request is accepted in
--   the same cycle.
-- At the end, every request must have its ACK, and enough requests must
-- have waited for another slave's ACKs, for the test to mean something.
-- The run stops with status 0 when every check passes, and 1 at the first
-- that fails.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;
   use ieee.math_real.all;

   use std.env.all;

entity tb_wb_dmux is
end entity tb_wb_dmux;

architecture simulation of tb_wb_dmux is

   constant C_SLAVES      : positive := 3;
   constant C_MAX_PENDING : positive := 4;
   constant C_REQUESTS    : positive := 5000;
   constant C_TIMEOUT     : positive := 100_000;

   type t_percents is array (0 to C_SLAVES - 1) of natural;

   type t_bools is array (0 to C_SLAVES - 1) of boolean;

   type t_counts is array (0 to C_SLAVES - 1) of natural;

   -- The slaves' behavior: the stall rate and the chance of an ACK in each
   -- cycle, in percent, and whether the slave stalls while it owes an ACK.
   constant C_STALL : t_percents := (30, 20, 0);
   constant C_ACK   : t_percents := (100, 15, 5);
   constant C_HOLD  : t_bools    := (false, false, true);

   signal clk : std_logic;
   signal rst : std_logic := '1';

   signal sel     : natural range 0 to C_SLAVES - 1 := 0;
   signal m_cyc   : std_logic                       := '0';
   signal m_stb   : std_logic                       := '0';
   signal m_stall : std_logic;
   signal m_ack   : std_logic;
   signal m_data  : std_logic_vector(31 downto 0);
   signal addr    : std_logic_vector(23 downto 0)   := (others => '0');

   signal s_stb   : std_logic_vector(C_SLAVES - 1 downto 0);
   signal s_stall : std_logic_vector(C_SLAVES - 1 downto 0);
   signal s_ack   : std_logic_vector(C_SLAVES - 1 downto 0);
   signal s_data  : std_logic_vector(32 * C_SLAVES - 1 downto 0);
   -- The ACKs that each slave owes
   signal owed : t_counts;

begin

   p_clk : process
   begin
      clk <= '1', '0' after 5 ns;
      wait for 10 ns;
   end process p_clk;


   i_wb_dmux : entity work.wb_dmux
      generic map (
         G_SLAVES      => C_SLAVES,
         G_MAX_PENDING => C_MAX_PENDING
      )
      port map (
         clk_i     => clk,
         rst_i     => rst,
         sel_i     => sel,
         m_cyc_i   => m_cyc,
         m_stb_i   => m_stb,
         m_stall_o => m_stall,
         m_ack_o   => m_ack,
         m_data_o  => m_data,
         s_stb_o   => s_stb,
         s_stall_i => s_stall,
         s_ack_i   => s_ack,
         s_data_i  => s_data
      ); -- i_wb_dmux


   gen_slave : for s in 0 to C_SLAVES - 1 generate

      -- A pipelined Wishbone slave that answers in order, at random.
      p_slave : process (clk)
         type t_fifo is array (0 to 63) of std_logic_vector(23 downto 0);

         variable fifo_v  : t_fifo;
         variable count_v : natural := 0;
         variable ack_v   : natural;
         variable seed1_v : positive := 11 + s;
         variable seed2_v : positive := 23 + 7 * s;
         variable r_v     : real;
      begin
         if rising_edge(clk) then
            -- The ACK of the cycle that ends was popped when it was raised.
            -- An ACK answers a request of an earlier cycle, so the request
            -- accepted in the cycle that ends goes in after it.
            s_ack(s) <= '0';
            ack_v    := 0;
            uniform(seed1_v, seed2_v, r_v);
            if count_v /= 0 and r_v * 100.0 < real(C_ACK(s)) then
               s_ack(s)                          <= '1';
               ack_v                             := 1;
               s_data(32 * s + 31 downto 32 * s) <= to_slv(s, 8) & fifo_v(0);
               fifo_v(0 to fifo_v'high - 1)      := fifo_v(1 to fifo_v'high);
               count_v                           := count_v - 1;
            end if;
            if m_cyc = '1' and s_stb(s) = '1' and s_stall(s) = '0' then
               fifo_v(count_v) := addr;
               count_v         := count_v + 1;
            end if;
            owed(s) <= count_v + ack_v;

            uniform(seed1_v, seed2_v, r_v);
            if (C_HOLD(s) and count_v /= 0) or r_v * 100.0 < real(C_STALL(s)) then
               s_stall(s) <= '1';
            else
               s_stall(s) <= '0';
            end if;

            if rst = '1' then
               s_ack(s)   <= '0';
               s_stall(s) <= '0';
               owed(s)    <= 0;
               count_v    := 0;
            end if;
         end if;
      end process p_slave;

   end generate gen_slave;


   p_master : process
      type t_queue is array (0 to C_MAX_PENDING) of std_logic_vector(31 downto 0);

      variable queue_v  : t_queue;
      variable count_v  : natural  := 0;
      variable issued_v : natural  := 0;
      variable acks_v   : natural  := 0;
      variable waits_v  : natural  := 0;
      variable cycles_v : natural  := 0;
      variable others_v : natural;
      variable seed1_v  : positive := 5;
      variable seed2_v  : positive := 9;
      variable r_v      : real;

      procedure fail(msg : string) is
      begin
         report "tb_wb_dmux: " & msg
            severity error;
         stop(1);
      end procedure fail;

   begin
      wait for 100 ns;
      wait until rising_edge(clk);
      rst   <= '0';
      m_cyc <= '1';

      while issued_v < C_REQUESTS or count_v /= 0 loop
         wait until rising_edge(clk);
         cycles_v := cycles_v + 1;
         if cycles_v > C_TIMEOUT then
            fail("no progress after " & integer'image(C_TIMEOUT) & " cycles");
         end if;

         -- The values of the cycle that ends with this edge
         if m_ack = '1' then
            if count_v = 0 then
               fail("an ACK with no request owed one");
            end if;
            if m_data /= queue_v(0) then
               fail("ACK " & integer'image(acks_v) & " brought " & to_hstring(m_data) &
                    ", not " & to_hstring(queue_v(0)));
            end if;
            queue_v(0 to C_MAX_PENDING - 1) := queue_v(1 to C_MAX_PENDING);
            count_v                         := count_v - 1;
            acks_v                          := acks_v + 1;
         end if;

         for s in 0 to C_SLAVES - 1 loop
            if s_stb(s) = '1' and (m_stb = '0' or sel /= s) then
               fail("STB of slave " & integer'image(s) & " without a request to it");
            end if;
            others_v := 0;
            for t in 0 to C_SLAVES - 1 loop
               if t /= s then
                  others_v := others_v + owed(t);
               end if;
            end loop;
            if s_stb(s) = '1' and others_v /= 0 then
               fail("STB of slave " & integer'image(s) & " while another owes an ACK");
            end if;
            if m_stb = '1' and sel = s and m_stall = '1' and s_stall(s) = '0' then
               if others_v = 0 and owed(s) < C_MAX_PENDING then
                  fail("a request that may pass is stalled");
               end if;
               if others_v /= 0 then
                  waits_v := waits_v + 1;
               end if;
            end if;
         end loop;

         if m_stb = '1' and m_stall = '0' then
            if count_v = C_MAX_PENDING then
               fail("more than G_MAX_PENDING requests accepted");
            end if;
            queue_v(count_v) := to_slv(sel, 8) & addr;
            count_v          := count_v + 1;
            issued_v         := issued_v + 1;
         end if;

         -- The next request, unless a stalled one waits
         if m_stb = '0' or m_stall = '0' then
            uniform(seed1_v, seed2_v, r_v);
            if issued_v < C_REQUESTS and r_v < 0.7 then
               m_stb <= '1';
               addr  <= to_slv(issued_v, 24);
               uniform(seed1_v, seed2_v, r_v);
               if r_v >= 0.5 then
                  uniform(seed1_v, seed2_v, r_v);
                  sel <= integer(trunc(r_v * real(C_SLAVES)));
               end if;
            else
               m_stb <= '0';
            end if;
         end if;
      end loop;

      if waits_v < C_REQUESTS / 10 then
         fail("only " & integer'image(waits_v) & " cycles waited for another slave");
      end if;
      report "tb_wb_dmux: " & integer'image(acks_v) & " requests in " &
             integer'image(cycles_v) & " cycles, " & integer'image(waits_v) &
             " cycles waited for another slave";
      stop(0);
   end process p_master;

end architecture simulation;
