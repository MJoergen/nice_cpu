// Built with ReleaseSafe, which keeps Zig's safety checks. That makes Zig
// use a table, call_indirect, memory.copy, and memory.fill, even here.
//
// get is imported from env: get(i) = i + 100. It keeps Zig from folding
// the calls below at compile time.
extern fn get(i: i32) i32;

var buf: [16]u32 = undefined;

fn apply(f: *const fn (u32) u32, x: u32) u32 {
    return f(x);
}

fn sq(x: u32) u32 {
    return x * x;
}

fn inc(x: u32) u32 {
    return x + 1;
}

export fn main() i32 {
    const n: usize = @intCast(get(-90)); // 10
    for (buf[0..n], 0..) |*b, i| b.* = @intCast(i);
    const fs = [_]*const fn (u32) u32{ sq, inc };
    var s: u32 = 0;
    for (buf[0..n]) |x| s += apply(fs[x % 2], x);
    return @intCast(s);
}
