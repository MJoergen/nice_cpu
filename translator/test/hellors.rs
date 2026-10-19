// Prints on the console at 0xFFFFFF00 (SYSTEM.md §1) through nice.poke,
// and returns the number of bytes it printed, 13.
#![no_std]

#[link(wasm_import_module = "nice")]
extern "C" {
    fn poke(addr: u32, val: u32);
}

const CONSOLE: u32 = 0xFFFFFF00;

#[no_mangle]
pub extern "C" fn main() -> i32 {
    let msg = b"Hello, Rust!\n";
    for &c in msg {
        unsafe { poke(CONSOLE, c as u32) };
    }
    msg.len() as i32
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    core::arch::wasm32::unreachable()
}
