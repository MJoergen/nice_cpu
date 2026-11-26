// The sequences of the FPU's functions, DEVICES.md §11.3. Written by
// test/fpu_seq.py --zig from its programs; make test checks that it is
// current. Do not edit.
//
// The programs follow C code of fdlibm, FreeBSD, and musl, whose notices
// are in the header of test/fpu_seq.py.

pub const Op = enum { cmd, k, put, jz, jmp, pole, kx };
pub const Step = struct { op: Op, n: u32 };
pub const Program = struct { num: u8, pops: u2, steps: []const Step };

pub const constants = [_]u64{
    0x0000000000000000, // ipio2[0]
    0x0000000000000000, // ipio2[1]
    0x41645F3060000000, // ipio2[2]
    0x415B939100000000, // ipio2[3]
    0x413529FC00000000, // ipio2[4]
    0x4143ABE880000000, // ipio2[5]
    0x416EA69BA0000000, // ipio2[6]
    0x41681B6C40000000, // ipio2[7]
    0x4162B32780000000, // ipio2[8]
    0x4150E41040000000, // ipio2[9]
    0x416FCA2C60000000, // ipio2[10]
    0x41657BD760000000, // ipio2[11]
    0x4168AC36E0000000, // ipio2[12]
    0x4142371D00000000, // ipio2[13]
    0x4150937480000000, // ipio2[14]
    0x416C00C920000000, // ipio2[15]
    0x4147750480000000, // ipio2[16]
    0x416A324380000000, // ipio2[17]
    0x416FC3BD60000000, // ipio2[18]
    0x413CB12900000000, // ipio2[19]
    0x4164E7DD00000000, // ipio2[20]
    0x416046BEA0000000, // ipio2[21]
    0x41475DA200000000, // ipio2[22]
    0x41609D3380000000, // ipio2[23]
    0x415C09AD00000000, // ipio2[24]
    0x4157DF9040000000, // ipio2[25]
    0x414CC8EB00000000, // ipio2[26]
    0x414CC1A980000000, // ipio2[27]
    0x414CFA4E00000000, // ipio2[28]
    0x41608BF160000000, // ipio2[29]
    0x4167BF2500000000, // ipio2[30]
    0x414D8FFC00000000, // ipio2[31]
    0x4162FFFBC0000000, // ipio2[32]
    0x4116603C00000000, // ipio2[33]
    0x416DE5E220000000, // ipio2[34]
    0x41616B4140000000, // ipio2[35]
    0x415B47DB40000000, // ipio2[36]
    0x414B3F6780000000, // ipio2[37]
    0x4143E58480000000, // ipio2[38]
    0x4166E9E8C0000000, // ipio2[39]
    0x414FB34F00000000, // ipio2[40]
    0x4157FA8B40000000, // ipio2[41]
    0x415D49EE80000000, // ipio2[42]
    0x4168FD7CA0000000, // ipio2[43]
    0x416E2F67A0000000, // ipio2[44]
    0x411CE7DC00000000, // ipio2[45]
    0x41614A5240000000, // ipio2[46]
    0x416D4D7F60000000, // ipio2[47]
    0x4157EC47C0000000, // ipio2[48]
    0x4161ABA100000000, // ipio2[49]
    0x415580CC00000000, // ipio2[50]
    0x3FE921FC00000000, // H3FE921FC
    0x3E50000000000000, // H3E500000
    0x3DE5D93A5ACFD57C, // S6
    0xBE5AE5E68A2B9CEB, // S5
    0x3EC71DE357B1FE7D, // S4
    0xBF2A01A019C161D5, // S3
    0x3F8111111110F8A6, // S2
    0xBFC5555555555549, // S1
    0x7FF0000000000000, // H7FF00000
    0x7FF8000000000000, // nan
    0x413921FB00000000, // H413921FB
    0x4037000000000000, // 23.0
    0x4170000000000000, // 16777216.0
    0x4008000000000000, // 3.0
    0x4038000000000000, // 24.0
    0x0000000000000000, // 0.0
    0x4330000000000000, // 4503599627370496.0
    0x4022000000000000, // 9.0
    0x4020000000000000, // 8.0
    0x401C000000000000, // 7.0
    0x3E70000000000000, // 5.960464477539063e-08
    0x4018000000000000, // 6.0
    0x4014000000000000, // 5.0
    0x4010000000000000, // 4.0
    0x4000000000000000, // 2.0
    0x3FF0000000000000, // 1.0
    0x3FC0000000000000, // 0.125
    0x3FE0000000000000, // 0.5
    0x42F0000000000000, // 281474976710656.0
    0x3CF0000000000000, // 3.552713678800501e-15
    0x4065000000000000, // 168.0
    0x405E000000000000, // 120.0
    0x4052000000000000, // 72.0
    0x3FF921FB54442D18, // pio2_hi
    0x3C91A62633145C07, // pio2_lo
    0xBDA8FAE9BE8838D4, // C6
    0x3E21EE9EBDB4B1C4, // C5
    0xBE927E4F809C52AD, // C4
    0x3EFA01A019CB1590, // C3
    0xBF56C16C16C15177, // C2
    0x3FA555555555554C, // C1
    0x400F6A7B00000000, // H400F6A7B
    0x3FF921FB00000000, // H3FF921FB
    0x3FF921FC00000000, // H3FF921FC
    0x400921FB00000000, // H400921FB
    0x400921FC00000000, // H400921FC
    0x4002D97D00000000, // H4002D97D
    0x3FF921FB54400000, // pio2_1
    0x3DD0B4611A626331, // pio2_1t
    0xBFF0000000000000, // -1.0
    0x400921FB54400000, // 2*pio2_1
    0x3DE0B4611A626331, // 2*pio2_1t
    0xC000000000000000, // -2.0
    0x4015FDBD00000000, // H4015FDBD
    0x4012D97C00000000, // H4012D97C
    0x4012D97D00000000, // H4012D97D
    0x4012D97C7F300000, // 3*pio2_1
    0x3DE90E91A79394CA, // 3*pio2_1t
    0xC008000000000000, // -3.0
    0x401C463C00000000, // H401C463C
    0x401921FB00000000, // H401921FB
    0x401921FC00000000, // H401921FC
    0x401921FB54400000, // 4*pio2_1
    0x3DF0B4611A626331, // 4*pio2_1t
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
    0x3870000000000000, // tiny
    0x0010000000000000, // H00100000
    0x3F023DE10DFDF709, // pS5
    0x3F49EFE07501B288, // pS4
    0xBFA48228B5688F3B, // pS3
    0x3FC9C1550E884455, // pS2
    0xBFD4D61203EB6F7D, // pS1
    0x3FC5555555555555, // pS0
    0x3FB3B8C5B12E9282, // qS4
    0xBFE6066C1B8D0159, // qS3
    0x40002AE59C598AC8, // qS2
    0xC0033A271C8A2D4B, // qS1
    0x3FEF333300000000, // H3FEF3333
    0x400921FB54442D18, // pi
    0x3C60000100000000, // H3C600001
    0x4410000000000000, // H44100000
    0xBFF921FB54442D18, // -pio2_hi+tiny
    0x3FDC000000000000, // H3FDC0000
    0x3FF3000000000000, // H3FF30000
    0x3FE6000000000000, // H3FE60000
    0x3FDDAC670561BB4F, // atanhi0
    0x3C7A2B7F222F65E2, // atanlo0
    0x4003800000000000, // H40038000
    0x3FEF730BD281F69B, // atanhi2
    0x3C7007887AF0CBBD, // atanlo2
    0x3FF8000000000000, // 1.5
    0x3F90AD3AE322DA11, // aT10
    0x3FA97B4B24760DEB, // aT8
    0x3FB10D66A0D03D51, // aT6
    0x3FB745CDC54C206E, // aT4
    0x3FC24924920083FF, // aT2
    0x3FD555555555550D, // aT0
    0xBFA2B4442C6A6C2F, // aT9
    0xBFADDE2D52DEFD9A, // aT7
    0xBFB3B0F2AF749A6D, // aT5
    0xBFBC71C6FE231671, // aT3
    0xBFC999999998EBC4, // aT1
    0xC00921FB54442D18, // -pi
    0xBFF921FB54442D18, // -pi/2
    0xC002D97C7F3321D2, // -3*pi/4
    0x4002D97C7F3321D2, // 3*pi/4
    0xBFE921FB54442D18, // -pi/4
    0x8000000000000000, // -0.0
    0x4390000000000000, // 2.8823037615171174e+17
    0x3CA1A62633145C07, // pi_lo
    0xFFF0000000000000, // -H7FF00000
    0x3FF6A09C00000000, // 1.4142112731933594
    0x3FEFFFFE00000000, // H3FEFFFFE
    0x3FF0000100000000, // H3FF00001
    0x3FE62E42FEE00000, // ln2_hi
    0x3DEA39EF35793C76, // ln2_lo
    0x3FD5555555555555, // 0.3333333333333333
    0x3FC39A09D078C69F, // Lg6
    0x3FCC71C51D8E78AF, // Lg4
    0x3FD999999997FA04, // Lg2
    0x3FC2F112DF3E5244, // Lg7
    0x3FC7466496CB03DE, // Lg5
    0x3FD2492494229359, // Lg3
    0x3FE5555555555593, // Lg1
    0x3FF6147A00000000, // H3FF6147A
    0x3FE6B85200000000, // H3FE6B852
    0x3FF7154765200000, // ivln2hi
    0x3DE705FC2EEFA200, // ivln2lo
    0x3FF6A09E00000000, // 1.4142131805419922
    0x3FDBCB7B15200000, // ivln10hi
    0x3FD34413509F6000, // log10_2hi
    0x3D59FEF311F12B36, // log10_2lo
    0x3DBB9438CA9AADD5, // ivln10lo
    0x40862E4200000000, // H40862E42
    0x40862E42FEFA39EF, // o_threshold
    0xC0874910D52D3051, // u_threshold
    0x3FD62E4300000000, // H3FD62E43
    0x3FF0A2B200000000, // H3FF0A2B2
    0xBDEA39EF35793C76, // -ln2_lo
    0x3FF71547652B82FE, // invln2
    0x3E30000000000000, // H3E300000
    0x3E66376972BEA4D0, // P5
    0xBEBBBD41C5D26BF1, // P4
    0x3F11566AAF25DE2C, // P3
    0xBF66C16C16BEBD93, // P2
    0x3FC555555555553E, // P1
    0x41E0000100000000, // H41E00001
    0x4090000000000000, // 1024.0
    0x3C971547652B82FE, // ovt
    0xC090CC0000000000, // -1075.0
    0x3FE0000100000000, // H3FE00001
    0x3FE62E4300000000, // lg2_h
    0x3FE62E42FEFA39EF, // lg2
    0xBE205C610CA86C39, // lg2_l
    0x43F0000100000000, // H43F00001
    0x3FEFFFFF00000000, // H3FEFFFFF
    0x3FFBB67A00000000, // H3FFBB67A
    0x3FF3988F00000000, // H3FF3988F
    0x3FCA7E284A454EEF, // pL6
    0x3FCD864A93C9DB65, // pL5
    0x3FD17460A91D4101, // pL4
    0x3FD55555518F264D, // pL3
    0x3FDB6DB6DB6FABFF, // pL2
    0x3FE3333333333303, // pL1
    0x3FEEC709E0000000, // cp_h
    0xBE3E2FE0145B01F5, // cp_l
    0x3FEEC709DC3A03FD, // cp
    0x3E5CFDEB43CFD006, // 2.0*dp_l1
    0x3FF2B80340000000, // 2.0*dp_h1
    0xC08FF80000000000, // -1023.0
    0x4050000000000000, // 64.0
    0x5FE0000000000000, // H5FE00000
    0x6BB0000000000000, // H6BB00000
    0x1430000000000000, // H14300000
    0x23D0000000000000, // H23D00000
};

