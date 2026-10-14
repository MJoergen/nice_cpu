-- Simulation-only memory for the testbench: the whole 2^32-word address space
-- (ISA.md §1.1), with a read-only Wishbone port for the instruction bus and a
-- read-write Wishbone port for the data bus, as MICROARCH.md §8 describes. It
-- loads a .bin file (ISA.md §10.4) at time 0. A word never written reads 0.
--
-- THEORY OF OPERATION
-- The memory is held sparsely, like the emulator's: 2^20 pages of 4096 words,
-- each allocated on its first write. One process owns it, so the two ports
-- need no shared variable. When both ports reach the same word in one cycle,
-- the instruction port reads the value from before the data port's write.
--
-- Both ports are pipelined Wishbone slaves that never stall and acknowledge
-- each request in the next cycle.
--
-- The I/O range, 0xFFFFFF00-0xFFFFFFFF, follows ISA.md §8.3:
-- * The instruction port reads 0 there.
-- * The console is at 0xFFFFFF00. A write puts bits 7..0 on console_data_o,
--   with console_valid_o high, in the cycle the write is accepted, and stores
--   nothing. A read returns 0.
-- * The rest of the range is plain memory, as in the emulator.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) The masters hold CYC high from a request until its ACK.
--
-- RESET
-- Synchronous. It drops the ACKs owed and leaves the memory as it is
-- (ISA.md §8.1).

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;
   use std.textio.all;

entity wb_mem is
   generic (
      G_INIT_FILE : string
   );
   port (
      clk_i           : in  std_logic;
      rst_i           : in  std_logic;

      -- Instruction bus: read only
      ibus_cyc_i      : in  std_logic;
      ibus_stb_i      : in  std_logic;
      ibus_stall_o    : out std_logic;
      ibus_ack_o      : out std_logic := '0';
      ibus_addr_i     : in  std_logic_vector(31 downto 0);
      ibus_data_o     : out std_logic_vector(31 downto 0);

      -- Data bus: read and write
      dbus_cyc_i      : in  std_logic;
      dbus_stb_i      : in  std_logic;
      dbus_stall_o    : out std_logic;
      dbus_ack_o      : out std_logic := '0';
      dbus_we_i       : in  std_logic;
      dbus_addr_i     : in  std_logic_vector(31 downto 0);
      dbus_data_i     : in  std_logic_vector(31 downto 0);
      dbus_data_o     : out std_logic_vector(31 downto 0);

      -- Console output
      console_valid_o : out std_logic;
      console_data_o  : out std_logic_vector(7 downto 0)
   );
end entity wb_mem;

architecture simulation of wb_mem is

   constant C_IO_BASE : std_logic_vector(31 downto 0) := X"FFFFFF00";
   constant C_CONSOLE : std_logic_vector(31 downto 0) := X"FFFFFF00";

