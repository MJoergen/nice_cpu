// The sequences of the FPU's functions, DEVICES.md §11.3. Written by
// test/fpu_seq.py --zig from its programs; make test checks that it is
// current. Do not edit.

pub const Op = enum { cmd, k, put, jz, jmp, pole };
pub const Step = struct { op: Op, n: u32 };
pub const Program = struct { num: u8, pops: u2, steps: []const Step };

pub const constants = [_]u64{
    0x3FE921FC00000000, // H3FE921FC
    0x3E50000000000000, // H3E500000
    0x3DE5D93A5ACFD57C, // S6
    0xBE5AE5E68A2B9CEB, // S5
    0x3EC71DE357B1FE7D, // S4
    0xBF2A01A019C161D5, // S3
    0x3F8111111110F8A6, // S2
    0xBFC5555555555549, // S1
    0x413921FB00000000, // H413921FB
    0x7FF8000000000000, // nan
    0x400F6A7B00000000, // H400F6A7B
    0x3FF921FB00000000, // H3FF921FB
    0x3FF921FC00000000, // H3FF921FC
    0x400921FB00000000, // H400921FB
    0x400921FC00000000, // H400921FC
    0x4002D97D00000000, // H4002D97D
    0x0000000000000000, // 0.0
    0x3FF921FB54400000, // pio2_1
    0x3DD0B4611A626331, // pio2_1t
    0x3FF0000000000000, // 1.0
    0xBFF0000000000000, // -1.0
    0x400921FB54400000, // 2*pio2_1
    0x3DE0B4611A626331, // 2*pio2_1t
    0x4000000000000000, // 2.0
    0xC000000000000000, // -2.0
    0x4015FDBD00000000, // H4015FDBD
    0x4012D97C00000000, // H4012D97C
    0x4012D97D00000000, // H4012D97D
    0x4012D97C7F300000, // 3*pio2_1
    0x3DE90E91A79394CA, // 3*pio2_1t
    0x4008000000000000, // 3.0
    0xC008000000000000, // -3.0
    0x401C463C00000000, // H401C463C
    0x401921FB00000000, // H401921FB
    0x401921FC00000000, // H401921FC
    0x401921FB54400000, // 4*pio2_1
    0x3DF0B4611A626331, // 4*pio2_1t
    0x4010000000000000, // 4.0
    0xC010000000000000, // -4.0
    0x3FE45F306DC9C883, // invpio2
    0xBFE921FB54442D18, // -pio4
    0x3FE921FB54442D18, // pio4
    0x4030000000000000, // 16.0
    0x3DD0B4611A600000, // pio2_2
    0x3BA3198A2E037073, // pio2_2t
    0x4048800000000000, // 49.0
    0x3BA3198A2E000000, // pio2_3
    0x397B839A252049C1, // pio2_3t
    0x3FE0000000000000, // 0.5
    0xBDA8FAE9BE8838D4, // C6
    0x3E21EE9EBDB4B1C4, // C5
    0xBE927E4F809C52AD, // C4
    0x3EFA01A019CB1590, // C3
    0xBF56C16C16C15177, // C2
    0x3FA555555555554C, // C1
    0x3E46A09E00000000, // H3E46A09E
    0x3E40000000000000, // H3E400000
    0x3FE5942800000000, // H3FE59428
    0x3C81A62633145C07, // pio4lo
    0xBEF375CBDB605373, // T11
    0x3F147E88A03792A6, // T9
    0x3F4344D8F2F26501, // T7
    0x3F6D6D22C9560328, // T5
    0x3F9664F48406D637, // T3
    0x3FC111111110FE7A, // T1
    0x3EFB2A7074BF7AD4, // T12
    0x3F12B80F32F0A7E9, // T10
    0x3F3026F71A8D1068, // T8
    0x3F57DBC8FEE08315, // T6
    0x3F8226E3E96E8493, // T4
    0x3FABA1BA1BB341FE, // T2
    0x3FD5555555555563, // T0
};

