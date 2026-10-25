-- A self-checking test of src/debug_link.vhd, the debug link of doc/DEBUG.md.
--
-- THEORY OF OPERATION
-- The test plays the host and the board. It sends the byte streams of
-- DEBUG.md §8, and more, and compares every byte that the link sends with
-- the exact string it must be. Each string is written out with its
-- checksum, which is the sum of the bytes from the tag to the last payload
-- byte, mod 256, worked out by hand. ESC is the byte 0xFF.
-- The board is a memory of 4096 words on a Wishbone slave that stalls in
-- every other cycle, a memory clear that takes 30 cycles, or 300 where the
-- test says so, and a core model that halts when the test says so, pauses
-- some cycles after a request, goes on for a step_wait cycles when
-- pause_o falls while it is paused, and loses its registers, its halt, and its
-- pause while it is held, as the real core does.
-- The checks, in the order of the run:
-- * the notice `b03` after reset, and the examples of DEBUG.md §8;
-- * lowercase digits, a bad checksum, an unknown tag, a payload with a bad
--   length or a bad digit, and a W with too many words;
-- * the debug registers, a clear of the memory, one that a dropped packet
--   started, a W that wraps past 0xFFFFFFFF, and a start;
-- * the errors while the program runs, and that no word is written then;
-- * console bytes both ways, ESC ESC, the overflow notice `o`, and the
--   order of console bytes and packets;
-- * the timeout, an ESC with no letter, and the end of the input;
-- * the halt notice `h`, the registers and the halt kept while held, and
--   the restart;
-- * the pause: bit 4, the notice `p` after and before the answer, the memory,
--   the registers, and the console while paused, a hold and a start that
--   keep or begin a pause, a go on, and a halt that ignores a request;
-- * the step: bit 5, pause_o low for exactly one cycle, bit 4 and the memory
--   during the step, one `p` after it, a step into a halt, a hold during the
--   step, and a write with bit 5 that does not step.
-- The run stops with status 0 when every check passes, and 1 at the first
-- that fails.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

   use std.env.all;

entity tb_debug_link is
end entity tb_debug_link;

architecture simulation of tb_debug_link is

   constant C_TIMEOUT : positive    := 300;
   constant C_ESC     : character := character'val(255);

   type t_mem is array (0 to 4095) of std_logic_vector(31 downto 0);

   signal clk : std_logic;
   signal rst : std_logic := '1';

   signal rx_valid : std_logic                    := '0';
   signal rx_ready : std_logic;
   signal rx_data  : std_logic_vector(7 downto 0) := (others => '0');
   signal rx_break : std_logic                    := '0';
   signal tx_valid : std_logic;
   signal tx_ready : std_logic;
   signal tx_data  : std_logic_vector(7 downto 0);
   signal tx_ok    : std_logic                    := '1';
   signal tick     : std_logic                    := '0';

   signal con_valid    : std_logic                     := '0';
   signal con_ready    : std_logic;
   signal con_data     : std_logic_vector(7 downto 0)  := (others => '0');
   signal con_in_valid : std_logic;
   signal con_in_data  : std_logic_vector(7 downto 0);
   signal free         : std_logic_vector(15 downto 0) := X"0008";
   signal eoi          : std_logic;

   signal hold       : std_logic;
   signal rom_hide   : std_logic;
   signal clear      : std_logic;
   signal clear_done : std_logic                      := '0';
   signal clear_len  : natural                        := 30;
   signal halted     : std_logic                      := '0';
   signal reason     : std_logic_vector(2 downto 0)   := "000";
   signal regs       : std_logic_vector(511 downto 0) := (others => '0');
   signal core_halt  : std_logic                      := '0';
   signal pause      : std_logic;
   signal paused     : std_logic                      := '0';
   signal pause_wait : natural                        := 40;
   signal step_wait  : natural                        := 20;
   signal step_halts : std_logic                      := '0';
   signal short_runs : natural                        := 0;
   signal long_runs  : natural                        := 0;

   signal wb_cyc   : std_logic;
   signal wb_stb   : std_logic;
   signal wb_stall : std_logic                     := '0';
   signal wb_ack   : std_logic                     := '0';
   signal wb_we    : std_logic;
   signal wb_addr  : std_logic_vector(31 downto 0);
   signal wb_wdata : std_logic_vector(31 downto 0);
   signal wb_rdata : std_logic_vector(31 downto 0) := (others => '0');

   signal mem    : t_mem   := (others => (others => '0'));
   signal writes : natural := 0;

   -- Every byte sent to the host, and every console byte for the program
   signal got     : string(1 to 4096);
   signal got_len : natural := 0;
   signal cin     : string(1 to 256);
   signal cin_len : natural := 0;

