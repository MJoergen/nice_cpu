// Floats in Rust: arithmetic, which nicewasm turns into calls of the float
// library, the math methods of nice::Float, which are compiler_builtins'
// C functions, rounding and conversions, and core::fmt's printing of
// floats. The arguments are read through volatile loads, so that rustc
// cannot compute the results itself. Each printed value is the shortest
// decimal that gives back the same float, as Python's repr prints it
// too, and test/rustfloat.expected was checked with Python's math module.
// main returns 0.
#![no_std]

#[path = "../nice.rs"]
#[macro_use]
mod nice;

use nice::Float;

static mut TWO: f64 = 2.0;
static mut TENTH: f32 = 0.1;

fn two() -> f64 {
    unsafe { core::ptr::read_volatile(&raw const TWO) }
}

fn tenth() -> f32 {
    unsafe { core::ptr::read_volatile(&raw const TENTH) }
}

#[no_mangle]
pub extern "C" fn main() -> i32 {
    let x = two();
    let one = x / 2.0;
    // 3, 2/3, and 1.9 rounded to double, which prints as 1.9.
    println!("{} {} {}", x * 1.5, x / 3.0, x - 0.1);
    // √2, sin 1, e, ln 2, √2 again as 2^0.5, and π as 4 atan2(1, 1).
    // compiler_builtins' exp is fdlibm's, whose exp(1) is the double above
    // e, 2.7182818284590455, 0.67 ulp off: the same steps in Python's
    // doubles give it too.
    println!(
        "{} {} {} {} {} {}",
        x.sqrt(),
        one.sin(),
        one.exp(),
        x.ln(),
        x.powf(0.5),
        4.0 * one.atan2(one)
    );
    // The same in f32. 0.1 times 3 rounds to the float nearest 0.3.
    let y = tenth();
    let yone = y * 10.0;
    println!("{} {} {} {} {}", y * 3.0, (y * 20.0).sqrt(), yone.sin(), yone.exp(), y.ln());
    // Rounding: 3.4 down, -2.5 away from 0 and to even, |-2|, and to
    // integers, which saturate.
    println!(
        "{} {} {} {} {} {}",
        (x * 1.7).floor(),
        (-x - 0.5).round(),
        (-x - 0.5).round_ties_even(),
        (-x).abs(),
        (x * 1.7) as i32,
        (x * 1e10) as i32
    );
    // The special values, and the exponent form.
    let zero = x - x;
    println!("{} {} {} {} {:e} {:e}", zero / zero, one / zero, -one / zero, -zero, x * 617.25, y);
    0
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    core::arch::wasm32::unreachable()
}
