//! The sound of doc/DEVICES.md §12: an FM synthesizer whose registers are
//! the YM2151's, and its FIFO of writes. `Opm` follows the model,
//! test/opm_model.py, step by step, and its unit test replays the model's
//! vectors. The model follows ymfm, whose notice is in the header of
//! test/opm_tables.py.

const std = @import("std");
const T = @import("opm_tables.zig");
const build_options = @import("build_options");

/// The first of the eight words of the sound (DEVICES §12.1).
pub const base: u32 = 0xFFFF_FF08;

/// The writes the FIFO holds (DEVICES §12.3).
pub const fifo_len = 64;

/// The chip's clock, and the clocks of a sample: one sample every 64.
pub const chip_hz: u64 = 3_579_545;
pub const clocks_per_sample: u64 = 64;

/// The sample rate as a WAV file states it, rounded down from 55930.4 Hz.
pub const sample_rate: u32 = @intCast(chip_hz / clocks_per_sample);

/// The value of bits 31..16 of `OPM_STATUS`.
pub const status_id: u32 = 0x2151;

pub const Sample = struct { left: i16, right: i16 };

const State = enum(u2) { attack, decay, sustain, release };

/// The attenuation above which an operator gives 0.
const quiet = 0x380;

/// The slots of a channel's operators in the order of the connections: M1,
/// C1, M2, C2. The key-on bits 3 to 6 of register 0x08 take this order.
const order = [4]u5{ 0, 2, 1, 3 };

/// For each connection: the inputs of the 2nd, 3rd, and 4th operator, and
/// which of the 1st, 2nd, and 3rd go to the output, as `CONNECTIONS` of
/// the model has them.
const Connection = struct { in2: u3, in3: u3, in4: u3, out1: bool, out2: bool, out3: bool };
const connections = [8]Connection{
    .{ .in2 = 1, .in3 = 2, .in4 = 3, .out1 = false, .out2 = false, .out3 = false },
    .{ .in2 = 0, .in3 = 5, .in4 = 3, .out1 = false, .out2 = false, .out3 = false },
    .{ .in2 = 0, .in3 = 2, .in4 = 6, .out1 = false, .out2 = false, .out3 = false },
    .{ .in2 = 1, .in3 = 0, .in4 = 7, .out1 = false, .out2 = false, .out3 = false },
    .{ .in2 = 1, .in3 = 0, .in4 = 3, .out1 = false, .out2 = true, .out3 = false },
    .{ .in2 = 1, .in3 = 1, .in4 = 1, .out1 = false, .out2 = true, .out3 = true },
    .{ .in2 = 1, .in3 = 0, .in4 = 0, .out1 = false, .out2 = true, .out3 = true },
    .{ .in2 = 0, .in3 = 0, .in4 = 0, .out1 = true, .out2 = true, .out3 = true },
};

/// The phase step of the 13 bits block, note, and fraction, moved by
/// `delta` 64ths of a semitone.
fn phaseStepOf(block_freq: u32, delta: i32) u32 {
    var block: i32 = @intCast(block_freq >> 10);
    // The note is 0 to 15 with gaps, 12 in an octave: take 1/4 off.
    const code: i32 = @intCast(((block_freq >> 6) & 15) - ((block_freq >> 8) & 3));
    var freq: i32 = (code << 6) + @as(i32, @intCast(block_freq & 63)) + delta;
    if (freq < 0) {
        freq += 768;
        if (block == 0) return (@as(u32, T.PHASE_STEP[0]) << 5) >> 7;
        block -= 1;
    } else if (freq >= 768) {
        freq -= 768;
        if (freq >= 768) {
            block += 1;
            freq -= 768;
        }
        if (block >= 7) return @as(u32, T.PHASE_STEP[767]) << 5;
        block += 1;
    }
    const shift: u5 = @intCast(block ^ 7);
    return (@as(u32, T.PHASE_STEP[@intCast(freq)]) << 5) >> shift;
}

/// The linear level, 13 bits, of an attenuation of 5.8 bits.
fn volume(att: u32) i32 {
    const v = (@as(u32, T.POW[att & 0xFF]) | 0x400) << 2;
    const shift = att >> 8;
    return if (shift >= 32) 0 else @intCast(v >> @intCast(shift));
}

