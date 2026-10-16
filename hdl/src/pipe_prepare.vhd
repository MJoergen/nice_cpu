-- PREPARE of the pipelined core (MICROARCH.md §3, §5.2, §5.3).
--
-- THEORY OF OPERATION
-- PREPARE holds one micro-operation in prep_r. It tests the condition of
-- the instruction when no older micro-operation in WRITE may still change
-- SR, and must before it issues a data read. It loads each data read of
-- the micro-operation into the request register, rd_stb_r and rd_addr_r,
-- which holds it on the data bus until the bus accepts it, but only when
-- the instruction is certain to run (MICROARCH.md §5.3). It reads the
-- registers in WRITE's state for the address, and waits while the
-- micro-operation in WRITE will still write the register it needs. Then it
-- passes the micro-operation to WRITE, with what it found out: the
-- condition, and whether the instruction has made a data read (committed)
-- and been counted on instret_o (counted).
--
-- An instruction with a data read is counted in the cycle the bus accepts
-- its last read, count_o.
--
-- The registers are prep_r, the request register, and what PREPARE knows
-- of the current instruction. ready_o, move_o, uop_o, load_o,
-- first_read_o, and count_o depend combinationally on the state of WRITE
-- and on the bus in the same cycle: a read may go out in the cycle WRITE
-- retires an older store, and a micro-operation moves on in the cycle
-- WRITE frees itself.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) w_i is WRITE's state, and done_i, flush_i, accept_i, take_nmi_i, and
--    take_irq_i are WRITE's decisions in the same cycle.
-- b) tag_cnt_i counts the data bus requests accepted and not acknowledged.
--
-- RESET
-- Synchronous. It empties the stage and drops the request.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use work.nice_pkg.all;
   use work.pipe_pkg.all;
   use work.trace_pkg.all;

entity pipe_prepare is
   port (
      clk_i        : in  std_logic;
      rst_i        : in  std_logic;

      -- From the SEQUENCER
      emit_i       : in  std_logic;
      uop_i        : in  t_uop;
      ready_o      : out std_logic;

      -- WRITE's state and decisions
      w_i          : in  t_write;
      done_i       : in  std_logic;
      flush_i      : in  std_logic;
      accept_i     : in  std_logic;
      take_nmi_i   : in  std_logic;
      take_irq_i   : in  std_logic;

      -- The interrupt requests (MICROARCH.md §5.3, rule 4)
      nmi_valid_i  : in  std_logic;
      irq_valid_i  : in  std_logic;

      -- To WRITE
      move_o       : out std_logic;
      uop_o        : out t_uop;
      first_read_o : out std_logic;   -- The first data read of an instruction
      prep_o       : out t_uop;       -- prep_r, for the check of stores into fetched code

      -- The data read, held until the bus accepts it
      dbus_stall_i : in  std_logic;
      tag_cnt_i    : in  natural range 0 to C_MAX_OUT;
      rd_stb_o     : out std_logic;
      rd_addr_o    : out std_logic_vector(31 downto 0);
      load_o       : out std_logic;   -- A data read is loaded now

      -- Counts an instruction on instret_o
      count_o      : out std_logic
   );
end entity pipe_prepare;

architecture synthesis of pipe_prepare is

   signal seq_uop   : t_uop;
   signal seq_emit  : std_logic;
   signal w_r       : t_write;
   signal w_done    : std_logic;
   signal w_flush   : std_logic;
   signal w_accept  : std_logic;
   signal take_nmi  : std_logic;
   signal take_irq  : std_logic;
   signal tag_cnt_r : natural range 0 to C_MAX_OUT;

   signal prep_r        : t_uop;
   signal p_loaded_r    : natural range 0 to 2;   -- Reads of prep_r loaded
   signal p_ck_r        : std_logic;              -- The instruction's condition is known
   signal p_cv_r        : std_logic;              -- and is this
   signal p_committed_r : std_logic;
   signal p_counted_r   : std_logic;
   signal p_out         : t_uop;
   signal p_load        : std_logic;
   signal p_first_read  : std_logic;
   signal p_last_read   : std_logic;
   signal p_addr        : std_logic_vector(31 downto 0);
   signal p_move        : std_logic;
   signal rd_stb_r      : std_logic;
   signal rd_addr_r     : std_logic_vector(31 downto 0);
   signal rd_last_r     : std_logic;              -- rd_stb_r is its instruction's last read

