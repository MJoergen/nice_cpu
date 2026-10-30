//! niceemu: runs a NICE program in the `.bin` format of doc/ISA.md §10.4.

const std = @import("std");
const Cpu = @import("cpu.zig").Cpu;
const Link = @import("link.zig").Link;
const frame = @import("frame.zig");
const build_options = @import("build_options");
const Window = if (build_options.window) @import("window.zig").Window else void;

const usage =
    \\Usage: niceemu [options] program.bin
    \\       niceemu --link [ADDR:]PORT [options] [program.bin]
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
    \\      --color          Like --screen, with the colors as ANSI escapes.
    \\      --invert-fg      With --color, invert the foreground, as the 2004 IDE does.
    \\  -2004                Put the screen at 0x400, as the 2004 emulator does.
    \\  -d, --dump ADDR:N    Print N memory words from ADDR. May be repeated.
    \\  -n, --max-steps N    Stop after N steps (default: no limit).
    \\  -i, --input FILE     Read the console input from FILE, or stdin for -.
    \\      --irq STEP:VEC   Raise IRQ with vector VEC before step STEP.
    \\      --nmi STEP:VEC   Raise NMI with vector VEC before step STEP.
    \\                       Both may be repeated. Steps count from 0.
    \\      --symbols FILE   Read labels from FILE, as niceasm --symbols writes it, and
    \\                       name the location of a halt other than HALT, and of a
    \\                       wasm trap (translator/WASM.md), after the halt message.
    \\      --no-cycle-counter  Make 0xFFFFFF40, 0xFFFFFF41, 0xFFFFFF44, and
    \\                       0xFFFFFF45 ordinary memory, for comparing traces
    \\                       with an FPGA core.
    \\      --no-timer-irq   The timer counts, but raises no requests, so that
    \\                       --irq can raise them where an FPGA core took them.
    \\      --link [ADDR:]PORT  Serve the debug link of doc/DEBUG.md on PORT of
    \\                       ADDR (default 127.0.0.1), or on a free port for 0,
    \\                       until a signal. ADDR is an IPv4 address, or an IPv6
    \\                       one in brackets; 0.0.0.0 lets other computers connect.
    \\      --window         Show the screen in a window while the program runs, and
    \\                       keep it after the halt until it is closed. The console
    \\                       reads --input, if given, then the keys typed into the
    \\                       window, and a read returns 0 while no byte waits.
    \\                       Needs a build with -Dwindow.
    \\      --speed N        With --window, run N steps a second (default 1000000,
    \\                       one per microsecond), or as fast as possible for 0.
    \\  -h, --help           Print this help.
    \\
    \\Numbers may be decimal or 0x hex. Exit status: 0 after HALT, 1 on a
    \\usage, file or memory error, 2 after any other halt, 3 at the step
    \\limit, 4 when the window was closed before either.
    \\
;

/// The character screen (doc/SYSTEM.md §1). Each word holds a character in
/// bits 7..0, its background color in bits 31..20, and its foreground color
/// in bits 19..8, each as 4-bit R, G, and B. The 2004 emulator has it at
/// 0x400.
const screen_base = 0xFFFF0000;
const screen_base_2004 = 0x400;

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
    color: bool = false,
    invert_fg: bool = false,
    screen_base: u32 = screen_base,
    dumps: []const Dump = &.{},
    /// Sorted by step, in command-line order within a step.
    requests: []const Request = &.{},
    max_steps: u64 = std.math.maxInt(u64),
    cycle_counter: bool = true,
    timer_irq: bool = true,
    /// The console input file, or "-" for stdin.
    input: []const u8 = "-",
    /// Whether --input was given, as the window reads stdin only then.
    input_given: bool = false,
    /// The label file of niceasm --symbols, or "" for none.
    symbols: []const u8 = "",
    /// The address of --link, or null to run the program once.
    link: ?std.Io.net.IpAddress = null,
    /// Show the screen in a window (doc/SYSTEM.md §1).
    window: bool = false,
    /// Steps a second with the window, or 0 for as fast as possible.
    speed: u64 = 1_000_000,
    help: bool = false,
};

