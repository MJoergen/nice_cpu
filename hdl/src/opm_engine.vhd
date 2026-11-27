-- The synthesizer of the sound of DEVICES.md §12, whose registers are the
-- YM2151's: on start_i it applies one write of a register, if it is
-- given one, and computes the next stereo sample. src/opm.vhd gives it
-- its writes from the FIFO and its starts from the sample clock.
--
-- THEORY OF OPERATION
-- The samples are those of the model, emulator/test/opm_model.py, bit
-- for bit, and the engine computes them in the model's order. The chip
-- computes its 32 operators in a pipeline of one slot in each of its
-- clocks, but ymfm, which the model follows, computes them channel by
-- channel, each modulation from the same sample. So the engine is a state
-- machine that computes one step at a time: at 100 MHz a sample has 1788
-- cycles, and the engine takes at most 422.
--
-- A sample goes through four phases, as Opm.sample() of the model does:
-- * LFO_ST, WAVE_ST, and DEPTH_ST step the envelope's counter, the noise,
--   and the LFO, and compute the LFO's AM and PM.
-- * SLOT_A_ST to SLOT_F_ST go through the 32 slots. For each, they read
--   its registers, key it on or off, step its envelope, compute its phase
--   step, and add it to its phase. The model's prepare() computes the
--   step without the PM where the PM is off, which is the step with it,
--   as the PM is then 0 or ignored. So the step is always computed with it.
-- * CH_ST to ACC_ST go through the 8 channels. For each, they compute its
--   operators in the order M1, C1, M2, C2, each from the one before by
--   the table of its connection, and add its output to the left and the
--   right sum. OP_A_ST to OP_E_ST compute one operator, and go back to
--   the state in ret_r.
-- * DAC_ST rounds the sums as the DAC does, and OUT_ST gives them with
--   valid_o.
--
-- The registers that the slots and the channels read are kept as the
-- configurator of github.com/MJoergen/ym2151 keeps them: one RAM of 32
-- bytes for each range of the slots' registers, 0x40 to 0xE0, and one of
-- 8 bytes for each of the channels', 0x20 to 0x38. All are read at the
-- address slot_r, or its low 3 bits, the channel. The other registers
-- that do something are flip-flops, and the rest are not kept, as a read
-- of a register is not possible. The state of each operator, its phase,
-- attenuation, envelope state, and key, is a RAM of 32 entries, and the
-- key that register 0x08 wrote, flip-flops. Each channel keeps the last
-- two values of M1, for its feedback, and the noise keeps 256 bytes for
-- the LFO's noise wave. Each RAM has one write port, from registers that
-- the state machine sets, so that synthesis can map it to distributed
-- RAM. A write lands in the cycle after the state that sets it, and no
-- state reads an entry in that cycle.
--
-- The tables are those of the model, in src/opm_tables_pkg.vhd: the sine
-- and the exponent, as the ROMs of the log-sine and the exponent of
-- github.com/MJoergen/ym2151 do, and the phase steps, the detunes, the
-- increments of the envelope, and DT2.
--
-- The model keeps the envelope's counter in 32 bits, and the engine in 16:
-- a step reads bits 15..2 of it at most, and a carry only goes up.
-- Likewise, the LFO's counter has the 30 bits whose top 8 are its index,
-- and the noise's shift register the 25 bits whose top 8 the noise wave
-- keeps.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) start_i is high only while ready_o is high.
--
-- RESET
-- Reset sets every register as DEVICES.md §12.2 says, every envelope to
-- its end, 0x3FF, with its key off, every phase to 0, and the LFO and the
-- noise to their start, so that the sound is silent. It writes each RAM
-- an entry at a time, in 256 cycles, with ready_o low.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

library work;
   use work.opm_tables_pkg.all;

entity opm_engine is
   generic (
      -- The envelope's counter after reset. DEVICES.md §12.3 wants 0. A
      -- test starts it elsewhere, as it can the model's.
      G_ENV_START : natural range 0 to 65535 := 0
   );
   port (
      clk_i   : in  std_logic;
      rst_i   : in  std_logic;

      -- High while a start is taken
      ready_o : out std_logic;

      -- A start, and with write_i a write of data_i to the register reg_i
      start_i : in  std_logic;
      write_i : in  std_logic;
      reg_i   : in  std_logic_vector(7 downto 0);
      data_i  : in  std_logic_vector(7 downto 0);

      -- High for one cycle with each sample
      valid_o : out std_logic := '0';
      left_o  : out std_logic_vector(15 downto 0) := (others => '0');
      right_o : out std_logic_vector(15 downto 0) := (others => '0')
   );
end entity opm_engine;

