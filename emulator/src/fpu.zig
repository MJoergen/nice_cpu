//! The floating-point unit of doc/SYSTEM.md §11, phase 1: a stack of up
//! to 16 binary64 values, eight registers, and the commands.
//!
//! It computes with the host's binary64 values, which are IEEE 754's, so
//! it gives the same bits as the FPGA implementation. It works out the
//! flags itself, and makes every NaN the canonical one where §11.3 says
//! so, as the host's NaNs differ between an x86 and an ARM. The reference
//! is test/fpu_model.py, which computes exactly; the test at the end
//! replays its vectors.

const std = @import("std");

/// The flags, bits 11..8 of `FPU_STATUS`, shifted down by 8.
pub const invalid: u4 = 1;
pub const divzero: u4 = 2;
pub const overflow: u4 = 4;
pub const stack_fault: u4 = 8;

pub const canonical_nan: u64 = 0x7FF8_0000_0000_0000;
const nan32: u32 = 0x7FC0_0000;
const sign_bit: u64 = 1 << 63;
const exp_mask: u64 = 0x7FF0_0000_0000_0000;
const quiet_bit: u64 = 1 << 51;

pub const depth_max = 16;

/// The registers, by their offset from the FPU's base.
pub const x_lo = 0;
pub const x_hi = 1;
pub const x_s = 2;
pub const x_w = 3;
pub const cmd = 4;
pub const status = 5;
pub const rel = 6;

fn f(a: u64) f64 {
    return @bitCast(a);
}

fn bits(x: f64) u64 {
    return @bitCast(x);
}

fn isNan(a: u64) bool {
    return a & ~sign_bit > exp_mask;
}

fn isSnan(a: u64) bool {
    return isNan(a) and a & quiet_bit == 0;
}

fn isInf(a: u64) bool {
    return a & ~sign_bit == exp_mask;
}

fn isFinite(a: u64) bool {
    return a & ~sign_bit < exp_mask;
}

fn isZero(a: u64) bool {
    return a & ~sign_bit == 0;
}

fn isNeg(a: u64) bool {
    return a & sign_bit != 0;
}

/// A value and the flags that computing it set.
const Result = struct {
    v: u64,
    flags: u4 = 0,
};

/// The canonical NaN, for an operation with a NaN operand: a signaling
/// one sets the invalid flag.
fn nan(a: u64, b: u64) Result {
    return .{ .v = canonical_nan, .flags = if (isSnan(a) or isSnan(b)) invalid else 0 };
}

fn nan1(a: u64) Result {
    return nan(a, 0);
}

const bad: Result = .{ .v = canonical_nan, .flags = invalid };

/// ADD, SUB, MUL, and DIV, of Y and X.
fn arith(num: u8, y: u64, x: u64) Result {
    if (isNan(y) or isNan(x)) return nan(y, x);
    const r = switch (num) {
        0x10 => f(y) + f(x),
        0x11 => f(y) - f(x),
        0x12 => f(y) * f(x),
        else => f(y) / f(x),
    };
    if (std.math.isNan(r)) return bad;
    var fl: u4 = 0;
    if (std.math.isInf(r) and isFinite(y) and isFinite(x)) fl = if (num == 0x13 and isZero(x)) divzero else overflow;
    return .{ .v = bits(r), .flags = fl };
}

fn sqrt(a: u64) Result {
    if (isNan(a)) return nan1(a);
    if (isZero(a)) return .{ .v = a };
    if (isNeg(a)) return bad;
    return .{ .v = bits(@sqrt(f(a))) };
}

/// X rounded to binary32, to nearest, ties to even, with subnormals.
fn to32(a: u64) f32 {
    return @floatCast(f(a));
}

fn round32(a: u64) Result {
    if (isNan(a)) return nan1(a);
    const s = to32(a);
    const r: f64 = s;
    return .{ .v = bits(r), .flags = if (std.math.isInf(s) and isFinite(a)) overflow else 0 };
}