const sin_steps = [_]Step{
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 51 }, // H3FE921FC
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 55 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 52 }, // H3E500000
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 13 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 1498 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 53 }, // S6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 54 }, // S5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 55 }, // S4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 56 }, // S3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 57 }, // S2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 58 }, // S1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 54 },
    .{ .op = .jmp, .n = 1498 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 59 }, // H7FF00000
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 63 },
    .{ .op = .k, .n = 60 }, // nan
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 1498 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 61 }, // H413921FB
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 860 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .k, .n = 62 }, // 23.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 64 }, // 3.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x0018 }, // MAX
    .{ .op = .k, .n = 67 }, // 4503599627370496.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 68 }, // 9.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 69 }, // 8.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 70 }, // 7.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 69 }, // 8.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 70 }, // 7.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 72 }, // 6.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 70 }, // 7.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 72 }, // 6.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 73 }, // 5.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 72 }, // 6.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 73 }, // 5.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 74 }, // 4.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 73 }, // 5.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 74 }, // 4.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 64 }, // 3.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 74 }, // 4.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 64 }, // 3.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 6 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 64 }, // 3.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 6 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0A06 }, // PICK 10
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .k, .n = 62 }, // 23.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .k, .n = 67 }, // 4503599627370496.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 8 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 77 }, // 0.125
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 69 }, // 8.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .put, .n = 6 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 456 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 6 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0A06 }, // PICK 10
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 62 }, // 23.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .put, .n = 5 },
    .{ .op = .jmp, .n = 463 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 463 },
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .put, .n = 5 },
    .{ .op = .jmp, .n = 463 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 585 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 6 },
    .{ .op = .k, .n = 79 }, // 281474976710656.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 80 }, // 3.552713678800501e-15
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .put, .n = 4 },
    .{ .op = .k, .n = 79 }, // 281474976710656.0
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 79 }, // 281474976710656.0
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 80 }, // 3.552713678800501e-15
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .put, .n = 4 },
    .{ .op = .k, .n = 79 }, // 281474976710656.0
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .k, .n = 79 }, // 281474976710656.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 80 }, // 3.552713678800501e-15
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .put, .n = 4 },
    .{ .op = .k, .n = 79 }, // 281474976710656.0
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .put, .n = 4 },
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 569 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0A06 }, // PICK 10
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 569 },
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 584 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0A06 }, // PICK 10
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .jmp, .n = 584 },
    .{ .op = .jmp, .n = 585 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 81 }, // 168.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 82 }, // 120.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .k, .n = 83 }, // 72.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 684 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 684 },
    .{ .op = .cmd, .n = 0x0A06 }, // PICK 10
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 698 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 698 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 84 }, // pio2_hi
    .{ .op = .cmd, .n = 0x001E }, // XMUL
    .{ .op = .put, .n = 6 },
    .{ .op = .put, .n = 9 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 85 }, // pio2_lo
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 84 }, // pio2_hi
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0060 }, // AND
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 788 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 53 }, // S6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 54 }, // S5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 55 }, // S4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 56 }, // S3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 57 }, // S2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 58 }, // S1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 787 },
    .{ .op = .jmp, .n = 844 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 86 }, // C6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 87 }, // C5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 88 }, // C4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 89 }, // C3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 90 }, // C2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 91 }, // C1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 844 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0060 }, // AND
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x051C }, // CMP 5
    .{ .op = .jz, .n = 855 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 859 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 859 },
    .{ .op = .jmp, .n = 1498 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 92 }, // H400F6A7B
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 986 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 93 }, // H3FF921FB
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 882 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 94 }, // H3FF921FC
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 882 },
    .{ .op = .jmp, .n = 892 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 95 }, // H400921FB
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 893 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 96 }, // H400921FC
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 893 },
    .{ .op = .jmp, .n = 986 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 97 }, // H4002D97D
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 942 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 922 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 98 }, // pio2_1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 99 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 99 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1256 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 98 }, // pio2_1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 99 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 100 }, // -1.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 99 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1256 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 966 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 101 }, // 2*pio2_1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 102 }, // 2*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 102 }, // 2*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1256 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 101 }, // 2*pio2_1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 102 }, // 2*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 103 }, // -2.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 102 }, // 2*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1256 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 92 }, // H400F6A7B
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 1051 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 104 }, // H4015FDBD
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 1051 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 105 }, // H4012D97C
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 1007 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 106 }, // H4012D97D
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 1007 },
    .{ .op = .jmp, .n = 1051 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 1031 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 107 }, // 3*pio2_1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 108 }, // 3*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 64 }, // 3.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 108 }, // 3*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1256 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 107 }, // 3*pio2_1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 108 }, // 3*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 109 }, // -3.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 108 }, // 3*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1256 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 104 }, // H4015FDBD
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 1116 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 110 }, // H401C463C
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 1116 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 111 }, // H401921FB
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 1072 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 112 }, // H401921FC
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 1072 },
    .{ .op = .jmp, .n = 1116 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 1096 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 113 }, // 4*pio2_1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 114 }, // 4*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 74 }, // 4.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 114 }, // 4*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1256 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 113 }, // 4*pio2_1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 114 }, // 4*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 115 }, // -4.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 114 }, // 4*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1256 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 116 }, // invpio2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0023 }, // NEAREST
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 98 }, // pio2_1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 99 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 117 }, // -pio4
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 1152 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 98 }, // pio2_1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 99 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 1174 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 118 }, // pio4
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 1174 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 98 }, // pio2_1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 99 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 1174 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 119 }, // 16.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 1244 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 120 }, // pio2_2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 121 }, // pio2_2t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 122 }, // 49.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 1243 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 123 }, // pio2_3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 124 }, // pio2_3t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .jmp, .n = 1243 },
    .{ .op = .jmp, .n = 1244 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 1256 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 64 }, // 3.0
    .{ .op = .cmd, .n = 0x0060 }, // AND
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 1316 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 53 }, // S6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 54 }, // S5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 55 }, // S4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 56 }, // S3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 57 }, // S2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 58 }, // S1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 6 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1314 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1498 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 1378 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 86 }, // C6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 87 }, // C5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 88 }, // C4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 89 }, // C3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 90 }, // C2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 91 }, // C1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 76 }, // 1.0
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
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 1376 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1498 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 1437 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 53 }, // S6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 54 }, // S5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 55 }, // S4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 56 }, // S3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 57 }, // S2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 58 }, // S1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1433 },
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1498 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 86 }, // C6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 87 }, // C5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 88 }, // C4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 89 }, // C3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 90 }, // C2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 91 }, // C1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 76 }, // 1.0
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
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 1494 },
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1498 },
};