architecture synthesis of opm_engine is

   type t_state is (
      CLEAR_ST, IDLE_ST, LFO_ST, WAVE_ST, DEPTH_ST,
      SLOT_A_ST, SLOT_B_ST, SLOT_C_ST, SLOT_D_ST, SLOT_E_ST, SLOT_F_ST,
      CH_ST, M1_DONE_ST, C1_DONE_ST, M2_DONE_ST, C2_DONE_ST, SUM2_ST, SUM3_ST, ACC_ST,
      OP_A_ST, OP_B_ST, OP_C_ST, OP_D_ST, OP_E_ST,
      DAC_ST, OUT_ST
   );

   -- The envelope's states
   constant C_ATTACK  : unsigned(1 downto 0) := "00";
   constant C_DECAY   : unsigned(1 downto 0) := "01";
   constant C_SUSTAIN : unsigned(1 downto 0) := "10";
   constant C_RELEASE : unsigned(1 downto 0) := "11";

   -- The attenuation above which an operator gives 0.
   constant C_QUIET : natural := 16#380#;

   -- For each connection: the inputs of C1, M2, and C2, as numbers of
   -- the values of the model's CONNECTIONS: 0 nothing, 1 M1, 2 C1, 3 M2,
   -- 5 M1 + C1, 6 M1 + M2, and 7 C1 + M2. And whether M1, C1, and M2
   -- go to the output, as bits 0, 1, and 2. C2 always does.
   type t_inputs is array (0 to 7) of natural range 0 to 7;
   type t_outputs is array (0 to 7) of std_logic_vector(2 downto 0);

   constant C_IN2 : t_inputs  := (1, 0, 0, 1, 1, 1, 1, 0);
   constant C_IN3 : t_inputs  := (2, 5, 2, 0, 0, 1, 0, 0);
   constant C_IN4 : t_inputs  := (3, 3, 6, 7, 3, 1, 0, 0);
   constant C_OUT : t_outputs := ("000", "000", "000", "000", "010", "110", "110", "111");

   type t_bytes32 is array (0 to 31) of std_logic_vector(7 downto 0);
   type t_bytes8 is array (0 to 7) of std_logic_vector(7 downto 0);
   type t_bytes256 is array (0 to 255) of std_logic_vector(7 downto 0);
   type t_phases is array (0 to 31) of unsigned(19 downto 0);
   type t_atts is array (0 to 31) of unsigned(9 downto 0);
   type t_states is array (0 to 31) of unsigned(1 downto 0);
   type t_values is array (0 to 7) of signed(13 downto 0);
   type t_rates is array (0 to 3) of unsigned(5 downto 0);

   -- The RAMs of the registers of the slots, 0x40 + s to 0xE0 + s, and
   -- of the channels, 0x20 + c to 0x38 + c.
   signal r40 : t_bytes32 := (others => X"00");
   signal r60 : t_bytes32 := (others => X"00");
   signal r80 : t_bytes32 := (others => X"00");
   signal ra0 : t_bytes32 := (others => X"00");
   signal rc0 : t_bytes32 := (others => X"00");
   signal re0 : t_bytes32 := (others => X"00");
   signal r20 : t_bytes8  := (others => X"C0");
   signal r28 : t_bytes8  := (others => X"00");
   signal r30 : t_bytes8  := (others => X"00");
   signal r38 : t_bytes8  := (others => X"00");

   -- Their write ports: a write enable for each RAM, in the order above.
   signal sreg_we_r   : std_logic_vector(5 downto 0) := (others => '0');
   signal sreg_addr_r : unsigned(4 downto 0)         := (others => '0');
   signal creg_we_r   : std_logic_vector(3 downto 0) := (others => '0');
   signal creg_addr_r : unsigned(2 downto 0)         := (others => '0');
   signal reg_data_r  : std_logic_vector(7 downto 0) := (others => '0');

   -- The other registers that do something
   signal lfo_rst_r : std_logic                    := '0';
   signal ne_r      : std_logic                    := '0';
   signal nfrq_r    : unsigned(4 downto 0)         := (others => '0');
   signal lfrq_r    : unsigned(7 downto 0)         := (others => '0');
   signal amd_r     : unsigned(6 downto 0)         := (others => '0');
   signal pmd_r     : unsigned(6 downto 0)         := (others => '0');
   signal w_r       : unsigned(1 downto 0)         := (others => '0');
   signal keyon_r   : std_logic_vector(31 downto 0) := (others => '0');

   -- The RAM of the operators' state, and its write port
   signal op_phase     : t_phases := (others => (others => '0'));
   signal op_att       : t_atts   := (others => (others => '1'));
   signal op_state     : t_states := (others => C_RELEASE);
   signal op_key       : std_logic_vector(31 downto 0) := (others => '0');
   signal op_we_r      : std_logic            := '0';
   signal op_addr_r    : unsigned(4 downto 0) := (others => '0');
   signal op_phase_d_r : unsigned(19 downto 0) := (others => '0');
   signal op_att_d_r   : unsigned(9 downto 0)  := (others => '0');
   signal op_state_d_r : unsigned(1 downto 0)  := (others => '0');
   signal op_key_d_r   : std_logic             := '0';

   -- The last two values of each channel's M1, and their write port
   signal fb_old     : t_values := (others => (others => '0'));
   signal fb_new     : t_values := (others => (others => '0'));
   signal fb_we_r    : std_logic            := '0';
   signal fb_addr_r  : unsigned(2 downto 0) := (others => '0');
   signal fb_old_d_r : signed(13 downto 0)  := (others => '0');
   signal fb_new_d_r : signed(13 downto 0)  := (others => '0');

   -- The LFO's noise wave, and its write port
   signal wave        : t_bytes256 := (others => X"00");
   signal wave_we_r   : std_logic            := '0';
   signal wave_addr_r : unsigned(7 downto 0) := (others => '0');
   signal wave_d_r    : std_logic_vector(7 downto 0) := (others => '0');

   signal state_r : t_state := CLEAR_ST;
   signal ret_r   : t_state := IDLE_ST;
   signal clr_r   : unsigned(7 downto 0) := (others => '0');
   signal slot_r  : unsigned(4 downto 0) := (others => '0');

   -- The envelope's counter, the noise, and the LFO
   signal env_cnt_r   : unsigned(15 downto 0) := to_unsigned(G_ENV_START, 16);
   signal env_due_r   : std_logic             := '0';
   signal lfsr_r      : std_logic_vector(24 downto 0) := (0 => '1', others => '0');
   signal noise_cnt_r : unsigned(4 downto 0)  := (others => '0');
   signal noise_r     : std_logic             := '0';
   signal lfo_cnt_r   : unsigned(29 downto 0) := (others => '0');
   signal am_raw_r    : unsigned(7 downto 0)  := (others => '0');
   signal pm_raw_r    : signed(7 downto 0)    := (others => '0');
   signal lfo_am_r    : unsigned(7 downto 0)  := (others => '0');
   signal pm_r        : signed(7 downto 0)    := (others => '0');

   -- A slot: what its registers give it, and its state
   signal rates_r     : t_rates := (others => (others => '0'));
   signal sustain_r   : unsigned(9 downto 0)  := (others => '0');
   signal freq_r      : signed(11 downto 0)   := (others => '0');
   signal blk_r       : unsigned(3 downto 0)  := (others => '0');
   signal det_r       : signed(5 downto 0)    := (others => '0');
   signal mul_r       : unsigned(4 downto 0)  := (others => '0');
   signal phase_r     : unsigned(19 downto 0) := (others => '0');
   signal att_r       : unsigned(9 downto 0)  := (others => '0');
   signal st_r        : unsigned(1 downto 0)  := (others => '0');
   signal key_r       : std_logic             := '0';
   signal keyon_bit_r : std_logic             := '0';
   signal rate_r      : unsigned(5 downto 0)  := (others => '0');
   signal inc_r       : natural range 0 to 15 := 0;
   signal ps_addr_r   : unsigned(9 downto 0)  := (others => '0');
   signal clamp_lo_r  : std_logic             := '0';
   signal clamp_hi_r  : std_logic             := '0';
   signal ps_r        : unsigned(11 downto 0) := (others => '0');
   signal step_r      : unsigned(20 downto 0) := (others => '0');
   signal prod_r      : unsigned(19 downto 0) := (others => '0');

   -- A channel
   signal am_r    : unsigned(9 downto 0)  := (others => '0');
   signal con_r   : natural range 0 to 7  := 0;
   signal pan_r   : std_logic_vector(1 downto 0) := (others => '0');
   signal v1_r    : signed(13 downto 0)   := (others => '0');
   signal v2_r    : signed(13 downto 0)   := (others => '0');
   signal v3_r    : signed(13 downto 0)   := (others => '0');
   signal out_r   : signed(15 downto 0)   := (others => '0');
   signal left_r  : signed(18 downto 0)   := (others => '0');
   signal right_r : signed(18 downto 0)   := (others => '0');

   -- An operator
   signal mod_r      : unsigned(9 downto 0)  := (others => '0');
   signal noise_op_r : std_logic             := '0';
   signal idx_r      : unsigned(9 downto 0)  := (others => '0');
   signal quiet_r    : std_logic             := '0';
   signal ea_r       : unsigned(9 downto 0)  := (others => '0');
   signal sin_r      : unsigned(11 downto 0) := (others => '0');
   signal neg_r      : std_logic             := '0';
   signal x_r        : unsigned(12 downto 0) := (others => '0');
   signal pow_r      : unsigned(9 downto 0)  := (others => '0');
   signal sh_r       : unsigned(4 downto 0)  := (others => '0');
   signal op_out_r   : signed(13 downto 0)   := (others => '0');

   -- The effective rate of the raw rate raw, 0 for 0.
   function eff_rate (raw : unsigned(5 downto 0);
                      ksr : unsigned(4 downto 0)) return unsigned is
      variable s_v : unsigned(6 downto 0);
   begin
      if raw = 0 then
         return to_unsigned(0, 6);
      end if;
      s_v := ('0' & raw) + ksr;
      if s_v > 63 then
         return to_unsigned(63, 6);
      end if;
      return s_v(5 downto 0);
   end function eff_rate;

   -- The value of a connection's input, halved for a modulation, in 1024ths.
   function modulation (sel : natural range 0 to 7;
                        v1  : signed(13 downto 0);
                        v2  : signed(13 downto 0);
                        v3  : signed(13 downto 0)) return unsigned is
      variable s_v : signed(14 downto 0);
   begin
      case sel is
         when 1      => s_v := resize(v1, 15);
         when 2      => s_v := resize(v2, 15);
         when 3      => s_v := resize(v3, 15);
         when 5      => s_v := resize(v1, 15) + v2;
         when 6      => s_v := resize(v1, 15) + v3;
         when 7      => s_v := resize(v2, 15) + v3;
         when others => s_v := (others => '0');
      end case;
      return unsigned(s_v(10 downto 1));
   end function modulation;

   -- a + b, clipped to 16 bits.
   function clamp_add (a : signed(15 downto 0);
                       b : signed(13 downto 0)) return signed is
      variable s_v : signed(16 downto 0);
   begin
      s_v := resize(a, 17) + b;
      if s_v > 32767 then
         return to_signed(32767, 16);
      elsif s_v < -32768 then
         return to_signed(-32768, 16);
      end if;
      return s_v(15 downto 0);
   end function clamp_add;

   -- v as the DAC gives it: clipped to 16 bits, and rounded down to the 9
   -- bits below its leading sign bit, or all of them below 512.
   function dac (v : signed(18 downto 0)) return std_logic_vector is
      variable w_v    : signed(15 downto 0);
      variable m_v    : std_logic_vector(14 downto 0);
      variable bits_v : natural range 0 to 15;
   begin
      if v > 32767 then
         return std_logic_vector(to_signed(32767, 16));
      elsif v < -32768 then
         return std_logic_vector(to_signed(-32768, 16));
      end if;
      w_v    := v(15 downto 0);
      m_v    := std_logic_vector(w_v(14 downto 0)) xor (14 downto 0 => w_v(15));
      bits_v := 0;
      for i in 0 to 14 loop
         if m_v(i) = '1' then
            bits_v := i + 1;
         end if;
      end loop;
      for i in 0 to 5 loop
         if i < bits_v - 9 then
            w_v(i) := '0';
         end if;
      end loop;
      return std_logic_vector(w_v);
   end function dac;

