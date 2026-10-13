//! The NICE processor, as specified in doc/ISA.md. Section numbers (§) refer
//! to that document.

const std = @import("std");

/// SR bit numbers (§1.3).
pub const sr_i: u5 = 31;
pub const sr_e: u5 = 30;
pub const sr_v: u5 = 29;
pub const sr_n: u5 = 28;
pub const sr_z: u5 = 27;
pub const sr_c: u5 = 26;
pub const sr_x: u5 = 25;
pub const sr_one: u5 = 24;

const one_bit: u32 = 1 << sr_one;
/// The flags an instruction with M = 1 rewrites (§6).
const flag_mask: u32 = 0x3E00_0000;

pub const HaltReason = enum {
    /// Not halted.
    none,
    /// A `HALT` instruction.
    halt,
    /// A reserved control word (§5.3).
    reserved,
    /// `INT` while `in_service` = 1 (§7.2).
    nested_int,
    /// `RTI` while `in_service` = 0 (§7.4).
    rti_outside_isr,

    pub fn describe(self: HaltReason) []const u8 {
        return switch (self) {
            .none => "running",
            .halt => "HALT",
            .reserved => "reserved control instruction",
            .nested_int => "INT inside an interrupt routine",
            .rti_outside_isr => "RTI outside an interrupt routine",
        };
    }
};

