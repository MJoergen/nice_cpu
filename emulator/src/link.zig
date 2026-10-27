//! The debug link of doc/DEBUG.md, served on a TCP port of 127.0.0.1.
//! One host at a time reads and writes the memory, loads and starts a
//! program, and learns when it halts. The link shares its byte stream with
//! the console.

const std = @import("std");
const posix = std.posix;
const cpu_zig = @import("cpu.zig");
const Cpu = cpu_zig.Cpu;

/// The escape byte, which starts a packet (DEBUG.md §1).
pub const esc: u8 = 0xFF;
/// The protocol version (DEBUG.md §4, §6).
const version: u8 = 4;
/// The program's input buffer, in bytes (DEBUG.md §7).
pub const input_size = 2048;
/// The packet timeout of DEBUG.md §5.
const timeout_ms = 100;
/// The debug registers, for the link only (DEBUG.md §6).
const debug_base: u32 = 0xFFFF_FFE0;
const control_addr: u32 = debug_base + 0x10;
/// The number of breakpoints (DEBUG.md §6, §7).
const breaks = 4;
const break_en_addr: u32 = debug_base + 0x14;
const break_addr0: u32 = debug_base + 0x18;
/// The longest payload of a request: A, N, and 65535 words.
const max_payload = 12 + 8 * 0xFFFF;

/// The bits of the control register (DEBUG.md §6).
const ctl_hold: u32 = 1 << 0;
const ctl_halted: u32 = 1 << 1;
const ctl_clear: u32 = 1 << 2;
const ctl_rom_hidden: u32 = 1 << 3;
const ctl_pause: u32 = 1 << 4;
const ctl_step: u32 = 1 << 5;

