// nice.zig: the heap of a memory whose reserved part ends before the heap
// starts, as libc/test/noheap.c checks malloc's. The Makefile translates
// the test with --memory-bytes 4 below __heap_base, and says how. The
// heap is then empty, and an allocation fails. Otherwise it would write
// its block past the reserved part, which traps (code 2). main returns a
// bit for each: the memory ends below __heap_base, and alloc and create
// fail, 7. It prints nothing, so that the heap's three words are the
// program's only static data.
const nice = @import("nice");

extern "nice" fn heap_end() u32;
extern var __heap_base: u8;

export fn main() i32 {
    const below: i32 = @intFromBool(heap_end() < @intFromPtr(&__heap_base));
    const no_alloc: i32 = if (nice.heap.alloc(u8, 16)) |_| 0 else |_| 1;
    const no_create: i32 = if (nice.heap.create(u32)) |_| 0 else |_| 1;
    return below << 2 | no_alloc << 1 | no_create;
}
