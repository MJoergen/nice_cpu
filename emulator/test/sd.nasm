; The SD card controller (DEVICES.md §5). Slot 0 holds test/sd.img.out, an
; image that the Makefile makes for each run, of 2 sectors in which byte o
; is o mod 251. Slot 1 is empty. A command ends in the write that
; starts it, so busy never reads 1. Each result goes to the next word from
; 0x200:
;
;   0x200  SD_SLOTS                     2
;   0x201  SD_CSR after reset           0x14   present, changed
;   0x202  SD_LAST before Init          0
;   0x203  Read before Init: SD_ERROR   2      not ready
;   0x204  SD_CSR                       0x16   and the error bit
;   0x205  Init: SD_CSR                 0x20C  present, ready, type 2
;   0x206  SD_LAST                      1      2 sectors
;   0x207  SD_ERROR                     0
;   0x208  command 7: SD_ERROR          0      ignored
;   0x209  Read sector 1: SD_ERROR      0
;   0x20A  chunk 0, SD_BUF0             0x0D0C0B0A  bytes 512..515: 10..13
;   0x20B  chunk 0, SD_BUF7             0x29282726  bytes 540..543: 38..41
;   0x20C  chunk 15, SD_BUF7            0x13121110  bytes 1020..1023: 16..19
;   0x20D  SD_CHUNK after 0x12          2      bits 3..0
;   0x20E  chunk 2, SD_BUF0             0x4D4C4B4A  bytes 576..579: 74..77
;   0x20F  Read sector 2: SD_ERROR      7      out of range
;   0x210  SD_CSR                       0x20E  and the error bit
;   0x211  Write sector 0: SD_ERROR     0      the buffer of sector 1, with
;                                              word 29 = 0xCAFEF00D
;   0x212  Read sector 1, chunk 3, SD_BUF5  0x81807F7E  bytes 628..631: 126..129
;   0x213  Read sector 0, chunk 3, SD_BUF5  0xCAFEF00D  as written
;   0x214  chunk 0, SD_BUF0             0x0D0C0B0A  sector 1's, as written
;   0x215  SD_ERROR                     0
;   0x216  SD_SELECT after 0x11         1      bits 3..0
;   0x217  SD_CSR                       0      slot 1 is empty
;   0x218  Init: SD_ERROR               1      no card
;   0x219  SD_CSR                       2      the error bit only
;   0x21A  slot 0 again: SD_CSR         6      present and the error bit;
;                                              not ready, not changed
;   0x21B  SD_LAST                      0      not ready
;   0x21C  Read: SD_ERROR               2      not ready after the change
;   0x21D  slot 5, Init: SD_ERROR       1      above SD_SLOTS: no card
;   0x21E  0xFFFFFFA7                   0
;   0x21F  SD_ERROR after a write of 9  1      the write is ignored
;
; The dump of the controller at the end shows SD_CSR 2, SD_LBA 0, SD_CHUNK
; 0, SD_ERROR 1, SD_SELECT 5, SD_LAST 0, SD_SLOTS 2, 0, and SD_BUF0-7 of
; chunk 0 of sector 0: 0x0D0C0B0A and on, as the words of 0x20A and 0x20B
; show, bytes 512..543 of the image.
SD_CSR          .EQU    0xFFFFFFA0
SD_LBA          .EQU    0xFFFFFFA1
SD_CHUNK        .EQU    0xFFFFFFA2
SD_ERROR        .EQU    0xFFFFFFA3
SD_SELECT       .EQU    0xFFFFFFA4
SD_LAST         .EQU    0xFFFFFFA5
SD_SLOTS        .EQU    0xFFFFFFA6
SD_BUF0         .EQU    0xFFFFFFA8
SD_BUF5         .EQU    0xFFFFFFAD
SD_BUF7         .EQU    0xFFFFFFAF
                MOVE    R1, 0x200
                MOVE    @R1++, @SD_SLOTS
                MOVE    @R1++, @SD_CSR
                MOVE    @R1++, @SD_LAST
                MOVE    @SD_CSR, 1
                MOVE    @R1++, @SD_ERROR
                MOVE    @R1++, @SD_CSR
                MOVE    @SD_CSR, 0
                MOVE    @R1++, @SD_CSR
                MOVE    @R1++, @SD_LAST
                MOVE    @R1++, @SD_ERROR
                MOVE    @SD_CSR, 7
                MOVE    @R1++, @SD_ERROR
                MOVE    @SD_LBA, 1
                MOVE    @SD_CSR, 1
                MOVE    @R1++, @SD_ERROR
                MOVE    @R1++, @SD_BUF0
                MOVE    @R1++, @SD_BUF7
                MOVE    @SD_CHUNK, 15
                MOVE    @R1++, @SD_BUF7
                MOVE    @SD_CHUNK, 0x12
                MOVE    @R1++, @SD_CHUNK
                MOVE    @R1++, @SD_BUF0
                MOVE    @SD_LBA, 2
                MOVE    @SD_CSR, 1
                MOVE    @R1++, @SD_ERROR
                MOVE    @R1++, @SD_CSR
                MOVE    @SD_CHUNK, 3
                MOVE    @SD_BUF5, 0xCAFEF00D
                MOVE    @SD_LBA, 0
                MOVE    @SD_CSR, 2
                MOVE    @R1++, @SD_ERROR
                MOVE    @SD_LBA, 1
                MOVE    @SD_CSR, 1
                MOVE    @R1++, @SD_BUF5
                MOVE    @SD_LBA, 0
                MOVE    @SD_CSR, 1
                MOVE    @R1++, @SD_BUF5
                MOVE    @SD_CHUNK, 0
                MOVE    @R1++, @SD_BUF0
                MOVE    @R1++, @SD_ERROR
                MOVE    @SD_SELECT, 0x11
                MOVE    @R1++, @SD_SELECT
                MOVE    @R1++, @SD_CSR
                MOVE    @SD_CSR, 0
                MOVE    @R1++, @SD_ERROR
                MOVE    @R1++, @SD_CSR
                MOVE    @SD_SELECT, 0
                MOVE    @R1++, @SD_CSR
                MOVE    @R1++, @SD_LAST
                MOVE    @SD_CSR, 1
                MOVE    @R1++, @SD_ERROR
                MOVE    @SD_SELECT, 5
                MOVE    @SD_CSR, 0
                MOVE    @R1++, @SD_ERROR
                MOVE    @R1++, @0xFFFFFFA7
                MOVE    @SD_ERROR, 9
                MOVE    @R1++, @SD_ERROR
                HALT
