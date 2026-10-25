-- The debug link of doc/DEBUG.md, as a byte-stream module: one byte stream
-- in from the host and one out, such as a UART receiver and transmitter,
-- and a Wishbone master for the memory. It knows no FPGA and no clock rate.
--
-- THEORY OF OPERATION
-- Three processes. p_rx splits the incoming bytes into console bytes and
-- packets (§1, §2), checks the checksum and the timeout (§5), decides the
-- errors (§3), and writes the words of a W as they arrive. p_acc executes
-- one word access at a time, for p_rx and p_tx: it holds the debug
-- registers of §6 itself, and sends any other address to the Wishbone
-- master. p_tx sends the output: the answers, the notices (§4), and the
-- console bytes of the program, one whole packet at a time, so nothing
-- comes between the bytes of a packet. When more than one is waiting, the
-- order is: an answer, `b`, `o`, a console byte, `h`, and `p`. So `h` and
-- `p` come after the last console byte that the program wrote.
--
-- The link reaches no word but the debug registers while the program runs
-- (§3), so the Wishbone master is used only while the processor is held,
-- halted, or paused.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) Every access on the Wishbone master is a link access (§3). The
--    board's bus must give such an access to the console (0xFFFFFF00) and
--    the read counter (0xFFFFFF01) as the board's own link rule: a read
--    returns 0 and takes no input byte and counts nothing, and a write is
--    ignored. A read of CYCLE_LO, INSTR_LO, or TIME_LO (SYSTEM.md §3)
--    returns the low word, and may take a snapshot, as perf.vhd does
--    (DEBUG.md §3). The simplest board gives the console and the read
--    counter a link-only path that these accesses take. The
--    processor never uses the bus while this master does: the master
--    works only while hold_o, halted_i, or the link's paused flag is high.
--    While the processor is paused, the counters and the timer stop, and a
--    link read of a counter may take a snapshot (DEBUG.md §3).
-- b) The Wishbone slave is pipelined, as the cores' data bus is: it sends
--    ACK in a later cycle than the one that accepts a request, and holds
--    its read data valid with the ACK.
-- c) rx_ready_o goes low for at most a few cycles after a byte, for as long
--    as a Wishbone write takes, so a UART receiver that cannot wait must be
--    able to hold a byte for that long. It goes low for longer only after
--    the tag of a packet that waits for the answer to the last request, or
--    for a clear (below) that a dropped W started. A host that waits for
--    its answers (DEBUG.md §3) sends no such tag, but for one after a
--    dropped packet, before the clear ends.
-- d) free_i is the number of console bytes that the program's input buffer
--    can take, and shows a byte of con_in_valid_o 2 cycles after the
--    strobe. A strobe is always accepted: it comes only while free_i was
--    not 0 two cycles earlier.
-- e) halted_i, paused_i, and regs_i come from a core that rst_i = hold_o
--    resets, so they may change to 0 once hold_o is high. This unit keeps
--    the last values of a halt or a pause itself (§6). regs_i is R0 to R15,
--    R(n) in bits 32 * n + 31 .. 32 * n, and valid as long as halted_i or
--    paused_i is high. A board without the registers ties it to 0. A core
--    pauses only after pause_o was high (MICROARCH.md §6.1), never together
--    with a halt, and never while hold_o is high.
-- f) A clear: clear_o goes high when the link asks for it, and stays high
--    until the board has set every word of the memory to 0 and answers
--    with one cycle of clear_done_i, which is not before the cycle after
--    clear_o rose. While clear_o is high, the board owns the memory, so
--    the master makes no access. The answer to the request waits for it,
--    and so does the next request, also when the W that started the clear
--    was dropped.
--
-- The host side:
-- * rx_*: a byte from the host, with valid and ready, and rx_break_i, a
--   pulse for a UART break. It ends the console's input (eoi_o) until the
--   next start (SYSTEM.md §5, DEBUG.md §7).
-- * tx_*: a byte to the host.
-- The program side:
-- * con_*: a byte that the program wrote to 0xFFFFFF00, with valid and
--   ready. The link sends it, and a 0xFF as ESC ESC.
-- * con_in_valid_o and con_in_data_o: a one-cycle strobe with a console
--   byte from the host, for the program's input buffer.
-- * eoi_o: '1' from a break until the next start, the end of the input.
--   While it is high, the console reads 0x200.
-- Processor control:
-- * hold_o: the control register's bit 0. It resets the core and the
--   devices. The board empties the program's input buffer when it falls,
--   which is a start.
-- * rom_hide_o: bit 3. '1' where the RAM is at 0.
-- * halted_i and halt_reason_i: the core's halt (DEBUG.md §6).
-- * pause_o and paused_i: bit 4, the request of a pause, which comes from a
--   flip-flop as MICROARCH.md §6.1 requires, and the core's pause. The
--   board stops the counters and the timer while paused_i is high.
--   A step (DEBUG.md §6) drops pause_o for exactly one cycle while the core
--   is paused, and raises it again.
--
-- FORMAL
-- With G_FORMAL, the properties that need the state of the processes, for
-- formal/formal_debug_link.vhd: p_out parses the bytes that the host
-- takes, as DEBUG.md §1 and §2 frame them, and every packet is whole, with
-- a known tag, upper-case hex digits, `#`, and its checksum, and a console
-- byte goes out only between packets; no answer starts during a clear;
-- rx_ready_o is low only as contract c says; and hold_o and rom_hide_o
-- change only on a write to the control register, at the end of a clear,
-- or at reset. The invariants i_* tie p_rx, p_acc, p_tx, and the parser
-- together, so that k-induction proves it all. The properties of the ports
-- are in formal/formal_debug_link.vhd.
--
-- RESET
-- Synchronous. It sends `b03`, empties everything, and leaves the
-- processor held with G_BOOT_HELD, or running with the ROM shown otherwise.
-- G_HAS_ROM is false on a system without a ROM: bit 3 then reads 1 and
-- ignores writes, and rom_hide_o is 1.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

