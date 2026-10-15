//! Support for Rust code that reaches NICE through wasm: the device routines
//! of ISA.md §9.3, which are imports from env and so the routines of
//! lib.nasm, and the `nice` imports of ISA.md §9.4. It is the Rust
//! counterpart of the C library's nice.h, with a `core::fmt::Write`
//! console and `print!` and `println!`, for `#![no_std]` programs. Mount it
//! at the crate root as `nice`, so that `print!` and `println!` find it:
//!
//!     #[path = "runtime/nice.rs"]
//!     mod nice;

// A program uses only some of these.
#![allow(dead_code)]

#[link(wasm_import_module = "nice")]
extern "C" {
    #[link_name = "peek"]
    fn nice_peek(addr: u32) -> u32;
    #[link_name = "poke"]
    fn nice_poke(addr: u32, val: u32);
}

// The device routines of ISA.md §9.3. nice_print is left out: it takes a
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

/// Waits for the next input byte. Returns None once the emulator's input
/// has ended, which a UART's input never does.
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

/// The performance counters of ISA.md §8.5: the clock cycles and the
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

/// Writes c, the character in bits 7..0 and its colour above, to a column,
/// 0 to 79, of a row, 0 to 24.
pub fn screen_put(col: u32, row: u32, c: u32) {
    unsafe { nice_screen_put(col as i32, row as i32, c as i32) }
}

/// Writes a blank, 0x20, to every word of the screen.
pub fn screen_clear() {
    unsafe { nice_screen_clear() }
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
