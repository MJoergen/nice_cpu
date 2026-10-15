//! Support for Rust code that reaches NICE through wasm: the `nice` imports
//! of ISA.md §9.4, the console of ISA.md §8.3, and the performance counters
//! of ISA.md §8.5. It is the Rust counterpart of the C library's nice.h and
//! console code, for `#![no_std]` programs. Mount it at the crate root as
//! `nice`, so that `print!` and `println!` find it:
//!
//!     #[path = "runtime/nice.rs"]
//!     mod nice;

#[link(wasm_import_module = "nice")]
extern "C" {
    #[link_name = "peek"]
    fn nice_peek(addr: u32) -> u32;
    #[link_name = "poke"]
    fn nice_poke(addr: u32, val: u32);
}

/// Reads the NICE word at a word address.
pub fn peek(addr: u32) -> u32 {
    unsafe { nice_peek(addr) }
}

/// Writes val to the NICE word at a word address.
pub fn poke(addr: u32, val: u32) {
    unsafe { nice_poke(addr, val) }
}

/// The console. Each write prints bits 7..0 of the word. A read returns the
/// next input byte with CONSOLE_BYTE set, 0 if no byte is there yet, or
/// CONSOLE_END once the emulator's input ended.
pub const CONSOLE: u32 = 0xFFFFFF00;
pub const CONSOLE_BYTE: u32 = 0x100;
pub const CONSOLE_END: u32 = 0x200;

/// The address of each performance counter's low word. Read them with
/// counter64.
pub const CYCLE_LO: u32 = 0xFFFFFF10;
pub const INSTR_LO: u32 = 0xFFFFFF12;

/// Prints the bytes of s on the console.
pub fn write(s: &[u8]) {
    for &c in s {
        poke(CONSOLE, c as u32);
    }
}

/// Waits for the next input byte. Returns None once the emulator's input
/// has ended, which a UART's input never does.
pub fn getchar() -> Option<u8> {
    loop {
        let v = peek(CONSOLE);
        if v & CONSOLE_BYTE != 0 {
            return Some(v as u8);
        }
        if v & CONSOLE_END != 0 {
            return None;
        }
    }
}

/// Reads the 64-bit performance counter whose low word is at lo, such as
/// CYCLE_LO: the low word first, which takes a snapshot of the high word,
/// and then the high word at lo + 1.
pub fn counter64(lo: u32) -> u64 {
    let low = peek(lo);
    (peek(lo + 1) as u64) << 32 | low as u64
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
