-- A simple multi-cycle NICE core. It runs one step at a time: either one
-- instruction, or the entry into an interrupt (ISA.md §5, §7). It is a
-- reference for the pipelined core of doc/MICROARCH.md, not a replacement.
--
-- THEORY OF OPERATION
-- A state machine follows the steps of ISA.md §5 in order:
--
--   BOUNDARY  Take a pending NMI or IRQ (ISA.md §7.1), or start an
--             instruction.
--   FETCH     Read the instruction word, then each constant word, through
--             the instruction bus. Each read increments R15.
--   COND      Test the condition. Run a control instruction.
--   SRC       Evaluate s0, then s1, with their side effects. A memory
--             operand is read through the data bus.
--   MOD33     For C<C and C>C only, reduce the count mod 33.
--   EXEC      Compute the result, write the destination, apply its side
--             effect, and update the flags. A memory destination is written
--             through the data bus.
--   DEST_ADJ  For a register destination with mode 001 or 010 only, step
--             the register after the result, so that the step is not in
--             series with the ALU.
--   VEC       Read the vector table entry, for IRQ, NMI, and INT.
--   RETIRE    Report the step on retire_o, and an instruction on
--             instret_o.
--
-- The instruction bus is 64 bits wide, as MICROARCH.md §1 requires of both
-- cores. A read returns the aligned pair of words 2a and 2a + 1 for the pair
-- address a, the lower word in bits 31..0. The core reads one pair per word
-- it needs, at bits 31..1 of R15, and keeps the half that bit 0 selects.
--
-- Each bus access is one pipelined Wishbone transaction, and the core waits
-- for its ACK before it moves on. So the data accesses happen exactly once
-- and in program order, as ISA.md §8.2 requires, and a store always takes
-- effect before the next instruction is fetched.
--
-- The registers are flip-flops. R0 is held at 0 and bit 24 of R14 at 1:
-- every write goes through set_reg, which applies the rules of ISA.md §4.3.
-- So every read sees the register as getReg in the emulator would.
--
-- Interrupt requests use valid/ready ports. A device holds valid and the
-- vector until the core raises ready, which it does for one cycle in the
-- BOUNDARY state when it takes the request.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) The bus slaves acknowledge every request.
-- b) A device holds nmi_valid_i or irq_valid_i, and the vector, stable until
--    the core raises the matching ready.
-- c) nmi_ready_o and irq_ready_o depend combinationally on nmi_valid_i and
--    irq_valid_i, so a device must not make valid depend combinationally on
--    ready.
--
-- RESET
-- Synchronous. It sets the state of ISA.md §8.1 and drops any bus request.
-- Memory is not changed.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use work.nice_pkg.all;
   use work.trace_pkg.all;

entity multicycle is
   generic (
      -- Adds the invariants that formal/multicycle.sby needs.
      G_FORMAL : boolean := false
   );
   port (
      clk_i        : in  std_logic;
      rst_i        : in  std_logic;

      -- Instruction bus: read only
      ibus_cyc_o   : out std_logic                     := '0';
      ibus_stb_o   : out std_logic                     := '0';
      ibus_stall_i : in  std_logic;
      ibus_ack_i   : in  std_logic;
      ibus_addr_o  : out std_logic_vector(30 downto 0) := (others => '0');
      ibus_data_i  : in  std_logic_vector(63 downto 0);

      -- Data bus: read and write
      dbus_cyc_o   : out std_logic                     := '0';
      dbus_stb_o   : out std_logic                     := '0';
      dbus_stall_i : in  std_logic;
      dbus_ack_i   : in  std_logic;
      dbus_we_o    : out std_logic                     := '0';
      dbus_addr_o  : out std_logic_vector(31 downto 0) := (others => '0');
      dbus_data_o  : out std_logic_vector(31 downto 0) := (others => '0');
      dbus_data_i  : in  std_logic_vector(31 downto 0);

      -- Interrupt requests
      nmi_valid_i  : in  std_logic;
      nmi_ready_o  : out std_logic;
      nmi_vector_i : in  std_logic_vector(7 downto 0);
      irq_valid_i  : in  std_logic;
      irq_ready_o  : out std_logic;
      irq_vector_i : in  std_logic_vector(7 downto 0);

      -- '1' once the core has halted (ISA.md §1.4)
      halted_o     : out std_logic;

      -- '1' for one cycle when an instruction completes, but not an
      -- interrupt entry, for the instruction counter (SYSTEM.md §3)
      instret_o    : out std_logic;

      -- One report per step, for sim/trace.vhd
      retire_o     : out t_retire
   );
