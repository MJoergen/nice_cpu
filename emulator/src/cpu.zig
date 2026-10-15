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

/// The full 2³² words of memory (§1.1), held sparsely: a page is allocated
/// on its first write of a nonzero word, and a word never written reads 0.
pub const Memory = struct {
    const page_bits = 12;
    const Page = [1 << page_bits]u32;
    const offset_mask: u32 = (1 << page_bits) - 1;

    gpa: std.mem.Allocator,
    pages: std.AutoHashMapUnmanaged(u20, *Page) = .empty,
    last: ?struct { n: u20, page: *Page } = null,

    pub fn init(gpa: std.mem.Allocator) Memory {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Memory) void {
        var it = self.pages.valueIterator();
        while (it.next()) |page| self.gpa.destroy(page.*);
        self.pages.deinit(self.gpa);
    }

    pub fn read(self: *Memory, addr: u32) u32 {
        const page = self.lookup(@truncate(addr >> page_bits)) orelse return 0;
        return page[addr & offset_mask];
    }

    /// `read` without updating the cache, for a `*const Memory`.
    pub fn peek(self: *const Memory, addr: u32) u32 {
        const page = self.pages.get(@truncate(addr >> page_bits)) orelse return 0;
        return page[addr & offset_mask];
    }

    pub fn write(self: *Memory, addr: u32, value: u32) error{OutOfMemory}!void {
        const n: u20 = @truncate(addr >> page_bits);
        if (self.lookup(n)) |page| {
            page[addr & offset_mask] = value;
        } else if (value != 0) {
            const page = try self.gpa.create(Page);
            errdefer self.gpa.destroy(page);
            try self.pages.put(self.gpa, n, page);
            page.* = @splat(0);
            page[addr & offset_mask] = value;
        }
    }

    /// The page `n`, if it is allocated. Most accesses are to the page of
    /// the one before, so that page is remembered.
    fn lookup(self: *Memory, n: u20) ?*Page {
        if (self.last) |last| {
            if (last.n == n) return last.page;
        }
        const page = self.pages.get(n) orelse return null;
        self.last = .{ .n = n, .page = page };
        return page;
    }
};

pub const Error = std.Io.Writer.Error || error{OutOfMemory};

/// The first address of the I/O range (§8.3).
pub const io_base: u32 = 0xFFFF_FF00;

/// The emulator's console output: the first I/O address (§8.3).
pub const console_addr: u32 = io_base;

/// The emulator's read counter (§8.3): a data read returns the number of
/// data reads of it since the last write, and then counts itself. A write
/// sets the count. It lets tests see the data reads of §8.2.
pub const counter_addr: u32 = io_base + 1;

/// The first of the 32 words of the math unit (§8.4).
pub const mpu_base: u32 = io_base + 0x20;

/// The math unit (§8.4). It computes each result when it is read, so a
/// read never waits.
pub const Mpu = struct {
    a: u32 = 0,
    b: u32 = 0,
    c: u64 = 0,
    d: u64 = 0,

    /// The value a data read of word `i` returns.
    pub fn read(self: Mpu, i: u5) u32 {
        if (i >= 16) {
            const w = self.read64(@truncate(i / 2 - 8));
            return @truncate(if (i % 2 == 0) w else w >> 32);
        }
        const sa: i64 = @as(i32, @bitCast(self.a));
        const sb: i64 = @as(i32, @bitCast(self.b));
        const sp: u64 = @bitCast(sa * sb);
        const up: u64 = @as(u64, self.a) * self.b;
        return switch (i) {
            0 => self.a,
            1 => self.b,
            2 => @truncate(sp),
            3 => @truncate(sp >> 32),
            4 => @truncate(up),
            5 => @truncate(up >> 32),
            6, 7 => {
                // Division by zero, and -2^31 / -1, which overflows.
                if (self.b == 0) return if (i == 6) 0xFFFF_FFFF else self.a;
                if (self.a == 0x8000_0000 and self.b == 0xFFFF_FFFF) return if (i == 6) 0x8000_0000 else 0;
                const a: i32 = @bitCast(self.a);
                const b: i32 = @bitCast(self.b);
                return @bitCast(if (i == 6) @divTrunc(a, b) else @rem(a, b));
            },
            8 => if (self.b == 0) 0xFFFF_FFFF else self.a / self.b,
            9 => if (self.b == 0) self.a else self.a % self.b,
            else => 0,
        };
    }

    /// The 64-bit value of the word pair 16 + 2k, 17 + 2k: C, D, the
    /// signed quotient and remainder, the unsigned ones, and 0 for the
    /// spare pairs.
    fn read64(self: Mpu, k: u3) u64 {
        return switch (k) {
            0 => self.c,
            1 => self.d,
            2, 3 => {
                // Division by zero, and -2^63 / -1, which overflows.
                if (self.d == 0) return if (k == 2) ~@as(u64, 0) else self.c;
                if (self.c == 1 << 63 and self.d == ~@as(u64, 0)) return if (k == 2) 1 << 63 else 0;
                const c: i64 = @bitCast(self.c);
                const d: i64 = @bitCast(self.d);
                return @bitCast(if (k == 2) @divTrunc(c, d) else @rem(c, d));
            },
            4 => if (self.d == 0) ~@as(u64, 0) else self.c / self.d,
            5 => if (self.d == 0) self.c else self.c % self.d,
            else => 0,
        };
    }

    /// A write of `value` to word `i`. Only the operands can be written.
    pub fn write(self: *Mpu, i: u5, value: u32) void {
        const lo: u64 = value;
        const hi: u64 = lo << 32;
        switch (i) {
            0 => self.a = value,
            1 => self.b = value,
            16 => self.c = (self.c & 0xFFFF_FFFF_0000_0000) | lo,
            17 => self.c = (self.c & 0xFFFF_FFFF) | hi,
            18 => self.d = (self.d & 0xFFFF_FFFF_0000_0000) | lo,
            19 => self.d = (self.d & 0xFFFF_FFFF) | hi,
            else => {},
        }
    }
};

