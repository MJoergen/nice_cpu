-- A self-checking test of src/sd_regs.vhd, with G_HOLD_ACK false, as on a
-- board, so that busy shows. The test process plays the engine and the
-- cards. emulator/test/sd.nasm, run on both cores by make test, checks
-- the held ACK of the simulation, and the rest of the registers.
--
-- THEORY OF OPERATION
-- The checks:
-- * After reset, the present slot shows "changed", and the empty one
--   nothing.
-- * Init starts the engine with its command and slot, and sets busy. While
--   busy, a write to SD_LBA, SD_SELECT, SD_CSR, or the buffer is ignored,
--   and SD_CHUNK takes one. The end of Init sets "ready", SD_LAST, and the
--   type, and clears "changed".
-- * The engine's bytes of a Read go into the buffer little-endian, and a
--   Write gives them back, each a cycle after its address.
-- * The checks without a card: not ready, out of range, write-protected,
--   and a slot at or above SD_SLOTS, each with no start of the engine.
-- * Taking the card out ends "ready", and putting it in sets "changed".
-- * An engine error is reported, and a failed Init leaves "ready" 0.
-- * Reset abandons a Read with abort_o, and lets a Write on slot 1 run on
--   that slot, with busy 1 until it ends and nothing reported.
-- The run stops with status 0 when every check passes, and 1 at the first
-- that fails.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use std.env.all;

entity tb_sd_regs is
end entity tb_sd_regs;

architecture simulation of tb_sd_regs is

   constant C_CSR    : natural := 0;
   constant C_LBA    : natural := 1;
   constant C_CHUNK  : natural := 2;
   constant C_ERROR  : natural := 3;
   constant C_SELECT : natural := 4;
   constant C_LAST   : natural := 5;
   constant C_SLOTS  : natural := 6;
   constant C_BUF0   : natural := 8;

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

   signal present  : std_logic_vector(1 downto 0)  := "01";
   signal wp       : std_logic_vector(1 downto 0)  := "00";
   signal start    : std_logic;
   signal abort    : std_logic;
   signal cmd      : std_logic_vector(1 downto 0);
   signal slot     : std_logic_vector(3 downto 0);
   signal lba      : std_logic_vector(31 downto 0);
   signal done     : std_logic                     := '0';
   signal fault    : std_logic_vector(3 downto 0)  := X"0";
   signal last     : std_logic_vector(31 downto 0) := (others => '0');
   signal kind     : std_logic_vector(1 downto 0)  := "00";
   signal buf_addr : std_logic_vector(8 downto 0)  := (others => '0');
   signal buf_we   : std_logic                     := '0';
   signal buf_wr   : std_logic_vector(7 downto 0)  := (others => '0');
   signal buf_rd   : std_logic_vector(7 downto 0);

   -- The starts and aborts seen so far
   signal starts : natural                       := 0;
   signal aborts : natural                       := 0;