begin

   p_clk : process
   begin
      clk <= '1', '0' after 5 ns;
      wait for 10 ns;
   end process p_clk;


   i_debug_link : entity work.debug_link
      generic map (
         G_TIMEOUT   => C_TIMEOUT,
         G_HAS_ROM   => true,
         G_BOOT_HELD => true
      )
      port map (
         clk_i          => clk,
         rst_i          => rst,
         rx_valid_i     => rx_valid,
         rx_ready_o     => rx_ready,
         rx_data_i      => rx_data,
         rx_break_i     => rx_break,
         tx_valid_o     => tx_valid,
         tx_ready_i     => tx_ready,
         tx_data_o      => tx_data,
         con_valid_i    => con_valid,
         con_ready_o    => con_ready,
         con_data_i     => con_data,
         con_in_valid_o => con_in_valid,
         con_in_data_o  => con_in_data,
         free_i         => free,
         eoi_o          => eoi,
         hold_o         => hold,
         rom_hide_o     => rom_hide,
         clear_o        => clear,
         clear_done_i   => clear_done,
         halted_i       => halted,
         halt_reason_i  => reason,
         pause_o        => pause,
         paused_i       => paused,
         regs_i         => regs,
         wb_cyc_o       => wb_cyc,
         wb_stb_o       => wb_stb,
         wb_stall_i     => wb_stall,
         wb_ack_i       => wb_ack,
         wb_we_o        => wb_we,
         wb_addr_o      => wb_addr,
         wb_data_o      => wb_wdata,
         wb_data_i      => wb_rdata
      ); -- i_debug_link


   -- The host's receiver takes a byte in every other cycle.
   p_tick : process (clk)
   begin
      if rising_edge(clk) then
         tick <= not tick;
      end if;
   end process p_tick;

   tx_ready <= tx_ok and tick;


   p_mon : process (clk)
   begin
      if rising_edge(clk) then
         if tx_valid = '1' and tx_ready = '1' then
            got(got_len + 1) <= character'val(to_integer(unsigned(tx_data)));
            got_len          <= got_len + 1;
         end if;
         if con_in_valid = '1' then
            cin(cin_len + 1) <= character'val(to_integer(unsigned(con_in_data)));
            cin_len          <= cin_len + 1;
         end if;
      end if;
   end process p_mon;


   -- The memory on a pipelined Wishbone slave that stalls in every other
   -- cycle, and the memory clear.
   p_board : process (clk)
      variable clear_cnt_v : natural := 0;
   begin
      if rising_edge(clk) then
         wb_ack     <= '0';
         wb_stall   <= not wb_stall;
         clear_done <= '0';
         if wb_cyc = '1' and wb_stb = '1' and wb_stall = '0' then
            wb_ack <= '1';
            if wb_we = '1' then
               writes <= writes + 1;
               if unsigned(wb_addr) < 4096 then
                  mem(to_integer(unsigned(wb_addr(11 downto 0)))) <= wb_wdata;
               end if;
            end if;
            if unsigned(wb_addr) < 4096 then
               wb_rdata <= mem(to_integer(unsigned(wb_addr(11 downto 0))));
            else
               wb_rdata <= X"DEADBEEF";
            end if;
         end if;
         assert clear = '0' or wb_cyc = '0'
            report "tb_debug_link: an access during a clear"
            severity failure;
         if clear = '1' then
            clear_cnt_v := clear_cnt_v + 1;
            if clear_cnt_v = clear_len then
               mem         <= (others => (others => '0'));
               clear_done  <= '1';
               clear_cnt_v := 0;
            end if;
         else
            clear_cnt_v := 0;
         end if;
      end if;
   end process p_board;


   -- The core: it halts when asked, and loses everything while it is held.
   -- R(n) is 0x1234560n while it runs or is halted.
   p_core : process (clk)
      variable wait_v : natural := 0;
      variable go_v   : boolean := false;
      variable step_v : natural := 0;
   begin
      if rising_edge(clk) then
         if hold = '1' then
            halted <= '0';
            reason <= "000";
            regs   <= (others => '0');
            paused <= '0';
            wait_v := 0;
            go_v   := false;
         else
            -- A pause comes pause_wait cycles after the request, and a halt
            -- goes first. When pause falls while the core is paused, it goes
            -- on, and runs for step_wait cycles whatever pause is, as the
            -- cores do after a go on (MICROARCH.md §6.1): it pauses again
            -- then if pause is 1, and halts if step_halts says so.
            if pause = '1' and halted = '0' and core_halt = '0' then
               if go_v then
                  if step_v >= step_wait then
                     go_v := false;
                     if step_halts = '1' then
                        halted <= '1';
                        reason <= "001";
                     else
                        paused <= '1';
                     end if;
                  else
                     step_v := step_v + 1;
                  end if;
               elsif wait_v >= pause_wait then
                  paused <= '1';
               else
                  wait_v := wait_v + 1;
               end if;
            else
               if paused = '1' and pause = '0' then
                  go_v   := true;
                  step_v := 0;
               elsif go_v then
                  if step_v >= step_wait then
                     go_v := false;
                  else
                     step_v := step_v + 1;
                  end if;
               end if;
               paused <= '0';
               wait_v := 0;
            end if;
            for n in 0 to 15 loop
               regs(32 * n + 31 downto 32 * n) <= X"123456" & "0000" &
                                                  std_logic_vector(to_unsigned(n, 4));
            end loop;
            if core_halt = '1' then
               halted <= '1';
               reason <= "001";
            end if;
         end if;
      end if;
   end process p_core;


   -- The runs of cycles with pause_o low that start while the core is paused:
   -- a step has one cycle, a go on more.
   p_runs : process (clk)
      variable run_v : natural := 0;
   begin
      if rising_edge(clk) then
         if pause = '0' and (paused = '1' or run_v > 0) then
            run_v := run_v + 1;
         else
            if run_v = 1 then
               short_runs <= short_runs + 1;
            elsif run_v > 1 then
               long_runs <= long_runs + 1;
            end if;
            run_v := 0;
         end if;
      end if;
   end process p_runs;


   p_test : process
      variable used_v  : natural := 0;
      variable cused_v : natural := 0;
      variable wr_v    : natural := 0;

      procedure fail(msg : string) is
      begin
         report "tb_debug_link: " & msg
            severity error;
         stop(1);
      end procedure fail;

      procedure cycles(n : natural) is
      begin
         for i in 1 to n loop
            wait until rising_edge(clk);
         end loop;
      end procedure cycles;

      -- Sends the bytes of s from the host to the link.
      procedure send(s : string) is
      begin
         for i in s'range loop
            rx_valid <= '1';
            rx_data  <= std_logic_vector(to_unsigned(character'pos(s(i)), 8));
            wait until rising_edge(clk) and rx_ready = '1';
         end loop;
         rx_valid <= '0';
      end procedure send;

      -- Waits for the bytes of s from the link, and compares them.
      procedure expect(s : string; what : string) is
         variable n_v : natural := 0;
      begin
         while got_len < used_v + s'length and n_v < 20000 loop
            wait until rising_edge(clk);
            n_v := n_v + 1;
         end loop;
         if got_len < used_v + s'length then
            fail(what & ": the answer is short, " & integer'image(got_len - used_v) &
                 " [" & got(used_v + 1 to got_len) & "]" &
                 " of " & integer'image(s'length) & " bytes");
         end if;
         for i in s'range loop
            if got(used_v + i) /= s(i) then
               fail(what & ": byte " & integer'image(i) & " is " &
                    integer'image(character'pos(got(used_v + i))) & ", not " &
                    integer'image(character'pos(s(i))));
            end if;
         end loop;
         used_v := used_v + s'length;
      end procedure expect;

      -- Waits for the bytes of a and b, in either order, and compares them.
      procedure expect_either(a : string; b : string; what : string) is
         variable n_v : natural := 0;
      begin
         while got_len < used_v + a'length + b'length and n_v < 20000 loop
            wait until rising_edge(clk);
            n_v := n_v + 1;
         end loop;
         if got_len < used_v + a'length + b'length then
            fail(what & ": the answer is short, " & integer'image(got_len - used_v) & " bytes");
         end if;
         if got(used_v + 1 to used_v + a'length + b'length) /= a & b and
            got(used_v + 1 to used_v + a'length + b'length) /= b & a then
            fail(what & ": got [" & got(used_v + 1 to used_v + a'length + b'length) & "]");
         end if;
         used_v := used_v + a'length + b'length;
      end procedure expect_either;

      -- Checks that the link sends nothing more.
      procedure quiet(what : string) is
      begin
         cycles(3 * C_TIMEOUT);
         if got_len /= used_v then
            fail(what & ": " & integer'image(got_len - used_v) & " unexpected bytes");
         end if;
      end procedure quiet;

      -- Checks the console bytes for the program since the last call.
      procedure expect_in(s : string; what : string) is
      begin
         cycles(20);
         if cin_len /= cused_v + s'length then
            fail(what & ": " & integer'image(cin_len - cused_v) & " console bytes, not " &
                 integer'image(s'length));
         end if;
         for i in s'range loop
            if cin(cused_v + i) /= s(i) then
               fail(what & ": console byte " & integer'image(i) & " differs");
            end if;
         end loop;
         cused_v := cused_v + s'length;
      end procedure expect_in;

      -- A byte that the program wrote to the console
      procedure con_put(b : natural) is
      begin
         con_valid <= '1';
         con_data  <= std_logic_vector(to_unsigned(b, 8));
         wait until rising_edge(clk) and con_ready = '1';
         con_valid <= '0';
      end procedure con_put;

      procedure check_mem(a : natural; v : std_logic_vector(31 downto 0); what : string) is
      begin
         if mem(a) /= v then
            fail(what & ": word " & integer'image(a) & " is " & to_hstring(mem(a)));
         end if;
      end procedure check_mem;

   begin
      cycles(3);
      rst <= '0';

      -- Reset: a notice, and the processor held with the ROM shown.
      expect(C_ESC & "b03#C5", "b02");
      assert hold = '1' and rom_hide = '0' and eoi = '0'
         report "tb_debug_link: state after reset"
         severity failure;

      -- DEBUG.md §8: a write and a read back, while held.
      send(C_ESC & "W0000010000021122334455667788#E2");
      expect(C_ESC & "k000001000002#AE", "write");
      check_mem(256, X"11223344", "write");
      check_mem(257, X"55667788", "write");
      send(C_ESC & "R000001000001#94");
      expect(C_ESC & "r00000100000111223344#48", "read");
      quiet("example");

      -- Lowercase digits are accepted. The checksum is of the bytes as sent.
      send(C_ESC & "W0000010000011a2b3c4d#ed");
      expect(C_ESC & "k000001000001#AD", "lowercase");
      check_mem(256, X"1A2B3C4D", "lowercase");
      send(C_ESC & "R000001000001#94");
      expect(C_ESC & "r0000010000011A2B3C4D#88", "lowercase read");

      -- A bad checksum drops the packet silently.
      send(C_ESC & "R000001000001#95");
      send(C_ESC & "R000001000001#9");
      quiet("bad checksum");
      send(C_ESC & "R000001000001#94");
      expect(C_ESC & "r0000010000011A2B3C4D#88", "after a bad checksum");

      -- Unknown tags, also lowercase ones, are e01.
      send(C_ESC & "XABCD#62");
      expect(C_ESC & "e5801#33", "e01");
      send(C_ESC & "rAB#F5");
      expect(C_ESC & "e7201#2F", "e01 for a lowercase tag");

      -- A bad length or a bad digit is e03.
      send(C_ESC & "R0000010000#33");
      expect(C_ESC & "e5203#2F", "short R");
      send(C_ESC & "R00000100000G#AA");
      expect(C_ESC & "e5203#2F", "bad digit");
      send(C_ESC & "R0000010000011#C5");
      expect(C_ESC & "e5203#2F", "long R");
      send(C_ESC & "W00000200000211223344#2F");
      expect(C_ESC & "e5703#34", "W with a word short");
      check_mem(512, X"11223344", "W with a word short");
      send(C_ESC & "W000002000001112233#C6");
      expect(C_ESC & "e5703#34", "W with a partial word");
      send(C_ESC & "W0000020000011122334455667788#E2");
      expect(C_ESC & "e5703#34", "W with too many words");
      check_mem(512, X"11223344", "W with too many words");
      check_mem(513, X"00000000", "W with too many words");
      send(C_ESC & "W000003000001ZZ000000#6F");
      expect(C_ESC & "e5703#34", "W with a bad digit");
      check_mem(768, X"00000000", "W with a bad digit");
      quiet("errors");

      -- The registers while held: version, free space, reserved words, and control.
      send(C_ESC & "RFFFFFFF20001#2F");
      expect(C_ESC & "rFFFFFFF2000100000003#D2", "version");
      send(C_ESC & "RFFFFFFF30001#30");
      expect(C_ESC & "rFFFFFFF3000100000008#D8", "free space");
      send(C_ESC & "RFFFFFFF40002#32");
      expect(C_ESC & "rFFFFFFF400020000000000000000#52", "reserved");
      send(C_ESC & "RFFFFFFF00001#2D");
      expect(C_ESC & "rFFFFFFF0000100000001#CE", "control while held");

      -- A clear and stay held: the answer comes when the memory is clear.
      send(C_ESC & "WFFFFFFF0000100000005#B7");
      expect(C_ESC & "kFFFFFFF00001#46", "clear");
      check_mem(256, X"00000000", "clear");
      check_mem(512, X"00000000", "clear");
      assert hold = '1' and rom_hide = '0' and clear = '0'
         report "tb_debug_link: state after a clear"
         severity failure;

      -- A clear that a dropped packet started: the clear starts with the
      -- word, before the bad checksum. The next request waits for the clear,
      -- so its word is not lost, and p_board checks that the master makes
      -- no access during the clear.
      clear_len <= 300;
      send(C_ESC & "WFFFFFFF0000100000005#B8");
      send(C_ESC & "W00000100000111223344#2D");
      expect(C_ESC & "k000001000001#AD", "write after a dropped clear");
      check_mem(256, X"11223344", "write after a dropped clear");
      clear_len <= 30;
      send(C_ESC & "WFFFFFFF0000100000005#B7");
      expect(C_ESC & "kFFFFFFF00001#46", "clear again");

      -- A W that wraps past 0xFFFFFFFF is e02, also while held, and writes
      -- nothing: neither the start in its first word nor word 0.
      send(C_ESC & "WFFFFFFF00011" & "00000000000000000000000000000000" &
           "00000000000000000000000000000000" & "00000000000000000000000000000000" &
           "00000000000000000000000000000000" & "00001234#BD");
      expect(C_ESC & "e5702#33", "W that wraps");
      check_mem(0, X"00000000", "W that wraps");
      assert hold = '1'
         report "tb_debug_link: a W that wraps starts the processor"
         severity failure;

      -- A clear that hides the ROM and stays held, then a plain start.
      send(C_ESC & "WFFFFFFF000010000000D#C6");
      expect(C_ESC & "kFFFFFFF00001#46", "clear and hide");
      assert hold = '1' and rom_hide = '1'
         report "tb_debug_link: hide"
         severity failure;
      send(C_ESC & "WFFFFFFF0000100000008#BA");
      expect(C_ESC & "kFFFFFFF00001#46", "start");
      assert hold = '0' and rom_hide = '1'
         report "tb_debug_link: start"
         severity failure;

      -- While the program runs, only the debug registers are reached.
      wr_v := writes;
      send(C_ESC & "R000001000001#94");
      expect(C_ESC & "e5202#2E", "e02 read");
      send(C_ESC & "W00000100000111111111#21");
      expect(C_ESC & "e5702#33", "e02 write");
      send(C_ESC & "R0000010000011#C5");
      expect(C_ESC & "e5202#2E", "e02 before e03");
      send(C_ESC & "XABCD#62");
      expect(C_ESC & "e5801#33", "e01 before e02");
      if writes /= wr_v then
         fail("a bus write while the program runs");
      end if;
      check_mem(256, X"00000000", "e02 write");
      send(C_ESC & "RFFFFFFF00002#2E");
      expect(C_ESC & "rFFFFFFF000020000000800000000#56", "debug registers while running");
      quiet("running");

      -- Console bytes from the host reach the program while it runs.
      send("A" & C_ESC & C_ESC & "B");
      expect_in("A" & character'val(255) & "B", "console in");
      quiet("console in");

      -- Overflow: one notice, until there is room again.
      free <= X"0000";
      cycles(5);
      send("C");
      expect(C_ESC & "o#6F", "o");
      send("D");
      send("E");
      quiet("second o");
      expect_in("", "lost bytes");
      free <= X"0005";
      cycles(5);
      send("F");
      expect_in("F", "room again");
      free <= X"0000";
      cycles(5);
      send("G");
      expect(C_ESC & "o#6F", "o again");
      free <= X"0008";
      quiet("o again");
      expect_in("", "after o again");

      -- Console bytes from the program, with 0xFF sent as ESC ESC.
      con_put(character'pos('x'));
      con_put(255);
      con_put(character'pos('y'));
      expect("x" & C_ESC & C_ESC & "y", "console out");
      quiet("console out");

      -- A packet is never broken by a console byte: that comes after it.
      tx_ok <= '0';
      send(C_ESC & "RFFFFFFF30001#30");
      cycles(10);
      con_valid <= '1';
      con_data  <= std_logic_vector(to_unsigned(character'pos('z'), 8));
      cycles(10);
      tx_ok <= '1';
      wait until rising_edge(clk) and con_ready = '1';
      con_valid <= '0';
      expect(C_ESC & "rFFFFFFF3000100000008#D8" & "z", "packet before console");
      quiet("order");

      -- The timeout: the rest of a packet is then console bytes.
      send(C_ESC & "R000001000001#");
      cycles(2 * C_TIMEOUT);
      send("94");
      expect_in("94", "timeout");
      quiet("timeout");

      -- ESC and a byte that is no letter drop both.
      send(C_ESC & "1Q");
      expect_in("Q", "C_ESC and a digit");

      -- An ESC before the # starts a new packet.
      send(C_ESC & "R000001" & C_ESC & "RFFFFFFF30001#30");
      expect(C_ESC & "rFFFFFFF3000100000008#D8", "C_ESC in a packet");
      quiet("C_ESC in a packet");

      -- A break ends the input, and a console byte is then dropped.
      rx_break <= '1';
      cycles(1);
      rx_break <= '0';
      cycles(3);
      assert eoi = '1'
         report "tb_debug_link: no end of input"
         severity failure;
      free <= X"0000";
      send("H");
      quiet("dropped after the end of the input");
      expect_in("", "after the end of the input");
      free <= X"0008";

      -- A halt: the last console byte, then h.
      con_put(character'pos('q'));
      core_halt <= '1';
      expect("q" & C_ESC & "h01#C9", "halt");
      quiet("halt");
      send(C_ESC & "RFFFFFFF00001#2D");
      expect(C_ESC & "rFFFFFFF000010000000A#DE", "control after the halt");
      send(C_ESC & "RFFFFFFF10001#2E");
      expect(C_ESC & "rFFFFFFF1000100000001#CF", "reason");
      send(C_ESC & "R000001000001#94");
      expect(C_ESC & "r00000100000100000000#34", "read after the halt");
      send(C_ESC & "W00000100000155555555#41");
      expect(C_ESC & "k000001000001#AD", "write after the halt");
      check_mem(256, X"55555555", "write after the halt");
      send(C_ESC & "RFFFFFFEF0001#42");
      expect(C_ESC & "rFFFFFFEF00011234560F#0D", "R15 after the halt");
      -- The console byte of a halted program is dropped, with no overflow.
      free <= X"0000";
      send("J");
      quiet("dropped after a halt");
      expect_in("", "after a halt");
      free <= X"0008";

      -- Hold: the registers and the halt stay while the core loses them.
      core_halt <= '0';
      send(C_ESC & "WFFFFFFF0000100000009#BB");
      expect(C_ESC & "kFFFFFFF00001#46", "hold");
      assert hold = '1'
         report "tb_debug_link: hold"
         severity failure;
      cycles(5);
      assert regs = (511 downto 0 => '0')
         report "tb_debug_link: the core keeps its registers"
         severity failure;
      send(C_ESC & "RFFFFFFEF0001#42");
      expect(C_ESC & "rFFFFFFEF00011234560F#0D", "R15 while held");
      send(C_ESC & "RFFFFFFF00001#2D");
      expect(C_ESC & "rFFFFFFF000010000000B#DF", "control while held after the halt");
      send(C_ESC & "RFFFFFFF10001#2E");
      expect(C_ESC & "rFFFFFFF1000100000001#CF", "reason while held");
      quiet("hold");

      -- Start again: the halt and the end of the input are cleared.
      send(C_ESC & "WFFFFFFF0000100000008#BA");
      expect(C_ESC & "kFFFFFFF00001#46", "restart");
      assert hold = '0' and eoi = '0'
         report "tb_debug_link: restart"
         severity failure;
      send(C_ESC & "RFFFFFFF00001#2D");
      expect(C_ESC & "rFFFFFFF0000100000008#D5", "control after the restart");
      send(C_ESC & "RFFFFFFF10001#2E");
      expect(C_ESC & "rFFFFFFF1000100000000#CE", "reason after the restart");
      quiet("restart");

      -- A pause request: k first, and p when the core has paused. Bit 4
      -- reads 1 then, and the link reaches the memory.
      send(C_ESC & "WFFFFFFF0000100000018#BB");
      expect(C_ESC & "kFFFFFFF00001#46", "pause request");
      expect(C_ESC & "p#70", "p");
      quiet("p once");
      assert pause = '1' and paused = '1'
         report "tb_debug_link: pause"
         severity failure;
      send(C_ESC & "RFFFFFFF00001#2D");
      expect(C_ESC & "rFFFFFFF0000100000018#D6", "control while paused");
      send(C_ESC & "R000001000001#94");
      expect(C_ESC & "r00000100000155555555#5C", "read while paused");
      send(C_ESC & "W00000101000166666666#4A");
      expect(C_ESC & "k000001010001#AE", "write while paused");
      check_mem(257, X"66666666", "write while paused");
      send(C_ESC & "RFFFFFFEF0001#42");
      expect(C_ESC & "rFFFFFFEF00011234560F#0D", "R15 while paused");
      -- A console byte waits for the program.
      send("K");
      expect_in("K", "console byte while paused");

      -- A hold ends the pause and keeps the registers, as after a halt.
      send(C_ESC & "WFFFFFFF0000100000009#BB");
      expect(C_ESC & "kFFFFFFF00001#46", "hold paused");
      cycles(5);
      assert hold = '1' and pause = '0' and regs = (511 downto 0 => '0')
         report "tb_debug_link: hold paused"
         severity failure;
      send(C_ESC & "RFFFFFFEF0001#42");
      expect(C_ESC & "rFFFFFFEF00011234560F#0D", "R15 kept by a hold");
      send(C_ESC & "RFFFFFFF00001#2D");
      expect(C_ESC & "rFFFFFFF0000100000009#D6", "control held after a pause");
      quiet("hold paused");

      -- A request while held does not read 1, and the start pauses before
      -- the first step.
      send(C_ESC & "WFFFFFFF0000100000019#BC");
      expect(C_ESC & "kFFFFFFF00001#46", "request while held");
      send(C_ESC & "RFFFFFFF00001#2D");
      expect(C_ESC & "rFFFFFFF0000100000009#D6", "request reads 0 while held");
      quiet("request while held");
      send(C_ESC & "WFFFFFFF0000100000018#BB");
      expect(C_ESC & "kFFFFFFF00001#46", "start paused");
      expect(C_ESC & "p#70", "p at start");
      assert paused = '1'
         report "tb_debug_link: start paused"
         severity failure;

      -- A write of 0 to bit 4 goes on, and the memory is out of reach at
      -- once. No notice follows.
      send(C_ESC & "WFFFFFFF0000100000008#BA");
      expect(C_ESC & "kFFFFFFF00001#46", "go on");
      send(C_ESC & "R000001000001#94");
      expect(C_ESC & "e5202#2E", "e02 after go on");
      send(C_ESC & "RFFFFFFF00001#2D");
      expect(C_ESC & "rFFFFFFF0000100000008#D5", "control after go on");
      quiet("go on");
      assert pause = '0' and paused = '0'
         report "tb_debug_link: go on"
         severity failure;

      -- A pause that is quick comes before the answer: a notice may come
      -- between a request and its answer.
      pause_wait <= 1;
      send(C_ESC & "WFFFFFFF0000100000018#BB");
      expect(C_ESC & "p#70" & C_ESC & "kFFFFFFF00001#46", "p before k");
      quiet("p before k");
      send(C_ESC & "WFFFFFFF0000100000008#BA");
      expect(C_ESC & "kFFFFFFF00001#46", "go on again");
      quiet("go on again");
      pause_wait <= 40;

      -- The step (DEBUG.md §6): pause, then a write with bits 4 and 5. pause_o
      -- is low for one cycle. Bit 4 reads 0 and the memory is out of reach
      -- until the step ends, then one p follows.
      send(C_ESC & "WFFFFFFF0000100000018#BB");
      expect(C_ESC & "kFFFFFFF00001#46", "pause before the step");
      expect(C_ESC & "p#70", "p before the step");
      wait until rising_edge(clk);
      assert short_runs = 0 and long_runs = 3
         report "tb_debug_link: runs before the step " & integer'image(short_runs) & " " &
                integer'image(long_runs)
         severity failure;
      step_wait <= 400;
      send(C_ESC & "WFFFFFFF0000100000038#BD");
      expect(C_ESC & "kFFFFFFF00001#46", "step");
      send(C_ESC & "R000001000001#94");
      expect(C_ESC & "e5202#2E", "e02 during the step");
      send(C_ESC & "RFFFFFFF00001#2D");
      expect(C_ESC & "rFFFFFFF0000100000008#D5", "control during the step");
      expect(C_ESC & "p#70", "p after the step");
      quiet("p once after the step");
      assert short_runs = 1 and long_runs = 3
         report "tb_debug_link: pause_o low for one cycle"
         severity failure;
      send(C_ESC & "RFFFFFFF00001#2D");
      expect(C_ESC & "rFFFFFFF0000100000018#D6", "control after the step");
      send(C_ESC & "R000001000001#94");
      expect(C_ESC & "r00000100000155555555#5C", "memory after the step");
      -- A quick step: the k and the p come in either order, and there is one
      -- of each.
      step_wait <= 1;
      send(C_ESC & "WFFFFFFF0000100000038#BD");
      expect_either(C_ESC & "kFFFFFFF00001#46", C_ESC & "p#70", "quick step");
      quiet("quick step");
      assert short_runs = 2 and long_runs = 3
         report "tb_debug_link: quick step"
         severity failure;
      -- A step is one pause_o fall each, also back to back.
      step_wait <= 20;
      for i in 1 to 3 loop
         send(C_ESC & "WFFFFFFF0000100000038#BD");
         expect_either(C_ESC & "kFFFFFFF00001#46", C_ESC & "p#70", "repeated step");
      end loop;
      assert short_runs = 5 and long_runs = 3
         report "tb_debug_link: repeated steps"
         severity failure;
      -- A hold during the step is a hold of a running core: no notice, and
      -- the next start paused sends its p.
      step_wait <= 400;
      send(C_ESC & "WFFFFFFF0000100000038#BD");
      expect(C_ESC & "kFFFFFFF00001#46", "step before the hold");
      send(C_ESC & "WFFFFFFF0000100000009#BB");
      expect(C_ESC & "kFFFFFFF00001#46", "hold during the step");
      cycles(500);
      quiet("hold during the step");
      send(C_ESC & "RFFFFFFF00001#2D");
      expect(C_ESC & "rFFFFFFF0000100000009#D6", "control held during the step");
      step_wait <= 20;
      send(C_ESC & "WFFFFFFF0000100000018#BB");
      expect(C_ESC & "kFFFFFFF00001#46", "start paused after the hold");
      expect(C_ESC & "p#70", "p after the hold");
      -- A write with bit 5 does not step unless the core is paused: the
      -- bit with bit 0 holds, and the bit alone goes on.
      send(C_ESC & "WFFFFFFF0000100000039#BE");
      expect(C_ESC & "kFFFFFFF00001#46", "hold with bit 5");
      quiet("hold with bit 5");
      assert short_runs = 6 and long_runs = 3
         report "tb_debug_link: hold with bit 5 " & integer'image(short_runs) & " " &
                integer'image(long_runs)
         severity failure;
      send(C_ESC & "WFFFFFFF0000100000038#BD");
      expect(C_ESC & "kFFFFFFF00001#46", "start with bit 5");
      expect(C_ESC & "p#70", "p after the start with bit 5");
      assert short_runs = 6 and long_runs = 3
         report "tb_debug_link: start with bit 5"
         severity failure;
      send(C_ESC & "WFFFFFFF0000100000028#BC");
      expect(C_ESC & "kFFFFFFF00001#46", "go on with bit 5 only");
      quiet("go on with bit 5 only");
      -- A step request while the pause is still on its way acts as a pause
      -- request: no step, and one p.
      pause_wait <= 2000;
      send(C_ESC & "WFFFFFFF0000100000018#BB");
      expect(C_ESC & "kFFFFFFF00001#46", "request before the early step");
      send(C_ESC & "WFFFFFFF0000100000038#BD");
      expect(C_ESC & "kFFFFFFF00001#46", "early step");
      expect(C_ESC & "p#70", "p after the early step");
      pause_wait <= 40;
      quiet("early step");
      assert short_runs = 6
         report "tb_debug_link: early step"
         severity failure;
      -- A step into a halt ends in h, not p, and bit 4 reads 0.
      step_halts <= '1';
      send(C_ESC & "WFFFFFFF0000100000038#BD");
      expect_either(C_ESC & "kFFFFFFF00001#46", C_ESC & "h01#C9", "step into a halt");
      quiet("step into a halt");
      send(C_ESC & "RFFFFFFF00002#2E");
      expect(C_ESC & "rFFFFFFF000020000000A00000001#60", "control after the halt step");
      step_halts <= '0';
      send(C_ESC & "WFFFFFFF0000100000009#BB");
      expect(C_ESC & "kFFFFFFF00001#46", "hold after the halt step");
      send(C_ESC & "WFFFFFFF0000100000008#BA");
      expect(C_ESC & "kFFFFFFF00001#46", "restart after the halt step");

      -- A halt goes first: a halted core ignores the request, bit 4 reads 0,
      -- and no p follows the h.
      core_halt <= '1';
      expect(C_ESC & "h01#C9", "halt before pause");
      send(C_ESC & "WFFFFFFF0000100000018#BB");
      expect(C_ESC & "kFFFFFFF00001#46", "request when halted");
      send(C_ESC & "RFFFFFFF00001#2D");
      expect(C_ESC & "rFFFFFFF000010000000A#DE", "control when halted");
      quiet("request when halted");

      report "tb_debug_link: pass";
      stop(0);
   end process p_test;

end architecture simulation;