pub const Cpu = struct {
    /// R0..R15. Read and write them through `getReg` and `setReg`, which
    /// apply the rules for R0 and R14 (§4.3).
    regs: [16]u32,
    /// Memory from address 0. Addresses at or beyond `mem.len` have nothing
    /// behind them: reads return 0 and writes are ignored (§8.2).
    mem: []u32,

    // Hidden state (§1.4).
    in_service: bool,
    after_rti: bool,
    saved_pc: u32,
    saved_sr: u32,
    halt_reason: HaltReason,

    // Pending interrupt requests, holding the vector the device supplies (§7.1).
    nmi_pending: ?u8,
    irq_pending: ?u8,

    /// When set, `step` writes one line per instruction or interrupt here.
    trace: ?*std.Io.Writer,
    /// The last memory write, for the trace.
    last_write: ?struct { addr: u32, value: u32 },

    /// A processor after reset (§8.1), using `mem` as its memory.
    pub fn init(mem: []u32) Cpu {
        var cpu: Cpu = .{
            .regs = undefined,
            .mem = mem,
            .in_service = false,
            .after_rti = false,
            .saved_pc = 0,
            .saved_sr = 0,
            .halt_reason = .none,
            .nmi_pending = null,
            .irq_pending = null,
            .trace = null,
            .last_write = null,
        };
        cpu.reset();
        return cpu;
    }

    pub fn reset(self: *Cpu) void {
        self.regs = @splat(0);
        self.regs[14] = one_bit;
        self.in_service = false;
        self.after_rti = false;
        self.halt_reason = .none;
        self.nmi_pending = null;
        self.irq_pending = null;
    }

    pub fn halted(self: *const Cpu) bool {
        return self.halt_reason != .none;
    }

    /// Raise the maskable interrupt request with vector `v`. Requests that
    /// arrive while one is pending merge into one (§7.1).
    pub fn requestIrq(self: *Cpu, v: u8) void {
        self.irq_pending = v;
    }

    /// Raise the non-maskable interrupt request with vector `v`.
    pub fn requestNmi(self: *Cpu, v: u8) void {
        self.nmi_pending = v;
    }

    pub fn getReg(self: *const Cpu, r: u4) u32 {
        return switch (r) {
            0 => 0,
            14 => self.regs[14] | one_bit,
            else => self.regs[r],
        };
    }

    pub fn setReg(self: *Cpu, r: u4, value: u32) void {
        switch (r) {
            0 => {},
            14 => self.regs[14] = value | one_bit,
            else => self.regs[r] = value,
        }
    }

    pub fn read(self: *const Cpu, addr: u32) u32 {
        return if (addr < self.mem.len) self.mem[addr] else 0;
    }

    pub fn write(self: *Cpu, addr: u32, value: u32) void {
        if (addr < self.mem.len) self.mem[addr] = value;
        self.last_write = .{ .addr = addr, .value = value };
    }

    fn flag(self: *const Cpu, bit: u5) u1 {
        return @truncate(self.getReg(14) >> bit);
    }

    /// Take a pending interrupt if one may be taken, or else run one
    /// instruction. Does nothing once the processor has halted.
    pub fn step(self: *Cpu) std.Io.Writer.Error!void {
        if (self.halted()) return;
        const before = self.regs;

        // §7.1: interrupts are checked before each instruction fetch.
        if (!self.after_rti and !self.in_service) {
            if (self.nmi_pending) |v| {
                self.nmi_pending = null;
                self.enterInterrupt(v);
                return self.traceInterrupt("NMI", v, before);
            }
            if (self.irq_pending) |v| {
                if (self.flag(sr_e) == 1) {
                    self.irq_pending = null;
                    self.enterInterrupt(v);
                    return self.traceInterrupt("IRQ", v, before);
                }
            }
        }

        // The instruction about to run clears after_rti when it completes,
        // unless it is itself an RTI, which sets it again.
        self.after_rti = false;
        self.last_write = null;
        const pc = self.regs[15];
        const iw = self.read(pc);
        const executed = self.execute();
        if (self.trace) |w| try self.traceInstruction(w, pc, iw, executed, before);
    }

    /// §7.2: interrupt entry, for IRQ, NMI and INT.
    fn enterInterrupt(self: *Cpu, v: u8) void {
        const sr = self.getReg(14);
        self.saved_pc = self.regs[15];
        self.saved_sr = sr;
        self.in_service = true;
        self.setReg(14, sr | (1 << sr_i));
        self.setReg(15, self.read(((sr & 0x00FF_FFFF) << 8) +% v));
    }

    /// Fetch and run one instruction (§5). Returns false if its condition
    /// was false.
    fn execute(self: *Cpu) bool {
        // 1. Fetch.
        const iw = self.fetch();

        const neg: u1 = @truncate(iw >> 31);
        const sel: u3 = @truncate(iw >> 28);
        const class: u2 = @truncate(iw >> 26);
        const m = (iw >> 25) & 1 == 1;
        const op: u4 = @truncate(iw >> 21);
        const fields = [3]u7{ @truncate(iw >> 14), @truncate(iw >> 7), @truncate(iw) };

        // 2. Constants, in the order dest, s0, s1.
        var consts: [3]u32 = @splat(0);
        if (class != 0b11) {
            for (fields, &consts) |f, *c| {
                if (f & 0x30 == 0x30) c.* = self.fetch();
            }
        }

        // 3. Condition, tested against SR as it was before the instruction.
        if (self.flag(@as(u5, sr_one) + sel) ^ neg == 0) return false;

        // 4. Control.
        if (class == 0b11) {
            self.control(iw);
            return true;
        }

        // 5. Sources.
        const s0 = self.source(fields[1], consts[1]);
        const s1 = self.source(fields[2], consts[2]);

        // 6. Operation.
        const res = if (class == 0b10)
            shift(op, s0, s1, self.flag(sr_c))
        else
            alu(op, s0, s1, if ((iw >> 26) & 1 == 1) self.flag(sr_c) else 0);

        // 7. Destination.
        self.destination(fields[0], consts[0], res.r);

        // 8. Flags (§6).
        const dmode: u3 = @truncate(fields[0] >> 4);
        const dreg: u4 = @truncate(fields[0]);
        if (m and !(dreg == 14 and dmode <= 0b010)) {
            var sr = self.getReg(14) & ~flag_mask;
            if (res.r == 0xFFFF_FFFF) sr |= 1 << sr_x;
            if (res.r == 0) sr |= 1 << sr_z;
            sr |= (res.r >> 31) << sr_n;
            sr |= @as(u32, res.c) << sr_c;
            sr |= @as(u32, res.v) << sr_v;
            self.setReg(14, sr);
        }
        return true;
    }

    fn fetch(self: *Cpu) u32 {
        const word = self.read(self.regs[15]);
        self.regs[15] +%= 1;
        return word;
    }

    /// §4.1: evaluate a source operand, including its side effect.
    fn source(self: *Cpu, field: u7, c: u32) u32 {
        const r: u4 = @truncate(field);
        return switch (@as(u3, @truncate(field >> 4))) {
            0b000 => self.getReg(r),
            0b001 => blk: {
                self.setReg(r, self.getReg(r) -% 1);
                break :blk self.getReg(r);
            },
            0b010 => blk: {
                const v = self.getReg(r);
                self.setReg(r, v +% 1);
                break :blk v;
            },
            0b011 => self.getReg(r) +% c,
            0b100 => self.read(self.getReg(r)),
            0b101 => blk: {
                self.setReg(r, self.getReg(r) -% 1);
                break :blk self.read(self.getReg(r));
            },
            0b110 => blk: {
                const v = self.read(self.getReg(r));
                self.setReg(r, self.getReg(r) +% 1);
                break :blk v;
            },
            0b111 => self.read(self.getReg(r) +% c),
        };
    }

    /// §4.2: write the result to the destination and apply its side effect.
    fn destination(self: *Cpu, field: u7, c: u32, res: u32) void {
        const r: u4 = @truncate(field);
        switch (@as(u3, @truncate(field >> 4))) {
            0b000 => self.setReg(r, res),
            0b001 => {
                self.setReg(r, res);
                self.setReg(r, self.getReg(r) -% 1);
            },
            0b010 => {
                self.setReg(r, res);
                self.setReg(r, self.getReg(r) +% 1);
            },
            0b011, 0b111 => self.write(self.getReg(r) +% c, res),
            0b100 => self.write(self.getReg(r), res),
            0b101 => {
                self.setReg(r, self.getReg(r) -% 1);
                self.write(self.getReg(r), res);
            },
            0b110 => {
                self.write(self.getReg(r), res);
                self.setReg(r, self.getReg(r) +% 1);
            },
        }
    }

    /// §5.3: HALT, RTI, INT and the reserved commands.
    fn control(self: *Cpu, iw: u32) void {
        const cmd: u5 = @truncate(iw >> 21);
        const vector: u8 = @truncate(iw);
        if (iw & 0x001F_FF00 != 0 or (cmd != 0b00010 and vector != 0)) {
            self.halt_reason = .reserved;
            return;
        }
        switch (cmd) {
            0b00000 => self.halt_reason = .halt,
            0b00001 => {
                if (!self.in_service) {
                    self.halt_reason = .rti_outside_isr;
                    return;
                }
                self.setReg(14, self.saved_sr);
                self.setReg(15, self.saved_pc);
                self.in_service = false;
                self.after_rti = true;
            },
            0b00010 => {
                if (self.in_service) {
                    self.halt_reason = .nested_int;
                    return;
                }
                self.enterInterrupt(vector);
            },
            else => self.halt_reason = .reserved,
        }
    }

    fn traceInterrupt(self: *Cpu, kind: []const u8, v: u8, before: [16]u32) std.Io.Writer.Error!void {
        const w = self.trace orelse return;
        try w.print("{s} {x:0>2}        ", .{ kind, v });
        try self.traceChanges(w, before, null);
    }

    fn traceInstruction(self: *Cpu, w: *std.Io.Writer, pc: u32, iw: u32, executed: bool, before: [16]u32) std.Io.Writer.Error!void {
        try w.print("{x:0>8} {x:0>8}", .{ pc, iw });
        if (!executed) return w.writeAll(" skipped\n");
        // PC is listed only when it differs from the address after the
        // instruction's last constant word, that is, on a jump.
        try self.traceChanges(w, before, nextPc(pc, iw));
    }

    /// The address after the instruction `iw` at `pc` and its constant words.
    fn nextPc(pc: u32, iw: u32) u32 {
        var n: u32 = 1;
        if ((iw >> 26) & 0b11 != 0b11) {
            for ([3]u5{ 14, 7, 0 }) |shift_by| {
                if ((iw >> shift_by) & 0x30 == 0x30) n += 1;
            }
        }
        return pc +% n;
    }

    fn traceChanges(self: *Cpu, w: *std.Io.Writer, before: [16]u32, next_pc: ?u32) std.Io.Writer.Error!void {
        for (0..15) |i| {
            if (self.regs[i] != before[i]) try w.print(" R{d}={x:0>8}", .{ i, self.regs[i] });
        }
        if (next_pc == null or self.regs[15] != next_pc.?) try w.print(" R15={x:0>8}", .{self.regs[15]});
        if (self.last_write) |lw| try w.print(" [{x:0>8}]={x:0>8}", .{ lw.addr, lw.value });
        if (self.halted()) try w.print(" {s}", .{self.halt_reason.describe()});
        try w.writeByte('\n');
    }
};

