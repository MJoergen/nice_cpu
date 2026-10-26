-- A self-checking test of the microsecond counter of src/perf.vhd at the
-- clock frequencies that 1000000 does not divide, or does by 10 only.
--
-- THEORY OF OPERATION
-- Three instances of perf run side by side, at 33333333, 83333333, and
-- 100000000 Hz, with G_RESET = 0. A read of the microsecond counter in a
-- cycle, and a read of the cycle counter in the next, give the cycles N
-- counted when the first read was accepted: the second value less 1. The
-- microsecond counter must read the integer part of N * 1000000 / G_CLK_HZ,
-- at 400 reads with gaps of 0 to 6 cycles, in each instance. The run stops
-- with status 0 when every check passes, and 1 at the first that fails.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;
   use ieee.math_real.all;

   use std.env.all;

entity tb_perf_hz is
end entity tb_perf_hz;

architecture simulation of tb_perf_hz is

   constant C_CYCLE_LO : natural := 0;
   constant C_TIME_LO  : natural := 4;

   type t_hz is array (0 to 2) of natural;
   type t_word is array (0 to 2) of std_logic_vector(31 downto 0);

   constant C_HZ : t_hz := (33333333, 83333333, 100000000);

   signal clk : std_logic;
   signal rst : std_logic := '1';

   signal cyc      : std_logic                    := '0';
   signal stb      : std_logic                    := '0';
   signal addr     : std_logic_vector(3 downto 0) := (others => '0');
   signal data_out : t_word;

begin

   p_clk : process
   begin
      clk <= '1', '0' after 5 ns;
      wait for 10 ns;
   end process p_clk;


   gen_perf : for i in 0 to 2 generate

      i_perf : entity work.perf
         generic map (
            G_CLK_HZ => C_HZ(i)
         )
         port map (
            clk_i      => clk,
            rst_i      => rst,
            instret_i  => '0',
            wb_cyc_i   => cyc,
            wb_stb_i   => stb,
            wb_stall_o => open,
            wb_ack_o   => open,
            wb_we_i    => '0',
            wb_addr_i  => addr,
            wb_data_i  => (others => '0'),
            wb_data_o  => data_out(i)
         ); -- i_perf

   end generate gen_perf;


   p_test : process
      variable time_v  : t_word;
      variable cycle_v : t_word;
      variable n_v     : natural;
      variable want_v  : natural;

      procedure fail(msg : string) is
      begin
         report "tb_perf_hz: " & msg
            severity error;
         stop(1);
      end procedure fail;

      -- A read of a low word, accepted at the next clock edge. Right after
      -- that edge, the data outputs hold the words read.
      procedure read_word(a : natural; q : out t_word) is
      begin
         cyc  <= '1';
         stb  <= '1';
         addr <= to_slv(a, 4);
         wait until rising_edge(clk);
         stb <= '0';
         cyc <= '0';
         wait for 1 ns;
         q := data_out;
      end procedure read_word;

   begin
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      rst <= '0';

      for k in 1 to 400 loop
         read_word(C_TIME_LO, time_v);
         read_word(C_CYCLE_LO, cycle_v);
         n_v := to_integer(cycle_v(0)) - 1;
         for i in 0 to 2 loop
            want_v := integer(floor(real(n_v) * 1.0e6 / real(C_HZ(i))));
            if to_integer(time_v(i)) /= want_v then
               fail(integer'image(C_HZ(i)) & " Hz, " & integer'image(n_v) & " cycles: " &
                    integer'image(to_integer(time_v(i))) & " us, expected " &
                    integer'image(want_v));
            end if;
         end loop;
         for g in 1 to k mod 7 loop
            wait until rising_edge(clk);
         end loop;
      end loop;

      report "tb_perf_hz: all checks passed";
      stop(0);
   end process p_test;

end architecture simulation;
