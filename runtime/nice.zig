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
/// bytes may still come after that (SYSTEM.md §1).
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

/// The performance counters of SYSTEM.md §3: the clock cycles and the
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

/// Writes c, the character in bits 7..0 and its colors above (doc/SYSTEM.md
/// §1), to a column, 0 to 79, of a row, 0 to 24.
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

// The heap: first fit, as the C library's malloc.c. It starts at
// __heap_base, which the linker puts after the stack and the data, and
// grows with memory.grow, up to nicewasm's --memory-pages. Each block has
// an 8-byte header, and its address and size are multiples of 8. Free
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
var heap_end: usize = 0;

// size bytes of new heap, or null if memory.grow fails.
fn more(size: usize) ?*Block {
    if (brk == 0) {
        brk = std.mem.alignForward(usize, @intFromPtr(&__heap_base), 8);
        heap_end = @wasmMemorySize(0) * page;
    }
    if (size > heap_end - brk) {
        const need = size - (heap_end - brk);
        // The page count would wrap: more than all of memory
        if (need > std.math.maxInt(usize) - (page - 1)) return null;
        const pages = (need + page - 1) / page;
        if (@wasmMemoryGrow(0, pages) == -1) return null;
        heap_end += pages * page;
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
