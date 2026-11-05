-- Simulation-only station for src/eth_regs.vhd: it gives the frames of
-- the file G_IN_FILE, and writes the frames sent to G_OUT_FILE, as
-- niceemu's --eth-in and --eth-out do (SYSTEM.md §7, the emulator).
--
-- THEORY OF OPERATION
-- The file is read at time 0: one frame per line, each byte as two hex
-- digits, with spaces between bytes allowed, a # that starts a comment,
-- and a line "N: ..." whose frame waits until N frames have been sent.
-- The lines arrive in order, at enable_i and at each frame sent, every
-- next line whose N has been reached, before enable_done_o or tx_done_o.
-- With eth_regs's G_HOLD_ACK, the core waits in the write that enabled
-- the port or sent the frame, so it reads the queue as in the emulator.
--
-- A line arrives at the station, which serves it as the emulator's does
-- (SYSTEM.md §6, §7): a frame to another MAC address than mac_i, and not
-- to everyone, is dropped. While ip_i is not 0, an ARP request for ip_i
-- and a ping to it are answered, the reply written to G_OUT_FILE, and TCP
-- to ip_i and tcp_port_i, if not 0, is kept. Every other frame goes to
-- eth_regs: rx_start_o for a cycle, then one word per cycle, and then
-- rx_done_o with the length. eth_regs decides whether it takes it.
--
-- A frame sent is read from the send buffer, a word in two cycles, and
-- written to G_OUT_FILE without the padding, as a line of hex bytes with
-- a space between them. Then the lines arrive, and tx_done_o ends it.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) enable_i and tx_start_i are high for a cycle, and not again before
--    enable_done_o or tx_done_o. tx_len_i holds until tx_done_o.
-- b) Each line of G_IN_FILE is valid, with 14 to 1514 bytes. Otherwise the
--    simulation fails at time 0, as niceemu refuses to start.
-- c) At most C_MAX_LINES lines.
--
-- RESET
-- None. The count of frames sent and the lines that have arrived are the
-- run's, as the emulator's are its launch's.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use std.textio.all;

entity eth_sim is
   generic (
      G_IN_FILE  : string := "";
      G_OUT_FILE : string := ""
   );
   port (
      clk_i         : in  std_logic;

      -- The station's registers of SYSTEM.md §6
      ip_i          : in  std_logic_vector(31 downto 0);
      mac_i         : in  std_logic_vector(47 downto 0);
      tcp_port_i    : in  std_logic_vector(15 downto 0);

      enable_i      : in  std_logic;
      enable_done_o : out std_logic                     := '0';

      rx_start_o    : out std_logic                     := '0';
      rx_we_o       : out std_logic                     := '0';
      rx_addr_o     : out std_logic_vector(8 downto 0)  := (others => '0');
      rx_data_o     : out std_logic_vector(31 downto 0) := (others => '0');
      rx_done_o     : out std_logic                     := '0';
      rx_len_o      : out std_logic_vector(10 downto 0) := (others => '0');

      tx_start_i    : in  std_logic;
      tx_len_i      : in  std_logic_vector(10 downto 0);
      tx_addr_o     : out std_logic_vector(8 downto 0)  := (others => '0');
      tx_data_i     : in  std_logic_vector(31 downto 0);
      tx_done_o     : out std_logic                     := '0'
   );
end entity eth_sim;

architecture simulation of eth_sim is

   constant C_MAX_LINES : natural := 256;

   subtype t_byte is natural range 0 to 255;

   type t_bytes is array (natural range <>) of t_byte;
   type t_frame is access t_bytes;

   type t_line is record
      wait_for : natural;
      frame    : t_frame;
   end record t_line;

   type t_lines is array (0 to C_MAX_LINES - 1) of t_line;

   file out_f : text;

   function hex_value(c : character) return integer is
   begin
      case c is
         when '0' to '9' => return character'pos(c) - character'pos('0');
         when 'a' to 'f' => return character'pos(c) - character'pos('a') + 10;
         when 'A' to 'F' => return character'pos(c) - character'pos('A') + 10;
         when others     => return -1;
      end case;
   end function hex_value;

   function hex2(b : t_byte) return string is
      constant C_DIGITS : string(1 to 16) := "0123456789abcdef";
   begin
      return C_DIGITS(b / 16 + 1) & C_DIGITS(b mod 16 + 1);
   end function hex2;

   -- The start of a message about line no of G_IN_FILE.
   function at_line(no : natural) return string is
   begin
      return "eth_sim: " & G_IN_FILE & ":" & integer'image(no) & ": ";
   end function at_line;

   -- The Internet checksum of f(first to last) (RFC 1071).
   function checksum(f : t_bytes; first : natural; last : natural) return natural is
      variable sum_v : natural := 0;
      variable i_v   : natural := first;
   begin
      while i_v <= last loop
         if i_v + 1 <= last then
            sum_v := sum_v + f(i_v) * 256 + f(i_v + 1);
         else
            sum_v := sum_v + f(i_v) * 256;
         end if;
         i_v := i_v + 2;
      end loop;
      while sum_v > 65535 loop
         sum_v := sum_v mod 65536 + sum_v / 65536;
      end loop;
      return 65535 - sum_v;
   end function checksum;

   -- The bytes f(first to first + n - 1), big-endian, as a number.
   function field(f : t_bytes; first : natural; n : natural) return std_logic_vector is
      variable v_v : std_logic_vector(8 * n - 1 downto 0);
   begin
      for i in 0 to n - 1 loop
         v_v(8 * (n - i) - 1 downto 8 * (n - i - 1)) := to_slv(f(first + i), 8);
      end loop;
      return v_v;
   end function field;

