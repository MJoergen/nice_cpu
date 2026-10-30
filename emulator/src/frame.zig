//! The frame of the window (doc/SYSTEM.md §1): the character screen drawn
//! with the font, in the colors of its words, with the cursor. It needs no
//! SDL, so its tests run in every build.

const std = @import("std");
const font = @import("font.zig");

/// The character screen (doc/SYSTEM.md §1), in characters and in pixels.
pub const cols = 80;
pub const rows = 25;
pub const cells = cols * rows;
pub const width = cols * font.width;
pub const height = rows * font.height;

/// A color as 8-bit R, G, and B.
pub const Rgb = [3]u8;

/// The background color of a screen word, from bits 31..20. Each 4-bit
/// component n becomes the byte n * 0x11, so 0xF is full intensity.
pub fn background(w: u32) Rgb {
    return .{ nibble(w, 28), nibble(w, 24), nibble(w, 20) };
}

/// The foreground color of a screen word, from bits 19..8. The 2004 IDE
/// inverts these components, so that 0x0 is full intensity; `invert` does the
/// same. Without it, 0xF is full intensity.
pub fn foreground(w: u32, invert: bool) Rgb {
    const x: u32 = if (invert) 0xFFF00 else 0;
    return .{ nibble(w ^ x, 16), nibble(w ^ x, 12), nibble(w ^ x, 8) };
}

fn nibble(w: u32, shift: u5) u8 {
    return @as(u8, @as(u4, @truncate(w >> shift))) * 0x11;
}

/// A color as a pixel of SDL's ARGB8888, opaque.
fn pixel(c: Rgb) u32 {
    return 0xFF00_0000 | @as(u32, c[0]) << 16 | @as(u32, c[1]) << 8 | c[2];
}

/// The cursor's registers (doc/SYSTEM.md §1): the state, the column, and
/// the row, from `cursor_base`.
pub const cursor_base: u32 = 0xFFFF_FF80;
pub const cursor_show: u32 = 1 << 6;
pub const cursor_blink: u32 = 1 << 5;
pub const cursor_small: u32 = 1 << 4;

/// The lines of the character that a small cursor covers, at its bottom.
const small_lines = 4;

pub const Cursor = struct {
    state: u32 = 0,
    col: u32 = 0,
    row: u32 = 0,

    /// The cell of the cursor and its look, or null when it is not shown:
    /// it is off, it blinks and `blink_on` is false, or it is out of range.
    fn at(self: Cursor, blink_on: bool) ?struct { cell: usize, look: Look } {
        if (self.state & cursor_show == 0) return null;
        if (self.state & cursor_blink != 0 and !blink_on) return null;
        if (self.col >= cols or self.row >= rows) return null;
        return .{
            .cell = self.row * cols + self.col,
            .look = if (self.state & cursor_small != 0) .small else .full,
        };
    }
};

/// How a cell shows the cursor.
const Look = enum(u2) { none, full, small };

pub const Frame = struct {
    /// The pixels of the window, `width` per line, the top line first.
    pixels: []u32,
    /// Invert the foreground, as `--invert-fg` does.
    invert: bool,
    /// What each cell shows: its word, and the look of the cursor in bits
    /// 33..32. All ones before the first draw, which no cell can show.
    shown: [cells]u64,

    pub fn init(gpa: std.mem.Allocator, invert: bool) !Frame {
        return .{
            .pixels = try gpa.alloc(u32, width * height),
            .invert = invert,
            .shown = @splat(std.math.maxInt(u64)),
        };
    }

    pub fn deinit(self: *Frame, gpa: std.mem.Allocator) void {
        gpa.free(self.pixels);
    }

    /// Draw the cells whose word or cursor has changed since the last draw,
    /// and return whether any had.
    pub fn draw(self: *Frame, words: *const [cells]u32, cursor: Cursor, blink_on: bool) bool {
        const cur = cursor.at(blink_on);
        var changed = false;
        for (words, &self.shown, 0..) |w, *shown, i| {
            const look: Look = if (cur != null and cur.?.cell == i) cur.?.look else .none;
            const now = @as(u64, @backingInt(look)) << 32 | w;
            if (now == shown.*) continue;
            shown.* = now;
            self.drawCell(i, w, look);
            changed = true;
        }
        return changed;
    }

    /// Draw one cell. The cursor swaps the colors of its lines.
    fn drawCell(self: *Frame, i: usize, w: u32, look: Look) void {
        const bg = pixel(background(w));
        const fg = pixel(foreground(w, self.invert));
        const glyph = &font.glyphs[@as(u8, @truncate(w))];
        const x0 = i % cols * font.width;
        const y0 = i / cols * font.height;
        for (glyph, 0..) |bits, y| {
            const swap = switch (look) {
                .none => false,
                .full => true,
                .small => y >= font.height - small_lines,
            };
            const on = if (swap) bg else fg;
            const off = if (swap) fg else bg;
            const line = self.pixels[(y0 + y) * width + x0 ..][0..font.width];
            for (line, 0..) |*p, x| {
                p.* = if (bits & (@as(u16, 0x8000) >> @intCast(x)) != 0) on else off;
            }
        }
    }
};

const testing = std.testing;

const red: u32 = 0xFFFF_0000;
const white: u32 = 0xFFFF_FFFF;
const black: u32 = 0xFF00_0000;

fn at(f: *const Frame, x: usize, y: usize) u32 {
    return f.pixels[y * width + x];
}

