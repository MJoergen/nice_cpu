//! The port for Ethernet frames of doc/SYSTEM.md §7, at 0xFFFFFFC0-CF,
//! with the part of the network station (§6) that serves frames before
//! the queue: ARP and ping for NET_IP, and the TCP of the debug link.
//!
//! The emulator has no Ethernet. The host gives frames to `Eth.receive`,
//! from a UDP socket whenever one arrives, and from the lines of --eth-in
//! at the writes of SYSTEM.md §7, which `Eth` takes itself. The frames
//! that the program sends, and the station's replies, go to `Wire`.

const std = @import("std");

/// The first of the 16 words of the port.
pub const base: u32 = 0xFFFF_FFC0;

/// The frames the queue holds, on every system.
pub const queue_len = 4;
/// The shortest and the longest frame, in bytes, without the FCS.
pub const min_len = 14;
pub const max_len = 1514;
/// The chunks of 8 words that hold a frame with its 2 bytes of offset.
pub const chunks = 48;
pub const buf_words = chunks * 8;
/// The shortest frame on the wire, to which the station pads.
pub const wire_min_len = 60;

const broadcast: u48 = 0xFFFF_FFFF_FFFF;

/// What the station needs of the registers of SYSTEM.md §6.
pub const Station = struct {
    ip: u32,
    mac: u48,
    /// The TCP port of the debug link, bits 15..0 of `NET_STATUS`, or 0.
    tcp_port: u16,
};

/// Where the frames go: the frames the program sends, and the replies of
/// the station, as bytes without the FCS or the padding.
pub const Wire = struct {
    ctx: *anyopaque,
    send_fn: *const fn (ctx: *anyopaque, frame: []const u8) void,
};

/// A line of --eth-in: a frame that waits until the program has sent
/// `after` frames.
pub const Line = struct {
    after: u64,
    frame: []const u8,
};

/// A frame in the queue: its length in bytes, and its words with the
/// offset, as `ETH_BUF0`-`7` read them.
const Frame = struct {
    len: u16,
    words: [buf_words]u32,
};