entity debug_link is
   generic (
      -- The most clock cycles between two bytes of a packet, 100 ms
      G_TIMEOUT   : positive := 10_000_000;
      G_HAS_ROM   : boolean  := true;
      G_BOOT_HELD : boolean  := false;
      -- The properties of formal/formal_debug_link.vhd that name the
      -- registers here
      G_FORMAL    : boolean  := false
   );
   port (
      clk_i          : in  std_logic;
      rst_i          : in  std_logic;

      -- The host
      rx_valid_i     : in  std_logic;
      rx_ready_o     : out std_logic;
      rx_data_i      : in  std_logic_vector(7 downto 0);
      rx_break_i     : in  std_logic;
      tx_valid_o     : out std_logic;
      tx_ready_i     : in  std_logic;
      tx_data_o      : out std_logic_vector(7 downto 0);

      -- The program's console
      con_valid_i    : in  std_logic;
      con_ready_o    : out std_logic;
      con_data_i     : in  std_logic_vector(7 downto 0);
      con_in_valid_o : out std_logic := '0';
      con_in_data_o  : out std_logic_vector(7 downto 0);
      free_i         : in  std_logic_vector(15 downto 0);
      eoi_o          : out std_logic;

      -- The processor
      hold_o         : out std_logic;
      rom_hide_o     : out std_logic;
      clear_o        : out std_logic;
      clear_done_i   : in  std_logic;
      halted_i       : in  std_logic;
      halt_reason_i  : in  std_logic_vector(2 downto 0);
      pause_o        : out std_logic;
      paused_i       : in  std_logic;
      regs_i         : in  std_logic_vector(511 downto 0);

      -- The memory: a pipelined Wishbone master, as the data bus of the cores
      wb_cyc_o       : out std_logic;
      wb_stb_o       : out std_logic;
      wb_stall_i     : in  std_logic;
      wb_ack_i       : in  std_logic;
      wb_we_o        : out std_logic;
      wb_addr_o      : out std_logic_vector(31 downto 0);
      wb_data_o      : out std_logic_vector(31 downto 0);
      wb_data_i      : in  std_logic_vector(31 downto 0)
   );
end entity debug_link;

architecture synthesis of debug_link is

   subtype t_byte is std_logic_vector(7 downto 0);

   subtype t_word is std_logic_vector(31 downto 0);

   type t_rx_st is (
      RX_IDLE_ST, RX_ESC_ST, RX_HOLD_ST, RX_PAY_ST, RX_CC1_ST, RX_CC2_ST, RX_CALL_ST, RX_WAIT_ST
   );

   type t_tx_st is (
      TX_IDLE_ST, TX_CON2_ST, TX_TAG_ST, TX_FIELD_ST, TX_CALL_ST, TX_WAIT_ST, TX_DIG_ST,
      TX_HASH_ST, TX_CC1_ST, TX_CC2_ST
   );

   type t_acc_st is (ACC_IDLE_ST, ACC_REQ_ST, ACC_WAIT_ST);

   type t_pkt is (PKT_B, PKT_H, PKT_O, PKT_K, PKT_E, PKT_R, PKT_P);

   constant C_ESC : t_byte := X"FF";

   constant C_VERSION : t_word := X"00000003";

   function to_sl(b : boolean) return std_logic is
   begin
      if b then
         return '1';
      end if;
      return '0';
   end function to_sl;

   function is_hex(b : t_byte) return boolean is
   begin
      return (b >= X"30" and b <= X"39") or (b >= X"41" and b <= X"46") or
             (b >= X"61" and b <= X"66");
   end function is_hex;

   function hex_of(b : t_byte) return std_logic_vector is
   begin
      if b <= X"39" then
         return b(3 downto 0);
      end if;
      return b(3 downto 0) + 9;
   end function hex_of;

   function hex_char(n : std_logic_vector(3 downto 0)) return t_byte is
   begin
      if n < 10 then
         return X"30" + ("0000" & n);
      end if;
      return X"37" + ("0000" & n);
   end function hex_char;

   function is_letter(b : t_byte) return boolean is
   begin
      return (b >= X"41" and b <= X"5A") or (b >= X"61" and b <= X"7A");
   end function is_letter;

   function kind_char(k : t_pkt) return t_byte is
   begin
      case k is
         when PKT_B => return X"62";
         when PKT_H => return X"68";
         when PKT_O => return X"6F";
         when PKT_K => return X"6B";
         when PKT_E => return X"65";
         when PKT_R => return X"72";
         when PKT_P => return X"70";
      end case;
   end function kind_char;

   -- True if the n words from a reach a word that is not a debug register
   function non_dbg(a : t_word; n : std_logic_vector(15 downto 0)) return boolean is
   begin
      if n = X"0000" then
         return false;
      end if;
      if a(31 downto 5) /= (31 downto 5 => '1') then
         return true;
      end if;
      return to_integer(a(4 downto 0)) + to_integer(n) > 32;
   end function non_dbg;

   -- True if the n words from a run past 0xFFFFFFFF, which a W may not
   function wraps(a : t_word; n : std_logic_vector(15 downto 0)) return boolean is
   begin
      return a(31 downto 16) = X"FFFF" and
             to_integer(a(15 downto 0)) + to_integer(n) > 2 ** 16;
   end function wraps;

   -- The p_rx side
   signal rx_st      : t_rx_st                      := RX_IDLE_ST;
   signal rx_rdy     : std_logic;
   signal gap_r      : natural range 0 to 2         := 0;
   signal tmo_r      : natural range 0 to G_TIMEOUT := 0;
   signal tag_r      : t_byte                       := (others => '0');
   signal sum_r      : t_byte                       := (others => '0');
   signal cc_hi_r    : std_logic_vector(3 downto 0) := (others => '0');
   signal dig_r      : natural range 0 to 2 ** 20   := 0;
   signal nib_r      : natural range 0 to 7         := 0;
   signal wcnt_r     : natural range 0 to 2 ** 17   := 0;
   signal bad_r      : std_logic                    := '0';
   signal err02_r    : std_logic                    := '0';
   signal req_addr_r : t_word                       := (others => '0');
   signal req_n_r    : std_logic_vector(15 downto 0) := (others => '0');
   signal cur_addr_r : t_word                       := (others => '0');
   signal word_r     : t_word                       := (others => '0');
   signal rx_go_r    : std_logic                    := '0';
   signal o_armed_r  : std_logic                    := '1';

   -- The answer, from p_rx to p_tx. A request is pending as long as the two
   -- toggles differ, until p_tx has sent the whole answer.
   signal ans_req_tgl : std_logic                    := '0';
   signal ans_ack_tgl : std_logic                    := '0';
   signal ans_kind_r  : t_pkt                       := PKT_K;
   signal ans_tag_r   : t_byte                       := (others => '0');
   signal ans_code_r  : t_byte                       := (others => '0');
   signal ans_p       : std_logic;

   -- The overflow notice, from p_rx to p_tx
   signal o_req_tgl : std_logic                    := '0';
   signal o_ack_tgl : std_logic                    := '0';
   signal o_p       : std_logic;

   -- The p_tx side
   signal tx_st       : t_tx_st                      := TX_IDLE_ST;
   signal out_valid_r : std_logic                    := '0';
   signal out_data_r  : t_byte                       := (others => '0');
   signal kind_r      : t_pkt                       := PKT_B;
   signal fld_r       : natural range 0 to 2         := 0;
   signal ndig_r      : natural range 0 to 8         := 0;
   signal sh_r        : t_word                       := (others => '0');
   signal tx_sum_r    : t_byte                       := (others => '0');
   signal tx_addr_r   : t_word                       := (others => '0');
   signal tx_cnt_r    : std_logic_vector(15 downto 0) := (others => '0');
   signal tx_go_r     : std_logic                    := '0';
   signal b_pend_r    : std_logic                    := '1';
   signal h_sent_r    : std_logic                    := '0';
   signal p_sent_r    : std_logic                    := '0';

   -- The p_acc side
   signal acc_st      : t_acc_st                     := ACC_IDLE_ST;
   signal acc_go      : std_logic;
   signal acc_we      : std_logic;
   signal acc_addr    : t_word;
   signal acc_done_r  : std_logic                    := '0';
   signal acc_rdata_r : t_word                       := (others => '0');
   signal hold_r      : std_logic                    := '0';
   signal halted_r    : std_logic                    := '0';
   signal pause_r     : std_logic                    := '0';
   signal paused_r    : std_logic                    := '0';
   signal step_r      : std_logic                    := '0';
   signal stepping_r  : std_logic                    := '0';
   signal fell_r      : std_logic                    := '0';
   signal reason_r    : std_logic_vector(2 downto 0) := (others => '0');
   signal hide_r      : std_logic                    := '0';
   signal eoi_r       : std_logic                    := '0';
   signal clearing_r  : std_logic                    := '0';
   signal clr_hold_r  : std_logic                    := '0';
   signal regs_r      : std_logic_vector(511 downto 0) := (others => '0');
   signal wb_cyc_r    : std_logic                    := '0';
   signal wb_stb_r    : std_logic                    := '0';
   signal wb_we_r     : std_logic                    := '0';
   signal wb_addr_r   : t_word                       := (others => '0');
   signal wb_data_r   : t_word                       := (others => '0');

   -- The link owns the memory while the core is paused and the request of
   -- the pause stands. A write of 0 to bit 4 ends it at once, before the
   -- core has gone on. A step ends it too, from the write until the core has
   -- gone on and paused or halted again: paused_r still follows the old
   -- pause for a cycle, and pause_r is high again.
   signal pause_own : std_logic;

