-- The sound of DEVICES.md §12: an FM synthesizer whose registers are the
-- YM2151's, with a FIFO of 64 writes, as eight words of I/O.
--
--   0  OPM_WRITE   1  OPM_STATUS   2-7  read 0
--
-- THEORY OF OPERATION
-- A write of OPM_WRITE goes into the FIFO, its bits 15..8 the register
-- and 7..0 the data. The sample clock adds 3579545 to an accumulator in
-- each cycle, and is due each time the sum reaches 64 times G_CLK_HZ,
-- which it subtracts, as DEVICES.md §12.3 says. When a sample is due,
-- src/opm_engine.vhd takes the oldest write in the FIFO, if any, applies
-- it, and computes the sample, which it gives on sample_valid_o,
-- sample_left_o, and sample_right_o. The engine takes at most 422 cycles
-- for a sample, and a sample is due once in 64 * G_CLK_HZ / 3579545
-- cycles, which must be more. A sample that is due while the engine
-- computes the one before waits for it, and a simulation fails if a
-- third is due meanwhile.
--
-- The port is a pipelined Wishbone slave. It acknowledges each request
-- in the cycle after it accepts it, but a write of OPM_WRITE while the
-- FIFO is full: that one waits, with STALL high, until a sample takes a
-- write from the FIFO, and is acknowledged in the cycle after it goes in.
-- So a full FIFO holds off the acknowledge, as §12.3 asks.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) The master holds STB and the request while STALL is high.
-- b) STB is high only for requests to the sound: the bus decoder decodes
--    the address. The sound is at 0xFFFFFF08-0xFFFFFF0F, so the offset is
--    address bits 2..0.
--
-- RESET
-- Reset empties the FIFO, starts the sample clock anew, and resets the
-- engine, which is silent after it.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

entity opm is
   generic (
      -- The frequency of clk_i in hertz. It sets the rate of the samples.
      G_CLK_HZ    : natural range 1000000 to 500000000 := 100000000;
      -- The envelope's counter after reset, for a test (src/opm_engine.vhd).
      G_ENV_START : natural range 0 to 65535 := 0
   );
   port (
      clk_i          : in  std_logic;
      rst_i          : in  std_logic;

      wb_cyc_i       : in  std_logic;
      wb_stb_i       : in  std_logic;
      wb_stall_o     : out std_logic;
      wb_ack_o       : out std_logic := '0';
      wb_we_i        : in  std_logic;
      wb_addr_i      : in  std_logic_vector(2 downto 0);
      wb_data_i      : in  std_logic_vector(31 downto 0);
      wb_data_o      : out std_logic_vector(31 downto 0) := (others => '0');

      -- High for one cycle with each sample, left and right
      sample_valid_o : out std_logic;
      sample_left_o  : out std_logic_vector(15 downto 0);
      sample_right_o : out std_logic_vector(15 downto 0)
   );
end entity opm;

architecture synthesis of opm is

   constant C_CHIP_HZ : unsigned(33 downto 0) := to_unsigned(3579545, 34);
   constant C_LIMIT   : unsigned(33 downto 0) := shift_left(to_unsigned(G_CLK_HZ, 34), 6);

   type t_fifo is array (0 to 63) of std_logic_vector(15 downto 0);

   signal fifo    : t_fifo               := (others => (others => '0'));
   signal head_r  : unsigned(5 downto 0) := (others => '0');
   signal count_r : unsigned(6 downto 0) := (others => '0');

   signal acc_r     : unsigned(33 downto 0) := (others => '0');
   signal due_r     : std_logic := '0';
   signal pending_r : std_logic := '0';

   signal accept    : std_logic;
   signal hold_r    : std_logic := '0';
   signal held_r    : std_logic_vector(15 downto 0) := (others => '0');
   signal push      : std_logic;
   signal push_data : std_logic_vector(15 downto 0);
   signal pop       : std_logic;

   signal oldest : std_logic_vector(15 downto 0);
   signal ready  : std_logic;
   signal start  : std_logic;

