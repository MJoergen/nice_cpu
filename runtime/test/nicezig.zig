// nice.zig: the console, the performance counters, and the screen. It
// prints a line with std.fmt, echoes the console input in upper case until
// it ends, checks that pollc then finds the end, checks the counters as
// libc/test/nice.c does, and reads back what it wrote to the screen. main
// returns the number of bytes it read, 4 with test/nicezig.input.
const nice = @import("nice");

export fn main() i32 {
    nice.print("{s} {d} 0x{x}\n", .{ "Zig", 42, 0xBEEF });
    const cycles = nice.cycles();
    const instrs = nice.instructions();
    var n: i32 = 0;
    while (nice.getc()) |c| : (n += 1) {
        nice.putc(if (c >= 'a' and c <= 'z') c - 32 else c);
    }
    const instrs2 = nice.instructions();
    const cycles2 = nice.cycles();
    nice.print("{} {} {}\n", .{ nice.pollc() == .end, instrs2 > instrs, cycles2 - cycles > instrs2 - instrs });

    nice.screenClear();
    nice.screenPut(2, 1, 0xC80FF021);
    nice.screenPut(nice.screen_cols - 1, nice.screen_rows - 1, 'Z');
    const screen: u32 = 0xFFFF0000;
    nice.print("{x} {x} {x}\n", .{ nice.peek(screen), nice.peek(screen + 82), nice.peek(screen + 1999) });
    return n;
}
