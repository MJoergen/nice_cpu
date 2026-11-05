-- The port for Ethernet frames of SYSTEM.md §7: 16 words of I/O, a queue
-- of 4 frames received, a send buffer, and a port to the station, which
-- writes the frames received and reads the frame to send.
--
--   0  ETH_CSR      2  ETH_TX_LEN   4  ETH_DROPPED   8-15  ETH_BUF0-7
--   1  ETH_RX_LEN   3  ETH_CHUNK    5-7  read 0
--
-- THEORY OF OPERATION
-- The queue is a RAM of 4 slots of 512 words, a frame in each slot as
-- the program reads it: big-endian, from byte 2. The head is the slot
-- that ETH_RX_LEN and the window show, and a frame enters at the tail,
-- head + count. The station writes a frame in three steps: rx_start_i
-- when it begins, rx_we_i with rx_addr_i and rx_data_i for each word, and
-- rx_done_i with rx_len_i when the frame is whole and good. At rx_start_i
-- the port takes the frame if it is enabled and the queue has room; if it
-- is enabled and the queue is full, it drops the frame and counts it.
-- The words of a frame it does not take, and its rx_done_i, are ignored.
-- So the station need not know whether the program wants frames. The
-- frame becomes the queue's at rx_done_i, so ETH_RX_LEN never shows a
-- frame half written. Bits 31..16 of word 0 are written as 0, the
-- bytes before the frame.
--
-- The send buffer is a RAM of 512 words, of which a program reaches 384.
-- A write of 14 to 1514 to ETH_TX_LEN while enabled and not busy raises
-- tx_start_o for a cycle, with the length on tx_len_o, which holds until
-- tx_done_i. The station reads the buffer with tx_addr_i, the word on
-- tx_data_o a cycle later, adds the FCS, pads the frame, and ends it with
-- tx_done_i. While busy, the bus's writes to the buffer are ignored, so
-- the frame does not change while it is sent.
--
-- busy_o is high while a frame is sent, as busy reads, for an activity
-- light.
--
-- With G_FORMAL, the invariants that tie busy and the held ACKs to the
-- station's port are proven too, for formal/formal_eth_regs.vhd.
--
-- The port is a pipelined Wishbone slave. It acknowledges each request in
-- the cycle after it accepts it. With G_HOLD_ACK, the write of ETH_CSR
-- that sets "enabled" from 0 to 1 is acknowledged in the cycle after
-- enable_done_i, and a write of ETH_TX_LEN that sends a frame in the cycle
-- after tx_done_i, and STALL is high until then. enable_o is high for a
-- cycle after such a write of ETH_CSR. So the simulation's station, which
-- gives the frames of a file at those writes (SYSTEM.md §7, the
-- emulator), has written them before the program reads again, and the
-- program runs as in the emulator. A board does not set G_HOLD_ACK.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) The master holds STB and the request while STALL is high.
-- b) STB is high only for requests to this unit: the bus decoder decodes
--    the address bits above bit 3.
-- c) The station's frames do not overlap: each rx_start_i is followed by
--    its words and at most one rx_done_i, before the next rx_start_i.
--    rx_len_i is 14 to 1514, and rx_addr_i is below 384.
-- d) The station raises tx_done_i once for each tx_start_o, in a cycle
--    after it. With G_HOLD_ACK, it raises enable_done_i once for each
--    enable_o, in a cycle after it, and rst_i is not raised while STALL
--    is high, as the simulation resets only at the start.
--
-- RESET
-- Synchronous, the reset that a start of the processor gives (SYSTEM.md
-- §7): "enabled" is 0, the queue is empty, ETH_DROPPED and ETH_CHUNK are
-- 0, a frame being written is not taken, and any ACK owed is dropped. A
-- frame being sent goes on until tx_done_i, and a write of ETH_TX_LEN in
-- the cycle of reset sends nothing. The send buffer keeps its contents.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

entity eth_regs is
   generic (
      -- Hold the ACK of a write that enables or sends until it is served
      G_HOLD_ACK : boolean := false;
      -- The properties of formal/formal_eth_regs.vhd that name the
      -- registers here
      G_FORMAL   : boolean := false
   );
   port (
      clk_i         : in  std_logic;
      rst_i         : in  std_logic;

      wb_cyc_i      : in  std_logic;
      wb_stb_i      : in  std_logic;
      wb_stall_o    : out std_logic;
      wb_ack_o      : out std_logic                     := '0';
      wb_we_i       : in  std_logic;
      wb_addr_i     : in  std_logic_vector(3 downto 0);
      wb_data_i     : in  std_logic_vector(31 downto 0);
      wb_data_o     : out std_logic_vector(31 downto 0);

      -- "Enabled", and its rise by a write
      enabled_o     : out std_logic;
      enable_o      : out std_logic                     := '0';
      enable_done_i : in  std_logic;

      -- The station writes a frame received
      rx_start_i    : in  std_logic;
      rx_we_i       : in  std_logic;
      rx_addr_i     : in  std_logic_vector(8 downto 0);
      rx_data_i     : in  std_logic_vector(31 downto 0);
      rx_done_i     : in  std_logic;
      rx_len_i      : in  std_logic_vector(10 downto 0);

      -- The station sends the frame in the send buffer
      tx_start_o    : out std_logic                     := '0';
      busy_o        : out std_logic;
      tx_len_o      : out std_logic_vector(10 downto 0);
      tx_addr_i     : in  std_logic_vector(8 downto 0);
      tx_data_o     : out std_logic_vector(31 downto 0) := (others => '0');
      tx_done_i     : in  std_logic
   );
