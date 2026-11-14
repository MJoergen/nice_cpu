-- The FPU with checks of its bus port and of its stack, for SymbiYosys.
-- Every input is free, so the solver tries every bus master that holds a
-- stalled request.
--
-- THEORY OF OPERATION
-- The FPU runs with G_FORMAL, which puts a free stand-in in place of its
-- arithmetic unit: it ends an operation in any cycle after the start,
-- with any result and any flags. The proofs are of the bus and the stack
-- only; tb_fpu and tb_fpu_unit check the values against the model.
--
-- The assumptions here are those of the master: it holds a stalled
-- request, and with G_STACK it writes only commands of the stack (NOP,
-- CLEAR, DUP, DROP, SWAP, OVER, and PICK, with any n) and neither X_S nor
-- X_W. The properties are in fpu itself, under G_FORMAL, because they
-- name its registers: those of the bus port, that each accepted request
-- gets one ACK, in order, and with G_STACK, its stack against a model of
-- §11.4 that the accesses keep. Its covers show a read of X_W that waits
-- for the unit, a write that waits for a command, and three requests
-- owed at once.
--
-- RESET
-- The first cycle is a reset.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

entity formal_fpu is
   generic (
      G_STACK : boolean := false
   );
   port (
      clk_i     : in  std_logic;
      rst_i     : in  std_logic;
      wb_cyc_i  : in  std_logic;
      wb_stb_i  : in  std_logic;
      wb_we_i   : in  std_logic;
      wb_addr_i : in  std_logic_vector(2 downto 0);
      wb_data_i : in  std_logic_vector(31 downto 0)
   );
end entity formal_fpu;

architecture synthesis of formal_fpu is

   signal wb_stall : std_logic;
   signal wb_ack   : std_logic;
   signal wb_data  : std_logic_vector(31 downto 0);

   signal stack_ok : std_logic;                   -- A request the stack task allows

begin

   stack_ok <= '1' when not G_STACK or wb_we_i = '0' or
                        (wb_addr_i /= "010" and wb_addr_i /= "011" and
                         (wb_addr_i /= "100" or
                          (unsigned(wb_data_i(31 downto 16)) = 0 and
                           unsigned(wb_data_i(7 downto 0)) <= 6))) else
               '0';

   -- psl default clock is rising_edge(clk_i);
   -- psl f_initial_reset : assume rst_i;
   -- psl f_hold : assume always
   --    {wb_cyc_i and wb_stb_i and wb_stall and not rst_i} |=>
   --    {wb_cyc_i = '1' and wb_stb_i = '1' and stable(wb_we_i) and stable(wb_addr_i) and
   --     stable(wb_data_i)};
   -- psl f_stack_only : assume always
   --    (wb_cyc_i and wb_stb_i) -> stack_ok;

   i_fpu : entity work.fpu
      generic map (
         G_FORMAL => true,
         G_STACK  => G_STACK
      )
      port map (
         clk_i      => clk_i,
         rst_i      => rst_i,
         wb_cyc_i   => wb_cyc_i,
         wb_stb_i   => wb_stb_i,
         wb_stall_o => wb_stall,
         wb_ack_o   => wb_ack,
         wb_we_i    => wb_we_i,
         wb_addr_i  => wb_addr_i,
         wb_data_i  => wb_data_i,
         wb_data_o  => wb_data
      ); -- i_fpu

end architecture synthesis;
