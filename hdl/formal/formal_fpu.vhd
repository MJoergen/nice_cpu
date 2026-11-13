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
-- The assertions here are those of the bus port. f_owed counts the
-- requests accepted and not yet acknowledged. The assertions say that at
-- most one is owed, that an ACK comes only when one is owed, and that
-- STALL is high exactly while one is owed and not acknowledged. So each
-- accepted request gets one ACK, in order. The covers show a read of X_W
-- that waits for the unit, and a write that waits for a command.
--
-- With G_STACK, the master writes only commands of the stack (NOP,
-- CLEAR, DUP, DROP, SWAP, OVER, and PICK, with any n) and does not write
-- X_S or X_W, and the FPU proves its stack against a model of §11.4 that
-- the accesses keep. The properties are in fpu itself, under G_FORMAL,
-- because they name its registers.
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

   signal accept   : std_logic;
   signal stack_ok : std_logic;                   -- A request the stack task allows
   signal f_owed   : natural range 0 to 2 := 0;
   signal f_waits  : natural range 0 to 2 := 0;   -- Cycles STALL was high, up to 2

begin

   accept   <= wb_cyc_i and wb_stb_i and not wb_stall;
   stack_ok <= '1' when not G_STACK or wb_we_i = '0' or
                        (wb_addr_i /= "010" and wb_addr_i /= "011" and
                         (wb_addr_i /= "100" or
                          (unsigned(wb_data_i(31 downto 16)) = 0 and
                           unsigned(wb_data_i(7 downto 0)) <= 6))) else
               '0';


   p_owed : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if accept = '1' and wb_ack = '0' and f_owed < 2 then
            f_owed <= f_owed + 1;
         elsif accept = '0' and wb_ack = '1' and f_owed > 0 then
            f_owed <= f_owed - 1;
         end if;

         if wb_stall = '1' and f_waits < 2 then
            f_waits <= f_waits + 1;
         elsif wb_stall = '0' then
            f_waits <= 0;
         end if;

         if rst_i = '1' then
            f_owed  <= 0;
            f_waits <= 0;
         end if;
      end if;
   end process p_owed;


   -- psl default clock is rising_edge(clk_i);
   -- psl f_initial_reset : assume rst_i;
   -- psl f_hold : assume always
   --    {wb_cyc_i and wb_stb_i and wb_stall and not rst_i} |=>
   --    {wb_cyc_i = '1' and wb_stb_i = '1' and stable(wb_we_i) and stable(wb_addr_i) and
   --     stable(wb_data_i)};
   -- psl f_stack_only : assume always
   --    (wb_cyc_i and wb_stb_i) -> stack_ok;

   -- psl f_owed_max : assert always f_owed <= 1;
   -- psl f_ack_owed : assert always wb_ack -> f_owed = 1;
   -- psl f_stall : assert always wb_stall = '1' -> (f_owed = 1 and wb_ack = '0');
   -- psl f_stall_wait : assert always (f_owed = 1 and wb_ack = '0') -> wb_stall = '1';
   -- psl f_ack_reset : assert always rst_i |=> not wb_ack and not wb_stall;

   -- psl c_view : cover {f_waits = 2 and wb_addr_i = "011"; wb_ack};
   -- psl c_pending : cover {f_waits = 2 and wb_addr_i = "101" and wb_we_i = '1'; wb_ack};


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