begin

   ready_o <= '1' when state_r = IDLE_ST else
              '0';


   -----------------------------------------------------------------------------
   -- The write ports of the RAMs.
   -----------------------------------------------------------------------------

   p_sregs : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if sreg_we_r(0) = '1' then
            r40(to_integer(sreg_addr_r)) <= reg_data_r;
         end if;
         if sreg_we_r(1) = '1' then
            r60(to_integer(sreg_addr_r)) <= reg_data_r;
         end if;
         if sreg_we_r(2) = '1' then
            r80(to_integer(sreg_addr_r)) <= reg_data_r;
         end if;
         if sreg_we_r(3) = '1' then
            ra0(to_integer(sreg_addr_r)) <= reg_data_r;
         end if;
         if sreg_we_r(4) = '1' then
            rc0(to_integer(sreg_addr_r)) <= reg_data_r;
         end if;
         if sreg_we_r(5) = '1' then
            re0(to_integer(sreg_addr_r)) <= reg_data_r;
         end if;
      end if;
   end process p_sregs;


   p_cregs : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if creg_we_r(0) = '1' then
            r20(to_integer(creg_addr_r)) <= reg_data_r;
         end if;
         if creg_we_r(1) = '1' then
            r28(to_integer(creg_addr_r)) <= reg_data_r;
         end if;
         if creg_we_r(2) = '1' then
            r30(to_integer(creg_addr_r)) <= reg_data_r;
         end if;
         if creg_we_r(3) = '1' then
            r38(to_integer(creg_addr_r)) <= reg_data_r;
         end if;
      end if;
   end process p_cregs;


   p_ops : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if op_we_r = '1' then
            op_phase(to_integer(op_addr_r)) <= op_phase_d_r;
            op_att(to_integer(op_addr_r))   <= op_att_d_r;
            op_state(to_integer(op_addr_r)) <= op_state_d_r;
            op_key(to_integer(op_addr_r))   <= op_key_d_r;
         end if;
      end if;
   end process p_ops;


   p_fb : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if fb_we_r = '1' then
            fb_old(to_integer(fb_addr_r)) <= fb_old_d_r;
            fb_new(to_integer(fb_addr_r)) <= fb_new_d_r;
         end if;
      end if;
   end process p_fb;


   p_wave : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if wave_we_r = '1' then
            wave(to_integer(wave_addr_r)) <= wave_d_r;
         end if;
      end if;
   end process p_wave;


   -----------------------------------------------------------------------------
   -- The state machine.
   -----------------------------------------------------------------------------

   p_fsm : process (clk_i)
      variable s_v       : natural range 0 to 31;
      variable c_v       : natural range 0 to 7;
      variable reg_v     : unsigned(7 downto 0);
      variable env_v     : unsigned(15 downto 0);
      variable lfsr_v    : std_logic_vector(24 downto 0);
      variable cnt_v     : unsigned(4 downto 0);
      variable lfo_v     : unsigned(7 downto 0);
      variable am_v      : unsigned(7 downto 0);
      variable prod_v    : signed(15 downto 0);
      variable kc_v      : unsigned(6 downto 0);
      variable keycode_v : unsigned(4 downto 0);
      variable ksr_v     : unsigned(4 downto 0);
      variable sl_v      : unsigned(4 downto 0);
      variable note_v    : unsigned(3 downto 0);
      variable code_v    : unsigned(5 downto 0);
      variable pms_v     : natural range 0 to 7;
      variable delta_v   : signed(11 downto 0);
      variable d_v       : signed(5 downto 0);
      variable dt1_v     : unsigned(2 downto 0);
      variable mul_v     : unsigned(3 downto 0);
      variable att_v     : unsigned(9 downto 0);
      variable st_v      : unsigned(1 downto 0);
      variable f_v       : signed(11 downto 0);
      variable b_v       : unsigned(3 downto 0);
      variable sh_v      : natural range 0 to 15;
      variable idx_v     : natural range 0 to 7;
      variable go_v      : boolean;
      variable e_v       : unsigned(13 downto 0);
      variable t_v       : signed(15 downto 0);
      variable sum_v     : unsigned(10 downto 0);
      variable base_v    : unsigned(16 downto 0);
      variable mprod_v   : unsigned(25 downto 0);
      variable ams_v     : natural range 0 to 3;
      variable fbl_v     : natural range 0 to 7;
      variable fbs_v     : signed(14 downto 0);
      variable a_v       : unsigned(11 downto 0);
      variable q_v       : unsigned(7 downto 0);
      variable v_v       : unsigned(12 downto 0);
      variable n_v       : signed(13 downto 0);
   begin
      if rising_edge(clk_i) then
         sreg_we_r <= (others => '0');
         creg_we_r <= (others => '0');
         op_we_r   <= '0';
         fb_we_r   <= '0';
         wave_we_r <= '0';
         valid_o   <= '0';
         s_v       := to_integer(slot_r);
         c_v       := to_integer(slot_r(2 downto 0));

         case state_r is

            -- Reset writes every entry of the RAMs, one at a time. The
            -- RAMs of the registers share reg_data_r, so the slots' take
            -- cycles 0 to 31 and the channels' cycles 32 to 47.
            when CLEAR_ST =>
               wave_we_r   <= '1';
               wave_addr_r <= clr_r;
               wave_d_r    <= X"00";
               if clr_r < 32 then
                  sreg_we_r    <= (others => '1');
                  sreg_addr_r  <= clr_r(4 downto 0);
                  reg_data_r   <= X"00";
                  op_we_r      <= '1';
                  op_addr_r    <= clr_r(4 downto 0);
                  op_phase_d_r <= (others => '0');
                  op_att_d_r   <= (others => '1');
                  op_state_d_r <= C_RELEASE;
                  op_key_d_r   <= '0';
               elsif clr_r < 40 then
                  -- 0x20 + c is 0xC0, so that each channel goes to both outputs.
                  creg_we_r    <= "0001";
                  creg_addr_r  <= clr_r(2 downto 0);
                  reg_data_r   <= X"C0";
                  fb_we_r      <= '1';
                  fb_addr_r    <= clr_r(2 downto 0);
                  fb_old_d_r   <= (others => '0');
                  fb_new_d_r   <= (others => '0');
               elsif clr_r < 48 then
                  creg_we_r    <= "1110";
                  creg_addr_r  <= clr_r(2 downto 0);
                  reg_data_r   <= X"00";
               end if;
               clr_r <= clr_r + 1;
               if clr_r = 255 then
                  state_r <= IDLE_ST;
               end if;

            -- A write lands before the sample.
            when IDLE_ST =>
               if start_i = '1' then
                  if write_i = '1' then
                     reg_v       := unsigned(reg_i);
                     reg_data_r  <= data_i;
                     sreg_addr_r <= reg_v(4 downto 0);
                     creg_addr_r <= reg_v(2 downto 0);
                     case to_integer(reg_v(7 downto 5)) is
                        when 0 =>
                           case to_integer(reg_v(4 downto 0)) is
                              when 16#01# =>
                                 lfo_rst_r <= data_i(1);

                              when 16#08# =>
                                 -- Bits 3 to 6 key M1, C1, M2, and C2.
                                 c_v                := to_integer(unsigned(data_i(2 downto 0)));
                                 keyon_r(c_v)      <= data_i(3);
                                 keyon_r(16 + c_v) <= data_i(4);
                                 keyon_r(8 + c_v)  <= data_i(5);
                                 keyon_r(24 + c_v) <= data_i(6);

                              when 16#0F# =>
                                 ne_r   <= data_i(7);
                                 nfrq_r <= unsigned(data_i(4 downto 0));

                              when 16#18# =>
                                 lfrq_r <= unsigned(data_i);

                              when 16#19# =>
                                 -- Bit 7 says the PM depth, else the AM depth.
                                 if data_i(7) = '1' then
                                    pmd_r <= unsigned(data_i(6 downto 0));
                                 else
                                    amd_r <= unsigned(data_i(6 downto 0));
                                 end if;

                              when 16#1B# =>
                                 w_r <= unsigned(data_i(1 downto 0));

                              when others =>
                                 null;
                           end case;

                        when 1 =>
                           creg_we_r(to_integer(reg_v(4 downto 3))) <= '1';

                        when others =>
                           sreg_we_r(to_integer(reg_v(7 downto 5)) - 2) <= '1';
                     end case;
                  end if;
                  state_r <= LFO_ST;
               end if;

            -- The envelope's counter steps 3 times in 4 of its counts, and
            -- the noise twice.
            when LFO_ST =>
               env_v := env_cnt_r + 1;
               if env_v(1 downto 0) = "11" then
                  env_v := env_v + 1;
               end if;
               env_cnt_r <= env_v;
               if env_v(1 downto 0) = "00" then
                  env_due_r <= '1';
               else
                  env_due_r <= '0';
               end if;

               lfsr_v := lfsr_r;
               cnt_v  := noise_cnt_r;
               for i in 1 to 2 loop
                  -- The taps are those of the register after the shift.
                  lfsr_v := lfsr_v(23 downto 0) & not (lfsr_v(16) xor lfsr_v(13));
                  if cnt_v >= (nfrq_r xor "11111") then
                     cnt_v   := (others => '0');
                     noise_r <= lfsr_v(17);
                  else
                     cnt_v := cnt_v + 1;
                  end if;
               end loop;
               lfsr_r      <= lfsr_v;
               noise_cnt_r <= cnt_v;

               if lfo_rst_r = '1' then
                  lfo_cnt_r <= (others => '0');
               else
                  lfo_cnt_r <= lfo_cnt_r + shift_left(resize("1" & lfrq_r(3 downto 0), 30),
                                                      to_integer(lfrq_r(7 downto 4)));
               end if;
               state_r <= WAVE_ST;

            -- The noise goes into the wave one ahead of the LFO's index.
            when WAVE_ST =>
               lfo_v       := lfo_cnt_r(29 downto 22);
               wave_we_r   <= '1';
               wave_addr_r <= lfo_v + 1;
               wave_d_r    <= lfsr_r(24 downto 17);
               case to_integer(w_r) is
                  when 0 =>
                     am_raw_r <= not lfo_v;
                     pm_raw_r <= signed(lfo_v);

                  when 1 =>
                     if lfo_v(7) = '1' then
                        am_v := X"00";
                     else
                        am_v := X"FF";
                     end if;
                     am_raw_r <= am_v;
                     pm_raw_r <= signed(am_v xor X"80");

                  when 2 =>
                     if lfo_v(7) = '1' then
                        am_v := lfo_v(6 downto 0) & '0';
                     else
                        am_v := not lfo_v(6 downto 0) & '0';
                     end if;
                     am_raw_r <= am_v;
                     if lfo_v(6) = '1' then
                        pm_raw_r <= signed(am_v);
                     else
                        pm_raw_r <= signed(not am_v);
                     end if;

                  when others =>
                     am_raw_r <= unsigned(wave(to_integer(lfo_v)));
                     pm_raw_r <= signed(wave(to_integer(lfo_v)));
               end case;
               state_r <= DEPTH_ST;

            when DEPTH_ST =>
               lfo_am_r <= resize(shift_right(am_raw_r * amd_r, 7), 8);
               prod_v   := pm_raw_r * signed('0' & std_logic_vector(pmd_r));
               pm_r     <= resize(shift_right(prod_v, 7), 8);
               slot_r   <= (others => '0');
               state_r  <= SLOT_A_ST;

            -- What the registers give the slot.
            when SLOT_A_ST =>
               kc_v      := unsigned(r28(c_v)(6 downto 0));
               keycode_v := kc_v(6 downto 2);
               ksr_v     := shift_right(keycode_v, 3 - to_integer(unsigned(r80(s_v)(7 downto 6))));
               rates_r(0) <= eff_rate(unsigned(r80(s_v)(4 downto 0)) & '0', ksr_v);
               rates_r(1) <= eff_rate(unsigned(ra0(s_v)(4 downto 0)) & '0', ksr_v);
               rates_r(2) <= eff_rate(unsigned(rc0(s_v)(4 downto 0)) & '0', ksr_v);
               rates_r(3) <= eff_rate(unsigned(re0(s_v)(3 downto 0)) & "10", ksr_v);

               -- D1L 15 is 31, 93 dB.
               sl_v := '0' & unsigned(re0(s_v)(7 downto 4));
               if sl_v = 15 then
                  sl_v := to_unsigned(31, 5);
               end if;
               sustain_r <= sl_v & "00000";

               -- The note in 64ths of a semitone, 12 semitones in an octave.
               note_v  := kc_v(3 downto 0);
               pms_v   := to_integer(unsigned(r38(c_v)(6 downto 4)));
               delta_v := to_signed(C_DT2(to_integer(unsigned(rc0(s_v)(7 downto 6)))), 12);
               case pms_v is
                  when 0      => null;
                  when 6      => delta_v := delta_v + shift_left(resize(pm_r, 12), 1);
                  when 7      => delta_v := delta_v + shift_left(resize(pm_r, 12), 2);
                  when others => delta_v := delta_v + shift_right(resize(pm_r, 12), 6 - pms_v);
               end case;
               code_v := resize(note_v - note_v(3 downto 2), 6);
               freq_r <= signed(unsigned'(code_v & "000000"))
                         + signed(resize(unsigned(r30(c_v)(7 downto 2)), 12)) + delta_v;
               blk_r  <= '0' & kc_v(6 downto 4);

               dt1_v := unsigned(r40(s_v)(6 downto 4));
               d_v   := to_signed(C_DETUNE(to_integer(keycode_v & dt1_v(1 downto 0))), 6);
               if dt1_v(2) = '1' then
                  det_r <= -d_v;
               else
                  det_r <= d_v;
               end if;
               mul_v := unsigned(r40(s_v)(3 downto 0));
               if mul_v = 0 then
                  mul_r <= to_unsigned(1, 5);
               else
                  mul_r <= mul_v & '0';
               end if;

               phase_r     <= op_phase(s_v);
               att_r       <= op_att(s_v);
               st_r        <= op_state(s_v);
               key_r       <= op_key(s_v);
               keyon_bit_r <= keyon_r(s_v);
               state_r     <= SLOT_B_ST;

            -- The key, the envelope's state, and the phase step's octave.
            when SLOT_B_ST =>
               att_v := att_r;
               st_v  := st_r;
               if keyon_bit_r /= key_r then
                  key_r <= keyon_bit_r;
                  if keyon_bit_r = '1' then
                     if st_v /= C_ATTACK then
                        st_v    := C_ATTACK;
                        phase_r <= (others => '0');
                        if rates_r(0) >= 62 then
                           att_v := (others => '0');
                        end if;
                     end if;
                  else
                     st_v := C_RELEASE;
                  end if;
               end if;
               if env_due_r = '1' then
                  if st_v = C_ATTACK and att_v = 0 then
                     st_v := C_DECAY;
                  end if;
                  if st_v = C_DECAY and att_v >= sustain_r then
                     st_v := C_SUSTAIN;
                  end if;
               end if;
               att_r  <= att_v;
               st_r   <= st_v;
               rate_r <= rates_r(to_integer(st_v));

               f_v        := freq_r;
               b_v        := blk_r;
               clamp_lo_r <= '0';
               clamp_hi_r <= '0';
               if f_v < 0 then
                  f_v := f_v + 768;
                  if b_v = 0 then
                     clamp_lo_r <= '1';
                  else
                     b_v := b_v - 1;
                  end if;
               elsif f_v >= 768 then
                  f_v := f_v - 768;
                  if f_v >= 768 then
                     b_v := b_v + 1;
                     f_v := f_v - 768;
                  end if;
                  if b_v >= 7 then
                     clamp_hi_r <= '1';
                  else
                     b_v := b_v + 1;
                  end if;
               end if;
               ps_addr_r <= unsigned(f_v(9 downto 0));
               blk_r     <= b_v;
               state_r   <= SLOT_C_ST;

            -- The increment of the envelope, once in 3 samples, at the
            -- rate's times, and else 0, which changes nothing.
            when SLOT_C_ST =>
               ps_r  <= to_unsigned(C_PHASE_STEP(to_integer(ps_addr_r)), 12);
               inc_r <= 0;
               if env_due_r = '1' then
                  sh_v := to_integer(rate_r(5 downto 2));
                  if sh_v >= 11 then
                     go_v  := true;
                     idx_v := to_integer(env_cnt_r(4 downto 2));
                  else
                     go_v  := (env_cnt_r(12 downto 2) and shift_right(to_unsigned(16#7FF#, 11), sh_v)) = 0;
                     e_v   := shift_right(env_cnt_r(15 downto 2), 11 - sh_v);
                     idx_v := to_integer(e_v(2 downto 0));
                  end if;
                  -- An attack at 62 or 63 starts at 0, and does not step.
                  if go_v and (st_r /= C_ATTACK or rate_r < 62) then
                     inc_r <= C_INCREMENT(to_integer(rate_r) * 8 + idx_v);
                  end if;
               end if;
               state_r <= SLOT_D_ST;

            -- The envelope's step, and the phase step, with DT1.
            when SLOT_D_ST =>
               if st_r = C_ATTACK then
                  -- att += (-(att + 1) * inc) >> 4, which ends at 0.
                  t_v   := to_signed(-(to_integer(att_r) + 1) * inc_r, 16);
                  t_v   := signed(resize(att_r, 16)) + shift_right(t_v, 4);
                  att_r <= unsigned(t_v(9 downto 0));
               else
                  sum_v := resize(att_r, 11) + inc_r;
                  if sum_v >= 16#400# then
                     att_r <= (others => '1');
                  else
                     att_r <= sum_v(9 downto 0);
                  end if;
               end if;

               if clamp_lo_r = '1' then
                  base_v := to_unsigned((C_PHASE_STEP(0) * 32) / 128, 17);
               elsif clamp_hi_r = '1' then
                  base_v := to_unsigned(C_PHASE_STEP(767) * 32, 17);
               else
                  base_v := shift_right(ps_r & "00000", 7 - to_integer(blk_r(2 downto 0)));
               end if;
               step_r  <= unsigned(signed(resize(base_v, 21)) + det_r);
               state_r <= SLOT_E_ST;

            -- MUL, which is 1/2 for 0: the bits of the phase that matter
            -- are those of the product's low 21 bits.
            when SLOT_E_ST =>
               mprod_v := step_r * mul_r;
               prod_r  <= mprod_v(20 downto 1);
               state_r <= SLOT_F_ST;

            when SLOT_F_ST =>
               op_we_r      <= '1';
               op_addr_r    <= slot_r;
               op_phase_d_r <= phase_r + prod_r;
               op_att_d_r   <= att_r;
               op_state_d_r <= st_r;
               op_key_d_r   <= key_r;
               slot_r       <= slot_r + 1;
               if slot_r = 31 then
                  left_r  <= (others => '0');
                  right_r <= (others => '0');
                  state_r <= CH_ST;
               else
                  state_r <= SLOT_A_ST;
               end if;

            -- A channel: its AM, and M1 with its feedback. slot_r is M1's.
            when CH_ST =>
               ams_v := to_integer(unsigned(r38(c_v)(1 downto 0)));
               if ams_v = 0 then
                  am_r <= (others => '0');
               else
                  am_r <= shift_left(resize(lfo_am_r, 10), ams_v - 1);
               end if;
               con_r <= to_integer(unsigned(r20(c_v)(2 downto 0)));
               pan_r <= r20(c_v)(7 downto 6);
               fbl_v := to_integer(unsigned(r20(c_v)(5 downto 3)));
               if fbl_v = 0 then
                  mod_r <= (others => '0');
               else
                  fbs_v := shift_right(resize(fb_old(c_v), 15) + fb_new(c_v), 10 - fbl_v);
                  mod_r <= unsigned(fbs_v(9 downto 0));
               end if;
               noise_op_r <= '0';
               ret_r      <= M1_DONE_ST;
               state_r    <= OP_A_ST;

            when M1_DONE_ST =>
               v1_r       <= op_out_r;
               fb_we_r    <= '1';
               fb_addr_r  <= slot_r(2 downto 0);
               fb_old_d_r <= fb_new(c_v);
               fb_new_d_r <= op_out_r;
               if r20(c_v)(7 downto 6) = "00" then
                  state_r <= ACC_ST;
               else
                  slot_r  <= slot_r + 16;
                  mod_r   <= modulation(C_IN2(con_r), op_out_r, v2_r, v3_r);
                  ret_r   <= C1_DONE_ST;
                  state_r <= OP_A_ST;
               end if;

            when C1_DONE_ST =>
               v2_r    <= op_out_r;
               slot_r  <= slot_r - 8;
               mod_r   <= modulation(C_IN3(con_r), v1_r, op_out_r, v3_r);
               ret_r   <= M2_DONE_ST;
               state_r <= OP_A_ST;

            -- With NE, the noise replaces C2 of channel 7.
            when M2_DONE_ST =>
               v3_r    <= op_out_r;
               slot_r  <= slot_r + 16;
               mod_r   <= modulation(C_IN4(con_r), v1_r, v2_r, op_out_r);
               if c_v = 7 then
                  noise_op_r <= ne_r;
               end if;
               ret_r   <= C2_DONE_ST;
               state_r <= OP_A_ST;

            -- The output, clipped after each operator added to it.
            when C2_DONE_ST =>
               out_r <= resize(op_out_r, 16);
               if C_OUT(con_r)(0) = '1' then
                  out_r <= clamp_add(resize(op_out_r, 16), v1_r);
               end if;
               state_r <= SUM2_ST;

            when SUM2_ST =>
               if C_OUT(con_r)(1) = '1' then
                  out_r <= clamp_add(out_r, v2_r);
               end if;
               state_r <= SUM3_ST;

            when SUM3_ST =>
               if C_OUT(con_r)(2) = '1' then
                  out_r <= clamp_add(out_r, v3_r);
               end if;
               state_r <= ACC_ST;

            -- A channel with neither output, which M1_DONE_ST skips to,
            -- adds nothing.
            when ACC_ST =>
               if pan_r(0) = '1' then
                  left_r <= left_r + out_r;
               end if;
               if pan_r(1) = '1' then
                  right_r <= right_r + out_r;
               end if;
               slot_r <= "00" & (slot_r(2 downto 0) + 1);
               if slot_r(2 downto 0) = 7 then
                  state_r <= DAC_ST;
               else
                  state_r <= CH_ST;
               end if;

            -- An operator: its attenuation, and the index of its sine.
            when OP_A_ST =>
               a_v := resize(op_att(s_v), 12) + (unsigned(r60(s_v)(6 downto 0)) & "000");
               if ra0(s_v)(7) = '1' then
                  a_v := a_v + am_r;
               end if;
               if a_v > 16#3FF# then
                  ea_r <= (others => '1');
               else
                  ea_r <= a_v(9 downto 0);
               end if;
               if op_att(s_v) > C_QUIET then
                  quiet_r <= '1';
               else
                  quiet_r <= '0';
               end if;
               idx_r   <= op_phase(s_v)(19 downto 10) + mod_r;
               state_r <= OP_B_ST;

            -- The sine is the first quarter of its wave, mirrored.
            when OP_B_ST =>
               if idx_r(8) = '1' then
                  q_v := not idx_r(7 downto 0);
               else
                  q_v := idx_r(7 downto 0);
               end if;
               sin_r   <= to_unsigned(C_SIN(to_integer(q_v)), 12);
               neg_r   <= idx_r(9);
               state_r <= OP_C_ST;

            when OP_C_ST =>
               x_r     <= resize(sin_r, 13) + (ea_r & "00");
               state_r <= OP_D_ST;

            when OP_D_ST =>
               pow_r   <= to_unsigned(C_POW(to_integer(x_r(7 downto 0))), 10);
               sh_r    <= x_r(12 downto 8);
               state_r <= OP_E_ST;

            -- The level, 2^(-x/256) in 13 bits, with the sine's sign.
            when OP_E_ST =>
               v_v := shift_right("1" & pow_r & "00", to_integer(sh_r));
               if noise_op_r = '1' then
                  n_v := signed(resize((ea_r xor "1111111111") & '0', 14));
                  if noise_r = '1' then
                     op_out_r <= -n_v;
                  else
                     op_out_r <= n_v;
                  end if;
               elsif quiet_r = '1' then
                  op_out_r <= (others => '0');
               elsif neg_r = '1' then
                  op_out_r <= -signed(resize(v_v, 14));
               else
                  op_out_r <= signed(resize(v_v, 14));
               end if;
               state_r <= ret_r;

            when DAC_ST =>
               left_o  <= dac(left_r);
               right_o <= dac(right_r);
               state_r <= OUT_ST;

            when OUT_ST =>
               valid_o <= '1';
               state_r <= IDLE_ST;

         end case;

         if rst_i = '1' then
            state_r     <= CLEAR_ST;
            clr_r       <= (others => '0');
            lfo_rst_r   <= '0';
            ne_r        <= '0';
            nfrq_r      <= (others => '0');
            lfrq_r      <= (others => '0');
            amd_r       <= (others => '0');
            pmd_r       <= (others => '0');
            w_r         <= (others => '0');
            keyon_r     <= (others => '0');
            env_cnt_r   <= to_unsigned(G_ENV_START, 16);
            lfsr_r      <= (0 => '1', others => '0');
            noise_cnt_r <= (others => '0');
            noise_r     <= '0';
            lfo_cnt_r   <= (others => '0');
            valid_o     <= '0';
         end if;
      end if;
   end process p_fsm;

end architecture synthesis;
