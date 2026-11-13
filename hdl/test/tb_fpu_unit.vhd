-- A test of src/fpu_unit.vhd against the model, at a small width and at
-- the FPU's.
--
-- THEORY OF OPERATION
-- By default the unit has 4 bits of exponent and 3 of fraction, and a
-- short format of 3 and 2, and multiplies 3 bits at a time, so that a
-- product takes two steps. test/fpu_unit_vectors.py writes each operation
-- on every operand, or every pair of operands, with the result and the
-- flags of the model emulator/test/fpu_model.py, to the file G_VECTORS.
-- With the generics of the FPU, binary64, binary32, and 17 bits, it
-- writes random operands instead, with --wide. This replays each
-- line: it starts the operation, waits for DONE, and compares the result
-- and the flags. It reports the first 20 differences, then how many lines
-- differ, and the most cycles an operation took. The run stops with
-- status 0 if none differ, and 1 if any do.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

   use std.textio.all;
   use std.env.all;

library work;
   use work.fpu_pkg.all;

entity tb_fpu_unit is
   generic (
      G_VECTORS : string  := "fpu_unit.vectors";
      G_EBITS   : natural := 4;
      G_FBITS   : natural := 3;
      G_SEBITS  : natural := 3;
      G_SFBITS  : natural := 2;
      G_CHUNK   : natural := 3
   );
end entity tb_fpu_unit;

architecture simulation of tb_fpu_unit is

   constant C_W : natural := 1 + G_EBITS + G_FBITS;

   signal clk   : std_logic := '0';
   signal rst   : std_logic := '1';
   signal start : std_logic := '0';
   signal op    : t_fpu_op  := OP_ADD;
   signal rnd   : t_fpu_rnd := RND_EVEN;
   signal short : std_logic := '0';
   signal a     : std_logic_vector(C_W - 1 downto 0) := (others => '0');
   signal b     : std_logic_vector(C_W - 1 downto 0) := (others => '0');
   signal k     : std_logic_vector(15 downto 0)      := (others => '0');
   signal busy  : std_logic;
   signal done  : std_logic;
   signal res   : std_logic_vector(C_W - 1 downto 0);
   signal flags : std_logic_vector(2 downto 0);

   signal running : boolean := true;

begin

   clk <= not clk after 5 ns when running else '0';


   i_fpu_unit : entity work.fpu_unit
      generic map (
         G_EBITS  => G_EBITS,
         G_FBITS  => G_FBITS,
         G_SEBITS => G_SEBITS,
         G_SFBITS => G_SFBITS,
         G_CHUNK  => G_CHUNK
      )
      port map (
         clk_i    => clk,
         rst_i    => rst,
         start_i  => start,
         op_i     => op,
         rnd_i    => rnd,
         short_i  => short,
         a_i      => a,
         b_i      => b,
         k_i      => k,
         busy_o   => busy,
         done_o   => done,
         result_o => res,
         flags_o  => flags
      ); -- i_fpu_unit


   p_test : process
      file     vec_f    : text;
      variable l_v      : line;
      variable op_v     : integer;
      variable rnd_v    : integer;
      variable sh_v     : integer;
      variable a_v      : std_logic_vector(C_W - 1 downto 0);
      variable b_v      : std_logic_vector(C_W - 1 downto 0);
      variable k_v      : integer;
      variable r_v      : std_logic_vector(C_W - 1 downto 0);
      variable f_v      : integer;
      variable lines_v  : natural := 0;
      variable fails_v  : natural := 0;
      variable cycles_v : natural;
      variable most_v   : natural := 0;
   begin
      file_open(vec_f, G_VECTORS, read_mode);
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      rst <= '0';
      wait until rising_edge(clk);

      while not endfile(vec_f) loop
         readline(vec_f, l_v);
         read(l_v, op_v);
         read(l_v, rnd_v);
         read(l_v, sh_v);
         hread(l_v, a_v);
         hread(l_v, b_v);
         read(l_v, k_v);
         hread(l_v, r_v);
         read(l_v, f_v);
         lines_v := lines_v + 1;

         op    <= t_fpu_op'val(op_v);
         rnd   <= t_fpu_rnd'val(rnd_v);
         short <= '1' when sh_v = 1 else '0';
         a     <= a_v;
         b     <= b_v;
         k     <= std_logic_vector(to_signed(k_v, 16));
         start <= '1';
         wait until rising_edge(clk);
         start    <= '0';
         cycles_v := 1;
         while done /= '1' loop
            wait until rising_edge(clk);
            cycles_v := cycles_v + 1;
         end loop;
         if cycles_v > most_v then
            most_v := cycles_v;
         end if;

         if res /= r_v or to_integer(unsigned(flags)) /= f_v then
            fails_v := fails_v + 1;
            if fails_v <= 20 then
               report "tb_fpu_unit: line " & integer'image(lines_v) & ": " &
                      t_fpu_op'image(t_fpu_op'val(op_v)) & " " &
                      t_fpu_rnd'image(t_fpu_rnd'val(rnd_v)) & " short=" & integer'image(sh_v) &
                      " a=" & to_hstring(a_v) &
                      " b=" & to_hstring(b_v) & " k=" & integer'image(k_v) &
                      ": got " & to_hstring(res) & " flags " &
                      integer'image(to_integer(unsigned(flags))) &
                      ", want " & to_hstring(r_v) & " flags " & integer'image(f_v)
                  severity note;
            end if;
         end if;
      end loop;

      report "tb_fpu_unit: " & integer'image(lines_v) & " lines, " & integer'image(fails_v) &
             " differ, at most " & integer'image(most_v) & " cycles"
         severity note;
      running <= false;
      if fails_v = 0 then
         stop(0);
      else
         stop(1);
      end if;
      wait;
   end process p_test;

end architecture simulation;