/// The attenuation of |sin| at a phase of 10 bits, and whether it is negative.
fn sinAtt(phase: u32) struct { att: u32, neg: bool } {
    const i = phase & 0x3FF;
    var q = i & 0x1FF;
    if (q & 0x100 != 0) q = ~q;
    return .{ .att = T.SIN[q & 0xFF], .neg = i & 0x200 != 0 };
}

/// `value` as the DAC gives it (DEVICES §12.4).
pub fn dac(value: i32) i16 {
    if (value < -32768) return -32768;
    if (value > 32767) return 32767;
    const mag: u32 = @bitCast(value ^ (value >> 31));
    const bits: u32 = 32 - @clz(mag);
    const shift: u5 = @intCast(@max(@as(i32, @intCast(bits)) - 8, 1) - 1);
    return @intCast(value & ~((@as(i32, 1) << shift) - 1));
}

fn clamp16(v: i32) i32 {
    return std.math.clamp(v, -32768, 32767);
}

/// The state of one operator, and what the registers give it in this sample.
const Operator = struct {
    phase: u32 = 0, // 10.10 bits
    att: u32 = 0x3FF, // 4.6 bits
    state: State = .release,
    key: u1 = 0, // the key state the envelope follows
    keyon: u1 = 0, // the key state that register 0x08 wrote
    step: u32 = 0,
    dynamic: bool = false,
    block_freq: u32 = 0,
    detune: i32 = 0,
    multiple: u32 = 1,
    tl: u32 = 0,
    sustain: u32 = 0,
    rates: [4]u32 = @splat(0),
};

