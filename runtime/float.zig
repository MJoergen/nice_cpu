//! The floating-point routines of the runtime library (doc/ISA.md §9.3).
//!
//! This file is compiled to wasm and translated as the library module
//! "float" (§9.4) into float.asm. See README.md for how to rebuild it.
//!
//! Most routines come unchanged from Zig's compiler_rt, which the build
//! copies next to this file: the arithmetic, the comparisons, and the
//! conversions from integers and between f32 and f64. They keep their
//! usual names, such as __addsf3. This file adds the routines whose
//! meaning differs from C's or that compiler_rt does not have, all written
//! with integer operations on the bits of the numbers:
//!
//! - __fixsfsi and the other conversions to integers saturate, and give 0
//!   for a NaN, as wasm's trunc_sat does. C leaves these cases undefined,
//!   so the same routines serve C.
//! - __sqrtsf, __ceilsf, __floorsf, __truncsf, __nearestsf, __minsf, and
//!   __maxsf, and the same with df for f64, as wasm defines them.
//!
//! The library must not use the wasm float instructions, because nicewasm
//! translates those into calls to this library. nicewasm rejects a library
//! module that uses them, so a build that does fails.

const std = @import("std");
const int_from_float = @import("compiler_rt/int_from_float.zig");

comptime {
    _ = @import("compiler_rt/addsf3.zig");
    _ = @import("compiler_rt/subsf3.zig");
    _ = @import("compiler_rt/mulsf3.zig");
    _ = @import("compiler_rt/divsf3.zig");
    _ = @import("compiler_rt/adddf3.zig");
    _ = @import("compiler_rt/subdf3.zig");
    _ = @import("compiler_rt/muldf3.zig");
    _ = @import("compiler_rt/divdf3.zig");
    _ = @import("compiler_rt/cmpsf2.zig");
    _ = @import("compiler_rt/gesf2.zig");
    _ = @import("compiler_rt/cmpdf2.zig");
    _ = @import("compiler_rt/gedf2.zig");
    _ = @import("compiler_rt/floatsisf.zig");
    _ = @import("compiler_rt/floatunsisf.zig");
    _ = @import("compiler_rt/floatdisf.zig");
    _ = @import("compiler_rt/floatundisf.zig");
    _ = @import("compiler_rt/floatsidf.zig");
    _ = @import("compiler_rt/floatunsidf.zig");
    _ = @import("compiler_rt/floatdidf.zig");
    _ = @import("compiler_rt/floatundidf.zig");
    _ = @import("compiler_rt/extendsfdf2.zig");
    _ = @import("compiler_rt/truncdfsf2.zig");
    // The 128-bit shifts that the f64 routines need. The build leaves out
    // the rest of compiler_rt, whose __fixsfsi and the like have C's
    // meaning, not the one below.
    _ = @import("compiler_rt/shift.zig");
}

/// The bits of a float type, and its layout.
fn Layout(comptime T: type) type {
    return struct {
        const Bits = std.meta.Int(.unsigned, @bitSizeOf(T));
        const mant = std.math.floatMantissaBits(T); // fraction bits: 23 or 52
        const bias = (1 << (std.math.floatExponentBits(T) - 1)) - 1;
        const sign: Bits = 1 << (@bitSizeOf(T) - 1);
        const inf: Bits = @as(Bits, (1 << std.math.floatExponentBits(T)) - 1) << mant;
        const quiet: Bits = 1 << (mant - 1);
        const one: Bits = @as(Bits, bias) << mant;
        const frac: Bits = (1 << mant) - 1;

        fn isNan(x: Bits) bool {
            return x & ~sign > inf;
        }
    };
}

// Conversions to integers: saturating, and 0 for a NaN.

fn fix(comptime I: type, comptime T: type, x: Layout(T).Bits) I {
    if (Layout(T).isNan(x)) return 0;
    return int_from_float.intFromFloat(I, @as(T, @bitCast(x)));
}

export fn __fixsfsi(x: u32) i32 {
    return fix(i32, f32, x);
}
export fn __fixunssfsi(x: u32) u32 {
    return fix(u32, f32, x);
}
export fn __fixsfdi(x: u32) i64 {
    return fix(i64, f32, x);
}
export fn __fixunssfdi(x: u32) u64 {
    return fix(u64, f32, x);
}
export fn __fixdfsi(x: u64) i32 {
    return fix(i32, f64, x);
}
export fn __fixunsdfsi(x: u64) u32 {
    return fix(u32, f64, x);
}
export fn __fixdfdi(x: u64) i64 {
    return fix(i64, f64, x);
}
export fn __fixunsdfdi(x: u64) u64 {
    return fix(u64, f64, x);
}

// Rounding to an integral value. A NaN gives a quiet NaN, and an infinity,
// a zero, and an integral value give themselves.

const Rounding = enum { ceil, floor, trunc, nearest };

