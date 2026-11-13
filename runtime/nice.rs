//! Support for Rust code that reaches NICE through wasm: the device routines
//! of ABI.md, which are imports from env and so the routines of
//! lib.nasm, and the `nice` imports of WASM.md. It is the Rust
//! counterpart of the C library's nice.h, with a `core::fmt::Write`
//! console and `print!` and `println!`, for `#![no_std]` programs, and a
//! heap for the `alloc` crate. Mount it at the crate root as `nice`, so
//! that `print!` and `println!` find it:
//!
//!     #[path = "runtime/nice.rs"]
//!     mod nice;
//!
//! A program that uses `alloc` names the heap as its allocator:
//!
//!     extern crate alloc;
//!     #[global_allocator]
//!     static HEAP: nice::Heap = nice::Heap;
//!
//! A program that takes square roots, sines, and the like brings in the
//! `Float` trait, whose methods have the names of std's:
//!
//!     use nice::Float;
//!     let r = (x * x + y * y).sqrt();

// A program uses only some of these.
#![allow(dead_code)]

#[link(wasm_import_module = "nice")]
extern "C" {
    #[link_name = "peek"]
    fn nice_peek(addr: u32) -> u32;
    #[link_name = "poke"]
    fn nice_poke(addr: u32, val: u32);
}

// The device routines of ABI.md. nice_print is left out: it takes a
// string of one character per word, and Rust strings are bytes.
#[link(wasm_import_module = "env")]
extern "C" {
    fn nice_putc(c: i32);
    fn nice_getc() -> i32;
    fn nice_pollc() -> i32;
    fn nice_cycles() -> u64;
    fn nice_instructions() -> u64;
    fn nice_screen_put(col: i32, row: i32, c: i32);
    fn nice_screen_clear();
}

/// Reads the NICE word at a word address.
pub fn peek(addr: u32) -> u32 {
    unsafe { nice_peek(addr) }
}

/// Writes val to the NICE word at a word address.
pub fn poke(addr: u32, val: u32) {
    unsafe { nice_poke(addr, val) }
}

/// Writes c to the console.
pub fn putc(c: u8) {
    unsafe { nice_putc(c as i32) }
}

/// Writes the bytes of s to the console.
pub fn write(s: &[u8]) {
    for &c in s {
        putc(c);
    }
}

/// Waits for the next input byte. Returns None once the line's input has
/// ended: the emulator's stdin or the host of the debug link. A keyboard's
/// bytes may still come after that (DEVICES.md §1).
pub fn getc() -> Option<u8> {
    let c = unsafe { nice_getc() };
    if c < 0 { None } else { Some(c as u8) }
}

/// What pollc found: a byte, no byte yet, or the end of the input.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Poll {
    Byte(u8),
    Empty,
    End,
}

/// Reads the console once, without waiting.
pub fn pollc() -> Poll {
    match unsafe { nice_pollc() } {
        c if c >= 0 => Poll::Byte(c as u8),
        -2 => Poll::Empty,
        _ => Poll::End,
    }
}

/// Reads a line of console input into buf and returns it, without the
/// "\n", and without a "\r" just before it. A line longer than buf is cut
/// off: its first buf.len() bytes are kept, and the rest is read and
/// dropped. Bytes that are not UTF-8, as a character cut in two, end the
/// string at the last whole character. A last line with no "\n" before the
/// end of the input is returned too. Returns None once the input has ended
/// with no byte read.
pub fn read_line(buf: &mut [u8]) -> Option<&str> {
    let mut n = 0;
    let mut cut = false;
    loop {
        match getc() {
            Some(b'\n') => break,
            Some(c) => {
                if n < buf.len() {
                    buf[n] = c;
                    n += 1;
                } else {
                    cut = true;
                }
            }
            None if n == 0 && !cut => return None,
            None => break,
        }
    }
    if !cut && n > 0 && buf[n - 1] == b'\r' {
        n -= 1;
    }
    let line = &buf[..n];
    Some(match core::str::from_utf8(line) {
        Ok(s) => s,
        // The prefix is valid UTF-8, so the second call cannot fail.
        Err(e) => core::str::from_utf8(&line[..e.valid_up_to()]).unwrap_or(""),
    })
}