pub const Eth = struct {
    enabled: bool = false,
    queue: [queue_len]Frame = undefined,
    head: u2 = 0,
    count: u3 = 0,
    dropped: u32 = 0,
    chunk: u6 = 0,
    /// Bit 8 of `ETH_CHUNK`: the send buffer is selected.
    tx_sel: bool = false,
    /// The send buffer, which a start keeps, and which is 0 at the launch.
    tx: [buf_words]u32 = @splat(0),
    /// The lines of --eth-in, and the first that has not arrived.
    lines: []const Line = &.{},
    next_line: usize = 0,
    /// The frames the program has sent since the launch, for `Line.after`.
    sent: u64 = 0,
    wire: ?Wire = null,

    /// Reset (SYSTEM §7). The send buffer, the lines, and the count of
    /// frames sent stay.
    pub fn reset(self: *Eth) void {
        self.enabled = false;
        self.head = 0;
        self.count = 0;
        self.dropped = 0;
        self.chunk = 0;
        self.tx_sel = false;
    }

    /// The value a data read of word `i` returns. Reads have no side effect.
    pub fn read(self: *const Eth, i: u4) u32 {
        return switch (i) {
            0 => @as(u32, @intFromBool(self.enabled)) | @as(u32, @intFromBool(self.count != 0)) << 1,
            1 => if (self.count != 0) self.queue[self.head].len else 0,
            3 => self.chunk | @as(u32, @intFromBool(self.tx_sel)) << 8,
            4 => self.dropped,
            8...15 => self.bufWord(i - 8),
            else => 0,
        };
    }

    fn bufWord(self: *const Eth, k: u4) u32 {
        if (self.chunk >= chunks) return 0;
        const n = @as(usize, self.chunk) * 8 + k;
        if (self.tx_sel) return self.tx[n];
        return if (self.count != 0) self.queue[self.head].words[n] else 0;
    }

    /// A write of `value` to word `i`, with the station's registers `st`.
    pub fn write(self: *Eth, i: u4, value: u32, st: Station) void {
        switch (i) {
            0 => if (value & 1 != 0) {
                if (!self.enabled) {
                    self.enabled = true;
                    self.arrive(st);
                }
            } else {
                self.enabled = false;
                self.head = 0;
                self.count = 0;
                self.dropped = 0;
            },
            1 => if (self.count != 0) {
                self.head +%= 1;
                self.count -= 1;
            },
            2 => if (self.enabled and value >= min_len and value <= max_len) {
                var bytes: [max_len]u8 = undefined;
                const frame = fromWords(&self.tx, @intCast(value), &bytes);
                if (self.wire) |w| w.send_fn(w.ctx, frame);
                self.sent += 1;
                self.arrive(st);
            },
            3 => {
                self.chunk = @truncate(value);
                self.tx_sel = value & 0x100 != 0;
            },
            8...15 => if (self.tx_sel and self.chunk < chunks) {
                self.tx[@as(usize, self.chunk) * 8 + (i - 8)] = value;
            },
            else => {},
        }
    }

    /// The lines of --eth-in whose count of frames sent has been reached
    /// arrive, in order (SYSTEM §7, the emulator).
    fn arrive(self: *Eth, st: Station) void {
        while (self.next_line < self.lines.len and self.lines[self.next_line].after <= self.sent) {
            self.receive(self.lines[self.next_line].frame, st);
            self.next_line += 1;
        }
    }

    /// A frame of `min_len` to `max_len` bytes arrives at the station,
    /// which serves it, passes it to the queue, or drops it (SYSTEM §6, §7).
    pub fn receive(self: *Eth, frame: []const u8, st: Station) void {
        std.debug.assert(frame.len >= min_len and frame.len <= max_len);
        const dest = std.mem.readInt(u48, frame[0..6], .big);
        if (dest != st.mac and dest != broadcast) return;
        if (self.serve(frame, st)) return;
        if (!self.enabled) return;
        if (self.count == queue_len) {
            self.dropped +%= 1;
            return;
        }
        const q = &self.queue[self.head +% @as(u2, @truncate(self.count))];
        q.len = @intCast(frame.len);
        toWords(frame, &q.words);
        self.count += 1;
    }

    /// Serve `frame` if the station keeps it: an ARP request for its IP
    /// address and a ping to it get a reply, and the TCP of the debug link
    /// is the host's. Returns whether it kept the frame.
    fn serve(self: *Eth, frame: []const u8, st: Station) bool {
        if (st.ip == 0) return false;
        const ether_type = std.mem.readInt(u16, frame[12..14], .big);
        if (ether_type == 0x0806) return self.serveArp(frame, st);
        if (ether_type != 0x0800 or frame.len < 14 + 20) return false;
        const ihl: usize = @as(usize, frame[14] & 0x0F) * 4;
        if (frame[14] >> 4 != 4 or ihl < 20) return false;
        const total = std.mem.readInt(u16, frame[16..18], .big);
        if (total < ihl or 14 + @as(usize, total) > frame.len) return false;
        if (std.mem.readInt(u32, frame[30..34], .big) != st.ip) return false;
        const ip = frame[14 .. 14 + @as(usize, total)];
        switch (ip[9]) {
            1 => {
                if (ip.len < ihl + 8 or ip[ihl] != 8 or ip[ihl + 1] != 0) return false;
                self.echoReply(frame[0 .. 14 + ip.len], ihl, st);
                return true;
            },
            6 => {
                if (st.tcp_port == 0 or ip.len < ihl + 4) return false;
                return std.mem.readInt(u16, ip[ihl + 2 ..][0..2], .big) == st.tcp_port;
            },
            else => return false,
        }
    }

    fn serveArp(self: *Eth, frame: []const u8, st: Station) bool {
        if (frame.len < 42) return false;
        const a = frame[14..42];
        const want = [_]u8{ 0, 1, 0x08, 0x00, 6, 4, 0, 1 };
        if (!std.mem.eql(u8, a[0..8], &want)) return false;
        if (std.mem.readInt(u32, a[24..28], .big) != st.ip) return false;
        var r: [42]u8 = undefined;
        @memcpy(r[0..6], a[8..14]); // to the sender's MAC address
        std.mem.writeInt(u48, r[6..12], st.mac, .big);
        std.mem.writeInt(u16, r[12..14], 0x0806, .big);
        @memcpy(r[14..20], want[0..6]);
        std.mem.writeInt(u16, r[20..22], 2, .big); // a reply
        std.mem.writeInt(u48, r[22..28], st.mac, .big);
        std.mem.writeInt(u32, r[28..32], st.ip, .big);
        @memcpy(r[32..42], a[8..18]); // the sender's MAC and IP addresses
        if (self.wire) |w| w.send_fn(w.ctx, &r);
        return true;
    }

    /// Answer the echo request `frame`, whose IPv4 header is `ihl` bytes.
    fn echoReply(self: *Eth, frame: []const u8, ihl: usize, st: Station) void {
        var r: [max_len]u8 = undefined;
        const out = r[0..frame.len];
        @memcpy(out, frame);
        @memcpy(out[0..6], frame[6..12]);
        std.mem.writeInt(u48, out[6..12], st.mac, .big);
        const ip = out[14..];
        @memcpy(ip[16..20], frame[14 + 12 ..][0..4]); // to the sender
        std.mem.writeInt(u32, ip[12..16], st.ip, .big);
        std.mem.writeInt(u16, ip[10..12], 0, .big);
        std.mem.writeInt(u16, ip[10..12], checksum(ip[0..ihl]), .big);
        const icmp = ip[ihl..];
        icmp[0] = 0; // an echo reply
        std.mem.writeInt(u16, icmp[2..4], 0, .big);
        std.mem.writeInt(u16, icmp[2..4], checksum(icmp), .big);
        if (self.wire) |w| w.send_fn(w.ctx, out);
    }
};

