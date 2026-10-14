// get is imported from env: get(i) = i + 100. It keeps Zig from folding
// the calls below at compile time.
extern fn get(i: i32) i32;

// Initialized data, in a data segment. Bytes, because indexing wider
// elements needs a shift, which nicewasm does not support yet.
const primes = [_]u8{ 2, 3, 5, 7, 11, 13, 17, 19 };
var state: u32 = 0x12345678;

export fn main() i32 {
    const i: usize = @intCast(get(-95)); // 5
    const p: i32 = primes[i]; // 13
    state +%= @bitCast(get(0)); // 0x123456DC
    return p + @as(i32, @bitCast(state & 0xFFFF)); // 13 + 0x56DC
}
