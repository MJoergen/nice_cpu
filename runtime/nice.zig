//! Support for Zig code that reaches NICE through wasm: the device routines
//! of ABI.md, which are imports from env and so the routines of
//! lib.nasm, and the `nice` imports of WASM.md. It is the Zig
//! counterpart of the C library's nice.h, with a console writer for
//! std.fmt, and a heap, `nice.heap`, a std.mem.Allocator. Build with
//! `--dep nice -Mroot=prog.zig -Mnice=nice.zig` and
//! `const nice = @import("nice");`.
const std = @import("std");

/// Reads the NICE word at a word address.
pub extern "nice" fn peek(addr: u32) u32;
/// Writes val to the NICE word at a word address.
pub extern "nice" fn poke(addr: u32, val: u32) void;
// The end of the linear memory in bytes, and memory.grow, also where only
// its start is reserved, which has no page count (WASM.md). The heap uses
// them.
extern "nice" fn heap_end() u32;
extern "nice" fn grow(pages: i32) i32;

// The device routines of ABI.md. nice_print is left out: it takes a
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

/// Waits for the next input byte. Returns null once the line's input has
/// ended: the emulator's stdin or the host of the debug link. A keyboard's
/// bytes may still come after that (DEVICES.md §1).
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

/// Whether the last line that readLine read ended at a "\r", whose "\n",
/// if one comes, the next call drops.
var after_cr = false;

/// Reads a line of console input into buf and returns it, without its end:
/// "\n", "\r", the Enter key (DEVICES.md §1), or "\r\n". A line longer
/// than buf is cut off: its first buf.len bytes are returned, and the rest
/// is read and dropped. A last line with no end before the end of the
/// input is returned too. Returns null once the input has ended with no
/// byte read. After a "\r" it does not wait for a "\n", which a keyboard
/// never sends: the next call drops it.
pub fn readLine(buf: []u8) ?[]u8 {
    var n: usize = 0;
    var cut = false;
    var next = getc();
    if (after_cr and next != null and next.? == '\n') next = getc();
    after_cr = false;
    while (next) |c| : (next = getc()) {
        if (c == '\n') break;
        if (c == '\r') {
            after_cr = true;
            break;
        }
        if (n < buf.len) {
            buf[n] = c;
            n += 1;
        } else cut = true;
    } else if (n == 0 and !cut) return null;
    return buf[0..n];
}

/// The performance counters of DEVICES.md §3: the clock cycles and the
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
/// The blank that screenClear writes: a space in white on black, the
/// colors a board's monitor writes in, so that a cursor, which swaps the
/// colors of its cell, shows on it (doc/DEVICES.md §1.4).
pub const screen_blank: u32 = fg_white | bg_black | ' ';

/// The screen's mode word (doc/DEVICES.md §1.10): poke mode_chunky to it
/// and peek it back, to find out whether the system has 160x100 pixels,
/// one word each at 0xFFFF0000 + 160 * y + x, colored as a bg_* color.
pub const screen_mode: u32 = 0xFFFFFF87;
pub const mode_text: u32 = 0;
pub const mode_chunky: u32 = 1;
pub const pixel_cols = 160;
pub const pixel_rows = 100;

/// The colors of a screen word (doc/DEVICES.md §1.1): fg_* in bits 19..8, the
/// foreground, and bg_* in bits 31..20, the background. A color is a
/// foreground, a background, and a character or-ed, and a color left out is
/// black: fg_yellow | bg_blue | 'A'. nice.h, nice.rs, and colors.nasm have
/// the same colors.
pub const fg_black: u32 = 0x00000000;
pub const fg_red: u32 = 0x000F0000;
pub const fg_green: u32 = 0x0000F000;
pub const fg_yellow: u32 = 0x000FF000;
pub const fg_blue: u32 = 0x00000F00;
pub const fg_magenta: u32 = 0x000F0F00;
pub const fg_cyan: u32 = 0x0000FF00;
pub const fg_white: u32 = 0x000FFF00;
pub const fg_gray: u32 = 0x00088800;
pub const fg_light_gray: u32 = 0x000CCC00;
pub const fg_light_red: u32 = 0x000F6600;
pub const fg_light_green: u32 = 0x0008E800;
pub const fg_light_blue: u32 = 0x0000DF00;
pub const fg_navy: u32 = 0x00000A00;
pub const fg_dark_blue: u32 = 0x00003600;
pub const bg_black: u32 = 0x00000000;
pub const bg_red: u32 = 0xF0000000;
pub const bg_green: u32 = 0x0F000000;
pub const bg_yellow: u32 = 0xFF000000;
pub const bg_blue: u32 = 0x00F00000;
pub const bg_magenta: u32 = 0xF0F00000;
pub const bg_cyan: u32 = 0x0FF00000;
pub const bg_white: u32 = 0xFFF00000;
pub const bg_gray: u32 = 0x88800000;
pub const bg_light_gray: u32 = 0xCCC00000;
pub const bg_light_red: u32 = 0xF6600000;
pub const bg_light_green: u32 = 0x8E800000;
pub const bg_light_blue: u32 = 0x0DF00000;
pub const bg_navy: u32 = 0x00A00000;
pub const bg_dark_blue: u32 = 0x03600000;