/// The Internet checksum of `bytes` (RFC 1071).
pub fn checksum(bytes: []const u8) u16 {
    var sum: u32 = 0;
    var i: usize = 0;
    while (i + 1 < bytes.len) : (i += 2) sum += std.mem.readInt(u16, bytes[i..][0..2], .big);
    if (i < bytes.len) sum += @as(u32, bytes[i]) << 8;
    while (sum > 0xFFFF) sum = (sum & 0xFFFF) + (sum >> 16);
    return ~@as(u16, @truncate(sum));
}

/// Put `frame` into `words` as SYSTEM §7 has it: from byte 2, big-endian,
/// with 0 in the other bytes.
pub fn toWords(frame: []const u8, words: *[buf_words]u32) void {
    @memset(words, 0);
    for (frame, 2..) |b, k| words[k / 4] |= @as(u32, b) << @intCast(24 - 8 * (k % 4));
}

/// The first `len` bytes of the frame in `words`, put into `out`.
pub fn fromWords(words: *const [buf_words]u32, len: usize, out: []u8) []const u8 {
    for (out[0..len], 2..) |*b, k| b.* = @truncate(words[k / 4] >> @intCast(24 - 8 * (k % 4)));
    return out[0..len];
}

/// Write `frame` as a line of --eth-out: each byte as two hex digits, with
/// a space between bytes.
pub fn writeLine(w: *std.Io.Writer, frame: []const u8) std.Io.Writer.Error!void {
    for (frame, 0..) |b, i| {
        if (i != 0) try w.writeByte(' ');
        try w.print("{x:0>2}", .{b});
    }
    try w.writeByte('\n');
}

