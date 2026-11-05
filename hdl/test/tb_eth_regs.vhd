-- A self-checking test of src/eth_regs.vhd, without G_HOLD_ACK, as on a
-- board, where the station's frames come while the program runs.
--
-- THEORY OF OPERATION
-- p_test plays the program on the bus, and the station on the frame
-- ports. The checks:
-- * After reset, every word reads 0, and enabled_o is 0.
-- * While not enabled, a frame is not taken and not counted, and a write
--   of ETH_TX_LEN sends nothing.
-- * Once enabled, frames enter the queue only when whole: ETH_RX_LEN
--   reads 0 while the first is being written. Bits 31..16 of word 0 read
--   0. Four frames fill the queue, and a fifth is dropped and counted.
-- * The window reads the head's frame by chunk, chunk 48 and up reads 0,
--   and a write to the queue's buffer changes nothing.
-- * A release while a frame is being written lets that frame in at the
--   right slot, and a release of an empty queue is ignored.
-- * A write of ETH_CSR with bit 0 at 0 while a frame is being written
--   empties the queue, sets ETH_DROPPED to 0, and drops the frame.
-- * A send: tx_start_o with the length, busy in ETH_CSR until tx_done_i,
--   the buffer on tx_data_o, writes to it and a second send ignored while
--   busy, lengths 13 and 1515 ignored, and none after a reset that came
--   while it was being sent, which lets it finish.
-- * Reset keeps the send buffer.
-- The run stops with status 0 when every check passes, and 1 at the first
-- that fails.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use std.env.all;

entity tb_eth_regs is
end entity tb_eth_regs;

architecture simulation of tb_eth_regs is

   constant C_CSR     : natural := 0;
   constant C_RX_LEN  : natural := 1;
   constant C_TX_LEN  : natural := 2;
   constant C_CHUNK   : natural := 3;
   constant C_DROPPED : natural := 4;
   constant C_BUF0    : natural := 8;

   signal clk : std_logic;
   signal rst : std_logic := '1';

   signal cyc       : std_logic                     := '0';
   signal stb       : std_logic                     := '0';
   signal stall     : std_logic;
   signal ack       : std_logic;
   signal we        : std_logic                     := '0';
   signal addr      : std_logic_vector(3 downto 0)  := (others => '0');
   signal data_out  : std_logic_vector(31 downto 0) := (others => '0');
   signal data_in   : std_logic_vector(31 downto 0);
   signal enabled   : std_logic;
   signal enable    : std_logic;
   signal rx_start  : std_logic                     := '0';
   signal rx_we     : std_logic                     := '0';
   signal rx_addr   : std_logic_vector(8 downto 0)  := (others => '0');
   signal rx_data   : std_logic_vector(31 downto 0) := (others => '0');
   signal rx_done   : std_logic                     := '0';
   signal rx_len    : std_logic_vector(10 downto 0) := (others => '0');
   signal tx_start  : std_logic;
   signal tx_len    : std_logic_vector(10 downto 0);
   signal tx_addr   : std_logic_vector(8 downto 0)  := (others => '0');
   signal tx_data   : std_logic_vector(31 downto 0);
   signal tx_done   : std_logic                     := '0';
   signal tx_starts : natural                       := 0;

