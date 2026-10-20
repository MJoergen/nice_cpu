// nice.zig: what test/nicezig.zig leaves out. pollc returns .byte for a
// waiting byte, getc then reads the next one, and at the end of the input
// pollc returns .end and getc null, again and again. poke writes a NICE
// word that peek reads back. The console input is test/zigpoll.input,
// "ab", so the output is "true 61 62" and "true true true true". main
// returns 0x5A, the word that poke wrote and peek read back.
const nice = @import("nice");

export fn main() i32 {
    const p = nice.pollc();
    const b = nice.getc();
    nice.print("{} {x} {x}\n", .{ p == .byte, p.byte, b.? });
    nice.print("{} {} {} {}\n", .{ nice.pollc() == .end, nice.getc() == null, nice.pollc() == .end, nice.getc() == null });

    const word: u32 = 0xFFFF0000 + 80 * 3 + 4; // the screen, row 3, column 4
    nice.poke(word, 0x5A);
    return @intCast(nice.peek(word));
}