/// The synthesizer without its FIFO, as `Opm` of the model.
pub const Opm = struct {
    regs: [256]u8,
    ops: [32]Operator,
    fb: [8][2]i32,
    fb_in: [8]i32,
    env_counter: u32,
    lfo_counter: u32,
    lfo_am: u32,
    noise_lfsr: u32,
    noise_counter: u8,
    noise_state: u1,
    noise_wave: [256]u8,

    /// The state after a reset (DEVICES §12.3).
    pub fn init() Opm {
        var o: Opm = .{
            .regs = @splat(0),
            .ops = @splat(.{}),
            .fb = @splat(.{ 0, 0 }),
            .fb_in = @splat(0),
            .env_counter = 0,
            .lfo_counter = 0,
            .lfo_am = 0,
            .noise_lfsr = 1,
            .noise_counter = 0,
            .noise_state = 0,
            .noise_wave = @splat(0),
        };
        for (0x20..0x28) |r| o.regs[r] = 0xC0;
        return o;
    }

    /// A write of `data` to the register `reg`.
    pub fn write(self: *Opm, reg: u8, data: u8) void {
        if (reg == 0x19) {
            // Bit 7 says AM (0) or PM (1); the PM depth is kept at 0x1A.
            self.regs[0x19 + @as(usize, data >> 7)] = data;
        } else if (reg != 0x1A) {
            self.regs[reg] = data;
        }
        if (reg == 0x08) {
            const ch = data & 7;
            for (order, 0..) |o, i| self.ops[8 * @as(usize, o) + ch].keyon = @truncate(data >> @intCast(3 + i));
        }
    }

    fn pmDepth(self: *const Opm) u32 {
        return self.regs[0x1A] & 0x7F;
    }

    fn prepare(self: *Opm, slot: usize) void {
        const r = &self.regs;
        const op = &self.ops[slot];
        const ch = slot & 7;
        const bf: u32 = @as(u32, r[0x28 + ch] & 0x7F) << 6 | r[0x30 + ch] >> 2;
        op.block_freq = bf;
        const keycode = bf >> 8;
        const dt1 = (r[0x40 + slot] >> 4) & 7;
        const d: i32 = T.DETUNE[keycode][dt1 & 3];
        op.detune = if (dt1 & 4 != 0) -d else d;
        const mul: u32 = r[0x40 + slot] & 15;
        op.multiple = if (mul == 0) 1 else mul * 2;
        const pms = (r[0x38 + ch] >> 4) & 7;
        op.dynamic = self.pmDepth() != 0 and pms != 0;
        if (!op.dynamic) op.step = self.phaseStep(slot, 0);
        op.tl = @as(u32, r[0x60 + slot] & 0x7F) << 3;
        var sl: u32 = r[0xE0 + slot] >> 4;
        sl |= (sl + 1) & 0x10;
        op.sustain = sl << 5;
        const ksr = keycode >> @intCast((r[0x80 + slot] >> 6) ^ 3);
        op.rates[@backingInt(State.attack)] = rate(@as(u32, r[0x80 + slot] & 31) * 2, ksr);
        op.rates[@backingInt(State.decay)] = rate(@as(u32, r[0xA0 + slot] & 31) * 2, ksr);
        op.rates[@backingInt(State.sustain)] = rate(@as(u32, r[0xC0 + slot] & 31) * 2, ksr);
        op.rates[@backingInt(State.release)] = rate(@as(u32, r[0xE0 + slot] & 15) * 4 + 2, ksr);
    }

    fn rate(raw: u32, ksr: u32) u32 {
        return if (raw == 0) 0 else @min(raw + ksr, 63);
    }

    fn phaseStep(self: *const Opm, slot: usize, pm: i32) u32 {
        const r = &self.regs;
        const op = &self.ops[slot];
        const ch = slot & 7;
        var delta: i32 = T.DT2[r[0xC0 + slot] >> 6];
        const pms: u5 = @intCast((r[0x38 + ch] >> 4) & 7);
        if (pms != 0) delta += if (pms < 6) pm >> (6 - pms) else pm << (pms - 5);
        const step: u32 = @bitCast(@as(i32, @bitCast(phaseStepOf(op.block_freq, delta))) +% op.detune);
        return (step *% op.multiple) >> 1;
    }

    fn keystate(op: *Operator) void {
        if (op.keyon == op.key) return;
        op.key = op.keyon;
        if (op.key == 1) {
            if (op.state != .attack) {
                op.state = .attack;
                op.phase = 0;
                if (op.rates[@backingInt(State.attack)] >= 62) op.att = 0;
            }
        } else if (op.state != .release) {
            op.state = .release;
        }
    }

    fn envelope(op: *Operator, counter_in: u32) void {
        if (op.state == .attack and op.att == 0) op.state = .decay;
        if (op.state == .decay and op.att >= op.sustain) op.state = .sustain;
        const r = op.rates[@backingInt(op.state)];
        const shift: u5 = @intCast(r >> 2);
        const counter = counter_in << shift;
        if (counter & 0x7FF != 0) return;
        const index: u5 = @intCast((counter >> (if (shift <= 11) 11 else shift)) & 7);
        const inc = (T.INCREMENT[r] >> (4 * index)) & 15;
        if (op.state == .attack) {
            if (r < 62) {
                const a: i32 = @intCast(op.att);
                op.att = @intCast(a + ((-(a + 1) * @as(i32, @intCast(inc))) >> 4));
            }
        } else {
            op.att += inc;
            if (op.att >= 0x400) op.att = 0x3FF;
        }
    }

    fn envAtt(self: *const Opm, op: *const Operator, slot: usize, am: u32) u32 {
        var a = op.att;
        if (self.regs[0xA0 + slot] & 0x80 != 0) a += am;
        a += op.tl;
        return @min(a, 0x3FF);
    }

    fn opOut(self: *const Opm, slot: usize, mod: i32, am: u32) i32 {
        const op = &self.ops[slot];
        if (op.att > quiet) return 0;
        const s = sinAtt((op.phase >> 10) +% @as(u32, @bitCast(mod)));
        const v = volume(s.att + (self.envAtt(op, slot, am) << 2));
        return if (s.neg) -v else v;
    }

    fn noiseAndLfo(self: *Opm) i32 {
        const r = &self.regs;
        const freq: u8 = (r[0x0F] & 31) ^ 31;
        for (0..2) |_| {
            // The taps are those of the register after the shift.
            var lfsr = self.noise_lfsr << 1;
            lfsr |= ((lfsr >> 17) ^ (lfsr >> 14) ^ 1) & 1;
            self.noise_lfsr = lfsr;
            const c = self.noise_counter;
            self.noise_counter +%= 1;
            if (c >= freq) {
                self.noise_counter = 0;
                self.noise_state = @truncate(lfsr >> 17);
            }
        }
        const lrate = r[0x18];
        self.lfo_counter +%= @as(u32, 0x10 | (lrate & 15)) << @intCast(lrate >> 4);
        if (r[0x01] & 2 != 0) self.lfo_counter = 0;
        const lfo: u8 = @truncate(self.lfo_counter >> 22);
        self.noise_wave[lfo +% 1] = @truncate(self.noise_lfsr >> 17);
        var am: u32 = undefined;
        var pm: i32 = undefined;
        switch (r[0x1B] & 3) {
            0 => {
                am = lfo ^ 0xFF;
                pm = @as(i8, @bitCast(lfo));
            },
            1 => {
                const a: u8 = if (lfo & 0x80 != 0) 0 else 0xFF;
                am = a;
                pm = @as(i8, @bitCast(a ^ 0x80));
            },
            2 => {
                const a: u8 = if (lfo & 0x80 != 0) lfo << 1 else (lfo ^ 0xFF) << 1;
                am = a;
                pm = @as(i8, @bitCast(if (lfo & 0x40 != 0) a else a ^ 0xFF));
            },
            else => {
                am = self.noise_wave[lfo];
                pm = @as(i8, @bitCast(self.noise_wave[lfo]));
            },
        }
        self.lfo_am = (am * (r[0x19] & 0x7F)) >> 7;
        return (pm * @as(i32, @intCast(self.pmDepth()))) >> 7;
    }

    /// The next sample.
    pub fn sample(self: *Opm) Sample {
        const r = &self.regs;
        for (0..32) |slot| {
            self.prepare(slot);
            keystate(&self.ops[slot]);
        }
        self.env_counter +%= 1;
        if (self.env_counter & 3 == 3) self.env_counter +%= 1;
        const pm = self.noiseAndLfo();
        const env_due = self.env_counter & 3 == 0;
        for (&self.fb, self.fb_in) |*fb, in| {
            fb[0] = fb[1];
            fb[1] = in;
        }
        for (0..32) |slot| {
            const op = &self.ops[slot];
            if (env_due) envelope(op, self.env_counter >> 2);
            const step = if (op.dynamic) self.phaseStep(slot, pm) else op.step;
            op.phase = (op.phase +% step) & 0xFFFFF;
        }
        var left: i32 = 0;
        var right: i32 = 0;
        for (0..8) |ch| {
            const ams: u5 = @intCast(r[0x38 + ch] & 3);
            const am: u32 = if (ams != 0) self.lfo_am << (ams - 1) else 0;
            const s1 = ch;
            const s2 = 16 + ch;
            const s3 = 8 + ch;
            const s4 = 24 + ch;
            const fbl: u5 = @intCast((r[0x20 + ch] >> 3) & 7);
            const fb = self.fb[ch];
            const mod: i32 = if (fbl != 0) (fb[0] + fb[1]) >> (10 - fbl) else 0;
            const o1 = self.opOut(s1, mod, am);
            self.fb_in[ch] = o1;
            const pan = r[0x20 + ch] >> 6;
            if (pan == 0) continue;
            const c = connections[r[0x20 + ch] & 7];
            var v = [8]i32{ 0, o1, 0, 0, 0, 0, 0, 0 };
            v[2] = self.opOut(s2, v[c.in2] >> 1, am);
            v[5] = v[1] + v[2];
            v[3] = self.opOut(s3, v[c.in3] >> 1, am);
            v[6] = v[1] + v[3];
            v[7] = v[2] + v[3];
            var out: i32 = undefined;
            if (ch == 7 and r[0x0F] & 0x80 != 0) {
                const n: i32 = @intCast((self.envAtt(&self.ops[s4], s4, am) ^ 0x3FF) << 1);
                out = if (self.noise_state == 1) -n else n;
            } else {
                out = self.opOut(s4, v[c.in4] >> 1, am);
            }
            if (c.out1) out = clamp16(out + v[1]);
            if (c.out2) out = clamp16(out + v[2]);
            if (c.out3) out = clamp16(out + v[3]);
            if (pan & 1 != 0) left += out;
            if (pan & 2 != 0) right += out;
        }
        return .{ .left = dac(left), .right = dac(right) };
    }
};