/// ISQRT: √X rounded toward zero, and then TRUNC. The square root to
/// nearest is one too high where its square exceeds X, and then the
/// value below it is the one toward zero.
fn isqrt(a: u64) Result {
    const r = sqrt(a);
    if (!isFinite(r.v) or isZero(r.v)) return r;
    var s = f(r.v);
    if (@mulAdd(f64, s, s, -f(a)) > 0) s = f(r.v - 1);
    return .{ .v = bits(@trunc(s)) };
}

/// X rounded to the nearest whole number, ties to even: below 2^52,
/// adding 2^52 and subtracting it again rounds the fraction away.
fn nearest(x: f64) f64 {
    const ax = @abs(x);
    if (ax >= 0x1p52) return x;
    return std.math.copysign((ax + 0x1p52) - 0x1p52, x);
}

fn integral(num: u8, a: u64) Result {
    if (isNan(a)) return nan1(a);
    if (!isFinite(a) or isZero(a)) return .{ .v = a };
    const x = f(a);
    const r = switch (num) {
        0x20 => @floor(x),
        0x21 => @ceil(x),
        0x22 => @trunc(x),
        0x23 => nearest(x),
        else => @round(x),
    };
    // A result of zero has the sign of X; any other has it anyway.
    return .{ .v = bits(std.math.copysign(r, x)) };
}

fn sign(a: u64) Result {
    if (isNan(a)) return nan1(a);
    if (isZero(a)) return .{ .v = 0 };
    return .{ .v = bits(if (isNeg(a)) -1.0 else 1.0) };
}

/// Y compared with X: -1, 0, or 1, or null if unordered.
fn compare(y: u64, x: u64) ?i2 {
    if (isNan(y) or isNan(x)) return null;
    const a = f(y);
    const b = f(x);
    return if (a < b) -1 else if (a > b) 1 else 0;
}

/// MIN and MAX, as wasm's: a NaN gives a NaN, and -0 < +0.
fn minMax(y: u64, x: u64, max: bool) Result {
    if (isNan(y) or isNan(x)) return nan(y, x);
    const c = compare(y, x).?;
    if (c == 0) {
        // Equal values differ only as zeros of two signs.
        const neg = if (max) isNeg(y) and isNeg(x) else isNeg(y) or isNeg(x);
        return .{ .v = y & ~sign_bit | (if (neg) sign_bit else 0) };
    }
    return .{ .v = if ((c > 0) == max) y else x };
}

fn cmpN(y: u64, x: u64, n: u8) Result {
    const c = compare(y, x) orelse return .{ .v = 0, .flags = invalid };
    const bit: u3 = @intCast(@as(i4, c) + 1);
    return .{ .v = if (n >> bit & 1 != 0) bits(-1.0) else 0 };
}

fn fmod(y: u64, x: u64) Result {
    if (isNan(y) or isNan(x)) return nan(y, x);
    if (isInf(y) or isZero(x)) return bad;
    if (isInf(x) or isZero(y)) return .{ .v = y };
    return .{ .v = bits(@rem(f(y), f(x))) };
}

fn ftoi(a: u64) Result {
    if (isNan(a)) return .{ .v = 0, .flags = invalid };
    const x = f(a);
    if (x >= 0x1p63) return .{ .v = std.math.maxInt(i64), .flags = invalid };
    if (x < -0x1p63) return .{ .v = sign_bit, .flags = invalid };
    const i: i64 = @intFromFloat(@trunc(x));
    return .{ .v = @bitCast(i) };
}

fn ftou(a: u64) Result {
    if (isNan(a)) return .{ .v = 0, .flags = invalid };
    const x = f(a);
    if (x >= 0x1p64) return .{ .v = std.math.maxInt(u64), .flags = invalid };
    if (x <= -1.0) return .{ .v = 0, .flags = invalid };
    if (x < 0) return .{ .v = 0 };
    return .{ .v = @intFromFloat(@trunc(x)) };
}

/// X as a signed 32-bit integer, rounded toward zero and saturated, and
/// 0 for a NaN, as a read of `FPU_X_W` gives it.
fn toWord(a: u64) u32 {
    if (isNan(a)) return 0;
    const x = f(a);
    if (x >= 0x1p31) return 0x7FFF_FFFF;
    if (x <= -0x1p31 - 1.0) return 0x8000_0000;
    const i: i32 = @intFromFloat(@trunc(x));
    return @bitCast(i);
}

