//! The sample player of doc/DEVICES.md §12.7: a FIFO of stereo samples
//! that a program writes, played at a rate that the program sets.

const std = @import("std");
const opm = @import("opm.zig");

/// The first of the player's three words, `PCM_DATA` (DEVICES §12.7).
pub const base: u32 = 0xFFFF_FF0A;

/// The samples the FIFO holds, which bits 31..16 of the status give.
pub const depth = 4096;

/// The rates a write of `PCM_RATE` sets, but for 0, which stops the player.
pub const min_rate: u32 = 1000;
pub const max_rate: u32 = 48000;

/// The rate's sum that plays a sample: one microsecond's worth of steps.
const threshold: u64 = 1_000_000;

pub const Sample = opm.Sample;

/// Where the samples go, with the rate at which each is played.
pub const Sink = struct {
    ctx: *anyopaque,
    put_fn: *const fn (ctx: *anyopaque, s: Sample, rate: u32) void,
};

pub const Player = struct {
    /// Each sample as written: left in bits 31..16, right in 15..0.
    fifo: [depth]u32 = undefined,
    head: u16 = 0,
    count: u16 = 0,
    rate: u32 = 0,
    underrun: bool = false,
    /// The accumulator of §12.7: the rate for each microsecond, and a
    /// sample at each million.
    acc: u64 = 0,
    /// The samples played since the start, an underrun's included.
    samples: u64 = 0,
    sink: ?Sink = null,

    /// A reset of the system, a start, or a write of the status with bit
    /// 31 set (DEVICES §12.7). The sink and the count of samples stay.
    pub fn reset(self: *Player) void {
        self.head = 0;
        self.count = 0;
        self.rate = 0;
        self.underrun = false;
        self.acc = 0;
    }

    pub fn full(self: *const Player) bool {
        return self.count == depth;
    }

    /// Whether a write of `PCM_DATA` waits for a sample: the FIFO is full,
    /// and a sample will take one from it.
    pub fn holds(self: *const Player) bool {
        return self.full() and self.rate != 0;
    }

    /// The value a data read of word `i`, 0 to 2 from `base`, returns. A
    /// read has no side effect.
    pub fn read(self: *const Player, i: u2) u32 {
        return switch (i) {
            1 => self.rate,
            2 => depth << 16 | @as(u32, @intFromBool(self.underrun)) << 15 | self.count,
            else => 0,
        };
    }

    /// A write of `value` to word `i`, 0 to 2 from `base`. With the rate
    /// not 0, the caller has waited for a full FIFO to take a sample; with
    /// the rate 0, a write to a full FIFO is dropped.
    pub fn write(self: *Player, i: u2, value: u32) void {
        switch (i) {
            0 => if (!self.full()) {
                self.fifo[(self.head + self.count) % depth] = value;
                self.count += 1;
            },
            1 => self.rate = if (value == 0) 0 else std.math.clamp(value, min_rate, max_rate),
            2 => {
                self.underrun = false;
                if (value & opm.reset_bit != 0) self.reset();
            },
            3 => {},
        }
    }

    /// Play the next sample: the oldest in the FIFO, or 0 and an underrun.
    pub fn tick(self: *Player) void {
        var s: Sample = .{ .left = 0, .right = 0 };
        if (self.count == 0) {
            self.underrun = true;
        } else {
            const w = self.fifo[self.head];
            self.head = (self.head + 1) % depth;
            self.count -= 1;
            s = .{ .left = @bitCast(@as(u16, @truncate(w >> 16))), .right = @bitCast(@as(u16, @truncate(w))) };
        }
        self.samples += 1;
        if (self.sink) |k| k.put_fn(k.ctx, s, self.rate);
    }

    /// Let `us` microseconds pass at the rate that is set, and play the
    /// samples they bring. Without a sink, nobody hears them, so they are
    /// taken from the FIFO all at once, and a long skip costs nothing.
    pub fn advance(self: *Player, us: u64) void {
        if (self.rate == 0) return;
        const total = @as(u128, self.acc) + @as(u128, us) * self.rate;
        var n = total / threshold;
        self.acc = @intCast(total % threshold);
        if (self.sink == null) {
            const k: u16 = @intCast(@min(n, self.count));
            self.head = (self.head + k) % depth;
            self.count -= k;
            if (n > k) self.underrun = true;
            self.samples += @intCast(n);
            return;
        }
        while (n != 0) : (n -= 1) self.tick();
    }

    /// The microseconds until the next sample is due. The rate is not 0.
    pub fn microsToSample(self: *const Player) u64 {
        return std.math.divCeil(u64, threshold - self.acc, self.rate) catch unreachable;
    }
};

const testing = std.testing;