/// The performance counters of DEVICES.md §3: the clock cycles and the
/// instructions since reset. An interrupt routine must not read them while
/// the code it interrupted is reading one.
pub fn cycles() -> u64 {
    unsafe { nice_cycles() }
}

pub fn instructions() -> u64 {
    unsafe { nice_instructions() }
}

/// The emulator's character screen.
pub const SCREEN_COLS: u32 = 80;
pub const SCREEN_ROWS: u32 = 25;
/// The blank that screen_clear writes: a space in white on black, the
/// colors a board's monitor writes in, so that a cursor, which swaps the
/// colors of its cell, shows on it (doc/DEVICES.md §1.4).
pub const SCREEN_BLANK: u32 = 0x000F_FF20;

/// Writes c, the character in bits 7..0 and its color above, to a column,
/// 0 to 79, of a row, 0 to 24.
pub fn screen_put(col: u32, row: u32, c: u32) {
    unsafe { nice_screen_put(col as i32, row as i32, c as i32) }
}

/// Writes SCREEN_BLANK, a blank in white on black, to every word of the
/// screen.
pub fn screen_clear() {
    unsafe { nice_screen_clear() }
}

// The heap: first fit, as the C library's malloc.c. It starts at
// __heap_base, which wasm-ld puts after the stack and the data, and grows
// with memory.grow, up to nicewasm's --memory-pages. Each block has an
// 8-byte header, and its address and size are multiples of 8. Free blocks
// are kept in a list sorted by address, and neighbors are merged when a
// block is freed. NICE has no threads, and an interrupt routine must not
// use the heap.
#[repr(C)]
struct Block {
    size: usize,      // of the whole block, a multiple of 8
    next: *mut Block, // the next free block; unused when allocated
}

const HEADER: usize = core::mem::size_of::<Block>();
const PAGE: usize = 65536;

extern "C" {
    static __heap_base: u8;
}

static mut FREE_LIST: *mut Block = core::ptr::null_mut();
static mut BRK: usize = 0;
static mut HEAP_END: usize = 0;

// size bytes of new heap, or null if memory.grow fails.
unsafe fn more(size: usize) -> *mut Block {
    if BRK == 0 {
        BRK = (core::ptr::addr_of!(__heap_base) as usize + 7) & !7;
        HEAP_END = core::arch::wasm32::memory_size(0) * PAGE;
    }
    if size > HEAP_END - BRK {
        let need = size - (HEAP_END - BRK);
        // The page count would wrap: more than all of memory
        if need > usize::MAX - (PAGE - 1) {
            return core::ptr::null_mut();
        }
        let pages = (need + PAGE - 1) / PAGE;
        if core::arch::wasm32::memory_grow(0, pages) == usize::MAX {
            return core::ptr::null_mut();
        }
        HEAP_END += pages * PAGE;
    }
    let b = BRK as *mut Block;
    BRK += size;
    (*b).size = size;
    b
}

// n bytes, 8-aligned, or null.
unsafe fn heap_alloc(n: usize) -> *mut u8 {
    if n > usize::MAX - HEADER - 7 {
        return core::ptr::null_mut();
    }
    let size = (n + HEADER + 7) & !7;
    let mut pp = core::ptr::addr_of_mut!(FREE_LIST);
    while !(*pp).is_null() {
        let b = *pp;
        if (*b).size >= size {
            if (*b).size - size >= 2 * HEADER {
                let rest = (b as *mut u8).add(size) as *mut Block;
                (*rest).size = (*b).size - size;
                (*rest).next = (*b).next;
                *pp = rest;
                (*b).size = size;
            } else {
                *pp = (*b).next;
            }
            return b.add(1) as *mut u8;
        }
        pp = core::ptr::addr_of_mut!((*b).next);
    }
    let b = more(size);
    if b.is_null() { core::ptr::null_mut() } else { b.add(1) as *mut u8 }
}

unsafe fn heap_free(p: *mut u8) {
    let b = (p as *mut Block).sub(1);
    let mut prev: *mut Block = core::ptr::null_mut();
    let mut next = FREE_LIST;
    while !next.is_null() && next < b {
        prev = next;
        next = (*next).next;
    }
    if !next.is_null() && (b as *mut u8).add((*b).size) == next as *mut u8 {
        (*b).size += (*next).size;
        (*b).next = (*next).next;
    } else {
        (*b).next = next;
    }
    if !prev.is_null() && (prev as *mut u8).add((*prev).size) == b as *mut u8 {
        (*prev).size += (*b).size;
        (*prev).next = (*b).next;
    } else if !prev.is_null() {
        (*prev).next = b;
    } else {
        FREE_LIST = b;
    }
}