const sin_steps = [_]Step{
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 0 }, // H3FE921FC
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 67 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 1 }, // H3E500000
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 17 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 745 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 2 }, // S6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 3 }, // S5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 4 }, // S4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 5 }, // S3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 6 }, // S2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 7 }, // S1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 65 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 745 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 8 }, // H413921FB
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 76 },
    .{ .op = .k, .n = 9 }, // nan
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 745 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 10 }, // H400F6A7B
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 201 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 11 }, // H3FF921FB
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 97 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 12 }, // H3FF921FC
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 97 },
    .{ .op = .jmp, .n = 107 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 13 }, // H400921FB
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 108 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 14 }, // H400921FC
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 108 },
    .{ .op = .jmp, .n = 201 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 15 }, // H4002D97D
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 157 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 16 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 137 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 17 }, // pio2_1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 18 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 18 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 473 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 17 }, // pio2_1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 18 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 20 }, // -1.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 18 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 473 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 16 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 181 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 21 }, // 2*pio2_1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 22 }, // 2*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 23 }, // 2.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 22 }, // 2*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 473 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 21 }, // 2*pio2_1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 22 }, // 2*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 24 }, // -2.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 22 }, // 2*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 473 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 10 }, // H400F6A7B
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 266 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 25 }, // H4015FDBD
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 266 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 26 }, // H4012D97C
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 222 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 27 }, // H4012D97D
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 222 },
    .{ .op = .jmp, .n = 266 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 16 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 246 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 28 }, // 3*pio2_1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 29 }, // 3*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 30 }, // 3.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 29 }, // 3*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 473 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 28 }, // 3*pio2_1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 29 }, // 3*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 31 }, // -3.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 29 }, // 3*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 473 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 25 }, // H4015FDBD
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 331 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 32 }, // H401C463C
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 331 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 33 }, // H401921FB
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 287 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 34 }, // H401921FC
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 287 },
    .{ .op = .jmp, .n = 331 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 16 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 311 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 35 }, // 4*pio2_1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 36 }, // 4*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 37 }, // 4.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 36 }, // 4*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 473 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 35 }, // 4*pio2_1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 36 }, // 4*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 38 }, // -4.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 36 }, // 4*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 473 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 39 }, // invpio2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0023 }, // NEAREST
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 17 }, // pio2_1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 18 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 40 }, // -pio4
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 369 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 17 }, // pio2_1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 18 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .jmp, .n = 391 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 41 }, // pio4
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 391 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 17 }, // pio2_1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 18 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .jmp, .n = 391 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 42 }, // 16.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 461 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 43 }, // pio2_2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 44 }, // pio2_2t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 45 }, // 49.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 460 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 46 }, // pio2_3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 47 }, // pio2_3t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .jmp, .n = 460 },
    .{ .op = .jmp, .n = 461 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 473 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 30 }, // 3.0
    .{ .op = .cmd, .n = 0x0060 }, // AND
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 16 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 540 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 2 }, // S6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 3 }, // S5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 4 }, // S4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 5 }, // S3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 6 }, // S2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .k, .n = 48 }, // 0.5
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 7 }, // S1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 538 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 745 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 610 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 49 }, // C6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 50 }, // C5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 51 }, // C4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 52 }, // C3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 53 }, // C2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 54 }, // C1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 48 }, // 0.5
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 608 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 745 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 23 }, // 2.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 676 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 2 }, // S6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 3 }, // S5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 4 }, // S4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 5 }, // S3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 6 }, // S2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .k, .n = 48 }, // 0.5
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 7 }, // S1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 672 },
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 745 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 49 }, // C6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 50 }, // C5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 51 }, // C4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 52 }, // C3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 53 }, // C2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 54 }, // C1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 48 }, // 0.5
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 741 },
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 745 },
};