begin

   ibus_stall_o <= '0';
   dbus_stall_o <= '0';


   console_valid_o <= dbus_cyc_i and dbus_stb_i and dbus_we_i when dbus_addr_i = C_CONSOLE else
                      '0';
   console_data_o  <= dbus_data_i(7 downto 0);


   p_mem : process
      type     t_page     is array (0 to 4095) of std_logic_vector(31 downto 0);
      type     t_page_ptr is access t_page;
      type     t_pages    is array (0 to 2 ** 20 - 1) of t_page_ptr;
      variable pages_v    : t_pages;

      impure function mem_read(addr : std_logic_vector(31 downto 0)) return std_logic_vector is
         constant C_INDEX : natural := to_integer(addr(31 downto 12));
      begin
         if pages_v(C_INDEX) = null then
            return X"00000000";
         end if;
         return pages_v(C_INDEX)(to_integer(addr(11 downto 0)));
      end function mem_read;

      procedure mem_write(addr : std_logic_vector(31 downto 0);
                          data : std_logic_vector(31 downto 0)) is
         constant C_INDEX : natural := to_integer(addr(31 downto 12));
      begin
         if pages_v(C_INDEX) = null then
            pages_v(C_INDEX) := new t_page'(others => (others => '0'));
         end if;
         pages_v(C_INDEX)(to_integer(addr(11 downto 0))) := data;
      end procedure mem_write;

      -- Skips blanks, and the CR of a CRLF line end.
      procedure skip_blanks(l : inout line) is
         variable ch_v : character;
      begin
         while l'length > 0 and (l(l'low) = ' ' or l(l'low) = HT or l(l'low) = CR) loop
            read(l, ch_v);
         end loop;
      end procedure skip_blanks;

      -- Reads one field of 1 to 8 hex digits, after any blanks.
      procedure read_hex(l     : inout line;
                         value : out   std_logic_vector(31 downto 0);
                         good  : out   boolean) is
         variable ch_v     : character;
         variable digit_v  : natural range 0 to 15;
         variable value_v  : std_logic_vector(31 downto 0) := (others => '0');
         variable digits_v : natural                       := 0;
      begin
         skip_blanks(l);

         digit_loop : while l'length > 0 loop
            ch_v := l(l'low);
            case ch_v is
               when '0' to '9' => digit_v := character'pos(ch_v) - character'pos('0');
               when 'a' to 'f' => digit_v := character'pos(ch_v) - character'pos('a') + 10;
               when 'A' to 'F' => digit_v := character'pos(ch_v) - character'pos('A') + 10;
               when others     => exit digit_loop;
            end case;
            read(l, ch_v);
            value_v  := value_v(27 downto 0) & to_slv(digit_v, 4);
            digits_v := digits_v + 1;
         end loop digit_loop;

         value := value_v;
         good  := digits_v >= 1 and digits_v <= 8;
      end procedure read_hex;

      procedure load(file_name : string) is
         file     f         : text;
         variable l         : line;
         variable line_no_v : natural := 0;
         variable addr_v    : std_logic_vector(31 downto 0);
         variable data_v    : std_logic_vector(31 downto 0);
         variable good_v    : boolean;
         variable status_v  : file_open_status;
      begin
         file_open(status_v, f, file_name, read_mode);
         assert status_v = OPEN_OK
            report "wb_mem: cannot open " & file_name
            severity failure;

         while not endfile(f) loop
            readline(f, l);
            line_no_v := line_no_v + 1;

            -- Blank lines are allowed.
            skip_blanks(l);
            if l'length > 0 then
               read_hex(l, addr_v, good_v);
               if good_v then
                  read_hex(l, data_v, good_v);
               end if;
               skip_blanks(l);
               assert good_v and l'length = 0
                  report "wb_mem: " & file_name & ":" & integer'image(line_no_v) &
                         ": expected 'address word'"
                  severity failure;
               mem_write(addr_v, data_v);
            end if;

            deallocate(l);
         end loop;

         file_close(f);
      end procedure load;

   begin
      load(G_INIT_FILE);

      main_loop : loop
         wait until rising_edge(clk_i);

         ibus_ack_o <= ibus_cyc_i and ibus_stb_i;
         if ibus_cyc_i = '1' and ibus_stb_i = '1' then
            if ibus_addr_i >= C_IO_BASE then
               ibus_data_o <= X"00000000";
            else
               ibus_data_o <= mem_read(ibus_addr_i);
            end if;
         end if;

         dbus_ack_o <= dbus_cyc_i and dbus_stb_i;
         if dbus_cyc_i = '1' and dbus_stb_i = '1' then
            if dbus_we_i = '1' then
               if dbus_addr_i /= C_CONSOLE then
                  mem_write(dbus_addr_i, dbus_data_i);
               end if;
            elsif dbus_addr_i = C_CONSOLE then
               dbus_data_o <= X"00000000";
            else
               dbus_data_o <= mem_read(dbus_addr_i);
            end if;
         end if;

         if rst_i = '1' then
            ibus_ack_o <= '0';
            dbus_ack_o <= '0';
         end if;
      end loop main_loop;
   end process p_mem;

end architecture simulation;
