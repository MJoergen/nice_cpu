// nice.rs: the heap, for the alloc crate. It checks that a freed block is
// merged with its neighbor and reused, that a Vec, a String, and a Box
// work, that an alignment above 8 holds, that shrinking keeps the block,
// that the heap grows past the first page, and that it fails at the cap of
// --memory-pages 2. main returns the number of lines it printed, 8.
#![no_std]

extern crate alloc;

use alloc::alloc::{alloc, dealloc, Layout};
use alloc::boxed::Box;
use alloc::format;
use alloc::vec::Vec;
use core::arch::wasm32::memory_size;

#[path = "../nice.rs"]
mod nice;

#[global_allocator]
static HEAP: nice::Heap = nice::Heap;

#[repr(align(64))]
struct Aligned(u8);

#[no_mangle]
pub extern "C" fn main() -> i32 {
    // Blocks of 512 bytes each, header included: x and y next to each
    // other, and z after them. 1000 bytes need 1008. With only x free,
    // they come from the end of the heap; once y is freed and merged with
    // x, from x.
    unsafe {
        let small = Layout::from_size_align(504, 8).unwrap();
        let big = Layout::from_size_align(1000, 8).unwrap();
        let x = alloc(small);
        let y = alloc(small);
        let z = alloc(small);
        dealloc(x, small);
        let a = alloc(big);
        dealloc(y, small);
        let b = alloc(big);
        println!("{} {} {}", y == x.add(512), a != x, b == x);
        dealloc(a, big);
        dealloc(b, big);
        dealloc(z, small);
    }

    let mut v: Vec<u32> = Vec::new();
    for i in 0..1000 {
        v.push(i * i);
    }
    let sum: u64 = v.iter().map(|&x| x as u64).sum();
    let s = format!("{}-{}", "heap", sum);
    println!("{} {}", s, s.len());
    drop(v);

    let boxes: Vec<Box<Aligned>> = (0..3).map(|i| Box::new(Aligned(i))).collect();
    let ok = boxes.iter().all(|b| (&**b as *const Aligned as usize) % 64 == 0);
    println!("{} {}", ok, boxes.iter().map(|b| b.0 as u32).sum::<u32>());
    drop(boxes);

    let mut w: Vec<u8> = Vec::with_capacity(100);
    w.extend_from_slice(b"abc");
    let p = w.as_ptr();
    w.shrink_to(10);
    println!("{} {}", w.as_ptr() == p, w.capacity());
    drop(w);

    // 80000 bytes are more than the first page has left.
    let before = memory_size(0);
    let mut g: Vec<u32> = Vec::with_capacity(20000);
    for i in 0..20000 {
        g.push(i);
    }
    let gsum: u64 = g.iter().map(|&x| x as u64).sum();
    println!("{} {} {}", before, memory_size(0), gsum);

    // The cap is 2 pages, so 80000 bytes more cannot be had, and the
    // memory stays at 2 pages.
    let mut h: Vec<u32> = Vec::new();
    println!("{} {}", h.try_reserve(20000).is_err(), memory_size(0));
    drop(g);

    // With g freed, the same 80000 bytes fit.
    println!("{}", h.try_reserve(20000).is_ok());
    unsafe {
        let huge = Layout::from_size_align(1 << 30, 8).unwrap();
        println!("{}", alloc(huge).is_null());
    }
    8
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    core::arch::wasm32::unreachable()
}