begin

   ---------------------------------------------------------------------------
   -- Receive: console bytes and packets
   ---------------------------------------------------------------------------

   rx_rdy     <= '1' when gap_r = 0 and rx_st /= RX_HOLD_ST and rx_st /= RX_CALL_ST and
                      rx_st /= RX_WAIT_ST else
             '0';
   rx_ready_o <= rx_rdy;

   ans_p <= '1' when ans_req_tgl /= ans_ack_tgl and clearing_r = '0' else
            '0';
   o_p   <= '1' when o_req_tgl /= o_ack_tgl else
            '0';


   p_rx : process (clk_i)
      variable b_v    : t_byte;
      variable acc_v  : boolean;
      variable busy_v : boolean;
      variable h_v    : std_logic_vector(3 downto 0);
      variable n_v    : std_logic_vector(15 downto 0);
      variable code_v : t_byte;

      -- A console byte from the host goes to the program only while it runs
      -- and has room. Without room, the byte is lost, and `o` is due once.
      procedure forward(b : t_byte) is
      begin
         if hold_r = '0' and halted_r = '0' and eoi_r = '0' then
            if free_i = X"0000" then
               if o_armed_r = '1' then
                  o_req_tgl <= not o_req_tgl;
               end if;
               o_armed_r <= '0';
            else
               con_in_valid_o <= '1';
               con_in_data_o  <= b;
            end if;
         end if;
      end procedure forward;

   begin
      if rising_edge(clk_i) then
         con_in_valid_o <= '0';
         if free_i /= X"0000" then
            o_armed_r <= '1';
         end if;

         acc_v  := rx_valid_i = '1' and rx_rdy = '1';
         b_v    := rx_data_i;
         -- A W that a dropped packet ended may have started a clear, which
         -- no answer waits for.
         busy_v := ans_req_tgl /= ans_ack_tgl or clearing_r = '1';

         if gap_r /= 0 then
            gap_r <= gap_r - 1;
         end if;
         if acc_v then
            gap_r <= 2;
         end if;

         -- 100 ms between two bytes of a packet drop it, silently.
         if acc_v or not (rx_st = RX_ESC_ST or rx_st = RX_PAY_ST or rx_st = RX_CC1_ST or
                          rx_st = RX_CC2_ST) then
            tmo_r <= 0;
         elsif tmo_r = G_TIMEOUT - 1 then
            tmo_r <= 0;
            rx_st <= RX_IDLE_ST;
         else
            tmo_r <= tmo_r + 1;
         end if;

         case rx_st is

            when RX_IDLE_ST =>
               if acc_v then
                  if b_v = C_ESC then
                     rx_st <= RX_ESC_ST;
                  else
                     forward(b_v);
                  end if;
               end if;

            when RX_ESC_ST =>
               if acc_v then
                  rx_st <= RX_IDLE_ST;
                  if b_v = C_ESC then
                     forward(C_ESC);
                  elsif is_letter(b_v) then
                     tag_r  <= b_v;
                     sum_r  <= b_v;
                     dig_r  <= 0;
                     nib_r  <= 0;
                     wcnt_r <= 0;
                     bad_r  <= '0';
                     err02_r <= '0';
                     if busy_v then
                        rx_st <= RX_HOLD_ST;
                     else
                        rx_st <= RX_PAY_ST;
                     end if;
                  end if;
               end if;

            -- The tag waits for the answer to the last request, and for a clear.
            when RX_HOLD_ST =>
               if not busy_v then
                  rx_st <= RX_PAY_ST;
               end if;

            when RX_PAY_ST =>
               if acc_v then
                  if b_v = C_ESC then
                     rx_st <= RX_ESC_ST;
                  elsif b_v = X"23" then
                     rx_st <= RX_CC1_ST;
                  else
                     sum_r <= sum_r + b_v;
                     if tag_r = X"52" or tag_r = X"57" then
                        if dig_r < 2 ** 20 then
                           dig_r <= dig_r + 1;
                        end if;
                        if not is_hex(b_v) then
                           bad_r <= '1';
                        else
                           h_v := hex_of(b_v);
                           if dig_r < 8 then
                              req_addr_r <= req_addr_r(27 downto 0) & h_v;
                           elsif dig_r < 12 then
                              n_v := req_n_r(11 downto 0) & h_v;
                              req_n_r <= n_v;
                              if dig_r = 11 then
                                 cur_addr_r <= req_addr_r;
                                 -- The error 02 is decided here, before any data word.
                                 if bad_r = '0' and hold_r = '0' and halted_r = '0' and
                                    pause_own = '0' and non_dbg(req_addr_r, n_v) then
                                    err02_r <= '1';
                                 end if;
                                 if bad_r = '0' and tag_r = X"57" and wraps(req_addr_r, n_v) then
                                    err02_r <= '1';
                                 end if;
                              end if;
                           elsif tag_r = X"57" then
                              word_r <= word_r(27 downto 0) & h_v;
                              if nib_r = 7 then
                                 nib_r <= 0;
                                 if wcnt_r < 2 ** 17 then
                                    wcnt_r <= wcnt_r + 1;
                                 end if;
                                 -- Only the first N words are written.
                                 if bad_r = '0' and err02_r = '0' and
                                    wcnt_r < to_integer(req_n_r) then
                                    rx_go_r <= '1';
                                    rx_st   <= RX_CALL_ST;
                                 end if;
                              else
                                 nib_r <= nib_r + 1;
                              end if;
                           end if;
                        end if;
                     end if;
                  end if;
               end if;

            when RX_CC1_ST =>
               if acc_v then
                  if b_v = C_ESC then
                     rx_st <= RX_ESC_ST;
                  elsif is_hex(b_v) then
                     cc_hi_r <= hex_of(b_v);
                     rx_st   <= RX_CC2_ST;
                  else
                     rx_st <= RX_IDLE_ST;
                  end if;
               end if;

            when RX_CC2_ST =>
               if acc_v then
                  rx_st <= RX_IDLE_ST;
                  if b_v = C_ESC then
                     rx_st <= RX_ESC_ST;
                  elsif is_hex(b_v) and (cc_hi_r & hex_of(b_v)) = sum_r then
                     -- A good packet. Its error is the first one that applies.
                     code_v := X"00";
                     if tag_r /= X"52" and tag_r /= X"57" then
                        code_v := X"01";
                     elsif err02_r = '1' then
                        code_v := X"02";
                     elsif bad_r = '1' then
                        code_v := X"03";
                     elsif tag_r = X"52" and dig_r /= 12 then
                        code_v := X"03";
                     elsif tag_r = X"57" and
                           not (dig_r >= 12 and nib_r = 0 and wcnt_r = to_integer(req_n_r)) then
                        code_v := X"03";
                     end if;
                     ans_tag_r  <= tag_r;
                     ans_code_r <= code_v;
                     if code_v /= X"00" then
                        ans_kind_r <= PKT_E;
                     elsif tag_r = X"52" then
                        ans_kind_r <= PKT_R;
                     else
                        ans_kind_r <= PKT_K;
                     end if;
                     ans_req_tgl <= not ans_req_tgl;
                  end if;
               end if;

            -- The write of a data word: one cycle to start, then wait.
            when RX_CALL_ST =>
               rx_go_r <= '0';
               rx_st   <= RX_WAIT_ST;

            when RX_WAIT_ST =>
               if acc_done_r = '1' then
                  cur_addr_r <= cur_addr_r + 1;
                  rx_st      <= RX_PAY_ST;
               end if;

         end case;

         if rst_i = '1' then
            rx_st       <= RX_IDLE_ST;
            gap_r       <= 0;
            tmo_r       <= 0;
            rx_go_r     <= '0';
            o_armed_r   <= '1';
            ans_req_tgl <= '0';
            o_req_tgl   <= '0';
            con_in_valid_o <= '0';
         end if;
      end if;
   end process p_rx;


   ---------------------------------------------------------------------------
   -- One word access: the debug registers, or the Wishbone master
   ---------------------------------------------------------------------------

   -- The reads of the answer have priority, as p_rx is then not writing.
   acc_go   <= rx_go_r or tx_go_r;
   acc_we   <= not tx_go_r;
   acc_addr <= tx_addr_r when tx_go_r = '1' else
               cur_addr_r;

   hold_o     <= hold_r;
   eoi_o      <= eoi_r;
   pause_o    <= pause_r;
   pause_own  <= paused_r and pause_r and not stepping_r;
   clear_o    <= clearing_r;
   rom_hide_o <= hide_r when G_HAS_ROM else
                 '1';

   wb_cyc_o  <= wb_cyc_r;
   wb_stb_o  <= wb_stb_r;
   wb_we_o   <= wb_we_r;
   wb_addr_o <= wb_addr_r;
   wb_data_o <= wb_data_r;


   p_acc : process (clk_i)
      variable nh_v  : std_logic;
      variable rd_v  : t_word;
      variable idx_v : natural range 0 to 31;
   begin
      if rising_edge(clk_i) then
         nh_v := hold_r;

         -- What the core left at a halt stays until the next start.
         if halted_i = '1' and hold_r = '0' then
            halted_r <= '1';
            reason_r <= halt_reason_i;
            regs_r   <= regs_i;
         end if;

         -- The registers at a pause stay through a hold, as those of a halt.
         -- The flag follows the core a cycle later, so that regs_r is valid
         -- when it rises.
         if paused_i = '1' and hold_r = '0' then
            paused_r <= '1';
            regs_r   <= regs_i;
         else
            paused_r <= '0';
         end if;

         -- A step: pause_r was low for this cycle, and is high again. The
         -- step ends when the core has dropped paused_i and then raised
         -- paused_i or halted_i. A hold ends it as well.
         if step_r = '1' then
            step_r  <= '0';
            pause_r <= '1';
         end if;
         if stepping_r = '1' and step_r = '0' then
            if paused_i = '0' then
               fell_r <= '1';
            elsif fell_r = '1' then
               stepping_r <= '0';
            end if;
            if halted_i = '1' and fell_r = '1' then
               stepping_r <= '0';
            end if;
         end if;

         if rx_break_i = '1' then
            eoi_r <= '1';
         end if;

         -- The end of a clear
         if clearing_r = '1' and clear_done_i = '1' then
            clearing_r <= '0';
            nh_v       := clr_hold_r;
         end if;

         case acc_st is

            when ACC_IDLE_ST =>
               if acc_go = '1' then
                  acc_done_r <= '0';
                  if acc_addr(31 downto 5) = (31 downto 5 => '1') then
                     idx_v := to_integer(acc_addr(4 downto 0));
                     acc_done_r <= '1';
                     if acc_we = '1' then
                        -- Only the control register takes a write, and not during a clear.
                        if idx_v = 16 and clearing_r = '0' then
                           nh_v    := word_r(0);
                           pause_r <= word_r(4);
                           -- Bit 5 steps a paused core, and does nothing otherwise.
                           if word_r(5) = '1' and word_r(4) = '1' and word_r(2) = '0' and
                              word_r(0) = '0' and pause_own = '1' then
                              pause_r    <= '0';
                              step_r     <= '1';
                              stepping_r <= '1';
                              fell_r     <= '0';
                           end if;
                           if G_HAS_ROM then
                              hide_r <= word_r(3);
                           end if;
                           if word_r(2) = '1' then
                              clearing_r <= '1';
                              clr_hold_r <= word_r(0);
                              nh_v       := '1';
                           end if;
                        end if;
                     else
                        rd_v := (others => '0');
                        if idx_v < 16 then
                           rd_v := regs_r(32 * idx_v + 31 downto 32 * idx_v);
                        elsif idx_v = 16 then
                           rd_v(0) := hold_r;
                           rd_v(1) := halted_r;
                           rd_v(3) := hide_r or not to_sl(G_HAS_ROM);
                           rd_v(4) := pause_own;
                        elsif idx_v = 17 then
                           rd_v(2 downto 0) := reason_r;
                        elsif idx_v = 18 then
                           rd_v := C_VERSION;
                        elsif idx_v = 19 then
                           rd_v(15 downto 0) := free_i;
                        end if;
                        acc_rdata_r <= rd_v;
                     end if;
                  else
                     wb_cyc_r  <= '1';
                     wb_stb_r  <= '1';
                     wb_we_r   <= acc_we;
                     wb_addr_r <= acc_addr;
                     wb_data_r <= word_r;
                     acc_st    <= ACC_REQ_ST;
                  end if;
               end if;

            when ACC_REQ_ST =>
               if wb_stall_i = '0' then
                  wb_stb_r <= '0';
                  acc_st   <= ACC_WAIT_ST;
               end if;

            when ACC_WAIT_ST =>
               if wb_ack_i = '1' then
                  acc_rdata_r <= wb_data_i;
                  wb_cyc_r    <= '0';
                  acc_done_r  <= '1';
                  acc_st      <= ACC_IDLE_ST;
               end if;

         end case;

         -- A start: the control register goes from held to running.
         if hold_r = '1' and nh_v = '0' then
            halted_r <= '0';
            reason_r <= "000";
            eoi_r    <= '0';
         end if;
         hold_r <= nh_v;
         if nh_v = '1' then
            stepping_r <= '0';
         end if;

         if rst_i = '1' then
            acc_st     <= ACC_IDLE_ST;
            acc_done_r <= '0';
            hold_r     <= to_sl(G_BOOT_HELD);
            halted_r   <= '0';
            pause_r    <= '0';
            paused_r   <= '0';
            step_r     <= '0';
            stepping_r <= '0';
            fell_r     <= '0';
            reason_r   <= "000";
            hide_r     <= '0';
            eoi_r      <= '0';
            clearing_r <= '0';
            wb_cyc_r   <= '0';
            wb_stb_r   <= '0';
         end if;
      end if;
   end process p_acc;


   ---------------------------------------------------------------------------
   -- Send: answers, notices, and console bytes
   ---------------------------------------------------------------------------

   tx_valid_o  <= out_valid_r;
   tx_data_o   <= out_data_r;
   con_ready_o <= '1' when tx_st = TX_IDLE_ST and out_valid_r = '0' and ans_p = '0' and
                           b_pend_r = '0' and o_p = '0' else
                  '0';


   p_tx : process (clk_i)
      variable val_v : t_word;
      variable nd_v  : natural range 0 to 9;

      -- One byte to the output register. A byte of the packet's sum counts.
      procedure put(b : t_byte; counted : boolean) is
      begin
         out_valid_r <= '1';
         out_data_r  <= b;
         if counted then
            tx_sum_r <= tx_sum_r + b;
         end if;
      end procedure put;

   begin
      if rising_edge(clk_i) then
         if out_valid_r = '1' and tx_ready_i = '1' then
            out_valid_r <= '0';
         end if;
         if halted_r = '0' then
            h_sent_r <= '0';
         end if;
         if pause_own = '0' then
            p_sent_r <= '0';
         end if;

         if tx_st = TX_CALL_ST then
            tx_go_r <= '0';
            tx_st   <= TX_WAIT_ST;
         elsif tx_st = TX_WAIT_ST then
            -- A word of an `r` answer
            if acc_done_r = '1' then
               sh_r      <= acc_rdata_r;
               ndig_r    <= 8;
               tx_addr_r <= tx_addr_r + 1;
               tx_cnt_r  <= tx_cnt_r - 1;
               tx_st     <= TX_DIG_ST;
            end if;
         elsif out_valid_r = '0' then
            case tx_st is

               when TX_IDLE_ST =>
                  tx_sum_r <= (others => '0');
                  fld_r    <= 0;
                  if ans_p = '1' then
                     kind_r    <= ans_kind_r;
                     tx_addr_r <= req_addr_r;
                     tx_cnt_r  <= req_n_r;
                     put(C_ESC, false);
                     tx_st <= TX_TAG_ST;
                  elsif b_pend_r = '1' then
                     kind_r   <= PKT_B;
                     b_pend_r <= '0';
                     put(C_ESC, false);
                     tx_st <= TX_TAG_ST;
                  elsif o_p = '1' then
                     kind_r    <= PKT_O;
                     o_ack_tgl <= o_req_tgl;
                     put(C_ESC, false);
                     tx_st <= TX_TAG_ST;
                  elsif con_valid_i = '1' then
                     -- A console byte of 0xFF goes as ESC ESC.
                     put(con_data_i, false);
                     if con_data_i = C_ESC then
                        tx_st <= TX_CON2_ST;
                     end if;
                  elsif halted_r = '1' and h_sent_r = '0' then
                     kind_r   <= PKT_H;
                     h_sent_r <= '1';
                     put(C_ESC, false);
                     tx_st <= TX_TAG_ST;
                  elsif pause_own = '1' and p_sent_r = '0' then
                     kind_r   <= PKT_P;
                     p_sent_r <= '1';
                     put(C_ESC, false);
                     tx_st <= TX_TAG_ST;
                  end if;

               when TX_CON2_ST =>
                  put(C_ESC, false);
                  tx_st <= TX_IDLE_ST;

               when TX_TAG_ST =>
                  put(kind_char(kind_r), true);
                  tx_st <= TX_FIELD_ST;

               -- The next field of the payload, from kind_r and fld_r
               when TX_FIELD_ST =>
                  val_v := (others => '0');
                  nd_v  := 0;
                  case kind_r is
                     when PKT_B =>
                        if fld_r = 0 then
                           val_v := C_VERSION;
                           nd_v  := 2;
                        end if;
                     when PKT_H =>
                        if fld_r = 0 then
                           val_v(2 downto 0) := reason_r;
                           nd_v := 2;
                        end if;
                     when PKT_O | PKT_P =>
                        null;
                     when PKT_K | PKT_R =>
                        if fld_r = 0 then
                           val_v := req_addr_r;
                           nd_v  := 8;
                        elsif fld_r = 1 then
                           val_v(15 downto 0) := req_n_r;
                           nd_v := 4;
                        elsif kind_r = PKT_R and tx_cnt_r /= X"0000" then
                           nd_v := 9;
                        end if;
                     when PKT_E =>
                        if fld_r = 0 then
                           val_v(7 downto 0) := ans_tag_r;
                           nd_v := 2;
                        elsif fld_r = 1 then
                           val_v(7 downto 0) := ans_code_r;
                           nd_v := 2;
                        end if;
                  end case;
                  if nd_v = 9 then
                     -- The next word of an `r` answer comes from the memory.
                     tx_go_r <= '1';
                     tx_st   <= TX_CALL_ST;
                  elsif nd_v = 0 then
                     tx_st <= TX_HASH_ST;
                  else
                     sh_r   <= val_v sll (32 - 4 * nd_v);
                     ndig_r <= nd_v;
                     tx_st  <= TX_DIG_ST;
                  end if;

               when TX_DIG_ST =>
                  put(hex_char(sh_r(31 downto 28)), true);
                  sh_r <= sh_r(27 downto 0) & "0000";
                  if ndig_r = 1 then
                     tx_st <= TX_FIELD_ST;
                     if fld_r < 2 then
                        fld_r <= fld_r + 1;
                     end if;
                  else
                     ndig_r <= ndig_r - 1;
                  end if;

               when TX_HASH_ST =>
                  put(X"23", false);
                  tx_st <= TX_CC1_ST;

               when TX_CC1_ST =>
                  put(hex_char(tx_sum_r(7 downto 4)), false);
                  tx_st <= TX_CC2_ST;

               when TX_CC2_ST =>
                  put(hex_char(tx_sum_r(3 downto 0)), false);
                  tx_st <= TX_IDLE_ST;
                  if kind_r = PKT_K or kind_r = PKT_E or kind_r = PKT_R then
                     ans_ack_tgl <= ans_req_tgl;
                  end if;

               when others =>
                  null;

            end case;
         end if;

         if rst_i = '1' then
            tx_st       <= TX_IDLE_ST;
            out_valid_r <= '0';
            tx_go_r     <= '0';
            b_pend_r    <= '1';
            h_sent_r    <= '0';
            p_sent_r    <= '0';
            ans_ack_tgl <= '0';
            o_ack_tgl   <= '0';
         end if;
      end if;
   end process p_tx;

   gen_formal : if G_FORMAL generate
      type t_out_st is (OUT_IDLE_ST, OUT_ESC_ST, OUT_PAY_ST, OUT_CC1_ST, OUT_CC2_ST);

      -- The framing of the output, from the bytes that the host took
      signal f_out_st  : t_out_st                     := OUT_IDLE_ST;
      signal f_out_sum : t_byte                       := (others => '0');
      signal f_out_hi  : std_logic_vector(3 downto 0) := (others => '0');
      signal f_bad     : std_logic                    := '0';

      signal f_take   : std_logic;                     -- The host takes a byte
      signal f_tag    : std_logic;                     -- The byte out is a tag
      signal f_ctrl   : std_logic;                     -- A write of the control register
      signal f_answer : boolean;                       -- p_tx sends an answer
      signal f_ans    : boolean;                       -- An answer is due
      signal f_past   : boolean;                       -- p_rx is past the tag of a packet
      signal f_data   : boolean;                       -- p_rx is past A and N of a good W
      signal f_got    : boolean;                       -- p_rx is past A and N of a good R
      signal f_mem    : boolean;                       -- The link may reach the memory
      signal f_cur    : t_word;                        -- The word p_rx writes next
      signal f_end    : std_logic_vector(32 downto 0); -- A + N of the request
      signal f_tx_end : std_logic_vector(32 downto 0); -- The same, from p_tx
      signal f_step_d : std_logic := '0';              -- A step cycle without a reset, a cycle ago

      function f_is_digit(b : t_byte) return boolean is
      begin
         return (b >= X"30" and b <= X"39") or (b >= X"41" and b <= X"46");
      end function f_is_digit;

      function f_digit(b : t_byte) return std_logic_vector is
      begin
         if b <= X"39" then
            return b(3 downto 0);
         end if;
         return b(3 downto 0) + 9;
      end function f_digit;

      function f_dbg(a : t_word) return boolean is
      begin
         return a(31 downto 5) = (31 downto 5 => '1');
      end function f_dbg;

   begin

      f_take <= out_valid_r and tx_ready_i;

      p_f_step : process (clk_i)
      begin
         if rising_edge(clk_i) then
            f_step_d <= step_r and not rst_i;
         end if;
      end process p_f_step;

      f_tag  <= '1' when f_out_st = OUT_ESC_ST and out_valid_r = '1' and out_data_r /= C_ESC else
                '0';
      f_ctrl <= '1' when acc_st = ACC_IDLE_ST and acc_go = '1' and acc_we = '1' and
                         acc_addr = X"FFFFFFF0" else
                '0';

      f_answer <= tx_st /= TX_IDLE_ST and tx_st /= TX_CON2_ST and
                  (kind_r = PKT_K or kind_r = PKT_E or kind_r = PKT_R);
      f_ans    <= ans_req_tgl /= ans_ack_tgl;
      f_past   <= rx_st = RX_PAY_ST or rx_st = RX_CC1_ST or rx_st = RX_CC2_ST or
                  rx_st = RX_CALL_ST or rx_st = RX_WAIT_ST;
      f_data   <= tag_r = X"57" and dig_r >= 12 and bad_r = '0' and err02_r = '0' and f_past;
      f_got    <= tag_r = X"52" and dig_r >= 12 and bad_r = '0' and err02_r = '0' and
                  (rx_st = RX_PAY_ST or rx_st = RX_CC1_ST or rx_st = RX_CC2_ST);
      f_mem    <= (hold_r = '1' or halted_r = '1' or pause_own = '1') and clearing_r = '0';
      f_end    <= ('0' & req_addr_r) + req_n_r;
      f_tx_end <= ('0' & tx_addr_r) + tx_cnt_r;
      f_cur    <= req_addr_r + wcnt_r - 1 when rx_st = RX_CALL_ST or rx_st = RX_WAIT_ST else
                  req_addr_r + wcnt_r when wcnt_r <= to_integer(req_n_r) else
                  req_addr_r + req_n_r;


      -- Parses the bytes that the host takes, as DEBUG.md §1 and §2 frame
      -- them. f_bad is a byte out of place, a bad tag, or a bad checksum.
      p_out : process (clk_i)
      begin
         if rising_edge(clk_i) then
            f_bad <= '0';
            if f_take = '1' then
               case f_out_st is

                  when OUT_IDLE_ST =>
                     if out_data_r = C_ESC then
                        f_out_st <= OUT_ESC_ST;
                     end if;

                  when OUT_ESC_ST =>
                     if out_data_r = C_ESC then
                        f_out_st <= OUT_IDLE_ST;
                     elsif out_data_r = X"62" or out_data_r = X"68" or out_data_r = X"6F" or
                           out_data_r = X"6B" or out_data_r = X"65" or out_data_r = X"72" or
                           out_data_r = X"70" then
                        f_out_sum <= out_data_r;
                        f_out_st  <= OUT_PAY_ST;
                     else
                        f_bad <= '1';
                     end if;

                  when OUT_PAY_ST =>
                     if out_data_r = X"23" then
                        f_out_st <= OUT_CC1_ST;
                     elsif f_is_digit(out_data_r) then
                        f_out_sum <= f_out_sum + out_data_r;
                     else
                        f_bad <= '1';
                     end if;

                  when OUT_CC1_ST =>
                     f_out_hi <= f_digit(out_data_r);
                     f_out_st <= OUT_CC2_ST;
                     if not f_is_digit(out_data_r) then
                        f_bad <= '1';
                     end if;

                  when OUT_CC2_ST =>
                     f_out_st <= OUT_IDLE_ST;
                     if not f_is_digit(out_data_r) or
                        (f_out_hi & f_digit(out_data_r)) /= f_out_sum then
                        f_bad <= '1';
                     end if;

               end case;
            end if;

            if rst_i = '1' then
               f_out_st <= OUT_IDLE_ST;
               f_bad    <= '0';
            end if;
         end if;
      end process p_out;


      -- psl default clock is rising_edge(clk_i);

      -- The output: every packet is whole, with a known tag, upper-case hex
      -- digits, `#`, and its checksum. A console byte goes out only between
      -- packets, so nothing comes between the bytes of a packet, and no
      -- answer starts during a clear.
      -- psl f_framing : assert always f_bad = '0';
      -- psl f_con_between : assert always
      --    con_ready_o = '1' -> (f_out_st = OUT_IDLE_ST and out_valid_r = '0');
      -- psl f_clear_answer : assert always
      --    (f_tag = '1' and (out_data_r = X"6B" or out_data_r = X"65" or out_data_r = X"72")) ->
      --    clearing_r = '0';

      -- The receiver waits 2 cycles after a byte, 1 cycle to start the write
      -- of a data word, and then only for a Wishbone access, or with a tag
      -- for the answer to the last request or for a clear.
      -- psl f_ready : assert always
      --    rx_rdy = '0' -> (gap_r /= 0 or rx_st = RX_HOLD_ST or rx_st = RX_CALL_ST or
      --                     (rx_st = RX_WAIT_ST and (acc_done_r = '1' or wb_cyc_r = '1')));
      -- psl f_ready_clear : assert always
      --    clearing_r = '1' -> not (rx_st = RX_WAIT_ST and acc_done_r = '0');
      -- psl f_call : assert always
      --    {rx_st = RX_CALL_ST and rst_i = '0'} |=> {rst_i = '1' or rx_st = RX_WAIT_ST};

      -- psl f_hold : assert always
      --    {rst_i = '0' and f_ctrl = '0' and step_r = '0' and
      --     not (clearing_r = '1' and clear_done_i = '1')} |=>
      --    {stable(hold_r) and stable(hide_r) and stable(pause_r)};

      -- A step (DEBUG.md §6) lowers pause_r for exactly one cycle, only after
      -- a cycle in which the link owned the paused core, and the link does
      -- not own the memory from the write until the step has ended.
      -- psl f_step_pulse : assert always
      --    step_r = '1' -> (pause_r = '0' and stepping_r = '1' and hold_r = '0');
      -- A sequence here would have a cover that needs a whole W, deeper than the cover
      -- task looks.
      -- psl f_step_once : assert always f_step_d = '1' -> (pause_r = '1' and step_r = '0');
      -- psl f_step_paused : assert always {pause_own = '0'} |=> {step_r = '0'};
      -- psl f_step_own : assert always stepping_r = '1' -> pause_own = '0';

      -- The invariants of the proof. Each state is one of its values.
      -- psl i_acc_st : assert always
      --    acc_st = ACC_IDLE_ST or acc_st = ACC_REQ_ST or acc_st = ACC_WAIT_ST;
      -- psl i_tx_st : assert always
      --    tx_st = TX_IDLE_ST or tx_st = TX_CON2_ST or tx_st = TX_TAG_ST or tx_st = TX_FIELD_ST or
      --    tx_st = TX_CALL_ST or tx_st = TX_WAIT_ST or tx_st = TX_DIG_ST or tx_st = TX_HASH_ST or
      --    tx_st = TX_CC1_ST or tx_st = TX_CC2_ST;
      -- psl i_kind : assert always
      --    (kind_r = PKT_B or kind_r = PKT_H or kind_r = PKT_O or kind_r = PKT_K or
      --     kind_r = PKT_E or kind_r = PKT_R or kind_r = PKT_P) and
      --    (ans_kind_r = PKT_K or ans_kind_r = PKT_E or ans_kind_r = PKT_R);
      -- psl i_out_st : assert always
      --    f_out_st = OUT_IDLE_ST or f_out_st = OUT_ESC_ST or f_out_st = OUT_PAY_ST or
      --    f_out_st = OUT_CC1_ST or f_out_st = OUT_CC2_ST;

      -- A halt that p_acc keeps is still the
      -- core's while the processor runs, by the assumption of contract e.
      -- psl i_halted : assert always (halted_r = '1' and hold_r = '0') -> halted_i = '1';
      -- psl i_strobe : assert always con_in_valid_o = '1' -> gap_r = 2;
      -- psl i_clear : assert always clearing_r = '1' -> hold_r = '1';

      -- p_acc: one access at a time, for p_rx's write or p_tx's read.
      -- psl i_acc_idle : assert always
      --    acc_st = ACC_IDLE_ST -> (wb_cyc_r = '0' and wb_stb_r = '0');
      -- psl i_acc_req : assert always
      --    acc_st = ACC_REQ_ST -> (wb_cyc_r = '1' and wb_stb_r = '1');
      -- psl i_acc_wait : assert always
      --    acc_st = ACC_WAIT_ST -> (wb_cyc_r = '1' and wb_stb_r = '0');
      -- psl i_acc_busy : assert always
      --    acc_st /= ACC_IDLE_ST ->
      --    (acc_done_r = '0' and f_mem and not f_dbg(wb_addr_r) and
      --     ((rx_st = RX_WAIT_ST and wb_we_r = '1' and wb_addr_r = cur_addr_r) or
      --      (tx_st = TX_WAIT_ST and wb_we_r = '0' and wb_addr_r = tx_addr_r)));
      -- psl i_acc_done : assert always
      --    ((rx_st = RX_WAIT_ST or tx_st = TX_WAIT_ST) and acc_st = ACC_IDLE_ST) ->
      --    acc_done_r = '1';
      -- psl i_rx_go : assert always (rx_go_r = '1') = (rx_st = RX_CALL_ST);
      -- psl i_tx_go : assert always (tx_go_r = '1') = (tx_st = TX_CALL_ST);
      -- psl i_calls : assert always
      --    (rx_st = RX_CALL_ST or tx_st = TX_CALL_ST) -> acc_st = ACC_IDLE_ST;

      -- p_rx: a packet is past its tag only while no answer is due. The
      -- words of a good W follow A without a wrap, and reach the memory only
      -- while the link may.
      -- psl i_rx_ans : assert always f_past -> not f_ans;
      -- psl i_rx_hold : assert always
      --    rx_st = RX_HOLD_ST ->
      --    (dig_r = 0 and nib_r = 0 and wcnt_r = 0 and bad_r = '0' and err02_r = '0');
      -- psl i_rx_head : assert always dig_r <= 12 -> (wcnt_r = 0 and nib_r = 0);
      -- psl i_rx_call : assert always
      --    (rx_st = RX_CALL_ST or rx_st = RX_WAIT_ST) ->
      --    (f_data and wcnt_r >= 1 and wcnt_r <= to_integer(req_n_r));
      -- psl i_rx_wrap : assert always f_data -> f_end(32) = '0' or f_end = '1' & X"00000000";
      -- psl i_rx_cur : assert always f_data -> cur_addr_r = f_cur;
      -- psl i_rx_mem : assert always
      --    (f_data and not f_dbg(cur_addr_r) and
      --     (rx_st = RX_CALL_ST or rx_st = RX_WAIT_ST or wcnt_r < to_integer(req_n_r))) -> f_mem;
      -- psl i_rx_clear : assert always
      --    (clearing_r = '1' and f_past) ->
      --    (tag_r = X"57" and dig_r >= 12 and err02_r = '0' and
      --     (cur_addr_r >= X"FFFFFFF0" or
      --      (rx_st /= RX_CALL_ST and rx_st /= RX_WAIT_ST and wcnt_r >= to_integer(req_n_r))) and
      --     (bad_r = '1' or f_end(32) = '0' or f_end = '1' & X"00000000"));
      -- psl i_rx_read : assert always
      --    f_got ->
      --    (hold_r = '1' or halted_r = '1' or pause_own = '1' or not non_dbg(req_addr_r, req_n_r));

      -- p_tx: an answer is sent only while it is due, and an `r` reads the
      -- words from A on, only where the link may.
      -- psl i_tx_ans : assert always
      --    f_answer -> (f_ans and clearing_r = '0' and kind_r = ans_kind_r);
      -- psl i_ans_clear : assert always (f_ans and clearing_r = '1') -> ans_kind_r /= PKT_R;
      -- psl i_ans_read : assert always
      --    (f_ans and ans_kind_r = PKT_R) ->
      --    (hold_r = '1' or halted_r = '1' or pause_own = '1' or not non_dbg(req_addr_r, req_n_r));
      -- psl i_tx_call : assert always
      --    (tx_st = TX_CALL_ST or tx_st = TX_WAIT_ST) ->
      --    (kind_r = PKT_R and tx_cnt_r /= X"0000" and (f_mem or f_dbg(tx_addr_r)));
      -- psl i_tx_addr : assert always
      --    (f_answer and kind_r = PKT_R and tx_st /= TX_TAG_ST) ->
      --    (tx_cnt_r <= req_n_r and f_tx_end(31 downto 0) = f_end(31 downto 0));
      -- psl i_tx_tag : assert always
      --    (f_answer and tx_st = TX_TAG_ST) -> (tx_addr_r = req_addr_r and tx_cnt_r = req_n_r);

      -- p_tx and the parser agree on the bytes sent so far.
      -- psl i_out_idle : assert always
      --    (tx_st = TX_IDLE_ST and out_valid_r = '0') -> f_out_st = OUT_IDLE_ST;
      -- psl i_out_last : assert always
      --    (tx_st = TX_IDLE_ST and out_valid_r = '1') ->
      --    ((f_out_st = OUT_IDLE_ST and out_data_r /= C_ESC) or
      --     (f_out_st = OUT_ESC_ST and out_data_r = C_ESC) or
      --     (f_out_st = OUT_CC2_ST and f_out_hi = f_out_sum(7 downto 4) and
      --      out_data_r = hex_char(f_out_sum(3 downto 0))));
      -- psl i_out_con2 : assert always
      --    tx_st = TX_CON2_ST ->
      --    ((out_valid_r = '1' and out_data_r = C_ESC and f_out_st = OUT_IDLE_ST) or
      --     (out_valid_r = '0' and f_out_st = OUT_ESC_ST));
      -- psl i_out_tag : assert always
      --    tx_st = TX_TAG_ST ->
      --    ((out_valid_r = '1' and out_data_r = C_ESC and f_out_st = OUT_IDLE_ST) or
      --     (out_valid_r = '0' and f_out_st = OUT_ESC_ST)) and tx_sum_r = X"00";
      -- psl i_out_pay : assert always
      --    (tx_st = TX_FIELD_ST or tx_st = TX_DIG_ST or tx_st = TX_HASH_ST or
      --     tx_st = TX_CALL_ST or tx_st = TX_WAIT_ST) ->
      --    ((out_valid_r = '1' and f_out_st = OUT_ESC_ST and out_data_r = kind_char(kind_r) and
      --      tx_sum_r = out_data_r) or
      --     (out_valid_r = '1' and f_out_st = OUT_PAY_ST and f_is_digit(out_data_r) and
      --      tx_sum_r = f_out_sum + out_data_r) or
      --     (out_valid_r = '0' and f_out_st = OUT_PAY_ST and tx_sum_r = f_out_sum));
      -- psl i_out_cc1 : assert always
      --    tx_st = TX_CC1_ST ->
      --    ((out_valid_r = '1' and out_data_r = X"23" and f_out_st = OUT_PAY_ST) or
      --     (out_valid_r = '0' and f_out_st = OUT_CC1_ST)) and tx_sum_r = f_out_sum;
      -- psl i_out_cc2 : assert always
      --    tx_st = TX_CC2_ST ->
      --    ((out_valid_r = '1' and out_data_r = hex_char(tx_sum_r(7 downto 4)) and
      --      f_out_st = OUT_CC1_ST) or
      --     (out_valid_r = '0' and f_out_st = OUT_CC2_ST and f_out_hi = tx_sum_r(7 downto 4))) and
      --    tx_sum_r = f_out_sum;
      -- psl i_dig : assert always tx_st = TX_DIG_ST -> ndig_r >= 1;

      -- psl c_halt : cover {f_tag = '1' and out_data_r = X"68"};
      -- psl c_overflow : cover {f_tag = '1' and out_data_r = X"6F"};

   end generate gen_formal;

end architecture synthesis;