test "screen colors" {
    // No inversion: 0 is no intensity, 0xF is full.
    try testing.expectEqual(Rgb{ 0, 0, 0 }, background(0x000FFF41));
    try testing.expectEqual(Rgb{ 0xFF, 0xFF, 0xFF }, foreground(0x000FFF41, false));
    try testing.expectEqual(Rgb{ 0x11, 0x22, 0xEE }, background(0x12E00000));
    try testing.expectEqual(Rgb{ 0x00, 0x77, 0xAA }, foreground(0x00007A41, false));
    // Inverted, the foreground is 0xF - n, and the rest of the word is not
    // touched.
    try testing.expectEqual(Rgb{ 0xFF, 0x88, 0x55 }, foreground(0x00007A41, true));
    try testing.expectEqual(Rgb{ 0, 0, 0 }, foreground(0x000FFF41, true));
    try testing.expectEqual(0xFF11_22EE, pixel(background(0x12E00000)));
}

test "a character is drawn in its colors" {
    var f = try Frame.init(testing.allocator, false);
    defer f.deinit(testing.allocator);
    var words: [cells]u32 = @splat(0);
    // A white A on red at the top left, and a white B on black at row 1,
    // column 2, as in NiceMonMEGA65's SYSTEM.md.
    words[0] = 0xF00FFF41;
    words[cols + 2] = 0x000FFF42;
    try testing.expect(f.draw(&words, .{}, true));
    // Line 6 of Spleen's A is 0x0FF0: pixels 4 to 11 are set.
    try testing.expectEqual(red, at(&f, 0, 0));
    try testing.expectEqual(red, at(&f, 3, 6));
    try testing.expectEqual(white, at(&f, 4, 6));
    try testing.expectEqual(white, at(&f, 11, 6));
    try testing.expectEqual(red, at(&f, 12, 6));
    // Line 6 of B is 0x3FF0: pixels 2 to 11, here from x = 32, y = 32.
    try testing.expectEqual(black, at(&f, 33, 38));
    try testing.expectEqual(white, at(&f, 34, 38));
    // The cell between them, word 0, is black on black.
    try testing.expectEqual(black, at(&f, 16, 6));
    // The last pixel of the frame.
    try testing.expectEqual(black, at(&f, width - 1, height - 1));
}

test "the foreground is inverted with invert" {
    var f = try Frame.init(testing.allocator, true);
    defer f.deinit(testing.allocator);
    var words: [cells]u32 = @splat(0);
    // In the 2004 layout, 0x41 alone is white on black.
    words[0] = 0x41;
    _ = f.draw(&words, .{}, true);
    try testing.expectEqual(black, at(&f, 3, 6));
    try testing.expectEqual(white, at(&f, 4, 6));
}

test "the cursor swaps the colors, all lines or the bottom 4" {
    var f = try Frame.init(testing.allocator, false);
    defer f.deinit(testing.allocator);
    // Spaces, white on black: with the cursor, a white cell.
    var words: [cells]u32 = @splat(0x000FFF20);
    _ = f.draw(&words, .{ .state = cursor_show, .col = 1, .row = 2 }, true);
    try testing.expectEqual(black, at(&f, 15, 64));
    try testing.expectEqual(white, at(&f, 16, 64));
    try testing.expectEqual(white, at(&f, 31, 95));
    try testing.expectEqual(black, at(&f, 32, 95));
    // Small: lines 28 to 31 of the cell, y = 92 to 95.
    _ = f.draw(&words, .{ .state = cursor_show | cursor_small, .col = 1, .row = 2 }, true);
    try testing.expectEqual(black, at(&f, 16, 64));
    try testing.expectEqual(black, at(&f, 16, 91));
    try testing.expectEqual(white, at(&f, 16, 92));
    try testing.expectEqual(white, at(&f, 31, 95));
}

test "the cursor is not shown when off, in a blink, or out of range" {
    const c: Cursor = .{ .state = cursor_show, .col = 79, .row = 24 };
    try testing.expect(c.at(false) != null);
    try testing.expectEqual(cells - 1, c.at(false).?.cell);
    try testing.expect((Cursor{ .state = 0xFFFF_FFBF, .col = 0, .row = 0 }).at(true) == null);
    try testing.expect((Cursor{ .state = cursor_show | cursor_blink }).at(false) == null);
    try testing.expect((Cursor{ .state = cursor_show | cursor_blink }).at(true) != null);
    try testing.expect((Cursor{ .state = cursor_show, .col = 80, .row = 0 }).at(true) == null);
    try testing.expect((Cursor{ .state = cursor_show, .col = 0, .row = 25 }).at(true) == null);
}

test "a draw redraws only the cells that changed" {
    var f = try Frame.init(testing.allocator, false);
    defer f.deinit(testing.allocator);
    var words: [cells]u32 = @splat(0);
    try testing.expect(f.draw(&words, .{}, true));
    try testing.expect(!f.draw(&words, .{}, true));
    // Mark a pixel of cell 0, then change cell 1: cell 0 is not redrawn.
    f.pixels[0] = 0x1234_5678;
    words[1] = 0xF00FFF41;
    try testing.expect(f.draw(&words, .{}, true));
    try testing.expectEqual(0x1234_5678, f.pixels[0]);
    try testing.expectEqual(white, at(&f, 20, 6));
    // A cursor that moves onto a cell redraws it.
    try testing.expect(f.draw(&words, .{ .state = cursor_show }, true));
    try testing.expectEqual(black, f.pixels[0]);
    // The blink turns it off again.
    try testing.expect(f.draw(&words, .{ .state = cursor_show | cursor_blink }, false));
    try testing.expect(!f.draw(&words, .{ .state = cursor_show | cursor_blink }, false));
}
