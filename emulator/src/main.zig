//! niceemu: runs a NICE program in the `.bin` format of doc/ISA.md §10.4.

const std = @import("std");
const Cpu = @import("cpu.zig").Cpu;

const usage =
    \\Usage: niceemu [options] program.bin
    \\
    \\Runs the program from address 0 until it halts, then prints the
    \\registers. A write to 0xFFFFFF00 prints its low byte on stdout. A read
    \\of 0xFFFFFF00 returns the next byte of stdin plus 0x100, or 0x200 after
    \\the end of the input.
    \\The timer is at 0xFFFFFF10-0xFFFFFF1F, the math unit at 0xFFFFFF20-
    \\0xFFFFFF3F, and the performance counters at 0xFFFFFF40-0xFFFFFF7F.
    \\
    \\Options:
    \\  -t, --trace          Print one line per instruction.
    \\  -s, --screen         Print the 80x25 character screen at 0xFFFF0000.
    \\  -2004                Put the screen at 0x400, as the 2004 emulator does.
    \\  -d, --dump ADDR:N    Print N memory words from ADDR. May be repeated.
    \\  -n, --max-steps N    Stop after N steps (default 100000000).
    \\  -i, --input FILE     Read the console input from FILE, or stdin for -.
    \\      --irq STEP:VEC   Raise IRQ with vector VEC before step STEP.
    \\      --nmi STEP:VEC   Raise NMI with vector VEC before step STEP.
    \\                       Both may be repeated. Steps count from 0.
    \\      --no-cycle-counter  Make 0xFFFFFF40 and 0xFFFFFF41 ordinary memory,
    \\                       for comparing traces with an FPGA core.
    \\      --no-timer-irq   The timer counts, but raises no requests, so that
    \\                       --irq can raise them where an FPGA core took them.
    \\  -h, --help           Print this help.
    \\
    \\Numbers may be decimal or 0x hex. Exit status: 0 after HALT, 1 on a
    \\usage, file or memory error, 2 after any other halt, 3 at the step
    \\limit.
    \\
;

/// The character screen (doc/SYSTEM.md §1). Each word holds a character in
/// bits 7..0 and its colour above. The 2004 emulator has it at 0x400.
const screen_base = 0xFFFF0000;
const screen_base_2004 = 0x400;
const screen_width = 80;
const screen_height = 25;

const Dump = struct { addr: u32, len: u32 };

/// An interrupt request raised from the command line, before step `step`.
const Request = struct {
    step: u64,
    kind: enum { irq, nmi },
    vector: u8,

    fn before(_: void, a: Request, b: Request) bool {
        return a.step < b.step;
    }
};

const Options = struct {
    path: []const u8,
    trace: bool = false,
    screen: bool = false,
    screen_base: u32 = screen_base,
    dumps: []const Dump = &.{},
    /// Sorted by step, in command-line order within a step.
    requests: []const Request = &.{},
    max_steps: u64 = 100_000_000,
    cycle_counter: bool = true,
    timer_irq: bool = true,
    /// The console input file, or "-" for stdin.
    input: []const u8 = "-",
    help: bool = false,
};

pub fn main() !void {
    var arena_state: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var out_buf: [64 * 1024]u8 = undefined;
    // Streaming, not positional: when stdout is a file shared with other
    // writers, as in `(niceemu x.bin; echo) > log`, the output must go
    // where the file offset is.
    var out_w = std.fs.File.stdout().writerStreaming(&out_buf);
    const out = &out_w.interface;

    const status = run(arena, out) catch |err| switch (err) {
        error.Usage, error.Load => 1,
        error.OutOfMemory => blk: {
            out.flush() catch {};
            std.debug.print("niceemu: out of memory\n", .{});
            break :blk 1;
        },
        error.WriteFailed => outputFailed(&out_w),
        else => return err,
    };
    out.flush() catch outputFailed(&out_w);
    std.process.exit(status);
}