/// The word of the math unit that `addr` names, if it names one.
fn mpuWord(addr: u32) ?u5 {
    return if (addr -% mpu_base < 32) @truncate(addr -% mpu_base) else null;
}

/// The first of the 16 words of the performance counters (§8.5).
pub const perf_base: u32 = io_base + 0x10;

/// The performance counters (§8.5). Each 64-bit counter has a snapshot,
/// which a read of its low word fills and a read of its high word returns.
pub const Perf = struct {
    /// One per step: per instruction and per interrupt entry. The emulator
    /// has no clock, so this stands in for the clock cycles.
    cycles: u64 = 0,
    cycles_snap: u64 = 0,
    instrs: u64 = 0,
    instrs_snap: u64 = 0,

    /// The value a data read of word `i` returns, with its side effect.
    pub fn read(self: *Perf, i: u4) u32 {
        switch (i) {
            0 => self.cycles_snap = self.cycles,
            2 => self.instrs_snap = self.instrs,
            else => {},
        }
        return self.peek(i);
    }

    /// The value of word `i`, without the side effect of a read.
    pub fn peek(self: Perf, i: u4) u32 {
        return switch (i) {
            0 => @truncate(self.cycles),
            1 => @truncate(self.cycles_snap >> 32),
            2 => @truncate(self.instrs),
            3 => @truncate(self.instrs_snap >> 32),
            else => 0,
        };
    }
};

/// The word of the performance counters that `addr` names, if it names one.
fn perfWord(addr: u32) ?u4 {
    return if (addr -% perf_base < 16) @truncate(addr -% perf_base) else null;
}

/// The words of the cycle counter, `CYCLE_LO` and `CYCLE_HI`.
const cycle_words = 2;