const cos_steps = [_]Step{
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 0 }, // H3FE921FC
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 83 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 55 }, // H3E46A09E
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 17 },
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 761 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 49 }, // C6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 50 }, // C5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 51 }, // C4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 52 }, // C3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 53 }, // C2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 54 }, // C1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 48 }, // 0.5
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 16 }, // 0.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 81 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 761 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 8 }, // H413921FB
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 92 },
    .{ .op = .k, .n = 9 }, // nan
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 761 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 10 }, // H400F6A7B
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 217 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 11 }, // H3FF921FB
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 113 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 12 }, // H3FF921FC
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 113 },
    .{ .op = .jmp, .n = 123 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 13 }, // H400921FB
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 124 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 14 }, // H400921FC
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 124 },
    .{ .op = .jmp, .n = 217 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 15 }, // H4002D97D
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 173 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 16 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 153 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 17 }, // pio2_1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 18 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 18 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 489 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 17 }, // pio2_1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 18 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 20 }, // -1.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 18 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 489 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 16 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 197 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 21 }, // 2*pio2_1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 22 }, // 2*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 23 }, // 2.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 22 }, // 2*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 489 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 21 }, // 2*pio2_1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 22 }, // 2*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 24 }, // -2.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 22 }, // 2*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 489 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 10 }, // H400F6A7B
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 282 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 25 }, // H4015FDBD
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 282 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 26 }, // H4012D97C
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 238 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 27 }, // H4012D97D
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 238 },
    .{ .op = .jmp, .n = 282 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 16 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 262 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 28 }, // 3*pio2_1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 29 }, // 3*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 30 }, // 3.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 29 }, // 3*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 489 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 28 }, // 3*pio2_1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 29 }, // 3*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 31 }, // -3.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 29 }, // 3*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 489 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 25 }, // H4015FDBD
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 347 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 32 }, // H401C463C
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 347 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 33 }, // H401921FB
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 303 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 34 }, // H401921FC
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 303 },
    .{ .op = .jmp, .n = 347 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 16 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 327 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 35 }, // 4*pio2_1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 36 }, // 4*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 37 }, // 4.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 36 }, // 4*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 489 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 35 }, // 4*pio2_1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 36 }, // 4*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 38 }, // -4.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 36 }, // 4*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 489 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 39 }, // invpio2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0023 }, // NEAREST
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 17 }, // pio2_1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 18 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 40 }, // -pio4
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 385 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 17 }, // pio2_1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 18 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .jmp, .n = 407 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 41 }, // pio4
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 407 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 17 }, // pio2_1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 18 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .jmp, .n = 407 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 42 }, // 16.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 477 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 43 }, // pio2_2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 44 }, // pio2_2t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 45 }, // 49.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 476 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 46 }, // pio2_3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 47 }, // pio2_3t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .jmp, .n = 476 },
    .{ .op = .jmp, .n = 477 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 489 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 30 }, // 3.0
    .{ .op = .cmd, .n = 0x0060 }, // AND
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 16 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 563 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 49 }, // C6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 50 }, // C5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 51 }, // C4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 52 }, // C3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 53 }, // C2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 54 }, // C1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 48 }, // 0.5
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 561 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 761 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 629 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 2 }, // S6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 3 }, // S5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 4 }, // S4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 5 }, // S3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 6 }, // S2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .k, .n = 48 }, // 0.5
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 7 }, // S1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 625 },
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 761 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 23 }, // 2.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 702 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 49 }, // C6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 50 }, // C5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 51 }, // C4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 52 }, // C3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 53 }, // C2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 54 }, // C1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 48 }, // 0.5
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 698 },
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 761 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 2 }, // S6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 3 }, // S5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 4 }, // S4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 5 }, // S3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 6 }, // S2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .k, .n = 48 }, // 0.5
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 7 }, // S1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 759 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 761 },
};

