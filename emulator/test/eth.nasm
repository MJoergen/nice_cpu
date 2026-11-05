; The port for Ethernet frames (SYSTEM.md §7), with --eth-in test/eth.in
; and --eth-out. Each result goes to the next word from 0x200:
;
;   0x200  ETH_CSR after reset          0
;   0x201  ETH_RX_LEN                   0
;   0x202  ETH_DROPPED                  0
;
; A send while not enabled sends nothing. NET_IP is set to 192.168.1.65,
; then the port is enabled. The lines of eth.in arrive: A enters the
; queue, the station answers the ARP request, the frame to another MAC
; address is dropped, B, C, and D enter, and E is dropped and counted.
;
;   0x203  ETH_CSR                      3           enabled, a frame waits
;   0x204  ETH_RX_LEN                   60          A
;   0x205  ETH_DROPPED                  1           E
;   0x206  ETH_BUF0-7, chunk 0          0x0000024E  the destination
;   0x207                               0x49434500
;   0x208                               0x02000000  the source
;   0x209                               0x000188B5  and the EtherType
;   0x20A                               0x00010203  the payload
;   0x20B                               0x04050607
;   0x20C                               0x08090A0B
;   0x20D                               0x0C0D0E0F
;   0x20E  ETH_BUF0, chunk 1            0x10111213
;   0x20F  ETH_BUF0, chunk 48           0
;   0x210  ETH_CHUNK after 0x1FF        0x13F       bits 5..0 and 8
;
; A, B, C, and D are released in turn:
;
;   0x211  ETH_RX_LEN                   14          B
;   0x212  ETH_BUF3                     0x000288B5  its source's last bytes
;   0x213  ETH_RX_LEN                   14          C
;   0x214  ETH_BUF3                     0x000388B5
;   0x215  ETH_RX_LEN                   14          D
;   0x216  ETH_BUF3                     0x000488B5
;   0x217  ETH_RX_LEN                   0           the queue is empty
;   0x218  ETH_CSR                      1
;
; A frame of 14 bytes to everyone from the station goes into the send
; buffer. Lengths 13 and 1515 send nothing; 14 sends it, and F arrives.
;
;   0x219  ETH_CSR                      3
;   0x21A  ETH_RX_LEN                   20          F
;   0x21B  ETH_BUF3                     0x000688B5
;   0x21C  ETH_BUF4                     0xA1A2A3A4
;   0x21D  ETH_BUF3, the send buffer    0x450088B5
;
; Last, a write of 0 to ETH_CSR:
;
;   0x21E  ETH_CSR                      0
;   0x21F  ETH_RX_LEN                   0
;   0x220  ETH_DROPPED                  0
;
; The dump of the port at the end shows ETH_CHUNK 0x100, and the send
; buffer's first 4 words through ETH_BUF0-3. eth.frames.expected has the
; ARP reply and the frame sent, and nothing for the sends that failed.
NET_IP          .EQU    0xFFFFFFB0
ETH_CSR         .EQU    0xFFFFFFC0
ETH_RX_LEN      .EQU    0xFFFFFFC1
ETH_TX_LEN      .EQU    0xFFFFFFC2
ETH_CHUNK       .EQU    0xFFFFFFC3
ETH_DROPPED     .EQU    0xFFFFFFC4
ETH_BUF0        .EQU    0xFFFFFFC8
ETH_BUF1        .EQU    0xFFFFFFC9
ETH_BUF2        .EQU    0xFFFFFFCA
ETH_BUF3        .EQU    0xFFFFFFCB
ETH_BUF4        .EQU    0xFFFFFFCC
                MOVE    R1, 0x200
                MOVE    @R1++, @ETH_CSR
                MOVE    @R1++, @ETH_RX_LEN
                MOVE    @R1++, @ETH_DROPPED
                MOVE    @ETH_TX_LEN, 14
                MOVE    @NET_IP, 0xC0A80141
                MOVE    @ETH_CSR, 1
                MOVE    @R1++, @ETH_CSR
                MOVE    @R1++, @ETH_RX_LEN
                MOVE    @R1++, @ETH_DROPPED
                MOVE    R2, ETH_BUF0
                MOVE    R3, 8
copy            MOVE    @R1++, @R2++
                SUB[M]  R3, R3, 1
        ?!Z     MOVE    R15, copy
                MOVE    @ETH_CHUNK, 1
                MOVE    @R1++, @ETH_BUF0
                MOVE    @ETH_CHUNK, 48
                MOVE    @R1++, @ETH_BUF0
                MOVE    @ETH_CHUNK, 0x1FF
                MOVE    @R1++, @ETH_CHUNK
                MOVE    @ETH_CHUNK, 0
                MOVE    @ETH_RX_LEN, 0
                MOVE    @R1++, @ETH_RX_LEN
                MOVE    @R1++, @ETH_BUF3
                MOVE    @ETH_RX_LEN, 0
                MOVE    @R1++, @ETH_RX_LEN
                MOVE    @R1++, @ETH_BUF3
                MOVE    @ETH_RX_LEN, 0
                MOVE    @R1++, @ETH_RX_LEN
                MOVE    @R1++, @ETH_BUF3
                MOVE    @ETH_RX_LEN, 0
                MOVE    @R1++, @ETH_RX_LEN
                MOVE    @R1++, @ETH_CSR
                MOVE    @ETH_CHUNK, 0x100
                MOVE    @ETH_BUF0, 0x0000FFFF
                MOVE    @ETH_BUF1, 0xFFFFFFFF
                MOVE    @ETH_BUF2, 0x024E4943
                MOVE    @ETH_BUF3, 0x450088B5
                MOVE    @ETH_TX_LEN, 13
                MOVE    @ETH_TX_LEN, 1515
                MOVE    @ETH_TX_LEN, 14
                MOVE    @ETH_CHUNK, 0
                MOVE    @R1++, @ETH_CSR
                MOVE    @R1++, @ETH_RX_LEN
                MOVE    @R1++, @ETH_BUF3
                MOVE    @R1++, @ETH_BUF4
                MOVE    @ETH_CHUNK, 0x100
                MOVE    @R1++, @ETH_BUF3
                MOVE    @ETH_CSR, 0
                MOVE    @R1++, @ETH_CSR
                MOVE    @R1++, @ETH_RX_LEN
                MOVE    @R1++, @ETH_DROPPED
                HALT
