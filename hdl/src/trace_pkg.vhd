-- The interface between the core and the trace writer, sim/trace.vhd.
--
-- THEORY OF OPERATION
-- The core reports each step as it retires it, in a t_retire. A step is one
-- instruction, skipped or not, or the entry into an interrupt (ISA.md §7.2),
-- as in the emulator. The report carries the register values after the step,
-- not the register writes. The trace writer keeps the values of the step
-- before and prints the registers whose values differ, which is what
-- "niceemu --trace" prints. So the core need not count or order its register
-- writes, and a write of an unchanged value prints nothing, as in the
-- emulator.
--
-- A step makes at most one memory write: the destination of an instruction.
-- An interrupt entry saves PC and SR in hidden registers, not in memory.
--
-- INTERFACE CONTRACTS -- these are requirements on the core:
-- a) valid is '1' for one cycle per step, in program order.
-- b) regs holds R0-R15 as getReg would read them: R0 is 0, and bit 24 of R14
--    is 1 (ISA.md §4.3).
-- c) For a skipped instruction, regs holds the values before the step, with
--    R15 at the address after the instruction's constant words. mem_we is
--    '0' and halt is HALT_NONE. The trace writer prints any departure, so
--    that the comparison with the emulator fails.
-- d) For an interrupt entry, addr, iw, skipped, the memory write, and halt are
--    not used.
-- e) A store to the console is accepted on the data bus no later than the
--    cycle its instruction is reported, so that its byte comes before its
--    trace line, as in the emulator.

library ieee;
   use ieee.std_logic_1164.all;

package trace_pkg is

   -- The reasons for a halt, as in emulator/src/cpu.zig.
   type t_halt is (
      HALT_NONE,
      HALT_HALT,
      HALT_RESERVED,
      HALT_NESTED_INT,
      HALT_RTI_OUTSIDE_ISR
   );

   type t_regs is array (0 to 15) of std_logic_vector(31 downto 0);

   type t_retire is record
      valid    : std_logic;
      intr     : std_logic;                       -- An interrupt entry, not an instruction
      nmi      : std_logic;                       -- For an interrupt: NMI, not IRQ
      vector   : std_logic_vector(7 downto 0);    -- For an interrupt
      addr     : std_logic_vector(31 downto 0);   -- Address of the instruction word
      iw       : std_logic_vector(31 downto 0);   -- The instruction word
      skipped  : std_logic;                       -- The condition was false
      regs     : t_regs;                          -- R0-R15 after the step
      mem_we   : std_logic;                       -- The step wrote memory
      mem_addr : std_logic_vector(31 downto 0);
      mem_data : std_logic_vector(31 downto 0);
      halt     : t_halt;                          -- The step halted the processor
   end record t_retire;

   -- The register values after reset (ISA.md §8.1).
   constant C_REGS_RESET : t_regs := (14 => X"01000000", others => (others => '0'));

   constant C_RETIRE_NONE : t_retire := (
      valid    => '0',
      intr     => '0',
      nmi      => '0',
      vector   => (others => '0'),
      addr     => (others => '0'),
      iw       => (others => '0'),
      skipped  => '0',
      regs     => C_REGS_RESET,
      mem_we   => '0',
      mem_addr => (others => '0'),
      mem_data => (others => '0'),
      halt     => HALT_NONE
   );

   -- The text the emulator prints for each reason.
   function halt_text(halt : t_halt) return string;

end package trace_pkg;

package body trace_pkg is

   function halt_text(halt : t_halt) return string is
   begin
      case halt is
         when HALT_NONE            => return "running";
         when HALT_HALT            => return "HALT";
         when HALT_RESERVED        => return "reserved control instruction";
         when HALT_NESTED_INT      => return "INT inside an interrupt routine";
         when HALT_RTI_OUTSIDE_ISR => return "RTI outside an interrupt routine";
      end case;
   end function halt_text;

end package body trace_pkg;
