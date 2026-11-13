-- A test of src/fpu.vhd against the vectors of the model,
-- emulator/test/fpu_vectors.py.
--
-- THEORY OF OPERATION
-- Each line of G_VECTORS is the state before an access, the access, and
-- the state after it. This replays a line over the bus, as a master of
-- pipelined Wishbone: it sets the state before, with CLEAR 1, a write of
-- X_LO and of X_HI for each value from the deepest, and a write of STATUS
-- for the flags. It does the access, and compares the word a read
-- returns. It then reads STATUS for the depth and the flags, and reads X
-- and drops it for each value, and compares those with the state after.
-- After the vectors, it checks the waits of §11.2: while DIV runs, a read
-- of CMD is acknowledged in the next cycle, and a read of X waits for the
-- result.
-- It reports the first 20 lines that differ, then how many differ, and
-- stops with status 0 if none do, and 1 if any do.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

   use std.textio.all;
   use std.env.all;

entity tb_fpu is
   generic (
      G_VECTORS : string := "fpu.vectors"
   );
end entity tb_fpu;

architecture simulation of tb_fpu is

   subtype t_word64 is std_logic_vector(63 downto 0);

   type t_stack is array (0 to 15) of t_word64;

   signal clk     : std_logic := '0';
   signal rst     : std_logic := '1';
   signal cyc     : std_logic := '0';
   signal stb     : std_logic := '0';
   signal stall   : std_logic;
   signal ack     : std_logic;
   signal we      : std_logic := '0';
   signal addr    : std_logic_vector(2 downto 0)  := (others => '0');
   signal wdata   : std_logic_vector(31 downto 0) := (others => '0');
   signal rdata   : std_logic_vector(31 downto 0);
   signal running : boolean := true;