/// A label and its address, from a file of niceasm --symbols.
const Symbol = struct {
    addr: u32,
    name: []const u8,

    fn before(_: void, a: Symbol, b: Symbol) bool {
        return a.addr < b.addr;
    }
};

/// Read a file of lines "address name", as niceasm --symbols writes it.
/// The result is sorted by address.
fn loadSymbols(arena: std.mem.Allocator, io: std.Io, path: []const u8) error{ Load, OutOfMemory }![]Symbol {
    const text = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(1 << 30)) catch |err| {
        std.debug.print("niceemu: cannot read {s}: {s}\n", .{ path, @errorName(err) });
        return error.Load;
    };
    var syms: std.ArrayList(Symbol) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var line_no: usize = 0;
    while (lines.next()) |raw| {
        line_no += 1;
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        var it = std.mem.tokenizeAny(u8, line, " \t");
        const a = it.next().?;
        const name = it.next() orelse
            return loadError(path, line_no, "expected 'address name', found only '{s}'", .{a});
        if (it.next()) |extra|
            return loadError(path, line_no, "unexpected '{s}' after the name", .{extra});
        try syms.append(arena, .{ .addr = try parseHex(path, line_no, a), .name = name });
    }
    std.sort.insertion(Symbol, syms.items, {}, Symbol.before);
    return syms.items;
}

/// The symbol at or before `addr` that comes first in the file, among
/// those at the same address, or null if `addr` is before them all.
fn findSymbol(syms: []const Symbol, addr: u32) ?Symbol {
    var lo: usize = 0;
    var hi: usize = syms.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (syms[mid].addr <= addr) lo = mid + 1 else hi = mid;
    }
    if (lo == 0) return null;
    var i = lo - 1;
    while (i > 0 and syms[i - 1].addr == syms[i].addr) i -= 1;
    return syms[i];
}

/// Print `addr` as "name+0x1f", or just "name", or as hex if no symbol
/// is at or before it.
fn printLocation(out: *std.Io.Writer, syms: []const Symbol, addr: u32) !void {
    const sym = findSymbol(syms, addr) orelse return out.print("{x:0>8}", .{addr});
    if (addr == sym.addr) return out.writeAll(sym.name);
    try out.print("{s}+0x{x}", .{ sym.name, addr - sym.addr });
}

/// The meaning of a wasm trap code (translator/WASM.md).
fn trapName(code: u32) []const u8 {
    return switch (code) {
        1 => "unreachable",
        2 => "memory access out of bounds",
        3 => "division by zero",
        4 => "integer overflow",
        5 => "float to integer conversion",
        6 => "call_indirect: bad index",
        7 => "call_indirect: type mismatch",
        else => "unknown code",
    };
}

/// After a halt other than HALT, or at the step limit: where the program
/// was, and for a halt at the default trap handler, `___wasm_trap`, where
/// the wasm instruction trapped, from R2.
fn printWhere(out: *std.Io.Writer, cpu: *const Cpu, syms: []const Symbol) !void {
    // After a halt, PC is the address after the halting instruction.
    const pc = if (cpu.halted()) cpu.getReg(15) -% 1 else cpu.getReg(15);
    try out.writeAll("At ");
    try printLocation(out, syms, pc);
    try out.writeByte('\n');
    const at = findSymbol(syms, pc) orelse return;
    if (cpu.halted() and pc == at.addr and std.mem.eql(u8, at.name, "___wasm_trap")) {
        try out.print("Trap {d} ({s}) at ", .{ cpu.getReg(1), trapName(cpu.getReg(1)) });
        try printLocation(out, syms, cpu.getReg(2));
        try out.writeByte('\n');
    }
}

/// The signal that asked the run to stop, or 0. Set by `onSignal`.
var stop_signal: std.atomic.Value(u8) = .init(0);