end entity eth_regs;

architecture synthesis of eth_regs is

   constant C_CHUNKS : natural := 48;

   type t_ram is array (natural range <>) of std_logic_vector(31 downto 0);
   type t_lens is array (0 to 3) of std_logic_vector(10 downto 0);

   signal rx_ram : t_ram(0 to 2047) := (others => (others => '0'));
   signal tx_ram : t_ram(0 to 511)  := (others => (others => '0'));

   signal enabled_r : std_logic                     := '0';
   signal head_r    : std_logic_vector(1 downto 0)  := (others => '0');
   signal count_r   : std_logic_vector(2 downto 0)  := (others => '0');
   signal lens_r    : t_lens                        := (others => (others => '0'));
   signal dropped_r : std_logic_vector(31 downto 0) := (others => '0');
   signal chunk_r   : std_logic_vector(5 downto 0)  := (others => '0');
   signal sel_r     : std_logic                     := '0';
   signal take_r    : std_logic                     := '0';
   signal busy_r    : std_logic                     := '0';
   signal len_r     : std_logic_vector(10 downto 0) := (others => '0');
   -- The held ACK of a write that enabled, or of one that sent
   signal hold_en_r : std_logic                     := '0';
   signal hold_tx_r : std_logic                     := '0';

   -- The read data of a register, or of a buffer, and which
   signal rdata_r   : std_logic_vector(31 downto 0) := (others => '0');
   signal rd_buf_r  : std_logic                     := '0';
   signal rd_tx_r   : std_logic                     := '0';
   signal rd_zero_r : std_logic                    := '0';
   signal rx_q      : std_logic_vector(31 downto 0) := (others => '0');
   signal tx_q      : std_logic_vector(31 downto 0) := (others => '0');

   signal hold     : std_logic;
   signal accept   : std_logic;
   signal buf_word : std_logic_vector(8 downto 0);
   signal tail     : std_logic_vector(1 downto 0);
   signal tx_we    : std_logic;

