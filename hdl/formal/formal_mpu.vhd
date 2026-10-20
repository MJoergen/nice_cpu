-- The math unit with checks of its port, for SymbiYosys. Every input is
-- free, so the solver tries every bus master that holds a stalled request,
-- with every pair of operands.
--
-- THEORY OF OPERATION
-- The assertions here are those of the bus port. f_owed counts the
-- requests accepted and not yet acknowledged. The assertions say that at
-- most one is owed, that an ACK comes only when one is owed, that STALL is
-- high exactly while a read waits for its ACK, and that a write, and a
-- read of an operand or a spare word, are acknowledged in the next cycle.
-- So each accepted request gets one ACK, in order. The properties of the
-- data, and the invariants that make them inductive, are in mpu itself,
-- under G_FORMAL, because they name its registers: among them that a read
-- waits no longer than its unit takes, so that each ACK comes.
-- The covers show a read that waits for each kind of unit, and a write
-- that restarts a computation.
--
-- RESET
-- The first cycle is a reset.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

entity formal_mpu is
   port (
      clk_i     : in  std_logic;
      rst_i     : in  std_logic;
      wb_cyc_i  : in  std_logic;
      wb_stb_i  : in  std_logic;
      wb_we_i   : in  std_logic;
      wb_addr_i : in  std_logic_vector(4 downto 0);
      wb_data_i : in  std_logic_vector(31 downto 0)
   );
end entity formal_mpu;

architecture synthesis of formal_mpu is

   signal wb_stall : std_logic;
   signal wb_ack   : std_logic;
   signal wb_data  : std_logic_vector(31 downto 0);

   signal accept  : std_logic;
   signal fast    : std_logic;                   -- A request never waits
   signal f_owed  : natural range 0 to 2 := 0;
   signal f_waits : natural range 0 to 2 := 0;   -- Cycles a read waited, up to 2

begin

   accept <= wb_cyc_i and wb_stb_i and not wb_stall;
   fast   <= '1' when wb_we_i = '1' or wb_addr_i <= 1 or (wb_addr_i >= 10 and wb_addr_i <= 19) or
                      wb_addr_i >= 28 else
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

   -- psl f_owed_max : assert always f_owed <= 1;
   -- psl f_ack_owed : assert always wb_ack -> f_owed = 1;
   -- psl f_stall : assert always wb_stall = '1' -> (f_owed = 1 and wb_ack = '0');
   -- psl f_stall_wait : assert always (f_owed = 1 and wb_ack = '0') -> wb_stall = '1';
   -- psl f_fast : assert always
   --    {accept and fast and not rst_i} |=> {wb_ack};
   -- psl f_ack_reset : assert always rst_i |=> not wb_ack and not wb_stall;

   -- psl c_mul : cover {f_waits = 2 and wb_addr_i = 3; wb_ack};
   -- psl c_div : cover {f_waits = 2 and wb_addr_i = 6; wb_ack};
   -- psl c_div64 : cover {f_waits = 2 and wb_addr_i = 25; wb_ack};


   i_mpu : entity work.mpu
      generic map (
         G_FORMAL => true
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
      ); -- i_mpu

end architecture synthesis;
