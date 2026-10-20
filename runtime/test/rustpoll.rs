// nice.rs: what test/nicers.rs leaves out, as test/zigpoll.zig checks it
// of nice.zig. pollc returns Byte for a waiting byte, getc then reads the
// next one, and at the end of the input pollc returns End and getc None,
// again and again. poke writes a NICE word that peek reads back. The
// console input is test/rustpoll.input, "ab", so the output is
// "true 61 62" and "true true true true". main returns 0x5A, the word
// that poke wrote and peek read back.
#![no_std]

#[path = "../nice.rs"]
mod nice;

#[no_mangle]
pub extern "C" fn main() -> i32 {
    let p = nice::pollc();
    let b = nice::getc();
    let byte = match p {
        nice::Poll::Byte(c) => c,
        _ => 0,
    };
    println!("{} {:x} {:x}", p == nice::Poll::Byte(b'a'), byte, b.unwrap_or(0));
    println!(
        "{} {} {} {}",
        nice::pollc() == nice::Poll::End,
        nice::getc().is_none(),
        nice::pollc() == nice::Poll::End,
        nice::getc().is_none()
    );

    let word: u32 = 0xFFFF0000 + 80 * 3 + 4; // the screen, row 3, column 4
    nice::poke(word, 0x5A);
    nice::peek(word) as i32
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    core::arch::wasm32::unreachable()
}