/// An operand of the word operators: X rounded toward zero, if it fits a
/// signed 32-bit integer.
fn word(a: u64) ?i64 {
    if (!isFinite(a)) return null;
    const t = @trunc(f(a));
    if (t < -0x1p31 or t >= 0x1p31) return null;
    return @intFromFloat(t);
}

fn fromInt(i: i64) u64 {
    return bits(@floatFromInt(i));
}

fn wordOp(num: u8, y: u64, x: u64) Result {
    const a = word(y) orelse return bad;
    const b = word(x) orelse return bad;
    const ua: u32 = @truncate(@as(u64, @bitCast(a)));
    const r: i64 = switch (num) {
        0x60 => a & b,
        0x61 => a | b,
        0x62 => a ^ b,
        0x64, 0x65 => blk: {
            if (b < 0) return bad;
            if (b >= 32) break :blk 0;
            const sh: u5 = @intCast(b);
            const w = if (num == 0x64) ua << sh else ua >> sh;
            break :blk @as(i32, @bitCast(w));
        },
        0x66 => if (b == 0) return bad else @divTrunc(a, b),
        else => if (b == 0) return bad else @rem(a, b),
    };
    return .{ .v = fromInt(r) };
}

fn notOp(a: u64) Result {
    const w = word(a) orelse return bad;
    return .{ .v = fromInt(-w - 1) };
}

/// The constant table of `CONST n`.
const constants = [16]u64{
    0x0000000000000000, // 0
    0x3FF0000000000000, // 1
    0x4024000000000000, // 10
    0x400921FB54442D18, // π
    0x4005BF0A8B145769, // e
    0x3FE62E42FEFA39EF, // ln 2
    0x40026BB1BBB55516, // ln 10
    0x3FD34413509F79FF, // log10 2
    0x3FD45F306DC9C883, // 1/π
    0x3FB999999999999A, // 1/10
    0x3FF921FB54442D18, // π/2
    0x401921FB54442D18, // 2π
    0x3FF71547652B82FE, // log2 e
    0x3FDBCB7B1526E50E, // log10 e
    0x400A934F0979A371, // log2 10
    0x3FF6A09E667F3BCD, // √2
};

/// y · 2^n, rounded once, as musl's scalbn: the steps before the last
/// multiply are exact.
fn scalbn(y0: f64, n0: i32) f64 {
    var y = y0;
    var n = n0;
    if (n > 1023) {
        y *= 0x1p1023;
        n -= 1023;
        if (n > 1023) {
            y *= 0x1p1023;
            n -= 1023;
            if (n > 1023) n = 1023;
        }
    } else if (n < -1022) {
        y *= 0x1p-1022 * 0x1p53;
        n += 1022 - 53;
        if (n < -1022) {
            y *= 0x1p-1022 * 0x1p53;
            n += 1022 - 53;
            if (n < -1022) n = -1022;
        }
    }
    return y * f(@as(u64, @intCast(0x3FF + n)) << 52);
}

/// The whole X of SCALE2 and SCALE10, with an infinity counted as
/// ±limit, and any larger X too. Null for a NaN or an X not whole.
fn scaleCount(x: u64, limit: i32) ?i32 {
    if (isNan(x)) return null;
    if (isInf(x)) return if (isNeg(x)) -limit else limit;
    const v = f(x);
    if (@trunc(v) != v) return null;
    const l: f64 = @floatFromInt(limit);
    return @intFromFloat(std.math.clamp(v, -l, l));
}

fn scale(num: u8, y: u64, x: u64) Result {
    const limit: i32 = if (num == 0x38) 2100 else 650;
    const k = scaleCount(x, limit) orelse return .{ .v = canonical_nan, .flags = invalid | nan1(y).flags };
    if (isNan(y)) return nan1(y);
    if (isInf(y) or isZero(y)) return .{ .v = y };
    const r = if (num == 0x38) bits(scalbn(f(y), k)) else scale10(y, k);
    // An infinite X sets no overflow flag (§11.3).
    return .{ .v = r, .flags = if (isInf(r) and !isInf(x)) overflow else 0 };
}