/// Exit after stdout failed. A closed pipe, as in `niceemu -t x.bin | head`,
/// ends the program quietly with the status of a filter killed by SIGPIPE.
fn outputFailed(out_w: *const std.fs.File.Writer) noreturn {
    const err = out_w.err orelse error.Unexpected;
    if (err == error.BrokenPipe) std.process.exit(128 + 13);
    std.debug.print("niceemu: cannot write the output: {s}\n", .{@errorName(err)});
    std.process.exit(1);
}

fn fail(comptime fmt: []const u8, args: anytype) error{Usage} {
    std.debug.print("niceemu: " ++ fmt ++ "\n", args);
    return error.Usage;
}

/// Parse the value `s` of option `opt`: decimal, or hex after 0x.
fn parseNumber(comptime T: type, opt: []const u8, s: []const u8) !T {
    const hex = std.mem.startsWith(u8, s, "0x") or std.mem.startsWith(u8, s, "0X");
    const base: u8 = if (hex) 16 else 10;
    const digits = if (hex) s[2..] else s;
    // parseInt would also take a sign and underscores.
    if (digits.len == 0) return fail("{s}: bad number '{s}'", .{ opt, s });
    for (digits) |c| {
        _ = std.fmt.charToDigit(c, base) catch return fail("{s}: bad number '{s}'", .{ opt, s });
    }
    return std.fmt.parseInt(T, digits, base) catch |err| switch (err) {
        error.Overflow => fail("{s}: '{s}' is larger than {d}", .{ opt, s, std.math.maxInt(T) }),
        error.InvalidCharacter => unreachable,
    };
}

fn parseArgs(arena: std.mem.Allocator) !Options {
    const args = try std.process.argsAlloc(arena);
    var opts: Options = .{ .path = "" };
    var dumps: std.ArrayList(Dump) = .empty;
    var requests: std.ArrayList(Request) = .empty;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        const takes_value = for ([_][]const u8{ "-d", "--dump", "-n", "--max-steps", "-i", "--input", "--irq", "--nmi" }) |o| {
            if (std.mem.eql(u8, arg, o)) break true;
        } else false;
        const value = if (takes_value) blk: {
            i += 1;
            if (i == args.len) return fail("{s} needs a value", .{arg});
            break :blk args[i];
        } else "";

        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            opts.help = true;
            return opts;
        } else if (std.mem.eql(u8, arg, "-t") or std.mem.eql(u8, arg, "--trace")) {
            opts.trace = true;
        } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--screen")) {
            opts.screen = true;
        } else if (std.mem.eql(u8, arg, "-2004")) {
            opts.screen_base = screen_base_2004;
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--dump")) {
            const colon = std.mem.indexOfScalar(u8, value, ':') orelse
                return fail("{s} wants ADDR:N, not '{s}'", .{ arg, value });
            try dumps.append(arena, .{
                .addr = try parseNumber(u32, arg, value[0..colon]),
                .len = try parseNumber(u32, arg, value[colon + 1 ..]),
            });
        } else if (std.mem.eql(u8, arg, "-n") or std.mem.eql(u8, arg, "--max-steps")) {
            opts.max_steps = try parseNumber(u64, arg, value);
        } else if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--input")) {
            opts.input = value;
        } else if (std.mem.eql(u8, arg, "--irq") or std.mem.eql(u8, arg, "--nmi")) {
            const colon = std.mem.indexOfScalar(u8, value, ':') orelse
                return fail("{s} wants STEP:VEC, not '{s}'", .{ arg, value });
            try requests.append(arena, .{
                .step = try parseNumber(u64, arg, value[0..colon]),
                .kind = if (std.mem.eql(u8, arg, "--irq")) .irq else .nmi,
                .vector = try parseNumber(u8, arg, value[colon + 1 ..]),
            });
        } else if (std.mem.eql(u8, arg, "--no-cycle-counter")) {
            opts.cycle_counter = false;
        } else if (std.mem.eql(u8, arg, "--no-timer-irq")) {
            opts.timer_irq = false;
        } else if (arg.len > 1 and arg[0] == '-') {
            return fail("unknown option '{s}'\n\n{s}", .{ arg, usage });
        } else if (opts.path.len != 0) {
            return fail("more than one program given", .{});
        } else {
            opts.path = arg;
        }
    }
    if (opts.path.len == 0) return fail("no program given\n\n{s}", .{usage});
    opts.dumps = dumps.items;
    // Insertion sort is stable, so of two requests of one kind at one step
    // the later one wins (they merge, ISA.md §7.1).
    std.sort.insertion(Request, requests.items, {}, Request.before);
    opts.requests = requests.items;
    return opts;
}

