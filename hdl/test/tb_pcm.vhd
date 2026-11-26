-- A self-checking test of src/pcm.vhd, the sample player.
--
-- THEORY OF OPERATION
-- The player runs at G_CLK_HZ = 1 MHz, so that a cycle is a microsecond,
-- and at the rate 40000 a sample is due once in exactly 25 cycles. A
-- monitor logs each sample of the strobe, and the cycle it comes in. The
-- checks:
-- * After reset, the status reads 0x10000000, the rate 0, and PCM_DATA
--   and the offsets that are not the player's 0.
-- * Writes of PCM_DATA count in the status. Writes of the rate set 1000
--   to 48000, or 0, and with the rate 0 no sample is played.
-- * At 40000, the samples come out in the order of their writes, 25
--   cycles apart, and then the 0s of an underrun, which sets the flag. A
--   write of the status clears it.
-- * With the rate 0, 4096 writes fill the FIFO, and a write to the full
--   FIFO is acknowledged at once and dropped.
-- * At 40000, a write to the full FIFO waits for a sample, at most 25
--   cycles and a few, and then goes in behind the others, which all play.
-- * Every request but the held write is acknowledged in the cycle after
--   it is accepted.
-- * Reset empties the FIFO, sets the rate to 0, clears the flag, and stops
--   the samples.
-- The run stops with status 0 when every check passes, and 1 at the first
-- that fails.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use std.env.all;

entity tb_pcm is
end entity tb_pcm;

architecture simulation of tb_pcm is

   constant C_DATA   : natural := 2;
   constant C_RATE   : natural := 3;
   constant C_STATUS : natural := 4;
   constant C_PERIOD : natural := 25;
   constant C_LOG    : natural := 8192;

   type t_log is array (1 to C_LOG) of std_logic_vector(31 downto 0);
   type t_cycles is array (1 to C_LOG) of natural;

   signal clk : std_logic;
   signal rst : std_logic := '1';

   signal cyc      : std_logic                     := '0';
   signal stb      : std_logic                     := '0';
   signal stall    : std_logic;
   signal ack      : std_logic;
   signal we       : std_logic                     := '0';
   signal addr     : std_logic_vector(2 downto 0)  := (others => '0');
   signal data_out : std_logic_vector(31 downto 0) := (others => '0');
   signal data_in  : std_logic_vector(31 downto 0);

   signal valid : std_logic;
   signal left  : std_logic_vector(15 downto 0);
   signal right : std_logic_vector(15 downto 0);

   signal cycle   : natural := 0;
   signal played  : natural := 0;
   signal log     : t_log;
   signal log_cyc : t_cycles;

