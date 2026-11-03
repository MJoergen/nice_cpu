-- The registers and the buffer of the SD card controller of SYSTEM.md §5:
-- 16 words of I/O, and a port to a protocol engine that talks to the card.
--
--   0  SD_CSR     2  SD_CHUNK   4  SD_SELECT  6  SD_SLOTS  8-15  SD_BUF0-7
--   1  SD_LBA     3  SD_ERROR   5  SD_LAST    7  reads 0
--
-- THEORY OF OPERATION
-- This unit holds everything a program sees, and makes every check of
-- SYSTEM.md §5 that needs no card: no card (error 1), not ready (2), out of
-- range (7), and write-protected (6), in that order. A command that passes
-- them goes to the engine, which does the protocol: start_o is high for
-- one cycle, with the command, the slot, and the sector on cmd_o, slot_o,
-- and lba_o, which stay as they are until done_i. The engine ends the
-- command with done_i high for one cycle, and error_i: 0, or 3, 4, 5, or
-- 8. Init's done_i also carries the card's last sector and type.
--
-- The buffer is 512 bytes in four byte lanes, lane j holding bits
-- 8j + 7..8j of the 128 words, so that byte 4n + j of the sector is lane j
-- of word n (SYSTEM.md §5). While the engine runs, the buffer is its own,
-- through buf_addr_i, buf_we_i, and buf_data_i, and buf_data_o, which
-- holds the byte of buf_addr_i of the cycle before. Otherwise it is the
-- bus's, through SD_BUF0-7 and SD_CHUNK. The two never share a cycle, as
-- the bus's writes to the buffer are ignored while busy, and its reads
-- then return what the engine's address selects, which SYSTEM.md §5 allows.
--
-- "Changed" is one bit per slot, set when present_i of the slot rises.
-- "Ready" is one bit for the controller: it falls when the selected slot
-- changes or shows no card, and only Init sets it.
--
-- The port is a pipelined Wishbone slave. It acknowledges each request in
-- the cycle after it accepts it, but with G_HOLD_ACK, a write to SD_CSR
-- that starts the engine is acknowledged in the cycle after done_i, and
-- STALL is high until then. So no access sees busy 1, and a program runs
-- as in the emulator, where a command ends in the write that starts it.
-- The simulation sets G_HOLD_ACK. A board does not, as an Init may take
-- hundreds of milliseconds.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) The master holds STB and the request while STALL is high.
-- b) STB is high only for requests to this unit: the bus decoder decodes
--    the address bits above bit 3.
-- c) The engine raises done_i once for each start_o, in a cycle after it,
--    and never after abort_o until the next start_o. Its buf_we_i is low
--    while no command runs. present_i and wp_i are the card detect and the
--    write protect switch of each slot, synchronous to clk_i.
--
-- RESET
-- Synchronous, as SYSTEM.md §5 says: a Write that runs goes on, and its
-- done_i reports nothing. Any other command is abandoned with abort_o.
-- Slot 0 is selected, SD_CHUNK, SD_LBA, and SD_ERROR are 0, "ready" is 0,
-- "changed" is set where a card is present, and any ACK owed is dropped.
-- The buffer keeps its contents.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

entity sd_regs is
   generic (
      -- The number of slots, SD_SLOTS
      G_SLOTS    : positive range 1 to 16 := 2;
      -- Hold the ACK of a write that starts a command until it ends
      G_HOLD_ACK : boolean                := false
   );
   port (
      clk_i      : in  std_logic;
      rst_i      : in  std_logic;

      wb_cyc_i   : in  std_logic;
      wb_stb_i   : in  std_logic;
      wb_stall_o : out std_logic;
      wb_ack_o   : out std_logic                            := '0';
      wb_we_i    : in  std_logic;
      wb_addr_i  : in  std_logic_vector(3 downto 0);
      wb_data_i  : in  std_logic_vector(31 downto 0);
      wb_data_o  : out std_logic_vector(31 downto 0);

      -- The cards
      present_i  : in  std_logic_vector(G_SLOTS - 1 downto 0);
      wp_i       : in  std_logic_vector(G_SLOTS - 1 downto 0);

      -- High while a command runs, as busy reads, for an activity light
      busy_o     : out std_logic;

      -- The engine: a command, and its end
      start_o    : out std_logic                            := '0';
      abort_o    : out std_logic                            := '0';
      cmd_o      : out std_logic_vector(1 downto 0);
      slot_o     : out std_logic_vector(3 downto 0);
      lba_o      : out std_logic_vector(31 downto 0);
      done_i     : in  std_logic;
      error_i    : in  std_logic_vector(3 downto 0);
      last_i     : in  std_logic_vector(31 downto 0);
      type_i     : in  std_logic_vector(1 downto 0);

      -- The engine: the buffer, a byte at a time
      buf_addr_i : in  std_logic_vector(8 downto 0);
      buf_we_i   : in  std_logic;
      buf_data_i : in  std_logic_vector(7 downto 0);
      buf_data_o : out std_logic_vector(7 downto 0)
   );