/// Where the samples go, such as the file of --wav.
pub const Sink = struct {
    ctx: *anyopaque,
    put_fn: *const fn (ctx: *anyopaque, s: Sample) void,
};

/// The device of DEVICES §12: the synthesizer, its FIFO of writes, and the
/// accumulator that says when a sample is due.
pub const Sound = struct {
    opm: Opm = .init(),
    fifo: [fifo_len]u16 = undefined,
    head: u8 = 0,
    count: u8 = 0,
    /// The accumulator of §12.3: chip_hz for each microsecond, and a
    /// sample at each 64 million.
    acc: u64 = 0,
    /// The samples since the start, computed or not.
    samples: u64 = 0,
    sink: ?Sink = null,

    /// A reset of the system or a start (DEVICES §12.3). The sink and
    /// the count of samples stay.
    pub fn reset(self: *Sound) void {
        self.opm = .init();
        self.head = 0;
        self.count = 0;
        self.acc = 0;
    }

    pub fn full(self: *const Sound) bool {
        return self.count == fifo_len;
    }

    /// The value a data read of word `i` returns. A read has no side effect.
    pub fn read(self: *const Sound, i: u3) u32 {
        if (i != 1) return 0;
        return status_id << 16 | @as(u32, self.count) << 8 | @as(u32, @intFromBool(self.count != 0)) << 7;
    }

    /// A write of `value` to word `i`. The FIFO must have room: the
    /// caller waits for a sample first.
    pub fn write(self: *Sound, i: u3, value: u32) void {
        if (i != 0) return;
        std.debug.assert(!self.full());
        self.fifo[(self.head + self.count) % fifo_len] = @truncate(value);
        self.count += 1;
    }

    /// The oldest write in the FIFO, if any, takes effect.
    fn takeWrite(self: *Sound) void {
        if (self.count == 0) return;
        const w = self.fifo[self.head];
        self.head = (self.head + 1) % fifo_len;
        self.count -= 1;
        self.opm.write(@truncate(w >> 8), @truncate(w));
    }

    /// The oldest write in the FIFO takes effect, then a sample is computed.
    pub fn tick(self: *Sound) void {
        self.takeWrite();
        const s = self.opm.sample();
        self.samples += 1;
        if (self.sink) |k| k.put_fn(k.ctx, s);
    }

    /// Let `us` microseconds pass, and compute the samples they bring.
    /// Without a sink nobody takes the samples, and nothing else shows
    /// what the synthesizer computes: the status has the FIFO alone. So
    /// then no sample is computed. The writes of the FIFO take effect,
    /// one for each sample, the samples are counted, and the synthesizer
    /// stands still. A sample costs some 0.3 microseconds of the host's
    /// time, which a long run or a long skip would pay for nothing.
    pub fn advance(self: *Sound, us: u64) void {
        const threshold = clocks_per_sample * 1_000_000;
        const total = @as(u128, self.acc) + @as(u128, us) * chip_hz;
        var n = total / threshold;
        self.acc = @intCast(total % threshold);
        if (self.sink == null) {
            for (0..@min(n, self.count)) |_| self.takeWrite();
            self.samples += @intCast(n);
            return;
        }
        while (n != 0) : (n -= 1) self.tick();
    }

    /// The microseconds until the next sample is due.
    pub fn microsToSample(self: *const Sound) u64 {
        const threshold = clocks_per_sample * 1_000_000;
        return std.math.divCeil(u64, threshold - self.acc, chip_hz) catch unreachable;
    }
};

