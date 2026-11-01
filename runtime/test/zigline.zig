// nice.zig: readLine, with a buffer of 16 bytes, on test/zigline.input.
// It prints each line in brackets, with the bytes outside 0x20 to 0x7E as
// \xNN, and its length, then the sum of the numbers of the first line,
// parsed with std. The input checks a "\r" before the "\n" (dropped) and
// inside the line (kept), an empty line, lines cut off at 16 bytes, with
// a "\r" past the cut and one just inside it, and a last line with no
// "\n". After it, readLine returns null, twice. test/rustline.rs reads
// the same input. main returns the number of lines read, 10.
const std = @import("std");
const nice = @import("nice");

fn show(line: []const u8) void {
    nice.putc('[');
    for (line) |c| {
        if (c >= 0x20 and c <= 0x7E) nice.putc(c) else nice.print("\\x{x:0>2}", .{c});
    }
    nice.print("] {d}\n", .{line.len});
}

export fn main() i32 {
    var buf: [16]u8 = undefined;
    var count: i32 = 0;
    var sum: i32 = 0;
    while (nice.readLine(&buf)) |line| {
        show(line);
        if (count == 0) {
            var it = std.mem.tokenizeAny(u8, line, " ");
            while (it.next()) |w| sum += std.fmt.parseInt(i32, w, 10) catch 0;
        }
        count += 1;
    }
    nice.print("sum {d} {} {}\n", .{ sum, nice.readLine(&buf) == null, nice.readLine(&buf) == null });
    return count;
}
