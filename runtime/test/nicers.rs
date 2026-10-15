// nice.rs: the console and the performance counters. It prints a line with
// core::fmt, echoes the console input in upper case until it ends, and
// checks the counters as libc/test/nice.c does. main returns the number of
// bytes it read, 4 with test/nicers.input.
#![no_std]

#[path = "../nice.rs"]
mod nice;

#[no_mangle]
pub extern "C" fn main() -> i32 {
    println!("{} {} {:#x}", "Rust", 42, 0xBEEF);
    let cycles = nice::counter64(nice::CYCLE_LO);
    let instrs = nice::counter64(nice::INSTR_LO);
    let mut n = 0;
    while let Some(c) = nice::getchar() {
        nice::write(&[c.to_ascii_uppercase()]);
        n += 1;
    }
    let instrs2 = nice::counter64(nice::INSTR_LO);
    let cycles2 = nice::counter64(nice::CYCLE_LO);
    println!("{} {}", instrs2 > instrs, cycles2 - cycles > instrs2 - instrs);
    n
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    core::arch::wasm32::unreachable()
}
