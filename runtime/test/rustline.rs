// nice.rs: read_line, with a buffer of 16 bytes, on test/rustline.input,
// the input of test/zigline.zig. It prints each line in brackets, with
// the bytes outside 0x20 to 0x7E as \xNN, and its length, then the sum of
// the numbers of the first line, parsed with core. The output is that of
// zigline.zig, but for two lines that are not UTF-8: the line with "é"
// cut in two after its first byte, and the one with the byte 0xFF, end
// before the bad byte. main returns the number of lines read, 10.
#![no_std]

#[path = "../nice.rs"]
mod nice;

fn show(line: &str) {
    nice::putc(b'[');
    for &c in line.as_bytes() {
        if (0x20..=0x7E).contains(&c) {
            nice::putc(c);
        } else {
            print!("\\x{:02x}", c);
        }
    }
    println!("] {}", line.len());
}

#[no_mangle]
pub extern "C" fn main() -> i32 {
    let mut buf = [0u8; 16];
    let mut count = 0;
    let mut sum = 0;
    while let Some(line) = nice::read_line(&mut buf) {
        show(line);
        if count == 0 {
            sum = line.split_whitespace().filter_map(|w| w.parse::<i32>().ok()).sum();
        }
        count += 1;
    }
    let end1 = nice::read_line(&mut buf).is_none();
    let end2 = nice::read_line(&mut buf).is_none();
    println!("sum {} {} {}", sum, end1, end2);
    count
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    core::arch::wasm32::unreachable()
}