begin

   clk <= not clk after 5 ns when running else '0';


   i_fpu : entity work.fpu
      port map (
         clk_i      => clk,
         rst_i      => rst,
         wb_cyc_i   => cyc,
         wb_stb_i   => stb,
         wb_stall_o => stall,
         wb_ack_o   => ack,
         wb_we_i    => we,
         wb_addr_i  => addr,
         wb_data_i  => wdata,
         wb_data_o  => rdata
      ); -- i_fpu


   p_test : process
      file     vec_f   : text;
      variable l_v     : line;
      variable c_v     : character;
      variable kind_v  : character;
      variable lines_v : natural := 0;
      variable fails_v : natural := 0;
      variable bf_v    : std_logic_vector(3 downto 0);
      variable bd_v    : std_logic_vector(7 downto 0);
      variable bs_v    : t_stack;
      variable af_v    : std_logic_vector(3 downto 0);
      variable ad_v    : std_logic_vector(7 downto 0);
      variable as_v    : t_stack;
      variable reg_v   : std_logic_vector(3 downto 0);
      variable word_v  : std_logic_vector(31 downto 0);
      variable rd_v    : std_logic_vector(31 downto 0);
      variable lo_v    : std_logic_vector(31 downto 0);
      variable t_v     : time;

      -- One access: the request until it is accepted, then the ack.
      procedure bus_access(w : std_logic;
                       a : natural;
                       d : std_logic_vector(31 downto 0);
                       r : out std_logic_vector(31 downto 0)) is
      begin
         cyc   <= '1';
         stb   <= '1';
         we    <= w;
         addr  <= std_logic_vector(to_unsigned(a, 3));
         wdata <= d;
         wait until rising_edge(clk);
         while stall = '1' loop
            wait until rising_edge(clk);
         end loop;
         stb <= '0';
         while ack /= '1' loop
            wait until rising_edge(clk);
         end loop;
         r   := rdata;
         cyc <= '0';
      end procedure bus_access;

      procedure write(a : natural;
                      d : std_logic_vector(31 downto 0)) is
         variable r_v : std_logic_vector(31 downto 0);
      begin
         bus_access('1', a, d, r_v);
      end procedure write;

      procedure read(a : natural;
                     r : out std_logic_vector(31 downto 0)) is
      begin
         bus_access('0', a, X"00000000", r);
      end procedure read;

      -- A state: the flags, the depth, and the values, the deepest first.
      procedure read_state(f : out std_logic_vector(3 downto 0);
                           d : out std_logic_vector(7 downto 0);
                           s : out t_stack) is
         variable d_v : std_logic_vector(7 downto 0);
      begin
         hread(l_v, f);
         hread(l_v, d_v);
         d := d_v;
         for i in 0 to to_integer(unsigned(d_v)) - 1 loop
            hread(l_v, s(i));
         end loop;
      end procedure read_state;

      procedure fail(text : string) is
      begin
         fails_v := fails_v + 1;
         if fails_v <= 20 then
            report "tb_fpu: line " & integer'image(lines_v) & ": " & text
               severity note;
         end if;
      end procedure fail;

   begin
      file_open(vec_f, G_VECTORS, read_mode);
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      rst <= '0';
      wait until rising_edge(clk);

      while not endfile(vec_f) loop
         readline(vec_f, l_v);
         if l_v'length = 0 or l_v(l_v'left) = '#' then
            next;
         end if;
         lines_v := lines_v + 1;
         read_state(bf_v, bd_v, bs_v);
         read(l_v, c_v);              -- the space
         read(l_v, c_v);              -- ':'
         read(l_v, c_v);
         read(l_v, kind_v);           -- R or W
         hread(l_v, reg_v);
         hread(l_v, word_v);
         read(l_v, c_v);
         read(l_v, c_v);              -- ':'
         read_state(af_v, ad_v, as_v);

         -- The state before.
         write(4, X"00000101");
         for i in 0 to to_integer(unsigned(bd_v)) - 1 loop
            write(0, bs_v(i)(31 downto 0));
            write(1, bs_v(i)(63 downto 32));
         end loop;
         write(5, X"00000" & bf_v & X"00");

         -- The access.
         if kind_v = 'W' then
            write(to_integer(unsigned(reg_v(2 downto 0))), word_v);
         else
            read(to_integer(unsigned(reg_v(2 downto 0))), rd_v);
            if rd_v /= word_v then
               fail("read " & to_hstring(reg_v) & " gave " & to_hstring(rd_v) & ", want " &
                    to_hstring(word_v));
            end if;
         end if;

         -- The state after.
         read(5, rd_v);
         if rd_v(11 downto 8) /= af_v or unsigned(rd_v(4 downto 0)) /= unsigned(ad_v) then
            fail("STATUS " & to_hstring(rd_v) & ", want flags " & to_hstring(af_v) &
                 " depth " & to_hstring(ad_v));
         else
            for i in to_integer(unsigned(ad_v)) - 1 downto 0 loop
               read(0, lo_v);
               read(1, rd_v);
               if rd_v & lo_v /= as_v(i) then
                  fail("value " & integer'image(i) & " is " & to_hstring(rd_v & lo_v) &
                       ", want " & to_hstring(as_v(i)));
                  exit;
               end if;
               write(4, X"00000003");
            end loop;
         end if;
      end loop;

      -- 7 / 2 = 3.5: a read of CMD at once, then a read of X after DIV.
      write(4, X"00000101");
      write(3, X"00000007");
      write(3, X"00000002");
      write(4, X"00000013");
      t_v := now;
      read(4, rd_v);
      if now - t_v > 20 ns or rd_v /= X"00000000" then
         fail("a read of CMD took " & time'image(now - t_v) & " and gave " & to_hstring(rd_v));
      end if;
      t_v := now;
      read(1, rd_v);
      if now - t_v < 200 ns or rd_v /= X"400C0000" then
         fail("a read of X_HI after DIV took " & time'image(now - t_v) & " and gave " &
              to_hstring(rd_v));
      end if;

      report "tb_fpu: " & integer'image(lines_v) & " lines, " & integer'image(fails_v) &
             " differ"
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
