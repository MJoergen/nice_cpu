-- A system test of the debug link of doc/DEBUG.md: src/debug_link.vhd
-- connected to a core, the data bus decoder, the memory model, and the
-- math unit, as a board connects them.
--
-- THEORY OF OPERATION
-- G_CORE names the core, as in tb_core. The core runs on sim/wb_mem.vhd,
-- which loads G_INIT_FILE. Its data bus goes through src/wb_dmux.vhd to
-- the memory model, the math unit, src/mpu.vhd, and the console, p_con.
-- The link is the second master of the data bus. It owns the bus while
-- the processor is held or halted, as debug_link's contract (a) says, and
-- the core owns it otherwise. hold_o holds the core in reset, and its
-- fall, a start, resets the math unit.
--
-- p_con stands in for a board's UART console (SYSTEM.md §1). For the
-- core, a read of 0xFFFFFF00 returns the next byte of its input buffer
-- plus 0x100, 0x200 after the end of the input, and 0 while no byte
-- waits; a write sends the byte to the link. For the link, 0xFFFFFF00 and
-- 0xFFFFFF01 read 0 and ignore writes, as DEBUG.md §3 says. The input
-- buffer holds 2048 bytes and is emptied at a start, when hold_o falls.
--
-- The test plays the host. It loads G_PROG_FILE, test/linkecho.nasm,
-- with a W built from the file, starts it, and checks every byte the link
-- sends against the exact string. The checksums of the fixed strings are
-- the sum of the bytes from the tag to the end of the payload, mod 256,
-- worked out with a script, not taken from a simulation. The checks:
-- * `b01`, and the W and R of DEBUG.md §8, through the decoder to memory;
-- * a word that G_INIT_FILE loaded, and the math unit through the decoder;
-- * the link's reads of the console and the read counter, and its writes
--   to the console, which the program must not see;
-- * the load, the start, the echo of console bytes and of ESC ESC, `e02`
--   and the control register while the program runs;
-- * a UART break, the halt notice, and the registers the program left;
-- * the restart of DEBUG.md §8, and a hold while the program runs.
-- The run stops with status 0 when every check passes, and 1 at the first
-- that fails.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

   use std.textio.all;
   use std.env.all;

library work;
   use work.pipe_pkg.all;
   use work.trace_pkg.all;

entity tb_link is
   generic (
      G_CORE      : string := "pipeline";
      G_INIT_FILE : string;
      G_PROG_FILE : string
   );
end entity tb_link;

