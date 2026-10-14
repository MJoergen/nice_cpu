// Traits, slices, iterators, u64 arithmetic, and initialized data.
// Calls through dyn Shape use a table and call_indirect.
//
// get is imported from env: get(i) = i + 100. It keeps rustc from folding
// the calls below at compile time.
#![no_std]

#[link(wasm_import_module = "env")]
extern "C" {
    fn get(i: i32) -> i32;
}

fn g(i: i32) -> i32 {
    unsafe { get(i) }
}

trait Shape {
    fn area(&self) -> u32;
}

struct Square(u32);
struct Rect(u32, u32);

impl Shape for Square {
    fn area(&self) -> u32 {
        self.0 * self.0
    }
}

impl Shape for Rect {
    fn area(&self) -> u32 {
        self.0 * self.1
    }
}

static PRIMES: [u16; 8] = [2, 3, 5, 7, 11, 13, 17, 19];
static mut BUF: [u8; 32] = [0; 32];

#[no_mangle]
pub extern "C" fn main() -> i32 {
    let a = g(-97) as u32; // 3
    let b = g(-95) as u32; // 5
    let sq = Square(a);
    let re = Rect(a, b);
    let shapes: [&dyn Shape; 3] = [&sq, &re, &sq];
    let i = g(-99) as usize; // 1
    let areas: u32 = shapes[i..].iter().map(|s| s.area()).sum(); // 15 + 9

    let n = g(-92) as usize; // 8
    let p: u32 = PRIMES[..n].iter().filter(|&&p| p % 4 == 1).map(|&p| p as u32).sum(); // 5 + 13 + 17

    let buf = unsafe { &mut *core::ptr::addr_of_mut!(BUF) };
    for (j, x) in buf.iter_mut().enumerate() {
        *x = (j as u8).wrapping_mul(7);
    }
    buf.reverse();
    let r = buf[g(-100) as usize] as u32; // buf[0] = 31 * 7 = 217

    let big = (g(-1) as u64) << 40; // 99 * 2^40
    let q = (big / 1_000_000_007) as u32; // 108851

    (areas + p + r + q % 1000) as i32
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    core::arch::wasm32::unreachable()
}