/// 10^k for k from 0 to 22, each exact in binary64.
const pow10 = blk: {
    var t: [23]f64 = undefined;
    var p: f64 = 1;
    for (&t) |*e| {
        e.* = p;
        p *= 10;
    }
    break :blk t;
};

/// SCALE10's table: 10^(2^i), and 10^(-2^i), for i from 0 to 8, each as
/// a high part, the binary64 value nearest it, and a low part, the value
/// nearest what remains. test/fpu_model.py computes them as TEN_PAIRS.
const ten_up = [9][2]u64{
    .{ 0x4024000000000000, 0x0000000000000000 }, // 10^1
    .{ 0x4059000000000000, 0x0000000000000000 }, // 10^2
    .{ 0x40C3880000000000, 0x0000000000000000 }, // 10^4
    .{ 0x4197D78400000000, 0x0000000000000000 }, // 10^8
    .{ 0x4341C37937E08000, 0x0000000000000000 }, // 10^16
    .{ 0x4693B8B5B5056E17, 0xC333107F00000000 }, // 10^32
    .{ 0x4D384F03E93FF9F5, 0xC9C2AC340948E389 }, // 10^64
    .{ 0x5A827748F9301D32, 0xD72901CC86649E4A }, // 10^128
    .{ 0x75154FDD7F73BF3C, 0xF1A7222446FE4670 }, // 10^256
};
const ten_down = [9][2]u64{
    .{ 0x3FB999999999999A, 0xBC5999999999999A }, // 10^-1
    .{ 0x3F847AE147AE147B, 0xBC0EB851EB851EB8 }, // 10^-2
    .{ 0x3F1A36E2EB1C432D, 0xBBB6A161E4F765FE }, // 10^-4
    .{ 0x3E45798EE2308C3A, 0xBAD03023DF2D4C94 }, // 10^-8
    .{ 0x3C9CD2B297D889BC, 0x3925B4C2EBE68799 }, // 10^-16
    .{ 0x3949F623D5A8A733, 0xB5EA2CC10F3892D4 }, // 10^-32
    .{ 0x32A50FFD44F4A73D, 0x2F3A53F2398D747B }, // 10^-64
    .{ 0x255BBA08CF8C979D, 0xA1FAFA9C1A60497D }, // 10^-128
    .{ 0x0AC8062864AC6F43, 0x07539FA911155FF0 }, // 10^-256
};

const Pair = struct { h: f64, l: f64 };

/// Dekker's product of two pairs, as SYSTEM.md §11.3 lists its steps.
fn mulPair(a: Pair, b: [2]u64) Pair {
    const bh = f(b[0]);
    const bl = f(b[1]);
    const p = a.h * bh;
    if (std.math.isInf(p)) return .{ .h = p, .l = 0 };
    var e = @mulAdd(f64, a.h, bh, -p);
    e = e + a.h * bl;
    e = e + a.l * bh;
    const h = p + e;
    if (std.math.isInf(h)) return .{ .h = h, .l = 0 };
    return .{ .h = h, .l = e - (h - p) };
}

/// Y · 10^k for a finite nonzero Y, by SCALE10's sequence.
fn scale10(y: u64, k0: i32) u64 {
    const neg = k0 < 0;
    const k: u32 = @min(@abs(k0), 650);
    if (k <= 22) return bits(if (neg) f(y) / pow10[k] else f(y) * pow10[k]);
    const table = if (neg) &ten_down else &ten_up;
    var r: Pair = .{ .h = f(y), .l = 0 };
    for (0..9) |i| {
        if (k >> @intCast(i) & 1 != 0) r = mulPair(r, table[i]);
    }
    if (k >> 9 & 1 != 0) {
        r = mulPair(r, table[8]);
        r = mulPair(r, table[8]);
    }
    if (std.math.isInf(r.h)) return bits(r.h);
    return bits(r.h + r.l);
}

