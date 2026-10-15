-- A self-checking test of src/mpu.vhd.
--
-- THEORY OF OPERATION
-- For each pair A, B it writes A and B, then reads all 16 words and checks
-- them against results that numeric_std computes, with the special cases
-- of ISA.md §8.4. The pairs are the corner cases first, then G_RANDOM
-- random ones. Further checks:
-- * A read of a result right after a write waits for the computation, and
--   a read of A, B, or a spare word does not.
-- * A write to A while a computation runs restarts it.
-- * A write and a read issued in back-to-back cycles, as a pipelined master
--   may, still see each other in order.
-- * Writes to the result words and the spare words are ignored.
-- * Reset sets A and B to 0.
-- The run stops with status 0 when every check passes, and 1 at the first
-- that fails.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;
   use ieee.math_real.all;

   use std.env.all;

entity tb_mpu is
   generic (
      G_RANDOM : natural  := 2000;
      G_SEED   : positive := 1
   );
end entity tb_mpu;

architecture simulation of tb_mpu is

   -- The computation takes 33 cycles (src/mpu.vhd).
   constant C_MIN_WAIT : natural := 30;

   signal clk : std_logic;
   signal rst : std_logic := '1';

   signal cyc      : std_logic                     := '0';
   signal stb      : std_logic                     := '0';
   signal stall    : std_logic;
   signal ack      : std_logic;
   signal we       : std_logic                     := '0';
   signal addr     : std_logic_vector(3 downto 0)  := (others => '0');
   signal data_out : std_logic_vector(31 downto 0) := (others => '0');
   signal data_in  : std_logic_vector(31 downto 0);

   type t_words is array (0 to 15) of std_logic_vector(31 downto 0);

   -- The 16 words of ISA.md §8.4 for A and B.
   function expected(a : std_logic_vector(31 downto 0);
                     b : std_logic_vector(31 downto 0)) return t_words is
      variable res_v : t_words := (others => (others => '0'));
      variable sp_v  : signed(63 downto 0);
      variable up_v  : unsigned(63 downto 0);
   begin
      sp_v     := signed(a) * signed(b);
      up_v     := unsigned(a) * unsigned(b);
      res_v(0) := a;
      res_v(1) := b;
      res_v(2) := std_logic_vector(sp_v(31 downto 0));
      res_v(3) := std_logic_vector(sp_v(63 downto 32));
      res_v(4) := std_logic_vector(up_v(31 downto 0));
      res_v(5) := std_logic_vector(up_v(63 downto 32));
      if b = X"00000000" then
         res_v(6) := X"FFFFFFFF";
         res_v(7) := a;
         res_v(8) := X"FFFFFFFF";
         res_v(9) := a;
      else
         if a = X"80000000" and b = X"FFFFFFFF" then
            res_v(6) := X"80000000";
            res_v(7) := X"00000000";
         else
            -- numeric_std's "/" rounds toward zero, and "rem" has the sign
            -- of the dividend.
            res_v(6) := std_logic_vector(signed(a) / signed(b));
            res_v(7) := std_logic_vector(signed(a) rem signed(b));
         end if;
         res_v(8) := std_logic_vector(unsigned(a) / unsigned(b));
         res_v(9) := std_logic_vector(unsigned(a) rem unsigned(b));
      end if;
      return res_v;
   end function expected;

   type t_pair is record
      a : std_logic_vector(31 downto 0);
      b : std_logic_vector(31 downto 0);
   end record t_pair;

   type t_pairs is array (natural range <>) of t_pair;

   constant C_CORNERS : t_pairs := (
      (X"00000007", X"00000003"),
      (X"FFFFFFF9", X"00000002"),
      (X"00000007", X"FFFFFFFE"),
      (X"FFFFFFF9", X"FFFFFFFE"),
      (X"FFFFFFFF", X"FFFFFFFF"),
      (X"80000000", X"FFFFFFFF"),
      (X"80000000", X"80000000"),
      (X"80000000", X"00000001"),
      (X"7FFFFFFF", X"7FFFFFFF"),
      (X"7FFFFFFF", X"80000000"),
      (X"00000000", X"00000000"),
      (X"00000005", X"00000000"),
      (X"FFFFFFFB", X"00000000"),
      (X"80000000", X"00000000"),
      (X"00000000", X"FFFFFFFF"),
      (X"00000003", X"00000007"),
      (X"FFFFFFFF", X"00000001"),
      (X"FFFFFFFF", X"80000000"),
      (X"12345678", X"9ABCDEF0"),
      (X"9ABCDEF0", X"00012345")
   );

