// nice.rs: the console, the performance counters, and the screen. It
// prints a line with core::fmt, echoes the console input in upper case
// until it ends, checks that pollc then finds the end, checks the counters
// as libc/test/nice.c does, and reads back what it wrote to the screen.
// main returns the number of bytes it read, 4 with test/nicers.input.
#![no_std]

#[path = "../nice.rs"]
mod nice;

#[no_mangle]
pub extern "C" fn main() -> i32 {
    println!("{} {} {:#x}", "Rust", 42, 0xBEEF);
    let cycles = nice::cycles();
    let instrs = nice::instructions();
    let mut n = 0;
    while let Some(c) = nice::getc() {
        nice::putc(c.to_ascii_uppercase());
        n += 1;
    }
    let instrs2 = nice::instructions();
    let cycles2 = nice::cycles();
    println!(
        "{} {} {}",
        nice::pollc() == nice::Poll::End,
        instrs2 > instrs,
        cycles2 - cycles > instrs2 - instrs
    );

    nice::screen_clear();
    nice::screen_put(2, 1, 0xC80FF021);
    nice::screen_put(nice::SCREEN_COLS - 1, nice::SCREEN_ROWS - 1, 'Z' as u32);
    const SCREEN: u32 = 0xFFFF0000;
    println!(
        "{:x} {:x} {:x}",
        nice::peek(SCREEN),
        nice::peek(SCREEN + 82),
        nice::peek(SCREEN + 1999)
    );
    n
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    core::arch::wasm32::unreachable()
}