begin

   p_clk : process
   begin
      clk <= '1', '0' after 5 ns;
      wait for 10 ns;
   end process p_clk;


   i_pcm : entity work.pcm
      generic map (
         G_CLK_HZ => 1000000
      )
      port map (
         clk_i          => clk,
         rst_i          => rst,
         wb_cyc_i       => cyc,
         wb_stb_i       => stb,
         wb_stall_o     => stall,
         wb_ack_o       => ack,
         wb_we_i        => we,
         wb_addr_i      => addr,
         wb_data_i      => data_out,
         wb_data_o      => data_in,
         sample_valid_o => valid,
         sample_left_o  => left,
         sample_right_o => right
      ); -- i_pcm


   -- The samples of the strobe, and their cycles.
   p_monitor : process (clk)
   begin
      if rising_edge(clk) then
         cycle <= cycle + 1;
         if valid = '1' and played < C_LOG then
            log(played + 1)     <= left & right;
            log_cyc(played + 1) <= cycle;
            played              <= played + 1;
         end if;
      end if;
   end process p_monitor;


   p_test : process
      variable q_v      : std_logic_vector(31 downto 0);
      variable waited_v : natural;
      variable first_v  : natural;

      procedure fail(msg : string) is
      begin
         report "tb_pcm: " & msg
            severity error;
         stop(1);
      end procedure fail;

      -- A request, accepted at the next clock edge, where STALL must be
      -- low. Its ACK comes in the cycle after, or, for a write held by a
      -- full FIFO, `waited` cycles later. Then the data holds the word.
      procedure access_word(w : std_logic; a : natural; d : std_logic_vector(31 downto 0);
                            q : out std_logic_vector(31 downto 0); waited : out natural) is
         variable n_v : natural := 0;
      begin
         cyc      <= '1';
         stb      <= '1';
         we       <= w;
         addr     <= to_slv(a, 3);
         data_out <= d;
         wait until rising_edge(clk);
         if stall /= '0' then
            fail("STALL is high before a request");
         end if;
         stb <= '0';
         wait for 1 ns;
         while ack /= '1' loop
            n_v := n_v + 1;
            if n_v > 100 then
               fail("no ACK within 100 cycles");
            end if;
            wait until rising_edge(clk);
            wait for 1 ns;
         end loop;
         cyc    <= '0';
         q      := data_in;
         waited := n_v;
      end procedure access_word;

      procedure write_word(a : natural; d : std_logic_vector(31 downto 0)) is
         variable got_v : std_logic_vector(31 downto 0);
         variable n_v   : natural;
      begin
         access_word('1', a, d, got_v, n_v);
         if n_v /= 0 then
            fail("a write of word " & integer'image(a) & " waits " &
                 integer'image(n_v) & " cycles");
         end if;
      end procedure write_word;

      procedure check(a : natural; want : std_logic_vector(31 downto 0); what : string) is
         variable got_v : std_logic_vector(31 downto 0);
         variable n_v   : natural;
      begin
         access_word('0', a, X"00000000", got_v, n_v);
         if n_v /= 0 then
            fail("a read waits");
         end if;
         if got_v /= want then
            fail(what & ": word " & integer'image(a) & " = " & to_hstring(got_v) &
                 ", expected " & to_hstring(want));
         end if;
      end procedure check;

      procedure clocks(n : natural) is
      begin
         for i in 1 to n loop
            wait until rising_edge(clk);
         end loop;
         wait for 1 ns;
      end procedure clocks;

      procedure wait_played(n : natural) is
      begin
         for i in 1 to 30 * C_PERIOD * C_LOG loop
            exit when played >= n;
            clocks(1);
         end loop;
         if played < n then
            fail(integer'image(played) & " samples played, not " & integer'image(n));
         end if;
      end procedure wait_played;

      -- Sample n, and, if `gap`, its distance from the one before.
      procedure check_sample(n : natural; want : std_logic_vector(31 downto 0);
                             gap : boolean := true) is
      begin
         if log(n) /= want then
            fail("sample " & integer'image(n) & " = " & to_hstring(log(n)) &
                 ", expected " & to_hstring(want));
         end if;
         if gap and log_cyc(n) - log_cyc(n - 1) /= C_PERIOD then
            fail("sample " & integer'image(n) & " comes " &
                 integer'image(log_cyc(n) - log_cyc(n - 1)) & " cycles after the one before");
         end if;
      end procedure check_sample;

   begin
      clocks(2);
      rst <= '0';

      check(C_STATUS, X"10000000", "after reset");
      check(C_RATE, X"00000000", "after reset");
      check(C_DATA, X"00000000", "after reset");
      for a in 0 to 7 loop
         if a < C_DATA or a > C_STATUS then
            check(a, X"00000000", "a word not the player's");
         end if;
      end loop;

      write_word(C_DATA, X"00010002");
      write_word(C_DATA, X"FFFF8000");
      check(C_STATUS, X"10000002", "two samples");
      check(C_STATUS, X"10000002", "a read has no side effect");

      write_word(C_RATE, X"00000001");
      check(C_RATE, to_slv(1000, 32), "the rate of 1");
      write_word(C_RATE, to_slv(999, 32));
      check(C_RATE, to_slv(1000, 32), "the rate of 999");
      write_word(C_RATE, to_slv(48001, 32));
      check(C_RATE, to_slv(48000, 32), "the rate of 48001");
      write_word(C_RATE, X"FFFFFFFF");
      check(C_RATE, to_slv(48000, 32), "the rate of 0xFFFFFFFF");
      write_word(C_RATE, to_slv(44100, 32));
      check(C_RATE, to_slv(44100, 32), "the rate of 44100");
      write_word(C_RATE, X"00000000");
      check(C_RATE, X"00000000", "the rate of 0");
      clocks(1000);
      if played /= 0 then
         fail("a sample is played with the rate 0, or before");
      end if;
      check(C_STATUS, X"10000002", "the rate 0 plays nothing");

      -- Two samples, then the 0s of the underrun.
      write_word(C_RATE, to_slv(40000, 32));
      wait_played(4);
      check_sample(1, X"00010002", false);
      check_sample(2, X"FFFF8000");
      check_sample(3, X"00000000");
      check_sample(4, X"00000000");
      write_word(C_RATE, X"00000000");
      check(C_STATUS, X"10008000", "the underrun");
      write_word(C_STATUS, X"00000000");
      check(C_STATUS, X"10000000", "the underrun cleared");
      first_v := played;
      clocks(100);
      if played /= first_v then
         fail("a sample is played after the rate is set to 0");
      end if;

      -- Stopped, a write to the full FIFO is dropped at once.
      for i in 1 to 4096 loop
         write_word(C_DATA, to_slv(i, 32));
      end loop;
      check(C_STATUS, X"10001000", "full");
      write_word(C_DATA, X"0000DEAD");
      check(C_STATUS, X"10001000", "full, with a write dropped");

      -- Playing, a write to the full FIFO waits for a sample.
      write_word(C_RATE, to_slv(40000, 32));
      access_word('1', C_DATA, X"0000BEEF", q_v, waited_v);
      if waited_v = 0 or waited_v > C_PERIOD + 3 then
         fail("the write to the full FIFO waits " & integer'image(waited_v) & " cycles");
      end if;
      check(C_STATUS, X"10001000", "full again");
      wait_played(first_v + 4096 + 2);
      check_sample(first_v + 1, to_slv(1, 32), false);
      for i in 2 to 4096 loop
         check_sample(first_v + i, to_slv(i, 32));
      end loop;
      check_sample(first_v + 4097, X"0000BEEF");
      check_sample(first_v + 4098, X"00000000");
      check(C_STATUS, X"10008000", "the underrun after the FIFO");

      -- Reset with samples in the FIFO.
      write_word(C_RATE, X"00000000");
      write_word(C_DATA, X"11112222");
      write_word(C_DATA, X"33334444");
      write_word(C_RATE, to_slv(1000, 32));
      rst <= '1';
      clocks(1);
      rst <= '0';
      check(C_STATUS, X"10000000", "after a second reset");
      check(C_RATE, X"00000000", "after a second reset");
      first_v := played;
      clocks(3000);
      if played /= first_v then
         fail("a sample is played after the second reset");
      end if;

      report "tb_pcm: all checks pass";
      stop(0);
   end process p_test;

end architecture simulation;