/// The exponent E of a finite nonzero X, with 2^E <= |X| < 2^(E+1).
fn exponent(a: u64) i32 {
    const e: i32 = @intCast(a >> 52 & 0x7FF);
    if (e != 0) return e - 1023;
    const m = a & (quiet_bit << 1) - 1;
    return @as(i32, 63 - @clz(m)) - 1074;
}

fn getexp(a: u64) Result {
    if (isNan(a)) return nan1(a);
    if (isZero(a)) return .{ .v = sign_bit | exp_mask, .flags = divzero };
    if (isInf(a)) return .{ .v = exp_mask };
    return .{ .v = fromInt(exponent(a)) };
}

fn getmant(a: u64) Result {
    if (isNan(a)) return nan1(a);
    if (!isFinite(a) or isZero(a)) return .{ .v = a };
    return .{ .v = bits(scalbn(f(a), -exponent(a))) };
}

fn frombcd(a: u64) Result {
    var v: u64 = 0;
    var i: u6 = 60;
    while (true) : (i -= 4) {
        const c = a >> i & 0xF;
        if (c > 9) return bad;
        v = 10 * v + c;
        if (i == 0) break;
    }
    return .{ .v = bits(@floatFromInt(v)) };
}

/// DIGITS n of a finite nonzero X, n from 1 to 15: the digits D and the
/// exponent e. D is NEAREST of SCALE10 of |X| by n - 1 - e, and e the
/// largest whole number for which D >= 10^(n-1). No e above
/// floor(log10 |X|) + 1 has one, so the search starts at or above it.
fn digits(a: u64, n: u8) struct { d: u64, e: i32 } {
    const ax = a & ~sign_bit;
    const lowest = std.math.pow(u64, 10, @as(u64, n) - 1);
    // log10 2 < 0.30103, so this is at least floor(log10 |X|) + 1.
    var e: i32 = @divFloor((exponent(ax) + 1) * 30103, 100000) + 2;
    while (true) : (e -= 1) {
        const d = nearest(f(scale10(ax, @as(i32, n) - 1 - e)));
        if (d >= @as(f64, @floatFromInt(lowest))) return .{ .d = @intFromFloat(d), .e = e };
    }
}