/// Load a `.bin` file (doc/ISA.md §10.4): one "address word" line per word,
/// each field 1 to 8 hex digits.
fn load(arena: std.mem.Allocator, cpu: *Cpu, path: []const u8, text: []const u8) error{ Load, OutOfMemory }!void {
    // The line that loaded each address, to report duplicates.
    var loaded: std.AutoHashMapUnmanaged(u32, usize) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var line_no: usize = 0;
    while (lines.next()) |raw| {
        line_no += 1;
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        var it = std.mem.tokenizeAny(u8, line, " \t");
        const a = it.next().?;
        const w = it.next() orelse
            return loadError(path, line_no, "expected 'address word', found only '{s}'", .{a});
        if (it.next()) |extra|
            return loadError(path, line_no, "unexpected '{s}' after the word", .{extra});
        const addr = try parseHex(path, line_no, a);
        const word = try parseHex(path, line_no, w);
        const gop = try loaded.getOrPut(arena, addr);
        if (gop.found_existing)
            return loadError(path, line_no, "address {x:0>8} is already loaded by line {d}", .{ addr, gop.value_ptr.* });
        gop.value_ptr.* = line_no;
        try cpu.mem.write(addr, word);
    }
    if (loaded.count() == 0) {
        std.debug.print("{s}: error: no words to load\n", .{path});
        return error.Load;
    }
}

fn parseHex(path: []const u8, line_no: usize, s: []const u8) error{Load}!u32 {
    for (s) |c| {
        if (!std.ascii.isHex(c)) return loadError(path, line_no, "'{s}' is not a hex number", .{s});
    }
    if (s.len > 8) return loadError(path, line_no, "'{s}' has more than 8 hex digits", .{s});
    return std.fmt.parseInt(u32, s, 16) catch unreachable;
}

fn loadError(path: []const u8, line_no: usize, comptime fmt: []const u8, args: anytype) error{Load} {
    std.debug.print("{s}:{d}: error: " ++ fmt ++ "\n", .{ path, line_no } ++ args);
    return error.Load;
}

