-- A test of src/opm.vhd against the vectors of the model,
-- emulator/test/opm_vectors.py.
--
-- THEORY OF OPERATION
-- G_VECTORS is a log of writes, each with the number of the sample
-- before which it lands, at most one in a sample, then "end N", then the
-- N samples of the model, left and right. G_CLK_HZ is low, so that a
-- sample is due once in some 700 cycles, and not 1788.
--
-- p_drive writes the log over the bus, as a master of pipelined
-- Wishbone. A write must go into the FIFO behind the writes of the
-- samples before it, and be the only one there when its own sample
-- starts. So a write whose sample follows that of the write before it
-- goes in at once, behind it, and one after a gap waits until the sample
-- before its own has come out: the next is then some 250 cycles away. A
-- run of more than 64 writes, such as the 228 that set up the channels
-- at the start of a log, fills the FIFO, and each write after that waits
-- for its ACK until a sample takes a write: p_drive counts those waits,
-- and there must be some. Before each write after a gap, it reads the
-- status, whose bits 31..16 must be 0x2151, bits 15..8 at most 64, and
-- bit 7 1 when they are not 0. First, it checks that a reset leaves the
-- FIFO empty, that the words other than the status read 0, and that a
-- write of the status does nothing.
--
-- p_check compares each sample with the model's. It reports the first 10
-- that differ, then how many differ, and stops with status 0 if none, and
-- 1 if any, or if no sample comes for 4 of their periods. It also checks
-- the rate of the samples: from the first to the last, each takes
-- 64 * G_CLK_HZ / 3579545 cycles, and the sum may be off by the cycles of
-- one sample in the engine, C_ENGINE, as a sample comes out when the
-- engine is done with it.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

   use std.textio.all;
   use std.env.all;

entity tb_opm is
   generic (
      G_VECTORS   : string  := "opm.vectors";
      G_CLK_HZ    : natural := 40000000;
      G_ENV_START : natural := 0
   );
end entity tb_opm;

architecture simulation of tb_opm is

   -- The cycles of a sample, rounded up.
   constant C_PERIOD : natural := (64 * (G_CLK_HZ / 1000) + 3579) / 3580;

   -- The most cycles the engine takes for a sample (src/opm_engine.vhd),
   -- and a few for the sample clock.
   constant C_ENGINE : natural := 430;

   signal clk     : std_logic := '0';
   signal rst     : std_logic := '1';
   signal cyc     : std_logic := '0';
   signal stb     : std_logic := '0';
   signal stall   : std_logic;
   signal ack     : std_logic;
   signal we      : std_logic := '0';
   signal addr    : std_logic_vector(2 downto 0)  := (others => '0');
   signal wdata   : std_logic_vector(31 downto 0) := (others => '0');
   signal rdata   : std_logic_vector(31 downto 0);
   signal valid   : std_logic;
   signal left    : std_logic_vector(15 downto 0);
   signal right   : std_logic_vector(15 downto 0);
   signal samples : natural   := 0;
   signal waits   : natural   := 0;
   signal running : boolean   := true;

