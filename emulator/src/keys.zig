//! The bytes of the window's keys (doc/SYSTEM.md §1), as xterm sends them.
//! It needs no SDL, so its tests run in every build.

const std = @import("std");
const Input = @import("cpu.zig").Input;

/// The keys that do not type a character.
pub const Key = enum { enter, backspace, delete, tab, escape, up, down, right, left, f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12 };

/// The bytes of a key.
pub fn bytes(key: Key) []const u8 {
    return switch (key) {
        .enter => "\r",
        .backspace, .delete => "\x7f",
        .tab => "\t",
        .escape => "\x1b",
        .up => "\x1b[A",
        .down => "\x1b[B",
        .right => "\x1b[C",
        .left => "\x1b[D",
        .f1 => "\x1bOP",
        .f2 => "\x1bOQ",
        .f3 => "\x1bOR",
        .f4 => "\x1bOS",
        .f5 => "\x1b[15~",
        .f6 => "\x1b[17~",
        .f7 => "\x1b[18~",
        .f8 => "\x1b[19~",
        .f9 => "\x1b[20~",
        .f10 => "\x1b[21~",
        .f11 => "\x1b[23~",
        .f12 => "\x1b[24~",
    };
}

/// The control code of Ctrl with a letter, or null for another character.
pub fn ctrl(c: u8) ?u8 {
    return switch (c) {
        'a'...'z' => c - 'a' + 1,
        'A'...'Z' => c - 'A' + 1,
        else => null,
    };
}

/// Whether a byte of typed text is passed on: printable ASCII. The bytes of
/// a character outside ASCII are all 0x80 or more in UTF-8, so dropping
/// those drops the character.
pub fn typed(b: u8) bool {
    return b >= 0x20 and b < 0x7F;
}

/// The console's input with the window: the bytes of `--input`, if given,
/// and then the keys typed. It has no end, so a read returns 0 while no
/// byte is waiting (doc/SYSTEM.md §1).
pub const Queue = struct {
    file: ?*std.Io.Reader,
    buf: [size]u8 = undefined,
    head: usize = 0,
    len: usize = 0,

    pub const size = 2048;

    /// Queue the bytes of a key, or drop the key if they do not all fit.
    pub fn push(self: *Queue, b: []const u8) void {
        if (b.len > size - self.len) return;
        for (b) |c| {
            self.buf[(self.head + self.len) % size] = c;
            self.len += 1;
        }
    }

    pub fn input(self: *Queue) Input {
        return .{ .ctx = self, .next_fn = next };
    }

    fn next(ctx: *anyopaque) Input.Next {
        const self: *Queue = @ptrCast(@alignCast(ctx));
        if (self.file) |r| {
            if (r.takeByte()) |b| return .{ .byte = b } else |_| self.file = null;
        }
        if (self.len == 0) return .none;
        const b = self.buf[self.head];
        self.head = (self.head + 1) % size;
        self.len -= 1;
        return .{ .byte = b };
    }
};

const testing = std.testing;

test "the bytes of the keys, as in SYSTEM.md" {
    try testing.expectEqualStrings("\x0d", bytes(.enter));
    try testing.expectEqualStrings("\x7f", bytes(.backspace));
    try testing.expectEqualStrings("\x7f", bytes(.delete));
    try testing.expectEqualStrings("\x09", bytes(.tab));
    try testing.expectEqualStrings("\x1b", bytes(.escape));
    try testing.expectEqualStrings("\x1b\x5b\x41", bytes(.up));
    try testing.expectEqualStrings("\x1b\x5b\x42", bytes(.down));
    try testing.expectEqualStrings("\x1b\x5b\x43", bytes(.right));
    try testing.expectEqualStrings("\x1b\x5b\x44", bytes(.left));
    try testing.expectEqualStrings("\x1b\x4f\x50", bytes(.f1));
    try testing.expectEqualStrings("\x1b\x4f\x53", bytes(.f4));
    try testing.expectEqualStrings("\x1b\x5b\x31\x35\x7e", bytes(.f5));
    try testing.expectEqualStrings("\x1b\x5b\x31\x37\x7e", bytes(.f6));
    try testing.expectEqualStrings("\x1b\x5b\x32\x31\x7e", bytes(.f10));
    try testing.expectEqualStrings("\x1b\x5b\x32\x33\x7e", bytes(.f11));
    try testing.expectEqualStrings("\x1b\x5b\x32\x34\x7e", bytes(.f12));
}

test "Ctrl with a letter gives its control code" {
    try testing.expectEqual(0x01, ctrl('a'));
    try testing.expectEqual(0x03, ctrl('c'));
    try testing.expectEqual(0x03, ctrl('C'));
    try testing.expectEqual(0x1A, ctrl('z'));
    try testing.expectEqual(null, ctrl('1'));
    try testing.expectEqual(null, ctrl('['));
}

test "typed text passes printable ASCII only" {
    try testing.expect(typed(' '));
    try testing.expect(typed('A'));
    try testing.expect(typed('~'));
    try testing.expect(!typed(0x7F));
    try testing.expect(!typed('\n'));
    // The two bytes of "é" in UTF-8.
    try testing.expect(!typed(0xC3));
    try testing.expect(!typed(0xA9));
}

test "the queue gives the file, then the keys, and never ends" {
    var r: std.Io.Reader = .fixed("ab");
    var q: Queue = .{ .file = &r };
    const in = q.input();
    q.push("c");
    try testing.expectEqual(Input.Next{ .byte = 'a' }, in.next());
    try testing.expectEqual(Input.Next{ .byte = 'b' }, in.next());
    try testing.expectEqual(Input.Next{ .byte = 'c' }, in.next());
    try testing.expectEqual(Input.Next.none, in.next());
    q.push(bytes(.up));
    try testing.expectEqual(Input.Next{ .byte = 0x1b }, in.next());
    try testing.expectEqual(Input.Next{ .byte = '[' }, in.next());
    try testing.expectEqual(Input.Next{ .byte = 'A' }, in.next());
    try testing.expectEqual(Input.Next.none, in.next());
}

test "a key that does not fit in the queue is dropped whole" {
    var q: Queue = .{ .file = null };
    for (0..Queue.size - 2) |_| q.push("x");
    q.push(bytes(.up));
    try testing.expectEqual(Queue.size - 2, q.len);
    q.push("\r");
    q.push("\r");
    try testing.expectEqual(Queue.size, q.len);
    q.push("y");
    try testing.expectEqual(Queue.size, q.len);
    // The ring wraps: take one, and one more fits, at the start of buf.
    const in = q.input();
    try testing.expectEqual(Input.Next{ .byte = 'x' }, in.next());
    q.push("z");
    try testing.expectEqual('z', q.buf[0]);
}