end entity sd_regs;

architecture synthesis of sd_regs is

   constant C_INIT  : std_logic_vector(1 downto 0) := "00";
   constant C_WRITE : std_logic_vector(1 downto 0) := "10";

   type t_lane is array (0 to 127) of std_logic_vector(7 downto 0);
   type t_lanes is array (0 to 3) of std_logic_vector(7 downto 0);

   signal lba_r     : std_logic_vector(31 downto 0)          := (others => '0');
   signal chunk_r   : std_logic_vector(3 downto 0)           := (others => '0');
   signal err_r     : std_logic_vector(3 downto 0)           := (others => '0');
   signal select_r  : std_logic_vector(3 downto 0)           := (others => '0');
   signal ready_r   : std_logic                              := '0';
   signal last_r    : std_logic_vector(31 downto 0)          := (others => '0');
   signal type_r    : std_logic_vector(1 downto 0)           := (others => '0');
   signal changed_r : std_logic_vector(G_SLOTS - 1 downto 0) := (others => '0');
   signal seen_r    : std_logic_vector(G_SLOTS - 1 downto 0) := (others => '0');

   -- The command that runs, whether its end reports nothing, and the ACK
   -- of the write that started it, held until it ends
   signal busy_r    : std_logic                     := '0';
   signal cmd_r     : std_logic_vector(1 downto 0)  := (others => '0');
   signal slot_r    : std_logic_vector(3 downto 0)  := (others => '0');
   signal cmd_lba_r : std_logic_vector(31 downto 0) := (others => '0');
   signal quiet_r   : std_logic                     := '0';
   signal hold_r    : std_logic                     := '0';

   -- The read data of a register, or of the buffer
   signal rdata_r  : std_logic_vector(31 downto 0) := (others => '0');
   signal rd_buf_r : std_logic                     := '0';
   signal lane_r   : std_logic_vector(1 downto 0)  := (others => '0');

   -- The buffer's one port, and the byte lanes read from it
   signal ram_addr  : std_logic_vector(6 downto 0);
   signal ram_we    : std_logic_vector(3 downto 0);
   signal ram_wdata : t_lanes;
   signal ram_q     : t_lanes;

   signal accept  : std_logic;
   signal present : std_logic;
   signal wp      : std_logic;
   signal changed : std_logic;

   -- Bit i of v, or '0' for a slot that the system does not have
   function slot_bit(v : std_logic_vector;
                     i : std_logic_vector) return std_logic is
   begin
      if to_integer(i) < v'length then
         return v(to_integer(i));
      end if;
      return '0';
   end function slot_bit;

