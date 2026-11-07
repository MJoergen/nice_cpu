// Floats in Zig: arithmetic, which nicewasm turns into calls of the float
// library, the math builtins and std.math, which are Zig's own code in the
// module, rounding and conversions, f128, which Zig's compiler_rt does in
// the module, and std.fmt's printing of floats. The arguments are read
// through volatile pointers, so that Zig cannot compute the results
// itself. Each printed value is the shortest decimal that gives back the
// same float, as Python's repr prints it too, and test/zigfloat.expected
// was checked with Python's math and fractions modules. main returns 0.
const std = @import("std");
const nice = @import("nice");

var two_v: f64 = 2.0;
var tenth_v: f32 = 0.1;

fn two() f64 {
    return @as(*volatile f64, &two_v).*;
}

fn tenth() f32 {
    return @as(*volatile f32, &tenth_v).*;
}

export fn main() i32 {
    const x = two();
    const one = x / 2;
    // 3, 2/3, and 1.9 rounded to double, which prints as 1.9.
    nice.print("{d} {d} {d}\n", .{ x * 1.5, x / 3, x - 0.1 });
    // √2, sin 1, e, ln 2, √2 again as 2^0.5, and π as 4 atan2(1, 1).
    // compiler_rt's exp is fdlibm's, whose exp(1) is the double above e,
    // 2.7182818284590455, 0.67 ulp off: the same steps in Python's doubles
    // give it too.
    nice.print("{d} {d} {d} {d} {d} {d}\n", .{
        @sqrt(x),                  @sin(one),
        @exp(one),                 @log(x),
        std.math.pow(f64, x, 0.5), 4 * std.math.atan2(one, one),
    });
    // The same in f32. 0.1 times 3 rounds to the float nearest 0.3.
    const y = tenth();
    const yone = y * 10;
    nice.print("{d} {d} {d} {d} {d}\n", .{ y * 3, @sqrt(y * 20), @sin(yone), @exp(yone), @log(y) });
    // Rounding: 3.4 down, -2.5 away from 0, |-2|, and to integers.
    nice.print("{d} {d} {d} {d}\n", .{ @floor(x * 1.7), @round(-x - 0.5), @abs(-x), @as(i32, @intFromFloat(x * 1.7)) });
    // The special values, the exponent form, and 2/3 in f128, whose 34
    // sixes are the fewest digits that give the f128 back.
    const zero = x - x;
    nice.print("{d} {d} {d} {d} {e} {e} {d}\n", .{
        zero / zero, one / zero, -one / zero, -zero, x * 617.25, y, @as(f128, x) / 3,
    });
    return 0;
}