/// The result of an operation: the value, plus C and V for the flag update.
const Result = struct { r: u32, c: u1 = 0, v: u1 = 0 };

fn add(a: u32, b: u32, cin: u1) Result {
    const sum = @as(u64, a) + b + cin;
    const r: u32 = @truncate(sum);
    return .{ .r = r, .c = @truncate(sum >> 32), .v = @truncate(((a ^ r) & (b ^ r)) >> 31) };
}

fn sub(a: u32, b: u32, cin: u1) Result {
    const r = a -% b -% cin;
    const borrow = @as(u64, a) < @as(u64, b) + cin;
    return .{ .r = r, .c = @intFromBool(borrow), .v = @truncate(((a ^ b) & (a ^ r)) >> 31) };
}

/// §5.1. `cin` is already 0 if the instruction's C bit is clear.
fn alu(op: u4, s0: u32, s1: u32, cin: u1) Result {
    return switch (op) {
        0b0000 => .{ .r = s0 },
        0b0001 => sub(s0, s1, cin),
        0b0010 => add(s0, s0 & s1, cin),
        0b0011 => add(s0, s1, cin),
        0b0100 => add(s0, s0, cin),
        0b0101 => sub(s0, 1, 0),
        0b0110 => .{ .r = ~s0 },
        0b0111 => .{ .r = ~(s0 | s1) },
        0b1000 => .{ .r = ~s0 & s1 },
        0b1001 => .{ .r = ~(s0 & s1) },
        0b1010 => .{ .r = s0 ^ s1 },
        0b1011 => .{ .r = ~s0 | s1 },
        0b1100 => .{ .r = ~(s0 ^ s1) },
        0b1101 => .{ .r = s0 & s1 },
        0b1110 => .{ .r = 1 },
        0b1111 => .{ .r = s0 | s1 },
    };
}