pub const Fpu = struct {
    /// The values, the deepest first.
    stack: [depth_max]u64 = @splat(0),
    depth: u5 = 0,
    flags: u4 = 0,

    /// X, or the canonical NaN for an empty stack.
    pub fn x(self: *const Fpu) u64 {
        return if (self.depth > 0) self.stack[self.depth - 1] else canonical_nan;
    }

    fn y(self: *const Fpu) u64 {
        return if (self.depth > 1) self.stack[self.depth - 2] else canonical_nan;
    }

    /// A push onto 16 values drops the deepest, with the stack fault.
    fn push(self: *Fpu, v: u64) void {
        if (self.depth == depth_max) {
            std.mem.copyForwards(u64, self.stack[0 .. depth_max - 1], self.stack[1..]);
            self.depth -= 1;
            self.flags |= stack_fault;
        }
        self.stack[self.depth] = v;
        self.depth += 1;
    }

    /// A pop of a value that is not there gives the canonical NaN, with
    /// the stack fault.
    fn pop(self: *Fpu) u64 {
        if (self.depth == 0) {
            self.flags |= stack_fault;
            return canonical_nan;
        }
        self.depth -= 1;
        return self.stack[self.depth];
    }

    fn copy(self: *Fpu, n: u8) u64 {
        if (n < self.depth) return self.stack[self.depth - 1 - n];
        self.flags |= stack_fault;
        return canonical_nan;
    }

    /// The class of X, bits 21..16 of `FPU_STATUS`, shifted down by 16.
    fn class(self: *const Fpu) u6 {
        const a = self.x();
        var c: u6 = 0;
        if (isNeg(a)) c |= 1;
        if (isZero(a)) c |= 2;
        if (isInf(a)) c |= 4;
        if (isNan(a)) c |= 8;
        if (isFinite(a) and @trunc(f(a)) == f(a)) c |= 16;
        if (word(a) != null) c |= 32;
        return c;
    }

    /// A data read of register `i`. It changes nothing, so a dump of the
    /// I/O range can use it as a peek.
    pub fn read(self: *const Fpu, i: u3) u32 {
        const a = self.x();
        return switch (i) {
            x_lo => @truncate(a),
            x_hi => @truncate(a >> 32),
            x_s => if (isNan(a)) nan32 else @bitCast(to32(a)),
            x_w => toWord(a),
            status => @as(u32, self.depth) | @as(u32, self.flags) << 8 | @as(u32, self.class()) << 16,
            rel => if (compare(self.y(), a)) |c| @bitCast(@as(i32, c)) else 2,
            else => 0,
        };
    }

    pub fn write(self: *Fpu, i: u3, w: u32) void {
        switch (i) {
            x_lo => self.push(w),
            x_hi => if (self.depth > 0) {
                const t = &self.stack[self.depth - 1];
                t.* = t.* & 0xFFFF_FFFF | @as(u64, w) << 32;
            } else {
                self.flags |= stack_fault;
            },
            x_s => {
                const s: f32 = @bitCast(w);
                const v: f64 = s;
                self.push(if (std.math.isNan(s)) canonical_nan else bits(v));
            },
            x_w => self.push(fromInt(@as(i32, @bitCast(w)))),
            cmd => self.command(w),
            status => self.flags = @truncate(w >> 8),
            else => {},
        }
    }

    /// The bits of n that a command uses, and whether S applies, or null
    /// for a number that is not defined.
    fn spec(num: u8) ?struct { nmask: u8 = 0, s: bool = false } {
        return switch (num) {
            0x01 => .{ .nmask = 0x01 },
            0x03, 0x06, 0x30, 0x3A => .{ .nmask = 0xFF },
            0x1C => .{ .nmask = 0x07 },
            0x10...0x14 => .{ .s = true },
            0x00, 0x02, 0x04, 0x05, 0x15...0x1B, 0x1D, 0x20...0x24, 0x28...0x2B, 0x38...0x39, 0x3B...0x3D, 0x60...0x67 => .{},
            else => null,
        };
    }

    pub fn command(self: *Fpu, w: u32) void {
        const num: u8 = @truncate(w);
        const n: u8 = @truncate(w >> 8);
        const s = w >> 16 & 1 != 0;
        const sp = spec(num) orelse {
            self.flags |= invalid;
            return;
        };
        if (w >> 17 != 0 or (s and !sp.s) or n & ~sp.nmask != 0) {
            self.flags |= invalid;
            return;
        }
        var r: Result = undefined;
        switch (num) {
            0x00 => return,
            0x01 => {
                self.depth = 0;
                if (n != 0) self.flags = 0;
                return;
            },
            0x02, 0x05, 0x06 => {
                self.push(self.copy(if (num == 0x02) 0 else if (num == 0x05) 1 else n));
                return;
            },
            0x03 => {
                for (0..@max(n, 1)) |_| _ = self.pop();
                return;
            },
            0x04 => {
                const a = self.pop();
                const b = self.pop();
                self.push(a);
                self.push(b);
                return;
            },
            0x30 => r = if (n < constants.len) .{ .v = constants[n] } else bad,
            0x3A => {
                const a = self.pop();
                if (!isFinite(a) or n == 0 or n > 15) {
                    self.flags |= invalid | nan1(a).flags;
                    self.push(canonical_nan);
                    self.push(canonical_nan);
                } else if (isZero(a)) {
                    self.push(0);
                    self.push(0);
                } else {
                    // D has n digits: d1 goes to bits 63..60, and each
                    // next one to the 4 bits below.
                    const d = digits(a, n);
                    var bcd: u64 = 0;
                    var rest = d.d;
                    var j: u6 = @intCast(n);
                    while (j > 0) {
                        j -= 1;
                        bcd |= (rest % 10) << (60 - 4 * j);
                        rest /= 10;
                    }
                    self.push(bcd);
                    self.push(fromInt(d.e));
                }
                return;
            },
            0x10...0x13, 0x17, 0x18, 0x1C, 0x1D, 0x38, 0x39, 0x60...0x62, 0x64...0x67 => {
                const xv = self.pop();
                const yv = self.pop();
                r = switch (num) {
                    0x10...0x13 => arith(num, yv, xv),
                    0x17, 0x18 => minMax(yv, xv, num == 0x18),
                    0x1C => cmpN(yv, xv, n),
                    0x1D => fmod(yv, xv),
                    0x38, 0x39 => scale(num, yv, xv),
                    else => wordOp(num, yv, xv),
                };
            },
            else => {
                const a = self.pop();
                r = switch (num) {
                    0x14 => sqrt(a),
                    0x15 => .{ .v = a ^ sign_bit },
                    0x16 => .{ .v = a & ~sign_bit },
                    0x19 => round32(a),
                    0x1A => isqrt(a),
                    0x1B => sign(a),
                    0x20...0x24 => integral(num, a),
                    0x28 => .{ .v = fromInt(@bitCast(a)) },
                    0x29 => .{ .v = bits(@floatFromInt(a)) },
                    0x2A => ftoi(a),
                    0x2B => ftou(a),
                    0x3B => frombcd(a),
                    0x3C => getexp(a),
                    0x3D => getmant(a),
                    else => notOp(a),
                };
            },
        }
        if (s) {
            const q = round32(r.v);
            r = .{ .v = q.v, .flags = r.flags | q.flags };
        }
        self.flags |= r.flags;
        self.push(r.v);
    }
};