pub const Link = struct {
    cpu: *Cpu,
    gpa: std.mem.Allocator,
    io: std.Io,
    listener: std.Io.net.Server,
    conn: ?std.Io.net.Stream = null,
    /// The host has closed its half of the connection for writing.
    conn_eof: bool = false,

    /// Bit 0 of the control register.
    held: bool = true,
    /// Bit 4 as last written: a pause is asked for (DEBUG.md §6).
    pause_req: bool = false,
    /// The processor has paused: bit 4 reads 1. Only the run loop sets it.
    paused: bool = false,
    /// A step of a paused processor has been asked for and not yet run: the
    /// run loop takes one step before it pauses again (DEBUG.md §6).
    step_due: bool = false,
    /// The first step after a go on or a step, which no pause request and
    /// no breakpoint stops (DEBUG.md §6).
    after_go: bool = false,
    /// The enable bits and the addresses of the breakpoints (DEBUG.md §6).
    break_en: u32 = 0,
    break_addr: [breaks]u32 = @splat(0),
    /// The breakpoint of the last `x`, until the next go on, step, or start:
    /// the stop register.
    stop_break: ?u8 = null,
    /// The step limit stopped the run: halt reason 5.
    limit_hit: bool = false,
    /// A start that the run loop has not carried out yet. It resets the
    /// processor there, and not inside a waiting console read.
    started: bool = false,
    /// Set by a hold or a start, so that a waiting console read gives up.
    interrupted: bool = false,
    /// Called while a console read waits, to end the emulator on a signal.
    on_wait: *const fn () void,

    /// The program's input, a ring of `input_size` bytes.
    input: [input_size]u8 = undefined,
    input_head: usize = 0,
    input_len: usize = 0,
    /// The end of the input (DEBUG.md §7).
    input_end: bool = false,
    /// An `o` was sent, and the buffer has had no room since.
    overflow_sent: bool = false,

    // The packet being received (DEBUG.md §2, §5).
    state: enum { idle, escape, payload, cc_high, cc_low } = .idle,
    tag: u8 = 0,
    sum: u8 = 0,
    cc_high: u8 = 0,
    payload: std.ArrayList(u8) = .empty,
    too_long: bool = false,
    last_byte_ms: i64 = 0,

    /// The program's console output, escaped and sent to the host.
    console_w: std.Io.Writer,
    console_buf: [4096]u8 = undefined,
    /// The program's console input, from `input`.
    reader: std.Io.Reader,
    reader_buf: [16]u8 = undefined,

    /// Listen on `port` of 127.0.0.1, or on a free port for 0, and return
    /// the port. `self` must not move afterwards.
    pub fn open(self: *Link, gpa: std.mem.Allocator, io: std.Io, cpu: *Cpu, port: u16, on_wait: *const fn () void) !u16 {
        const addr: std.Io.net.IpAddress = .{ .ip4 = .loopback(port) };
        const server = try addr.listen(io, .{ .kernel_backlog = 1, .reuse_address = true });
        self.* = .{
            .io = io,
            .cpu = cpu,
            .gpa = gpa,
            .listener = server,
            .on_wait = on_wait,
            .console_w = .{ .vtable = &.{ .drain = drainConsole }, .buffer = undefined },
            .reader = .{ .vtable = &.{ .stream = streamInput }, .buffer = undefined, .seek = 0, .end = 0 },
        };
        self.console_w.buffer = &self.console_buf;
        self.reader.buffer = &self.reader_buf;
        return server.socket.address.getPort();
    }

    /// Whether the processor has halted, or the step limit stopped it.
    pub fn halted(self: *const Link) bool {
        return !self.started and (self.cpu.halted() or self.limit_hit);
    }

    /// Whether the program runs: bits 0, 1, and 4 of the control register
    /// read 0.
    pub fn running(self: *const Link) bool {
        return !self.held and !self.halted() and !self.paused;
    }

    /// Whether a pause request takes effect now, between two steps. A halt
    /// goes first, so not at the step limit (DEBUG.md §6).
    pub fn pauseDue(self: *const Link, at_limit: bool) bool {
        return self.running() and self.pause_req and !at_limit and !self.step_due;
    }

    /// The lowest enabled breakpoint at `addr`, if any.
    fn breakAt(self: *const Link, addr: u32) ?u8 {
        for (self.break_addr, 0..) |a, i| {
            if (self.break_en >> @intCast(i) & 1 == 1 and a == addr) return @intCast(i);
        }
        return null;
    }

    /// Whether a breakpoint stops the processor now, before the next step:
    /// R15 is an enabled breakpoint, and the step is not the first after a go
    /// on or a step, nor an interrupt entry, which goes first (DEBUG.md §6).
    pub fn breakDue(self: *const Link) bool {
        return self.running() and !self.after_go and !self.cpu.entryDue() and
            self.breakAt(self.cpu.getReg(15)) != null;
    }

    /// Pause the processor, and send the console output so far and the
    /// notice: `x` if R15 is an enabled breakpoint, and `p` otherwise
    /// (DEBUG.md §4). A stop at a breakpoint sets bit 4 as a request does.
    pub fn pause(self: *Link) void {
        self.paused = true;
        self.pause_req = true;
        self.console_w.flush() catch {};
        self.stop_break = self.breakAt(self.cpu.getReg(15));
        if (self.stop_break) |i| {
            var buf: [2]u8 = undefined;
            self.sendPacket('x', hex(&buf, i));
        } else {
            self.sendPacket('p', "");
        }
    }

    /// The halt reason of DEBUG.md §6.
    fn haltReason(self: *const Link) u32 {
        if (!self.halted()) return 0;
        if (self.limit_hit) return 5;
        return @backingInt(self.cpu.halt_reason);
    }

    /// Send the console output so far, and the `h` notice.
    pub fn notifyHalt(self: *Link) void {
        self.console_w.flush() catch {};
        var buf: [2]u8 = undefined;
        self.sendPacket('h', hex(&buf, self.haltReason()));
    }

    /// Accept a host, read what it sent, and act on it. Waits up to
    /// `timeout` ms for something to happen, or not at all for 0.
    pub fn service(self: *Link, timeout: i32) !void {
        var fds = [2]posix.pollfd{
            .{ .fd = self.listener.socket.handle, .events = posix.POLL.IN, .revents = 0 },
            .{ .fd = if (self.conn) |c| c.socket.handle else -1, .events = if (self.conn_eof) 0 else posix.POLL.IN, .revents = 0 },
        };
        if (try posix.poll(&fds, timeout) == 0) return;
        if (fds[0].revents & posix.POLL.IN != 0) self.accept();
        if (fds[1].revents != 0 and self.conn_eof) return self.disconnect();
        if (fds[1].revents != 0 and self.conn != null) {
            var buf: [4096]u8 = undefined;
            var vec = [1][]u8{&buf};
            const n = (self.conn.?.readWithControl(self.io, &vec, &.{}) catch return self.disconnect()).data_len;
            if (n == 0) {
                // A half-close or a disconnect: both end the input.
                self.conn_eof = true;
                self.input_end = true;
                return;
            }
            const now = std.Io.Timestamp.now(self.io, .awake).toMilliseconds();
            for (buf[0..n]) |b| self.receive(b, now);
        }
    }

    /// Accept a host. While one is connected, another is closed at once,
    /// unless the first has closed its half for writing: a host that sends
    /// nothing more cannot be told from one that has gone.
    fn accept(self: *Link) void {
        const stream = self.listener.accept(self.io) catch return;
        if (self.conn != null and !self.conn_eof) {
            stream.close(self.io);
            return;
        }
        if (self.conn) |old| old.close(self.io);
        self.conn = stream;
        const fd = stream.socket.handle;
        self.conn_eof = false;
        posix.setsockopt(fd, posix.IPPROTO.TCP, posix.TCP.NODELAY, &std.mem.toBytes(@as(c_int, 1))) catch {};
        self.state = .idle;
        // Every `b` means that no breakpoint is left (DEBUG.md §6, §7).
        self.break_en = 0;
        self.break_addr = @splat(0);
        var buf: [2]u8 = undefined;
        self.sendPacket('b', hex(&buf, version));
    }

    fn disconnect(self: *Link) void {
        if (self.conn) |c| c.close(self.io);
        self.conn = null;
        self.conn_eof = false;
        self.input_end = true;
    }

    /// Send `bytes` to the host, if one is connected.
    fn send(self: *Link, bytes: []const u8) void {
        const c = self.conn orelse return;
        var w = c.writer(self.io, &.{});
        w.interface.writeAll(bytes) catch return self.disconnect();
    }

    /// Send ESC, `tag`, `payload`, `#`, and the checksum, whole.
    fn sendPacket(self: *Link, tag: u8, payload: []const u8) void {
        var head = [2]u8{ esc, tag };
        var tail: [3]u8 = undefined;
        tail[0] = '#';
        _ = hex(tail[1..3], checksum(tag, payload));
        self.send(&head);
        self.send(payload);
        self.send(&tail);
    }

    fn sendError(self: *Link, tag: u8, code: u8) void {
        var buf: [4]u8 = undefined;
        _ = hex(buf[0..2], tag);
        _ = hex(buf[2..4], code);
        self.sendPacket('e', &buf);
    }

    /// One byte from the host (DEBUG.md §1, §5).
    fn receive(self: *Link, b: u8, now: i64) void {
        if (self.state != .idle and now - self.last_byte_ms > timeout_ms) self.state = .idle;
        self.last_byte_ms = now;
        switch (self.state) {
            .idle => if (b == esc) {
                self.state = .escape;
            } else self.consoleByte(b),
            .escape => if (b == esc) {
                self.state = .idle;
                self.consoleByte(esc);
            } else if (std.ascii.isAlphabetic(b)) {
                self.state = .payload;
                self.tag = b;
                self.sum = b;
                self.payload.clearRetainingCapacity();
                self.too_long = false;
            } else {
                self.state = .idle;
            },
            .payload => if (b == esc) {
                self.state = .escape;
            } else if (b == '#') {
                self.state = .cc_high;
            } else {
                self.sum +%= b;
                if (self.payload.items.len == max_payload) {
                    self.too_long = true;
                } else {
                    self.payload.append(self.gpa, b) catch {
                        self.too_long = true;
                    };
                }
            },
            .cc_high => if (b == esc) {
                self.state = .escape;
            } else {
                self.cc_high = b;
                self.state = .cc_low;
            },
            .cc_low => if (b == esc) {
                self.state = .escape;
            } else {
                self.state = .idle;
                const hi = std.fmt.charToDigit(self.cc_high, 16) catch return;
                const lo = std.fmt.charToDigit(b, 16) catch return;
                if (hi * 16 + lo == self.sum) self.request();
            },
        }
    }

    /// A console byte from the host. It reaches the program while it runs
    /// or is paused, before the end of the input.
    fn consoleByte(self: *Link, b: u8) void {
        if (self.held or self.halted() or self.input_end) return;
        if (self.input_len == input_size) {
            if (!self.overflow_sent) self.sendPacket('o', "");
            self.overflow_sent = true;
            return;
        }
        self.input[(self.input_head + self.input_len) % input_size] = b;
        self.input_len += 1;
    }

    /// A packet with a good checksum (DEBUG.md §3).
    fn request(self: *Link) void {
        const p = self.payload.items;
        if (self.tag != 'R' and self.tag != 'W') return self.sendError(self.tag, 1);
        const a = parseHex(p, 0, 8) orelse return self.sendError(self.tag, 3);
        const n = parseHex(p, 8, 4) orelse return self.sendError(self.tag, 3);
        // Decided from A and N alone, before any data word.
        if (self.running() and reachesMemory(a, n)) return self.sendError(self.tag, 2);
        if (self.tag == 'W' and wraps(a, n)) return self.sendError(self.tag, 2);
        var head: [12]u8 = undefined;
        _ = hex(head[0..8], a);
        _ = hex(head[8..12], n);
        if (self.tag == 'R') {
            if (p.len != 12 or self.too_long) return self.sendError(self.tag, 3);
            var answer: std.ArrayList(u8) = .empty;
            defer answer.deinit(self.gpa);
            answer.appendSlice(self.gpa, &head) catch return;
            for (0..n) |i| {
                var w: [8]u8 = undefined;
                answer.appendSlice(self.gpa, hex(&w, self.readWord(a +% @as(u32, @intCast(i))))) catch return;
            }
            return self.sendPacket('r', answer.items);
        }
        // The words are written in order, as a board writes them as they
        // arrive: those before a bad byte, and at most N.
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const w = parseHex(p, 12 + 8 * i, 8) orelse break;
            self.writeWord(a +% i, w);
        }
        if (self.too_long or p.len != 12 + 8 * @as(usize, n) or i < n) return self.sendError(self.tag, 3);
        self.sendPacket('k', &head);
    }

    /// A link read (DEBUG.md §3): no read has a side effect.
    fn readWord(self: *Link, addr: u32) u32 {
        if (addr >= debug_base) return self.readDebug(addr);
        if (addr == cpu_zig.console_addr or addr == cpu_zig.counter_addr) return 0;
        return self.cpu.peek(addr);
    }

    fn readDebug(self: *Link, addr: u32) u32 {
        return switch (addr - debug_base) {
            0x00...0x0F => self.cpu.getReg(@truncate(addr)),
            0x10 => @as(u32, @intFromBool(self.held)) | @as(u32, @intFromBool(self.halted())) << 1 | ctl_rom_hidden |
                @as(u32, @intFromBool(self.paused)) << 4,
            0x11 => self.haltReason(),
            0x12 => version,
            0x13 => @intCast(input_size - self.input_len),
            0x14 => self.break_en,
            0x15 => breaks,
            0x16 => if (self.stop_break) |i| 0x100 | @as(u32, i) else 0,
            0x18...0x18 + breaks - 1 => self.break_addr[addr - break_addr0],
            else => 0,
        };
    }

    /// A link write (DEBUG.md §3).
    fn writeWord(self: *Link, addr: u32, value: u32) void {
        if (addr == control_addr) return self.writeControl(value);
        if (addr == break_en_addr) {
            self.break_en = value & ((1 << breaks) - 1);
            return;
        }
        if (addr >= break_addr0 and addr < break_addr0 + breaks) {
            self.break_addr[addr - break_addr0] = value;
            return;
        }
        if (addr >= debug_base) return;
        if (addr == cpu_zig.console_addr or addr == cpu_zig.counter_addr) return;
        // Out of memory leaves the word unwritten.
        self.cpu.write(addr, value) catch {};
    }

    /// A write to the control register (DEBUG.md §6). The emulator has no
    /// ROM, so bit 3 reads 1 and is ignored.
    fn writeControl(self: *Link, value: u32) void {
        if (value & ctl_clear != 0) {
            self.hold();
            self.cpu.mem.deinit();
            self.cpu.mem = .init(self.gpa);
        }
        self.pause_req = value & ctl_pause != 0;
        if (value & ctl_hold != 0) {
            self.hold();
        } else if (self.held) {
            self.start();
        } else if (!self.pause_req) {
            // Cancels a request, or makes a paused processor go on.
            if (self.paused) self.goOn();
        } else if (value & ctl_step != 0 and self.paused) {
            // One step, and then the run loop pauses again. Bit 5 does
            // nothing unless the processor is paused.
            self.goOn();
            self.step_due = true;
        }
    }

    /// A paused processor goes on, for a go on or a step.
    fn goOn(self: *Link) void {
        self.paused = false;
        self.after_go = true;
        self.stop_break = null;
    }

    /// A hold ends a pause, and R0 to R15 stay as they are.
    fn hold(self: *Link) void {
        if (!self.held) self.interrupted = true;
        self.held = true;
        self.paused = false;
        self.step_due = false;
        self.after_go = false;
    }

    fn start(self: *Link) void {
        self.held = false;
        self.paused = false;
        self.started = true;
        self.step_due = false;
        self.after_go = false;
        self.stop_break = null;
        self.interrupted = true;
        self.limit_hit = false;
        self.input_head = 0;
        self.input_len = 0;
        self.input_end = false;
        self.overflow_sent = false;
    }

    /// The console output of the program: every 0xFF becomes ESC ESC.
    fn drainConsole(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *Link = @fieldParentPtr("console_w", w);
        self.sendConsole(w.buffered());
        w.end = 0;
        var n: usize = 0;
        for (data[0 .. data.len - 1]) |d| {
            self.sendConsole(d);
            n += d.len;
        }
        for (0..splat) |_| self.sendConsole(data[data.len - 1]);
        return n + data[data.len - 1].len * splat;
    }

    fn sendConsole(self: *Link, bytes: []const u8) void {
        var rest = bytes;
        while (std.mem.indexOfScalar(u8, rest, esc)) |i| {
            self.send(rest[0 .. i + 1]);
            self.send(&.{esc});
            rest = rest[i + 1 ..];
        }
        self.send(rest);
    }

    /// The next input byte of the program. While none is there, the link is
    /// served. A hold or a start ends the wait, and so does the end of the
    /// input. Then the read returns the end of the input, and the step
    /// stops.
    fn streamInput(r: *std.Io.Reader, w: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
        const self: *Link = @fieldParentPtr("reader", r);
        if (limit == .nothing) return 0;
        self.interrupted = false;
        while (self.input_len == 0) {
            if (self.input_end) return error.EndOfStream;
            self.console_w.flush() catch {};
            self.on_wait();
            self.service(timeout_ms) catch return error.ReadFailed;
            if (self.interrupted) {
                self.cpu.stopped = true;
                return error.EndOfStream;
            }
        }
        const b = self.input[self.input_head];
        self.input_head = (self.input_head + 1) % input_size;
        self.input_len -= 1;
        self.overflow_sent = false;
        try w.writeByte(b);
        return 1;
    }
};