fn round(comptime T: type, comptime mode: Rounding, x: Layout(T).Bits) Layout(T).Bits {
    const L = Layout(T);
    if (L.isNan(x)) return x | L.quiet;
    const mag = x & ~L.sign;
    const neg = x & L.sign != 0;
    const e = @as(i32, @intCast(mag >> L.mant)) - L.bias; // unbiased exponent
    if (e >= L.mant) return x; // integral, or an infinity
    if (e < 0) {
        // 0 < |x| < 1, or a zero: the result is 0 or 1 with x's sign.
        if (mag == 0) return x;
        const away = switch (mode) {
            .trunc => false,
            .floor => neg,
            .ceil => !neg,
            // Away from 0 only above 0.5, whose bits are (bias - 1) << mant.
            // 0.5 itself is a tie, and goes to the even 0.
            .nearest => mag > @as(L.Bits, L.bias - 1) << L.mant,
        };
        return (x & L.sign) | (if (away) L.one else 0);
    }
    // 1 <= |x| < 2^mant: the fraction bits below the integer part go.
    const below: L.Bits = (@as(L.Bits, 1) << @intCast(L.mant - e)) - 1;
    const rest = x & below;
    if (rest == 0) return x;
    const cut = x & ~below;
    const up = switch (mode) {
        .trunc => false,
        .floor => neg,
        .ceil => !neg,
        // Ties go to even. The lowest bit of the integer part is the bit
        // just above the fraction that goes. For e = 0 that is the lowest
        // bit of the exponent field, which is 1, as the bias is odd, just
        // as the integer part, 1, is odd.
        .nearest => blk: {
            const half = (below >> 1) + 1;
            break :blk rest > half or (rest == half and (x >> @intCast(L.mant - e)) & 1 == 1);
        },
    };
    // Adding 1 to the integer part may carry into the exponent, which is
    // then right too.
    return if (up) cut + below + 1 else cut;
}

export fn __ceilsf(x: u32) u32 {
    return round(f32, .ceil, x);
}
export fn __floorsf(x: u32) u32 {
    return round(f32, .floor, x);
}
export fn __truncsf(x: u32) u32 {
    return round(f32, .trunc, x);
}
export fn __nearestsf(x: u32) u32 {
    return round(f32, .nearest, x);
}
export fn __ceildf(x: u64) u64 {
    return round(f64, .ceil, x);
}
export fn __floordf(x: u64) u64 {
    return round(f64, .floor, x);
}
export fn __truncdf(x: u64) u64 {
    return round(f64, .trunc, x);
}
export fn __nearestdf(x: u64) u64 {
    return round(f64, .nearest, x);
}

// min and max as wasm defines them: a NaN operand gives a NaN, and -0 is
// less than +0.

/// A key whose unsigned order is the order of the numbers.
fn key(comptime T: type, x: Layout(T).Bits) Layout(T).Bits {
    const L = Layout(T);
    return if (x & L.sign != 0) ~x else x | L.sign;
}

fn minmax(comptime T: type, comptime max: bool, a: Layout(T).Bits, b: Layout(T).Bits) Layout(T).Bits {
    const L = Layout(T);
    if (L.isNan(a)) return a | L.quiet;
    if (L.isNan(b)) return b | L.quiet;
    const a_less = key(T, a) < key(T, b);
    return if (a_less != max) a else b;
}

export fn __minsf(a: u32, b: u32) u32 {
    return minmax(f32, false, a, b);
}
export fn __maxsf(a: u32, b: u32) u32 {
    return minmax(f32, true, a, b);
}
export fn __mindf(a: u64, b: u64) u64 {
    return minmax(f64, false, a, b);
}
export fn __maxdf(a: u64, b: u64) u64 {
    return minmax(f64, true, a, b);
}

// The square root, rounded to nearest. A negative number other than -0
// gives a NaN.

fn sqrt(comptime T: type, x: Layout(T).Bits) Layout(T).Bits {
    const L = Layout(T);
    // Wide enough for the significand shifted left by s, an even number.
    const W = if (T == f32) u64 else u128;
    const s = if (T == f32) 38 else 66;
    if (x & ~L.sign == 0) return x; // +0 and -0
    if (L.isNan(x)) return x | L.quiet;
    if (x & L.sign != 0) return L.inf | L.quiet; // negative
    if (x == L.inf) return x;
    // x = m * 2^E, with m an integer.
    var m: W = x & L.frac;
    var field: i32 = @intCast(x >> L.mant);
    if (field == 0) {
        // Subnormal: normalize, so that the top bit of m is bit mant.
        field = 1;
        while (m & (@as(W, 1) << L.mant) == 0) {
            m <<= 1;
            field -= 1;
        }
    } else {
        m |= @as(W, 1) << L.mant;
    }
    var E: i32 = field - L.bias - L.mant;
    if (E & 1 != 0) {
        m <<= 1;
        E -= 1;
    }
    // q = floor(sqrt(m << s)), bit by bit, with r the remainder.
    var r: W = m << s;
    E -= s;
    var q: W = 0;
    var bit: W = @as(W, 1) << (@bitSizeOf(W) - 2);
    while (bit > r) bit >>= 2;
    while (bit != 0) : (bit >>= 2) {
        if (r >= q + bit) {
            r -= q + bit;
            q = (q >> 1) + bit;
        } else {
            q >>= 1;
        }
    }
    // sqrt(x) = q * 2^(E/2), plus a part that is not 0 if r is not 0.
    // Round q to mant + 1 bits, to nearest, ties to even.
    const len: i32 = @bitSizeOf(W) - @as(i32, @clz(q));
    var sh: i32 = len - (L.mant + 1);
    const guard = (q >> @intCast(sh - 1)) & 1 != 0;
    const sticky = q & ((@as(W, 1) << @intCast(sh - 1)) - 1) != 0 or r != 0;
    var f: W = q >> @intCast(sh);
    if (guard and (sticky or f & 1 != 0)) {
        f += 1;
        if (f == @as(W, 1) << (L.mant + 1)) {
            f >>= 1;
            sh += 1;
        }
    }
    const exp: i32 = L.mant + sh + @divExact(E, 2) + L.bias;
    return (@as(L.Bits, @intCast(exp)) << L.mant) | (@as(L.Bits, @intCast(f)) & L.frac);
}

export fn __sqrtsf(x: u32) u32 {
    return sqrt(f32, x);
}
export fn __sqrtdf(x: u64) u64 {
    return sqrt(f64, x);
}