/// How often, in steps, the run loop looks at `stop_signal`.
const signal_check_mask: u64 = 0xFFFF;

fn onSignal(sig: std.posix.SIG) callconv(.c) void {
    stop_signal.store(@intCast(@backingInt(sig)), .release);
}

/// A reader of a file descriptor that, unlike `std.Io.File.Reader`, gives up
/// when a signal interrupts the read. The console read then returns the end
/// of the input, and the run loop sees `stop_signal` at its next check.
const InterruptibleReader = struct {
    fd: std.posix.fd_t,
    interface: std.Io.Reader,

    fn init(fd: std.posix.fd_t, buffer: []u8) InterruptibleReader {
        return .{
            .fd = fd,
            .interface = .{ .vtable = &.{ .stream = stream }, .buffer = buffer, .seek = 0, .end = 0 },
        };
    }

    fn stream(io_reader: *std.Io.Reader, w: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
        const self: *InterruptibleReader = @alignCast(@fieldParentPtr("interface", io_reader));
        const dest = limit.slice(try w.writableSliceGreedy(1));
        const rc = std.posix.system.read(self.fd, dest.ptr, dest.len);
        switch (std.posix.errno(rc)) {
            .SUCCESS => {},
            else => return error.ReadFailed,
        }
        if (rc == 0) return error.EndOfStream;
        w.advance(@intCast(rc));
        return @intCast(rc);
    }
};

