-- DECODE of the pipelined core, for SymbiYosys. Every input is free, so
-- the solver plays every FETCH that offers at most four words, every
-- PREPARE, and every flush of WRITE.
--
-- THEORY OF OPERATION
-- The properties are in pipe_decode itself, under G_FORMAL, because their
-- invariants name its registers. The words from FETCH are a free signal
-- here (anyseq), since the top level has only plain ports. The
-- assertions are what the proof of PREPARE assumes of DECODE, what DECODE
-- takes from FETCH, and where it redirects FETCH.
--
-- RESET
-- The first cycle is a reset.

library ieee;
   use ieee.std_logic_1164.all;

   use work.pipe_pkg.all;

entity formal_pipe_decode is
   port (
      clk_i     : in  std_logic;
      rst_i     : in  std_logic;
      f_addr_i  : in  std_logic_vector(31 downto 0);
      f_count_i : in  natural range 0 to 4;
      flush_i   : in  std_logic;
      ready_i   : in  std_logic
   );
end entity formal_pipe_decode;

architecture synthesis of formal_pipe_decode is

   signal f_words  : t_words4;
   signal consume  : natural range 0 to 4;
   signal redirect : std_logic;
   signal target   : std_logic_vector(31 downto 0);
   signal emit     : std_logic;
   signal uop      : t_uop;
   signal inst     : t_inst;
   signal inst2    : t_inst;
   signal skid     : t_inst;
   signal starve   : std_logic;
   signal blocked  : std_logic;

   attribute anyseq : boolean;
   attribute anyseq of f_words : signal is true;

begin

   -- psl default clock is rising_edge(clk_i);
   -- psl f_initial_reset : assume rst_i;


   i_pipe_decode : entity work.pipe_decode
      generic map (
         G_FORMAL => true
      )
      port map (
         clk_i      => clk_i,
         rst_i      => rst_i,
         f_addr_i   => f_addr_i,
         f_words_i  => f_words,
         f_count_i  => f_count_i,
         consume_o  => consume,
         redirect_o => redirect,
         target_o   => target,
         flush_i    => flush_i,
         ready_i    => ready_i,
         emit_o     => emit,
         uop_o      => uop,
         inst_o     => inst,
         inst2_o    => inst2,
         skid_o     => skid,
         starve_o   => starve,
         blocked_o  => blocked
      ); -- i_pipe_decode

end architecture synthesis;
