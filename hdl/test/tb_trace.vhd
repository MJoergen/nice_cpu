-- A test of the trace writer and the memory model, before there is a core.
--
-- THEORY OF OPERATION
-- The process p_core stands in for the core and runs test/trace.nasm, with
-- an NMI at step 5. For each step it fetches the instruction word through
-- the instruction bus, makes the step's data accesses on the data bus, and
-- reports the step to sim/trace.vhd. The register values and memory writes
-- of each step are written out by hand below, from the comments in
-- trace.nasm. The Makefile compares the output with that of
-- "niceemu --nmi 5:0x20" on the same program, with and without -t, and
-- with the step limits that G_MAX_STEPS sets.
--
-- So the instruction words, the console bytes, and the vector come from the
-- memory model, and the format comes from the trace writer. Only the effects
-- of each instruction are given here.

library ieee;
   use ieee.std_logic_1164.all;

   use std.env.all;

   use work.trace_pkg.all;

entity tb_trace is
   generic (
      G_BIN_FILE   : string;
      G_TRACE_FILE : string;
      G_TRACE      : boolean  := true;
      G_MAX_STEPS  : positive := 100_000_000
   );
end entity tb_trace;

architecture simulation of tb_trace is

   signal clk : std_logic;
   signal rst : std_logic;

   signal ibus_cyc   : std_logic := '0';
   signal ibus_stb   : std_logic := '0';
   signal ibus_stall : std_logic;
   signal ibus_ack   : std_logic;
   signal ibus_addr  : std_logic_vector(30 downto 0) := (others => '0');
   signal ibus_data  : std_logic_vector(63 downto 0);

   signal dbus_cyc      : std_logic := '0';
   signal dbus_stb      : std_logic := '0';
   signal dbus_stall    : std_logic;
   signal dbus_ack      : std_logic;
   signal dbus_we       : std_logic := '0';
   signal dbus_addr     : std_logic_vector(31 downto 0) := (others => '0');
   signal dbus_data_out : std_logic_vector(31 downto 0);
   signal dbus_data_in  : std_logic_vector(31 downto 0);

   signal console_valid : std_logic;
   signal console_data  : std_logic_vector(7 downto 0);

   signal retire : t_retire := C_RETIRE_NONE;
   signal done   : std_logic;
   signal status : natural;