/// The heap, for `#[global_allocator]`. Blocks are 8-aligned. A larger
/// alignment costs the alignment in extra bytes, and the word before the
/// block holds the address that the heap gave out.
pub struct Heap;

unsafe impl core::alloc::GlobalAlloc for Heap {
    unsafe fn alloc(&self, layout: core::alloc::Layout) -> *mut u8 {
        let align = layout.align();
        if align <= 8 {
            return heap_alloc(layout.size());
        }
        if layout.size() > usize::MAX - align {
            return core::ptr::null_mut();
        }
        let q = heap_alloc(layout.size() + align);
        if q.is_null() {
            return q;
        }
        // q is 8-aligned and align at least 16, so p is at least 8 bytes
        // past q and at most align, and the block holds the size from p.
        let p = ((q as usize + 4 + align - 1) & !(align - 1)) as *mut u8;
        *(p as *mut usize).sub(1) = q as usize;
        p
    }

    unsafe fn dealloc(&self, p: *mut u8, layout: core::alloc::Layout) {
        if layout.align() <= 8 {
            heap_free(p);
        } else {
            heap_free(*(p as *mut usize).sub(1) as *mut u8);
        }
    }

    // A smaller size, as one that still fits the block, keeps the block,
    // as the C library's realloc does.
    unsafe fn realloc(&self, p: *mut u8, layout: core::alloc::Layout, new_size: usize) -> *mut u8 {
        if layout.align() <= 8 && new_size <= (*(p as *mut Block).sub(1)).size - HEADER {
            return p;
        }
        let new_layout = core::alloc::Layout::from_size_align_unchecked(new_size, layout.align());
        let q = self.alloc(new_layout);
        if !q.is_null() {
            core::ptr::copy_nonoverlapping(p, q, core::cmp::min(layout.size(), new_size));
            self.dealloc(p, layout);
        }
        q
    }
}

/// The console, for core::fmt, as print! and println! use it.
pub struct Console;

impl core::fmt::Write for Console {
    fn write_str(&mut self, s: &str) -> core::fmt::Result {
        write(s.as_bytes());
        Ok(())
    }
}

/// Prints on the console with core::fmt.
#[macro_export]
macro_rules! print {
    ($($arg:tt)*) => {{
        let _ = core::fmt::Write::write_fmt(&mut $crate::nice::Console, format_args!($($arg)*));
    }};
}

/// Prints on the console with core::fmt, and then a newline.
#[macro_export]
macro_rules! println {
    () => { $crate::print!("\n") };
    ($($arg:tt)*) => {{
        $crate::print!($($arg)*);
        $crate::print!("\n");
    }};
}