end entity multicycle;

architecture synthesis of multicycle is

   type t_state is (
      BOUNDARY_ST,
      FETCH_ST,
      FETCH_WAIT_ST,
      COND_ST,
      SRC_ST,
      SRC_WAIT_ST,
      MOD33_ST,
      EXEC_ST,
      DEST_ADJ_ST,
      DEST_WAIT_ST,
      VEC_ST,
      VEC_WAIT_ST,
      RETIRE_ST,
      HALTED_ST
   );

   type t_consts is array (0 to 2) of std_logic_vector(31 downto 0);

   procedure set_reg(regs : inout t_regs;
                     x    : natural range 0 to 15;
                     v    : std_logic_vector(31 downto 0)) is
   begin
      regs(x) := regval(x, v);
   end procedure set_reg;

   signal state : t_state;
   signal regs  : t_regs;

   -- Hidden state (ISA.md §1.4)
   signal in_service : std_logic;
   signal after_rti  : std_logic;
   signal saved_pc   : std_logic_vector(31 downto 0);
   signal saved_sr   : std_logic_vector(31 downto 0);
   signal halt       : t_halt;

   -- The current instruction
   signal iw         : std_logic_vector(31 downto 0);
   signal consts     : t_consts;
   signal fetch_iw   : std_logic;                       -- FETCH reads the instruction word
   signal fetch_need : std_logic_vector(0 to 2);        -- Constant words still to read
   signal src_idx    : natural range 1 to 2;            -- The source field in SRC
   signal srcs       : t_consts;                        -- The source values, at 1 and 2
   signal src2_count : t_shift_count;                   -- shift_count(srcs(2))
   signal int_vector : std_logic_vector(7 downto 0);

   -- The step being reported
   signal rep_intr    : std_logic;
   signal rep_nmi     : std_logic;
   signal rep_addr    : std_logic_vector(31 downto 0);
   signal rep_skipped : std_logic;
   signal rep_mem_we  : std_logic;

   signal take_nmi : boolean;
   signal take_irq : boolean;