/// §5.2. Bit 3 of `op` is the direction; bits 2..0 pick the fill bit and
/// whether the bit shifted out goes to C, the same way in both directions.
fn shift(op: u4, s0: u32, count: u32, c_in: u1) Result {
    const Fill = enum { zero, one, carry, out };
    const kinds = [8]struct { fill: Fill, to_c: bool }{
        .{ .fill = .zero, .to_c = false },
        .{ .fill = .one, .to_c = false },
        .{ .fill = .carry, .to_c = false },
        .{ .fill = .zero, .to_c = true },
        .{ .fill = .one, .to_c = true },
        .{ .fill = .carry, .to_c = true },
        .{ .fill = .out, .to_c = false },
        .{ .fill = .out, .to_c = true },
    };
    const kind = kinds[op & 0b111];
    const right = op & 0b1000 != 0;

    // The loop of §5.2, with the count reduced to at most 33 steps without
    // changing the result or C:
    // - `C<C` and `C>C` rotate 33 bits, so only n mod 33 matters.
    // - The other rotations repeat every 32 steps. Keeping n > 0 keeps the
    //   last bit rotated, which C<< and >>C copy to C.
    // - With a fixed fill, every step after the 33rd shifts out the fill bit
    //   and leaves d and c as they were.
    const n: u32 = if (kind.fill == .carry and kind.to_c)
        count % 33
    else if (kind.fill == .out)
        (if (count == 0) 0 else (count - 1) % 32 + 1)
    else
        @min(count, 33);

    var d = s0;
    var c = c_in;
    for (0..n) |_| {
        const out: u1 = @truncate(if (right) d else d >> 31);
        const fill: u1 = switch (kind.fill) {
            .zero => 0,
            .one => 1,
            .carry => c,
            .out => out,
        };
        d = if (right) (d >> 1) | (@as(u32, fill) << 31) else (d << 1) | fill;
        if (kind.to_c) c = out;
    }
    return .{ .r = d, .c = if (kind.to_c) c else 0 };
}

// ---------------------------------------------------------------- tests ---

const testing = std.testing;

// Instruction encoders for the tests (§2).
const Cond = enum(u4) { always = 0, x = 1, c = 2, z = 3, n = 4, v = 5, e = 6, i = 7, never = 8, nx = 9, nc = 10, nz = 11 };

fn alu_iw(cond: Cond, op: u4, cm: enum { none, m, c, cm }, d: u7, s0: u7, s1: u7) u32 {
    const bits: u32 = switch (cm) {
        .none => 0,
        .m => 0b001,
        .c => 0b010,
        .cm => 0b011,
    };
    return @as(u32, @intFromEnum(cond)) << 28 | bits << 25 | @as(u32, op) << 21 |
        @as(u32, d) << 14 | @as(u32, s0) << 7 | s1;
}