pub const Cpu = struct {
    /// R0..R15. Read and write them through `getReg` and `setReg`, which
    /// apply the rules for R0 and R14 (§4.3).
    regs: [16]u32,
    mem: Memory,

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
    /// The read counter at `counter_addr`.
    read_count: u32,
    /// When set, a write to `console_addr` writes its low byte here
    /// instead of to memory. This device belongs to the emulator, not to
    /// the ISA (§8.3).
    console: ?*std.Io.Writer,
    /// The math unit at `mpu_base`.
    mpu: Mpu,
    /// The performance counters at `perf_base`.
    perf: Perf,
    /// When false, `CYCLE_LO` and `CYCLE_HI` are ordinary memory
    /// (`--no-cycle-counter`). The emulator counts steps where an FPGA core
    /// counts clock cycles, so a comparison of their traces must leave the
    /// cycle counter out. The instruction counter stays.
    cycle_counter: bool,

    /// A processor after reset (§8.1), with empty memory allocated from `gpa`.
    pub fn init(gpa: std.mem.Allocator) Cpu {
        var cpu: Cpu = .{
            .regs = undefined,
            .mem = .init(gpa),
            .in_service = false,
            .after_rti = false,
            .saved_pc = 0,
            .saved_sr = 0,
            .halt_reason = .none,
            .nmi_pending = null,
            .irq_pending = null,
            .trace = null,
            .last_write = null,
            .read_count = 0,
            .console = null,
            .mpu = .{},
            .perf = .{},
            .cycle_counter = true,
        };
        cpu.reset();
        return cpu;
    }

    pub fn deinit(self: *Cpu) void {
        self.mem.deinit();
    }

    pub fn reset(self: *Cpu) void {
        self.regs = @splat(0);
        self.regs[14] = one_bit;
        self.in_service = false;
        self.after_rti = false;
        self.halt_reason = .none;
        self.nmi_pending = null;
        self.irq_pending = null;
        self.mpu = .{};
        self.perf = .{};
    }

    pub fn halted(self: *const Cpu) bool {
        return self.halt_reason != .none;
    }

    /// Raise the maskable interrupt request with vector `v`. Requests that
    /// arrive while one is pending merge into one (§7.1).
    pub fn requestIrq(self: *Cpu, v: u8) void {
        self.irq_pending = v;
    }

    /// Raise the non-maskable interrupt request with vector `v`. Requests
    /// that arrive while one is pending merge into one (§7.1).
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

    /// A data read by the processor (§8.2).
    pub fn read(self: *Cpu, addr: u32) u32 {
        if (addr == counter_addr) {
            const n = self.read_count;
            self.read_count +%= 1;
            return n;
        }
        if (mpuWord(addr)) |i| return self.mpu.read(i);
        if (self.perfDevice(addr)) |i| return self.perf.read(i);
        return self.mem.read(addr);
    }

    /// The word of the performance counters that `addr` names, if it names
    /// one that is a device: not a word of the cycle counter when that is
    /// switched off.
    fn perfDevice(self: *const Cpu, addr: u32) ?u4 {
        const i = perfWord(addr) orelse return null;
        return if (self.cycle_counter or i >= cycle_words) i else null;
    }

    /// A look at memory from outside the processor, for dumps and tests.
    /// Unlike `read`, it is not an access in the sense of §8.2, so once
    /// devices are mapped it must not trigger their side effects.
    pub fn peek(self: *const Cpu, addr: u32) u32 {
        if (addr == counter_addr) return self.read_count;
        if (mpuWord(addr)) |i| return self.mpu.read(i);
        if (self.perfDevice(addr)) |i| return self.perf.peek(i);
        return self.mem.peek(addr);
    }

    /// A memory write by the processor (§8.2).
    pub fn write(self: *Cpu, addr: u32, value: u32) Error!void {
        if (addr == console_addr) {
            if (self.console) |w| try w.writeByte(@truncate(value));
        }
        if (addr == counter_addr) {
            self.read_count = value;
        } else if (mpuWord(addr)) |i| {
            self.mpu.write(i, value);
        } else if (self.perfDevice(addr) != null) {
            // The counters cannot be written (§8.5).
        } else if (addr != console_addr or self.console == null) {
            try self.mem.write(addr, value);
        }
        self.last_write = .{ .addr = addr, .value = value };
    }

    fn flag(self: *const Cpu, bit: u5) u1 {
        return @truncate(self.getReg(14) >> bit);
    }

    /// Take a pending interrupt if one may be taken, or else run one
    /// instruction. Does nothing once the processor has halted. Each step
    /// counts as one cycle (§8.5).
    pub fn step(self: *Cpu) Error!void {
        if (self.halted()) return;
        defer self.perf.cycles +%= 1;
        const before = self.regs;
        self.last_write = null;

        // §7.1: interrupts are checked before each instruction.
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
        const pc = self.regs[15];
        const ex = try self.execute();
        self.perf.instrs +%= 1;
        if (self.trace) |w| try self.traceInstruction(w, pc, ex.iw, ex.executed, before);
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

    /// Fetch and run one instruction (§5). Returns the instruction word, so
    /// that the trace need not read it a second time, and whether the
    /// condition was true.
    fn execute(self: *Cpu) Error!struct { iw: u32, executed: bool } {
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
        if (self.flag(@as(u5, sr_one) + sel) ^ neg == 0) return .{ .iw = iw, .executed = false };

        // 4. Control.
        if (class == 0b11) {
            self.control(iw);
            return .{ .iw = iw, .executed = true };
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
        try self.destination(fields[0], consts[0], res.r);

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
        return .{ .iw = iw, .executed = true };
    }

    /// An instruction fetch (§8.2). It never reaches the I/O range, where
    /// it reads 0 (§8.3).
    fn fetch(self: *Cpu) u32 {
        const pc = self.regs[15];
        const word = if (pc >= io_base) 0 else self.mem.read(pc);
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
    fn destination(self: *Cpu, field: u7, c: u32, res: u32) Error!void {
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
            0b011, 0b111 => try self.write(self.getReg(r) +% c, res),
            0b100 => try self.write(self.getReg(r), res),
            0b101 => {
                self.setReg(r, self.getReg(r) -% 1);
                try self.write(self.getReg(r), res);
            },
            0b110 => {
                try self.write(self.getReg(r), res);
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

    fn traceInterrupt(self: *const Cpu, kind: []const u8, v: u8, before: [16]u32) std.Io.Writer.Error!void {
        const w = self.trace orelse return;
        // Padded to the width of "pppppppp iiiiiiii", so that the changes
        // line up with those of the instruction lines.
        try w.print("{s} {x:0>2}           ", .{ kind, v });
        try self.traceChanges(w, before, null);
    }

    fn traceInstruction(self: *const Cpu, w: *std.Io.Writer, pc: u32, iw: u32, executed: bool, before: [16]u32) std.Io.Writer.Error!void {
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

    fn traceChanges(self: *const Cpu, w: *std.Io.Writer, before: [16]u32, next_pc: ?u32) std.Io.Writer.Error!void {
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
const Cond = enum(u4) { always, x, c, z, n, v, e, i, never, nx, nc, nz, nn, nv, ne, ni };

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
fn postdec(r: u4) u7 {
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
const NOR = 0b0111;
const IAND = 0b1000;
const NAND = 0b1001;
const XOR = 0b1010;
const IOR = 0b1011;
const XNOR = 0b1100;
const AND = 0b1101;
const ONE = 0b1110;
const OR = 0b1111;
const HALT = 0x0C00_0000;
const RTI = 0x0C20_0000;
const INT = 0x0C40_0000;

/// A processor with `words` loaded at `addr`.
fn load(cpu: *Cpu, addr: u32, words: []const u32) !void {
    for (words, 0..) |w, i| try cpu.mem.write(addr +% @as(u32, @intCast(i)), w);
}

fn runToHalt(cpu: *Cpu) !void {
    var steps: usize = 0;
    while (!cpu.halted()) : (steps += 1) {
        if (steps == 10_000) @panic("program did not halt");
        try cpu.step();
    }
}

/// Load `program` at address 0 and run it until it halts. The caller
/// deinits the result.
fn run(program: []const u32) !Cpu {
    var cpu = Cpu.init(testing.allocator);
    errdefer cpu.deinit();
    try load(&cpu, 0, program);
    try runToHalt(&cpu);
    return cpu;
}

fn flags(cpu: *const Cpu) u32 {
    return cpu.getReg(14) & flag_mask;
}

test "source order of §5: MOVE @R1, R1++" {
    // MOVE R1, 0x40;  MOVE @R1, R1++;  HALT
    var cpu = try run(&.{
        alu_iw(.always, MOVE, .none, reg(1), imm(0), reg(0)), 0x40, // MOVE R1, 0x40
        alu_iw(.always, MOVE, .none, ind(1), postinc(1), reg(0)), // MOVE @R1, R1++
        HALT,
    });
    defer cpu.deinit();
    try testing.expectEqual(0x40, cpu.peek(0x41));
    try testing.expectEqual(0x41, cpu.getReg(1));
}

test "worked example of §11" {
    const iw = 0xB278C971;
    try testing.expectEqual(iw, alu_iw(.nz, ADD, .m, ind_postinc(3), predec(2), ind_imm(1)));
    // ?!Z ADD[M] @R3++, --R2, @0x12345678[R1], with R1 chosen so that the
    // operand address wraps to 0x60.
    var cpu = Cpu.init(testing.allocator);
    defer cpu.deinit();
    try load(&cpu, 0, &.{
        alu_iw(.always, MOVE, .none, reg(1), imm(0), reg(0)), @as(u32, 0x60) -% 0x12345678,
        alu_iw(.always, MOVE, .none, reg(2), imm(0), reg(0)), 5,
        alu_iw(.always, MOVE, .none, reg(3), imm(0), reg(0)), 0x80,
        iw,                                                   0x12345678,
        HALT,
    });
    try load(&cpu, 0x60, &.{10});
    try runToHalt(&cpu);
    try testing.expectEqual(4, cpu.getReg(2));
    try testing.expectEqual(14, cpu.peek(0x80));
    try testing.expectEqual(0x81, cpu.getReg(3));
    try testing.expectEqual(0, flags(&cpu));
}

test "R14 bit 24 and MOVE R1, --R14 (§4.3)" {
    var cpu = try run(&.{ alu_iw(.always, MOVE, .none, reg(1), predec(14), reg(0)), HALT });
    defer cpu.deinit();
    try testing.expectEqual(0x01FF_FFFF, cpu.getReg(1));
    try testing.expectEqual(0x01FF_FFFF, cpu.getReg(14));
}

test "MOVE R14--, 0: both writes set bit 24 (§4.2)" {
    var cpu = try run(&.{ alu_iw(.always, MOVE, .none, postdec(14), reg(0), reg(0)), HALT });
    defer cpu.deinit();
    try testing.expectEqual(0x01FF_FFFF, cpu.getReg(14));
}

test "R0 reads 0 in every mode (§4.3)" {
    // MOVE R1, --R0;  MOVE R2, @--R0  (reads word 0)
    var cpu = try run(&.{
        alu_iw(.always, MOVE, .none, reg(1), predec(0), reg(0)),
        alu_iw(.always, MOVE, .none, reg(2), ind_predec(0), reg(0)),
        HALT,
    });
    defer cpu.deinit();
    try testing.expectEqual(0, cpu.getReg(1));
    try testing.expectEqual(cpu.peek(0), cpu.getReg(2));
    try testing.expectEqual(0, cpu.getReg(0));
}

test "R15 reads as the next instruction; call and return (§9.1)" {
    // 0: MOVE R13, 0x80         ; SP
    // 2: ADD @--R13, 2, R15     ; push return address 6
    // 4: MOVE R15, 8            ; call
    // 6: HALT
    // 7: (unused)
    // 8: MOVE R1, 7
    // 10: MOVE R15, @R13++      ; return
    var cpu = try run(&.{
        alu_iw(.always, MOVE, .none, reg(13), imm(0), reg(0)), 0x80, // 0
        alu_iw(.always, ADD, .none, ind_predec(13), imm(0), reg(15)), 2, // 2
        alu_iw(.always, MOVE, .none, reg(15), imm(0), reg(0)), 8, // 4
        HALT, // 6
        0, // 7
        alu_iw(.always, MOVE, .none, reg(1), imm(0), reg(0)), 7, // 8
        alu_iw(.always, MOVE, .none, reg(15), ind_postinc(13), reg(0)), // 10
    });
    defer cpu.deinit();
    try testing.expectEqual(7, cpu.getReg(1));
    try testing.expectEqual(0x80, cpu.getReg(13));
    try testing.expectEqual(6, cpu.peek(0x7F));
    try testing.expectEqual(7, cpu.getReg(15));
}

test "skipped instruction consumes constants and has no effect (§3)" {
    // ?Z MOVE @0x50, R2++, @R3++  is skipped: Z = 0 after reset.
    var cpu = try run(&.{
        alu_iw(.z, MOVE, .none, imm(0), postinc(2), ind_postinc(3)), 0x50, // ?Z MOVE 0x50, R2++, @R3++
        alu_iw(.nz, MOVE, .none, reg(4), imm(0), reg(0)), 9, // ?!Z MOVE R4, 9
        HALT,
    });
    defer cpu.deinit();
    try testing.expectEqual(0, cpu.getReg(2));
    try testing.expectEqual(0, cpu.getReg(3));
    try testing.expectEqual(9, cpu.getReg(4));
    try testing.expectEqual(0, cpu.peek(0x50));
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
    // DEC and MOVE ignore the carry input.
    try testing.expectEqual(Result{ .r = 4 }, alu(DEC, 5, 0, 1));
    try testing.expectEqual(Result{ .r = 5 }, alu(MOVE, 5, 0, 1));
}

test "logic operations (§5.1)" {
    const a = 0xF0F0_F0F0;
    const b = 0xFF00_FF00;
    try testing.expectEqual(0x0F0F_0F0F, alu(NOT, a, b, 1).r);
    try testing.expectEqual(0x000F_000F, alu(NOR, a, b, 1).r);
    try testing.expectEqual(0x0F00_0F00, alu(IAND, a, b, 1).r);
    try testing.expectEqual(0x0FFF_0FFF, alu(NAND, a, b, 1).r);
    try testing.expectEqual(0x0FF0_0FF0, alu(XOR, a, b, 1).r);
    try testing.expectEqual(0xFF0F_FF0F, alu(IOR, a, b, 1).r);
    try testing.expectEqual(0xF00F_F00F, alu(XNOR, a, b, 1).r);
    try testing.expectEqual(0xF000_F000, alu(AND, a, b, 1).r);
    try testing.expectEqual(0xFFF0_FFF0, alu(OR, a, b, 1).r);
}

test "flags with M (§6)" {
    // MOVE R1, 0xFFFFFFFF; ADD[M] R2, R1, 1 -> Z, C;  then ADD[CM] R3, R0, R0 -> 1
    var cpu = try run(&.{
        alu_iw(.always, MOVE, .none, reg(1), imm(0), reg(0)), 0xFFFF_FFFF, // MOVE R1, -1
        alu_iw(.always, ADD, .m, reg(2), reg(1), imm(0)), 1, // ADD[M] R2, R1, 1
        alu_iw(.always, ADD, .cm, reg(3), reg(0), reg(0)), // ADD[CM] R3, R0, R0
        HALT,
    });
    try testing.expectEqual(1, cpu.getReg(3));
    try testing.expectEqual(0, flags(&cpu));
    cpu.deinit();

    // MOVE[M] R1, -1 sets X and N; logic ops clear C.
    cpu = try run(&.{ alu_iw(.always, MOVE, .m, reg(1), imm(0), reg(0)), 0xFFFF_FFFF, HALT });
    try testing.expectEqual(1 << sr_x | 1 << sr_n, flags(&cpu));
    cpu.deinit();

    // Flags come from r, not from the value an Rx++ destination stores.
    cpu = try run(&.{ alu_iw(.always, MOVE, .m, postinc(1), reg(0), reg(0)), HALT });
    defer cpu.deinit();
    try testing.expectEqual(1, cpu.getReg(1));
    try testing.expectEqual(1 << sr_z, flags(&cpu));
}

test "explicit write to R14 beats the flag update (§6)" {
    var cpu = try run(&.{ alu_iw(.always, OR, .m, reg(14), reg(14), imm(0)), 0x4000_0000, HALT });
    defer cpu.deinit();
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
    try testing.expectEqual(Result{ .r = 0x3000_0000, .c = 0 }, shift(0b1101, 0x8000_0000, 0xFFFF_FFFF, 1));
    // 0<C fills with the original C every step.
    try testing.expectEqual(Result{ .r = 0xF }, shift(0b0010, 0, 4, 1));
}

test "shifts write C only with M (§5.2)" {
    // C<1 R1, R2, 1 with R2 = 0x80000000, without and with M.
    var cpu = try run(&.{
        alu_iw(.always, MOVE, .none, reg(2), imm(0), reg(0)), 0x8000_0000, // MOVE R2, 0x80000000
        shift_iw(0b0100, false, reg(1), reg(2), imm(0)), 1, // C<1 R1, R2, 1
        HALT,
    });
    try testing.expectEqual(1, cpu.getReg(1));
    try testing.expectEqual(0, flags(&cpu));
    cpu.deinit();
    cpu = try run(&.{
        alu_iw(.always, MOVE, .none, reg(2), imm(0), reg(0)), 0x8000_0000, // MOVE R2, 0x80000000
        shift_iw(0b0100, true, reg(1), reg(2), imm(0)), 1, // C<1[M] R1, R2, 1
        HALT,
    });
    defer cpu.deinit();
    try testing.expectEqual(1 << sr_c, flags(&cpu));
}

test "INT and RTI (§7)" {
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
    var cpu = try run(&program);
    defer cpu.deinit();
    try testing.expectEqual(.halt, cpu.halt_reason);
    try testing.expectEqual(program[0], cpu.getReg(2));
    // Inside the routine I was set; RTI restored SR.
    try testing.expectEqual(0x8100_0000, cpu.getReg(3));
    try testing.expectEqual(0x0100_0000, cpu.getReg(14));
    try testing.expectEqual(false, cpu.in_service);
}

/// A processor with NOPs from address 0, vector 5 pointing at an RTI at
/// 0x40 and vector 6 at an RTI at 0x50.
fn interruptTestCpu() !Cpu {
    var cpu = Cpu.init(testing.allocator);
    errdefer cpu.deinit();
    try load(&cpu, 5, &.{ 0x40, 0x50 });
    try load(&cpu, 0x40, &.{RTI});
    try load(&cpu, 0x50, &.{RTI});
    return cpu;
}

test "IRQ needs E, NMI does not (§7.1)" {
    var cpu = try interruptTestCpu();
    defer cpu.deinit();

    cpu.requestIrq(5);
    try cpu.step(); // E = 0: a NOP at address 0 runs instead
    try testing.expectEqual(1, cpu.regs[15]);
    try testing.expect(cpu.irq_pending != null);

    cpu.requestNmi(6);
    try cpu.step(); // NMI entry
    try testing.expectEqual(0x50, cpu.regs[15]);
    try testing.expectEqual(1, cpu.saved_pc);
    try testing.expectEqual(0x8100_0000, cpu.getReg(14));
}

test "no interrupt right after RTI, and RTI restores E (§7.1, §7.4)" {
    var cpu = try interruptTestCpu();
    defer cpu.deinit();

    cpu.setReg(14, 1 << sr_e);
    cpu.requestNmi(6);
    try cpu.step(); // NMI entry, saving E = 1
    cpu.setReg(14, cpu.getReg(14) & ~@as(u32, 1 << sr_e));
    cpu.requestIrq(5);
    try cpu.step(); // RTI
    try testing.expectEqual(0, cpu.regs[15]);
    try testing.expectEqual(0x4100_0000, cpu.getReg(14));
    try cpu.step(); // after_rti: the NOP at 0 runs first
    try testing.expectEqual(1, cpu.regs[15]);
    try cpu.step(); // now the IRQ
    try testing.expectEqual(0x40, cpu.regs[15]);
    try testing.expectEqual(1, cpu.saved_pc);
    try testing.expectEqual(null, cpu.irq_pending);
}

test "NMI before IRQ; the IRQ waits through the routine (§7.1)" {
    var cpu = try interruptTestCpu();
    defer cpu.deinit();

    cpu.setReg(14, 1 << sr_e);
    cpu.requestIrq(5);
    cpu.requestNmi(6);
    try cpu.step(); // the NMI
    try testing.expectEqual(0x50, cpu.regs[15]);
    try testing.expect(cpu.irq_pending != null);
    try cpu.step(); // RTI, although the IRQ is pending
    try testing.expectEqual(0, cpu.regs[15]);
    try cpu.step(); // the NOP at 0
    try cpu.step(); // the IRQ
    try testing.expectEqual(0x40, cpu.regs[15]);
    try testing.expectEqual(1, cpu.saved_pc);
}

test "HALT inside an interrupt routine, and INT inside one (§7.2)" {
    // 0: INT 2;  2: .DAT 3 (vector 2);  3: HALT
    var cpu = try run(&.{ INT + 2, 0, 3, HALT });
    try testing.expectEqual(.halt, cpu.halt_reason);
    try testing.expect(cpu.in_service);
    cpu.deinit();
    // 0: INT 2;  2: .DAT 3;  3: INT 2
    cpu = try run(&.{ INT + 2, 0, 3, INT + 2 });
    defer cpu.deinit();
    try testing.expectEqual(.nested_int, cpu.halt_reason);
}

test "VBASE selects the vector table (§7.3)" {
    // 0: MOVE R14, 1  (VBASE = 1: the table is at 0x100);  2: INT 2;  3: HALT
    // 0x10: HALT;  0x102: .DAT 0x10
    var cpu = Cpu.init(testing.allocator);
    defer cpu.deinit();
    try load(&cpu, 0, &.{ alu_iw(.always, MOVE, .none, reg(14), imm(0), reg(0)), 1, INT + 2, HALT });
    try load(&cpu, 0x10, &.{HALT});
    try load(&cpu, 0x102, &.{0x10});
    try runToHalt(&cpu);
    try testing.expectEqual(0x11, cpu.regs[15]);
    try testing.expectEqual(0x8100_0001, cpu.getReg(14));
}

test "reserved control words halt, unless skipped (§5.3)" {
    var cpu = try run(&.{ 0x0C00_0001, HALT });
    try testing.expectEqual(.reserved, cpu.halt_reason);
    cpu.deinit();
    cpu = try run(&.{ 0x8C60_0000, HALT }); // never-executed command 3
    try testing.expectEqual(.halt, cpu.halt_reason);
    try testing.expectEqual(2, cpu.regs[15]);
    cpu.deinit();
    cpu = try run(&.{RTI});
    defer cpu.deinit();
    try testing.expectEqual(.rti_outside_isr, cpu.halt_reason);
}

test "the whole address space exists and wraps (§1.1)" {
    // MOVE @1[R1], 5 with R1 = 0xFFFFFFFF writes address 0, which held the
    // instruction word; then HALT at 3.
    var cpu = Cpu.init(testing.allocator);
    defer cpu.deinit();
    try load(&cpu, 0, &.{ alu_iw(.always, MOVE, .none, ind_imm(1), imm(0), reg(0)), 1, 5, HALT });
    try load(&cpu, 0xFFFF_FFFF, &.{7});
    cpu.regs[1] = 0xFFFF_FFFF;
    try runToHalt(&cpu);
    try testing.expectEqual(5, cpu.peek(0));
    try testing.expectEqual(7, cpu.peek(0xFFFF_FFFF));
    try testing.expectEqual(4, cpu.regs[15]);
    // Writing 0 to an untouched page allocates nothing.
    try cpu.mem.write(0x8000_0000, 0);
    try testing.expectEqual(2, cpu.mem.pages.count());
}

test "the console takes the low byte of a write, and memory keeps nothing" {
    // MOVE @0xFFFFFF00, 0x1234_5648 ("H"), MOVE @0xFFFFFF00, 0x69 ("i"),
    // MOVE R1, @0xFFFFFF00, HALT.
    var cpu = Cpu.init(testing.allocator);
    defer cpu.deinit();
    try load(&cpu, 0, &.{
        alu_iw(.always, MOVE, .none, imm(0), imm(0), reg(0)), console_addr, 0x1234_5648,
        alu_iw(.always, MOVE, .none, imm(0), imm(0), reg(0)), console_addr, 0x69,
        alu_iw(.always, MOVE, .none, reg(1), ind_imm(0), reg(0)), console_addr,
        HALT,
    });
    var buf: [8]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    cpu.console = &w;
    cpu.regs[1] = 7;
    try runToHalt(&cpu);
    try testing.expectEqualStrings("Hi", w.buffered());
    try testing.expectEqual(0, cpu.regs[1]);
    try testing.expectEqual(1, cpu.mem.pages.count()); // only the program's page
}

test "the read counter counts data reads, and a write sets it" {
    // MOVE @0xFFFFFF01, 5;  ADD R1, @0xFFFFFF01, @0xFFFFFF01;  HALT
    var cpu = Cpu.init(testing.allocator);
    defer cpu.deinit();
    try load(&cpu, 0, &.{
        alu_iw(.always, MOVE, .none, imm(0), imm(0), reg(0)), counter_addr, 5,
        alu_iw(.always, ADD, .none, reg(1), ind_imm(0), ind_imm(0)), counter_addr, counter_addr,
        HALT,
    });
    try runToHalt(&cpu);
    try testing.expectEqual(5 + 6, cpu.regs[1]);
    try testing.expectEqual(7, cpu.peek(counter_addr));
    try testing.expectEqual(7, cpu.read_count);
}

test "the math unit's results, with division by zero and overflow (§8.4)" {
    // A, B, then SMUL_LO, SMUL_HI, UMUL_LO, UMUL_HI, SDIV_Q, SDIV_R, UDIV_Q, UDIV_R.
    const cases = [_][10]u32{
        .{ 7, 3, 21, 0, 21, 0, 2, 1, 2, 1 },
        // -7 * 2 = -14; 0xFFFFFFF9 * 2 = 0x1_FFFFFFF2; -7 / 2 = -3 rem -1.
        .{ 0xFFFF_FFF9, 2, 0xFFFF_FFF2, 0xFFFF_FFFF, 0xFFFF_FFF2, 1, 0xFFFF_FFFD, 0xFFFF_FFFF, 0x7FFF_FFFC, 1 },
        // -1 * -1 = 1; 0xFFFFFFFF^2 = 0xFFFFFFFE_00000001.
        .{ 0xFFFF_FFFF, 0xFFFF_FFFF, 1, 0, 1, 0xFFFF_FFFE, 1, 0, 1, 0 },
        // -2^31 * -1 = 2^31; 2^31 * (2^32 - 1) = 0x7FFFFFFF_80000000; -2^31 / -1 overflows.
        .{ 0x8000_0000, 0xFFFF_FFFF, 0x8000_0000, 0, 0x8000_0000, 0x7FFF_FFFF, 0x8000_0000, 0, 0, 0x8000_0000 },
        // -5 / 0 and 0xFFFFFFFB / 0.
        .{ 0xFFFF_FFFB, 0, 0, 0, 0, 0, 0xFFFF_FFFF, 0xFFFF_FFFB, 0xFFFF_FFFF, 0xFFFF_FFFB },
    };
    for (cases) |c| {
        const mpu: Mpu = .{ .a = c[0], .b = c[1] };
        for (0..10) |i| try testing.expectEqual(c[i], mpu.read(@intCast(i)));
        for (10..16) |i| try testing.expectEqual(0, mpu.read(@intCast(i)));
    }
}

test "the math unit's 64-bit division, with division by zero and overflow (§8.4)" {
    // C, D, then the signed quotient and remainder, and the unsigned ones.
    const cases = [_][6]u64{
        .{ 100, 7, 14, 2, 14, 2 },
        // -7 / 2 = -3 rem -1; 2^64 - 7 = 2 * 0x7FFFFFFF_FFFFFFFC + 1.
        .{ 0xFFFF_FFFF_FFFF_FFF9, 2, 0xFFFF_FFFF_FFFF_FFFD, 0xFFFF_FFFF_FFFF_FFFF, 0x7FFF_FFFF_FFFF_FFFC, 1 },
        // -2^63 / -1 overflows; unsigned, 2^63 / (2^64 - 1) = 0 rem 2^63.
        .{ 1 << 63, 0xFFFF_FFFF_FFFF_FFFF, 1 << 63, 0, 0, 1 << 63 },
        // -5 / 0.
        .{ 0xFFFF_FFFF_FFFF_FFFB, 0, 0xFFFF_FFFF_FFFF_FFFF, 0xFFFF_FFFF_FFFF_FFFB, 0xFFFF_FFFF_FFFF_FFFF, 0xFFFF_FFFF_FFFF_FFFB },
        // 2^40 + 3 = 2^20 * 2^20 + 3.
        .{ (1 << 40) + 3, 1 << 20, 1 << 20, 3, 1 << 20, 3 },
    };
    for (cases) |c| {
        var mpu: Mpu = .{};
        mpu.write(16, @truncate(c[0]));
        mpu.write(17, @truncate(c[0] >> 32));
        mpu.write(18, @truncate(c[1]));
        mpu.write(19, @truncate(c[1] >> 32));
        for (0..6) |k| {
            try testing.expectEqual(@as(u32, @truncate(c[k])), mpu.read(@intCast(16 + 2 * k)));
            try testing.expectEqual(@as(u32, @truncate(c[k] >> 32)), mpu.read(@intCast(17 + 2 * k)));
        }
        for (28..32) |i| try testing.expectEqual(0, mpu.read(@intCast(i)));
    }
}

test "the math unit takes writes to A and B only, and memory keeps nothing" {
    // MOVE @A, 6;  MOVE @B, 7;  MOVE @UMUL_LO, 5;  MOVE R1, @UMUL_LO;  HALT
    var cpu = Cpu.init(testing.allocator);
    defer cpu.deinit();
    try load(&cpu, 0, &.{
        alu_iw(.always, MOVE, .none, imm(0), imm(0), reg(0)), mpu_base, 6,
        alu_iw(.always, MOVE, .none, imm(0), imm(0), reg(0)), mpu_base + 1, 7,
        alu_iw(.always, MOVE, .none, imm(0), imm(0), reg(0)), mpu_base + 4, 5,
        alu_iw(.always, MOVE, .none, reg(1), ind_imm(0), reg(0)), mpu_base + 4,
        HALT,
    });
    try runToHalt(&cpu);
    try testing.expectEqual(42, cpu.regs[1]);
    try testing.expectEqual(42, cpu.peek(mpu_base + 4));
    try testing.expectEqual(1, cpu.mem.pages.count()); // only the program's page
    cpu.reset();
    try testing.expectEqual(0, cpu.peek(mpu_base));
}

test "a read of a counter's low word keeps its high word for the next read (§8.5)" {
    var perf: Perf = .{ .instrs = 0xFFFF_FFFF, .cycles = 0x1_2345_6789 };
    try testing.expectEqual(0xFFFF_FFFF, perf.read(2));
    perf.instrs += 1; // the low word wraps between the two reads
    try testing.expectEqual(0, perf.read(3)); // the snapshot, not the counter
    try testing.expectEqual(0, perf.read(2));
    try testing.expectEqual(1, perf.read(3));
    // The cycle counter has a snapshot of its own, still 0.
    try testing.expectEqual(0, perf.read(1));
    try testing.expectEqual(0x2345_6789, perf.read(0));
    try testing.expectEqual(1, perf.read(1));
    try testing.expectEqual(0, perf.read(4));
    try testing.expectEqual(0, perf.read(15));
    // peek leaves the snapshots alone.
    perf.cycles = 0x5_0000_0000;
    try testing.expectEqual(0, perf.peek(0));
    try testing.expectEqual(1, perf.peek(1));
}

test "the counters count instructions and steps, and ignore writes (§8.5)" {
    // 0:  MOVE R1, @INSTR_LO    0 instructions before it
    // 2:  ?Z MOVE R2, 7         skipped, but counts
    // 4:  MOVE R2, @INSTR_LO    2
    // 6:  MOVE R3, @CYCLE_LO    3 steps before it
    //     NMI with vector 13, which holds 8: a step, not an instruction
    // 8:  MOVE R4, @INSTR_LO    4
    // 10: MOVE R5, @CYCLE_LO    6 steps: 5 instructions and the NMI
    // 12: HALT                  the 7th instruction and the 8th step
    var cpu = Cpu.init(testing.allocator);
    defer cpu.deinit();
    try load(&cpu, 0, &.{
        alu_iw(.always, MOVE, .none, reg(1), ind_imm(0), reg(0)), perf_base + 2,
        alu_iw(.z, MOVE, .none, reg(2), imm(0), reg(0)), 7,
        alu_iw(.always, MOVE, .none, reg(2), ind_imm(0), reg(0)), perf_base + 2,
        alu_iw(.always, MOVE, .none, reg(3), ind_imm(0), reg(0)), perf_base,
        alu_iw(.always, MOVE, .none, reg(4), ind_imm(0), reg(0)), perf_base + 2,
        alu_iw(.always, MOVE, .none, reg(5), ind_imm(0), reg(0)), perf_base,
        HALT,
        8, // the NMI's vector table entry, at 13
    });
    for (0..4) |_| try cpu.step();
    cpu.requestNmi(13);
    try runToHalt(&cpu);
    try testing.expectEqual([5]u32{ 0, 2, 3, 4, 6 }, cpu.regs[1..6].*);
    try testing.expectEqual(7, cpu.perf.instrs);
    try testing.expectEqual(8, cpu.perf.cycles);
    try cpu.write(perf_base + 2, 99);
    try cpu.write(perf_base + 3, 99);
    try testing.expectEqual(7, cpu.peek(perf_base + 2));
    try testing.expectEqual(0, cpu.peek(perf_base + 3));
    cpu.reset();
    try testing.expectEqual(Perf{}, cpu.perf);
}

test "without the cycle counter, its two words are memory (--no-cycle-counter)" {
    var cpu = Cpu.init(testing.allocator);
    defer cpu.deinit();
    cpu.cycle_counter = false;
    try cpu.write(perf_base, 5);
    try cpu.write(perf_base + 1, 6);
    try cpu.write(perf_base + 2, 7); // still the instruction counter: ignored
    try testing.expectEqual(5, cpu.read(perf_base));
    try testing.expectEqual(6, cpu.peek(perf_base + 1));
    try testing.expectEqual(0, cpu.read(perf_base + 2));
    try testing.expectEqual(0, cpu.perf.cycles_snap); // no snapshot was taken
    cpu.cycle_counter = true;
    try testing.expectEqual(0, cpu.read(perf_base)); // the counter again, not the memory
}

test "instruction fetches from the I/O range read 0 (§8.3)" {
    // 0xFFFFFEFF: MOVE R1, c, with c at 0xFFFFFF00 holding 7. The constant
    // is fetched from the I/O range, so R1 = 0. Then the words at
    // 0xFFFFFF01 (the read counter) and the HALT at 0xFFFFFF02 are fetched
    // as 0, NOPs, but a data read still sees the HALT.
    var cpu = Cpu.init(testing.allocator);
    defer cpu.deinit();
    try load(&cpu, 0xFFFF_FEFF, &.{ alu_iw(.always, MOVE, .none, reg(1), imm(0), reg(0)), 7, 0, HALT });
    cpu.regs[15] = 0xFFFF_FEFF;
    cpu.regs[1] = 9;
    try cpu.step();
    try testing.expectEqual(0, cpu.regs[1]);
    try testing.expectEqual(0xFFFF_FF01, cpu.regs[15]);
    try cpu.step();
    try cpu.step();
    try testing.expect(!cpu.halted());
    try testing.expectEqual(0xFFFF_FF03, cpu.regs[15]);
    try testing.expectEqual(0, cpu.read_count);
    try testing.expectEqual(HALT, cpu.read(0xFFFF_FF02));
}

/// Run `cpu` for `n` steps, tracing into a buffer, and return the trace.
fn traceSteps(cpu: *Cpu, buf: []u8, n: usize) ![]const u8 {
    var w: std.Io.Writer = .fixed(buf);
    cpu.trace = &w;
    defer cpu.trace = null;
    for (0..n) |_| try cpu.step();
    return w.buffered();
}

test "trace: write, jump, skip and halt" {
    var cpu = Cpu.init(testing.allocator);
    defer cpu.deinit();
    try load(&cpu, 0, &.{
        alu_iw(.always, MOVE, .none, imm(0), imm(0), reg(0)), 0x50, 7, // 0: MOVE @0x50, 7 (mode 011)
        alu_iw(.always, MOVE, .none, reg(15), imm(0), reg(0)), 6, // 3: MOVE R15, 6
        HALT, // 5
        alu_iw(.z, MOVE, .none, reg(1), imm(0), reg(0)), 1, // 6: ?Z MOVE R1, 1
        alu_iw(.always, DEC, .m, reg(2), reg(2), reg(0)), // 8: DEC[M] R2, R2
        HALT, // 9
    });
    var buf: [512]u8 = undefined;
    try testing.expectEqualStrings(
        \\00000000 000c1800 [00000050]=00000007
        \\00000003 0003d800 R15=00000006
        \\00000006 30005800 skipped
        \\00000008 02a08100 R2=ffffffff R14=17000000
        \\00000009 0c000000 HALT
        \\
    , try traceSteps(&cpu, &buf, 5));
}

test "trace: an interrupt line shows no write of the instruction before (§7.2)" {
    var cpu = Cpu.init(testing.allocator);
    defer cpu.deinit();
    try load(&cpu, 0, &.{
        alu_iw(.always, MOVE, .none, imm(0), imm(0), reg(0)), 0x50, 7, // 0: MOVE @0x50, 7
    });
    try load(&cpu, 6, &.{0x40}); // vector 6
    var buf: [512]u8 = undefined;
    try cpu.step();
    cpu.requestNmi(6);
    try testing.expectEqualStrings(
        \\NMI 06            R14=81000000 R15=00000040
        \\
    , try traceSteps(&cpu, &buf, 1));
}