test "the words, the status, and the limits of the rate" {
    var p: Player = .{};
    try testing.expectEqual(0x1000_0000, p.read(2));
    p.write(0, 0x1234_5678);
    p.write(0, 0xFFFF_8000);
    try testing.expectEqual(0x1000_0002, p.read(2));
    try testing.expectEqual(0, p.read(0));
    for ([_][2]u32{ .{ 0, 0 }, .{ 1, 1000 }, .{ 999, 1000 }, .{ 1000, 1000 }, .{ 44100, 44100 }, .{ 48000, 48000 }, .{ 48001, 48000 }, .{ 0xFFFF_FFFF, 48000 } }) |c| {
        p.write(1, c[0]);
        try testing.expectEqual(c[1], p.read(1));
    }
}

fn record(ctx: *anyopaque, s: Sample, rate: u32) void {
    const log: *std.ArrayList([3]i32) = @ptrCast(@alignCast(ctx));
    log.append(testing.allocator, .{ s.left, s.right, @intCast(rate) }) catch unreachable;
}

test "a sample each time the rate's sum reaches a million, then an underrun" {
    var log: std.ArrayList([3]i32) = .empty;
    defer log.deinit(testing.allocator);
    var p: Player = .{ .sink = .{ .ctx = &log, .put_fn = record } };
    p.write(0, 0x0001_FFFF);
    p.write(0, 0x8000_7FFF);
    // Stopped: the time passes, and nothing is played.
    p.advance(1000);
    try testing.expectEqual(0, p.samples);
    // At 3000 Hz, the samples are due at 334, 667, and 1000 microseconds.
    p.write(1, 3000);
    try testing.expectEqual(334, p.microsToSample());
    p.advance(333);
    try testing.expectEqual(0, p.samples);
    p.advance(1);
    try testing.expectEqual(1, p.samples);
    try testing.expectEqual(333, p.microsToSample());
    p.advance(666);
    try testing.expectEqual(3, p.samples);
    try testing.expectEqualSlices([3]i32, &.{ .{ 1, -1, 3000 }, .{ -32768, 32767, 3000 }, .{ 0, 0, 3000 } }, log.items);
    try testing.expectEqual(0x1000_8000, p.read(2));
    p.write(2, 0);
    try testing.expectEqual(0x1000_0000, p.read(2));
    // A new rate keeps the sum: 3000 of it at 1000 Hz is a sample in 997
    // microseconds.
    p.advance(1);
    p.write(1, 1000);
    try testing.expectEqual(997, p.microsToSample());
}

test "a full FIFO holds a write while the player runs, and drops it while stopped" {
    var p: Player = .{};
    for (0..depth) |i| p.write(0, @intCast(i));
    try testing.expect(p.full());
    try testing.expect(!p.holds());
    p.write(0, 0xDEAD);
    try testing.expectEqual(depth, p.count);
    p.write(1, 48000);
    try testing.expect(p.holds());
    try testing.expectEqual(21, p.microsToSample());
    p.advance(21);
    try testing.expect(!p.full());
    try testing.expectEqual(1, p.fifo[p.head]);
    p.reset();
    try testing.expectEqual(0x1000_0000, p.read(2));
    try testing.expectEqual(0, p.read(1));
}

test "without a sink, the samples leave the FIFO at once, and an underrun shows" {
    var p: Player = .{};
    for (0..10) |i| p.write(0, @intCast(i));
    p.write(1, 48000);
    // 1000 microseconds at 48000 Hz are 48 samples: 10 and 38 of nothing.
    p.advance(1000);
    try testing.expectEqual(48, p.samples);
    try testing.expectEqual(0x1000_8000, p.read(2));
    // A year passes at once.
    p.advance(366 * 86400 * 1_000_000);
    try testing.expectEqual(48 + 366 * 86400 * 48000, p.samples);
}

test "a write of the status with bit 31 set resets the player" {
    var p: Player = .{};
    for (0..depth) |i| p.write(0, @intCast(i));
    p.write(1, 48000);
    p.advance(25);
    try testing.expectEqual(0x1000_0FFF, p.read(2));
    // Bits 30..0 do nothing more than clear the flag: a program that
    // writes back the status it read, with an odd count, never resets.
    p.write(2, p.read(2));
    p.write(2, 0x7FFF_FFFF);
    try testing.expectEqual(0x1000_0FFF, p.read(2));
    try testing.expectEqual(48000, p.read(1));
    p.write(2, opm.reset_bit);
    try testing.expectEqual(0x1000_0000, p.read(2));
    try testing.expectEqual(0, p.read(1));
    try testing.expectEqual(0, p.acc);
    p.write(0, 0x1234_5678);
    try testing.expectEqual(0x1000_0001, p.read(2));
    try testing.expectEqual(0x1234_5678, p.fifo[p.head]);
}
