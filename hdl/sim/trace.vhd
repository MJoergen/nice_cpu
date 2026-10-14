-- Simulation-only trace writer. It prints the core's steps in the format of
-- "niceemu --trace" (emulator/README.md, Trace format), so that the two
-- outputs can be compared with diff.
--
-- THEORY OF OPERATION
-- Everything goes to one file, in this order within a cycle: the console
-- byte, then the step's trace line. A console byte is added to the current
-- line, and a newline byte ends it, so console output is mixed in with the
-- trace lines exactly as the emulator mixes them. The emulator writes the
-- byte while it runs the storing instruction, and its trace line after.
--
-- The writer keeps the register values of the step before, and a trace line
-- lists R0-R14 where they differ. R15 is listed after an interrupt entry, and
-- after an instruction only when it is not the address after the
-- instruction's constant words. The writer works that address out from the
-- instruction word itself, as the emulator does, rather than trusting the
-- core's.
--
-- When a step halts the processor, or the step count reaches G_MAX_STEPS,
-- the writer prints the "Halted" or "Stopped" line and the registers, as the
-- emulator does at the end of a run. Then it closes the file, raises done_o,
-- and sets status_o to the emulator's exit status: 0 after HALT, 2 after the
-- other halts, and 3 at the step limit.
--
-- After the "Halted" or "Stopped" line it prints a "Pending:" line for the
-- interrupt requests that were never taken, as the emulator does. They are
-- the requests that the pending inputs show in the cycle of the last step.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) retire_i follows the contracts in src/trace_pkg.vhd.
-- b) console_valid_i is '1' for one cycle per byte, in the cycle the data
--    bus accepts the store (sim/wb_mem.vhd).
-- c) nmi_pending_i and irq_pending_i are '1' while a request of that kind is
--    held and not yet taken, with its vector on nmi_vector_i or irq_vector_i.
--
-- RESET
-- Nothing is written while rst_i is '1'. Reset does not clear the step count
-- or the register values: the trace covers one run from the first reset.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;
   use std.textio.all;

   use work.trace_pkg.all;

entity trace is
   generic (
      G_FILE_NAME : string;
      -- False prints only the console output and the end of the run, as
      -- niceemu does without --trace.
      G_TRACE     : boolean  := true;
      -- The emulator's default for -n.
      G_MAX_STEPS : positive := 100_000_000
   );
   port (
      clk_i           : in  std_logic;
      rst_i           : in  std_logic;
      retire_i        : in  t_retire;
      console_valid_i : in  std_logic;
      console_data_i  : in  std_logic_vector(7 downto 0);
      nmi_pending_i   : in  std_logic                    := '0';
      nmi_vector_i    : in  std_logic_vector(7 downto 0) := X"00";
      irq_pending_i   : in  std_logic                    := '0';
      irq_vector_i    : in  std_logic_vector(7 downto 0) := X"00";
      done_o          : out std_logic := '0';
      status_o        : out natural   := 0
   );
end entity trace;