begin

   p_clk : process
   begin
      clk <= '1', '0' after 5 ns;
      wait for 10 ns;
   end process p_clk;


   p_rst : process
   begin
      rst <= '1';
      wait for 100 ns;
      wait until rising_edge(clk);
      rst <= '0';
      wait;
   end process p_rst;


   i_wb_mem : entity work.wb_mem
      generic map (
         G_INIT_FILE => G_BIN_FILE
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


   i_trace : entity work.trace
      generic map (
         G_FILE_NAME => G_TRACE_FILE,
         G_TRACE     => G_TRACE,
         G_MAX_STEPS => G_MAX_STEPS
      )
      port map (
         clk_i           => clk,
         rst_i           => rst,
         retire_i        => retire,
         console_valid_i => console_valid,
         console_data_i  => console_data,
         done_o          => done,
         status_o        => status
      ); -- i_trace


   p_core : process
      variable regs_v : t_regs := C_REGS_RESET;
      variable iw_v   : std_logic_vector(31 downto 0);
      variable data_v : std_logic_vector(31 downto 0);
      variable step_v : t_retire;

      -- One Wishbone read on the instruction bus, of the pair that holds the
      -- word at addr. It keeps that word.
      procedure fetch(addr : std_logic_vector(31 downto 0)) is
      begin
         ibus_cyc  <= '1';
         ibus_stb  <= '1';
         ibus_addr <= addr(31 downto 1);
         wait until rising_edge(clk) and ibus_stall = '0';
         ibus_stb  <= '0';
         wait until rising_edge(clk) and ibus_ack = '1';
         ibus_cyc  <= '0';
         if addr(0) = '1' then
            iw_v := ibus_data(63 downto 32);
         else
            iw_v := ibus_data(31 downto 0);
         end if;
      end procedure fetch;

      -- One Wishbone access on the data bus. A read leaves its data in data_v.
      procedure access_data(we   : std_logic;
                            addr : std_logic_vector(31 downto 0);
                            data : std_logic_vector(31 downto 0)) is
      begin
         dbus_cyc      <= '1';
         dbus_stb      <= '1';
         dbus_we       <= we;
         dbus_addr     <= addr;
         dbus_data_out <= data;
         wait until rising_edge(clk) and dbus_stall = '0';
         dbus_stb      <= '0';
         wait until rising_edge(clk) and dbus_ack = '1';
         dbus_cyc      <= '0';
         data_v        := dbus_data_in;
      end procedure access_data;

      -- Report a step for one cycle.
      procedure report_step(step : t_retire) is
      begin
         retire       <= step;
         retire.valid <= '1';
         wait until rising_edge(clk);
         retire.valid <= '0';
      end procedure report_step;

      -- An instruction at addr, leaving the registers at regs_v. A store,
      -- if any, goes on the data bus before the step is reported.
      procedure instruction(addr     : std_logic_vector(31 downto 0);
                            skipped  : std_logic                     := '0';
                            mem_we   : std_logic                     := '0';
                            mem_addr : std_logic_vector(31 downto 0) := X"00000000";
                            mem_data : std_logic_vector(31 downto 0) := X"00000000";
                            halt     : t_halt                        := HALT_NONE) is
      begin
         fetch(addr);
         if mem_we = '1' then
            access_data('1', mem_addr, mem_data);
         end if;
         step_v          := C_RETIRE_NONE;
         step_v.addr     := addr;
         step_v.iw       := iw_v;
         step_v.skipped  := skipped;
         step_v.regs     := regs_v;
         step_v.mem_we   := mem_we;
         step_v.mem_addr := mem_addr;
         step_v.mem_data := mem_data;
         step_v.halt     := halt;
         report_step(step_v);
      end procedure instruction;

   begin
      wait until rising_edge(clk) and rst = '0';

      -- 0: MOVE @0x50, 7
      regs_v(15) := X"00000003";
      instruction(X"00000000", mem_we => '1', mem_addr => X"00000050", mem_data => X"00000007");

      -- 1: MOVE @CONSOLE, 0x48
      regs_v(15) := X"00000006";
      instruction(X"00000003", mem_we => '1', mem_addr => X"FFFFFF00", mem_data => X"00000048");

      -- 2: MOVE R15, skip
      regs_v(15) := X"00000009";
      instruction(X"00000006");

      -- 3: ?Z MOVE R1, 1, skipped. Only R15 changes.
      regs_v(15) := X"0000000B";
      instruction(X"00000009", skipped => '1');

      -- 4: DEC[M] R2, R2: 0 - 1 sets X, C, and N.
      regs_v(2)  := X"FFFFFFFF";
      regs_v(14) := X"17000000";
      regs_v(15) := X"0000000C";
      instruction(X"0000000B");

      -- 5: NMI 0x20. Entry reads the vector at VBASE * 256 + 0x20 on the data
      -- bus, sets I, and jumps (ISA.md §7.2).
      access_data('0', X"00000020", X"00000000");
      regs_v(14) := X"97000000";
      regs_v(15) := data_v;
      step_v        := C_RETIRE_NONE;
      step_v.intr   := '1';
      step_v.nmi    := '1';
      step_v.vector := X"20";
      step_v.regs   := regs_v;
      report_step(step_v);

      -- 6: MOVE @CONSOLE, 10
      regs_v(15) := X"00000024";
      instruction(X"00000021", mem_we => '1', mem_addr => X"FFFFFF00", mem_data => X"0000000A");

      -- 7: INT 0, inside the NMI routine
      regs_v(15) := X"00000025";
      instruction(X"00000024", halt => HALT_NESTED_INT);
      wait;
   end process p_core;


   -- The trace writer may stop the run before p_core has finished, at
   -- G_MAX_STEPS.
   p_finish : process
   begin
      wait until done = '1';
      stop(status);
   end process p_finish;


   p_watchdog : process
   begin
      wait for 100 us;
      report "tb_trace: the trace writer did not finish"
         severity failure;
   end process p_watchdog;

end architecture simulation;