const testing = std.testing;

test "the DAC rounds as the model's test checks by hand" {
    const cases = [_][2]i32{
        .{ 0, 0 },         .{ -1, -1 },       .{ 255, 255 },     .{ 511, 511 },
        .{ 512, 512 },     .{ 513, 512 },     .{ -513, -514 },   .{ 8168, 8160 },
        .{ -8168, -8176 }, .{ 32767, 32704 }, .{ 40000, 32767 }, .{ -40000, -32768 },
    };
    for (cases) |c| try testing.expectEqual(@as(i16, @intCast(c[1])), dac(c[0]));
}

test "the FIFO takes one write before each sample, in order" {
    var s: Sound = .{};
    try testing.expectEqual(status_id << 16, s.read(1));
    s.write(0, 0x2007);
    s.write(0, 0x0F80);
    try testing.expectEqual(status_id << 16 | 2 << 8 | 0x80, s.read(1));
    try testing.expectEqual(0, s.read(0));
    s.tick();
    try testing.expectEqual(0x07, s.opm.regs[0x20]);
    try testing.expectEqual(0, s.opm.regs[0x0F]);
    s.tick();
    try testing.expectEqual(0x80, s.opm.regs[0x0F]);
    try testing.expectEqual(status_id << 16, s.read(1));
    for (0..fifo_len) |_| s.write(0, 0);
    try testing.expect(s.full());
}

test "a sample is due every 64 clocks of 3579545 Hz" {
    var s: Sound = .{};
    s.advance(17);
    try testing.expectEqual(0, s.samples);
    try testing.expectEqual(1, s.microsToSample());
    s.advance(1);
    try testing.expectEqual(1, s.samples);
    s.advance(1_000_000 - 18);
    try testing.expectEqual(55930, s.samples);
    s.advance(1_000_000);
    try testing.expectEqual(111860, s.samples);
}