begin

   accept     <= wb_cyc_i and wb_stb_i and not hold_r;
   wb_stall_o <= hold_r;

   present <= slot_bit(present_i, select_r);
   wp      <= slot_bit(wp_i, select_r);
   changed <= slot_bit(changed_r, select_r);

   busy_o <= busy_r;
   cmd_o  <= cmd_r;
   slot_o <= slot_r;
   lba_o  <= cmd_lba_r;

   wb_data_o <= ram_q(3) & ram_q(2) & ram_q(1) & ram_q(0) when rd_buf_r = '1' else
                rdata_r;

   buf_data_o <= ram_q(to_integer(lane_r));


   -- The engine has the buffer while busy, and the bus otherwise.
   p_ram_port : process (all)
   begin
      if busy_r = '1' then
         ram_addr <= buf_addr_i(8 downto 2);
         for j in 0 to 3 loop
            ram_wdata(j) <= buf_data_i;
            ram_we(j)    <= '1' when buf_we_i = '1' and to_integer(buf_addr_i(1 downto 0)) = j else
                            '0';
         end loop;
      else
         ram_addr <= chunk_r & wb_addr_i(2 downto 0);
         for j in 0 to 3 loop
            ram_wdata(j) <= wb_data_i(8 * j + 7 downto 8 * j);
            ram_we(j)    <= accept and wb_we_i and wb_addr_i(3);
         end loop;
      end if;
   end process p_ram_port;


   gen_lanes : for j in 0 to 3 generate
      signal lane_ram : t_lane := (others => (others => '0'));
   begin

      p_lane : process (clk_i)
      begin
         if rising_edge(clk_i) then
            if ram_we(j) = '1' then
               lane_ram(to_integer(ram_addr)) <= ram_wdata(j);
            end if;
            ram_q(j) <= lane_ram(to_integer(ram_addr));
         end if;
      end process p_lane;

   end generate gen_lanes;


   p_regs : process (clk_i)
      variable cmd_v : std_logic_vector(3 downto 0);
   begin
      if rising_edge(clk_i) then
         wb_ack_o <= accept;
         start_o  <= '0';
         abort_o  <= '0';
         lane_r   <= buf_addr_i(1 downto 0);

         if accept = '1' and wb_we_i = '0' then
            rd_buf_r <= wb_addr_i(3);
            case wb_addr_i is
               when X"0" =>
                  rdata_r                <= (others => '0');
                  rdata_r(0)             <= busy_r;
                  rdata_r(1)             <= or err_r;
                  rdata_r(2)             <= present;
                  rdata_r(3)             <= ready_r;
                  rdata_r(4)             <= changed;
                  rdata_r(5)             <= wp and present;
                  rdata_r(9 downto 8)    <= type_r when ready_r = '1' else "00";

               when X"1"   => rdata_r <= lba_r;
               when X"2"   => rdata_r <= X"0000000" & chunk_r;
               when X"3"   => rdata_r <= X"0000000" & err_r;
               when X"4"   => rdata_r <= X"0000000" & select_r;
               when X"5"   => rdata_r <= last_r when ready_r = '1' else X"00000000";
               when X"6"   => rdata_r <= to_slv(G_SLOTS, 32);
               when others => rdata_r <= (others => '0');
            end case;
         end if;

         -- SD_CHUNK takes a write at any time, the others only while idle.
         if accept = '1' and wb_we_i = '1' then
            if wb_addr_i = X"2" then
               chunk_r <= wb_data_i(3 downto 0);
            end if;

            if busy_r = '0' then
               case wb_addr_i is
                  when X"0" =>
                     cmd_v := wb_data_i(3 downto 0);
                     if cmd_v <= 2 then
                        if present = '0' then
                           err_r <= X"1";
                        elsif cmd_v /= 0 and ready_r = '0' then
                           err_r <= X"2";
                        elsif cmd_v /= 0 and lba_r > last_r then
                           err_r <= X"7";
                        elsif cmd_v = 2 and wp = '1' then
                           err_r <= X"6";
                        else
                           busy_r    <= '1';
                           start_o   <= '1';
                           cmd_r     <= cmd_v(1 downto 0);
                           slot_r    <= select_r;
                           cmd_lba_r <= lba_r;
                           if G_HOLD_ACK then
                              hold_r   <= '1';
                              wb_ack_o <= '0';
                           end if;
                           if cmd_v = 0 then
                              ready_r                        <= '0';
                              changed_r(to_integer(select_r)) <= '0';
                           end if;
                        end if;
                     end if;

                  when X"1" =>
                     lba_r <= wb_data_i;

                  when X"4" =>
                     if wb_data_i(3 downto 0) /= select_r then
                        ready_r <= '0';
                     end if;
                     select_r <= wb_data_i(3 downto 0);

                  when others =>
                     null;
               end case;
            end if;
         end if;

         if busy_r = '1' and done_i = '1' then
            busy_r  <= '0';
            quiet_r <= '0';
            if hold_r = '1' then
               hold_r   <= '0';
               wb_ack_o <= '1';
            end if;
            if quiet_r = '0' then
               err_r <= error_i;
               if cmd_r = C_INIT and error_i = X"0" then
                  ready_r <= '1';
                  last_r  <= last_i;
                  type_r  <= type_i;
               end if;
            end if;
         end if;

         -- A card put in sets "changed", and one taken out ends "ready".
         for i in 0 to G_SLOTS - 1 loop
            if present_i(i) = '1' and seen_r(i) = '0' then
               changed_r(i) <= '1';
            end if;
         end loop;
         seen_r <= present_i;
         if present = '0' then
            ready_r <= '0';
         end if;

         if rst_i = '1' then
            wb_ack_o  <= '0';
            hold_r    <= '0';
            start_o   <= '0';
            lba_r     <= (others => '0');
            chunk_r   <= (others => '0');
            err_r     <= (others => '0');
            select_r  <= (others => '0');
            ready_r   <= '0';
            last_r    <= (others => '0');
            type_r    <= (others => '0');
            changed_r <= present_i;
            seen_r    <= present_i;
            -- A Write that runs goes on, and reports nothing.
            if busy_r = '1' and cmd_r = C_WRITE then
               quiet_r <= not done_i;
            else
               busy_r  <= '0';
               quiet_r <= '0';
               abort_o <= busy_r and not done_i;
            end if;
         end if;
      end if;
   end process p_regs;

end architecture synthesis;