fn shift_iw(op: u4, m: bool, d: u7, s0: u7, s1: u7) u32 {
    return 0b10 << 26 | @as(u32, @intFromBool(m)) << 25 | @as(u32, op) << 21 |
        @as(u32, d) << 14 | @as(u32, s0) << 7 | s1;
}

// Operand fields (§2.2).
fn reg(r: u4) u7 {
    return r;
}
fn predec(r: u4) u7 {
    return 0x10 | @as(u7, r);
}
fn postinc(r: u4) u7 {
    return 0x20 | @as(u7, r);
}
fn imm(r: u4) u7 {
    return 0x30 | @as(u7, r);
}
fn ind(r: u4) u7 {
    return 0x40 | @as(u7, r);
}
fn ind_predec(r: u4) u7 {
    return 0x50 | @as(u7, r);
}
fn ind_postinc(r: u4) u7 {
    return 0x60 | @as(u7, r);
}
fn ind_imm(r: u4) u7 {
    return 0x70 | @as(u7, r);
}

const MOVE = 0b0000;
const SUB = 0b0001;
const MDBL = 0b0010;
const ADD = 0b0011;
const DEC = 0b0101;
const NOT = 0b0110;
const AND = 0b1101;
const ONE = 0b1110;
const OR = 0b1111;
const HALT = 0x0C00_0000;
const RTI = 0x0C20_0000;
const INT = 0x0C40_0000;

/// Load `program` at address 0 and run it until it halts.
fn run(mem: []u32, program: []const u32) Cpu {
    @memset(mem, 0);
    @memcpy(mem[0..program.len], program);
    var cpu = Cpu.init(mem);
    var steps: usize = 0;
    while (!cpu.halted()) : (steps += 1) {
        if (steps == 10_000) @panic("program did not halt");
        cpu.step() catch unreachable;
    }
    return cpu;
}

fn flags(cpu: *const Cpu) u32 {
    return cpu.getReg(14) & flag_mask;
}

test "worked example of §11 and source order of §5" {
    var mem: [0x100]u32 = undefined;
    // MOVE R1, 0x40;  MOVE @R1, R1++;  HALT
    const cpu = run(&mem, &.{
        alu_iw(.always, MOVE, .none, reg(1), imm(0), reg(0)), 0x40, // MOVE R1, 0x40
        alu_iw(.always, MOVE, .none, ind(1), postinc(1), reg(0)), // MOVE @R1, R1++
        HALT,
    });
    try testing.expectEqual(0x40, cpu.read(0x41));
    try testing.expectEqual(0x41, cpu.getReg(1));
    // The §11 encoding.
    try testing.expectEqual(0xB278C971, alu_iw(.nz, ADD, .m, ind_postinc(3), predec(2), ind_imm(1)));
}

test "R14 bit 24 and MOVE R1, --R14 (§4.3)" {
    var mem: [0x100]u32 = undefined;
    const cpu = run(&mem, &.{ alu_iw(.always, MOVE, .none, reg(1), predec(14), reg(0)), HALT });
    try testing.expectEqual(0x01FF_FFFF, cpu.getReg(1));
    try testing.expectEqual(0x01FF_FFFF, cpu.getReg(14));
}

test "R0 reads 0 in every mode (§4.3)" {
    var mem: [0x100]u32 = undefined;
    // MOVE R1, --R0;  MOVE R2, @--R0  (reads word 0)
    const cpu = run(&mem, &.{
        alu_iw(.always, MOVE, .none, reg(1), predec(0), reg(0)),
        alu_iw(.always, MOVE, .none, reg(2), ind_predec(0), reg(0)),
        HALT,
    });
    try testing.expectEqual(0, cpu.getReg(1));
    try testing.expectEqual(mem[0], cpu.getReg(2));
    try testing.expectEqual(0, cpu.getReg(0));
}