begin

   p_station : process
      variable lines_v  : t_lines;
      variable nlines_v : natural := 0;
      variable next_v   : natural := 0;
      variable sent_v   : natural := 0;

      -- Read the lines of G_IN_FILE (SYSTEM.md §7).
      procedure load is
         file     f        : text;
         variable status_v : file_open_status;
         variable l_v      : line;
         variable no_v     : natural := 0;
         variable bytes_v  : t_bytes(0 to 1513);
         variable n_v      : natural;
         variable after_v  : natural;
         variable have_v   : integer;
         variable d_v      : integer;
         variable last_v   : natural;
      begin
         if G_IN_FILE = "" then
            return;
         end if;
         file_open(status_v, f, G_IN_FILE, read_mode);
         assert status_v = open_ok
            report "eth_sim: cannot read " & G_IN_FILE
            severity failure;
         while not endfile(f) loop
            readline(f, l_v);
            no_v    := no_v + 1;
            n_v     := 0;
            after_v := 0;
            have_v  := -1;
            last_v  := l_v'length;
            for i in 1 to l_v'length loop
               if l_v(i) = '#' then
                  last_v := i - 1;
                  exit;
               end if;
            end loop;
            for i in 1 to last_v loop
               if l_v(i) = ':' then
                  -- The digits so far were the count, in decimal.
                  after_v := 0;
                  for j in 1 to i - 1 loop
                     if l_v(j) /= ' ' and l_v(j) /= HT then
                        assert l_v(j) >= '0' and l_v(j) <= '9'
                           report at_line(no_v) & "bad count"
                           severity failure;
                        after_v := after_v * 10 + hex_value(l_v(j));
                     end if;
                  end loop;
                  n_v    := 0;
                  have_v := -1;
               elsif l_v(i) = ' ' or l_v(i) = HT or l_v(i) = CR then
                  assert have_v = -1
                     report at_line(no_v) & "a byte has one hex digit"
                     severity failure;
               else
                  d_v := hex_value(l_v(i));
                  assert d_v >= 0
                     report at_line(no_v) & "not a hex digit"
                     severity failure;
                  if have_v = -1 then
                     have_v := d_v;
                  else
                     bytes_v(n_v) := have_v * 16 + d_v;
                     n_v          := n_v + 1;
                     have_v       := -1;
                  end if;
               end if;
            end loop;
            if n_v /= 0 then
               assert n_v >= 14 and have_v = -1
                  report at_line(no_v) & "not a frame of 14 to 1514 bytes"
                  severity failure;
               assert nlines_v < C_MAX_LINES
                  report "eth_sim: more than " & integer'image(C_MAX_LINES) & " lines"
                  severity failure;
               lines_v(nlines_v).wait_for := after_v;
               lines_v(nlines_v).frame := new t_bytes'(bytes_v(0 to n_v - 1));
               nlines_v                := nlines_v + 1;
            end if;
         end loop;
         file_close(f);
      end procedure load;

      -- Write the frame f to G_OUT_FILE.
      procedure emit(f : t_bytes) is
         variable l_v : line;
      begin
         if G_OUT_FILE = "" then
            return;
         end if;
         for i in f'range loop
            if i /= f'low then
               write(l_v, string'(" "));
            end if;
            write(l_v, hex2(f(i)));
         end loop;
         writeline(out_f, l_v);
         flush(out_f);
      end procedure emit;

      -- Give the frame f to eth_regs.
      procedure enqueue(f : t_bytes) is
         variable word_v : std_logic_vector(31 downto 0);
         variable k_v    : natural;
      begin
         rx_start_o <= '1';
         wait until rising_edge(clk_i);
         rx_start_o <= '0';
         for w in 0 to (f'length + 2 + 3) / 4 - 1 loop
            word_v := (others => '0');
            for j in 0 to 3 loop
               k_v := 4 * w + j;
               if k_v >= 2 and k_v - 2 < f'length then
                  word_v(31 - 8 * j downto 24 - 8 * j) := to_slv(f(k_v - 2), 8);
               end if;
            end loop;
            rx_we_o   <= '1';
            rx_addr_o <= to_slv(w, 9);
            rx_data_o <= word_v;
            wait until rising_edge(clk_i);
         end loop;
         rx_we_o   <= '0';
         rx_done_o <= '1';
         rx_len_o  <= to_slv(f'length, 11);
         wait until rising_edge(clk_i);
         rx_done_o <= '0';
      end procedure enqueue;

      -- Whether the station keeps f, as SYSTEM.md §6 says, with its reply.
      procedure serve(f : t_bytes; kept : out boolean) is
         variable r_v     : t_bytes(0 to 1513);
         variable ihl_v   : natural;
         variable total_v : natural;
         variable sum_v   : natural;
      begin
         kept := false;
         if ip_i = 0 then
            return;
         end if;
         if field(f, 12, 2) = X"0806" then
            if f'length < 42 or field(f, 14, 8) /= X"0001080006040001" or
               field(f, 38, 4) /= ip_i then
               return;
            end if;
            r_v(0 to 5) := f(22 to 27);
            for i in 0 to 5 loop
               r_v(6 + i)  := to_integer(mac_i(47 - 8 * i downto 40 - 8 * i));
               r_v(22 + i) := r_v(6 + i);
            end loop;
            r_v(12 to 21) := (16#08#, 16#06#, 0, 1, 16#08#, 0, 6, 4, 0, 2);
            for i in 0 to 3 loop
               r_v(28 + i) := to_integer(ip_i(31 - 8 * i downto 24 - 8 * i));
            end loop;
            r_v(32 to 41) := f(22 to 31);
            emit(r_v(0 to 41));
            kept := true;
            return;
         end if;
         if field(f, 12, 2) /= X"0800" or f'length < 34 or f(14) / 16 /= 4 or f(14) mod 16 < 5 then
            return;
         end if;
         ihl_v   := (f(14) mod 16) * 4;
         total_v := f(16) * 256 + f(17);
         if total_v < ihl_v or 14 + total_v > f'length or field(f, 30, 4) /= ip_i then
            return;
         end if;
         if f(23) = 1 then
            if total_v < ihl_v + 8 or f(14 + ihl_v) /= 8 or f(15 + ihl_v) /= 0 then
               return;
            end if;
            r_v(0 to 13 + total_v) := f(0 to 13 + total_v);
            r_v(0 to 5)            := f(6 to 11);
            for i in 0 to 5 loop
               r_v(6 + i) := to_integer(mac_i(47 - 8 * i downto 40 - 8 * i));
            end loop;
            r_v(30 to 33) := f(26 to 29);
            for i in 0 to 3 loop
               r_v(26 + i) := to_integer(ip_i(31 - 8 * i downto 24 - 8 * i));
            end loop;
            r_v(24 to 25)          := (0, 0);
            sum_v                  := checksum(r_v, 14, 13 + ihl_v);
            r_v(24 to 25)          := (sum_v / 256, sum_v mod 256);
            r_v(14 + ihl_v)        := 0;
            r_v(16 + ihl_v)        := 0;
            r_v(17 + ihl_v)        := 0;
            sum_v                  := checksum(r_v, 14 + ihl_v, 13 + total_v);
            r_v(16 + ihl_v)        := sum_v / 256;
            r_v(17 + ihl_v)        := sum_v mod 256;
            emit(r_v(0 to 13 + total_v));
            kept := true;
         elsif f(23) = 6 then
            kept := tcp_port_i /= 0 and total_v >= ihl_v + 4 and
                    field(f, 16 + ihl_v, 2) = tcp_port_i;
         end if;
      end procedure serve;

      -- A frame arrives at the station.
      procedure receive(f : t_bytes) is
         variable kept_v : boolean;
      begin
         if field(f, 0, 6) /= mac_i and field(f, 0, 6) /= X"FFFFFFFFFFFF" then
            return;
         end if;
         serve(f, kept_v);
         if not kept_v then
            enqueue(f);
         end if;
      end procedure receive;

      -- The lines whose count of frames sent has been reached arrive.
      procedure arrive is
      begin
         while next_v < nlines_v and lines_v(next_v).wait_for <= sent_v loop
            receive(lines_v(next_v).frame.all);
            next_v := next_v + 1;
         end loop;
      end procedure arrive;

      variable frame_v : t_bytes(0 to 1513);
      variable len_v   : natural;
      variable k_v     : natural;
      variable word_v  : std_logic_vector(31 downto 0);
   begin
      load;
      if G_OUT_FILE /= "" then
         file_open(out_f, G_OUT_FILE, write_mode);
      end if;

      loop
         wait until rising_edge(clk_i);
         if enable_i = '1' then
            arrive;
            enable_done_o <= '1';
            wait until rising_edge(clk_i);
            enable_done_o <= '0';
         elsif tx_start_i = '1' then
            len_v := to_integer(tx_len_i);
            for w in 0 to (len_v + 2 + 3) / 4 - 1 loop
               tx_addr_o <= to_slv(w, 9);
               wait until rising_edge(clk_i);
               wait until rising_edge(clk_i);
               word_v := tx_data_i;
               for j in 0 to 3 loop
                  k_v := 4 * w + j;
                  if k_v >= 2 and k_v - 2 < len_v then
                     frame_v(k_v - 2) := to_integer(word_v(31 - 8 * j downto 24 - 8 * j));
                  end if;
               end loop;
            end loop;
            emit(frame_v(0 to len_v - 1));
            sent_v := sent_v + 1;
            arrive;
            tx_done_o <= '1';
            wait until rising_edge(clk_i);
            tx_done_o <= '0';
         end if;
      end loop;
   end process p_station;

end architecture simulation;
