-- DECODE of the pipelined core (MICROARCH.md §3, §4).
--
-- THEORY OF OPERATION
-- DECODE takes one whole instruction from FETCH into dec_r, when all its
-- words are present and dec_r is free. For "MOVE R15, c" and
-- "ADD R15, R15, c" with condition "always" it redirects FETCH at once
-- (MICROARCH.md §5.4). Then it splits the instruction in dec_r into
-- micro-operations (src/pipe_pkg.vhd), one per cycle, for PREPARE.
--
-- The registers are dec_r, the micro-operation to emit, and the id of the
-- next instruction. consume_o, redirect_o, target_o, and emit_o depend
-- combinationally on the words from FETCH and on ready_i and flush_i, so
-- that an instruction moves on in the cycle the next stage frees itself.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) ready_i is '1' when PREPARE takes uop_o at the end of the cycle.
-- b) flush_i empties the stage, and wins over everything else.
--
-- RESET
-- Synchronous. It empties the stage.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use work.nice_pkg.all;
   use work.pipe_pkg.all;
   use work.trace_pkg.all;

entity pipe_decode is
   port (
      clk_i      : in  std_logic;
      rst_i      : in  std_logic;

      -- From FETCH (src/pipe_fetch.vhd)
      f_addr_i   : in  std_logic_vector(31 downto 0);
      f_words_i  : in  t_words4;
      f_count_i  : in  natural range 0 to 4;
      -- The words that DECODE takes
      consume_o  : out natural range 0 to 4;
      -- A jump that DECODE resolves, and its target
      redirect_o : out std_logic;
      target_o   : out std_logic_vector(31 downto 0);

      -- WRITE empties the pipeline.
      flush_i    : in  std_logic;

      -- To PREPARE
      ready_i    : in  std_logic;
      emit_o     : out std_logic;
      uop_o      : out t_uop;
      -- The instruction in dec_r, for the check of stores into
      -- fetched code
      inst_o     : out t_inst
   );
end entity pipe_decode;

architecture synthesis of pipe_decode is

   signal f_addr    : std_logic_vector(31 downto 0);
   signal f_words   : t_words4;
   signal f_count   : natural range 0 to 4;
   signal f_consume : natural range 0 to 4;
   signal w_flush   : std_logic;
   signal p_ready   : std_logic;

   -- Taking an instruction into dec_r
   signal d_inst  : t_inst;
   signal d_ok    : std_logic;
   signal d_load  : std_logic;
   signal d_early : std_logic;
   signal d_dest  : std_logic_vector(31 downto 0);
   signal id_r    : std_logic_vector(2 downto 0);

   -- Splitting it into micro-operations
   signal dec_r       : t_inst;
   signal seq_kind_r  : t_kind;
   signal seq_first_r : std_logic;
   signal seq_uop     : t_uop;
   signal seq_emit    : std_logic;
   signal dec_free    : std_logic;

begin

   f_addr  <= f_addr_i;
   f_words <= f_words_i;
   f_count <= f_count_i;
   w_flush <= flush_i;
   p_ready <= ready_i;

   consume_o  <= f_consume;
   redirect_o <= d_load and d_early;
   target_o   <= d_dest;
   emit_o     <= seq_emit;
   uop_o      <= seq_uop;
   inst_o     <= dec_r;


   p_decode : process (all)
      variable inst_v  : t_inst;
      variable cf_v    : std_logic_vector(0 to 2);
      variable k_v     : natural range 1 to 4;
      variable len_v   : natural range 1 to 4;
      variable iw_v    : std_logic_vector(31 downto 0);
      variable early_v : std_logic;
      variable dest_v  : std_logic_vector(31 downto 0);
   begin
      iw_v           := f_words(0);
      cf_v           := const_fields(iw_v);
      len_v          := inst_len(iw_v);
      inst_v         := C_INST_NONE;
      inst_v.valid   := '1';
      inst_v.id      := id_r;
      inst_v.addr    := f_addr;
      inst_v.next_pc := f_addr + len_v;
      inst_v.iw      := iw_v;
      k_v            := 1;
      for i in 0 to 2 loop
         if cf_v(i) = '1' then
            inst_v.consts(i) := f_words(k_v);
            k_v              := minimum(k_v + 1, 3);
         end if;
      end loop;

      -- The jumps that DECODE resolves (MICROARCH.md §5.4): condition
      -- "always", an ALU instruction, and the destination R15 in mode 000.
      -- "MOVE R15, c" with s1 unused, and "ADD R15, R15, c" or
      -- "ADD R15, c, R15" without the C bit. They read no register but R15,
      -- and nothing changes R15 before them in the instruction.
      early_v := '0';
      dest_v  := inst_v.consts(1);
      if iw_v(31 downto 27) = "00000" and field(iw_v, 0) = "0001111" then
         if iw_v(26 downto 21) = "000000" and field(iw_v, 1) = "0110000" and
            field(iw_v, 2) = "0000000" then
            early_v := '1';
         elsif iw_v(26) = '0' and iw_v(24 downto 21) = "0011" then
            if field(iw_v, 1) = "0001111" and field(iw_v, 2) = "0110000" then
               early_v := '1';
               dest_v  := inst_v.next_pc + inst_v.consts(2);
            elsif field(iw_v, 1) = "0110000" and field(iw_v, 2) = "0001111" then
               early_v := '1';
               dest_v  := inst_v.next_pc + inst_v.consts(1);
            end if;
         end if;
      end if;
      inst_v.early := early_v;
      d_early      <= early_v;
      d_dest       <= dest_v;

      d_inst <= inst_v;
      d_ok   <= '1' when f_count >= len_v else '0';
   end process p_decode;

   d_load    <= d_ok and dec_free and not w_flush;
   f_consume <= inst_len(f_words(0)) when d_load = '1' else 0;


   p_seq_uop : process (all)
      variable uop_v : t_uop;
   begin
      uop_v       := C_UOP_NONE;
      uop_v.valid := dec_r.valid;
      uop_v.inst  := dec_r;
      uop_v.kind  := seq_kind_r;
      uop_v.first := seq_first_r;
      uop_v.last  := is_last(seq_kind_r);
      seq_uop     <= uop_v;
   end process p_seq_uop;

   seq_emit <= dec_r.valid and p_ready and not w_flush;
   dec_free <= not dec_r.valid or (seq_emit and seq_uop.last);


   p_seq : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if seq_emit = '1' then
            seq_kind_r  <= next_kind(dec_r.iw, seq_kind_r);
            seq_first_r <= '0';
            if seq_uop.last = '1' then
               dec_r.valid <= '0';
            end if;
         end if;

         if d_load = '1' then
            dec_r       <= d_inst;
            seq_kind_r  <= first_kind(d_inst.iw);
            seq_first_r <= '1';
            id_r        <= id_r + 1;
         end if;

         if w_flush = '1' then
            dec_r.valid <= '0';
         end if;

         if rst_i = '1' then
            dec_r       <= C_INST_NONE;
            seq_kind_r  <= UOP_OP;
            seq_first_r <= '0';
            id_r        <= (others => '0');
         end if;
      end if;
   end process p_seq;

end architecture synthesis;