begin

   -----------------------------------------------------------------------------
   -- The sample clock.
   -----------------------------------------------------------------------------

   p_clock : process (clk_i)
      variable sum_v : unsigned(33 downto 0);
   begin
      if rising_edge(clk_i) then
         sum_v := acc_r + C_CHIP_HZ;
         due_r <= '0';
         if sum_v >= C_LIMIT then
            sum_v := sum_v - C_LIMIT;
            due_r <= '1';
         end if;
         acc_r <= sum_v;

         if start = '1' then
            pending_r <= '0';
         end if;
         if due_r = '1' then
            assert pending_r = '0' or start = '1'
               report "opm: a sample is due while the one before it waits"
               severity failure;
            pending_r <= '1';
         end if;

         if rst_i = '1' then
            acc_r     <= (others => '0');
            due_r     <= '0';
            pending_r <= '0';
         end if;
      end if;
   end process p_clock;

   start  <= pending_r and ready;
   oldest <= fifo(to_integer(head_r));
   pop    <= '1' when start = '1' and count_r /= 0 else
            '0';


   -----------------------------------------------------------------------------
   -- The port and the FIFO.
   -----------------------------------------------------------------------------

   accept     <= wb_cyc_i and wb_stb_i and not hold_r;
   wb_stall_o <= hold_r;

   -- A write goes in while the FIFO was not full in the cycle before.
   push      <= '1' when count_r < 64 and (hold_r = '1' or
                         (accept = '1' and wb_we_i = '1' and wb_addr_i = "000")) else
                '0';
   push_data <= held_r when hold_r = '1' else
                wb_data_i(15 downto 0);

   p_fifo : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if push = '1' then
            fifo(to_integer(head_r + count_r(5 downto 0))) <= push_data;
         end if;
      end if;
   end process p_fifo;


   p_port : process (clk_i)
   begin
      if rising_edge(clk_i) then
         wb_ack_o <= '0';
         if pop = '1' then
            head_r <= head_r + 1;
         end if;
         if push = '1' and pop = '0' then
            count_r <= count_r + 1;
         elsif push = '0' and pop = '1' then
            count_r <= count_r - 1;
         end if;

         if hold_r = '1' then
            if push = '1' then
               hold_r   <= '0';
               wb_ack_o <= '1';
            end if;
         elsif accept = '1' then
            if wb_we_i = '1' and wb_addr_i = "000" and push = '0' then
               hold_r <= '1';
               held_r <= wb_data_i(15 downto 0);
            else
               wb_ack_o  <= '1';
               wb_data_o <= (others => '0');
               if wb_we_i = '0' and wb_addr_i = "001" then
                  wb_data_o(31 downto 16) <= X"2151";
                  wb_data_o(14 downto 8)  <= std_logic_vector(count_r);
                  if count_r /= 0 then
                     wb_data_o(7) <= '1';
                  end if;
               end if;
            end if;
         end if;

         if rst_i = '1' then
            head_r   <= (others => '0');
            count_r  <= (others => '0');
            hold_r   <= '0';
            wb_ack_o <= '0';
         end if;
      end if;
   end process p_port;


   -----------------------------------------------------------------------------
   -- The synthesizer.
   -----------------------------------------------------------------------------

   i_opm_engine : entity work.opm_engine
      generic map (
         G_ENV_START => G_ENV_START
      )
      port map (
         clk_i   => clk_i,
         rst_i   => rst_i,
         ready_o => ready,
         start_i => start,
         write_i => pop,
         reg_i   => oldest(15 downto 8),
         data_i  => oldest(7 downto 0),
         valid_o => sample_valid_o,
         left_o  => sample_left_o,
         right_o => sample_right_o
      ); -- i_opm_engine

end architecture synthesis;