begin

   p_clk : process
   begin
      clk <= '1', '0' after 5 ns;
      wait for 10 ns;
   end process p_clk;


   i_mpu : entity work.mpu
      port map (
         clk_i      => clk,
         rst_i      => rst,
         wb_cyc_i   => cyc,
         wb_stb_i   => stb,
         wb_stall_o => stall,
         wb_ack_o   => ack,
         wb_we_i    => we,
         wb_addr_i  => addr,
         wb_data_i  => data_out,
         wb_data_o  => data_in
      ); -- i_mpu


   p_test : process
      variable seed1_v : positive := G_SEED;
      variable seed2_v : positive := 1;
      variable a_v     : std_logic_vector(31 downto 0);
      variable b_v     : std_logic_vector(31 downto 0);
      variable data_v  : std_logic_vector(31 downto 0);
      variable cycles_v : natural;

      procedure fail(msg : string) is
      begin
         report "tb_mpu: " & msg severity error;
         stop(1);
      end procedure fail;

      -- Starts a request in the cycle after the call, and holds it while
      -- STALL is high. Right after a clock edge, the signals still hold the
      -- values the MPU saw at that edge.
      procedure request(w : std_logic; a : natural; d : std_logic_vector(31 downto 0)) is
      begin
         cyc      <= '1';
         stb      <= '1';
         we       <= w;
         addr     <= std_logic_vector(to_unsigned(a, 4));
         data_out <= d;
         wait until rising_edge(clk);
         while stall = '1' loop
            wait until rising_edge(clk);
         end loop;
         stb <= '0';
      end procedure request;

      -- Waits for the ACK of a request, and counts the cycles.
      procedure wait_ack(data : out std_logic_vector(31 downto 0); cycles : out natural) is
         variable n_v : natural := 0;
      begin
         while ack /= '1' loop
            wait until rising_edge(clk);
            n_v := n_v + 1;
            if n_v > 100 then
               fail("no ACK");
            end if;
         end loop;
         data   := data_in;
         cycles := n_v;
      end procedure wait_ack;

      procedure write_word(a : natural; d : std_logic_vector(31 downto 0)) is
         variable word_v : std_logic_vector(31 downto 0);
         variable n_v    : natural;
      begin
         request('1', a, d);
         wait_ack(word_v, n_v);
         cyc <= '0';
      end procedure write_word;

      procedure read_word(a : natural; d : out std_logic_vector(31 downto 0); cycles : out natural) is
      begin
         request('0', a, X"00000000");
         wait_ack(d, cycles);
         cyc <= '0';
      end procedure read_word;

      procedure check_all(a, b : std_logic_vector(31 downto 0)) is
         constant C_WANT : t_words := expected(a, b);
         variable word_v : std_logic_vector(31 downto 0);
         variable n_v    : natural;
      begin
         for i in 0 to 15 loop
            read_word(i, word_v, n_v);
            if word_v /= C_WANT(i) then
               fail("A = " & to_hstring(a) & ", B = " & to_hstring(b) & ": word " &
                    integer'image(i) & " = " & to_hstring(word_v) & ", expected " &
                    to_hstring(C_WANT(i)));
            end if;
         end loop;
      end procedure check_all;

      impure function random_word return std_logic_vector is
         variable r_v : real;
         variable w_v : std_logic_vector(31 downto 0);
      begin
         for i in 0 to 3 loop
            uniform(seed1_v, seed2_v, r_v);
            w_v(8 * i + 7 downto 8 * i) := std_logic_vector(to_unsigned(natural(floor(r_v * 256.0)) mod 256, 8));
         end loop;
         -- Small magnitudes in a quarter of the cases, so that the
         -- quotients are not mostly 0 and 1.
         uniform(seed1_v, seed2_v, r_v);
         if r_v < 0.25 then
            w_v(31 downto 8) := (others => w_v(7));
         end if;
         return w_v;
      end function random_word;

   begin
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      rst <= '0';
      wait until rising_edge(clk);

      -- Reset sets A and B to 0.
      check_all(X"00000000", X"00000000");

      -- The corner cases, then random pairs.
      for i in C_CORNERS'range loop
         write_word(0, C_CORNERS(i).a);
         write_word(1, C_CORNERS(i).b);
         check_all(C_CORNERS(i).a, C_CORNERS(i).b);
      end loop;

      for i in 1 to G_RANDOM loop
         a_v := random_word;
         b_v := random_word;
         write_word(0, a_v);
         write_word(1, b_v);
         check_all(a_v, b_v);
      end loop;

      -- A read of a result waits; a read of A, B, or a spare word does not.
      write_word(0, X"00000006");
      read_word(1, data_v, cycles_v);
      if cycles_v /= 1 then
         fail("a read of B waited " & integer'image(cycles_v) & " cycles");
      end if;
      read_word(12, data_v, cycles_v);
      if cycles_v /= 1 or data_v /= X"00000000" then
         fail("a read of a spare word waited or was not 0");
      end if;
      write_word(1, X"00000007");
      read_word(4, data_v, cycles_v);
      if cycles_v < C_MIN_WAIT or data_v /= X"0000002A" then
         fail("UMUL_LO = " & to_hstring(data_v) & " after " & integer'image(cycles_v) & " cycles");
      end if;

      -- A write to A while a computation runs restarts it.
      write_word(0, X"00000064");
      for i in 1 to 10 loop
         wait until rising_edge(clk);
      end loop;
      write_word(0, X"00000009");
      read_word(8, data_v, cycles_v);
      if data_v /= X"00000001" then
         fail("UDIV_Q after a restart = " & to_hstring(data_v));
      end if;

      -- Writes to results and spare words are ignored.
      for i in 2 to 15 loop
         write_word(i, X"DEADBEEF");
      end loop;
      check_all(X"00000009", X"00000007");

      -- A write of B, then a read of SMUL_LO in the next cycle, without
      -- waiting for the ACK of the write.
      cyc      <= '1';
      stb      <= '1';
      we       <= '1';
      addr     <= X"1";
      data_out <= X"FFFFFFFD";
      wait until rising_edge(clk);
      we   <= '0';
      addr <= X"2";
      wait until rising_edge(clk);
      if ack /= '1' or stall /= '0' then
         fail("no ACK of the pipelined write, or the read was not accepted");
      end if;
      stb <= '0';
      wait until rising_edge(clk);
      wait_ack(data_v, cycles_v);
      cyc <= '0';
      if data_v /= X"FFFFFFE5" then -- 9 * -3 = -27
         fail("SMUL_LO after a pipelined write = " & to_hstring(data_v));
      end if;

      -- Reset sets A and B to 0 again.
      rst <= '1';
      wait until rising_edge(clk);
      rst <= '0';
      check_all(X"00000000", X"00000000");

      report "tb_mpu: all checks passed";
      stop(0);
   end process p_test;

end architecture simulation;