const cos_steps = [_]Step{
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 51 }, // H3FE921FC
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 70 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 125 }, // H3E46A09E
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 13 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 1513 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 86 }, // C6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 87 }, // C5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 88 }, // C4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 89 }, // C3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 90 }, // C2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 91 }, // C1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 69 },
    .{ .op = .jmp, .n = 1513 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 59 }, // H7FF00000
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 78 },
    .{ .op = .k, .n = 60 }, // nan
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 1513 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 61 }, // H413921FB
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 875 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .k, .n = 62 }, // 23.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 64 }, // 3.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x0018 }, // MAX
    .{ .op = .k, .n = 67 }, // 4503599627370496.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 68 }, // 9.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 69 }, // 8.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 70 }, // 7.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 69 }, // 8.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 70 }, // 7.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 72 }, // 6.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 70 }, // 7.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 72 }, // 6.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 73 }, // 5.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 72 }, // 6.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 73 }, // 5.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 74 }, // 4.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 73 }, // 5.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 74 }, // 4.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 64 }, // 3.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 74 }, // 4.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 64 }, // 3.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 6 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 64 }, // 3.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 6 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0A06 }, // PICK 10
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .k, .n = 62 }, // 23.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .k, .n = 67 }, // 4503599627370496.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 8 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 77 }, // 0.125
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 69 }, // 8.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .put, .n = 6 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 471 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 6 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0A06 }, // PICK 10
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 62 }, // 23.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .put, .n = 5 },
    .{ .op = .jmp, .n = 478 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 478 },
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .put, .n = 5 },
    .{ .op = .jmp, .n = 478 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 600 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 6 },
    .{ .op = .k, .n = 79 }, // 281474976710656.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 80 }, // 3.552713678800501e-15
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .put, .n = 4 },
    .{ .op = .k, .n = 79 }, // 281474976710656.0
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 79 }, // 281474976710656.0
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 80 }, // 3.552713678800501e-15
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .put, .n = 4 },
    .{ .op = .k, .n = 79 }, // 281474976710656.0
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .k, .n = 79 }, // 281474976710656.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 80 }, // 3.552713678800501e-15
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .put, .n = 4 },
    .{ .op = .k, .n = 79 }, // 281474976710656.0
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .put, .n = 4 },
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 584 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0A06 }, // PICK 10
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 584 },
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 599 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0A06 }, // PICK 10
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .jmp, .n = 599 },
    .{ .op = .jmp, .n = 600 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 81 }, // 168.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 82 }, // 120.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .k, .n = 83 }, // 72.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 699 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 699 },
    .{ .op = .cmd, .n = 0x0A06 }, // PICK 10
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 713 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 713 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 84 }, // pio2_hi
    .{ .op = .cmd, .n = 0x001E }, // XMUL
    .{ .op = .put, .n = 6 },
    .{ .op = .put, .n = 9 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 85 }, // pio2_lo
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 84 }, // pio2_hi
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0060 }, // AND
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 803 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 53 }, // S6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 54 }, // S5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 55 }, // S4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 56 }, // S3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 57 }, // S2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 58 }, // S1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 802 },
    .{ .op = .jmp, .n = 859 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 86 }, // C6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 87 }, // C5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 88 }, // C4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 89 }, // C3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 90 }, // C2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 91 }, // C1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 859 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0060 }, // AND
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x051C }, // CMP 5
    .{ .op = .jz, .n = 870 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 874 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 874 },
    .{ .op = .jmp, .n = 1513 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 92 }, // H400F6A7B
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 1001 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 93 }, // H3FF921FB
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 897 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 94 }, // H3FF921FC
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 897 },
    .{ .op = .jmp, .n = 907 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 95 }, // H400921FB
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 908 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 96 }, // H400921FC
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 908 },
    .{ .op = .jmp, .n = 1001 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 97 }, // H4002D97D
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 957 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 937 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 98 }, // pio2_1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 99 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 99 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1271 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 98 }, // pio2_1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 99 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 100 }, // -1.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 99 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1271 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 981 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 101 }, // 2*pio2_1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 102 }, // 2*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 102 }, // 2*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1271 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 101 }, // 2*pio2_1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 102 }, // 2*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 103 }, // -2.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 102 }, // 2*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1271 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 92 }, // H400F6A7B
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 1066 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 104 }, // H4015FDBD
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 1066 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 105 }, // H4012D97C
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 1022 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 106 }, // H4012D97D
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 1022 },
    .{ .op = .jmp, .n = 1066 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 1046 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 107 }, // 3*pio2_1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 108 }, // 3*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 64 }, // 3.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 108 }, // 3*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1271 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 107 }, // 3*pio2_1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 108 }, // 3*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 109 }, // -3.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 108 }, // 3*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1271 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 104 }, // H4015FDBD
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 1131 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 110 }, // H401C463C
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 1131 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 111 }, // H401921FB
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 1087 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 112 }, // H401921FC
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 1087 },
    .{ .op = .jmp, .n = 1131 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 1111 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 113 }, // 4*pio2_1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 114 }, // 4*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 74 }, // 4.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 114 }, // 4*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1271 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 113 }, // 4*pio2_1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 114 }, // 4*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 115 }, // -4.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 114 }, // 4*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1271 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 116 }, // invpio2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0023 }, // NEAREST
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 98 }, // pio2_1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 99 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 117 }, // -pio4
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 1167 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 98 }, // pio2_1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 99 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 1189 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 118 }, // pio4
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 1189 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 98 }, // pio2_1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 99 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 1189 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 119 }, // 16.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 1259 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 120 }, // pio2_2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 121 }, // pio2_2t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 122 }, // 49.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 1258 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 123 }, // pio2_3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 124 }, // pio2_3t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .jmp, .n = 1258 },
    .{ .op = .jmp, .n = 1259 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 1271 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 64 }, // 3.0
    .{ .op = .cmd, .n = 0x0060 }, // AND
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 1337 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 86 }, // C6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 87 }, // C5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 88 }, // C4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 89 }, // C3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 90 }, // C2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 91 }, // C1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 76 }, // 1.0
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
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 1335 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1513 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 1396 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 53 }, // S6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 54 }, // S5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 55 }, // S4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 56 }, // S3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 57 }, // S2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 58 }, // S1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1392 },
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1513 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 1461 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 86 }, // C6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 87 }, // C5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 88 }, // C4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 89 }, // C3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 90 }, // C2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 91 }, // C1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 76 }, // 1.0
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
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 1457 },
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1513 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 53 }, // S6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 54 }, // S5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 55 }, // S4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 56 }, // S3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 57 }, // S2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 58 }, // S1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 6 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1511 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1513 },
};