fn countSample(ctx: *anyopaque, s: Sample) void {
    _ = s;
    const n: *u64 = @ptrCast(@alignCast(ctx));
    n.* += 1;
}

test "without a sink, the writes take effect and no sample is computed" {
    var heard: u64 = 0;
    var a: Sound = .{};
    var b: Sound = .{ .sink = .{ .ctx = &heard, .put_fn = countSample } };
    // The example of DEVICES §12.5.
    const writes = [_]u16{ 0x20C7, 0x284A, 0x607F, 0x687F, 0x707F, 0x5801, 0x981F, 0xF80F, 0x0878 };
    for ([_]*Sound{ &a, &b }) |s| {
        for (writes) |w| s.write(0, w);
        // The first sample is due at 18 microseconds, and takes one write.
        s.advance(18);
        try testing.expectEqual(1, s.samples);
        try testing.expectEqual(0xC7, s.opm.regs[0x20]);
        try testing.expectEqual(0, s.opm.regs[0x28]);
        try testing.expectEqual(status_id << 16 | 8 << 8 | 0x80, s.read(1));
        // A second brings 55930 samples, and the other eight writes.
        s.advance(1_000_000 - 18);
        try testing.expectEqual(55930, s.samples);
        try testing.expectEqual(status_id << 16, s.read(1));
    }
    try testing.expectEqualSlices(u8, &b.opm.regs, &a.opm.regs);
    try testing.expectEqual(0x78, a.opm.regs[0x08]);
    // With the sink the synthesizer ran, and without it stood still.
    try testing.expectEqual(55930, heard);
    try testing.expect(b.opm.env_counter != 0);
    try testing.expectEqual(0, a.opm.env_counter);
    // So a year of microseconds takes no time, and counts its samples:
    // 366 * 86400 * 3579545 / 64 of them.
    a.advance(366 * 86400 * 1_000_000);
    try testing.expectEqual(55930 + 1768653184500, a.samples);
}

// The vectors of test/opm_vectors.py, which make test writes and names
// with -Dopm-vectors: a log of writes, then each sample.
test "the sound replays the vectors of the model" {
    const path = build_options.opm_vectors orelse return error.SkipZigTest;
    const text = try std.Io.Dir.cwd().readFileAlloc(testing.io, path, testing.allocator, .limited(1 << 30));
    defer testing.allocator.free(text);
    var writes: std.ArrayList([3]u32) = .empty;
    defer writes.deinit(testing.allocator);
    var lines = std.mem.splitScalar(u8, text, '\n');
    var o: Opm = .init();
    var next: usize = 0;
    var count: usize = 0;
    var failures: usize = 0;
    var in_log = true;
    while (lines.next()) |line| {
        if (line.len == 0 or line[0] == '#') continue;
        var f = std.mem.tokenizeScalar(u8, line, ' ');
        const a = f.next() orelse return error.Format;
        if (std.mem.eql(u8, a, "end")) {
            in_log = false;
            continue;
        }
        const n = try std.fmt.parseInt(u32, a, 10);
        const b = f.next() orelse return error.Format;
        const c = f.next() orelse return error.Format;
        if (in_log) {
            // A write: the sample, the register, and the data, in hex.
            try writes.append(testing.allocator, .{ n, try std.fmt.parseInt(u8, b, 16), try std.fmt.parseInt(u8, c, 16) });
            continue;
        }
        // A sample: its number, left, and right.
        if (n != count) return error.Format;
        if (next < writes.items.len and writes.items[next][0] == n) {
            o.write(@intCast(writes.items[next][1]), @intCast(writes.items[next][2]));
            next += 1;
        }
        const s = o.sample();
        const left = try std.fmt.parseInt(i16, b, 10);
        const right = try std.fmt.parseInt(i16, c, 10);
        if (s.left != left or s.right != right) {
            failures += 1;
            if (failures <= 10) std.debug.print("FAIL sample {d}: {d} {d}, not {d} {d}\n", .{ n, s.left, s.right, left, right });
        }
        count += 1;
    }
    if (failures > 0) {
        std.debug.print("{d} of {d} vectors failed\n", .{ failures, count });
        return error.TestFailed;
    }
    try testing.expect(count > 0);
}