begin

   seq_uop   <= uop_i;
   seq_emit  <= emit_i;
   w_r       <= w_i;
   w_done    <= done_i;
   w_flush   <= flush_i;
   w_accept  <= accept_i;
   take_nmi  <= take_nmi_i;
   take_irq  <= take_irq_i;
   tag_cnt_r <= tag_cnt_i;

   ready_o      <= not prep_r.valid or p_move;
   move_o       <= p_move;
   uop_o        <= p_out;
   first_read_o <= p_first_read;
   prep_o       <= prep_r;
   rd_stb_o     <= rd_stb_r;
   rd_addr_o    <= rd_addr_r;
   load_o       <= p_load;

   -- An instruction with a data read is counted in the cycle the bus
   -- accepts its last read. The counter returns its value from before the
   -- count for that read, and every younger read is accepted later.
   count_o <= rd_stb_r and not dbus_stall_i and rd_last_r;


   p_prepare : process (all)
      variable u_v       : t_uop;
      variable wu_v      : t_uop;
      variable older_v   : boolean;   -- WRITE holds an older instruction
      variable ck_v      : std_logic;
      variable cv_v      : std_logic;
      variable rd_v      : std_logic_vector(1 to 2);
      variable nr_v      : natural range 0 to 2;
      variable f_v       : natural range 1 to 2;
      variable x_v       : natural range 0 to 15;
      variable b_v       : std_logic_vector(31 downto 0);
      variable busy_v    : boolean;   -- WRITE will still write the base
      variable older_ok  : boolean;
      variable intr_ok   : boolean;
      variable bus_ok    : boolean;
      variable started_v : boolean;
      variable load_v    : std_logic;
      variable irq_v     : boolean;
   begin
      u_v     := prep_r;
      wu_v    := w_r.uop;
      older_v := wu_v.valid = '1' and wu_v.inst.id /= u_v.inst.id;

      -- The condition (ISA.md §3), against SR before the instruction
      ck_v := '0';
      cv_v := condition(u_v.inst.iw, w_r.regs(14));
      if u_v.first = '1' then
         if w_r.mode = RUN_ST and
            not (wu_v.valid = '1' and uop_may_sr(wu_v.inst.iw, wu_v.kind)) then
            ck_v := '1';
         end if;
      elsif p_ck_r = '1' then
         ck_v := '1';
         cv_v := p_cv_r;
      elsif wu_v.valid = '0' and w_r.mode = RUN_ST then
         -- The instruction's first micro-operation has retired.
         ck_v := '1';
         cv_v := w_r.cond;
      end if;

      -- The next read to load: s0, then s1
      rd_v := uop_reads(u_v.inst.iw, u_v.kind);
      nr_v := popcount(rd_v);
      if p_loaded_r = 0 and rd_v(1) = '1' then
         f_v := 1;
      else
         f_v := 2;
      end if;
      x_v := reg(u_v.inst.iw, f_v);
      if x_v = 15 then
         b_v := w_r.regs(15) when not older_v and w_r.jump = '1' else u_v.inst.next_pc;
      else
         b_v := w_r.regs(x_v);
      end if;
      p_addr <= mem_addr(mode(u_v.inst.iw, f_v), x_v, b_v, u_v.inst.consts(f_v));

      busy_v := wu_v.valid = '1' and x_v /= 0 and
                ((x_v = 14 and uop_may_sr(wu_v.inst.iw, wu_v.kind)) or
                 (x_v /= 14 and uop_wreg(wu_v.inst.iw, wu_v.kind) = x_v));

      -- The older micro-operation in WRITE will not jump, halt, or store
      -- into fetched code, and is counted on instret_o. Either it retires
      -- now, or it has made its reads and makes no store.
      older_ok := not older_v or (w_done = '1' and w_flush = '0') or
                  (not uop_store(wu_v.inst.iw, wu_v.kind) and
                   not uop_may_jump(wu_v.inst.iw, wu_v.kind) and
                   w_r.jump = '0' and wu_v.counted = '1');

      -- No interrupt may be taken before this instruction (MICROARCH.md
      -- §5.3, rule 4). None can be if the instruction has made a data read
      -- or begun to retire, or follows RTI directly.
      started_v := not older_v and
                   ((wu_v.valid = '1' and wu_v.first = '0') or (wu_v.valid = '0' and w_r.mid = '1'));
      irq_v     := irq_valid_i = '1' and w_r.in_service = '0' and
                   (w_r.regs(14)(C_SR_E) = '1' or
                    (wu_v.valid = '1' and uop_may_sr(wu_v.inst.iw, wu_v.kind)));
      intr_ok   := started_v or p_committed_r = '1' or (not older_v and w_r.after_rti = '1') or
                   not ((nmi_valid_i = '1' and w_r.in_service = '0') or irq_v);

      bus_ok := (rd_stb_r = '0' or dbus_stall_i = '0') and
                tag_cnt_r + to_nat(rd_stb_r) < C_MAX_OUT;

      load_v := '0';
      if u_v.valid = '1' and ck_v = '1' and cv_v = '1' and p_loaded_r < nr_v and
         older_ok and intr_ok and not busy_v and bus_ok and
         w_r.mode = RUN_ST and w_flush = '0' and take_nmi = '0' and take_irq = '0' then
         load_v := '1';
      end if;
      p_load       <= load_v;
      p_first_read <= load_v and not p_committed_r;
      p_last_read  <= '0';
      if load_v = '1' and p_loaded_r + 1 = nr_v and not later_reads(u_v.inst.iw, u_v.kind) then
         p_last_read <= '1';
      end if;

      -- The micro-operation may go on when its reads are loaded, or it has
      -- none, or its condition is false.
      p_move <= '0';
      if u_v.valid = '1' and w_accept = '1' then
         if nr_v = 0 or (ck_v = '1' and (cv_v = '0' or p_loaded_r + to_nat(load_v) = nr_v)) then
            p_move <= '1';
         end if;
      end if;

      u_v.cond_known := ck_v;
      u_v.cond_val   := cv_v;
      u_v.committed  := p_committed_r or load_v;
      u_v.counted    := p_counted_r;
      if load_v = '1' and p_loaded_r + 1 = nr_v and not later_reads(u_v.inst.iw, u_v.kind) then
         u_v.counted := '1';
      end if;
      p_out <= u_v;
   end process p_prepare;


   p_prepare_reg : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if dbus_stall_i = '0' then
            rd_stb_r <= '0';
         end if;

         if p_load = '1' then
            rd_stb_r      <= '1';
            rd_addr_r     <= p_addr;
            rd_last_r     <= p_last_read;
            p_loaded_r    <= p_loaded_r + 1;
            p_committed_r <= '1';
            if p_last_read = '1' then
               p_counted_r <= '1';
            end if;
         end if;

         if p_move = '1' then
            p_loaded_r <= 0;
            if prep_r.first = '1' then
               p_ck_r <= p_out.cond_known;
               p_cv_r <= p_out.cond_val;
            end if;
            if prep_r.last = '1' then
               p_ck_r        <= '0';
               p_committed_r <= '0';
               p_counted_r   <= '0';
            end if;
            prep_r.valid <= '0';
         end if;

         if seq_emit = '1' then
            prep_r <= seq_uop;
         end if;

         if w_flush = '1' then
            prep_r.valid  <= '0';
            p_loaded_r    <= 0;
            p_ck_r        <= '0';
            p_committed_r <= '0';
            p_counted_r   <= '0';
         end if;

         if rst_i = '1' then
            prep_r        <= C_UOP_NONE;
            p_loaded_r    <= 0;
            p_ck_r        <= '0';
            p_cv_r        <= '0';
            p_committed_r <= '0';
            p_counted_r   <= '0';
            rd_stb_r      <= '0';
            rd_last_r     <= '0';
         end if;
      end if;
   end process p_prepare_reg;

end architecture synthesis;