// The math functions of C. rustc links its compiler_builtins into every
// wasm32 module, and that has musl's, ported to Rust, so these are no
// imports. sqrt, fabs, floor, ceil, trunc, rint, and copysign are wasm
// instructions in it, which nicewasm turns into calls of the float
// library or bit operations, as it does for + and *.
extern "C" {
    fn fabs(x: f64) -> f64;
    fn floor(x: f64) -> f64;
    fn ceil(x: f64) -> f64;
    fn trunc(x: f64) -> f64;
    fn round(x: f64) -> f64;
    fn rint(x: f64) -> f64;
    fn sqrt(x: f64) -> f64;
    fn cbrt(x: f64) -> f64;
    fn sin(x: f64) -> f64;
    fn cos(x: f64) -> f64;
    fn tan(x: f64) -> f64;
    fn asin(x: f64) -> f64;
    fn acos(x: f64) -> f64;
    fn atan(x: f64) -> f64;
    fn sinh(x: f64) -> f64;
    fn cosh(x: f64) -> f64;
    fn tanh(x: f64) -> f64;
    fn exp(x: f64) -> f64;
    fn exp2(x: f64) -> f64;
    fn log(x: f64) -> f64;
    fn log10(x: f64) -> f64;
    fn log2(x: f64) -> f64;
    fn atan2(y: f64, x: f64) -> f64;
    fn pow(x: f64, y: f64) -> f64;
    fn hypot(x: f64, y: f64) -> f64;
    fn copysign(x: f64, y: f64) -> f64;
    fn fabsf(x: f32) -> f32;
    fn floorf(x: f32) -> f32;
    fn ceilf(x: f32) -> f32;
    fn truncf(x: f32) -> f32;
    fn roundf(x: f32) -> f32;
    fn rintf(x: f32) -> f32;
    fn sqrtf(x: f32) -> f32;
    fn cbrtf(x: f32) -> f32;
    fn sinf(x: f32) -> f32;
    fn cosf(x: f32) -> f32;
    fn tanf(x: f32) -> f32;
    fn asinf(x: f32) -> f32;
    fn acosf(x: f32) -> f32;
    fn atanf(x: f32) -> f32;
    fn sinhf(x: f32) -> f32;
    fn coshf(x: f32) -> f32;
    fn tanhf(x: f32) -> f32;
    fn expf(x: f32) -> f32;
    fn exp2f(x: f32) -> f32;
    fn logf(x: f32) -> f32;
    fn log10f(x: f32) -> f32;
    fn log2f(x: f32) -> f32;
    fn atan2f(y: f32, x: f32) -> f32;
    fn powf(x: f32, y: f32) -> f32;
    fn hypotf(x: f32, y: f32) -> f32;
    fn copysignf(x: f32, y: f32) -> f32;
}

/// The math methods of std's f64 and f32, which a `#![no_std]` program
/// lacks, by the C functions of the same meaning. `round` rounds half away
/// from 0, and `round_ties_even` to even, as in std.
pub trait Float: Sized {
    fn abs(self) -> Self;
    fn floor(self) -> Self;
    fn ceil(self) -> Self;
    fn trunc(self) -> Self;
    fn round(self) -> Self;
    fn round_ties_even(self) -> Self;
    fn sqrt(self) -> Self;
    fn cbrt(self) -> Self;
    fn sin(self) -> Self;
    fn cos(self) -> Self;
    fn tan(self) -> Self;
    fn asin(self) -> Self;
    fn acos(self) -> Self;
    fn atan(self) -> Self;
    fn sinh(self) -> Self;
    fn cosh(self) -> Self;
    fn tanh(self) -> Self;
    fn exp(self) -> Self;
    fn exp2(self) -> Self;
    fn ln(self) -> Self;
    fn log10(self) -> Self;
    fn log2(self) -> Self;
    fn atan2(self, other: Self) -> Self;
    fn powf(self, n: Self) -> Self;
    fn hypot(self, other: Self) -> Self;
    fn copysign(self, sign: Self) -> Self;
}

macro_rules! float_impl {
    ($t:ty; $($m:ident => $c:ident),*; $($m2:ident => $c2:ident),*) => {
        impl Float for $t {
            $(fn $m(self) -> $t {
                unsafe { $c(self) }
            })*
            $(fn $m2(self, y: $t) -> $t {
                unsafe { $c2(self, y) }
            })*
        }
    };
}

float_impl!(f64;
    abs => fabs, floor => floor, ceil => ceil, trunc => trunc, round => round,
    round_ties_even => rint, sqrt => sqrt, cbrt => cbrt, sin => sin, cos => cos, tan => tan,
    asin => asin, acos => acos, atan => atan, sinh => sinh, cosh => cosh, tanh => tanh,
    exp => exp, exp2 => exp2, ln => log, log10 => log10, log2 => log2;
    atan2 => atan2, powf => pow, hypot => hypot, copysign => copysign);
float_impl!(f32;
    abs => fabsf, floor => floorf, ceil => ceilf, trunc => truncf, round => roundf,
    round_ties_even => rintf, sqrt => sqrtf, cbrt => cbrtf, sin => sinf, cos => cosf,
    tan => tanf, asin => asinf, acos => acosf, atan => atanf, sinh => sinhf, cosh => coshf,
    tanh => tanhf, exp => expf, exp2 => exp2f, ln => logf, log10 => log10f, log2 => log2f;
    atan2 => atan2f, powf => powf, hypot => hypotf, copysign => copysignf);