pub const ParseError = error{ Parse, OutOfMemory };

/// Parse the text of an --eth-in file (SYSTEM §7). An error is printed with
/// `path` and the line's number.
pub fn parseLines(arena: std.mem.Allocator, path: []const u8, text: []const u8) ParseError![]const Line {
    var lines: std.ArrayList(Line) = .empty;
    var it = std.mem.splitScalar(u8, text, '\n');
    var line_no: usize = 0;
    while (it.next()) |raw| {
        line_no += 1;
        var s = raw;
        if (std.mem.indexOfScalar(u8, s, '#')) |c| s = s[0..c];
        s = std.mem.trim(u8, s, " \t\r");
        if (s.len == 0) continue;
        var after: u64 = 0;
        if (std.mem.indexOfScalar(u8, s, ':')) |c| {
            const n = std.mem.trim(u8, s[0..c], " \t");
            // parseInt would also take a sign and underscores.
            const digits = n.len != 0 and for (n) |d| {
                if (!std.ascii.isDigit(d)) break false;
            } else true;
            if (!digits) return parseError(path, line_no, "'{s}' is not a decimal count of frames", .{n});
            after = std.fmt.parseInt(u64, n, 10) catch
                return parseError(path, line_no, "'{s}' is larger than {d}", .{ n, std.math.maxInt(u64) });
            s = s[c + 1 ..];
        }
        var bytes: std.ArrayList(u8) = .empty;
        var digits: [2]u8 = undefined;
        var have: usize = 0;
        for (s) |c| {
            if (c == ' ' or c == '\t' or c == '\r') {
                if (have == 1) return parseError(path, line_no, "a byte has one hex digit", .{});
                continue;
            }
            if (!std.ascii.isHex(c)) return parseError(path, line_no, "'{c}' is not a hex digit", .{c});
            digits[have] = c;
            have += 1;
            if (have == 2) {
                try bytes.append(arena, std.fmt.parseInt(u8, &digits, 16) catch unreachable);
                have = 0;
            }
        }
        if (have == 1) return parseError(path, line_no, "a byte has one hex digit", .{});
        if (bytes.items.len < min_len or bytes.items.len > max_len)
            return parseError(path, line_no, "a frame has 14 to 1514 bytes, not {d}", .{bytes.items.len});
        try lines.append(arena, .{ .after = after, .frame = bytes.items });
    }
    return lines.items;
}

fn parseError(path: []const u8, line_no: usize, comptime fmt: []const u8, args: anytype) error{Parse} {
    // Quiet in the unit tests, whose runner takes output for a failure.
    if (!@import("builtin").is_test) std.debug.print("{s}:{d}: error: " ++ fmt ++ "\n", .{ path, line_no } ++ args);
    return error.Parse;
}

// The tests

const testing = std.testing;

const test_st: Station = .{ .ip = 0xC0A8_0141, .mac = 0x024E_4943_4500, .tcp_port = 4510 };

/// A Wire that keeps the frames sent.
const Sink = struct {
    frames: std.ArrayList([]u8) = .empty,

    fn send(ctx: *anyopaque, frame: []const u8) void {
        const self: *Sink = @ptrCast(@alignCast(ctx));
        self.frames.append(testing.allocator, testing.allocator.dupe(u8, frame) catch unreachable) catch unreachable;
    }

    fn wire(self: *Sink) Wire {
        return .{ .ctx = self, .send_fn = send };
    }

    fn deinit(self: *Sink) void {
        for (self.frames.items) |f| testing.allocator.free(f);
        self.frames.deinit(testing.allocator);
    }
};

