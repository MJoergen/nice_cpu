-- The operations of src/fpu_unit.vhd, the arithmetic unit of the FPU of
-- DEVICES.md §11, and the bits of its flags. src/fpu.vhd runs the commands
-- of §11.3 as sequences of these operations.
--
-- Each operation takes A, and B for those of two operands, and gives a
-- result as the model emulator/test/fpu_model.py does, with its flags:
--
--   OP_ADD, OP_SUB, OP_MUL, OP_DIV   A + B, A - B, A * B, A / B, rounded
--   OP_SQRT                          the square root of A, rounded to
--                                    nearest, or toward zero with RND_TRUNC
--   OP_MULERR                        fma(A, B, -(A * B)): the error of the
--                                    rounded product, rounded, for finite A
--                                    and B whose product is finite
--   OP_FMOD                          the remainder of A / B with the sign of
--                                    A, exact
--   OP_TOSHORT                       A rounded to the short format, in the
--                                    low bits of the result
--   OP_FROMSHORT                     the short value in the low bits of A,
--                                    exact
--   OP_INTEGRAL                      A rounded to a whole number by the
--                                    rounding mode
--   OP_ITOF, OP_UTOF                 the bits of A as a signed or unsigned
--                                    integer, rounded
--   OP_FTOI, OP_FTOU                 A rounded toward zero as a signed or
--                                    unsigned integer of the width of A,
--                                    saturated, and 0 for a NaN
--   OP_FTOW                          the same as a signed integer of half
--                                    that width, sign-extended
--   OP_SCALE2                        A * 2^K, rounded, for the integer K
--   OP_GETEXP, OP_GETMANT            GETEXP and GETMANT of §11.3
--   OP_ILOGB                         the exponent of a finite nonzero A as
--                                    a signed integer

library ieee;
   use ieee.std_logic_1164.all;

package fpu_pkg is

   type t_fpu_op is (
      OP_ADD, OP_SUB, OP_MUL, OP_MULERR, OP_DIV, OP_SQRT, OP_FMOD,
      OP_TOSHORT, OP_FROMSHORT, OP_INTEGRAL, OP_ITOF, OP_UTOF,
      OP_FTOI, OP_FTOU, OP_FTOW, OP_SCALE2, OP_GETEXP, OP_GETMANT, OP_ILOGB
   );

   -- The rounding modes: to nearest with ties to even, toward zero, toward
   -- -infinity, toward +infinity, and to nearest with ties away from zero.
   -- Only OP_SQRT and OP_INTEGRAL take one; the others round to nearest.
   type t_fpu_rnd is (RND_EVEN, RND_TRUNC, RND_FLOOR, RND_CEIL, RND_AWAY);

   -- The bits of the flags, in the order of bits 8 to 10 of FPU_STATUS.
   constant C_FL_INVALID  : natural := 0;
   constant C_FL_DIVZERO  : natural := 1;
   constant C_FL_OVERFLOW : natural := 2;

end package fpu_pkg;