architecture simulation of tb_link is

   constant C_TIMEOUT : positive  := 2000;
   constant C_ESC     : character := character'val(255);

   -- The slaves of the data bus decoder
   constant C_MEM    : natural := 0;
   constant C_MPU    : natural := 1;
   constant C_CON    : natural := 2;
   constant C_SLAVES : natural := 3;

   constant C_CONSOLE : std_logic_vector(31 downto 0) := X"FFFFFF00";
   constant C_COUNTER : std_logic_vector(31 downto 0) := X"FFFFFF01";

   signal clk      : std_logic;
   signal rst      : std_logic := '1';
   signal core_rst : std_logic;
   signal dev_rst  : std_logic;

   -- The host
   signal rx_valid : std_logic                    := '0';
   signal rx_ready : std_logic;
   signal rx_data  : std_logic_vector(7 downto 0) := (others => '0');
   signal rx_break : std_logic                    := '0';
   signal tx_valid : std_logic;
   signal tx_data  : std_logic_vector(7 downto 0);

   -- The console between p_con and the link
   signal con_valid    : std_logic := '0';
   signal con_ready    : std_logic;
   signal con_data     : std_logic_vector(7 downto 0);
   signal con_in_valid : std_logic;
   signal con_in_data  : std_logic_vector(7 downto 0);
   signal free         : std_logic_vector(15 downto 0);
   signal eoi          : std_logic;

   -- The processor
   signal hold          : std_logic;
   signal hold_d        : std_logic := '1';
   signal halted        : std_logic;
   signal halt          : t_halt    := HALT_NONE;
   signal halt_reason   : std_logic_vector(2 downto 0);
   signal regs          : t_regs;
   signal regs_flat     : std_logic_vector(511 downto 0);
   signal retire        : t_retire;
   signal link_owns_bus : std_logic;

   -- The instruction bus
   signal ibus_cyc   : std_logic;
   signal ibus_stb   : std_logic;
   signal ibus_stall : std_logic;
   signal ibus_ack   : std_logic;
   signal core_iack  : std_logic;
   signal ibus_addr  : std_logic_vector(30 downto 0);
   signal ibus_data  : std_logic_vector(63 downto 0);

   -- The core's data bus
   signal core_cyc      : std_logic;
   signal core_stb      : std_logic;
   signal core_we       : std_logic;
   signal core_addr     : std_logic_vector(31 downto 0);
   signal core_data_out : std_logic_vector(31 downto 0);
   signal core_stall    : std_logic;
   signal core_ack      : std_logic;

   -- The link's data bus
   signal link_cyc      : std_logic;
   signal link_stb      : std_logic;
   signal link_we       : std_logic;
   signal link_addr     : std_logic_vector(31 downto 0);
   signal link_data_out : std_logic_vector(31 downto 0);
   signal link_stall    : std_logic;
   signal link_ack      : std_logic;

   -- The data bus after the choice of master
   signal dbus_cyc      : std_logic;
   signal dbus_stb      : std_logic;
   signal dbus_stall    : std_logic;
   signal dbus_ack      : std_logic;
   signal dbus_we       : std_logic;
   signal dbus_addr     : std_logic_vector(31 downto 0);
   signal dbus_data_out : std_logic_vector(31 downto 0);
   signal dbus_data_in  : std_logic_vector(31 downto 0);
   signal dbus_sel      : natural range 0 to C_SLAVES - 1;

   signal slave_stb   : std_logic_vector(C_SLAVES - 1 downto 0);
   signal slave_stall : std_logic_vector(C_SLAVES - 1 downto 0);
   signal slave_ack   : std_logic_vector(C_SLAVES - 1 downto 0);
   signal slave_data  : std_logic_vector(32 * C_SLAVES - 1 downto 0);

   -- What the link sent, for the checks
   signal got     : string(1 to 4096);
   signal got_len : natural := 0;

   -- The console bytes that the program wrote, waiting for the link
   type   t_bytes is array (0 to 255) of std_logic_vector(7 downto 0);
   signal out_q     : t_bytes;
   signal out_head  : natural range 0 to 255 := 0;
   signal out_count : natural range 0 to 256 := 0;

   -- The core and its devices are held when the link holds them.
   signal unused_fetch_events : t_fetch_events;

