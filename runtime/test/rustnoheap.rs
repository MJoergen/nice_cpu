// nice.rs: the heap of a memory whose reserved part ends before the heap
// starts, as libc/test/noheap.c checks malloc's. The Makefile translates
// the test with --memory-bytes 4 below __heap_base, and says how. The
// heap is then empty, and an allocation fails. Otherwise it would write
// its block past the reserved part, which traps (code 2). main returns a
// bit for each: the memory ends below __heap_base, and alloc fails with
// an alignment of 8 and with one of 64, 7. It prints nothing, so that the
// heap's three words are the program's only static data.
#![no_std]

extern crate alloc;

use alloc::alloc::{alloc, Layout};

#[path = "../nice.rs"]
mod nice;

#[global_allocator]
static HEAP: nice::Heap = nice::Heap;

#[link(wasm_import_module = "nice")]
extern "C" {
    fn heap_end() -> u32;
}

extern "C" {
    static __heap_base: u8;
}

#[no_mangle]
pub extern "C" fn main() -> i32 {
    unsafe {
        let below = (heap_end() as usize) < core::ptr::addr_of!(__heap_base) as usize;
        let no_alloc = alloc(Layout::from_size_align(16, 8).unwrap()).is_null();
        let no_aligned = alloc(Layout::from_size_align(16, 64).unwrap()).is_null();
        (below as i32) << 2 | (no_alloc as i32) << 1 | no_aligned as i32
    }
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    core::arch::wasm32::unreachable()
}