/// Writes c, the character in bits 7..0 and its colors above (doc/DEVICES.md
/// §1), to a column, 0 to 79, of a row, 0 to 24.
pub fn screenPut(col: u32, row: u32, c: u32) void {
    nice_screen_put(@bitCast(col), @bitCast(row), @bitCast(c));
}

/// Writes screen_blank, a blank in white on black, to every word of the
/// screen.
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

// The heap: first fit, as the C library's malloc.c. It starts at
// __heap_base, which the linker puts after the stack and the data, and
// ends at nice.heap_end. It grows with nice.grow, which works as
// memory.grow, up to nicewasm's --memory-pages, where the memory can grow,
// and fails where only its start is reserved. Each block has an 8-byte
// header, and its address and size are multiples of 8. Free
// blocks are kept in a list sorted by address, and neighbors are merged
// when a block is freed. NICE has no threads, and an interrupt routine
// must not use the heap.
const Block = extern struct {
    size: usize, // of the whole block, a multiple of 8
    next: ?*Block, // the next free block; unused when allocated
};

const header = @sizeOf(Block);
const page = 65536;

extern var __heap_base: u8;

var free_list: ?*Block = null;
var brk: usize = 0;
var end: usize = 0;

// size bytes of new heap, or null if the memory cannot grow.
fn more(size: usize) ?*Block {
    if (brk == 0) {
        brk = std.mem.alignForward(usize, @intFromPtr(&__heap_base), 8);
        // A reserved part that ends before the heap leaves it empty.
        end = @max(heap_end(), brk);
    }
    if (size > end - brk) {
        const need = size - (end - brk);
        // The page count would wrap: more than all of memory
        if (need > std.math.maxInt(usize) - (page - 1)) return null;
        const pages = (need + page - 1) / page;
        if (grow(@intCast(pages)) == -1) return null;
        end += pages * page;
    }
    const b: *Block = @ptrFromInt(brk);
    brk += size;
    b.size = size;
    return b;
}

// The block of n bytes, or null.
fn heapAlloc(n: usize) ?*Block {
    if (n > std.math.maxInt(usize) - header - 7) return null;
    const size = (n + header + 7) & ~@as(usize, 7);
    var pp: *?*Block = &free_list;
    while (pp.*) |b| : (pp = &b.next) {
        if (b.size < size) continue;
        if (b.size - size >= 2 * header) {
            const rest: *Block = @ptrFromInt(@intFromPtr(b) + size);
            rest.size = b.size - size;
            rest.next = b.next;
            pp.* = rest;
            b.size = size;
        } else {
            pp.* = b.next;
        }
        return b;
    }
    return more(size);
}

fn heapFree(b: *Block) void {
    var prev: ?*Block = null;
    var next = free_list;
    while (next) |n| {
        if (@intFromPtr(n) > @intFromPtr(b)) break;
        prev = n;
        next = n.next;
    }
    if (next) |n| {
        if (@intFromPtr(b) + b.size == @intFromPtr(n)) {
            b.size += n.size;
            b.next = n.next;
        } else b.next = n;
    } else b.next = null;
    if (prev) |p| {
        if (@intFromPtr(p) + p.size == @intFromPtr(b)) {
            p.size += b.size;
            p.next = b.next;
        } else p.next = b;
    } else free_list = b;
}

// The block of the bytes at p that the heap gave out with alignment a.
// Above 8, the word before p holds the address of the block.
fn blockOf(p: [*]u8, a: std.mem.Alignment) *Block {
    if (a.toByteUnits() <= 8) return @ptrFromInt(@intFromPtr(p) - header);
    return @ptrFromInt(@as(*const usize, @ptrFromInt(@intFromPtr(p) - @sizeOf(usize))).*);
}

fn alloc(_: *anyopaque, len: usize, a: std.mem.Alignment, _: usize) ?[*]u8 {
    const align_ = a.toByteUnits();
    if (align_ <= 8) {
        const b = heapAlloc(len) orelse return null;
        return @ptrFromInt(@intFromPtr(b) + header);
    }
    if (len > std.math.maxInt(usize) - align_) return null;
    const b = heapAlloc(len + align_) orelse return null;
    // The bytes start 8-aligned and align_ is at least 16, so p is at
    // least 8 bytes past them and at most align_, and the block holds
    // len bytes from p.
    const q = @intFromPtr(b) + header;
    const p = std.mem.alignForward(usize, q + @sizeOf(usize), align_);
    @as(*usize, @ptrFromInt(p - @sizeOf(usize))).* = @intFromPtr(b);
    return @ptrFromInt(p);
}

// A new length that fits the block keeps it, a smaller one included, as
// the C library's realloc does.
fn resize(_: *anyopaque, memory: []u8, a: std.mem.Alignment, new_len: usize, _: usize) bool {
    const b = blockOf(memory.ptr, a);
    return new_len <= @intFromPtr(b) + b.size - @intFromPtr(memory.ptr);
}

fn remap(ctx: *anyopaque, memory: []u8, a: std.mem.Alignment, new_len: usize, ra: usize) ?[*]u8 {
    return if (resize(ctx, memory, a, new_len, ra)) memory.ptr else null;
}

fn free(_: *anyopaque, memory: []u8, a: std.mem.Alignment, _: usize) void {
    heapFree(blockOf(memory.ptr, a));
}

/// The heap. Blocks are 8-aligned. A larger alignment costs the alignment
/// in extra bytes.
pub const heap: std.mem.Allocator = .{
    .ptr = undefined,
    .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free },
};