begin

   p_clk : process
   begin
      clk <= '1', '0' after 5 ns;
      wait for 10 ns;
   end process p_clk;

   core_rst <= rst or hold;
   -- A hold resets the core with fetches in flight. Their ACKs come while
   -- CYC is low, and Wishbone ignores them.
   core_iack <= ibus_ack and ibus_cyc;
   -- The devices answer the link while the core is held, and start from
   -- their reset values at a start, when hold_o falls (DEBUG.md §6).
   dev_rst <= rst or (hold_d and not hold);


   gen_core : if G_CORE = "multicycle" generate

      i_multicycle : entity work.multicycle
         port map (
            clk_i        => clk,
            rst_i        => core_rst,
            ibus_cyc_o   => ibus_cyc,
            ibus_stb_o   => ibus_stb,
            ibus_stall_i => ibus_stall,
            ibus_ack_i   => core_iack,
            ibus_addr_o  => ibus_addr,
            ibus_data_i  => ibus_data,
            dbus_cyc_o   => core_cyc,
            dbus_stb_o   => core_stb,
            dbus_stall_i => core_stall,
            dbus_ack_i   => core_ack,
            dbus_we_o    => core_we,
            dbus_addr_o  => core_addr,
            dbus_data_o  => core_data_out,
            dbus_data_i  => dbus_data_in,
            nmi_valid_i  => '0',
            nmi_ready_o  => open,
            nmi_vector_i => X"00",
            irq_valid_i  => '0',
            irq_ready_o  => open,
            irq_vector_i => X"00",
            halted_o     => halted,
            instret_o    => open,
            regs_o       => regs,
            retire_o     => retire
         ); -- i_multicycle

   elsif G_CORE = "pipeline" generate

      i_pipeline : entity work.pipeline
         port map (
            clk_i        => clk,
            rst_i        => core_rst,
            ibus_cyc_o   => ibus_cyc,
            ibus_stb_o   => ibus_stb,
            ibus_stall_i => ibus_stall,
            ibus_ack_i   => core_iack,
            ibus_addr_o  => ibus_addr,
            ibus_data_i  => ibus_data,
            dbus_cyc_o   => core_cyc,
            dbus_stb_o   => core_stb,
            dbus_stall_i => core_stall,
            dbus_ack_i   => core_ack,
            dbus_we_o    => core_we,
            dbus_addr_o  => core_addr,
            dbus_data_o  => core_data_out,
            dbus_data_i  => dbus_data_in,
            nmi_valid_i  => '0',
            nmi_ready_o  => open,
            nmi_vector_i => X"00",
            irq_valid_i  => '0',
            irq_ready_o  => open,
            irq_vector_i => X"00",
            halted_o     => halted,
            instret_o    => open,
            regs_o       => regs,
            retire_o     => retire,
            stats_o      => unused_fetch_events
         ); -- i_pipeline

   else generate

      -- A core without a branch above
      assert false
         report "tb_link: unknown core " & G_CORE
         severity failure;

   end generate gen_core;


   -- The halt reason of DEBUG.md §6, from the report of the halting step.
   p_halt : process (clk)
   begin
      if rising_edge(clk) then
         if retire.valid = '1' and retire.halt /= HALT_NONE then
            halt <= retire.halt;
         end if;
         if core_rst = '1' then
            halt <= HALT_NONE;
         end if;
      end if;
   end process p_halt;

   halt_reason <= std_logic_vector(to_unsigned(t_halt'pos(halt), 3));

   gen_regs : for n in 0 to 15 generate
      regs_flat(32 * n + 31 downto 32 * n) <= regs(n);
   end generate gen_regs;


   -- The link owns the data bus while the processor is held or halted.
   link_owns_bus <= hold or halted;

   dbus_cyc      <= link_cyc when link_owns_bus = '1' else core_cyc;
   dbus_stb      <= link_stb when link_owns_bus = '1' else core_stb;
   dbus_we       <= link_we when link_owns_bus = '1' else core_we;
   dbus_addr     <= link_addr when link_owns_bus = '1' else core_addr;
   dbus_data_out <= link_data_out when link_owns_bus = '1' else core_data_out;

   -- Each master sees the STALL and the ACK of its own accesses only.
   core_stall <= dbus_stall or link_owns_bus;
   core_ack   <= dbus_ack and not link_owns_bus;
   link_stall <= dbus_stall or not link_owns_bus;
   link_ack   <= dbus_ack and link_owns_bus;

   -- The link's accesses to the console and the read counter go to p_con,
   -- which gives them the link's rule.
   dbus_sel <= C_CON when dbus_addr = C_CONSOLE or
                          (link_owns_bus = '1' and dbus_addr = C_COUNTER) else
               C_MPU when dbus_addr(31 downto 5) = X"FFFFFF" & "001" else
               C_MEM;


   i_wb_dmux : entity work.wb_dmux
      generic map (
         G_SLAVES => C_SLAVES
      )
      port map (
         clk_i     => clk,
         rst_i     => rst,
         sel_i     => dbus_sel,
         m_cyc_i   => dbus_cyc,
         m_stb_i   => dbus_stb,
         m_stall_o => dbus_stall,
         m_ack_o   => dbus_ack,
         m_data_o  => dbus_data_in,
         s_stb_o   => slave_stb,
         s_stall_i => slave_stall,
         s_ack_i   => slave_ack,
         s_data_i  => slave_data
      ); -- i_wb_dmux


   i_wb_mem : entity work.wb_mem
      generic map (
         G_INIT_FILE => G_INIT_FILE
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
         dbus_stb_i      => slave_stb(C_MEM),
         dbus_stall_o    => slave_stall(C_MEM),
         dbus_ack_o      => slave_ack(C_MEM),
         dbus_we_i       => dbus_we,
         dbus_addr_i     => dbus_addr,
         dbus_data_i     => dbus_data_out,
         dbus_data_o     => slave_data(32 * C_MEM + 31 downto 32 * C_MEM),
         console_valid_o => open,
         console_data_o  => open
      ); -- i_wb_mem


   i_mpu : entity work.mpu
      port map (
         clk_i      => clk,
         rst_i      => dev_rst,
         wb_cyc_i   => dbus_cyc,
         wb_stb_i   => slave_stb(C_MPU),
         wb_stall_o => slave_stall(C_MPU),
         wb_ack_o   => slave_ack(C_MPU),
         wb_we_i    => dbus_we,
         wb_addr_i  => dbus_addr(4 downto 0),
         wb_data_i  => dbus_data_out,
         wb_data_o  => slave_data(32 * C_MPU + 31 downto 32 * C_MPU)
      ); -- i_mpu


   -- The console: an input buffer of 2048 bytes for the core, and the
   -- bytes the core writes, on their way to the link.
   p_con : process (clk)
      type     t_buffer is array (0 to 2047) of std_logic_vector(7 downto 0);
      variable in_q_v     : t_buffer;
      variable in_head_v  : natural range 0 to 2047 := 0;
      variable in_count_v : natural range 0 to 2048 := 0;
      variable push_v     : boolean;
   begin
      if rising_edge(clk) then
         slave_ack(C_CON) <= '0';
         push_v           := false;
         if dbus_cyc = '1' and slave_stb(C_CON) = '1' then
            slave_ack(C_CON)                                   <= '1';
            slave_data(32 * C_CON + 31 downto 32 * C_CON) <= (others => '0');
            if link_owns_bus = '0' then
               if dbus_we = '1' then
                  push_v := true;
               elsif in_count_v /= 0 then
                  slave_data(32 * C_CON + 8 downto 32 * C_CON) <= '1' & in_q_v(in_head_v);
                  in_head_v                                    := (in_head_v + 1) mod 2048;
                  in_count_v                                   := in_count_v - 1;
               elsif eoi = '1' then
                  slave_data(32 * C_CON + 9) <= '1';
               end if;
            end if;
         end if;

         if con_in_valid = '1' and in_count_v < 2048 then
            in_q_v((in_head_v + in_count_v) mod 2048) := con_in_data;
            in_count_v                                := in_count_v + 1;
         end if;

         -- A start empties the buffer.
         hold_d <= hold;
         if hold_d = '1' and hold = '0' then
            in_count_v := 0;
         end if;
         free <= std_logic_vector(to_unsigned(2048 - in_count_v, 16));

         if con_valid = '1' and con_ready = '1' then
            out_head  <= (out_head + 1) mod 256;
            out_count <= out_count - 1;
         end if;
         if push_v then
            out_q((out_head + out_count) mod 256) <= dbus_data_out(7 downto 0);
            if con_valid = '1' and con_ready = '1' then
               out_count <= out_count;
            else
               out_count <= out_count + 1;
            end if;
         end if;

         if rst = '1' then
            in_count_v := 0;
            out_count  <= 0;
         end if;
      end if;
   end process p_con;

   slave_stall(C_CON) <= '0';
   con_valid          <= '1' when out_count /= 0 else '0';
   con_data           <= out_q(out_head);


   i_debug_link : entity work.debug_link
      generic map (
         G_TIMEOUT   => C_TIMEOUT,
         G_HAS_ROM   => false,
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
         tx_ready_i     => '1',
         tx_data_o      => tx_data,
         con_valid_i    => con_valid,
         con_ready_o    => con_ready,
         con_data_i     => con_data,
         con_in_valid_o => con_in_valid,
         con_in_data_o  => con_in_data,
         free_i         => free,
         eoi_o          => eoi,
         hold_o         => hold,
         rom_hide_o     => open,
         clear_o        => open,
         clear_done_i   => '0',
         halted_i       => halted,
         halt_reason_i  => halt_reason,
         regs_i         => regs_flat,
         wb_cyc_o       => link_cyc,
         wb_stb_o       => link_stb,
         wb_stall_i     => link_stall,
         wb_ack_i       => link_ack,
         wb_we_o        => link_we,
         wb_addr_o      => link_addr,
         wb_data_o      => link_data_out,
         wb_data_i      => dbus_data_in
      ); -- i_debug_link


   p_mon : process (clk)
   begin
      if rising_edge(clk) then
         if tx_valid = '1' then
            got(got_len + 1) <= character'val(to_integer(unsigned(tx_data)));
            got_len          <= got_len + 1;
         end if;
      end if;
   end process p_mon;


   -- A run that hangs fails, with what the link sent so far.
   p_watchdog : process
   begin
      wait for 5 ms;
      report "tb_link: no end after 5 ms; the link sent [" & got(1 to got_len) & "]" &
             ", rx_ready " & std_logic'image(rx_ready) & ", hold " & std_logic'image(hold) &
             ", halted " & std_logic'image(halted)
         severity error;
      stop(1);
   end process p_watchdog;


   p_test : process
      variable used_v : natural := 0;

      procedure fail(msg : string) is
      begin
         report "tb_link: " & msg
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
         while got_len < used_v + s'length and n_v < 100000 loop
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
               fail(what & ": got [" & got(used_v + 1 to used_v + s'length) & "], not [" & s & "]");
            end if;
         end loop;
         used_v := used_v + s'length;
      end procedure expect;

      -- Checks that the link sends nothing more.
      procedure quiet(what : string) is
      begin
         cycles(3 * C_TIMEOUT);
         if got_len /= used_v then
            fail(what & ": unexpected bytes [" & got(used_v + 1 to got_len) & "]");
         end if;
      end procedure quiet;

      -- The checksum of DEBUG.md §2, as two hex digits.
      function cc(s : string) return string is
         variable sum_v : natural := 0;
      begin
         for i in s'range loop
            sum_v := (sum_v + character'pos(s(i))) mod 256;
         end loop;
         return to_hstring(std_logic_vector(to_unsigned(sum_v, 8)));
      end function cc;

      -- The W that loads G_PROG_FILE from address 0, and the number of
      -- words. The file holds the words 0 to n - 1, one per line, in order.
      procedure load(n : out natural) is
         file     f      : text;
         variable l      : line;
         variable addr_v : std_logic_vector(31 downto 0);
         variable data_v : std_logic_vector(31 downto 0);
         variable body_v : line;
         variable n_v    : natural := 0;
      begin
         file_open(f, G_PROG_FILE, read_mode);
         while not endfile(f) loop
            readline(f, l);
            if l'length > 0 then
               hread(l, addr_v);
               hread(l, data_v);
               if to_integer(unsigned(addr_v)) /= n_v then
                  fail("the program's words are not in order from 0");
               end if;
               write(body_v, to_hstring(data_v));
               n_v := n_v + 1;
            end if;
            deallocate(l);
         end loop;
         file_close(f);
         send(C_ESC & "W00000000" & to_hstring(std_logic_vector(to_unsigned(n_v, 16))) & body_v.all &
              "#" & cc("W00000000" & to_hstring(std_logic_vector(to_unsigned(n_v, 16))) & body_v.all));
         deallocate(body_v);
         n := n_v;
      end procedure load;

      variable words_v : natural;

   begin
      cycles(3);
      rst <= '0';

      expect(C_ESC & "b01#C3", "b01");

      -- DEBUG.md §8, through the decoder to the memory model
      send(C_ESC & "W0000010000021122334455667788#E2");
      expect(C_ESC & "k000001000002#AE", "W of §8");
      send(C_ESC & "R000001000001#94");
      expect(C_ESC & "r00000100000111223344#48", "R of §8");

      -- A word that the memory model loaded
      send(C_ESC & "R001000000001#94");
      expect(C_ESC & "r0010000000010000600D#4E", "a loaded word");

      -- The math unit: A = 6, B = 7, and SMUL_LO = 42
      send(C_ESC & "WFFFFFF2000020000000600000007#2C");
      expect(C_ESC & "kFFFFFF200002#33", "W to the math unit");
      send(C_ESC & "RFFFFFF220001#1B");
      expect(C_ESC & "rFFFFFF2200010000002A#CE", "R of SMUL_LO");

      -- The link's writes to the console and the read counter are ignored,
      -- and its reads return 0.
      send(C_ESC & "WFFFFFF00000200000041000000AA#44");
      expect(C_ESC & "kFFFFFF000002#31", "W to the console");
      send(C_ESC & "RFFFFFF000002#18");
      expect(C_ESC & "rFFFFFF0000020000000000000000#38", "R of the console");

      -- The program, and the start: bit 0 from 1 to 0, bit 3 at 1
      load(words_v);
      if words_v /= 15 then
         fail("linkecho.bin has " & integer'image(words_v) & " words, not 15");
      end if;
      expect(C_ESC & "k00000000000F#C1", "load");
      send(C_ESC & "WFFFFFFF0000100000008#BA");
      expect(C_ESC & "kFFFFFFF00001#46", "start");

      -- The echo: the program sees no byte that the link wrote before.
      send("Hi" & C_ESC & C_ESC);
      expect("Hi" & C_ESC & C_ESC, "echo");

      -- While it runs: e02 for memory, and the control register
      send(C_ESC & "R000001000001#94");
      expect(C_ESC & "e5202#2E", "e02");
      send(C_ESC & "RFFFFFFF00002#2E");
      expect(C_ESC & "rFFFFFFF000020000000800000000#56", "running");

      -- A UART break ends the input, and the program halts. R1 = 0x200,
      -- R2 = 3 bytes echoed.
      wait until rising_edge(clk);
      rx_break <= '1';
      wait until rising_edge(clk);
      rx_break <= '0';
      expect(C_ESC & "h01#C9", "halt");
      send(C_ESC & "RFFFFFFE10002#2E");
      expect(C_ESC & "rFFFFFFE100020000020000000003#53", "registers after the halt");
      send(C_ESC & "RFFFFFFF00002#2E");
      expect(C_ESC & "rFFFFFFF000020000000A00000001#60", "halted");

      -- The restart of DEBUG.md §8: hold, then start
      send(C_ESC & "WFFFFFFF0000100000009#BB");
      expect(C_ESC & "kFFFFFFF00001#46", "hold after the halt");
      send(C_ESC & "RFFFFFFF00002#2E");
      expect(C_ESC & "rFFFFFFF000020000000B00000001#61", "held after the halt");
      send(C_ESC & "WFFFFFFF0000100000008#BA");
      expect(C_ESC & "kFFFFFFF00001#46", "restart");
      send("A");
      expect("A", "echo after the restart");

      -- A hold while the program runs, with no notice
      send(C_ESC & "WFFFFFFF0000100000009#BB");
      expect(C_ESC & "kFFFFFFF00001#46", "hold while running");
      send(C_ESC & "RFFFFFFF00002#2E");
      expect(C_ESC & "rFFFFFFF000020000000900000000#57", "held");
      quiet("after the hold");

      report "tb_link: pass";
      stop(0);
   end process p_test;

end architecture simulation;
