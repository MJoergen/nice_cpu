// Prints on the console at 0xFFFFFF00 (SYSTEM.md §1) through nice.poke,
// and returns the number of bytes it printed, 13.
extern "nice" fn poke(addr: u32, val: u32) void;

const console: u32 = 0xFFFFFF00;

export fn main() i32 {
    const msg = "Hello, NICE!\n";
    for (msg) |c| poke(console, c);
    return msg.len;
}