const tan_steps = [_]Step{
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 51 }, // H3FE921FC
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 159 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 126 }, // H3E400000
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 13 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 1600 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 127 }, // H3FE59428
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .jz, .n = 43 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .jz, .n = 32 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 2 },
    .{ .op = .jmp, .n = 32 },
    .{ .op = .k, .n = 118 }, // pio4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 128 }, // pio4lo
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 2 },
    .{ .op = .jmp, .n = 43 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 129 }, // T11
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 130 }, // T9
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 131 }, // T7
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 132 }, // T5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 133 }, // T3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 134 }, // T1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 135 }, // T12
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 136 }, // T10
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 137 }, // T8
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 138 }, // T6
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 139 }, // T4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 140 }, // T2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0012 }, // MUL
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
    .{ .op = .k, .n = 141 }, // T0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .jz, .n = 154 },
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 76 }, // 1.0
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
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .jz, .n = 150 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 8 },
    .{ .op = .cmd, .n = 0x0803 }, // DROP 8
    .{ .op = .jmp, .n = 158 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .put, .n = 8 },
    .{ .op = .cmd, .n = 0x0803 }, // DROP 8
    .{ .op = .jmp, .n = 158 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .put, .n = 8 },
    .{ .op = .cmd, .n = 0x0803 }, // DROP 8
    .{ .op = .jmp, .n = 158 },
    .{ .op = .jmp, .n = 1600 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 59 }, // H7FF00000
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 167 },
    .{ .op = .k, .n = 60 }, // nan
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 1600 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 61 }, // H413921FB
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 1017 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .k, .n = 62 }, // 23.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 64 }, // 3.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x0018 }, // MAX
    .{ .op = .k, .n = 67 }, // 4503599627370496.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 68 }, // 9.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 69 }, // 8.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 70 }, // 7.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 69 }, // 8.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 70 }, // 7.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 72 }, // 6.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 70 }, // 7.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 72 }, // 6.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 73 }, // 5.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 72 }, // 6.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 73 }, // 5.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 74 }, // 4.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 73 }, // 5.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 74 }, // 4.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 64 }, // 3.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 74 }, // 4.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 64 }, // 3.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 6 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 64 }, // 3.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 6 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0A06 }, // PICK 10
    .{ .op = .kx, .n = 0 }, // ipio2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .k, .n = 62 }, // 23.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .k, .n = 67 }, // 4503599627370496.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 8 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 77 }, // 0.125
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 69 }, // 8.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .put, .n = 6 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 560 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 6 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0A06 }, // PICK 10
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 62 }, // 23.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .put, .n = 5 },
    .{ .op = .jmp, .n = 567 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 567 },
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .put, .n = 5 },
    .{ .op = .jmp, .n = 567 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 689 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 6 },
    .{ .op = .k, .n = 79 }, // 281474976710656.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 80 }, // 3.552713678800501e-15
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .put, .n = 4 },
    .{ .op = .k, .n = 79 }, // 281474976710656.0
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 79 }, // 281474976710656.0
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 80 }, // 3.552713678800501e-15
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .put, .n = 4 },
    .{ .op = .k, .n = 79 }, // 281474976710656.0
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .k, .n = 79 }, // 281474976710656.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 80 }, // 3.552713678800501e-15
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .put, .n = 4 },
    .{ .op = .k, .n = 79 }, // 281474976710656.0
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 71 }, // 5.960464477539063e-08
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .put, .n = 4 },
    .{ .op = .k, .n = 63 }, // 16777216.0
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 673 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0A06 }, // PICK 10
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 673 },
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 688 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0A06 }, // PICK 10
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .jmp, .n = 688 },
    .{ .op = .jmp, .n = 689 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 81 }, // 168.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .k, .n = 82 }, // 120.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .k, .n = 83 }, // 72.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .k, .n = 65 }, // 24.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 788 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 788 },
    .{ .op = .cmd, .n = 0x0A06 }, // PICK 10
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 802 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 802 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 84 }, // pio2_hi
    .{ .op = .cmd, .n = 0x001E }, // XMUL
    .{ .op = .put, .n = 6 },
    .{ .op = .put, .n = 9 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 85 }, // pio2_lo
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 84 }, // pio2_hi
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0060 }, // AND
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 127 }, // H3FE59428
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .jz, .n = 862 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .jz, .n = 851 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 5 },
    .{ .op = .jmp, .n = 851 },
    .{ .op = .k, .n = 118 }, // pio4
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 128 }, // pio4lo
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 5 },
    .{ .op = .jmp, .n = 862 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 129 }, // T11
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 130 }, // T9
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 131 }, // T7
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 132 }, // T5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 133 }, // T3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 134 }, // T1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 135 }, // T12
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 136 }, // T10
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 137 }, // T8
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 138 }, // T6
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 139 }, // T4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 140 }, // T2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0B06 }, // PICK 11
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0B06 }, // PICK 11
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 141 }, // T0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .jz, .n = 973 },
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 76 }, // 1.0
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
    .{ .op = .cmd, .n = 0x0A06 }, // PICK 10
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .jz, .n = 969 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 11 },
    .{ .op = .cmd, .n = 0x0803 }, // DROP 8
    .{ .op = .jmp, .n = 1014 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .put, .n = 11 },
    .{ .op = .cmd, .n = 0x0803 }, // DROP 8
    .{ .op = .jmp, .n = 1014 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 981 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .put, .n = 11 },
    .{ .op = .cmd, .n = 0x0803 }, // DROP 8
    .{ .op = .jmp, .n = 1014 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x001F }, // CHOP
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0A06 }, // PICK 10
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 100 }, // -1.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .put, .n = 10 },
    .{ .op = .cmd, .n = 0x0A06 }, // PICK 10
    .{ .op = .cmd, .n = 0x001F }, // CHOP
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0B06 }, // PICK 11
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 11 },
    .{ .op = .cmd, .n = 0x0803 }, // DROP 8
    .{ .op = .jmp, .n = 1014 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1016 },
    .{ .op = .jmp, .n = 1600 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 92 }, // H400F6A7B
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 1143 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 93 }, // H3FF921FB
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 1039 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 94 }, // H3FF921FC
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 1039 },
    .{ .op = .jmp, .n = 1049 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 95 }, // H400921FB
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 1050 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 96 }, // H400921FC
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 1050 },
    .{ .op = .jmp, .n = 1143 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 97 }, // H4002D97D
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 1099 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 1079 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 98 }, // pio2_1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 99 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 99 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1413 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 98 }, // pio2_1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 99 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 100 }, // -1.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 99 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1413 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 1123 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 101 }, // 2*pio2_1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 102 }, // 2*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 102 }, // 2*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1413 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 101 }, // 2*pio2_1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 102 }, // 2*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 103 }, // -2.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 102 }, // 2*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1413 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 92 }, // H400F6A7B
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 1208 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 104 }, // H4015FDBD
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 1208 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 105 }, // H4012D97C
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 1164 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 106 }, // H4012D97D
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 1164 },
    .{ .op = .jmp, .n = 1208 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 1188 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 107 }, // 3*pio2_1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 108 }, // 3*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 64 }, // 3.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 108 }, // 3*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1413 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 107 }, // 3*pio2_1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 108 }, // 3*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 109 }, // -3.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 108 }, // 3*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1413 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 104 }, // H4015FDBD
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 1273 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 110 }, // H401C463C
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 1273 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 111 }, // H401921FB
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 1229 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 112 }, // H401921FC
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 1229 },
    .{ .op = .jmp, .n = 1273 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 1253 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 113 }, // 4*pio2_1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 114 }, // 4*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 74 }, // 4.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 114 }, // 4*pio2_1t
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1413 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 113 }, // 4*pio2_1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 114 }, // 4*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 115 }, // -4.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 114 }, // 4*pio2_1t
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1413 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 116 }, // invpio2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0023 }, // NEAREST
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 98 }, // pio2_1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 99 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 117 }, // -pio4
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 1309 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 98 }, // pio2_1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 99 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 1331 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 118 }, // pio4
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 1331 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 98 }, // pio2_1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 99 }, // pio2_1t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 1331 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 119 }, // 16.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 1401 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 120 }, // pio2_2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 121 }, // pio2_2t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 122 }, // 49.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 1400 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 123 }, // pio2_3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 124 }, // pio2_3t
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .jmp, .n = 1400 },
    .{ .op = .jmp, .n = 1401 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 1413 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0060 }, // AND
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 127 }, // H3FE59428
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .jz, .n = 1446 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .jz, .n = 1435 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 2 },
    .{ .op = .jmp, .n = 1435 },
    .{ .op = .k, .n = 118 }, // pio4
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 128 }, // pio4lo
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 2 },
    .{ .op = .jmp, .n = 1446 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 129 }, // T11
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 130 }, // T9
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 131 }, // T7
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 132 }, // T5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 133 }, // T3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 134 }, // T1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 135 }, // T12
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 136 }, // T10
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 137 }, // T8
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 138 }, // T6
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 139 }, // T4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 140 }, // T2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0012 }, // MUL
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
    .{ .op = .k, .n = 141 }, // T0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .jz, .n = 1557 },
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0A06 }, // PICK 10
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 76 }, // 1.0
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
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .jz, .n = 1553 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 10 },
    .{ .op = .cmd, .n = 0x0703 }, // DROP 7
    .{ .op = .jmp, .n = 1598 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .put, .n = 10 },
    .{ .op = .cmd, .n = 0x0703 }, // DROP 7
    .{ .op = .jmp, .n = 1598 },
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 1565 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .put, .n = 10 },
    .{ .op = .cmd, .n = 0x0703 }, // DROP 7
    .{ .op = .jmp, .n = 1598 },
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
    .{ .op = .k, .n = 100 }, // -1.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x001F }, // CHOP
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 76 }, // 1.0
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
    .{ .op = .jmp, .n = 1598 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 1600 },
};

