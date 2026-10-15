-- A self-checking test of sim/wb_mem.vhd.
--
-- THEORY OF OPERATION
-- It loads test/mem.bin, which is written by hand to use what ISA.md §10.4
-- and the emulator's loader accept beyond the assembler's output: short hex
-- fields, upper-case digits, blanks and tabs, a blank line, and a CRLF line
-- end. Then it checks each rule in the header of wb_mem.vhd. The run stops
-- with status 0 when every check passes, and 1 at the first that fails.

library ieee;
   use ieee.std_logic_1164.all;

   use std.env.all;

entity tb_mem is
   generic (
      G_BIN_FILE   : string;
      G_INPUT_FILE : string
   );
end entity tb_mem;

architecture simulation of tb_mem is

   signal clk : std_logic;
   signal rst : std_logic := '1';

   signal ibus_cyc   : std_logic                     := '0';
   signal ibus_stb   : std_logic                     := '0';
   signal ibus_stall : std_logic;
   signal ibus_ack   : std_logic;
   signal ibus_addr  : std_logic_vector(30 downto 0) := (others => '0');
   signal ibus_data  : std_logic_vector(63 downto 0);

   signal dbus_cyc      : std_logic                     := '0';
   signal dbus_stb      : std_logic                     := '0';
   signal dbus_stall    : std_logic;
   signal dbus_ack      : std_logic;
   signal dbus_we       : std_logic                     := '0';
   signal dbus_addr     : std_logic_vector(31 downto 0) := (others => '0');
   signal dbus_data_out : std_logic_vector(31 downto 0) := (others => '0');
   signal dbus_data_in  : std_logic_vector(31 downto 0);

   signal console_valid : std_logic;
   signal console_data  : std_logic_vector(7 downto 0);
   signal console_count : natural := 0;
   signal console_last  : std_logic_vector(7 downto 0);

