-- A test of src/fpu.vhd against the vectors of the model,
-- emulator/test/fpu_vectors.py.
--
-- THEORY OF OPERATION
-- Each line of G_VECTORS is the state before an access, the access, and
-- the state after it. This replays a line over the bus, as a master of
-- pipelined Wishbone: it sets the state before, with CLEAR 1, a write of
-- X_LO and of X_HI for each value from the deepest, and a write of STATUS
-- for the flags. It does the access, and compares the word a read
-- returns. After every third command, the next access comes at once, so
-- that it waits for the command: a read of X_LO, X_HI, X_S, X_W, STATUS,
-- or REL, each read again after it, or a write of X_LO, X_HI, X_S, or
-- STATUS, which changes the state after as the test knows. It then reads
-- STATUS for the depth and the flags, and reads X and drops it for each
-- value, and compares those with the state after. For each other command
-- it counts the cycles from the command's request to the ACK of that
-- read of STATUS, and keeps the most for each command, which must not
-- exceed its bound below. test/fpu_slow_vectors.py adds the slowest
-- commands to the vectors.
-- After the vectors, it checks the waits of §11.1: while DIV runs, a read
-- of CMD is acknowledged two cycles after it is accepted, as any request
-- is when it need not wait, and a read of X waits for the result.
-- Every 1000th command of the vectors is reset while it runs, and so are
-- DIV, and DIV with two reads of X waiting, whose ACKs the master gives
-- up as it drops CYC. A reset must leave no ACK, no value, and no flag,
-- and the command after it must run.
-- It reports the first 20 lines that differ, the most cycles of each
-- command that takes more than a few, with its line and its bound, and a
-- command over its bound, then how many lines differ or commands are over
-- their bounds, and the most cycles from an accepted request to its ACK,
-- with its line, and stops with status 0 if none, and 1 if any.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

   use std.textio.all;
   use std.env.all;

entity tb_fpu is
   generic (
      G_VECTORS : string  := "fpu.vectors";
      -- With G_SLOW > 0, each command of the vectors that takes more
      -- cycles than this is reported, for a search of the slow ones.
      G_SLOW    : natural := 0
   );
end entity tb_fpu;