const asin_steps = [_]Step{
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 24 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 20 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 84 }, // pio2_hi
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 142 }, // tiny
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 227 },
    .{ .op = .k, .n = 60 }, // nan
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 227 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 101 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 52 }, // H3E500000
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 43 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 143 }, // H00100000
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 43 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 227 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 144 }, // pS5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 145 }, // pS4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 146 }, // pS3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 147 }, // pS2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 148 }, // pS1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 149 }, // pS0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 150 }, // qS4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 151 }, // qS3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 152 }, // qS2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 153 }, // qS1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 94 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 227 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0014 }, // SQRT
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 144 }, // pS5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 145 }, // pS4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 146 }, // pS3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 147 }, // pS2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 148 }, // pS1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 149 }, // pS0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 150 }, // qS4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 151 }, // qS3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 152 }, // qS2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 153 }, // qS1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 159 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 154 }, // H3FEF3333
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 178 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 85 }, // pio2_lo
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 84 }, // pio2_hi
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 6 },
    .{ .op = .jmp, .n = 215 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x001F }, // CHOP
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .put, .n = 4 },
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 85 }, // pio2_lo
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 118 }, // pio4
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 118 }, // pio4
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 6 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .jz, .n = 223 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 227 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 227 },
};

const acos_steps = [_]Step{
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 29 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 25 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 21 },
    .{ .op = .k, .n = 155 }, // pi
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 266 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 266 },
    .{ .op = .k, .n = 60 }, // nan
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 266 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 108 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 156 }, // H3C600001
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 43 },
    .{ .op = .k, .n = 84 }, // pio2_hi
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 266 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 144 }, // pS5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 145 }, // pS4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 146 }, // pS3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 147 }, // pS2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 148 }, // pS1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 149 }, // pS0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 150 }, // qS4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 151 }, // qS3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 152 }, // qS2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 153 }, // qS1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 94 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 85 }, // pio2_lo
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 84 }, // pio2_hi
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 266 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 184 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0014 }, // SQRT
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 144 }, // pS5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 145 }, // pS4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 146 }, // pS3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 147 }, // pS2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 148 }, // pS1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 149 }, // pS0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 150 }, // qS4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 151 }, // qS3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 152 }, // qS2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 153 }, // qS1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 168 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 85 }, // pio2_lo
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .k, .n = 84 }, // pio2_hi
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 266 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0014 }, // SQRT
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x001F }, // CHOP
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 144 }, // pS5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 145 }, // pS4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 146 }, // pS3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 147 }, // pS2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 148 }, // pS1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 149 }, // pS0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 150 }, // qS4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 151 }, // qS3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 152 }, // qS2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 153 }, // qS1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 252 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 266 },
};