begin

   p_clk : process
   begin
      clk <= '1', '0' after 5 ns;
      wait for 10 ns;
   end process p_clk;


   i_sd_regs : entity work.sd_regs
      generic map (
         G_SLOTS    => 2,
         G_HOLD_ACK => false
      )
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
         wb_data_o  => data_in,
         present_i  => present,
         wp_i       => wp,
         busy_o     => open,
         start_o    => start,
         abort_o    => abort,
         cmd_o      => cmd,
         slot_o     => slot,
         lba_o      => lba,
         done_i     => done,
         error_i    => fault,
         last_i     => last,
         type_i     => kind,
         buf_addr_i => buf_addr,
         buf_we_i   => buf_we,
         buf_data_i => buf_wr,
         buf_data_o => buf_rd
      ); -- i_sd_regs


   p_count : process (clk)
   begin
      if rising_edge(clk) then
         if start = '1' then
            starts <= starts + 1;
         end if;
         if abort = '1' then
            aborts <= aborts + 1;
         end if;
      end if;
   end process p_count;


   p_test : process

      procedure fail(msg : string) is
      begin
         report "tb_sd_regs: " & msg
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

      procedure check(a : natural; want : std_logic_vector(31 downto 0); what : string) is
         variable got_v : std_logic_vector(31 downto 0);
      begin
         access_word('0', a, X"00000000", got_v);
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

      -- The engine ends its command with error e.
      procedure finish(e : std_logic_vector(3 downto 0)) is
      begin
         done  <= '1';
         fault <= e;
         clocks(1);
         done  <= '0';
         fault <= X"0";
      end procedure finish;

      -- A command that the checks refuse with error e, with no start.
      procedure refused(c : natural; e : std_logic_vector(3 downto 0); what : string) is
         variable n_v : natural;
      begin
         n_v := starts;
         write_word(C_CSR, to_slv(c, 32));
         clocks(1);
         if starts /= n_v then
            fail(what & ": the engine started");
         end if;
         check(C_ERROR, X"0000000" & e, what);
      end procedure refused;

      procedure check_start(c : std_logic_vector(1 downto 0); s : natural; what : string) is
      begin
         if start /= '1' or cmd /= c or slot /= to_slv(s, 4) then
            fail(what & ": no start of command " & to_hstring(c) & " on slot " &
                 integer'image(s));
         end if;
      end procedure check_start;

      procedure init_card(s : natural) is
      begin
         write_word(C_CSR, X"00000000");
         check_start("00", s, "Init");
         last <= X"00000003";
         kind <= "10";
         finish(X"0");
      end procedure init_card;

   begin
      clocks(2);
      rst <= '0';
      clocks(1);

      check(C_CSR, X"00000014", "after reset");
      check(C_SLOTS, X"00000002", "the slots");
      check(C_LAST, X"00000000", "not ready");
      write_word(C_SELECT, X"00000001");
      check(C_CSR, X"00000000", "the empty slot");
      write_word(C_SELECT, X"00000000");

      -- Init, with the writes while busy.
      write_word(C_LBA, X"00000002");
      write_word(C_CSR, X"00000000");
      check_start("00", 0, "Init");
      check(C_CSR, X"00000005", "busy in Init");
      write_word(C_LBA, X"00000009");
      write_word(C_SELECT, X"00000001");
      write_word(C_CSR, X"00000001");
      write_word(C_CHUNK, X"00000003");
      check(C_LBA, X"00000002", "SD_LBA while busy");
      check(C_SELECT, X"00000000", "SD_SELECT while busy");
      check(C_CHUNK, X"00000003", "SD_CHUNK while busy");
      last <= X"00000003";
      kind <= "10";
      finish(X"0");
      check(C_CSR, X"0000020C", "after Init");
      check(C_LAST, X"00000003", "SD_LAST");
      check(C_ERROR, X"00000000", "after Init");

      -- A Read of sector 2: byte b is b xor 0x5A.
      write_word(C_CSR, X"00000001");
      check_start("01", 0, "Read");
      if lba /= X"00000002" then
         fail("the Read's sector");
      end if;
      for b in 0 to 511 loop
         buf_addr <= to_slv(b, 9);
         buf_wr   <= to_slv(b mod 256, 8) xor X"5A";
         buf_we   <= '1';
         clocks(1);
      end loop;
      buf_we <= '0';
      write_word(C_BUF0, X"DEADBEEF");
      finish(X"0");
      -- Chunk 3: bytes 96 to 127, word 0 is bytes 96 to 99.
      check(C_BUF0, X"39383B3A", "chunk 3, word 0");
      check(C_BUF0 + 7, X"25242726", "chunk 3, word 7");
      write_word(C_CHUNK, X"0000000F");
      check(C_BUF0 + 7, X"A5A4A7A6", "chunk 15, word 7");

      -- A Write gives the bytes back, a cycle after their address.
      write_word(C_BUF0 + 7, X"11223344");
      write_word(C_LBA, X"00000003");
      write_word(C_CSR, X"00000002");
      check_start("10", 0, "Write");
      buf_addr <= to_slv(508, 9);
      clocks(1);
      if buf_rd /= X"44" then
         fail("byte 508 is " & to_hstring(buf_rd));
      end if;
      buf_addr <= to_slv(511, 9);
      clocks(1);
      if buf_rd /= X"11" then
         fail("byte 511 is " & to_hstring(buf_rd));
      end if;
      finish(X"0");

      -- The checks without a card.
      write_word(C_LBA, X"00000004");
      refused(1, X"7", "out of range");
      wp <= "01";
      clocks(1);
      check(C_CSR, X"0000022E", "write-protected");
      refused(2, X"7", "out of range before write-protected");
      write_word(C_LBA, X"00000000");
      refused(2, X"6", "write-protected");
      wp <= "00";
      write_word(C_SELECT, X"00000005");
      refused(0, X"1", "slot 5");
      write_word(C_SELECT, X"00000000");
      refused(1, X"2", "not ready after a change of slot");

      -- An engine error, and a failed Init.
      init_card(0);
      write_word(C_CSR, X"00000001");
      finish(X"4");
      check(C_CSR, X"0000020E", "a CRC error");
      write_word(C_CSR, X"00000000");
      finish(X"8");
      check(C_CSR, X"00000006", "a failed Init");
      check(C_ERROR, X"00000008", "a failed Init");

      -- The card taken out, and put in.
      init_card(0);
      present <= "00";
      clocks(1);
      check(C_CSR, X"00000000", "the card taken out");
      present <= "01";
      clocks(1);
      check(C_CSR, X"00000014", "the card put in");
      refused(1, X"2", "not ready after the card came back");

      -- Reset abandons a Read.
      init_card(0);
      write_word(C_CSR, X"00000001");
      rst <= '1';
      clocks(1);
      rst <= '0';
      clocks(1);
      if aborts /= 1 then
         fail("no abort of the Read");
      end if;
      check(C_CSR, X"00000014", "after reset in a Read");

      -- Reset lets a Write on slot 1 run on, and it reports nothing.
      present <= "11";
      clocks(1);
      write_word(C_SELECT, X"00000001");
      init_card(1);
      write_word(C_LBA, X"00000001");
      write_word(C_CSR, X"00000002");
      check_start("10", 1, "Write on slot 1");
      rst <= '1';
      clocks(1);
      rst <= '0';
      clocks(1);
      if aborts /= 1 then
         fail("the Write was abandoned");
      end if;
      check(C_CSR, X"00000015", "busy after reset in a Write");
      check(C_SELECT, X"00000000", "SD_SELECT after reset");
      if slot /= X"1" or lba /= X"00000001" then
         fail("the Write left its slot");
      end if;
      write_word(C_LBA, X"00000002");
      check(C_LBA, X"00000000", "SD_LBA while the Write runs on");
      finish(X"5");
      check(C_CSR, X"00000014", "after the Write");
      check(C_ERROR, X"00000000", "the Write reports nothing");

      report "tb_sd_regs: all checks passed";
      stop(0);
   end process p_test;

end architecture simulation;
