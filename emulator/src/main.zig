//! niceemu: runs a NICE program in the `.bin` format of doc/ISA.md §10.4.

const std = @import("std");
const Cpu = @import("cpu.zig").Cpu;

const usage =
    \\Usage: niceemu [options] program.bin
    \\
    \\Runs the program from address 0 until it halts, then prints the
    \\registers.
    \\
    \\Options:
    \\  -t, --trace          Print one line per instruction.
    \\  -s, --screen         Print the 80x25 character screen at 0x400.
    \\  -d, --dump ADDR:N    Print N memory words from ADDR. May be repeated.
    \\  -n, --max-steps N    Stop after N steps (default 100000000).
    \\  -m, --mem-size N     Words of memory from address 0 (default 0x100000).
    \\  -h, --help           Print this help.
    \\
    \\Numbers may be decimal or 0x hex. Exit status: 0 after HALT, 1 on a
    \\usage or file error, 2 after any other halt, 3 at the step limit.
    \\
;

/// The character screen of the 2004 emulator (doc/ISA.md §8.3). Each word
/// holds a character in bits 7..0 and its colour above.
const screen_base = 0x400;
const screen_width = 80;
const screen_height = 25;

const Dump = struct { addr: u32, len: u32 };

const Options = struct {
    path: []const u8,
    trace: bool = false,
    screen: bool = false,
    dumps: []const Dump = &.{},
    max_steps: u64 = 100_000_000,
    mem_size: u32 = 0x10_0000,
};

pub fn main() !void {
    var arena_state: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var out_buf: [64 * 1024]u8 = undefined;
    var out_w = std.fs.File.stdout().writer(&out_buf);
    const out = &out_w.interface;

    const status = run(arena, out) catch |err| switch (err) {
        error.Usage, error.Load => 1,
        else => return err,
    };
    try out.flush();
    std.process.exit(status);
}

fn fail(comptime fmt: []const u8, args: anytype) error{Usage} {
    std.debug.print("niceemu: " ++ fmt ++ "\n", args);
    return error.Usage;
}

fn parseNumber(s: []const u8) !u32 {
    return std.fmt.parseInt(u32, s, 0) catch fail("bad number '{s}'", .{s});
}

fn parseArgs(arena: std.mem.Allocator) !Options {
    const args = try std.process.argsAlloc(arena);
    var opts: Options = .{ .path = "" };
    var dumps: std.ArrayList(Dump) = .empty;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        const takes_value = for ([_][]const u8{ "-d", "--dump", "-n", "--max-steps", "-m", "--mem-size" }) |o| {
            if (std.mem.eql(u8, arg, o)) break true;
        } else false;
        const value = if (takes_value) blk: {
            i += 1;
            if (i == args.len) return fail("{s} needs a value", .{arg});
            break :blk args[i];
        } else "";

        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            std.debug.print("{s}", .{usage});
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "-t") or std.mem.eql(u8, arg, "--trace")) {
            opts.trace = true;
        } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--screen")) {
            opts.screen = true;
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--dump")) {
            const colon = std.mem.indexOfScalar(u8, value, ':') orelse
                return fail("--dump wants ADDR:N, not '{s}'", .{value});
            try dumps.append(arena, .{
                .addr = try parseNumber(value[0..colon]),
                .len = try parseNumber(value[colon + 1 ..]),
            });
        } else if (std.mem.eql(u8, arg, "-n") or std.mem.eql(u8, arg, "--max-steps")) {
            opts.max_steps = try parseNumber(value);
        } else if (std.mem.eql(u8, arg, "-m") or std.mem.eql(u8, arg, "--mem-size")) {
            opts.mem_size = try parseNumber(value);
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
    return opts;
}

/// Load a `.bin` file: one "AAAAAAAA WWWWWWWW" line per word.
fn load(mem: []u32, path: []const u8, text: []const u8) error{Load}!void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    var line_no: usize = 0;
    while (lines.next()) |raw| {
        line_no += 1;
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        var it = std.mem.tokenizeAny(u8, line, " \t");
        const a = it.next().?;
        const w = it.next() orelse "";
        const addr = std.fmt.parseInt(u32, a, 16) catch null;
        const word = std.fmt.parseInt(u32, w, 16) catch null;
        if (addr == null or word == null or it.next() != null) {
            std.debug.print("{s}:{d}: error: expected 'address word' in hex\n", .{ path, line_no });
            return error.Load;
        }
        if (addr.? >= mem.len) {
            std.debug.print("{s}:{d}: error: address {x:0>8} is beyond memory (see --mem-size)\n", .{ path, line_no, addr.? });
            return error.Load;
        }
        mem[addr.?] = word.?;
    }
}

fn run(arena: std.mem.Allocator, out: *std.Io.Writer) !u8 {
    const opts = try parseArgs(arena);

    const text = std.fs.cwd().readFileAlloc(arena, opts.path, 1 << 30) catch |err| {
        std.debug.print("niceemu: cannot read {s}: {s}\n", .{ opts.path, @errorName(err) });
        return error.Load;
    };
    const mem = try arena.alloc(u32, opts.mem_size);
    @memset(mem, 0);
    try load(mem, opts.path, text);

    var cpu = Cpu.init(mem);
    if (opts.trace) cpu.trace = out;
    var steps: u64 = 0;
    while (!cpu.halted() and steps < opts.max_steps) : (steps += 1) {
        try cpu.step();
    }

    if (cpu.halted()) {
        try out.print("Halted ({s}) after {d} steps, PC={x:0>8}\n", .{ cpu.halt_reason.describe(), steps, cpu.regs[15] });
    } else {
        try out.print("Stopped at the step limit after {d} steps, PC={x:0>8}\n", .{ steps, cpu.regs[15] });
    }
    try printRegisters(out, &cpu);
    for (opts.dumps) |d| try printMemory(out, &cpu, d);
    if (opts.screen) try printScreen(out, &cpu);

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
        try out.print(" {x:0>8}", .{cpu.read(addr)});
        if (i % 8 == 7 or i + 1 == d.len) try out.writeByte('\n');
    }
}

/// Print the screen, one row per line, without trailing blanks. Characters
/// outside printable ASCII show as blanks.
fn printScreen(out: *std.Io.Writer, cpu: *const Cpu) !void {
    var rows: [screen_height][screen_width]u8 = undefined;
    var last_row: usize = 0;
    for (&rows, 0..) |*row, y| {
        for (row, 0..) |*ch, x| {
            const c: u8 = @truncate(cpu.read(@intCast(screen_base + y * screen_width + x)));
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