const atan_steps = [_]Step{
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 157 }, // H44100000
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 20 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 16 },
    .{ .op = .k, .n = 158 }, // -pio2_hi+tiny
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 197 },
    .{ .op = .k, .n = 84 }, // pio2_hi
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 197 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 159 }, // H3FDC0000
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 40 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 126 }, // H3E400000
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 37 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 197 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 3 },
    .{ .op = .jmp, .n = 108 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 160 }, // H3FF30000
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 81 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 161 }, // H3FE60000
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 68 },
    .{ .op = .k, .n = 162 }, // atanhi0
    .{ .op = .put, .n = 2 },
    .{ .op = .k, .n = 163 }, // atanlo0
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .put, .n = 4 },
    .{ .op = .jmp, .n = 80 },
    .{ .op = .k, .n = 118 }, // pio4
    .{ .op = .put, .n = 2 },
    .{ .op = .k, .n = 128 }, // pio4lo
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .put, .n = 4 },
    .{ .op = .jmp, .n = 108 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 164 }, // H40038000
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 100 },
    .{ .op = .k, .n = 165 }, // atanhi2
    .{ .op = .put, .n = 2 },
    .{ .op = .k, .n = 166 }, // atanlo2
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 167 }, // 1.5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 167 }, // 1.5
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .put, .n = 4 },
    .{ .op = .jmp, .n = 108 },
    .{ .op = .k, .n = 84 }, // pio2_hi
    .{ .op = .put, .n = 2 },
    .{ .op = .k, .n = 85 }, // pio2_lo
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 100 }, // -1.0
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 168 }, // aT10
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 169 }, // aT8
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 170 }, // aT6
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 171 }, // aT4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 172 }, // aT2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 173 }, // aT0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 174 }, // aT9
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 175 }, // aT7
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 176 }, // aT5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 177 }, // aT3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 178 }, // aT1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 172 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0703 }, // DROP 7
    .{ .op = .jmp, .n = 197 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .jz, .n = 193 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 197 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 197 },
    .{ .op = .jmp, .n = 198 },
};

const atan2_steps = [_]Step{
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 34 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 10 },
    .{ .op = .jmp, .n = 16 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 30 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 26 },
    .{ .op = .k, .n = 179 }, // -pi
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 404 },
    .{ .op = .k, .n = 155 }, // pi
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 404 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 404 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 50 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 46 },
    .{ .op = .k, .n = 180 }, // -pi/2
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 404 },
    .{ .op = .k, .n = 84 }, // pio2_hi
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 404 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 59 }, // H7FF00000
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 116 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 59 }, // H7FF00000
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 88 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 76 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 72 },
    .{ .op = .k, .n = 181 }, // -3*pi/4
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 404 },
    .{ .op = .k, .n = 182 }, // 3*pi/4
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 404 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 84 },
    .{ .op = .k, .n = 183 }, // -pi/4
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 404 },
    .{ .op = .k, .n = 118 }, // pio4
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 404 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 104 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 100 },
    .{ .op = .k, .n = 179 }, // -pi
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 404 },
    .{ .op = .k, .n = 155 }, // pi
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 404 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 112 },
    .{ .op = .k, .n = 184 }, // -0.0
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 404 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 404 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .cmd, .n = 0x001F }, // CHOP
    .{ .op = .cmd, .n = 0x0028 }, // ITOF
    .{ .op = .k, .n = 185 }, // 2.8823037615171174e+17
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .cmd, .n = 0x001F }, // CHOP
    .{ .op = .cmd, .n = 0x0028 }, // ITOF
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 129 },
    .{ .op = .jmp, .n = 134 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 59 }, // H7FF00000
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 146 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 142 },
    .{ .op = .k, .n = 180 }, // -pi/2
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 404 },
    .{ .op = .k, .n = 84 }, // pio2_hi
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 404 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 165 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .cmd, .n = 0x001F }, // CHOP
    .{ .op = .cmd, .n = 0x0028 }, // ITOF
    .{ .op = .k, .n = 185 }, // 2.8823037615171174e+17
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .cmd, .n = 0x001F }, // CHOP
    .{ .op = .cmd, .n = 0x0028 }, // ITOF
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 165 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 366 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 157 }, // H44100000
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 189 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 185 },
    .{ .op = .k, .n = 180 }, // -pi/2
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 366 },
    .{ .op = .k, .n = 84 }, // pio2_hi
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 366 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 159 }, // H3FDC0000
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 209 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 126 }, // H3E400000
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 206 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 366 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 3 },
    .{ .op = .jmp, .n = 277 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 160 }, // H3FF30000
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 250 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 161 }, // H3FE60000
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 237 },
    .{ .op = .k, .n = 162 }, // atanhi0
    .{ .op = .put, .n = 2 },
    .{ .op = .k, .n = 163 }, // atanlo0
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .put, .n = 4 },
    .{ .op = .jmp, .n = 249 },
    .{ .op = .k, .n = 118 }, // pio4
    .{ .op = .put, .n = 2 },
    .{ .op = .k, .n = 128 }, // pio4lo
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .put, .n = 4 },
    .{ .op = .jmp, .n = 277 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 164 }, // H40038000
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 269 },
    .{ .op = .k, .n = 165 }, // atanhi2
    .{ .op = .put, .n = 2 },
    .{ .op = .k, .n = 166 }, // atanlo2
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 167 }, // 1.5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 167 }, // 1.5
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .put, .n = 4 },
    .{ .op = .jmp, .n = 277 },
    .{ .op = .k, .n = 84 }, // pio2_hi
    .{ .op = .put, .n = 2 },
    .{ .op = .k, .n = 85 }, // pio2_lo
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 100 }, // -1.0
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 168 }, // aT10
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 169 }, // aT8
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 170 }, // aT6
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 171 }, // aT4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 172 }, // aT2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 173 }, // aT0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 174 }, // aT9
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 175 }, // aT7
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 176 }, // aT5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 177 }, // aT3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 178 }, // aT1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 341 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 8 },
    .{ .op = .cmd, .n = 0x0803 }, // DROP 8
    .{ .op = .jmp, .n = 366 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .jz, .n = 362 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 6 },
    .{ .op = .cmd, .n = 0x0603 }, // DROP 6
    .{ .op = .jmp, .n = 366 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .put, .n = 6 },
    .{ .op = .cmd, .n = 0x0603 }, // DROP 6
    .{ .op = .jmp, .n = 366 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 391 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 382 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 186 }, // pi_lo
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 155 }, // pi
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 404 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 186 }, // pi_lo
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 155 }, // pi
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 404 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 400 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 404 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 404 },
};

