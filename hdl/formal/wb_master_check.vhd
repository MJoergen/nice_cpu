-- Formal properties of a pipelined Wishbone B4 master port, for
-- SymbiYosys. It watches the port and drives nothing.
--
-- THEORY OF OPERATION
-- A request is accepted in a cycle with CYC and STB high and STALL low, and
-- the slave answers it with one ACK in a later cycle. The checker counts the
-- accepted requests not yet acknowledged, and dropping CYC clears the count.
--
-- It assumes the slave side of the protocol: ACK only while CYC is high,
-- and only for an accepted request. It asserts the master side:
-- - STB is high only while CYC is high.
-- - A stalled request is held, with WE, ADDR, and DATA unchanged.
-- - CYC stays high while a request waits for its ACK, from the cycle after
--   the request is accepted. The count includes the request only from the
--   cycle after that, so f_cyc_accept covers the first.
-- - No more than G_MAX_PENDING requests wait at a time.
-- - Reset drops CYC and STB.
-- The covers show that a read, a write, and a stalled request can happen.
-- A port with G_READ_ONLY has no write to cover.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) A read-only port ties we_i and data_i to constants.

library ieee;
   use ieee.std_logic_1164.all;

entity wb_master_check is
   generic (
      G_MAX_PENDING : positive := 1;
      -- The widths of ADDR and DATA
      G_ADDR_SIZE   : positive := 32;
      G_DATA_SIZE   : positive := 32;
      -- A read-only port has no write to cover
      G_READ_ONLY   : boolean  := false
   );
   port (
      clk_i     : in  std_logic;
      rst_i     : in  std_logic;
      cyc_i     : in  std_logic;
      stb_i     : in  std_logic;
      stall_i   : in  std_logic;
      ack_i     : in  std_logic;
      we_i      : in  std_logic;
      addr_i    : in  std_logic_vector(G_ADDR_SIZE - 1 downto 0);
      data_i    : in  std_logic_vector(G_DATA_SIZE - 1 downto 0);

      -- The requests that wait for their ACK, for the invariants of a
      -- particular master
      pending_o : out natural range 0 to G_MAX_PENDING + 1
   );
end entity wb_master_check;

architecture synthesis of wb_master_check is

   signal pending : natural range 0 to G_MAX_PENDING + 1 := 0;
   signal accept  : std_logic;
   signal waiting : std_logic;

begin

   accept  <= cyc_i and stb_i and not stall_i;
   waiting <= '1' when pending /= 0 else '0';

   pending_o <= pending;


   p_pending : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if cyc_i = '0' then
            pending <= 0;
         elsif accept = '1' and ack_i = '0' then
            if pending <= G_MAX_PENDING then
               pending <= pending + 1;
            end if;
         elsif accept = '0' and ack_i = '1' then
            pending <= pending - 1;
         end if;

         if rst_i = '1' then
            pending <= 0;
         end if;
      end if;
   end process p_pending;


   -- psl default clock is rising_edge(clk_i);

   -- The slave
   -- psl f_ack_cyc : assume always ack_i -> cyc_i;
   -- psl f_ack_pending : assume always ack_i -> waiting;

   -- The master
   -- psl f_stb_cyc : assert always stb_i -> cyc_i;
   -- psl f_stall_hold : assert always
   --    {cyc_i and stb_i and stall_i and not rst_i} |=>
   --    {rst_i = '1' or (stb_i = '1' and stable(we_i) and stable(addr_i) and stable(data_i))};
   -- psl f_cyc_hold : assert always
   --    {waiting and not ack_i and not rst_i} |=> {cyc_i};
   -- psl f_cyc_accept : assert always {accept and not rst_i} |=> {rst_i = '1' or cyc_i = '1'};
   -- psl f_max_pending : assert always pending <= G_MAX_PENDING;
   -- psl f_reset : assert always {rst_i} |=> {not cyc_i and not stb_i};

   -- psl c_read : cover {accept and not we_i; [*1 to inf]; ack_i};
   -- psl c_stall : cover {cyc_i and stb_i and stall_i; accept};

   gen_write : if not G_READ_ONLY generate
      -- psl c_write : cover {accept and we_i; [*1 to inf]; ack_i};
   end generate gen_write;

end architecture synthesis;