test "R15 reads as the next instruction; call and return (§9.1)" {
    var mem: [0x100]u32 = undefined;
    // 0: MOVE R13, 0x80         ; SP
    // 2: ADD @--R13, 2, R15     ; push return address 6
    // 4: MOVE R15, 8            ; call
    // 6: HALT
    // 7: (unused)
    // 8: MOVE R1, 7
    // 10: MOVE R15, @R13++      ; return
    const cpu = run(&mem, &.{
        alu_iw(.always, MOVE, .none, reg(13), imm(0), reg(0)), 0x80, // 0
        alu_iw(.always, ADD, .none, ind_predec(13), imm(0), reg(15)), 2, // 2
        alu_iw(.always, MOVE, .none, reg(15), imm(0), reg(0)), 8, // 4
        HALT, // 6
        0, // 7
        alu_iw(.always, MOVE, .none, reg(1), imm(0), reg(0)), 7, // 8
        alu_iw(.always, MOVE, .none, reg(15), ind_postinc(13), reg(0)), // 10
    });
    try testing.expectEqual(7, cpu.getReg(1));
    try testing.expectEqual(0x80, cpu.getReg(13));
    try testing.expectEqual(6, mem[0x7F]);
    try testing.expectEqual(7, cpu.getReg(15));
}

test "skipped instruction consumes constants and has no effect (§3)" {
    var mem: [0x100]u32 = undefined;
    // ?Z MOVE @0x50, R2++, @R3++  is skipped: Z = 0 after reset.
    const cpu = run(&mem, &.{
        alu_iw(.z, MOVE, .none, imm(0), postinc(2), ind_postinc(3)), 0x50, // ?Z MOVE 0x50, R2++, @R3++
        alu_iw(.nz, MOVE, .none, reg(4), imm(0), reg(0)), 9, // ?!Z MOVE R4, 9
        HALT,
    });
    try testing.expectEqual(0, cpu.getReg(2));
    try testing.expectEqual(0, cpu.getReg(3));
    try testing.expectEqual(9, cpu.getReg(4));
    try testing.expectEqual(0, mem[0x50]);
}

test "ALU carry, borrow and overflow (§5.1)" {
    try testing.expectEqual(Result{ .r = 0, .c = 1, .v = 0 }, add(0xFFFF_FFFF, 1, 0));
    try testing.expectEqual(Result{ .r = 0x8000_0000, .c = 0, .v = 1 }, add(0x7FFF_FFFF, 0, 1));
    try testing.expectEqual(Result{ .r = 0xFFFF_FFFF, .c = 1, .v = 0 }, sub(0, 1, 0));
    try testing.expectEqual(Result{ .r = 0xFFFF_FFFF, .c = 1, .v = 0 }, sub(5, 5, 1));
    try testing.expectEqual(Result{ .r = 0x7FFF_FFFF, .c = 0, .v = 1 }, alu(DEC, 0x8000_0000, 0, 0));
    try testing.expectEqual(Result{ .r = 0xFFFF_FFFF, .c = 1, .v = 0 }, alu(DEC, 0, 0, 0));
    try testing.expectEqual(Result{ .r = 6 }, alu(MDBL, 3, 0xFFFF_FFFF, 0));
    try testing.expectEqual(Result{ .r = 3 }, alu(MDBL, 3, 0, 0));
    try testing.expectEqual(Result{ .r = 1 }, alu(ONE, 7, 7, 1));
}

test "flags with M (§6)" {
    var mem: [0x100]u32 = undefined;
    // MOVE R1, 0xFFFFFFFF; ADD[M] R2, R1, 1 -> Z, C;  then ADD[CM] R3, R0, R0 -> 1
    var cpu = run(&mem, &.{
        alu_iw(.always, MOVE, .none, reg(1), imm(0), reg(0)), 0xFFFF_FFFF, // MOVE R1, -1
        alu_iw(.always, ADD, .m, reg(2), reg(1), imm(0)), 1, // ADD[M] R2, R1, 1
        alu_iw(.always, ADD, .cm, reg(3), reg(0), reg(0)), // ADD[CM] R3, R0, R0
        HALT,
    });
    try testing.expectEqual(1, cpu.getReg(3));
    try testing.expectEqual(0, flags(&cpu));

    // MOVE[M] R1, -1 sets X and N; logic ops clear C.
    cpu = run(&mem, &.{ alu_iw(.always, MOVE, .m, reg(1), imm(0), reg(0)), 0xFFFF_FFFF, HALT });
    try testing.expectEqual(1 << sr_x | 1 << sr_n, flags(&cpu));

    // Flags come from r, not from the value an Rx++ destination stores.
    cpu = run(&mem, &.{ alu_iw(.always, MOVE, .m, postinc(1), reg(0), reg(0)), HALT });
    try testing.expectEqual(1, cpu.getReg(1));
    try testing.expectEqual(1 << sr_z, flags(&cpu));
}

