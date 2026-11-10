; The network station (SYSTEM.md §6), without --link, so NET_STATUS reads
; 0. The addresses are registers with reset values, the counts read 0, and
; writes to the read-only words are ignored. Each result goes to the next
; word from 0x200:
;
;   0x200  NET_IP after reset           0
;   0x201  NET_MAC_HI                   0x024E      02:4E
;   0x202  NET_MAC_LO                   0x49434500  49:43:45:00
;   0x203  NET_RX_GOOD                  0
;   0x204  NET_RX_BAD                   0
;   0x205  NET_TX                       0
;   0x206  NET_STATUS                   0           no --link
;   0x207  0xFFFFFFBF                   0
;
; Then 0xFFFFFFFF goes to each of the 16 words:
;
;   0x208  NET_IP                       0xFFFFFFFF
;   0x209  NET_MAC_HI                   0xFFFF      bits 31..16 dropped
;   0x20A  NET_MAC_LO                   0xFFFFFFFF
;   0x20B  NET_RX_GOOD                  0           the writes are ignored
;   0x20C  NET_RX_BAD                   0
;   0x20D  NET_TX                       0
;   0x20E  NET_STATUS                   0
;   0x20F  0xFFFFFFB7                   0
;   0x210  0xFFFFFFBF                   0
;
; Last, NET_IP is set to 192.168.1.65, NET_MAC_HI to 0xABCD024E, and
; NET_MAC_LO to 0x49434501. The dump of the station at the end shows
; 0xC0A80141, 0x024E, 0x49434501, and 13 zeros.
NET_IP          .EQU    0xFFFFFFB0
NET_MAC_HI      .EQU    0xFFFFFFB1
NET_MAC_LO      .EQU    0xFFFFFFB2
NET_RX_GOOD     .EQU    0xFFFFFFB3
NET_RX_BAD      .EQU    0xFFFFFFB4
NET_TX          .EQU    0xFFFFFFB5
NET_STATUS      .EQU    0xFFFFFFB6
                MOVE    R1, 0x200
                MOVE    @R1++, @NET_IP
                MOVE    @R1++, @NET_MAC_HI
                MOVE    @R1++, @NET_MAC_LO
                MOVE    @R1++, @NET_RX_GOOD
                MOVE    @R1++, @NET_RX_BAD
                MOVE    @R1++, @NET_TX
                MOVE    @R1++, @NET_STATUS
                MOVE    @R1++, @0xFFFFFFBF
                MOVE    R2, NET_IP
                MOVE    R3, 16
:               MOVE    @R2++, 0xFFFFFFFF
                SUB[M]  R3, R3, 1
        ?!Z     MOVE    R15, :-
                MOVE    @R1++, @NET_IP
                MOVE    @R1++, @NET_MAC_HI
                MOVE    @R1++, @NET_MAC_LO
                MOVE    @R1++, @NET_RX_GOOD
                MOVE    @R1++, @NET_RX_BAD
                MOVE    @R1++, @NET_TX
                MOVE    @R1++, @NET_STATUS
                MOVE    @R1++, @0xFFFFFFB7
                MOVE    @R1++, @0xFFFFFFBF
                MOVE    @NET_IP, 0xC0A80141
                MOVE    @NET_MAC_HI, 0xABCD024E
                MOVE    @NET_MAC_LO, 0x49434501
                HALT