/// A frame of `len` bytes to `dest`, from 02:00:00:00:00:01, with the
/// EtherType 0x88B5, the local experimental one, and byte i of the
/// payload `fill` + i.
fn testFrame(buf: []u8, dest: u48, len: usize, fill: u8) []const u8 {
    std.mem.writeInt(u48, buf[0..6], dest, .big);
    std.mem.writeInt(u48, buf[6..12], 0x0200_0000_0001, .big);
    std.mem.writeInt(u16, buf[12..14], 0x88B5, .big);
    for (buf[14..len], 0..) |*b, i| b.* = fill +% @as(u8, @truncate(i));
    return buf[0..len];
}

test "the layout of a frame in the buffer (SYSTEM §7)" {
    var words: [buf_words]u32 = undefined;
    var buf: [max_len]u8 = undefined;
    const f = testFrame(&buf, test_st.mac, 60, 0x10);
    toWords(f, &words);
    try testing.expectEqual(0x0000_024E, words[0]); // as NET_MAC_HI
    try testing.expectEqual(0x4943_4500, words[1]); // as NET_MAC_LO
    try testing.expectEqual(0x0200_0000, words[2]);
    try testing.expectEqual(0x0001_88B5, words[3]);
    try testing.expectEqual(0x1011_1213, words[4]);
    try testing.expectEqual(0x3C3D_0000, words[15]); // bytes 60 and 61 of the buffer are not the frame's
    var out: [max_len]u8 = undefined;
    try testing.expectEqualSlices(u8, f, fromWords(&words, f.len, &out));
}

test "the queue: enable, receive, release, drop, and disable (SYSTEM §7)" {
    var eth: Eth = .{};
    var buf: [max_len]u8 = undefined;
    eth.receive(testFrame(&buf, test_st.mac, 60, 0), test_st);
    try testing.expectEqual(0, eth.read(1)); // not enabled: dropped, not counted
    try testing.expectEqual(0, eth.read(4));
    eth.write(0, 1, test_st);
    try testing.expectEqual(1, eth.read(0));
    for (0..6) |n| eth.receive(testFrame(&buf, if (n == 5) broadcast else test_st.mac, 60 + n, @intCast(n)), test_st);
    eth.receive(testFrame(&buf, 0x0200_0000_0099, 60, 0), test_st); // another MAC address: not counted
    try testing.expectEqual(0b11, eth.read(0));
    try testing.expectEqual(2, eth.read(4));
    for (0..4) |n| {
        try testing.expectEqual(60 + n, eth.read(1));
        try testing.expectEqual(0x0001_88B5, eth.read(11));
        eth.write(3, 0, test_st);
        eth.write(3, 1, test_st);
        // Word 8 is bytes 30 to 33 of the frame, 16 to 19 of the payload.
        try testing.expectEqual((n + 16) << 24 | (n + 17) << 16 | (n + 18) << 8 | (n + 19), eth.read(8));
        eth.write(3, 0, test_st);
        eth.write(1, 0, test_st);
    }
    try testing.expectEqual(0, eth.read(1));
    try testing.expectEqual(1, eth.read(0));
    eth.write(1, 0, test_st); // a release of nothing is ignored
    try testing.expectEqual(0, eth.read(1));
    eth.receive(testFrame(&buf, test_st.mac, 70, 0), test_st);
    eth.write(0, 0, test_st);
    try testing.expectEqual(0, eth.read(0));
    try testing.expectEqual(0, eth.read(1));
    try testing.expectEqual(0, eth.read(4));
}

test "the window: chunks, the select bit, and ignored writes (SYSTEM §7)" {
    var eth: Eth = .{};
    eth.write(3, 0x1FF, test_st); // bits 5..0 and 8 only
    try testing.expectEqual(0x13F, eth.read(3));
    eth.write(8, 0x1234, test_st); // chunk 63: ignored
    try testing.expectEqual(0, eth.read(8));
    eth.write(3, 0x100 | 47, test_st);
    eth.write(15, 0xDEAD_BEEF, test_st);
    try testing.expectEqual(0xDEAD_BEEF, eth.read(15));
    try testing.expectEqual(0xDEAD_BEEF, eth.tx[383]);
    eth.write(3, 47, test_st); // the queue's buffer: empty reads 0, writes ignored
    eth.write(15, 1, test_st);
    try testing.expectEqual(0, eth.read(15));
    try testing.expectEqual(0xDEAD_BEEF, eth.tx[383]);
    eth.reset();
    try testing.expectEqual(0, eth.read(3));
    try testing.expectEqual(0xDEAD_BEEF, eth.tx[383]); // a start keeps the send buffer
}

