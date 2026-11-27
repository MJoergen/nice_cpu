-- The sample player of DEVICES.md §12.7: a FIFO of 4096 stereo samples,
-- played at a rate that a program sets, as words of the sound's I/O.
--
--   2  PCM_DATA   3  PCM_RATE   4  PCM_STATUS   0, 1, 5-7  read 0
--
-- THEORY OF OPERATION
-- A write of PCM_DATA goes into the FIFO, a block RAM of 4096 words,
-- bits 31..16 the left value and 15..0 the right one. While the rate is
-- not 0, the sample clock adds it to an accumulator in each cycle, and a
-- sample is due each time the sum reaches G_CLK_HZ, which it subtracts,
-- as DEVICES.md §12.7 says. A write of the rate keeps the sum. When a
-- sample is due, the oldest in the FIFO is read from the RAM, or, with
-- the FIFO empty, 0 is played and the underrun flag set. The sample comes
-- out in the next cycle on sample_valid_o, sample_left_o, and
-- sample_right_o.
--
-- The port is a pipelined Wishbone slave. It acknowledges each request
-- in the cycle after it accepts it, but a write of PCM_DATA while the
-- FIFO is full and the rate is not 0: that one waits, with STALL high,
-- until a sample takes one from the FIFO, and is acknowledged in the
-- cycle after it goes in. So a full FIFO holds off the acknowledge, as
-- §12.7 asks. With the rate 0, a write to a full FIFO is dropped.
--
-- A write of PCM_STATUS clears the underrun flag, and with bit 31 set
-- resets the player, as rst_i does, at the end of the cycle that accepts
-- it: a sample due then is not played, and a write in the next cycle
-- goes into the empty FIFO. A read of the status never has bit 31 set,
-- so a program that writes back what it read never resets the player.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) The master holds STB and the request while STALL is high.
-- b) STB is high only for requests to the player: the bus decoder
--    decodes the address. The sound is at 0xFFFFFF08-0xFFFFFF0F, the
--    player at 0xFFFFFF0A-0xFFFFFF0C, so the offset is address bits 2..0,
--    and the decoder gives the player offsets 2 to 7 and the synthesizer,
--    src/opm.vhd, 0 and 1.
--
-- RESET
-- Reset, by rst_i or by a write of the status, empties the FIFO, sets
-- the rate to 0, and clears the underrun flag and the accumulator.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

entity pcm is
   generic (
      -- The frequency of clk_i in hertz. A sample is due once in
      -- G_CLK_HZ / rate cycles, at least 20 at 1 MHz and 48000 Hz, and
      -- the sum of the accumulator fits 29 bits up to 268 MHz.
      G_CLK_HZ : natural range 1000000 to 268000000 := 100000000
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
      sample_valid_o : out std_logic := '0';
      sample_left_o  : out std_logic_vector(15 downto 0);
      sample_right_o : out std_logic_vector(15 downto 0)
   );
end entity pcm;

architecture synthesis of pcm is

   constant C_DEPTH    : natural               := 4096;
   constant C_LIMIT    : unsigned(28 downto 0) := to_unsigned(G_CLK_HZ, 29);
   constant C_MIN_RATE : natural               := 1000;
   constant C_MAX_RATE : natural               := 48000;

   type t_ram is array (0 to C_DEPTH - 1) of std_logic_vector(31 downto 0);

   signal ram     : t_ram;
   signal head_r  : unsigned(11 downto 0) := (others => '0');
   signal count_r : unsigned(12 downto 0) := (others => '0');

   signal rate_r     : unsigned(15 downto 0) := (others => '0');
   signal acc_r      : unsigned(28 downto 0) := (others => '0');
   signal due_r      : std_logic             := '0';
   signal underrun_r : std_logic             := '0';
   signal play_r     : std_logic             := '0';
   signal zero_r     : std_logic             := '0';
   signal q_r        : std_logic_vector(31 downto 0);

   signal accept    : std_logic;
   signal hold_r    : std_logic                     := '0';
   signal held_r    : std_logic_vector(31 downto 0) := (others => '0');
   signal full      : std_logic;
   signal push      : std_logic;
   signal push_data : std_logic_vector(31 downto 0);
   signal pop       : std_logic;

   -- A write of the status with bit 31 set, and the reset of all but the
   -- acknowledge.
   signal clear : std_logic;
   signal rst   : std_logic;