/// Whether N words from A reach a word that is not a debug register.
fn reachesMemory(a: u32, n: u32) bool {
    return n != 0 and (a < debug_base or n > 0 -% a);
}

/// Whether N words from A run past 0xFFFFFFFF, which a W may not (DEBUG.md §3).
fn wraps(a: u32, n: u32) bool {
    return a != 0 and n > 0 -% a;
}

/// The sum mod 256 of the tag and the payload (DEBUG.md §2).
fn checksum(tag: u8, payload: []const u8) u8 {
    var sum = tag;
    for (payload) |b| sum +%= b;
    return sum;
}

/// Write `value` into `buf` as uppercase hex digits, big-endian, and
/// return `buf`.
fn hex(buf: []u8, value: u32) []u8 {
    var v = value;
    var i = buf.len;
    while (i > 0) {
        i -= 1;
        buf[i] = "0123456789ABCDEF"[v & 0xF];
        v >>= 4;
    }
    return buf;
}

/// The `len` hex digits of `p` at `at`, in either case, or null if `p` is
/// too short or one is not a hex digit.
fn parseHex(p: []const u8, at: usize, len: usize) ?u32 {
    if (p.len < at + len) return null;
    var v: u32 = 0;
    for (p[at .. at + len]) |c| v = v << 4 | (std.fmt.charToDigit(c, 16) catch return null);
    return v;
}

