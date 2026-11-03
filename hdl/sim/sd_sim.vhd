-- Simulation-only protocol engine for src/sd_regs.vhd: two slots, with a
-- card in each slot whose image file is given, as niceemu's --sd0 and
-- --sd1 give them (SYSTEM.md §5).
--
-- THEORY OF OPERATION
-- Each image is read into memory at time 0, and never written back, as
-- VHDL has no seek. So a Write changes the image of this run only: a test
-- that writes a sector and reads it back sees the same as in the emulator,
-- but the file is as it was. A card is present when its image is given,
-- is never write-protected, and is SDHC, type 2, with the image's size in
-- sectors.
--
-- Init ends in the cycle after start_i. Read writes the 512 bytes of the
-- sector into the buffer, one per cycle, and Write reads them, one per
-- cycle, with the byte of each address in the cycle after it. Each then
-- ends with done_o and error 0. With sd_regs's G_HOLD_ACK, the core waits
-- for the end in the write that started the command, so it never sees
-- busy 1, and the trace is the emulator's.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) start_i comes only while no command runs, with the command, the slot,
--    and the sector of sd_regs, which hold until done_o.
-- b) An image file is empty or a multiple of 512 bytes long. Otherwise
--    the simulation fails at time 0.
--
-- RESET
-- None. abort_i abandons the command that runs.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

entity sd_sim is
   generic (
      G_SD0_FILE : string := "";
      G_SD1_FILE : string := ""
   );
   port (
      clk_i      : in  std_logic;
      present_o  : out std_logic_vector(1 downto 0);
      wp_o       : out std_logic_vector(1 downto 0);
      start_i    : in  std_logic;
      abort_i    : in  std_logic;
      cmd_i      : in  std_logic_vector(1 downto 0);
      slot_i     : in  std_logic_vector(3 downto 0);
      lba_i      : in  std_logic_vector(31 downto 0);
      done_o     : out std_logic                     := '0';
      error_o    : out std_logic_vector(3 downto 0)  := (others => '0');
      last_o     : out std_logic_vector(31 downto 0) := (others => '0');
      type_o     : out std_logic_vector(1 downto 0)  := (others => '0');
      buf_addr_o : out std_logic_vector(8 downto 0)  := (others => '0');
      buf_we_o   : out std_logic                     := '0';
      buf_data_o : out std_logic_vector(7 downto 0)  := (others => '0');
      buf_data_i : in  std_logic_vector(7 downto 0)
   );
end entity sd_sim;

architecture simulation of sd_sim is

   type t_bytes is array (natural range <>) of std_logic_vector(7 downto 0);
   type t_image is access t_bytes;
   type t_images is array (0 to 1) of t_image;

   -- The image of name, or null for "".
   impure function load(name : string) return t_image is
      type t_char_file is file of character;

      file     f        : t_char_file;
      variable status_v : file_open_status;
      variable c_v      : character;
      variable n_v      : natural := 0;
      variable image_v  : t_image;
   begin
      if name = "" then
         return null;
      end if;
      -- A file of character reads one byte per element.
      file_open(status_v, f, name, read_mode);
      assert status_v = open_ok
         report "sd_sim: cannot read " & name
         severity failure;
      while not endfile(f) loop
         read(f, c_v);
         n_v := n_v + 1;
      end loop;
      file_close(f);
      assert n_v > 0 and n_v mod 512 = 0
         report "sd_sim: " & name & " is not a positive multiple of 512 bytes"
         severity failure;
      image_v := new t_bytes(0 to n_v - 1);
      file_open(f, name, read_mode);
      for i in 0 to n_v - 1 loop
         read(f, c_v);
         image_v(i) := to_slv(character'pos(c_v), 8);
      end loop;
      file_close(f);
      return image_v;
   end function load;

begin

   present_o(0) <= '1' when G_SD0_FILE /= "" else '0';
   present_o(1) <= '1' when G_SD1_FILE /= "" else '0';
   wp_o         <= "00";


   p_engine : process
      variable images_v  : t_images;
      variable image_v   : t_image;
      variable base_v    : natural;
      variable aborted_v : boolean;
   begin
      images_v(0) := load(G_SD0_FILE);
      images_v(1) := load(G_SD1_FILE);

      loop
         wait until rising_edge(clk_i);
         done_o <= '0';
         if start_i = '1' then
            image_v   := images_v(to_integer(slot_i(0 downto 0)));
            base_v    := to_integer(lba_i) * 512;
            aborted_v := false;
            case cmd_i is
               when "01" =>
                  for b in 0 to 511 loop
                     buf_addr_o <= to_slv(b, 9);
                     buf_data_o <= image_v(base_v + b);
                     buf_we_o   <= '1';
                     wait until rising_edge(clk_i);
                     aborted_v := abort_i = '1';
                     exit when aborted_v;
                  end loop;
                  buf_we_o <= '0';

               when "10" =>
                  for b in 0 to 512 loop
                     if b < 512 then
                        buf_addr_o <= to_slv(b, 9);
                     end if;
                     wait until rising_edge(clk_i);
                     aborted_v := abort_i = '1';
                     exit when aborted_v;
                     if b > 0 then
                        image_v(base_v + b - 1) := buf_data_i;
                     end if;
                  end loop;

               when others =>
                  last_o <= to_slv(image_v'length / 512 - 1, 32);
                  type_o <= "10";
            end case;
            if not aborted_v then
               error_o <= X"0";
               done_o  <= '1';
            end if;
         end if;
      end loop;
   end process p_engine;

end architecture simulation;