begin

   -- ISA.md §7.1. NMI goes first.
   take_nmi <= state = BOUNDARY_ST and rst_i = '0' and nmi_valid_i = '1' and
               in_service = '0' and after_rti = '0';
   take_irq <= state = BOUNDARY_ST and rst_i = '0' and irq_valid_i = '1' and
               in_service = '0' and after_rti = '0' and regs(14)(C_SR_E) = '1' and not take_nmi;

   nmi_ready_o <= '1' when take_nmi else '0';
   irq_ready_o <= '1' when take_irq else '0';

   halted_o  <= '1' when state = HALTED_ST else '0';
   instret_o <= '1' when state = RETIRE_ST and rep_intr = '0' else '0';


   p_fsm : process (clk_i)
      variable regs_v : t_regs;
      variable sr_v   : std_logic_vector(31 downto 0);
      variable f_v    : std_logic_vector(6 downto 0);
      variable x_v    : natural range 0 to 15;
      variable addr_v : std_logic_vector(31 downto 0);
      variable need_v : std_logic_vector(0 to 2);
      variable word_v : std_logic_vector(31 downto 0);
      variable res_v  : t_result;

      -- Start a data bus access.
      procedure dbus_start(we   : std_logic;
                           addr : std_logic_vector(31 downto 0);
                           data : std_logic_vector(31 downto 0)) is
      begin
         dbus_cyc_o  <= '1';
         dbus_stb_o  <= '1';
         dbus_we_o   <= we;
         dbus_addr_o <= addr;
         dbus_data_o <= data;
      end procedure dbus_start;

      -- Read the constant word of the first field in need, or go on to the
      -- condition.
      procedure fetch_next(need : std_logic_vector(0 to 2)) is
      begin
         fetch_need <= need;
         state      <= FETCH_ST when need /= "000" else COND_ST;
      end procedure fetch_next;

      -- The value of source i is known.
      procedure src_done(i : natural range 1 to 2;
                         v : std_logic_vector(31 downto 0)) is
      begin
         srcs(i) <= v;
         if i = 2 then
            -- The reduced counts of a shift. mod 33 is slow, and gets
            -- MOD33_ST of its own.
            src2_count.sat <= 33 when v > 33 else to_integer(v(5 downto 0));
            src2_count.nz  <= '1' when v /= 0 else '0';
         end if;
         if i = 1 then
            src_idx <= 2;
            state   <= SRC_ST;
         elsif iw(27) = '1' and iw(23 downto 21) = "101" then
            state <= MOD33_ST;
         else
            state <= EXEC_ST;
         end if;
      end procedure src_done;

   begin
      if rising_edge(clk_i) then
         regs_v := regs;

         -- Wishbone: a request is accepted when STALL is low.
         if ibus_stall_i = '0' then
            ibus_stb_o <= '0';
         end if;
         if dbus_stall_i = '0' then
            dbus_stb_o <= '0';
         end if;

         case state is
            when BOUNDARY_ST =>
               rep_intr    <= '0';
               rep_skipped <= '0';
               rep_mem_we  <= '0';
               rep_addr    <= regs(15);
               if take_nmi then
                  rep_intr   <= '1';
                  rep_nmi    <= '1';
                  int_vector <= nmi_vector_i;
                  state      <= VEC_ST;
               elsif take_irq then
                  rep_intr   <= '1';
                  rep_nmi    <= '0';
                  int_vector <= irq_vector_i;
                  state      <= VEC_ST;
               else
                  fetch_iw <= '1';
                  state    <= FETCH_ST;
               end if;

            -- ISA.md §5 steps 1 and 2
            when FETCH_ST =>
               ibus_cyc_o  <= '1';
               ibus_stb_o  <= '1';
               ibus_addr_o <= regs(15)(31 downto 1);
               state       <= FETCH_WAIT_ST;

            when FETCH_WAIT_ST =>
               if ibus_ack_i = '1' then
                  ibus_cyc_o <= '0';
                  if regs(15)(0) = '1' then
                     word_v := ibus_data_i(63 downto 32);
                  else
                     word_v := ibus_data_i(31 downto 0);
                  end if;
                  set_reg(regs_v, 15, regs(15) + 1);
                  if fetch_iw = '1' then
                     fetch_iw <= '0';
                     iw       <= word_v;
                     need_v   := const_fields(word_v);
                  else
                     need_v := fetch_need;
                     for i in 0 to 2 loop
                        if need_v(i) = '1' then
                           consts(i) <= word_v;
                           need_v(i) := '0';
                           exit;
                        end if;
                     end loop;
                  end if;
                  fetch_next(need_v);
               end if;

            -- ISA.md §5 steps 3 and 4
            when COND_ST =>
               -- The instruction about to run clears after_rti when it
               -- completes, unless it is an RTI, which sets it again.
               after_rti <= '0';
               src_idx   <= 1;
               state     <= SRC_ST;

               if condition(iw, regs(14)) = '0' then
                  rep_skipped <= '1';
                  state       <= RETIRE_ST;
               elsif iw(27 downto 26) = "11" then
                  state <= RETIRE_ST;
                  x_v := to_integer(iw(3 downto 0));
                  if ctrl_reserved(iw) then
                     halt <= HALT_RESERVED;
                  elsif ctrl_saved(iw) and in_service = '0' then
                     halt <= HALT_SAVED_OUTSIDE_ISR;
                  else
                     case iw(25 downto 21) is
                        when "00000" =>
                           halt <= HALT_HALT;

                        when "00001" =>
                           if in_service = '0' then
                              halt <= HALT_RTI_OUTSIDE_ISR;
                           else
                              set_reg(regs_v, 14, saved_sr);
                              set_reg(regs_v, 15, saved_pc);
                              in_service <= '0';
                              after_rti  <= '1';
                           end if;

                        when "00010" =>
                           if in_service = '1' then
                              halt <= HALT_NESTED_INT;
                           else
                              int_vector <= iw(7 downto 0);
                              state      <= VEC_ST;
                           end if;

                        -- The saved-state instructions. R15 already holds
                        -- the address of the next instruction.
                        when "00100" =>
                           set_reg(regs_v, x_v, saved_pc);

                        when "00101" =>
                           set_reg(regs_v, x_v, saved_sr);

                        when "00110" =>
                           saved_pc <= regs(x_v);

                        when "00111" =>
                           saved_sr <= regval(14, regs(x_v));

                        when others =>
                           halt <= HALT_RESERVED;
                     end case;
                  end if;
               end if;

            -- ISA.md §4.1 and §5 step 5
            when SRC_ST =>
               f_v := field(iw, src_idx);
               x_v := to_integer(f_v(3 downto 0));
               case f_v(6 downto 4) is
                  when "000" =>
                     src_done(src_idx, regs(x_v));
                  when "001" =>
                     set_reg(regs_v, x_v, regs(x_v) - 1);
                     src_done(src_idx, regs_v(x_v));
                  when "010" =>
                     set_reg(regs_v, x_v, regs(x_v) + 1);
                     src_done(src_idx, regs(x_v));
                  when "011" =>
                     src_done(src_idx, regs(x_v) + consts(src_idx));
                  when "100" =>
                     dbus_start('0', regs(x_v), X"00000000");
                     state <= SRC_WAIT_ST;
                  when "101" =>
                     set_reg(regs_v, x_v, regs(x_v) - 1);
                     dbus_start('0', regs_v(x_v), X"00000000");
                     state <= SRC_WAIT_ST;
                  when "110" =>
                     set_reg(regs_v, x_v, regs(x_v) + 1);
                     dbus_start('0', regs(x_v), X"00000000");
                     state <= SRC_WAIT_ST;
                  when others =>
                     dbus_start('0', regs(x_v) + consts(src_idx), X"00000000");
                     state <= SRC_WAIT_ST;
               end case;

            when SRC_WAIT_ST =>
               if dbus_ack_i = '1' then
                  dbus_cyc_o <= '0';
                  src_done(src_idx, dbus_data_i);
               end if;

            -- The count of C<C and C>C, n mod 33
            when MOD33_ST =>
               src2_count.m33 <= mod33(srcs(2));
               state          <= EXEC_ST;

            -- ISA.md §5 steps 6 to 8
            when EXEC_ST =>
               if iw(27) = '1' then
                  res_v := shift(iw(24 downto 21), srcs(1), srcs(2), regs(14)(C_SR_C),
                                 src2_count);
               else
                  res_v := alu(iw(24 downto 21), srcs(1), srcs(2), iw(26) and regs(14)(C_SR_C));
               end if;

               -- The destination (ISA.md §4.2)
               f_v   := field(iw, 0);
               x_v   := to_integer(f_v(3 downto 0));
               state <= RETIRE_ST;
               case f_v(6 downto 4) is
                  when "000" =>
                     set_reg(regs_v, x_v, res_v.r);
                  when "001" | "010" =>
                     -- The step of the register follows in DEST_ADJ_ST.
                     set_reg(regs_v, x_v, res_v.r);
                     state <= DEST_ADJ_ST;
                  when "100" =>
                     addr_v := regs_v(x_v);
                  when "101" =>
                     set_reg(regs_v, x_v, regs_v(x_v) - 1);
                     addr_v := regs_v(x_v);
                  when "110" =>
                     addr_v := regs_v(x_v);
                     set_reg(regs_v, x_v, regs_v(x_v) + 1);
                  when others =>
                     -- 011 and 111
                     addr_v := regs_v(x_v) + consts(0);
               end case;

               if f_v(6) = '1' or f_v(5 downto 4) = "11" then
                  dbus_start('1', addr_v, res_v.r);
                  rep_mem_we <= '1';
                  state      <= DEST_WAIT_ST;
               end if;

               -- The flags (ISA.md §6)
               if iw(25) = '1' and not (x_v = 14 and f_v(6 downto 4) <= "010") then
                  set_reg(regs_v, 14, flags(regs_v(14), res_v));
               end if;

            -- The step after the result, of modes 001 and 010
            when DEST_ADJ_ST =>
               f_v := field(iw, 0);
               x_v := to_integer(f_v(3 downto 0));
               if f_v(4) = '1' then
                  set_reg(regs_v, x_v, regs(x_v) - 1);
               else
                  set_reg(regs_v, x_v, regs(x_v) + 1);
               end if;
               state <= RETIRE_ST;

            when DEST_WAIT_ST =>
               if dbus_ack_i = '1' then
                  dbus_cyc_o <= '0';
                  state      <= RETIRE_ST;
               end if;

            -- ISA.md §7.2. The vector table entry is at VBASE * 256 + v.
            when VEC_ST =>
               dbus_start('0', regs(14)(23 downto 0) & int_vector, X"00000000");
               state <= VEC_WAIT_ST;

            when VEC_WAIT_ST =>
               if dbus_ack_i = '1' then
                  dbus_cyc_o <= '0';
                  saved_pc   <= regs(15);
                  saved_sr   <= regs(14);
                  in_service <= '1';
                  sr_v          := regs(14);
                  sr_v(C_SR_I)  := '1';
                  set_reg(regs_v, 14, sr_v);
                  set_reg(regs_v, 15, dbus_data_i);
                  state      <= RETIRE_ST;
               end if;

            when RETIRE_ST =>
               state <= HALTED_ST when halt /= HALT_NONE else BOUNDARY_ST;

            when HALTED_ST =>
               null;
         end case;

         regs <= regs_v;

         if rst_i = '1' then
            state      <= BOUNDARY_ST;
            regs       <= C_REGS_RESET;
            in_service <= '0';
            after_rti  <= '0';
            halt       <= HALT_NONE;
            fetch_iw   <= '0';
            ibus_cyc_o <= '0';
            ibus_stb_o <= '0';
            dbus_cyc_o <= '0';
            dbus_stb_o <= '0';
         end if;
      end if;
   end process p_fsm;


   -- The report of the step, in the cycle after it completed, when regs
   -- holds its result.
   p_retire : process (all)
   begin
      retire_o          <= C_RETIRE_NONE;
      retire_o.valid    <= '1' when state = RETIRE_ST else '0';
      retire_o.intr     <= rep_intr;
      retire_o.nmi      <= rep_nmi;
      retire_o.vector   <= int_vector;
      retire_o.addr     <= rep_addr;
      retire_o.iw       <= iw;
      retire_o.skipped  <= rep_skipped;
      retire_o.regs     <= regs;
      retire_o.mem_we   <= rep_mem_we;
      retire_o.mem_addr <= dbus_addr_o;
      retire_o.mem_data <= dbus_data_o;
      retire_o.halt     <= halt;
   end process p_retire;


   gen_formal : if G_FORMAL generate
      signal dbus_wait : boolean;
   begin
      -- The state has one of its 12 values, and each bus is busy in its
      -- wait states and only there. Without this the k-induction of
      -- formal/multicycle.sby starts from states that reset never leads
      -- to, such as a pending fetch in HALTED_ST.
      dbus_wait <= state = SRC_WAIT_ST or state = DEST_WAIT_ST or state = VEC_WAIT_ST;

      -- psl default clock is rising_edge(clk_i);

      -- psl f_state      : assert always rst_i = '0' -> state <= HALTED_ST;
      -- psl f_ibus_state : assert always
      --    rst_i = '0' -> (ibus_cyc_o = '1') = (state = FETCH_WAIT_ST);
      -- psl f_dbus_state : assert always
      --    rst_i = '0' -> (dbus_cyc_o = '1') = dbus_wait;
   end generate gen_formal;

end architecture synthesis;
