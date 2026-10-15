//! Support for Zig code that reaches NICE through wasm: the device routines
//! of ISA.md §9.3, which are imports from env and so the routines of
//! lib.nasm, and the `nice` imports of ISA.md §9.4. It is the Zig
//! counterpart of the C library's nice.h, with a console writer for
//! std.fmt. Build with `--dep nice -Mroot=prog.zig -Mnice=nice.zig` and
//! `const nice = @import("nice");`.
const std = @import("std");

/// Reads the NICE word at a word address.
pub extern "nice" fn peek(addr: u32) u32;
/// Writes val to the NICE word at a word address.
pub extern "nice" fn poke(addr: u32, val: u32) void;

// The device routines of ISA.md §9.3. nice_print is left out: it takes a
// string of one character per word, and wasm strings are bytes.
extern "env" fn nice_putc(c: i32) void;
extern "env" fn nice_getc() i32;
extern "env" fn nice_pollc() i32;
extern "env" fn nice_cycles() u64;
extern "env" fn nice_instructions() u64;
extern "env" fn nice_screen_put(col: i32, row: i32, c: i32) void;
extern "env" fn nice_screen_clear() void;

/// Writes c to the console.
pub fn putc(c: u8) void {
    nice_putc(c);
}

/// Writes the bytes of s to the console.
pub fn write(s: []const u8) void {
    for (s) |c| nice_putc(c);
}

/// Waits for the next input byte. Returns null once the emulator's input
/// has ended, which a UART's input never does.
pub fn getc() ?u8 {
    const c = nice_getc();
    return if (c < 0) null else @intCast(c);
}

/// What pollc found: a byte, no byte yet, or the end of the input.
pub const Poll = union(enum) { byte: u8, empty, end };

/// Reads the console once, without waiting.
pub fn pollc() Poll {
    const c = nice_pollc();
    if (c >= 0) return .{ .byte = @intCast(c) };
    return if (c == -2) .empty else .end;
}

/// The performance counters of ISA.md §8.5: the clock cycles and the
/// instructions since reset. An interrupt routine must not read them while
/// the code it interrupted is reading one.
pub fn cycles() u64 {
    return nice_cycles();
}

pub fn instructions() u64 {
    return nice_instructions();
}

/// The emulator's character screen.
pub const screen_cols = 80;
pub const screen_rows = 25;

/// Writes c, the character in bits 7..0 and its colour above, to a column,
/// 0 to 79, of a row, 0 to 24.
pub fn screenPut(col: u32, row: u32, c: u32) void {
    nice_screen_put(@bitCast(col), @bitCast(row), @bitCast(c));
}

/// Writes a blank, 0x20, to every word of the screen.
pub fn screenClear() void {
    nice_screen_clear();
}

fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
    write(w.buffered());
    w.end = 0;
    var n: usize = 0;
    for (data[0 .. data.len - 1]) |d| {
        write(d);
        n += d.len;
    }
    const last = data[data.len - 1];
    for (0..splat) |_| write(last);
    return n + last.len * splat;
}

/// A writer for the console, with no buffer, so that std.fmt can print
/// through it, as print does.
pub var writer: std.Io.Writer = .{ .vtable = &.{ .drain = drain }, .buffer = &.{} };

/// Prints on the console with std.fmt.
pub fn print(comptime fmt: []const u8, args: anytype) void {
    writer.print(fmt, args) catch {};
}