/// Catch the signals that end a run from outside, so that the buffered
/// output can be written first. No SA_RESTART, as the default is.
fn catchSignals() void {
    const act: std.posix.Sigaction = .{
        .handler = .{ .handler = onSignal },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    for ([_]std.posix.SIG{ .INT, .TERM, .HUP }) |sig| {
        std.posix.sigaction(sig, &act, null);
    }
}

/// Write the output so far, then die of `sig` with the default action, so
/// that the parent sees the signal.
fn dieOfSignal(out: *std.Io.Writer, sig: u8) noreturn {
    out.flush() catch {};
    const dfl: std.posix.Sigaction = .{
        .handler = .{ .handler = std.posix.SIG.DFL },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(@fromBackingInt(@intCast(sig)), &dfl, null);
    std.posix.raise(@fromBackingInt(@intCast(sig))) catch {};
    std.process.exit(128 + @as(u8, sig));
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    var out_buf: [64 * 1024]u8 = undefined;
    // Streaming, not positional: when stdout is a file shared with other
    // writers, as in `(niceemu x.bin; echo) > log`, the output must go
    // where the file offset is.
    var out_w = std.Io.File.stdout().writerStreaming(io, &out_buf);
    const out = &out_w.interface;

    const status = run(arena, io, args, out) catch |err| switch (err) {
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
fn outputFailed(out_w: *const std.Io.File.Writer) noreturn {
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
/// The `[ADDR:]PORT` of --link: ADDR is an IPv4 address, or an IPv6 one in
/// brackets, and 127.0.0.1 if none is given.
fn parseLink(opt: []const u8, s: []const u8) !std.Io.net.IpAddress {
    const net = std.Io.net;
    const colon = std.mem.findScalarLast(u8, s, ':') orelse
        return .{ .ip4 = .loopback(try parseNumber(u16, opt, s)) };
    const addr = s[0..colon];
    const port = try parseNumber(u16, opt, s[colon + 1 ..]);
    if (addr.len >= 2 and addr[0] == '[' and addr[addr.len - 1] == ']') {
        return net.IpAddress.parseIp6(addr[1 .. addr.len - 1], port) catch fail("{s}: bad address '{s}'", .{ opt, addr });
    }
    return net.IpAddress.parseIp4(addr, port) catch fail("{s}: bad address '{s}'", .{ opt, addr });
}

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

fn parseArgs(arena: std.mem.Allocator, args: []const [:0]const u8) !Options {
    var opts: Options = .{ .path = "" };
    var speed_given = false;
    var dumps: std.ArrayList(Dump) = .empty;
    var requests: std.ArrayList(Request) = .empty;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        const takes_value = for ([_][]const u8{ "-d", "--dump", "-n", "--max-steps", "-i", "--input", "--irq", "--nmi", "--symbols", "--link", "--speed" }) |o| {
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
        } else if (std.mem.eql(u8, arg, "--color")) {
            opts.screen = true;
            opts.color = true;
        } else if (std.mem.eql(u8, arg, "--invert-fg")) {
            opts.screen = true;
            opts.color = true;
            opts.invert_fg = true;
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
            opts.input_given = true;
        } else if (std.mem.eql(u8, arg, "--irq") or std.mem.eql(u8, arg, "--nmi")) {
            const colon = std.mem.indexOfScalar(u8, value, ':') orelse
                return fail("{s} wants STEP:VEC, not '{s}'", .{ arg, value });
            try requests.append(arena, .{
                .step = try parseNumber(u64, arg, value[0..colon]),
                .kind = if (std.mem.eql(u8, arg, "--irq")) .irq else .nmi,
                .vector = try parseNumber(u8, arg, value[colon + 1 ..]),
            });
        } else if (std.mem.eql(u8, arg, "--symbols")) {
            opts.symbols = value;
        } else if (std.mem.eql(u8, arg, "--link")) {
            opts.link = try parseLink(arg, value);
        } else if (std.mem.eql(u8, arg, "--window")) {
            opts.window = true;
        } else if (std.mem.eql(u8, arg, "--speed")) {
            opts.speed = try parseNumber(u64, arg, value);
            speed_given = true;
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
    if (opts.link != null and opts.input_given) return fail("--input cannot be given with --link", .{});
    if (speed_given and !opts.window) return fail("--speed needs --window", .{});
    if (opts.window and !build_options.window) return fail("--window needs a build with -Dwindow (emulator/README.md)", .{});
    if (opts.path.len == 0 and opts.link == null) return fail("no program given\n\n{s}", .{usage});
    opts.dumps = dumps.items;
    // Insertion sort is stable, so of two requests of one kind at one step
    // the earlier one wins (they merge, ISA.md §7.1).
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

fn run(arena: std.mem.Allocator, io: std.Io, args: []const [:0]const u8, out: *std.Io.Writer) !u8 {
    const opts = try parseArgs(arena, args);
    if (opts.help) {
        // Through `out`, so that a closed pipe is handled as for any output.
        try out.writeAll(usage);
        return 0;
    }

    var cpu = Cpu.init(arena);
    if (opts.path.len != 0) {
        const text = std.Io.Dir.cwd().readFileAlloc(io, opts.path, arena, .limited(1 << 30)) catch |err| {
            std.debug.print("niceemu: cannot read {s}: {s}\n", .{ opts.path, @errorName(err) });
            return error.Load;
        };
        try load(arena, &cpu, opts.path, text);
    }
    const syms: []const Symbol = if (opts.symbols.len != 0) try loadSymbols(arena, io, opts.symbols) else &.{};
    if (opts.link) |addr| return serve(arena, io, opts, syms, &cpu, addr);

    if (opts.trace) cpu.trace = out;
    cpu.console = out;
    cpu.console_flush = std.Io.File.stdout().isTty(io) catch false;
    cpu.cycle_counter = opts.cycle_counter;
    cpu.timer_irq = opts.timer_irq;
    var in_buf: [4096]u8 = undefined;
    var in_r: InterruptibleReader = undefined;
    const in_file = if (std.mem.eql(u8, opts.input, "-")) std.Io.File.stdin() else std.Io.Dir.cwd().openFile(io, opts.input, .{}) catch |err| {
        std.debug.print("niceemu: cannot read {s}: {s}\n", .{ opts.input, @errorName(err) });
        return error.Load;
    };
    // A directory opens, but every read of it fails, which would pass for
    // the end of the input.
    if (!std.mem.eql(u8, opts.input, "-")) {
        const stat = in_file.stat(io) catch |err| {
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
    in_r = InterruptibleReader.init(in_file.handle, &in_buf);
    catchSignals();
    if (comptime build_options.window) {
        if (opts.window) return runWindow(arena, io, out, opts, syms, &cpu, if (opts.input_given) &in_r.interface else null);
    }
    cpu.input = .fromReader(&in_r.interface);
    // A step is one instruction, or the entry into an interrupt.
    var steps: u64 = 0;
    var next: usize = 0;
    while (!cpu.halted() and steps < opts.max_steps) : (steps += 1) {
        if (steps & signal_check_mask == 0) {
            const sig = stop_signal.load(.acquire);
            if (sig != 0) dieOfSignal(out, sig);
        }
        raiseRequests(&cpu, opts, steps, &next);
        try cpu.step();
    }
    // A signal that interrupted a console read ended the input, and the
    // program may have halted before the next check above.
    const sig = stop_signal.load(.acquire);
    if (sig != 0) dieOfSignal(out, sig);
    return report(out, opts, syms, &cpu, steps, false);
}

/// Raise the requests of --irq and --nmi for step `steps`. `next` is the
/// first request not raised yet.
fn raiseRequests(cpu: *Cpu, opts: Options, steps: u64, next: *usize) void {
    while (next.* < opts.requests.len and opts.requests[next.*].step == steps) : (next.* += 1) {
        const r = opts.requests[next.*];
        switch (r.kind) {
            .irq => cpu.requestIrq(r.vector),
            .nmi => cpu.requestNmi(r.vector),
        }
    }
}

/// Keeps the speed of --speed: how long to wait after a number of steps,
/// so that they take as long as they would at `speed` steps a second.
const Pacer = struct {
    speed: u64,
    /// The time and the steps from which the pace counts.
    start_ns: i96,
    start_steps: u64 = 0,

    /// A run that falls further behind than this starts the pace again
    /// rather than catch up in a burst.
    const slack_ns = 100 * std.time.ns_per_ms;

    /// Count the pace from `steps` at `now_ns`, after a time without steps.
    fn restart(self: *Pacer, steps: u64, now_ns: i96) void {
        self.start_ns = now_ns;
        self.start_steps = steps;
    }

    /// The ms to wait now, after `steps` steps, at the time `now_ns`.
    fn wait(self: *Pacer, steps: u64, now_ns: i96) u32 {
        if (self.speed == 0) return 0;
        const due: i96 = @intCast(@as(u128, steps - self.start_steps) * std.time.ns_per_s / self.speed);
        const elapsed = now_ns - self.start_ns;
        if (elapsed > due + slack_ns) {
            self.restart(steps, now_ns);
            return 0;
        }
        if (due <= elapsed) return 0;
        return @intCast(@divFloor(due - elapsed, std.time.ns_per_ms));
    }
};

fn nowNs(io: std.Io) i96 {
    return std.Io.Timestamp.now(io, .awake).toNanoseconds();
}

/// The steps of a chunk, between two looks at the window: a millisecond at
/// `speed`, or 65536 without a pace.
fn chunkSteps(speed: u64) u64 {
    return if (speed == 0) 65536 else @max(1, speed / 1000);
}

/// Run the program with the window (doc/SYSTEM.md §1): the console reads
/// `file`, if given, then the keys. After the halt or the step limit, the
/// report is printed, and the window stays until it is closed. Closing it
/// before ends the run.
fn runWindow(arena: std.mem.Allocator, io: std.Io, out: *std.Io.Writer, opts: Options, syms: []const Symbol, cpu: *Cpu, file: ?*std.Io.Reader) !u8 {
    var win: Window = undefined;
    win.open(arena, opts.invert_fg, file) catch return error.Load;
    defer win.close(arena);
    cpu.input = win.queue.input();
    var pacer: Pacer = .{ .speed = opts.speed, .start_ns = nowNs(io) };
    const chunk = chunkSteps(opts.speed);
    var steps: u64 = 0;
    var next: usize = 0;
    var closed = false;
    while (!cpu.halted() and steps < opts.max_steps) {
        const sig = stop_signal.load(.acquire);
        if (sig != 0) dieOfSignal(out, sig);
        const end = @min(opts.max_steps, steps +| chunk);
        while (!cpu.halted() and steps < end) : (steps += 1) {
            raiseRequests(cpu, opts, steps, &next);
            try cpu.step();
        }
        // Show the console output with the screen.
        out.flush() catch {};
        if (!win.pump(cpu, opts.screen_base, @intCast(pacer.wait(steps, nowNs(io))))) {
            closed = true;
            break;
        }
    }
    const status = try report(out, opts, syms, cpu, steps, closed);
    try out.flush();
    while (!closed and win.pump(cpu, opts.screen_base, 100)) {
        const sig = stop_signal.load(.acquire);
        if (sig != 0) dieOfSignal(out, sig);
    }
    return status;
}

/// Print why the run stopped, the registers, the dumps, and the screen, and
/// return the exit status.
fn report(out: *std.Io.Writer, opts: Options, syms: []const Symbol, cpu: *Cpu, steps: u64, closed: bool) !u8 {
    // After a halt, PC is the address after the halting instruction.
    if (closed) {
        try out.print("Stopped when the window was closed after {d} steps, PC={x:0>8}\n", .{ steps, cpu.regs[15] });
    } else if (cpu.halted()) {
        try out.print("Halted ({s}) after {d} steps, PC={x:0>8}\n", .{ cpu.halt_reason.describe(), steps, cpu.regs[15] });
    } else {
        try out.print("Stopped at the step limit after {d} steps, PC={x:0>8}\n", .{ steps, cpu.regs[15] });
    }
    if (syms.len != 0 and !(cpu.halted() and cpu.halt_reason == .halt)) try printWhere(out, cpu, syms);
    // A request still pending now was never taken (ISA.md §7.1).
    if (cpu.nmi_pending != null or cpu.irq_pending != null) {
        try out.writeAll("Pending:");
        if (cpu.nmi_pending) |v| try out.print(" NMI {x:0>2}", .{v});
        if (cpu.irq_pending) |v| try out.print(" IRQ {x:0>2}", .{v});
        try out.writeByte('\n');
    }
    try printRegisters(out, cpu);
    for (opts.dumps) |d| try printMemory(out, cpu, d);
    if (opts.screen) try printScreen(out, cpu, opts.screen_base, opts.color, opts.invert_fg);

    return if (closed) 4 else if (!cpu.halted()) 3 else if (cpu.halt_reason == .halt) 0 else 2;
}

/// Where `serve` prints, so that a signal can flush it before the exit.
var serve_out: ?*std.Io.Writer = null;

/// End the emulator with status 0 if a signal asked it to stop.
fn exitOnSignal() void {
    if (stop_signal.load(.acquire) == 0) return;
    if (serve_out) |w| w.flush() catch {};
    std.process.exit(0);
}

/// Serve the debug link (doc/DEBUG.md) on `addr`, and run each program
/// that the host starts. What a run prints goes to stderr. Runs until a
/// signal, or with --window until the window is closed.
fn serve(arena: std.mem.Allocator, io: std.Io, opts: Options, syms: []const Symbol, cpu: *Cpu, addr: std.Io.net.IpAddress) !u8 {
    var err_buf: [64 * 1024]u8 = undefined;
    var err_w = std.Io.File.stderr().writerStreaming(io, &err_buf);
    const out = &err_w.interface;
    serve_out = out;
    catchSignals();

    var link: Link = undefined;
    const actual = link.open(arena, io, cpu, addr, exitOnSignal) catch |err| {
        std.debug.print("niceemu: cannot serve the link on {f}: {s}\n", .{ addr, @errorName(err) });
        return error.Load;
    };
    if (addr.getPort() == 0) std.debug.print("link: port {d}\n", .{actual});
    if (opts.trace) cpu.trace = out;
    cpu.console = &link.console_w;
    cpu.cycle_counter = opts.cycle_counter;
    cpu.timer_irq = opts.timer_irq;
    // With the window, the console reads do not wait, and the run is paced
    // (doc/SYSTEM.md §1).
    const windowed = build_options.window and opts.window;
    var win: Window = undefined;
    if (windowed) {
        win.open(arena, opts.invert_fg, null) catch return error.Load;
        cpu.input = link.pollInput();
    } else {
        cpu.input = .fromReader(&link.reader);
    }
    var pacer: Pacer = .{ .speed = if (windowed) opts.speed else 0, .start_ns = nowNs(io) };
    const chunk: u64 = if (windowed) chunkSteps(opts.speed) else 4096;

    var steps: u64 = 0;
    var next: usize = 0;
    var reported = false;
    while (true) {
        exitOnSignal();
        if (link.started) {
            link.started = false;
            cpu.reset();
            steps = 0;
            next = 0;
            reported = false;
            pacer.restart(0, nowNs(io));
        }
        if (link.pauseDue(steps == opts.max_steps)) link.pause();
        if (!link.running()) {
            if (link.halted() and !reported) {
                _ = try report(out, opts, syms, cpu, steps, false);
                link.notifyHalt();
                reported = true;
            }
            try out.flush();
            if (windowed) {
                try link.service(0);
                lookAtWindow(arena, &win, &link, cpu, opts, 10);
                pacer.restart(steps, nowNs(io));
            } else {
                try link.service(100);
            }
            continue;
        }
        // A chunk of steps, then the link is served. A step is as in `run`.
        var n: u64 = 0;
        while (n < chunk and link.running() and !link.started and !link.pauseDue(steps == opts.max_steps)) : (n += 1) {
            if (steps == opts.max_steps) {
                link.limit_hit = true;
                break;
            }
            while (next < opts.requests.len and opts.requests[next].step == steps) : (next += 1) {
                const r = opts.requests[next];
                switch (r.kind) {
                    .irq => cpu.requestIrq(r.vector),
                    .nmi => cpu.requestNmi(r.vector),
                }
            }
            // After the requests of this step, as an entry goes first.
            if (link.breakDue()) {
                link.pause();
                break;
            }
            const saved = cpu.save();
            link.taken = 0;
            try cpu.step();
            link.step_due = false;
            link.after_go = false;
            if (cpu.stopped) {
                cpu.stopped = false;
                if (link.undo) {
                    link.undo = false;
                    cpu.putBack(saved);
                    link.putBackInput();
                }
                break;
            }
            steps += 1;
        }
        link.console_w.flush() catch {};
        try link.service(0);
        if (windowed) lookAtWindow(arena, &win, &link, cpu, opts, pacer.wait(steps, nowNs(io)));
    }
}

/// Pump the window of `serve`, waiting up to `wait_ms` for an event, and
/// move the keys typed to the link's input. Closing the window ends the
/// emulator with status 0, as a signal does.
fn lookAtWindow(gpa: std.mem.Allocator, win: *Window, link: *Link, cpu: *Cpu, opts: Options, wait_ms: u32) void {
    if (!win.pump(cpu, opts.screen_base, @intCast(wait_ms))) {
        win.close(gpa);
        if (serve_out) |w| w.flush() catch {};
        std.process.exit(0);
    }
    link.takeKeys(&win.queue);
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
/// outside printable ASCII show as blanks. With `color`, each row has the
/// colors of its words as 24-bit ANSI escapes, changing only where they
/// change, and ends with a reset. With `invert`, the foreground is inverted.
fn printScreen(out: *std.Io.Writer, cpu: *const Cpu, base: u32, color: bool, invert: bool) !void {
    var words: [frame.rows][frame.cols]u32 = undefined;
    var rows: [frame.rows][frame.cols]u8 = undefined;
    var last_row: usize = 0;
    for (&rows, &words, 0..) |*row, *word_row, y| {
        for (row, word_row, 0..) |*ch, *w, x| {
            w.* = cpu.peek(base + @as(u32, @intCast(y * frame.cols + x)));
            const c: u8 = @truncate(w.*);
            ch.* = if (c > ' ' and c < 0x7F) c else ' ';
            if (ch.* != ' ') last_row = y + 1;
        }
    }
    try out.writeAll("Screen:\n");
    for (rows[0..last_row], words[0..last_row]) |*row, *word_row| {
        try out.writeByte('|');
        const text = std.mem.trimEnd(u8, row, " ");
        if (!color) {
            try out.writeAll(text);
        } else {
            var prev: ?[2]frame.Rgb = null;
            for (text, word_row[0..text.len]) |ch, w| {
                const now = [2]frame.Rgb{ frame.background(w), frame.foreground(w, invert) };
                if (prev == null or !std.meta.eql(prev.?, now)) {
                    try out.print("\x1b[48;2;{d};{d};{d};38;2;{d};{d};{d}m", .{
                        now[0][0], now[0][1], now[0][2], now[1][0], now[1][1], now[1][2],
                    });
                    prev = now;
                }
                try out.writeByte(ch);
            }
            try out.writeAll("\x1b[0m");
        }
        try out.writeByte('\n');
    }
}

test "findSymbol takes the nearest label at or before, the first at a tie" {
    const syms = [_]Symbol{
        .{ .addr = 2, .name = "a" },
        .{ .addr = 8, .name = "b" },
        .{ .addr = 8, .name = "c" },
        .{ .addr = 0x20, .name = "d" },
    };
    try std.testing.expect(findSymbol(&syms, 1) == null);
    try std.testing.expectEqualStrings("a", findSymbol(&syms, 2).?.name);
    try std.testing.expectEqualStrings("a", findSymbol(&syms, 7).?.name);
    try std.testing.expectEqualStrings("b", findSymbol(&syms, 8).?.name);
    try std.testing.expectEqualStrings("b", findSymbol(&syms, 0x1F).?.name);
    try std.testing.expectEqualStrings("d", findSymbol(&syms, 0xFFFFFFFF).?.name);
    try std.testing.expect(findSymbol(&.{}, 5) == null);
}

test "the pacer waits until the steps are due at their speed" {
    const ms = std.time.ns_per_ms;
    var p: Pacer = .{ .speed = 1_000_000, .start_ns = 0 };
    // 1000 steps at one a microsecond are due at 1 ms.
    try std.testing.expectEqual(1, p.wait(1000, 0));
    try std.testing.expectEqual(0, p.wait(1000, ms / 2 * 3));
    try std.testing.expectEqual(3, p.wait(5000, 2 * ms));
    // Less than 1 ms ahead waits 0.
    try std.testing.expectEqual(0, p.wait(5000, 4 * ms + 1));
    // 100 ms behind is within the slack; more starts the pace again.
    try std.testing.expectEqual(0, p.wait(5000, 105 * ms));
    try std.testing.expectEqual(0, p.start_steps);
    try std.testing.expectEqual(0, p.wait(5000, 106 * ms));
    try std.testing.expectEqual(5000, p.start_steps);
    try std.testing.expectEqual(2, p.wait(7000, 106 * ms));
    // Without a speed, it never waits.
    var q: Pacer = .{ .speed = 0, .start_ns = 0 };
    try std.testing.expectEqual(0, q.wait(1_000_000, 0));
}

test "a chunk is a millisecond of steps, or 65536 without a pace" {
    try std.testing.expectEqual(1000, chunkSteps(1_000_000));
    try std.testing.expectEqual(1, chunkSteps(500));
    try std.testing.expectEqual(65536, chunkSteps(0));
}

test {
    _ = @import("cpu.zig");
    _ = @import("link.zig");
    _ = @import("frame.zig");
    _ = @import("keys.zig");
    // The window is compiled, not run: its tests need a display.
    if (@import("build_options").window) {
        const W = @import("window.zig").Window;
        _ = &W.open;
        _ = &W.pump;
        _ = &W.close;
    }
}