test "sending: the lengths, enabled, and the lines that wait for it (SYSTEM §7)" {
    var sink: Sink = .{};
    defer sink.deinit();
    var buf: [max_len]u8 = undefined;
    const lines = [_]Line{
        .{ .after = 0, .frame = testFrame(buf[0..100], test_st.mac, 60, 0) },
        .{ .after = 1, .frame = testFrame(buf[100..200], test_st.mac, 61, 0) },
        .{ .after = 1, .frame = testFrame(buf[200..300], test_st.mac, 62, 0) },
        .{ .after = 3, .frame = testFrame(buf[300..400], test_st.mac, 63, 0) },
    };
    var eth: Eth = .{ .wire = sink.wire(), .lines = &lines };
    eth.write(3, 0x100, test_st);
    eth.write(8, 0xAAAA_0102, test_st);
    eth.write(9, 0x0304_0506, test_st);
    eth.write(2, 14, test_st); // not enabled: nothing
    try testing.expectEqual(0, sink.frames.items.len);
    eth.write(0, 1, test_st); // line 1 arrives
    try testing.expectEqual(60, eth.read(1));
    for ([_]u32{ 13, 1515, 0, 0xFFFF_FFFF }) |n| eth.write(2, n, test_st);
    try testing.expectEqual(0, sink.frames.items.len);
    eth.write(2, 14, test_st); // lines 2 and 3 arrive
    try testing.expectEqual(1, sink.frames.items.len);
    try testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5, 6, 0, 0, 0, 0, 0, 0, 0, 0 }, sink.frames.items[0]);
    try testing.expectEqual(0b11, eth.read(0)); // busy never reads 1
    eth.write(1, 0, test_st);
    try testing.expectEqual(61, eth.read(1));
    eth.write(1, 0, test_st);
    try testing.expectEqual(62, eth.read(1));
    eth.write(2, 20, test_st);
    try testing.expectEqual(3, eth.next_line);
    eth.write(0, 0, test_st);
    eth.write(0, 1, test_st); // a new enable takes no line that waits
    try testing.expectEqual(0, eth.read(1));
    eth.write(2, 20, test_st);
    try testing.expectEqual(63, eth.read(1));
    try testing.expectEqual(3, eth.sent);
}