const testing = std.testing;
const build_options = @import("build_options");

fn parseState(text: []const u8, fpu: *Fpu) !void {
    var it = std.mem.tokenizeScalar(u8, text, ' ');
    fpu.* = .{};
    fpu.flags = try std.fmt.parseInt(u4, it.next() orelse return error.Format, 16);
    const depth = try std.fmt.parseInt(u5, it.next() orelse return error.Format, 16);
    for (0..depth) |i| fpu.stack[i] = try std.fmt.parseInt(u64, it.next() orelse return error.Format, 16);
    fpu.depth = depth;
    if (it.next() != null or depth > depth_max) return error.Format;
}

fn same(a: Fpu, b: Fpu) bool {
    return a.depth == b.depth and a.flags == b.flags and std.mem.eql(u64, a.stack[0..a.depth], b.stack[0..b.depth]);
}

// The vectors of test/fpu_vectors.py, which make test writes and names
// with -Dfpu-vectors. Each line is the state before an access, the
// access, and the state after it, from the model.
test "the FPU replays the vectors of the model" {
    const path = build_options.fpu_vectors orelse return error.SkipZigTest;
    const text = try std.Io.Dir.cwd().readFileAlloc(testing.io, path, testing.allocator, .limited(1 << 30));
    defer testing.allocator.free(text);
    var lines = std.mem.splitScalar(u8, text, '\n');
    var count: usize = 0;
    var failures: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0 or line[0] == '#') continue;
        var parts = std.mem.splitScalar(u8, line, ':');
        var fpu: Fpu = undefined;
        var want: Fpu = undefined;
        try parseState(parts.next() orelse return error.Format, &fpu);
        var access = std.mem.tokenizeScalar(u8, parts.next() orelse return error.Format, ' ');
        const kind = access.next() orelse return error.Format;
        const reg = try std.fmt.parseInt(u3, access.next() orelse return error.Format, 16);
        const w = try std.fmt.parseInt(u32, access.next() orelse return error.Format, 16);
        try parseState(parts.next() orelse return error.Format, &want);
        var ok = true;
        if (kind[0] == 'R') {
            ok = fpu.read(reg) == w;
        } else {
            fpu.write(reg, w);
        }
        if (!ok or !same(fpu, want)) {
            failures += 1;
            if (failures <= 10) {
                std.debug.print("FAIL {s}\n  gives flags {X} depth {d} X {X:0>16}", .{ line, fpu.flags, fpu.depth, fpu.x() });
                if (kind[0] == 'R') std.debug.print(" read {X:0>8}", .{fpu.read(reg)});
                std.debug.print("\n", .{});
            }
        }
        count += 1;
    }
    if (failures > 0) {
        std.debug.print("{d} of {d} vectors failed\n", .{ failures, count });
        return error.TestFailed;
    }
    try testing.expect(count > 0);
}