test "the checksums of DEBUG.md §8" {
    const t = std.testing;
    try t.expectEqual(0xE2, checksum('W', "0000010000021122334455667788"));
    try t.expectEqual(0xAE, checksum('k', "000001000002"));
    try t.expectEqual(0x94, checksum('R', "000001000001"));
    try t.expectEqual(0x48, checksum('r', "00000100000111223344"));
    try t.expectEqual(0xC9, checksum('h', "01"));
    try t.expectEqual(0x2E, checksum('e', "5202"));
    try t.expectEqual(0xBB, checksum('W', "FFFFFFF0000100000009"));
    try t.expectEqual(0xBA, checksum('W', "FFFFFFF0000100000008"));
    try t.expectEqual(0x46, checksum('k', "FFFFFFF00001"));
    try t.expectEqual(0xC4, checksum('b', "02"));
    try t.expectEqual(0x70, checksum('p', ""));
    try t.expectEqual(0xBB, checksum('W', "FFFFFFF0000100000018"));
}

test "the debug registers are the only words a running program allows" {
    const t = std.testing;
    try t.expect(!reachesMemory(0, 0));
    try t.expect(reachesMemory(0x100, 1));
    try t.expect(!reachesMemory(0xFFFFFFE0, 32));
    try t.expect(reachesMemory(0xFFFFFFE0, 33));
    try t.expect(reachesMemory(0xFFFFFFDF, 1));
    try t.expect(!reachesMemory(0xFFFFFFFF, 1));
    try t.expect(reachesMemory(0xFFFFFFFF, 2));
}

test "a W may not wrap past 0xFFFFFFFF" {
    const t = std.testing;
    try t.expect(!wraps(0, 0));
    try t.expect(!wraps(0, 65535));
    try t.expect(!wraps(0xFFFFFFFF, 0));
    try t.expect(!wraps(0xFFFFFFFF, 1));
    try t.expect(wraps(0xFFFFFFFF, 2));
    try t.expect(!wraps(0xFFFFFFF0, 16));
    try t.expect(wraps(0xFFFFFFF0, 17));
    try t.expect(!wraps(0xFFFF0001, 65535));
    try t.expect(!wraps(0xFFFF0000, 65535));
    try t.expect(wraps(0xFFFF0002, 65535));
}

test "hex fields" {
    const t = std.testing;
    var buf: [8]u8 = undefined;
    try t.expectEqualStrings("00ABCDEF", hex(&buf, 0xABCDEF));
    try t.expectEqual(0xABCDEF, parseHex("00abCDef", 0, 8));
    try t.expectEqual(null, parseHex("00abCDeg", 0, 8));
    try t.expectEqual(null, parseHex("0001", 0, 8));
}
