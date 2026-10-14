// The index is past the end of BUF, so the bounds check panics. The
// panic handler ends in unreachable, which traps with code 1.
//
// get is imported from env: get(i) = i + 100.
#![no_std]

#[link(wasm_import_module = "env")]
extern "C" {
    fn get(i: i32) -> i32;
}

static BUF: [u32; 4] = [1, 2, 3, 4];

#[no_mangle]
pub extern "C" fn main() -> i32 {
    let i = unsafe { get(-96) } as usize; // 4
    BUF[i] as i32
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    core::arch::wasm32::unreachable()
}
