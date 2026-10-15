// nice.zig: the console and the performance counters. It prints a line
// with std.fmt, echoes the console input in upper case until it ends, and
// checks the counters as libc/test/nice.c does. main returns the number of
// bytes it read, 4 with test/nicezig.input.
const nice = @import("nice");

export fn main() i32 {
    nice.print("{s} {d} 0x{x}\n", .{ "Zig", 42, 0xBEEF });
    const cycles = nice.counter64(nice.cycle_lo);
    const instrs = nice.counter64(nice.instr_lo);
    var n: i32 = 0;
    while (nice.getchar()) |c| : (n += 1) {
        const u = if (c >= 'a' and c <= 'z') c - 32 else c;
        nice.write(&.{u});
    }
    const instrs2 = nice.counter64(nice.instr_lo);
    const cycles2 = nice.counter64(nice.cycle_lo);
    nice.print("{} {}\n", .{ instrs2 > instrs, cycles2 - cycles > instrs2 - instrs });
    return n;
}
