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
--   EXEC      Compute the result, write the destination, apply its side
--             effect, and update the flags. A memory destination is written
--             through the data bus.
--   VEC       Read the vector table entry, for IRQ, NMI, and INT.
--   RETIRE    Report the step on retire_o, and an instruction on
--             instret_o.
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

   use work.trace_pkg.all;

entity multicycle is
   port (
      clk_i        : in  std_logic;
      rst_i        : in  std_logic;

      -- Instruction bus: read only
      ibus_cyc_o   : out std_logic                     := '0';
      ibus_stb_o   : out std_logic                     := '0';
      ibus_stall_i : in  std_logic;
      ibus_ack_i   : in  std_logic;
      ibus_addr_o  : out std_logic_vector(31 downto 0) := (others => '0');
      ibus_data_i  : in  std_logic_vector(31 downto 0);

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
      -- interrupt entry, for the instruction counter (ISA.md §8.5)
      instret_o    : out std_logic;

      -- One report per step, for sim/trace.vhd
      retire_o     : out t_retire
   );
end entity multicycle;

architecture synthesis of multicycle is

   -- SR bits (ISA.md §1.3)
   constant C_SR_I   : natural := 31;
   constant C_SR_E   : natural := 30;
   constant C_SR_V   : natural := 29;
   constant C_SR_N   : natural := 28;
   constant C_SR_Z   : natural := 27;
   constant C_SR_C   : natural := 26;
   constant C_SR_X   : natural := 25;
   constant C_SR_ONE : natural := 24;

   -- The flags an instruction with M = 1 rewrites (ISA.md §6).
   constant C_FLAG_MASK : std_logic_vector(31 downto 0) := X"3E000000";

   type t_state is (
      S_BOUNDARY,
      S_FETCH,
      S_FETCH_WAIT,
      S_COND,
      S_SRC,
      S_SRC_WAIT,
      S_EXEC,
      S_DEST_WAIT,
      S_VEC,
      S_VEC_WAIT,
      S_RETIRE,
      S_HALTED
   );

   type t_consts is array (0 to 2) of std_logic_vector(31 downto 0);

   -- The result of an operation, with carry and overflow for the flags.
   type t_result is record
      r : std_logic_vector(31 downto 0);
      c : std_logic;
      v : std_logic;
   end record t_result;

   -- The value of register x after a write of v (ISA.md §4.3).
   function regval(x : natural range 0 to 15;
                   v : std_logic_vector(31 downto 0)) return std_logic_vector is
      variable res_v : std_logic_vector(31 downto 0) := v;
   begin
      if x = 0 then
         res_v := (others => '0');
      elsif x = 14 then
         res_v(C_SR_ONE) := '1';
      end if;
      return res_v;
   end function regval;

   procedure set_reg(regs : inout t_regs;
                     x    : natural range 0 to 15;
                     v    : std_logic_vector(31 downto 0)) is
   begin
      regs(x) := regval(x, v);
   end procedure set_reg;

   -- The operand field i of an instruction word: 0 = dest, 1 = s0, 2 = s1.
   function field(iw : std_logic_vector(31 downto 0);
                  i  : natural range 0 to 2) return std_logic_vector is
      constant C_LOW : natural := 14 - 7 * i;
      variable res_v : std_logic_vector(6 downto 0);
   begin
      res_v := iw(C_LOW + 6 downto C_LOW);
      return res_v;
   end function field;

   -- The fields that take a constant word (ISA.md §2.3). None for control
   -- instructions.
   function const_fields(iw : std_logic_vector(31 downto 0)) return std_logic_vector is
      variable res_v : std_logic_vector(0 to 2) := "000";
   begin
      if iw(27 downto 26) /= "11" then
         for i in 0 to 2 loop
            if field(iw, i)(5 downto 4) = "11" then
               res_v(i) := '1';
            end if;
         end loop;
      end if;
      return res_v;
   end function const_fields;

   function add(a   : std_logic_vector(31 downto 0);
                b   : std_logic_vector(31 downto 0);
                cin : std_logic) return t_result is
      variable sum_v : std_logic_vector(32 downto 0);
      variable res_v : t_result;
   begin
      sum_v   := ('0' & a) + ('0' & b) + cin;
      res_v.r := sum_v(31 downto 0);
      res_v.c := sum_v(32);
      res_v.v := (a(31) xor res_v.r(31)) and (b(31) xor res_v.r(31));
      return res_v;
   end function add;

   function sub(a   : std_logic_vector(31 downto 0);
                b   : std_logic_vector(31 downto 0);
                cin : std_logic) return t_result is
      variable diff_v : std_logic_vector(32 downto 0);
      variable res_v  : t_result;
   begin
      diff_v  := ('0' & a) - ('0' & b) - cin;
      res_v.r := diff_v(31 downto 0);
      res_v.c := diff_v(32);                  -- The borrow
      res_v.v := (a(31) xor b(31)) and (a(31) xor res_v.r(31));
      return res_v;
   end function sub;

   -- ISA.md §5.1. cin is already 0 if the instruction's C bit is clear.
   function alu(op  : std_logic_vector(3 downto 0);
                s0  : std_logic_vector(31 downto 0);
                s1  : std_logic_vector(31 downto 0);
                cin : std_logic) return t_result is
      variable res_v : t_result := (r => (others => '0'), c => '0', v => '0');
   begin
      case op is
         when "0000" => res_v.r := s0;
         when "0001" => res_v   := sub(s0, s1, cin);
         when "0010" => res_v   := add(s0, s0 and s1, cin);
         when "0011" => res_v   := add(s0, s1, cin);
         when "0100" => res_v   := add(s0, s0, cin);
         when "0101" => res_v   := sub(s0, X"00000001", '0');
         when "0110" => res_v.r := not s0;
         when "0111" => res_v.r := not (s0 or s1);
         when "1000" => res_v.r := (not s0) and s1;
         when "1001" => res_v.r := not (s0 and s1);
         when "1010" => res_v.r := s0 xor s1;
         when "1011" => res_v.r := (not s0) or s1;
         when "1100" => res_v.r := not (s0 xor s1);
         when "1101" => res_v.r := s0 and s1;
         when "1110" => res_v.r := X"00000001";
         when others => res_v.r := s0 or s1;
      end case;
      return res_v;
   end function alu;

   function reverse(v : std_logic_vector(31 downto 0)) return std_logic_vector is
      variable res_v : std_logic_vector(31 downto 0);
   begin
      for i in 0 to 31 loop
         res_v(i) := v(31 - i);
      end loop;
      return res_v;
   end function reverse;

   -- n mod 33, as in doc/MICROARCH.md §7.3: 32 = -1 (mod 33), so the 5-bit
   -- digits of n count with alternating signs. 99 keeps the sum positive.
   function mod33(n : std_logic_vector(31 downto 0)) return natural is
      variable sum_v : integer range 0 to 255;
   begin
      sum_v := 99 + to_integer(n(4 downto 0)) - to_integer(n(9 downto 5)) +
               to_integer(n(14 downto 10)) - to_integer(n(19 downto 15)) +
               to_integer(n(24 downto 20)) - to_integer(n(29 downto 25)) +
               to_integer(n(31 downto 30));

      for i in 1 to 5 loop
         if sum_v >= 33 then
            sum_v := sum_v - 33;
         end if;
      end loop;

      return sum_v;
   end function mod33;

   -- ISA.md §5.2, in the closed forms given there. A right shift is the
   -- mirror image of the left shift of the same kind, so s0 is reversed
   -- before and the result after. The carry is the C flag after the shift,
   -- before M is applied.
   function shift(op : std_logic_vector(3 downto 0);
                  s0 : std_logic_vector(31 downto 0);
                  n  : std_logic_vector(31 downto 0);
                  c  : std_logic) return t_result is
      variable d_v     : std_logic_vector(31 downto 0);
      variable fill_v  : std_logic;
      variable fills_v : std_logic_vector(32 downto 0);
      variable wide_v  : std_logic_vector(65 downto 0);   -- c, d, 33 fill bits
      variable rot_v   : std_logic_vector(32 downto 0);   -- c, d
      variable m_v     : natural range 0 to 33;           -- The reduced count
      variable res_v   : t_result := (r => (others => '0'), c => c, v => '0');
   begin
      d_v := reverse(s0) when op(3) = '1' else s0;

      case op(2 downto 0) is
         when "101" =>
            -- C<C, C>C: a 33-bit rotation of C and d
            m_v     := mod33(n);
            rot_v   := ((c & d_v) sll m_v) or ((c & d_v) srl (33 - m_v));
            res_v.r := rot_v(31 downto 0);
            res_v.c := rot_v(32);

         when "110" | "111" =>
            -- <<<, C<<, >>>, >>C: a 32-bit rotation. C gets the bit rotated
            -- last.
            res_v.r := d_v rol to_integer(n(4 downto 0));
            if n /= 0 then
               res_v.c := res_v.r(0);
            end if;

         when others =>
            -- A fixed fill. After 33 steps, nothing changes any more.
            case op(2 downto 0) is
               when "001" | "100" => fill_v := '1';   -- 0<1, C<1
               when "010"         => fill_v := c;     -- 0<C
               when others        => fill_v := '0';   -- 0<0, C<0
            end case;
            m_v     := 33 when n > 33 else to_integer(n(5 downto 0));
            fills_v := (others => fill_v);
            wide_v  := (c & d_v & fills_v) sll m_v;
            res_v.r := wide_v(64 downto 33);
            res_v.c := wide_v(65);
      end case;

      if op(3) = '1' then
         res_v.r := reverse(res_v.r);
      end if;

      -- Only 011, 100, 101, and 111 send the bit shifted out to C.
      case op(2 downto 0) is
         when "011" | "100" | "101" | "111" => null;
         when others                         => res_v.c := '0';
      end case;

      return res_v;
   end function shift;

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
   take_nmi <= state = S_BOUNDARY and rst_i = '0' and nmi_valid_i = '1' and
               in_service = '0' and after_rti = '0';
   take_irq <= state = S_BOUNDARY and rst_i = '0' and irq_valid_i = '1' and
               in_service = '0' and after_rti = '0' and regs(14)(C_SR_E) = '1' and not take_nmi;

   nmi_ready_o <= '1' when take_nmi else '0';
   irq_ready_o <= '1' when take_irq else '0';

   halted_o  <= '1' when state = S_HALTED else '0';
   instret_o <= '1' when state = S_RETIRE and rep_intr = '0' else '0';


   p_fsm : process (clk_i)
      variable regs_v : t_regs;
      variable sr_v   : std_logic_vector(31 downto 0);
      variable f_v    : std_logic_vector(6 downto 0);
      variable x_v    : natural range 0 to 15;
      variable addr_v : std_logic_vector(31 downto 0);
      variable need_v : std_logic_vector(0 to 2);
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
         state      <= S_FETCH when need /= "000" else S_COND;
      end procedure fetch_next;

      -- The value of source i is known.
      procedure src_done(i : natural range 1 to 2;
                         v : std_logic_vector(31 downto 0)) is
      begin
         srcs(i) <= v;
         if i = 1 then
            src_idx <= 2;
            state   <= S_SRC;
         else
            state <= S_EXEC;
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
            when S_BOUNDARY =>
               rep_intr    <= '0';
               rep_skipped <= '0';
               rep_mem_we  <= '0';
               rep_addr    <= regs(15);
               if take_nmi then
                  rep_intr   <= '1';
                  rep_nmi    <= '1';
                  int_vector <= nmi_vector_i;
                  state      <= S_VEC;
               elsif take_irq then
                  rep_intr   <= '1';
                  rep_nmi    <= '0';
                  int_vector <= irq_vector_i;
                  state      <= S_VEC;
               else
                  fetch_iw <= '1';
                  state    <= S_FETCH;
               end if;

            -- ISA.md §5 steps 1 and 2
            when S_FETCH =>
               ibus_cyc_o  <= '1';
               ibus_stb_o  <= '1';
               ibus_addr_o <= regs(15);
               state       <= S_FETCH_WAIT;

            when S_FETCH_WAIT =>
               if ibus_ack_i = '1' then
                  ibus_cyc_o <= '0';
                  set_reg(regs_v, 15, regs(15) + 1);
                  if fetch_iw = '1' then
                     fetch_iw <= '0';
                     iw       <= ibus_data_i;
                     need_v   := const_fields(ibus_data_i);
                  else
                     need_v := fetch_need;
                     for i in 0 to 2 loop
                        if need_v(i) = '1' then
                           consts(i) <= ibus_data_i;
                           need_v(i) := '0';
                           exit;
                        end if;
                     end loop;
                  end if;
                  fetch_next(need_v);
               end if;

            -- ISA.md §5 steps 3 and 4
            when S_COND =>
               -- The instruction about to run clears after_rti when it
               -- completes, unless it is an RTI, which sets it again.
               after_rti <= '0';
               src_idx   <= 1;
               state     <= S_SRC;

               if (regs(14)(C_SR_ONE + to_integer(iw(30 downto 28))) xor iw(31)) = '0' then
                  rep_skipped <= '1';
                  state       <= S_RETIRE;
               elsif iw(27 downto 26) = "11" then
                  state <= S_RETIRE;
                  if iw(20 downto 8) /= 0 or (iw(25 downto 21) /= "00010" and iw(7 downto 0) /= 0) then
                     halt <= HALT_RESERVED;
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
                              state      <= S_VEC;
                           end if;

                        when others =>
                           halt <= HALT_RESERVED;
                     end case;
                  end if;
               end if;

            -- ISA.md §4.1 and §5 step 5
            when S_SRC =>
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
                     state <= S_SRC_WAIT;
                  when "101" =>
                     set_reg(regs_v, x_v, regs(x_v) - 1);
                     dbus_start('0', regs_v(x_v), X"00000000");
                     state <= S_SRC_WAIT;
                  when "110" =>
                     set_reg(regs_v, x_v, regs(x_v) + 1);
                     dbus_start('0', regs(x_v), X"00000000");
                     state <= S_SRC_WAIT;
                  when others =>
                     dbus_start('0', regs(x_v) + consts(src_idx), X"00000000");
                     state <= S_SRC_WAIT;
               end case;

            when S_SRC_WAIT =>
               if dbus_ack_i = '1' then
                  dbus_cyc_o <= '0';
                  src_done(src_idx, dbus_data_i);
               end if;

            -- ISA.md §5 steps 6 to 8
            when S_EXEC =>
               if iw(27) = '1' then
                  res_v := shift(iw(24 downto 21), srcs(1), srcs(2), regs(14)(C_SR_C));
               else
                  res_v := alu(iw(24 downto 21), srcs(1), srcs(2), iw(26) and regs(14)(C_SR_C));
               end if;

               -- The destination (ISA.md §4.2)
               f_v   := field(iw, 0);
               x_v   := to_integer(f_v(3 downto 0));
               state <= S_RETIRE;
               case f_v(6 downto 4) is
                  when "000" =>
                     set_reg(regs_v, x_v, res_v.r);
                  when "001" =>
                     set_reg(regs_v, x_v, res_v.r);
                     set_reg(regs_v, x_v, regs_v(x_v) - 1);
                  when "010" =>
                     set_reg(regs_v, x_v, res_v.r);
                     set_reg(regs_v, x_v, regs_v(x_v) + 1);
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
                  state      <= S_DEST_WAIT;
               end if;

               -- The flags (ISA.md §6)
               if iw(25) = '1' and not (x_v = 14 and f_v(6 downto 4) <= "010") then
                  sr_v           := regs_v(14) and not C_FLAG_MASK;
                  sr_v(C_SR_X)   := and res_v.r;
                  sr_v(C_SR_Z)   := nor res_v.r;
                  sr_v(C_SR_N)   := res_v.r(31);
                  sr_v(C_SR_C)   := res_v.c;
                  sr_v(C_SR_V)   := res_v.v;
                  set_reg(regs_v, 14, sr_v);
               end if;

            when S_DEST_WAIT =>
               if dbus_ack_i = '1' then
                  dbus_cyc_o <= '0';
                  state      <= S_RETIRE;
               end if;

            -- ISA.md §7.2. The vector table entry is at VBASE * 256 + v.
            when S_VEC =>
               dbus_start('0', regs(14)(23 downto 0) & int_vector, X"00000000");
               state <= S_VEC_WAIT;

            when S_VEC_WAIT =>
               if dbus_ack_i = '1' then
                  dbus_cyc_o <= '0';
                  saved_pc   <= regs(15);
                  saved_sr   <= regs(14);
                  in_service <= '1';
                  sr_v          := regs(14);
                  sr_v(C_SR_I)  := '1';
                  set_reg(regs_v, 14, sr_v);
                  set_reg(regs_v, 15, dbus_data_i);
                  state      <= S_RETIRE;
               end if;

            when S_RETIRE =>
               state <= S_HALTED when halt /= HALT_NONE else S_BOUNDARY;

            when S_HALTED =>
               null;
         end case;

         regs <= regs_v;

         if rst_i = '1' then
            state      <= S_BOUNDARY;
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
      retire_o.valid    <= '1' when state = S_RETIRE else '0';
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

end architecture synthesis;