architecture simulation of tb_fpu is

   subtype t_word64 is std_logic_vector(63 downto 0);

   type t_stack is array (0 to 15) of t_word64;

   type t_counts is array (0 to 255) of natural;

   -- The most cycles that each command may take, from its request to the
   -- ACK of the read of STATUS after it, which adds some 6 cycles: the
   -- times of DEVICES.md §11.5 with a margin, and for the commands that it
   -- gives no time, some twice what they take. DIGITS, which §11.5 gives up
   -- to some 3400, takes at most 3363 on the slowest values that a scan
   -- found (test/fpu_slow_vectors.py), and its bound is 20% above that,
   -- as are those of SIN and COS, at most 1576, TAN, at most 2079, ASIN,
   -- 1124, ACOS, 871, ATAN, 946, and ATAN2, 1329.
   -- A command of the stack, and a number that is not a command, takes a
   -- few cycles.
   function bound (num : natural) return natural is
   begin
      case num is
         when 16#10# to 16#12# => return 60;
         when 16#13# | 16#14# | 16#1E# => return 120;
         when 16#1A# => return 150;
         when 16#1D# => return 2400;
         when 16#39# => return 1500;
         when 16#3A# => return 4000;
         when 16#17# to 16#19# | 16#1B# | 16#1C# | 16#20# to 16#24# | 16#28# to 16#2B# | 16#38# |
              16#3B# to 16#3D# | 16#60# to 16#65# => return 120;
         when 16#66# | 16#67# => return 200;
         when 16#40# | 16#41# => return 1900;
         when 16#42# => return 2500;
         when 16#43# => return 1350;
         when 16#44# => return 1050;
         when 16#45# => return 1150;
         when 16#46# => return 1600;
         when others => return 30;
      end case;
   end function bound;

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
      variable most_v  : natural := 0;
      variable mline_v : natural := 0;
      variable t_cmd_v : time;
      variable cyc_v   : natural;
      variable num_v   : natural;
      variable cmost_v : t_counts := (others => 0);
      variable cline_v : t_counts := (others => 0);
      variable timed_v : boolean;
      variable reset_v : boolean;
      variable ncmd_v  : natural := 0;

      procedure hung(n : natural) is
      begin
         if n = 10000 then
            report "tb_fpu: line " & integer'image(lines_v) & ": no ACK in 10000 cycles"
               severity note;
            stop(1);
         end if;
      end procedure hung;

      -- One access: the request until it is accepted, then the ack. An
      -- access that waits 10000 cycles, more than any command takes, ends
      -- the test, as the FPU will not answer it.
      procedure bus_access(w : std_logic;
                       a : natural;
                       d : std_logic_vector(31 downto 0);
                       r : out std_logic_vector(31 downto 0)) is
         variable n_v : natural;
      begin
         cyc   <= '1';
         stb   <= '1';
         we    <= w;
         addr  <= std_logic_vector(to_unsigned(a, 3));
         wdata <= d;
         wait until rising_edge(clk);
         n_v := 0;
         while stall = '1' loop
            wait until rising_edge(clk);
            n_v := n_v + 1;
            hung(n_v);
         end loop;
         stb <= '0';
         while ack /= '1' loop
            wait until rising_edge(clk);
            n_v := n_v + 1;
            hung(n_v);
         end loop;
         if n_v > most_v then
            most_v  := n_v;
            mline_v := lines_v;
         end if;
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

      -- An access right after a command, which waits for it, and the state
      -- after the command and that access: k = 0 to 5 reads X_LO, X_HI,
      -- X_S, X_W, STATUS, or REL, and then again, which must give the
      -- same, as a read has no side effect (DEVICES.md §11.1). k = 6 to 9
      -- writes X_LO, X_HI, X_S, or STATUS, where it changes the state
      -- after as the vectors' state after the command lets it be known:
      -- X_LO and X_S below 16 values, and X_HI above 0.
      procedure next_access(k : natural;
                            f : inout std_logic_vector(3 downto 0);
                            d : inout std_logic_vector(7 downto 0);
                            s : inout t_stack) is
         type     t_regs is array (0 to 5) of natural;
         constant C_READS : t_regs := (0, 1, 2, 3, 5, 6);
         variable n_v     : natural;
         variable r1_v    : std_logic_vector(31 downto 0);
         variable r2_v    : std_logic_vector(31 downto 0);
      begin
         n_v := to_integer(unsigned(d));
         if k <= 5 then
            read(C_READS(k), r1_v);
            read(C_READS(k), r2_v);
            if r1_v /= r2_v then
               fail("a read of " & integer'image(C_READS(k)) & " during the command gave " &
                    to_hstring(r1_v) & ", after it " & to_hstring(r2_v));
            end if;
         elsif k = 6 and n_v < 16 then
            write(0, X"13579BDF");
            s(n_v) := X"00000000_13579BDF";
            d      := std_logic_vector(to_unsigned(n_v + 1, 8));
         elsif k = 7 and n_v > 0 then
            write(1, X"3FF00000");
            s(n_v - 1)(63 downto 32) := X"3FF00000";
         elsif k = 8 and n_v < 16 then
            write(2, X"3F800000");
            s(n_v) := X"3FF00000_00000000";
            d      := std_logic_vector(to_unsigned(n_v + 1, 8));
         elsif k = 9 then
            f := f xor "0101";
            write(5, X"00000" & f & X"00");
         end if;
      end procedure next_access;

      -- A reset of n cycles, and then the state that it leaves: no
      -- ACK, no value, no flag, and X the canonical NaN of an empty
      -- stack.
      procedure reset_check(what : string; n : positive := 2) is
         variable r_v : std_logic_vector(31 downto 0);
      begin
         rst <= '1';
         for i in 1 to n loop
            wait until rising_edge(clk);
         end loop;
         rst <= '0';
         for i in 1 to 4 loop
            wait until rising_edge(clk);
            if ack = '1' then
               fail(what & ": an ACK after a reset");
            end if;
         end loop;
         read(5, r_v);
         if r_v(11 downto 0) /= X"000" then
            fail(what & ": STATUS " & to_hstring(r_v) & " after a reset");
         end if;
         read(1, r_v);
         if r_v /= X"7FF80000" then
            fail(what & ": X_HI " & to_hstring(r_v) & " after a reset");
         end if;
      end procedure reset_check;

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
         timed_v := false;
         reset_v := false;
         if kind_v = 'W' then
            t_cmd_v := now;
            write(to_integer(unsigned(reg_v(2 downto 0))), word_v);
            if reg_v = X"4" then
               ncmd_v := ncmd_v + 1;
            end if;
            -- Every 1000th command is reset while it runs, which leaves
            -- no state after to compare; the next line sets its own.
            -- After every third command, the next access comes at once,
            -- so that it waits for the command: each register in turn.
            if reg_v = X"4" and ncmd_v mod 1000 = 500 then
               reset_v := true;
               reset_check("a command");
            elsif reg_v = X"4" and lines_v mod 3 = 0 then
               next_access((lines_v / 3) mod 10, af_v, ad_v, as_v);
            else
               timed_v := reg_v = X"4";
            end if;
         else
            read(to_integer(unsigned(reg_v(2 downto 0))), rd_v);
            if rd_v /= word_v then
               fail("read " & to_hstring(reg_v) & " gave " & to_hstring(rd_v) & ", want " &
                    to_hstring(word_v));
            end if;
         end if;

         -- The state after. A command's time ends with this read.
         if reset_v then
            next;
         end if;
         read(5, rd_v);
         if timed_v then
            cyc_v := (now - t_cmd_v) / 10 ns;
            num_v := to_integer(unsigned(word_v(7 downto 0)));
            if cyc_v > cmost_v(num_v) then
               cmost_v(num_v) := cyc_v;
               cline_v(num_v) := lines_v;
            end if;
            if G_SLOW > 0 and cyc_v > G_SLOW then
               report "tb_fpu: line " & integer'image(lines_v) & ": command " &
                      to_hstring(word_v) & " took " & integer'image(cyc_v) & " cycles"
                  severity note;
            end if;
         end if;
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
      if now - t_v > 30 ns or rd_v /= X"00000000" then
         fail("a read of CMD took " & time'image(now - t_v) & " and gave " & to_hstring(rd_v));
      end if;
      t_v := now;
      read(1, rd_v);
      if now - t_v < 200 ns or rd_v /= X"400C0000" then
         fail("a read of X_HI after DIV took " & time'image(now - t_v) & " and gave " &
              to_hstring(rd_v));
      end if;

      -- The most cycles of each command, against its bound, and of those
      -- that take more than a few, reported.
      for i in 0 to 255 loop
         if cmost_v(i) > 10 then
            report "tb_fpu: command " & to_hstring(to_unsigned(i, 8)) & " took at most " &
                   integer'image(cmost_v(i)) & " cycles, line " & integer'image(cline_v(i)) &
                   ", bound " & integer'image(bound(i))
               severity note;
         end if;
         if cmost_v(i) > bound(i) then
            fails_v := fails_v + 1;
            report "tb_fpu: command " & to_hstring(to_unsigned(i, 8)) & " took " &
                   integer'image(cmost_v(i)) & " cycles, more than its bound"
               severity note;
         end if;
      end loop;

      -- A reset while DIV runs, and while two reads of X wait for it. Then the
      -- unit must run a command again: SQRT of 9 is 3.
      write(4, X"00000101");
      write(3, X"00000007");
      write(3, X"00000002");
      write(4, X"00000013");
      reset_check("DIV");
      write(4, X"00000101");
      write(3, X"00000007");
      write(3, X"00000002");
      write(4, X"00000013");
      cyc   <= '1';
      stb   <= '1';
      we    <= '0';
      addr  <= "001";
      -- Two reads taken on two edges, the second one waiting behind the
      -- first, and both dropped by the reset.
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      stb <= '0';
      wait until rising_edge(clk);
      if stall /= '1' then
         fail("the second read of X_HI during DIV does not wait");
      end if;
      wait until rising_edge(clk);
      cyc <= '0';
      -- One cycle, as two would serve the waiting read during the reset.
      reset_check("two reads of X_HI during DIV", 1);
      write(3, X"00000009");
      write(4, X"00000014");
      t_v := now;
      read(1, rd_v);
      if now - t_v > 2 us or rd_v /= X"40080000" then
         fail("SQRT after a reset took " & time'image(now - t_v) & " and gave " &
              to_hstring(rd_v));
      end if;

      report "tb_fpu: " & integer'image(lines_v) & " lines, " & integer'image(fails_v) &
             " differ, at most " & integer'image(most_v) & " cycles to an ACK, line " &
             integer'image(mline_v) & ", " & integer'image((ncmd_v + 500) / 1000 + 2) & " resets"
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