architecture simulation of trace is

   -- Lower-case hex, as the emulator prints it.
   function hex(v : std_logic_vector) return string is
      constant C_DIGITS : string(1 to 16) := "0123456789abcdef";
      constant C_LEN    : natural         := (v'length + 3) / 4;
      variable padded_v : std_logic_vector(C_LEN * 4 - 1 downto 0);
      variable res_v    : string(1 to C_LEN);
   begin
      padded_v := (others => '0');
      padded_v(v'length - 1 downto 0) := v;

      for i in 0 to C_LEN - 1 loop
         res_v(C_LEN - i) := C_DIGITS(to_integer(padded_v(i * 4 + 3 downto i * 4)) + 1);
      end loop;

      return res_v;
   end function hex;

   -- The address after the instruction iw at addr and its constant words
   -- (ISA.md §2.3). Control instructions (bits 27..26 = 11) have none.
   function next_pc(addr : std_logic_vector(31 downto 0);
                    iw   : std_logic_vector(31 downto 0)) return std_logic_vector is
      variable len_v : natural range 1 to 4 := 1;
   begin
      if iw(27 downto 26) /= "11" then
         for i in 0 to 2 loop
            if iw(i * 7 + 5 downto i * 7 + 4) = "11" then
               len_v := len_v + 1;
            end if;
         end loop;
      end if;

      return addr + len_v;
   end function next_pc;

begin

   p_trace : process
      file     tf       : text;
      variable l        : line;                 -- Console output and the trace
      variable step_l   : line;                 -- The trace line of one step
      variable before_v : t_regs  := C_REGS_RESET;
      variable steps_v  : natural := 0;
      variable status_v : natural;
      variable halt_v   : t_halt;
   begin
      file_open(tf, G_FILE_NAME, write_mode);

      main_loop : loop
         wait until rising_edge(clk_i);

         if rst_i = '0' and console_valid_i = '1' then
            if console_data_i = X"0A" then
               writeline(tf, l);
            else
               write(l, character'val(to_integer(console_data_i)));
            end if;
         end if;

         if rst_i = '0' and retire_i.valid = '1' then
            steps_v := steps_v + 1;
            halt_v  := HALT_NONE;

            if retire_i.intr = '1' then
               if retire_i.nmi = '1' then
                  write(step_l, string'("NMI "));
               else
                  write(step_l, string'("IRQ "));
               end if;
               -- Padded to the width of "pppppppp iiiiiiii", so that the
               -- changes line up with those of the instruction lines.
               write(step_l, hex(retire_i.vector) & "           ");
            else
               write(step_l, hex(retire_i.addr) & " " & hex(retire_i.iw));
            end if;

            if retire_i.intr = '0' and retire_i.skipped = '1' then
               write(step_l, string'(" skipped"));
               before_v(15) := next_pc(retire_i.addr, retire_i.iw);
            else
               for i in 0 to 14 loop
                  if retire_i.regs(i) /= before_v(i) then
                     write(step_l, " R" & integer'image(i) & "=" & hex(retire_i.regs(i)));
                  end if;
               end loop;

               if retire_i.intr = '1' or
                  retire_i.regs(15) /= next_pc(retire_i.addr, retire_i.iw) then
                  write(step_l, " R15=" & hex(retire_i.regs(15)));
               end if;

               if retire_i.intr = '0' and retire_i.mem_we = '1' then
                  write(step_l, " [" & hex(retire_i.mem_addr) & "]=" & hex(retire_i.mem_data));
               end if;

               if retire_i.intr = '0' then
                  halt_v := retire_i.halt;
               end if;
               if halt_v /= HALT_NONE then
                  write(step_l, " " & halt_text(halt_v));
               end if;

               before_v := retire_i.regs;
            end if;

            -- Without G_TRACE, only the console output stays in l.
            if G_TRACE then
               write(l, step_l.all);
               writeline(tf, l);
            end if;
            deallocate(step_l);

            if halt_v /= HALT_NONE then
               write(l, "Halted (" & halt_text(halt_v) & ") after " &
                        integer'image(steps_v) & " steps, PC=" & hex(before_v(15)));
               status_v := 0 when halt_v = HALT_HALT else 2;
               exit main_loop;
            elsif steps_v = G_MAX_STEPS then
               write(l, "Stopped at the step limit after " & integer'image(steps_v) &
                        " steps, PC=" & hex(before_v(15)));
               status_v := 3;
               exit main_loop;
            end if;
         end if;
      end loop main_loop;

      writeline(tf, l);

      if nmi_pending_i = '1' or irq_pending_i = '1' then
         write(l, string'("Pending:"));
         if nmi_pending_i = '1' then
            write(l, " NMI " & hex(nmi_vector_i));
         end if;
         if irq_pending_i = '1' then
            write(l, " IRQ " & hex(irq_vector_i));
         end if;
         writeline(tf, l);
      end if;

      for i in 0 to 15 loop
         write(l, "R" & integer'image(i));
         if i < 10 then
            write(l, string'(" "));
         end if;
         write(l, " " & hex(before_v(i)));
         if i mod 4 = 3 then
            writeline(tf, l);
         else
            write(l, string'(" "));
         end if;
      end loop;

      file_close(tf);
      status_o <= status_v;
      done_o   <= '1';
      wait;
   end process p_trace;

end architecture simulation;