test "explicit write to R14 beats the flag update (§6)" {
    var mem: [0x100]u32 = undefined;
    const cpu = run(&mem, &.{ alu_iw(.always, OR, .m, reg(14), reg(14), imm(0)), 0x4000_0000, HALT });
    try testing.expectEqual(0x4100_0000, cpu.getReg(14));
}

test "shifts (§5.2)" {
    // 0<0 and 0>0
    try testing.expectEqual(Result{ .r = 0x10 }, shift(0b0000, 1, 4, 0));
    try testing.expectEqual(Result{ .r = 0 }, shift(0b0000, 0xFFFF_FFFF, 0xFFFF_FFFF, 0));
    try testing.expectEqual(Result{ .r = 0x0800_0000 }, shift(0b1000, 0x8000_0000, 4, 0));
    // 1>0 fills ones from the top.
    try testing.expectEqual(Result{ .r = 0xF000_0000 }, shift(0b1001, 0, 4, 0));
    // C<0: C = last bit out; n = 32 gives bit 0, n > 32 gives the fill bit.
    try testing.expectEqual(Result{ .r = 0, .c = 1 }, shift(0b0011, 0x8000_0000, 1, 0));
    try testing.expectEqual(Result{ .r = 0, .c = 1 }, shift(0b0011, 1, 32, 0));
    try testing.expectEqual(Result{ .r = 0, .c = 0 }, shift(0b0011, 0xFFFF_FFFF, 33, 1));
    try testing.expectEqual(Result{ .r = 0xFFFF_FFFF, .c = 1 }, shift(0b0100, 0, 1000, 0));
    // n = 0: C keeps its value for the shifts that write C, else 0.
    try testing.expectEqual(Result{ .r = 5, .c = 1 }, shift(0b0011, 5, 0, 1));
    try testing.expectEqual(Result{ .r = 5, .c = 0 }, shift(0b0000, 5, 0, 1));
    // Rotations.
    try testing.expectEqual(Result{ .r = 0x0000_0003 }, shift(0b0110, 0x8000_0001, 1, 0));
    try testing.expectEqual(Result{ .r = 0x8000_0001, .c = 1 }, shift(0b0111, 0x8000_0001, 32, 0));
    try testing.expectEqual(Result{ .r = 0x8000_0001, .c = 1 }, shift(0b1111, 0x8000_0001, 64, 0));
    try testing.expectEqual(Result{ .r = 1, .c = 0 }, shift(0b1111, 1, 64, 1));
    try testing.expectEqual(Result{ .r = 1, .c = 0 }, shift(0b1111, 2, 1, 1));
    try testing.expectEqual(Result{ .r = 0xC000_0000, .c = 1 }, shift(0b1111, 0x8000_0001, 1, 0));
    // 33-bit rotation through carry.
    try testing.expectEqual(Result{ .r = 1, .c = 1 }, shift(0b0101, 0x8000_0000, 1, 1));
    try testing.expectEqual(Result{ .r = 0x1234_5678, .c = 1 }, shift(0b0101, 0x1234_5678, 33 * 7, 1));
    try testing.expectEqual(Result{ .r = 0x8000_0000, .c = 1 }, shift(0b1101, 1, 1, 1));
    // 0<C fills with the original C every step.
    try testing.expectEqual(Result{ .r = 0xF }, shift(0b0010, 0, 4, 1));
}

test "shifts write C only with M (§5.2)" {
    var mem: [0x100]u32 = undefined;
    // C<1 R1, R2, 1 with R2 = 0x80000000, without and with M.
    var cpu = run(&mem, &.{
        alu_iw(.always, MOVE, .none, reg(2), imm(0), reg(0)), 0x8000_0000, // MOVE R2, 0x80000000
        shift_iw(0b0100, false, reg(1), reg(2), imm(0)), 1, // C<1 R1, R2, 1
        HALT,
    });
    try testing.expectEqual(1, cpu.getReg(1));
    try testing.expectEqual(0, flags(&cpu));
    cpu = run(&mem, &.{
        alu_iw(.always, MOVE, .none, reg(2), imm(0), reg(0)), 0x8000_0000, // MOVE R2, 0x80000000
        shift_iw(0b0100, true, reg(1), reg(2), imm(0)), 1, // C<1[M] R1, R2, 1
        HALT,
    });
    try testing.expectEqual(1 << sr_c, flags(&cpu));
}

