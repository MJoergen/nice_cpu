-- The console's receive interrupt with checks of its ports, for
-- SymbiYosys. Every input is free, so the solver tries every bus master,
-- every input, and every core that takes the requests at any time.
--
-- THEORY OF OPERATION
-- The interrupt port is the source side of the core's valid/ready port:
-- once VALID is high, it stays high, with the vector unchanged, until
-- READY takes the request. wb_slave_check watches the bus port. f_enable
-- follows the enable from the writes, and with it the checks say when a
-- request comes (SYSTEM.md §1.9): in the cycle after entered_i with the
-- enable, or after a write that sets the enable from 0 to 1 while waits_i
-- is high, and at no other time. A read returns the enable and the
-- vector. The unit's enable shows only in a read, so f_enable cannot be
-- tied to it in every cycle, as k-induction would need: with G_SHADOW,
-- in the bmc task, these checks run from reset, and the prove task proves
-- the checks of the ports alone. The covers show a request raised by entered_i and by the
-- enable, and one that waits while another merges with it.
--
-- RESET
-- The first cycle is a reset.

library ieee;
   use ieee.std_logic_1164.all;

entity formal_console_irq is
   generic (
      G_SHADOW : boolean := true
   );
   port (
      clk_i       : in  std_logic;
      rst_i       : in  std_logic;
      entered_i   : in  std_logic;
      waits_i     : in  std_logic;
      wb_cyc_i    : in  std_logic;
      wb_stb_i    : in  std_logic;
      wb_we_i     : in  std_logic;
      wb_data_i   : in  std_logic_vector(31 downto 0);
      irq_ready_i : in  std_logic
   );
end entity formal_console_irq;

architecture synthesis of formal_console_irq is

   signal wb_stall   : std_logic;
   signal wb_ack     : std_logic;
   signal wb_data    : std_logic_vector(31 downto 0);
   signal irq_valid  : std_logic;
   signal irq_vector : std_logic_vector(7 downto 0);

   -- The enable and the vector as the writes set them; the enable after
   -- this cycle's write; a write that sets the enable from 0 to 1; a
   -- request due
   signal f_enable : std_logic                    := '0';
   signal f_vector : std_logic_vector(7 downto 0) := (others => '0');
   signal f_write  : std_logic;
   signal f_en_new : std_logic;
   signal f_rise   : std_logic;
   signal f_raise  : std_logic;
   signal f_check  : std_logic;

begin

   f_check <= '1' when G_SHADOW else
              '0';

   f_write  <= wb_cyc_i and wb_stb_i and wb_we_i;
   f_en_new <= wb_data_i(8) when f_write = '1' else
               f_enable;
   f_rise   <= f_write and wb_data_i(8) and not f_enable;
   f_raise  <= (f_en_new and entered_i) or (f_rise and waits_i);

   p_shadow : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if f_write = '1' then
            f_enable <= wb_data_i(8);
            f_vector <= wb_data_i(7 downto 0);
         end if;
         if rst_i = '1' then
            f_enable <= '0';
            f_vector <= (others => '0');
         end if;
      end if;
   end process p_shadow;

   -- psl default clock is rising_edge(clk_i);
   -- psl f_initial_reset : assume rst_i;

   -- The interrupt port
   -- psl f_valid_hold : assert always
   --    {irq_valid and not irq_ready_i and not rst_i} |=>
   --    {rst_i = '1' or (irq_valid = '1' and stable(irq_vector))};
   -- psl f_valid_reset : assert always rst_i |=> not irq_valid;

   -- When a request comes, and with which vector
   -- psl f_raise_due : assert always
   --    {f_check and f_raise and not rst_i} |=> {rst_i = '1' or irq_valid = '1'};
   -- psl f_raise_vector : assert always
   --    {f_check and f_raise and (not irq_valid or irq_ready_i) and not rst_i} |=>
   --    {rst_i = '1' or irq_vector = f_vector};
   -- psl f_raise_only : assert always
   --    {f_check and not f_raise and (not irq_valid or irq_ready_i)} |=> {not irq_valid};

   -- A read
   -- psl f_read : assert always
   --    {f_check and wb_cyc_i and wb_stb_i and not wb_we_i and not rst_i} |=>
   --    {rst_i = '1' or wb_data = X"00000" & "000" & f_enable & f_vector};

   -- psl c_entered : cover {f_enable and entered_i and not f_write; irq_valid};
   -- psl c_enable : cover {f_rise and waits_i and not entered_i; irq_valid};
   -- psl c_merge : cover {irq_valid and not irq_ready_i and f_raise; irq_valid and irq_ready_i};


   i_console_irq : entity work.console_irq
      port map (
         clk_i        => clk_i,
         rst_i        => rst_i,
         entered_i    => entered_i,
         waits_i      => waits_i,
         wb_cyc_i     => wb_cyc_i,
         wb_stb_i     => wb_stb_i,
         wb_stall_o   => wb_stall,
         wb_ack_o     => wb_ack,
         wb_we_i      => wb_we_i,
         wb_data_i    => wb_data_i,
         wb_data_o    => wb_data,
         irq_valid_o  => irq_valid,
         irq_ready_i  => irq_ready_i,
         irq_vector_o => irq_vector
      ); -- i_console_irq


   i_wb_slave_check : entity work.wb_slave_check
      port map (
         clk_i   => clk_i,
         rst_i   => rst_i,
         cyc_i   => wb_cyc_i,
         stb_i   => wb_stb_i,
         stall_i => wb_stall,
         ack_i   => wb_ack
      ); -- i_wb_slave_check

end architecture synthesis;