begin

   hold       <= hold_en_r or hold_tx_r;
   accept     <= wb_cyc_i and wb_stb_i and not hold;
   wb_stall_o <= hold;
   enabled_o  <= enabled_r;
   tx_len_o   <= len_r;
   busy_o     <= busy_r;

   -- The word of the window, as ETH_CHUNK and the address choose it
   buf_word <= chunk_r & wb_addr_i(2 downto 0);
   tail     <= head_r + count_r(1 downto 0);
   tx_we    <= accept and wb_we_i and wb_addr_i(3) and sel_r and not busy_r
               when chunk_r < C_CHUNKS else
               '0';

   wb_data_o <= rdata_r when rd_buf_r = '0' else
                (others => '0') when rd_zero_r = '1' else
                tx_q when rd_tx_r = '1' else
                rx_q;


   -- The queue: the bus reads the head's frame, the station writes the tail.
   p_rx_ram : process (clk_i)
      variable data_v : std_logic_vector(31 downto 0);
   begin
      if rising_edge(clk_i) then
         if rx_we_i = '1' and take_r = '1' then
            data_v := rx_data_i;
            if rx_addr_i = 0 then
               data_v(31 downto 16) := (others => '0');
            end if;
            rx_ram(to_integer(tail & rx_addr_i)) <= data_v;
         end if;
         rx_q <= rx_ram(to_integer(head_r & buf_word));
      end if;
   end process p_rx_ram;


   -- The send buffer: the bus reads and writes it, the station reads it.
   p_tx_ram : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if tx_we = '1' then
            tx_ram(to_integer(buf_word)) <= wb_data_i;
         end if;
         tx_q      <= tx_ram(to_integer(buf_word));
         tx_data_o <= tx_ram(to_integer(tx_addr_i));
      end if;
   end process p_tx_ram;


   p_regs : process (clk_i)
      variable count_v : std_logic_vector(2 downto 0);
      variable head_v  : std_logic_vector(1 downto 0);
      variable en_v    : std_logic;
   begin
      if rising_edge(clk_i) then
         wb_ack_o   <= accept;
         enable_o   <= '0';
         tx_start_o <= '0';
         count_v    := count_r;
         head_v     := head_r;
         en_v       := enabled_r;

         if accept = '1' and wb_we_i = '0' then
            rd_buf_r  <= wb_addr_i(3);
            rd_tx_r   <= sel_r;
            rd_zero_r <= '1' when chunk_r >= C_CHUNKS or (sel_r = '0' and count_r = 0) else
                         '0';
            case wb_addr_i is
               when X"0" =>
                  rdata_r    <= (others => '0');
                  rdata_r(0) <= enabled_r;
                  rdata_r(1) <= or count_r;
                  rdata_r(2) <= busy_r;

               when X"1" =>
                  rdata_r <= (others => '0');
                  if count_r /= 0 then
                     rdata_r(10 downto 0) <= lens_r(to_integer(head_r));
                  end if;

               when X"3" =>
                  rdata_r             <= (others => '0');
                  rdata_r(8)          <= sel_r;
                  rdata_r(5 downto 0) <= chunk_r;

               when X"4"   => rdata_r <= dropped_r;
               when others => rdata_r <= (others => '0');
            end case;
         end if;

         -- A frame that the station has written enters the queue.
         if rx_done_i = '1' and take_r = '1' then
            lens_r(to_integer(tail)) <= rx_len_i;
            count_v                  := count_v + 1;
            take_r                   <= '0';
         end if;

         if accept = '1' and wb_we_i = '1' then
            case wb_addr_i is
               when X"0" =>
                  if wb_data_i(0) = '1' then
                     if enabled_r = '0' then
                        en_v      := '1';
                        enabled_r <= '1';
                        enable_o  <= '1';
                        if G_HOLD_ACK then
                           hold_en_r <= '1';
                           wb_ack_o  <= '0';
                        end if;
                     end if;
                  else
                     en_v      := '0';
                     enabled_r <= '0';
                     count_v   := (others => '0');
                     head_v    := (others => '0');
                     dropped_r <= (others => '0');
                     take_r    <= '0';
                  end if;

               when X"1" =>
                  if count_r /= 0 then
                     head_v  := head_v + 1;
                     count_v := count_v - 1;
                  end if;

               when X"2" =>
                  if enabled_r = '1' and busy_r = '0' and
                     wb_data_i >= 14 and wb_data_i <= 1514 then
                     busy_r     <= '1';
                     tx_start_o <= '1';
                     len_r      <= wb_data_i(10 downto 0);
                     if G_HOLD_ACK then
                        hold_tx_r <= '1';
                        wb_ack_o  <= '0';
                     end if;
                  end if;

               when X"3" =>
                  chunk_r <= wb_data_i(5 downto 0);
                  sel_r   <= wb_data_i(8);

               when others =>
                  null;
            end case;
         end if;

         -- The station begins a frame: take it, or drop and count it, as
         -- the write of this cycle leaves "enabled" and the queue.
         if rx_start_i = '1' then
            take_r <= '0';
            if en_v = '1' then
               if count_v = 4 then
                  dropped_r <= dropped_r + 1;
               else
                  take_r <= '1';
               end if;
            end if;
         end if;

         count_r <= count_v;
         head_r  <= head_v;

         if busy_r = '1' and tx_done_i = '1' then
            busy_r <= '0';
         end if;

         if hold_en_r = '1' and enable_done_i = '1' then
            hold_en_r <= '0';
            wb_ack_o  <= '1';
         end if;
         if hold_tx_r = '1' and tx_done_i = '1' then
            hold_tx_r <= '0';
            wb_ack_o  <= '1';
         end if;

         if rst_i = '1' then
            wb_ack_o  <= '0';
            hold_en_r <= '0';
            hold_tx_r <= '0';
            enable_o  <= '0';
            enabled_r <= '0';
            head_r    <= (others => '0');
            count_r   <= (others => '0');
            dropped_r <= (others => '0');
            chunk_r   <= (others => '0');
            sel_r     <= '0';
            take_r    <= '0';
            -- A frame being sent goes on, but none starts.
            if busy_r = '0' then
               busy_r     <= '0';
               tx_start_o <= '0';
            end if;
         end if;
      end if;
   end process p_regs;


   gen_formal : if G_FORMAL generate
      -- A frame is sent, and an enable is served, from the station's view
      signal f_sending  : std_logic := '0';
      signal f_enabling : std_logic := '0';
   begin

      p_track : process (clk_i)
      begin
         if rising_edge(clk_i) then
            if tx_start_o = '1' then
               f_sending <= '1';
            elsif tx_done_i = '1' then
               f_sending <= '0';
            end if;
            if enable_o = '1' then
               f_enabling <= '1';
            elsif enable_done_i = '1' then
               f_enabling <= '0';
            end if;
         end if;
      end process p_track;

      -- psl default clock is rising_edge(clk_i);
      -- psl f_busy : assert always f_sending = (busy_r and not tx_start_o);
      -- psl f_count : assert always count_r <= 4;
      -- psl f_take : assert always take_r -> (count_r < 4 and enabled_r = '1');

      gen_hold : if G_HOLD_ACK generate
         -- psl f_enabler : assume always enable_done_i -> f_enabling;
         -- psl f_enabler_late : assume always enable_o -> not enable_done_i;
         -- psl f_one_enable : assert always enable_o -> not f_enabling;
         -- psl f_hold_one : assert always not (hold_en_r and hold_tx_r);
         -- psl f_hold_en : assert always hold_en_r = (enable_o or f_enabling);
         -- psl f_hold_tx : assert always hold_tx_r = busy_r;
      end generate gen_hold;

   end generate gen_formal;

end architecture synthesis;