fn run(arena: std.mem.Allocator, out: *std.Io.Writer) !u8 {
    const opts = try parseArgs(arena);
    if (opts.help) {
        // Through `out`, so that a closed pipe is handled as for any output.
        try out.writeAll(usage);
        return 0;
    }

    const text = std.fs.cwd().readFileAlloc(arena, opts.path, 1 << 30) catch |err| {
        std.debug.print("niceemu: cannot read {s}: {s}\n", .{ opts.path, @errorName(err) });
        return error.Load;
    };
    var cpu = Cpu.init(arena);
    try load(arena, &cpu, opts.path, text);

    if (opts.trace) cpu.trace = out;
    cpu.console = out;
    cpu.cycle_counter = opts.cycle_counter;
    cpu.timer_irq = opts.timer_irq;
    var in_buf: [4096]u8 = undefined;
    var in_r: std.fs.File.Reader = undefined;
    const in_file = if (std.mem.eql(u8, opts.input, "-")) std.fs.File.stdin() else std.fs.cwd().openFile(opts.input, .{}) catch |err| {
        std.debug.print("niceemu: cannot read {s}: {s}\n", .{ opts.input, @errorName(err) });
        return error.Load;
    };
    // A directory opens, but every read of it fails, which would pass for
    // the end of the input.
    if (!std.mem.eql(u8, opts.input, "-")) {
        const stat = in_file.stat() catch |err| {
            std.debug.print("niceemu: cannot read {s}: {s}\n", .{ opts.input, @errorName(err) });
            return error.Load;
        };
        if (stat.kind == .directory) {
            std.debug.print("niceemu: cannot read {s}: IsDir\n", .{opts.input});
            return error.Load;
        }
    }
    // Streaming, so that stdin may be a terminal or a pipe. Nothing is read
    // until the program reads the console.
    in_r = in_file.readerStreaming(&in_buf);
    cpu.input = &in_r.interface;
    // A step is one instruction, or the entry into an interrupt.
    var steps: u64 = 0;
    var next: usize = 0;
    while (!cpu.halted() and steps < opts.max_steps) : (steps += 1) {
        while (next < opts.requests.len and opts.requests[next].step == steps) : (next += 1) {
            const r = opts.requests[next];
            switch (r.kind) {
                .irq => cpu.requestIrq(r.vector),
                .nmi => cpu.requestNmi(r.vector),
            }
        }
        try cpu.step();
    }

    // After a halt, PC is the address after the halting instruction.
    if (cpu.halted()) {
        try out.print("Halted ({s}) after {d} steps, PC={x:0>8}\n", .{ cpu.halt_reason.describe(), steps, cpu.regs[15] });
    } else {
        try out.print("Stopped at the step limit after {d} steps, PC={x:0>8}\n", .{ steps, cpu.regs[15] });
    }
    // A request still pending now was never taken (ISA.md §7.1).
    if (cpu.nmi_pending != null or cpu.irq_pending != null) {
        try out.writeAll("Pending:");
        if (cpu.nmi_pending) |v| try out.print(" NMI {x:0>2}", .{v});
        if (cpu.irq_pending) |v| try out.print(" IRQ {x:0>2}", .{v});
        try out.writeByte('\n');
    }
    try printRegisters(out, &cpu);
    for (opts.dumps) |d| try printMemory(out, &cpu, d);
    if (opts.screen) try printScreen(out, &cpu, opts.screen_base);

    return if (!cpu.halted()) 3 else if (cpu.halt_reason == .halt) 0 else 2;
}

fn printRegisters(out: *std.Io.Writer, cpu: *const Cpu) !void {
    for (0..16) |i| {
        try out.print("R{d:<2} {x:0>8}", .{ i, cpu.getReg(@intCast(i)) });
        try out.writeByte(if (i % 4 == 3) '\n' else ' ');
    }
}

fn printMemory(out: *std.Io.Writer, cpu: *const Cpu, d: Dump) !void {
    var i: u32 = 0;
    while (i < d.len) : (i += 1) {
        const addr = d.addr +% i;
        if (i % 8 == 0) try out.print("{x:0>8}:", .{addr});
        try out.print(" {x:0>8}", .{cpu.peek(addr)});
        if (i % 8 == 7 or i + 1 == d.len) try out.writeByte('\n');
    }
}

/// Print the screen, one row per line, without trailing blanks. Characters
/// outside printable ASCII show as blanks.
fn printScreen(out: *std.Io.Writer, cpu: *const Cpu, base: u32) !void {
    var rows: [screen_height][screen_width]u8 = undefined;
    var last_row: usize = 0;
    for (&rows, 0..) |*row, y| {
        for (row, 0..) |*ch, x| {
            const c: u8 = @truncate(cpu.peek(base + @as(u32, @intCast(y * screen_width + x))));
            ch.* = if (c > ' ' and c < 0x7F) c else ' ';
            if (ch.* != ' ') last_row = y + 1;
        }
    }
    try out.writeAll("Screen:\n");
    for (rows[0..last_row]) |*row| {
        try out.print("|{s}\n", .{std.mem.trimRight(u8, row, " ")});
    }
}

test {
    _ = @import("cpu.zig");
}