begin

   clk <= not clk after 5 ns when running else
          '0';
   rst <= '0' after 100 ns;


   i_opm : entity work.opm
      generic map (
         G_CLK_HZ    => G_CLK_HZ,
         G_ENV_START => G_ENV_START
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
         wb_data_i      => wdata,
         wb_data_o      => rdata,
         sample_valid_o => valid,
         sample_left_o  => left,
         sample_right_o => right
      ); -- i_opm


   p_drive : process
      file     vec_f    : text;
      variable l_v      : line;
      variable k_v      : integer;
      variable last_v   : integer := -2;
      variable reg_v    : std_logic_vector(7 downto 0);
      variable data_v   : std_logic_vector(7 downto 0);
      variable word_v   : std_logic_vector(31 downto 0);
      variable cycles_v : natural;
      variable waits_v  : natural := 0;

      -- One access; it returns the word read and the cycles to the ACK.
      procedure bus_access(w : std_logic;
                           a : natural;
                           d : std_logic_vector(31 downto 0);
                           r : out std_logic_vector(31 downto 0);
                           n : out natural) is
         variable n_v : natural := 0;
      begin
         cyc   <= '1';
         stb   <= '1';
         we    <= w;
         addr  <= std_logic_vector(to_unsigned(a, 3));
         wdata <= d;
         loop
            wait until rising_edge(clk);
            n_v := n_v + 1;
            exit when stall = '0';
         end loop;
         stb <= '0';
         while ack /= '1' loop
            wait until rising_edge(clk);
            n_v := n_v + 1;
         end loop;
         cyc <= '0';
         r   := rdata;
         n   := n_v;
      end procedure bus_access;

      procedure read_word(a : natural;
                          r : out std_logic_vector(31 downto 0)) is
         variable n_v : natural;
      begin
         bus_access('0', a, X"00000000", r, n_v);
      end procedure read_word;

      procedure check_status is
         variable s_v : std_logic_vector(31 downto 0);
      begin
         read_word(1, s_v);
         assert s_v(31 downto 16) = X"2151" and unsigned(s_v(15 downto 8)) <= 64
                and s_v(6 downto 0) = "0000000" and (s_v(7) = '1') = (s_v(15 downto 8) /= X"00")
            report "tb_opm: the status is " & to_hstring(s_v)
            severity failure;
      end procedure check_status;

   begin
      wait until rst = '0';
      wait until rising_edge(clk);

      -- After reset: an empty FIFO, and words that read 0.
      bus_access('1', 1, X"0000FFFF", word_v, cycles_v);
      read_word(1, word_v);
      assert word_v = X"21510000"
         report "tb_opm: the status after reset is " & to_hstring(word_v)
         severity failure;
      for a in 0 to 7 loop
         if a /= 1 then
            read_word(a, word_v);
            assert word_v = X"00000000"
               report "tb_opm: word " & integer'image(a) & " reads " & to_hstring(word_v)
               severity failure;
         end if;
      end loop;

      file_open(vec_f, G_VECTORS, read_mode);
      loop
         readline(vec_f, l_v);
         exit when l_v'length > 0 and l_v(l_v'low) = 'e';
         read(l_v, k_v);
         hread(l_v, reg_v);
         hread(l_v, data_v);
         if k_v /= last_v + 1 then
            check_status;
            if samples < k_v then
               wait until samples = k_v;
            end if;
            assert samples = k_v
               report "tb_opm: the write of sample " & integer'image(k_v) & " is late"
               severity failure;
         end if;
         bus_access('1', 0, X"0000" & reg_v & data_v, word_v, cycles_v);
         if cycles_v > 4 then
            waits_v := waits_v + 1;
            waits   <= waits_v;
         end if;
         last_v := k_v;
      end loop;
      file_close(vec_f);
      wait;
   end process p_drive;


   p_check : process
      file     vec_f   : text;
      variable l_v     : line;
      variable word_v  : string(1 to 3);
      variable count_v : natural;
      variable n_v     : integer;
      variable left_v  : integer;
      variable right_v : integer;
      variable fails_v : natural := 0;
      variable first_v : time;
      variable took_v  : real;
      variable want_v  : real;
   begin
      file_open(vec_f, G_VECTORS, read_mode);
      loop
         readline(vec_f, l_v);
         exit when l_v'length > 0 and l_v(l_v'low) = 'e';
      end loop;
      read(l_v, word_v);
      read(l_v, count_v);

      for n in 0 to count_v - 1 loop
         wait until rising_edge(clk) and valid = '1' for 4 * C_PERIOD * 10 ns;
         if valid /= '1' then
            report "tb_opm: no sample " & integer'image(n) & " after " &
                   integer'image(4 * C_PERIOD) & " cycles"
               severity error;
            stop(1);
         end if;
         if n = 0 then
            first_v := now;
         end if;
         readline(vec_f, l_v);
         read(l_v, n_v);
         read(l_v, left_v);
         read(l_v, right_v);
         if to_integer(signed(left)) /= left_v or to_integer(signed(right)) /= right_v then
            fails_v := fails_v + 1;
            if fails_v <= 10 then
               report "tb_opm: sample " & integer'image(n) & " is " &
                      integer'image(to_integer(signed(left))) & " " &
                      integer'image(to_integer(signed(right))) &
                      ", not " & integer'image(left_v) & " " & integer'image(right_v)
                  severity error;
            end if;
         end if;
         samples <= n + 1;
      end loop;
      file_close(vec_f);

      -- The rate: the cycles from the first sample to the last.
      took_v := real((now - first_v) / 10 ns);
      want_v := real(count_v - 1) * 64.0 * real(G_CLK_HZ) / 3579545.0;
      if abs(took_v - want_v) > real(C_ENGINE) then
         report "tb_opm: " & integer'image(count_v - 1) & " samples take " &
                integer'image(integer(took_v)) & " cycles, not " & integer'image(integer(want_v))
            severity error;
         fails_v := fails_v + 1;
      end if;

      if waits = 0 then
         report "tb_opm: no write waited for a full FIFO"
            severity error;
         fails_v := fails_v + 1;
      end if;
      report "tb_opm: " & integer'image(count_v) & " samples, " &
             integer'image(fails_v) & " failures, " &
             integer'image(waits) & " writes waited for a full FIFO";
      running <= false;
      if fails_v = 0 then
         stop(0);
      else
         stop(1);
      end if;
      wait;
   end process p_check;

end architecture simulation;
