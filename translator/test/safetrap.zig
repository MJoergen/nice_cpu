// Built with ReleaseSafe. The index is past the end of buf, so Zig's
// bounds check panics, and the panic ends in unreachable, which traps
// with code 1. The panic handler puts a 4 KB buffer on the stack, so with
// a stack of only 4 KB it would instead trap with code 2, out of bounds.
//
// get is imported from env: get(i) = i + 100.
extern fn get(i: i32) i32;

var buf: [4]u32 = .{ 1, 2, 3, 4 };

export fn main() i32 {
    const i: usize = @intCast(get(-96)); // 4
    return @intCast(buf[i]);
}