begin

   p_clk : process
   begin
      clk <= '1', '0' after 5 ns;
      wait for 10 ns;
   end process p_clk;


   i_wb_mem : entity work.wb_mem
      generic map (
         G_INIT_FILE  => G_BIN_FILE,
         G_INPUT_FILE => G_INPUT_FILE
      )
      port map (
         clk_i           => clk,
         rst_i           => rst,
         ibus_cyc_i      => ibus_cyc,
         ibus_stb_i      => ibus_stb,
         ibus_stall_o    => ibus_stall,
         ibus_ack_o      => ibus_ack,
         ibus_addr_i     => ibus_addr,
         ibus_data_o     => ibus_data,
         dbus_cyc_i      => dbus_cyc,
         dbus_stb_i      => dbus_stb,
         dbus_stall_o    => dbus_stall,
         dbus_ack_o      => dbus_ack,
         dbus_we_i       => dbus_we,
         dbus_addr_i     => dbus_addr,
         dbus_data_i     => dbus_data_out,
         dbus_data_o     => dbus_data_in,
         console_valid_o => console_valid,
         console_data_o  => console_data
      ); -- i_wb_mem


   p_console : process (clk)
   begin
      if rising_edge(clk) then
         if console_valid = '1' then
            console_count <= console_count + 1;
            console_last  <= console_data;
         end if;
      end if;
   end process p_console;


   p_test : process

      procedure check(what     : string;
                      actual   : std_logic_vector;
                      expected : std_logic_vector) is
      begin
         if actual /= expected then
            report "tb_mem: " & what & ": got " & to_hstring(actual) &
                   ", expected " & to_hstring(expected)
               severity error;
            stop(1);
         end if;
      end procedure check;

      procedure check_true(what : string;
                           cond : boolean) is
      begin
         if not cond then
            report "tb_mem: " & what & ": failed"
               severity error;
            stop(1);
         end if;
      end procedure check_true;

      -- Reads the pair of words at addr and addr + 1. addr is even.
      procedure check_ibus(addr     : std_logic_vector(31 downto 0);
                           expected : std_logic_vector(63 downto 0)) is
      begin
         assert addr(0) = '0';
         ibus_cyc  <= '1';
         ibus_stb  <= '1';
         ibus_addr <= addr(31 downto 1);
         wait until rising_edge(clk);
         ibus_stb  <= '0';
         wait until rising_edge(clk) and ibus_ack = '1';
         ibus_cyc  <= '0';
         check("ibus read of " & to_hstring(addr), ibus_data, expected);
      end procedure check_ibus;

      procedure check_dbus(addr     : std_logic_vector(31 downto 0);
                           expected : std_logic_vector(31 downto 0)) is
      begin
         dbus_cyc  <= '1';
         dbus_stb  <= '1';
         dbus_we   <= '0';
         dbus_addr <= addr;
         wait until rising_edge(clk);
         dbus_stb  <= '0';
         wait until rising_edge(clk) and dbus_ack = '1';
         dbus_cyc  <= '0';
         check("dbus read of " & to_hstring(addr), dbus_data_in, expected);
      end procedure check_dbus;

      procedure write_dbus(addr : std_logic_vector(31 downto 0);
                           data : std_logic_vector(31 downto 0)) is
      begin
         dbus_cyc      <= '1';
         dbus_stb      <= '1';
         dbus_we       <= '1';
         dbus_addr     <= addr;
         dbus_data_out <= data;
         wait until rising_edge(clk);
         dbus_stb      <= '0';
         wait until rising_edge(clk) and dbus_ack = '1';
         dbus_cyc      <= '0';
      end procedure write_dbus;

   begin
      -- No port ever stalls, so the procedures above do not wait for it.
      wait until rising_edge(clk);
      check_true("ibus stall", ibus_stall = '0');
      check_true("dbus stall", dbus_stall = '0');
      rst <= '0';

      -- The loaded words, through both ports. The instruction port returns
      -- the word at the lower address in bits 31..0.
      check_ibus(X"00000000", X"00000050" & X"001C1800");
      check_dbus(X"00000000", X"001C1800");
      check_dbus(X"00000001", X"00000050");

      -- A word never written reads 0.
      check_ibus(X"12345678", X"00000000" & X"00000000");
      check_dbus(X"12345678", X"00000000");

      -- The I/O range: the loaded word at 0xFFFFFFFF and a written word at
      -- 0xFFFFFF80 are memory to the data port, and read 0 on the
      -- instruction port. The pair just below the range is memory to both.
      check_dbus(X"FFFFFFFF", X"00000007");
      check_ibus(X"FFFFFFFE", X"00000000" & X"00000000");
      write_dbus(X"FFFFFF80", X"00000005");
      check_dbus(X"FFFFFF80", X"00000005");
      check_ibus(X"FFFFFF80", X"00000000" & X"00000000");
      write_dbus(X"FFFFFEFF", X"00000003");
      check_ibus(X"FFFFFEFE", X"00000003" & X"00000000");

      -- The console takes bits 7..0, in the cycle the write is accepted,
      -- and stores nothing. A read returns 0x100 plus the next byte of
      -- G_INPUT_FILE, test/mem.input, which holds "A", the byte 0xC3, and
      -- a newline. After those, it returns 0x200 (ISA.md §8.3).
      dbus_cyc      <= '1';
      dbus_stb      <= '1';
      dbus_we       <= '1';
      dbus_addr     <= X"FFFFFF00";
      dbus_data_out <= X"12345648";
      wait for 1 ns;
      check_true("console valid in the request cycle", console_valid = '1');
      wait until rising_edge(clk);
      dbus_stb <= '0';
      wait until rising_edge(clk) and dbus_ack = '1';
      dbus_cyc <= '0';
      check_true("console bytes", console_count = 1);
      check("console byte", console_last, X"48");
      check_dbus(X"FFFFFF00", X"00000141");
      check_dbus(X"FFFFFF00", X"000001C3");
      check_dbus(X"FFFFFF00", X"0000010A");
      check_dbus(X"FFFFFF00", X"00000200");
      check_dbus(X"FFFFFF00", X"00000200");
      check_true("console bytes after a read", console_count = 1);

      -- The read counter: a data read returns the count and then counts
      -- itself, a write sets the count, and the instruction port reads 0.
      write_dbus(X"FFFFFF01", X"00000005");
      check_dbus(X"FFFFFF01", X"00000005");
      check_dbus(X"FFFFFF01", X"00000006");
      check_ibus(X"FFFFFF00", X"00000000" & X"00000000");
      check_dbus(X"FFFFFF01", X"00000007");

      -- Both ports at one word in one cycle: the instruction port reads the
      -- value from before the write.
      ibus_cyc      <= '1';
      ibus_stb      <= '1';
      ibus_addr     <= "000" & X"0000080";
      dbus_cyc      <= '1';
      dbus_stb      <= '1';
      dbus_we       <= '1';
      dbus_addr     <= X"00000100";
      dbus_data_out <= X"00000009";
      wait until rising_edge(clk);
      ibus_stb <= '0';
      dbus_stb <= '0';
      wait until rising_edge(clk);
      check_true("ibus ack", ibus_ack = '1');
      check_true("dbus ack", dbus_ack = '1');
      check("ibus read during a write", ibus_data, X"00000000" & X"00000000");
      ibus_cyc <= '0';
      dbus_cyc <= '0';
      check_ibus(X"00000100", X"00000000" & X"00000009");
      write_dbus(X"00000101", X"0000000A");
      check_ibus(X"00000100", X"0000000A" & X"00000009");

      -- Pipelined reads: a request in each of two cycles, then an ACK in
      -- each of the next two, in order.
      ibus_cyc  <= '1';
      ibus_stb  <= '1';
      ibus_addr <= "000" & X"0000000";
      wait until rising_edge(clk);
      ibus_addr <= "000" & X"0000080";
      wait until rising_edge(clk);
      ibus_stb  <= '0';
      check_true("first pipelined ack", ibus_ack = '1');
      check("first pipelined read", ibus_data, X"00000050" & X"001C1800");
      wait until rising_edge(clk);
      check_true("second pipelined ack", ibus_ack = '1');
      check("second pipelined read", ibus_data, X"0000000A" & X"00000009");
      ibus_cyc  <= '0';
      wait until rising_edge(clk);
      check_true("no third ack", ibus_ack = '0');

      -- Reset keeps the memory.
      rst <= '1';
      wait until rising_edge(clk);
      rst <= '0';
      check_dbus(X"00000001", X"00000050");
      check_dbus(X"FFFFFF80", X"00000005");

      report "tb_mem: all checks passed";
      stop(0);
   end process p_test;

end architecture simulation;