const tan_steps = [_]Step{
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 0 }, // H3FE921FC
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 178 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 56 }, // H3E400000
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 17 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 785 },
    .{ .op = .k, .n = 16 }, // 0.0
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0B06 }, // PICK 11
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 57 }, // H3FE59428
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .put, .n = 6 },
    .{ .op = .cmd, .n = 0x0B06 }, // PICK 11
    .{ .op = .k, .n = 16 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .jz, .n = 56 },
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .jz, .n = 45 },
    .{ .op = .cmd, .n = 0x0B06 }, // PICK 11
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 11 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 7 },
    .{ .op = .jmp, .n = 45 },
    .{ .op = .k, .n = 41 }, // pio4
    .{ .op = .cmd, .n = 0x0C06 }, // PICK 12
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 58 }, // pio4lo
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 11 },
    .{ .op = .k, .n = 16 }, // 0.0
    .{ .op = .put, .n = 7 },
    .{ .op = .jmp, .n = 56 },
    .{ .op = .cmd, .n = 0x0B06 }, // PICK 11
    .{ .op = .cmd, .n = 0x0C06 }, // PICK 12
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 59 }, // T11
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 60 }, // T9
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 61 }, // T7
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 62 }, // T5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 63 }, // T3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 64 }, // T1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 65 }, // T12
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 66 }, // T10
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 67 }, // T8
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 68 }, // T6
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 69 }, // T4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 70 }, // T2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0C06 }, // PICK 12
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 71 }, // T0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0B06 }, // PICK 11
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .jz, .n = 172 },
    .{ .op = .k, .n = 23 }, // 2.0
    .{ .op = .k, .n = 16 }, // 0.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0C06 }, // PICK 12
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .k, .n = 23 }, // 2.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .jz, .n = 168 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 11 },
    .{ .op = .cmd, .n = 0x0803 }, // DROP 8
    .{ .op = .jmp, .n = 176 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .put, .n = 11 },
    .{ .op = .cmd, .n = 0x0803 }, // DROP 8
    .{ .op = .jmp, .n = 176 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .put, .n = 11 },
    .{ .op = .cmd, .n = 0x0803 }, // DROP 8
    .{ .op = .jmp, .n = 176 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 785 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 8 }, // H413921FB
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 187 },
    .{ .op = .k, .n = 9 }, // nan
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 785 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 10 }, // H400F6A7B
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 312 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 11 }, // H3FF921FB
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 208 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 12 }, // H3FF921FC
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 208 },
    .{ .op = .jmp, .n = 218 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 13 }, // H400921FB
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 219 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 14 }, // H400921FC
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 219 },
    .{ .op = .jmp, .n = 312 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 15 }, // H4002D97D
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 268 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 16 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 248 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 17 }, // pio2_1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 18 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 18 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 584 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 17 }, // pio2_1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 18 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 20 }, // -1.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 18 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 584 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 16 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 292 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 21 }, // 2*pio2_1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 22 }, // 2*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 23 }, // 2.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 22 }, // 2*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 584 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 21 }, // 2*pio2_1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 22 }, // 2*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 24 }, // -2.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 22 }, // 2*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 584 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 10 }, // H400F6A7B
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 377 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 25 }, // H4015FDBD
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 377 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 26 }, // H4012D97C
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 333 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 27 }, // H4012D97D
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 333 },
    .{ .op = .jmp, .n = 377 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 16 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 357 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 28 }, // 3*pio2_1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 29 }, // 3*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 30 }, // 3.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 29 }, // 3*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 584 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 28 }, // 3*pio2_1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 29 }, // 3*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 31 }, // -3.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 29 }, // 3*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 584 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 25 }, // H4015FDBD
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 442 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 32 }, // H401C463C
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 442 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 33 }, // H401921FB
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 398 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 34 }, // H401921FC
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 398 },
    .{ .op = .jmp, .n = 442 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 16 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 422 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 35 }, // 4*pio2_1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 36 }, // 4*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 37 }, // 4.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 36 }, // 4*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 584 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 35 }, // 4*pio2_1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 36 }, // 4*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 38 }, // -4.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 36 }, // 4*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 584 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 39 }, // invpio2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0023 }, // NEAREST
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 17 }, // pio2_1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 18 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 40 }, // -pio4
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 480 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 17 }, // pio2_1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 18 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .jmp, .n = 502 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 41 }, // pio4
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 502 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 17 }, // pio2_1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 18 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .jmp, .n = 502 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 42 }, // 16.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 572 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 43 }, // pio2_2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 44 }, // pio2_2t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 45 }, // 49.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 571 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 46 }, // pio2_3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 47 }, // pio2_3t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .jmp, .n = 571 },
    .{ .op = .jmp, .n = 572 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 584 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .cmd, .n = 0x0060 }, // AND
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 57 }, // H3FE59428
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .put, .n = 6 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 16 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .jz, .n = 626 },
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .jz, .n = 615 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 8 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 7 },
    .{ .op = .jmp, .n = 615 },
    .{ .op = .k, .n = 41 }, // pio4
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 58 }, // pio4lo
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 8 },
    .{ .op = .k, .n = 16 }, // 0.0
    .{ .op = .put, .n = 7 },
    .{ .op = .jmp, .n = 626 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 59 }, // T11
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 60 }, // T9
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 61 }, // T7
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 62 }, // T5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 63 }, // T3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 64 }, // T1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 65 }, // T12
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 66 }, // T10
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 67 }, // T8
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 68 }, // T6
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 69 }, // T4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 70 }, // T2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 71 }, // T0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .jz, .n = 742 },
    .{ .op = .k, .n = 23 }, // 2.0
    .{ .op = .cmd, .n = 0x0A06 }, // PICK 10
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .k, .n = 23 }, // 2.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .jz, .n = 738 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 10 },
    .{ .op = .cmd, .n = 0x0703 }, // DROP 7
    .{ .op = .jmp, .n = 783 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .put, .n = 10 },
    .{ .op = .cmd, .n = 0x0703 }, // DROP 7
    .{ .op = .jmp, .n = 783 },
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .k, .n = 16 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 750 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .put, .n = 10 },
    .{ .op = .cmd, .n = 0x0703 }, // DROP 7
    .{ .op = .jmp, .n = 783 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x001F }, // CHOP
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 20 }, // -1.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x001F }, // CHOP
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 19 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 10 },
    .{ .op = .cmd, .n = 0x0703 }, // DROP 7
    .{ .op = .jmp, .n = 783 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 785 },
};

pub const programs = [_]Program{
    .{ .num = 0x40, .pops = 1, .steps = &sin_steps },
    .{ .num = 0x41, .pops = 1, .steps = &cos_steps },
    .{ .num = 0x42, .pops = 1, .steps = &tan_steps },
};