begin

   -----------------------------------------------------------------------------
   -- The sample clock.
   -----------------------------------------------------------------------------

   p_clock : process (clk_i)
      variable sum_v : unsigned(28 downto 0);
   begin
      if rising_edge(clk_i) then
         sum_v := acc_r + rate_r;
         due_r <= '0';
         if sum_v >= C_LIMIT then
            sum_v := sum_v - C_LIMIT;
            due_r <= '1';
         end if;
         acc_r <= sum_v;

         if rst = '1' then
            acc_r <= (others => '0');
            due_r <= '0';
         end if;
      end if;
   end process p_clock;

   pop <= '1' when due_r = '1' and count_r /= 0 else
          '0';


   -----------------------------------------------------------------------------
   -- The FIFO's RAM: a write and a read of the oldest, which never meet,
   -- as a read needs a sample in the FIFO and a write room for one.
   -----------------------------------------------------------------------------

   p_ram : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if push = '1' then
            ram(to_integer(head_r + count_r(11 downto 0))) <= push_data;
         end if;
         if pop = '1' then
            q_r <= ram(to_integer(head_r));
         end if;
      end if;
   end process p_ram;


   -----------------------------------------------------------------------------
   -- The samples.
   -----------------------------------------------------------------------------

   p_play : process (clk_i)
   begin
      if rising_edge(clk_i) then
         play_r <= due_r;
         zero_r <= not pop;

         if rst = '1' then
            play_r <= '0';
         end if;
      end if;
   end process p_play;

   sample_valid_o <= play_r;
   sample_left_o  <= (others => '0') when zero_r = '1' else
                     q_r(31 downto 16);
   sample_right_o <= (others => '0') when zero_r = '1' else
                     q_r(15 downto 0);


   -----------------------------------------------------------------------------
   -- The port and the FIFO.
   -----------------------------------------------------------------------------

   accept     <= wb_cyc_i and wb_stb_i and not hold_r;
   wb_stall_o <= hold_r;
   full       <= count_r(12);
   clear      <= '1' when accept = '1' and wb_we_i = '1' and wb_addr_i = "100" and
                          wb_data_i(31) = '1' else
                 '0';
   rst        <= rst_i or clear;

   -- A write goes in while the FIFO was not full in the cycle before.
   push      <= '1' when full = '0' and (hold_r = '1' or
                         (accept = '1' and wb_we_i = '1' and wb_addr_i = "010")) else
                '0';
   push_data <= held_r when hold_r = '1' else
                wb_data_i;

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
         if due_r = '1' and count_r = 0 then
            underrun_r <= '1';
         end if;

         if hold_r = '1' then
            if push = '1' then
               hold_r   <= '0';
               wb_ack_o <= '1';
            end if;
         elsif accept = '1' then
            if wb_we_i = '1' and wb_addr_i = "010" and full = '1' and rate_r /= 0 then
               hold_r <= '1';
               held_r <= wb_data_i;
            else
               wb_ack_o  <= '1';
               wb_data_o <= (others => '0');
               if wb_we_i = '1' then
                  if wb_addr_i = "011" then
                     -- The rate, limited to 1000 to 48000, or 0.
                     if wb_data_i = X"00000000" then
                        rate_r <= (others => '0');
                     elsif unsigned(wb_data_i) < C_MIN_RATE then
                        rate_r <= to_unsigned(C_MIN_RATE, 16);
                     elsif unsigned(wb_data_i) > C_MAX_RATE then
                        rate_r <= to_unsigned(C_MAX_RATE, 16);
                     else
                        rate_r <= unsigned(wb_data_i(15 downto 0));
                     end if;
                  elsif wb_addr_i = "100" then
                     underrun_r <= '0';
                  end if;
               else
                  if wb_addr_i = "011" then
                     wb_data_o(15 downto 0) <= std_logic_vector(rate_r);
                  elsif wb_addr_i = "100" then
                     wb_data_o(31 downto 16) <= std_logic_vector(to_unsigned(C_DEPTH, 16));
                     wb_data_o(15)           <= underrun_r;
                     wb_data_o(12 downto 0)  <= std_logic_vector(count_r);
                  end if;
               end if;
            end if;
         end if;

         if rst = '1' then
            head_r     <= (others => '0');
            count_r    <= (others => '0');
            rate_r     <= (others => '0');
            underrun_r <= '0';
            hold_r     <= '0';
         end if;
         if rst_i = '1' then
            wb_ack_o <= '0';
         end if;
      end if;
   end process p_port;

end architecture synthesis;