test "the station: ARP, ping, the link's TCP, and an IP address of 0 (SYSTEM §6, §7)" {
    var sink: Sink = .{};
    defer sink.deinit();
    var eth: Eth = .{ .wire = sink.wire() };
    eth.write(0, 1, test_st);
    // An ARP request from 192.168.1.10 at 02:00:00:00:00:01.
    const arp = [_]u8{
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x02, 0, 0, 0, 0, 1, 0x08, 0x06,
        0,    1,    0x08, 0x00, 6,    4,    0,    1, 0x02, 0, 0, 0, 0, 1,
        192,  168,  1,    10,   0,    0,    0,    0, 0,    0, 192, 168, 1, 65,
    };
    eth.receive(&arp, test_st);
    try testing.expectEqual(0, eth.read(1));
    try testing.expectEqualSlices(u8, &.{
        0x02, 0,    0,    0,    0,    1,    0x02, 0x4E, 0x49, 0x43, 0x45, 0, 0x08, 0x06,
        0,    1,    0x08, 0x00, 6,    4,    0,    2,    0x02, 0x4E, 0x49, 0x43, 0x45, 0,
        192,  168,  1,    65,   0x02, 0,    0,    0,    0,    1,    192,  168, 1,    10,
    }, sink.frames.items[0]);
    // The same request for another address goes to the program.
    var other = arp;
    other[41] = 66;
    eth.receive(&other, test_st);
    try testing.expectEqual(42, eth.read(1));
    eth.write(1, 0, test_st);
    // A ping from 192.168.1.10, with 4 bytes of data.
    var ping = [_]u8{
        0x02, 0x4E, 0x49, 0x43, 0x45, 0,    0x02, 0, 0, 0, 0, 1, 0x08, 0x00,
        0x45, 0,    0,    32,   0,    1,    0,    0, 64, 1, 0, 0, 192, 168,
        1,    10,   192,  168,  1,    65,   8,    0, 0, 0, 0x12, 0x34, 0, 1,
        0xDE, 0xAD, 0xBE, 0xEF,
    };
    std.mem.writeInt(u16, ping[24..26], checksum(ping[14..34]), .big);
    std.mem.writeInt(u16, ping[36..38], checksum(ping[34..]), .big);
    eth.receive(&ping, test_st);
    try testing.expectEqual(0, eth.read(1));
    const r = sink.frames.items[1];
    try testing.expectEqual(ping.len, r.len);
    try testing.expectEqualSlices(u8, ping[6..12], r[0..6]);
    try testing.expectEqualSlices(u8, &.{ 192, 168, 1, 65, 192, 168, 1, 10 }, r[26..34]);
    try testing.expectEqual(0, r[34]);
    try testing.expectEqual(0, checksum(r[14..34]));
    try testing.expectEqual(0, checksum(r[34..]));
    try testing.expectEqualSlices(u8, ping[38..], r[38..]);
    // TCP to the link's port is the host's; to another port, the program's.
    var tcp = ping;
    tcp[23] = 6;
    std.mem.writeInt(u16, tcp[36..38], 4510, .big);
    eth.receive(&tcp, test_st);
    try testing.expectEqual(0, eth.read(1));
    std.mem.writeInt(u16, tcp[36..38], 80, .big);
    eth.receive(&tcp, test_st);
    try testing.expectEqual(46, eth.read(1));
    eth.write(1, 0, test_st);
    // With an IP address of 0, the station serves nothing.
    var st0 = test_st;
    st0.ip = 0;
    eth.receive(&arp, st0);
    eth.receive(&ping, st0);
    try testing.expectEqual(2, eth.count);
    try testing.expectEqual(2, sink.frames.items.len);
}

test "parseLines: counts, comments, and errors" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text =
        \\# a comment
        \\ffffffffffff 020000000001 88b5   # 14 bytes
        \\
        \\3: ff ff ff ff ff ff 02 00 00 00 00 01 88 b5 00
    ;
    const lines = try parseLines(a, "t", text);
    try testing.expectEqual(2, lines.len);
    try testing.expectEqual(0, lines[0].after);
    try testing.expectEqual(14, lines[0].frame.len);
    try testing.expectEqual(3, lines[1].after);
    try testing.expectEqual(15, lines[1].frame.len);
    try testing.expectError(error.Parse, parseLines(a, "t", "ff ff ff ff ff ff ff ff ff ff ff ff ff"));
    try testing.expectError(error.Parse, parseLines(a, "t", "ffffffffffff020000000001 88b 5"));
    try testing.expectError(error.Parse, parseLines(a, "t", "x: ffffffffffff02000000000188b5"));
    try testing.expectError(error.Parse, parseLines(a, "t", "+1: ffffffffffff02000000000188b5"));
    try testing.expectError(error.Parse, parseLines(a, "t", "1_0: ffffffffffff02000000000188b5"));
    try testing.expectError(error.Parse, parseLines(a, "t", ": ffffffffffff02000000000188b5"));
    try testing.expectError(error.Parse, parseLines(a, "t", "ffffffffffff02000000000188g5"));
}