test "INT and RTI (§7)" {
    var mem: [0x100]u32 = undefined;
    // VBASE = 0, so vector 3 is word 3.
    // 0: MOVE R15, 0x10
    // 2: (unused)
    // 3: .DAT 0x20                ; vector 3
    // 0x10: INT 3
    // 0x11: MOVE R2, R1           ; runs after RTI
    // 0x12: HALT
    // 0x20: MOVE[M] R1, @R0++     ; sets the flags inside the routine
    // 0x21: MOVE R3, R14
    // 0x22: RTI
    var program: [0x23]u32 = @splat(0);
    program[0] = alu_iw(.always, MOVE, .none, reg(15), imm(0), reg(0));
    program[1] = 0x10;
    program[3] = 0x20;
    program[0x10] = INT + 3;
    program[0x11] = alu_iw(.always, MOVE, .none, reg(2), reg(1), reg(0));
    program[0x12] = HALT;
    program[0x20] = alu_iw(.always, MOVE, .m, reg(1), ind(0), reg(0));
    program[0x21] = alu_iw(.always, MOVE, .none, reg(3), reg(14), reg(0));
    program[0x22] = RTI;
    const cpu = run(&mem, &program);
    try testing.expectEqual(.halt, cpu.halt_reason);
    try testing.expectEqual(program[0], cpu.getReg(2));
    // Inside the routine I was set; RTI restored SR.
    try testing.expectEqual(0x8100_0000, cpu.getReg(3));
    try testing.expectEqual(0x0100_0000, cpu.getReg(14));
    try testing.expectEqual(false, cpu.in_service);
}

test "IRQ needs E, NMI does not, and neither is taken right after RTI (§7.1)" {
    var mem: [0x100]u32 = undefined;
    @memset(&mem, 0);
    mem[5] = 0x40; // vector 5
    mem[6] = 0x50; // vector 6
    mem[0x40] = RTI;
    mem[0x50] = RTI;
    var cpu = Cpu.init(&mem);

    cpu.requestIrq(5);
    try cpu.step(); // E = 0: a NOP at address 0 runs instead
    try testing.expectEqual(1, cpu.regs[15]);
    try testing.expect(cpu.irq_pending != null);

    cpu.requestNmi(6);
    try cpu.step(); // NMI entry
    try testing.expectEqual(0x50, cpu.regs[15]);
    try testing.expectEqual(1, cpu.saved_pc);

    cpu.setReg(14, cpu.getReg(14) | 1 << sr_e);
    try cpu.step(); // RTI; the saved SR has E = 0
    try testing.expectEqual(1, cpu.regs[15]);
    cpu.saved_sr = 0; // irrelevant from here
    cpu.setReg(14, 1 << sr_e);
    try cpu.step(); // after_rti: the NOP at 1 runs first
    try testing.expectEqual(2, cpu.regs[15]);
    try cpu.step(); // now the IRQ
    try testing.expectEqual(0x40, cpu.regs[15]);
    try testing.expectEqual(null, cpu.irq_pending);
}

test "reserved control words halt, unless skipped (§5.3)" {
    var mem: [0x100]u32 = undefined;
    var cpu = run(&mem, &.{ 0x0C00_0001, HALT });
    try testing.expectEqual(.reserved, cpu.halt_reason);
    cpu = run(&mem, &.{ 0x8C60_0000, HALT }); // never-executed command 3
    try testing.expectEqual(.halt, cpu.halt_reason);
    try testing.expectEqual(2, cpu.regs[15]);
    cpu = run(&mem, &.{RTI});
    try testing.expectEqual(.rti_outside_isr, cpu.halt_reason);
}

test "missing memory reads 0 and ignores writes (§8.2)" {
    var mem: [0x10]u32 = undefined;
    const cpu = run(&mem, &.{
        alu_iw(.always, MOVE, .none, imm(0), imm(0), reg(0)), 0x1000, 5, // MOVE 0x1000, 5
        alu_iw(.always, MOVE, .none, reg(1), ind_imm(0), reg(0)), 0x1000, // MOVE R1, @0x1000
        HALT,
    });
    try testing.expectEqual(0, cpu.getReg(1));
}