begin

   p_clk : process
   begin
      clk <= '1', '0' after 5 ns;
      wait for 10 ns;
   end process p_clk;


   i_eth_regs : entity work.eth_regs
      port map (
         clk_i         => clk,
         rst_i         => rst,
         wb_cyc_i      => cyc,
         wb_stb_i      => stb,
         wb_stall_o    => stall,
         wb_ack_o      => ack,
         wb_we_i       => we,
         wb_addr_i     => addr,
         wb_data_i     => data_out,
         wb_data_o     => data_in,
         enabled_o     => enabled,
         enable_o      => enable,
         enable_done_i => '0',
         rx_start_i    => rx_start,
         rx_we_i       => rx_we,
         rx_addr_i     => rx_addr,
         rx_data_i     => rx_data,
         rx_done_i     => rx_done,
         rx_len_i      => rx_len,
         tx_start_o    => tx_start,
         busy_o        => open,
         tx_len_o      => tx_len,
         tx_addr_i     => tx_addr,
         tx_data_o     => tx_data,
         tx_done_i     => tx_done
      ); -- i_eth_regs


   -- Counts the cycles with tx_start_o high.
   p_tx_starts : process (clk)
   begin
      if rising_edge(clk) then
         if tx_start = '1' then
            tx_starts <= tx_starts + 1;
         end if;
      end if;
   end process p_tx_starts;


   p_test : process

      procedure fail(msg : string) is
      begin
         report "tb_eth_regs: " & msg
            severity error;
         stop(1);
      end procedure fail;

      -- A request, accepted at the next clock edge. Right after that edge,
      -- ACK is high and the data holds the word as it was before the edge.
      procedure access_word(w : std_logic; a : natural; d : std_logic_vector(31 downto 0);
                            q : out std_logic_vector(31 downto 0)) is
      begin
         cyc      <= '1';
         stb      <= '1';
         we       <= w;
         addr     <= to_slv(a, 4);
         data_out <= d;
         wait until rising_edge(clk);
         if stall /= '0' then
            fail("STALL is high");
         end if;
         stb <= '0';
         cyc <= '0';
         wait for 1 ns;
         if ack /= '1' then
            fail("no ACK in the cycle after the request");
         end if;
         q := data_in;
      end procedure access_word;

      procedure write_word(a : natural; d : std_logic_vector(31 downto 0)) is
         variable q_v : std_logic_vector(31 downto 0);
      begin
         access_word('1', a, d, q_v);
      end procedure write_word;

      procedure write_word(a : natural; d : natural) is
      begin
         write_word(a, to_slv(d, 32));
      end procedure write_word;

      procedure check_word(a : natural; want : std_logic_vector(31 downto 0); what : string) is
         variable q_v : std_logic_vector(31 downto 0);
      begin
         access_word('0', a, X"00000000", q_v);
         if q_v /= want then
            fail(what & ": read " & to_hstring(q_v) & ", want " & to_hstring(want));
         end if;
      end procedure check_word;

      procedure check_word(a : natural; want : natural; what : string) is
      begin
         check_word(a, to_slv(want, 32), what);
      end procedure check_word;

      -- The station begins a frame, and writes its words: word w is
      -- tag * 0x1000000 + w, but word 0, which is all ones.
      procedure frame_begin(tag : natural; words : natural) is
      begin
         rx_start <= '1';
         wait until rising_edge(clk);
         rx_start <= '0';
         for w in 0 to words - 1 loop
            rx_we   <= '1';
            rx_addr <= to_slv(w, 9);
            rx_data <= X"FFFFFFFF" when w = 0 else
                       to_slv(tag, 8) & to_slv(w, 24);
            wait until rising_edge(clk);
         end loop;
         rx_we <= '0';
      end procedure frame_begin;

      procedure frame_end(len : natural) is
      begin
         rx_done <= '1';
         rx_len  <= to_slv(len, 11);
         wait until rising_edge(clk);
         rx_done <= '0';
      end procedure frame_end;

      procedure frame(tag : natural; words : natural; len : natural) is
      begin
         frame_begin(tag, words);
         frame_end(len);
      end procedure frame;

      type t_lens is array (1 to 4) of natural;

      -- The lengths of frames 1 to 4
      constant C_LENS : t_lens := (60, 20, 30, 40);

      variable starts_v : natural;

   begin
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      rst <= '0';
      wait until rising_edge(clk);

      for a in 0 to 15 loop
         check_word(a, 0, "after reset, word " & integer'image(a));
      end loop;
      if enabled /= '0' then
         fail("enabled_o after reset");
      end if;

      -- Not enabled: nothing taken, nothing counted, nothing sent.
      frame(1, 4, 14);
      check_word(C_RX_LEN, 0, "a frame while not enabled");
      check_word(C_DROPPED, 0, "a frame while not enabled is not counted");
      write_word(C_TX_LEN, 14);
      wait until rising_edge(clk);
      wait for 1 ns;
      if tx_starts /= 0 then
         fail("a send while not enabled");
      end if;

      -- Enabled: a frame enters only when whole.
      write_word(C_CSR, 1);
      if enabled /= '1' then
         fail("enabled_o after a write of 1");
      end if;
      frame_begin(1, 16);
      check_word(C_RX_LEN, 0, "a frame half written");
      check_word(C_CSR, 1, "ETH_CSR with a frame half written");
      frame_end(60);
      check_word(C_CSR, 3, "ETH_CSR with a frame waiting");
      check_word(C_RX_LEN, 60, "the first frame");
      check_word(C_BUF0, X"0000FFFF", "word 0's bits 31..16");
      check_word(C_BUF0 + 7, X"01000007", "word 7");
      write_word(C_CHUNK, 1);
      check_word(C_BUF0 + 2, X"0100000A", "word 10");
      write_word(C_CHUNK, 48);
      check_word(C_BUF0, 0, "chunk 48");
      write_word(C_CHUNK, 16#1FF#);
      check_word(C_CHUNK, 16#13F#, "ETH_CHUNK's bits");
      write_word(C_CHUNK, 0);
      write_word(C_BUF0 + 7, X"12345678");
      check_word(C_BUF0 + 7, X"01000007", "a write to the queue's buffer");

      -- Fill the queue, then drop and count.
      frame(2, 4, 20);
      frame(3, 4, 30);
      frame(4, 4, 40);
      frame(5, 4, 50);
      check_word(C_DROPPED, 1, "the fifth frame");
      for t in 1 to 4 loop
         check_word(C_RX_LEN, C_LENS(t), "frame " & integer'image(t));
         check_word(C_BUF0 + 3, to_slv(t, 8) & X"000003", "word 3 of frame " & integer'image(t));
         write_word(C_RX_LEN, 0);
         -- A frame written while the queue has room again goes in at the tail.
         if t = 2 then
            frame_begin(6, 4);
            write_word(C_RX_LEN, 0);
            frame_end(66);
            exit;
         end if;
      end loop;
      -- The queue now holds frames 4 and 6.
      check_word(C_RX_LEN, 40, "frame 4");
      write_word(C_RX_LEN, 0);
      check_word(C_RX_LEN, 66, "frame 6, written during a release");
      check_word(C_BUF0 + 3, X"06000003", "word 3 of frame 6");
      write_word(C_RX_LEN, 0);
      check_word(C_RX_LEN, 0, "the queue emptied");
      write_word(C_RX_LEN, 0);
      check_word(C_CSR, 1, "a release of an empty queue");

      -- A disable while a frame is being written drops it.
      frame(7, 4, 14);
      frame_begin(8, 4);
      write_word(C_CSR, 0);
      frame_end(14);
      check_word(C_CSR, 0, "after a disable");
      check_word(C_RX_LEN, 0, "the queue after a disable");
      check_word(C_DROPPED, 0, "ETH_DROPPED after a disable");
      write_word(C_CSR, 1);
      check_word(C_RX_LEN, 0, "the frame written across a disable");

      -- A send.
      write_word(C_CHUNK, 16#100#);
      write_word(C_BUF0, X"0000AAAA");
      write_word(C_BUF0 + 1, X"BBBBBBBB");
      check_word(C_BUF0 + 1, X"BBBBBBBB", "the send buffer");
      write_word(C_TX_LEN, 13);
      write_word(C_TX_LEN, 1515);
      wait until rising_edge(clk);
      wait for 1 ns;
      if tx_starts /= 0 then
         fail("a send of 13 or 1515 bytes");
      end if;
      write_word(C_TX_LEN, 14);
      wait until rising_edge(clk);
      wait for 1 ns;
      if tx_starts /= 1 or tx_len /= 14 then
         fail("no send of 14 bytes");
      end if;
      check_word(C_CSR, 5, "ETH_CSR while busy");
      write_word(C_BUF0 + 1, X"CCCCCCCC");
      write_word(C_TX_LEN, 20);
      tx_addr <= to_slv(1, 9);
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      wait for 1 ns;
      if tx_data /= X"BBBBBBBB" or tx_starts /= 1 or tx_len /= 14 then
         fail("a write or a send while busy");
      end if;
      tx_done <= '1';
      wait until rising_edge(clk);
      tx_done <= '0';
      check_word(C_CSR, 1, "ETH_CSR after the send");

      -- A reset while a frame is sent lets it finish, and keeps the buffer.
      write_word(C_TX_LEN, 14);
      rst <= '1';
      wait until rising_edge(clk);
      rst <= '0';
      wait for 1 ns;
      starts_v := tx_starts;
      check_word(C_CSR, 4, "busy after a reset during a send");
      tx_done <= '1';
      wait until rising_edge(clk);
      tx_done <= '0';
      check_word(C_CSR, 0, "after the send that a reset let finish");
      if tx_starts /= starts_v then
         fail("a send after the reset");
      end if;
      write_word(C_CHUNK, 16#100#);
      check_word(C_BUF0 + 1, X"BBBBBBBB", "a reset keeps the send buffer");

      report "tb_eth_regs: all checks passed";
      stop(0);
   end process p_test;

end architecture simulation;
