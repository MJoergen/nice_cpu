//! Support for Zig code that reaches NICE through wasm: the `nice` imports
//! of ISA.md §9.4, the console of ISA.md §8.3, and the performance counters
//! of ISA.md §8.5. It is the Zig counterpart of the C library's nice.h and
//! console code. Build with `--dep nice -Mroot=prog.zig -Mnice=nice.zig`
//! and `const nice = @import("nice");`.
const std = @import("std");

/// Reads the NICE word at a word address.
pub extern "nice" fn peek(addr: u32) u32;
/// Writes val to the NICE word at a word address.
pub extern "nice" fn poke(addr: u32, val: u32) void;

/// The console. Each write prints bits 7..0 of the word. A read returns the
/// next input byte with console_byte set, 0 if no byte is there yet, or
/// console_end once the emulator's input ended.
pub const console: u32 = 0xFFFFFF00;
pub const console_byte: u32 = 0x100;
pub const console_end: u32 = 0x200;

/// The address of each performance counter's low word. Read them with
/// counter64.
pub const cycle_lo: u32 = 0xFFFFFF10;
pub const instr_lo: u32 = 0xFFFFFF12;

/// Prints the bytes of s on the console.
pub fn write(s: []const u8) void {
    for (s) |c| poke(console, c);
}

/// Waits for the next input byte. Returns null once the emulator's input
/// has ended, which a UART's input never does.
pub fn getchar() ?u8 {
    while (true) {
        const v = peek(console);
        if (v & console_byte != 0) return @truncate(v);
        if (v & console_end != 0) return null;
    }
}

/// Reads the 64-bit performance counter whose low word is at lo, such as
/// cycle_lo: the low word first, which takes a snapshot of the high word,
/// and then the high word at lo + 1.
pub fn counter64(lo: u32) u64 {
    const low = peek(lo);
    return @as(u64, peek(lo + 1)) << 32 | low;
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