const ln_steps = [_]Step{
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x031C }, // CMP 3
    .{ .op = .jz, .n = 19 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 15 },
    .{ .op = .pole, .n = 0 },
    .{ .op = .k, .n = 187 }, // -H7FF00000
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 254 },
    .{ .op = .k, .n = 60 }, // nan
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 254 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 59 }, // H7FF00000
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 27 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 254 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x003D }, // GETMANT
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 188 }, // 1.4142112731933594
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 45 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 52 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .put, .n = 5 },
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 52 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 189 }, // H3FEFFFFE
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 121 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 190 }, // H3FF00001
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 121 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 85 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 75 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 254 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 191 }, // ln2_hi
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 192 }, // ln2_lo
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 254 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 193 }, // 0.3333333333333333
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 106 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 254 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 191 }, // ln2_hi
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 192 }, // ln2_lo
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 254 },
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 194 }, // Lg6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 195 }, // Lg4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 196 }, // Lg2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 197 }, // Lg7
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 198 }, // Lg5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 199 }, // Lg3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 200 }, // Lg1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 201 }, // H3FF6147A
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 170 },
    .{ .op = .jmp, .n = 174 },
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 202 }, // H3FE6B852
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 220 },
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 198 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 254 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 192 }, // ln2_lo
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 191 }, // ln2_hi
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 254 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 235 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 254 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 192 }, // ln2_lo
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 191 }, // ln2_hi
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 254 },
};

const log2_steps = [_]Step{
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x031C }, // CMP 3
    .{ .op = .jz, .n = 15 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 12 },
    .{ .op = .pole, .n = 0 },
    .{ .op = .k, .n = 187 }, // -H7FF00000
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 150 },
    .{ .op = .k, .n = 60 }, // nan
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 150 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 59 }, // H7FF00000
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 22 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 150 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x003D }, // GETMANT
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 188 }, // 1.4142112731933594
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 40 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 3 },
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 47 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .put, .n = 3 },
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 47 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 197 }, // Lg7
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 198 }, // Lg5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 199 }, // Lg3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 200 }, // Lg1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 194 }, // Lg6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 195 }, // Lg4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 196 }, // Lg2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 106 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x001F }, // CHOP
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 203 }, // ivln2hi
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .k, .n = 204 }, // ivln2lo
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 203 }, // ivln2hi
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 150 },
};

const log10_steps = [_]Step{
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x031C }, // CMP 3
    .{ .op = .jz, .n = 15 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 12 },
    .{ .op = .pole, .n = 0 },
    .{ .op = .k, .n = 187 }, // -H7FF00000
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 157 },
    .{ .op = .k, .n = 60 }, // nan
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 157 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 59 }, // H7FF00000
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 22 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 157 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x003D }, // GETMANT
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 205 }, // 1.4142131805419922
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 40 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 3 },
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 47 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .put, .n = 3 },
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 47 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x001F }, // CHOP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 197 }, // Lg7
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 198 }, // Lg5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 199 }, // Lg3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 200 }, // Lg1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 194 }, // Lg6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 195 }, // Lg4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 196 }, // Lg2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 110 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 206 }, // ivln10hi
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 207 }, // log10_2hi
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 208 }, // log10_2lo
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .k, .n = 209 }, // ivln10lo
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 206 }, // ivln10hi
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 157 },
};

const exp_steps = [_]Step{
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 210 }, // H40862E42
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 42 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 59 }, // H7FF00000
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 25 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 21 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 187 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 187 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 211 }, // o_threshold
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 33 },
    .{ .op = .k, .n = 59 }, // H7FF00000
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 187 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 212 }, // u_threshold
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 41 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 187 },
    .{ .op = .jmp, .n = 42 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 213 }, // H3FD62E43
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 109 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 214 }, // H3FF0A2B2
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 74 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 65 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 191 }, // ln2_hi
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .k, .n = 215 }, // -ln2_lo
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 100 }, // -1.0
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 73 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 191 }, // ln2_hi
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .k, .n = 192 }, // ln2_lo
    .{ .op = .put, .n = 1 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 104 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 86 },
    .{ .op = .k, .n = 216 }, // invln2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 93 },
    .{ .op = .k, .n = 216 }, // invln2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 191 }, // ln2_hi
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 192 }, // ln2_lo
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .jmp, .n = 122 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 217 }, // H3E300000
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 120 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 187 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 218 }, // P5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 219 }, // P4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 220 }, // P3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 221 }, // P2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 222 }, // P1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 167 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 187 },
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 187 },
};

const pow2_steps = [_]Step{
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 8 },
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0014 }, // SQRT
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 189 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 223 }, // H41E00001
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 23 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 20 },
    .{ .op = .k, .n = 59 }, // H7FF00000
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 189 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 189 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x001F }, // CHOP
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 224 }, // 1024.0
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 56 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 224 }, // 1024.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 43 },
    .{ .op = .k, .n = 59 }, // H7FF00000
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 187 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 225 }, // ovt
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 55 },
    .{ .op = .k, .n = 59 }, // H7FF00000
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 187 },
    .{ .op = .jmp, .n = 79 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 226 }, // -1075.0
    .{ .op = .cmd, .n = 0x031C }, // CMP 3
    .{ .op = .jz, .n = 79 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 226 }, // -1075.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 68 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 187 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 78 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 187 },
    .{ .op = .jmp, .n = 79 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 227 }, // H3FE00001
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 105 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 95 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 100 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .jmp, .n = 105 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x001F }, // CHOP
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 228 }, // lg2_h
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 229 }, // lg2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 230 }, // lg2_l
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 218 }, // P5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 219 }, // P4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 220 }, // P3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 221 }, // P2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 222 }, // P1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 187 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 189 },
};

