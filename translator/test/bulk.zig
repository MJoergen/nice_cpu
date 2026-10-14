// get is imported from env: get(i) = i + 100. It keeps Zig from folding
// the calls below at compile time.
extern fn get(i: i32) i32;

var buf: [64]u8 = undefined;

fn sum(s: []const u8) i32 {
    var t: i32 = 0;
    for (s) |b| t += b;
    return t;
}

export fn main() i32 {
    const n: usize = @intCast(get(-60)); // 40
    const m: usize = @intCast(get(-90)); // 10, so that the lengths are not constant
    for (buf[0..n], 0..) |*b, i| b.* = @intCast(i); // 0, 1, ..., 39
    @memcpy(buf[40 .. 40 + m], buf[3 .. 3 + m]); // 3 to 12
    @memset(buf[50 .. 50 + m], @intCast(get(-93))); // ten 7s
    @memmove(buf[1 .. 1 + 2 * m], buf[0 .. 2 * m]); // shifts 0 to 19 up by one
    return sum(buf[40..50]) + sum(buf[50..60]) + 1000 * @as(i32, buf[20]);
}