const pow_steps = [_]Step{
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 8 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 782 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 16 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 782 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 59 }, // H7FF00000
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 60 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 30 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 782 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 47 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 43 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 782 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 782 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 56 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 782 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 782 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 68 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 782 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 100 }, // -1.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 84 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 78 },
    .{ .op = .pole, .n = 0 },
    .{ .op = .jmp, .n = 78 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 782 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 94 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 782 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 115 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 103 },
    .{ .op = .jmp, .n = 109 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 114 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0014 }, // SQRT
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 782 },
    .{ .op = .jmp, .n = 115 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 59 }, // H7FF00000
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 121 },
    .{ .op = .jmp, .n = 131 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 126 },
    .{ .op = .jmp, .n = 131 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 216 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 136 },
    .{ .op = .jmp, .n = 142 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 194 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 100 }, // -1.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 155 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x051C }, // CMP 5
    .{ .op = .jz, .n = 155 },
    .{ .op = .k, .n = 60 }, // nan
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 782 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 193 },
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x051C }, // CMP 5
    .{ .op = .jz, .n = 193 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 187 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 179 },
    .{ .op = .pole, .n = 0 },
    .{ .op = .jmp, .n = 179 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 782 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .cmd, .n = 0x0015 }, // NEG
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 782 },
    .{ .op = .jmp, .n = 194 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 211 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 204 },
    .{ .op = .pole, .n = 0 },
    .{ .op = .jmp, .n = 204 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 782 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 782 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 229 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x051C }, // CMP 5
    .{ .op = .jz, .n = 229 },
    .{ .op = .k, .n = 60 }, // nan
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 782 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 223 }, // H41E00001
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 387 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 231 }, // H43F00001
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 268 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 256 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 252 },
    .{ .op = .k, .n = 59 }, // H7FF00000
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 782 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 782 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 264 },
    .{ .op = .k, .n = 59 }, // H7FF00000
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 782 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 782 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 232 }, // H3FEFFFFF
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 327 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 302 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 294 },
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x051C }, // CMP 5
    .{ .op = .jz, .n = 294 },
    .{ .op = .k, .n = 100 }, // -1.0
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 297 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 297 },
    .{ .op = .k, .n = 59 }, // H7FF00000
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 782 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 319 },
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x051C }, // CMP 5
    .{ .op = .jz, .n = 319 },
    .{ .op = .k, .n = 100 }, // -1.0
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 322 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 322 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 782 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 190 }, // H3FF00001
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 386 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 361 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 353 },
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x051C }, // CMP 5
    .{ .op = .jz, .n = 353 },
    .{ .op = .k, .n = 100 }, // -1.0
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 356 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 356 },
    .{ .op = .k, .n = 59 }, // H7FF00000
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 782 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 378 },
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x051C }, // CMP 5
    .{ .op = .jz, .n = 378 },
    .{ .op = .k, .n = 100 }, // -1.0
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 381 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 381 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .jmp, .n = 782 },
    .{ .op = .jmp, .n = 387 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x003D }, // GETMANT
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 233 }, // H3FFBB67A
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 409 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 0 },
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .jmp, .n = 409 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 234 }, // H3FF3988F
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x001F }, // CHOP
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x001F }, // CHOP
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x001F }, // CHOP
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0906 }, // PICK 9
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 235 }, // pL6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 236 }, // pL5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 237 }, // pL4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 238 }, // pL3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 239 }, // pL2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 240 }, // pL1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0806 }, // PICK 8
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 2 },
    .{ .op = .k, .n = 64 }, // 3.0
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x001F }, // CHOP
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 64 }, // 3.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 7 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x001F }, // CHOP
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0706 }, // PICK 7
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 6 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .k, .n = 241 }, // cp_h
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 242 }, // cp_l
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 243 }, // cp
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 244 }, // 2.0*dp_l1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 245 }, // 2.0*dp_h1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x001F }, // CHOP
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 245 }, // 2.0*dp_h1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 6 },
    .{ .op = .put, .n = 6 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 583 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x001F }, // CHOP
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x001F }, // CHOP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 224 }, // 1024.0
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 626 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 224 }, // 1024.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 613 },
    .{ .op = .k, .n = 59 }, // H7FF00000
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 758 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 225 }, // ovt
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 625 },
    .{ .op = .k, .n = 59 }, // H7FF00000
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 758 },
    .{ .op = .jmp, .n = 649 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 226 }, // -1075.0
    .{ .op = .cmd, .n = 0x031C }, // CMP 3
    .{ .op = .jz, .n = 649 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 226 }, // -1075.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 638 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 758 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 648 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 758 },
    .{ .op = .jmp, .n = 649 },
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .k, .n = 227 }, // H3FE00001
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 675 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 665 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 670 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .jmp, .n = 675 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x001F }, // CHOP
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 228 }, // lg2_h
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 229 }, // lg2
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 230 }, // lg2_l
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 218 }, // P5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 219 }, // P4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 220 }, // P3
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 221 }, // P2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 222 }, // P1
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0103 }, // DROP 1
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .k, .n = 75 }, // 2.0
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0013 }, // DIV
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0038 }, // SCALE2
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0403 }, // DROP 4
    .{ .op = .jmp, .n = 758 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 775 },
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .k, .n = 78 }, // 0.5
    .{ .op = .cmd, .n = 0x0606 }, // PICK 6
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .cmd, .n = 0x0022 }, // TRUNC
    .{ .op = .cmd, .n = 0x051C }, // CMP 5
    .{ .op = .jz, .n = 775 },
    .{ .op = .k, .n = 100 }, // -1.0
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 778 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .put, .n = 0 },
    .{ .op = .jmp, .n = 778 },
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 3 },
    .{ .op = .cmd, .n = 0x0303 }, // DROP 3
    .{ .op = .jmp, .n = 782 },
};

const hypot_steps = [_]Step{
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .cmd, .n = 0x0018 }, // MAX
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0016 }, // ABS
    .{ .op = .cmd, .n = 0x0017 }, // MIN
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 59 }, // H7FF00000
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 19 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 105 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .k, .n = 59 }, // H7FF00000
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 24 },
    .{ .op = .jmp, .n = 28 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 66 }, // 0.0
    .{ .op = .cmd, .n = 0x021C }, // CMP 2
    .{ .op = .jz, .n = 32 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 105 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .k, .n = 246 }, // -1023.0
    .{ .op = .cmd, .n = 0x0018 }, // MAX
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .cmd, .n = 0x003C }, // GETEXP
    .{ .op = .cmd, .n = 0x0004 }, // SWAP
    .{ .op = .cmd, .n = 0x0011 }, // SUB
    .{ .op = .k, .n = 247 }, // 64.0
    .{ .op = .cmd, .n = 0x041C }, // CMP 4
    .{ .op = .jz, .n = 49 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0203 }, // DROP 2
    .{ .op = .jmp, .n = 105 },
    .{ .op = .k, .n = 76 }, // 1.0
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 248 }, // H5FE00000
    .{ .op = .cmd, .n = 0x061C }, // CMP 6
    .{ .op = .jz, .n = 65 },
    .{ .op = .k, .n = 249 }, // H6BB00000
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 250 }, // H14300000
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 250 }, // H14300000
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 2 },
    .{ .op = .jmp, .n = 80 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 251 }, // H23D00000
    .{ .op = .cmd, .n = 0x011C }, // CMP 1
    .{ .op = .jz, .n = 80 },
    .{ .op = .k, .n = 250 }, // H14300000
    .{ .op = .put, .n = 0 },
    .{ .op = .cmd, .n = 0x0106 }, // PICK 1
    .{ .op = .k, .n = 249 }, // H6BB00000
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 1 },
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .k, .n = 249 }, // H6BB00000
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 2 },
    .{ .op = .jmp, .n = 80 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x001E }, // XMUL
    .{ .op = .put, .n = 1 },
    .{ .op = .put, .n = 2 },
    .{ .op = .cmd, .n = 0x0002 }, // DUP
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x001E }, // XMUL
    .{ .op = .put, .n = 1 },
    .{ .op = .put, .n = 4 },
    .{ .op = .cmd, .n = 0x0006 }, // PICK 0
    .{ .op = .cmd, .n = 0x0206 }, // PICK 2
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0506 }, // PICK 5
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0406 }, // PICK 4
    .{ .op = .cmd, .n = 0x0010 }, // ADD
    .{ .op = .cmd, .n = 0x0014 }, // SQRT
    .{ .op = .cmd, .n = 0x0306 }, // PICK 3
    .{ .op = .cmd, .n = 0x0012 }, // MUL
    .{ .op = .put, .n = 5 },
    .{ .op = .cmd, .n = 0x0503 }, // DROP 5
    .{ .op = .jmp, .n = 105 },
};

pub const programs = [_]Program{
    .{ .num = 0x40, .pops = 1, .steps = &sin_steps },
    .{ .num = 0x41, .pops = 1, .steps = &cos_steps },
    .{ .num = 0x42, .pops = 1, .steps = &tan_steps },
    .{ .num = 0x43, .pops = 1, .steps = &asin_steps },
    .{ .num = 0x44, .pops = 1, .steps = &acos_steps },
    .{ .num = 0x45, .pops = 1, .steps = &atan_steps },
    .{ .num = 0x46, .pops = 2, .steps = &atan2_steps },
    .{ .num = 0x48, .pops = 1, .steps = &ln_steps },
    .{ .num = 0x49, .pops = 1, .steps = &log2_steps },
    .{ .num = 0x4A, .pops = 1, .steps = &log10_steps },
    .{ .num = 0x4C, .pops = 1, .steps = &exp_steps },
    .{ .num = 0x4D, .pops = 1, .steps = &pow2_steps },
    .{ .num = 0x4E, .pops = 2, .steps = &pow_steps },
    .{ .num = 0x4F, .pops = 2, .steps = &hypot_steps },
};
