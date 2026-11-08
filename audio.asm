* PAK FAN audio engine: a 3-voice wave-table synth for the CoCo's 6-bit DAC.
*
* Lives in the upper 32K ($8000 up), which the game reaches by switching the SAM to all-RAM
* mode ($FFDF); QUIT switches it back ($FFDE). The data (wave tables, the sound streams,
* made by tools/mksynth.py) follow the code. The game calls these through the jump table:
*
*   $8004 A_INIT    clear the engine
*   $8007 A_SLICE   play until the next field sync (the game's idle time before a frame) and
*                   clear the sync flag, as the game's own wait does. Steps one tick a call.
*   $800A A_PLAY    A = sound id (0-4 play to the end, 5-9 start an effect, 10-16 start a loop
*                   under everything), $FF = stop the loop, $FE = stop everything.
*                   Returns C = 1 if BREAK was pressed while a sound ran to its end.
*
* A tick (a video field) is 3 voices of 3 bytes: phase step (16 bits), wave<<4 | volume.
* Each sample the loop adds each voice's step to its phase and looks the top 5 bits up in
* the voice's table (signed bytes, already scaled by the volume), 111 cycles = 8062 Hz.
* Tables: 144 x 32 bytes, (wave << 4 | volume) * 32 from WAVETBL. Interrupts are off.

        org     $8000
        fcb     'P','F','A',1           ; signature: the game looks for it
        jmp     A_INIT
        jmp     A_SLICE
        jmp     A_PLAY

* engine variables: a direct page of their own ($FD00)
DPV     equ     $FD
        setdp   DPV
PH1     equ     $FD00
PH2     equ     $FD02
PH3     equ     $FD04
INC1    equ     $FD06
INC2    equ     $FD08
INC3    equ     $FD0A
SUM     equ     $FD0C
BPTR    equ     $FD10           ; a sound that runs to its end: next tick, ticks left
BCNT    equ     $FD12
SPTR    equ     $FD14           ; an effect
SCNT    equ     $FD16
APTR    equ     $FD18           ; the loop under everything
ACNT    equ     $FD1A
ASTRT   equ     $FD1C
ALEN    equ     $FD1E
AID     equ     $FD20
V0      equ     $FD30           ; this tick's three voices: step (2), wave << 4 | volume
V1      equ     $FD33
V2      equ     $FD36
T1      equ     $FD40           ; their tables
T2      equ     $FD42
T3      equ     $FD44
CNT     equ     $FD47

A_INIT  ldx     #$FD00
        clra
AI1     sta     ,x+
        cmpx    #$FE00
        bne     AI1
        rts

* A_PLAY
A_PLAY  cmpa    #$FE
        bne     AP1
        bsr     A_INIT
        rts
AP1     cmpa    #$FF
        bne     AP2
        clr     ACNT
        clr     ACNT+1
        clr     AID
        rts
AP2     pshs    a,x,y,u,dp
        ldb     #DPV
        tfr     b,dp
        ldx     #SNDDIR
        lsla
        lsla
        leax    a,x
        ldy     ,x              ; Y -> the stream, U = its ticks
        ldu     2,x
        lda     ,s              ; the id again
        cmpa    #5
        blo     APB
        cmpa    #10
        blo     APS
* a loop: nothing to do if it is already the one playing
        cmpa    <AID
        bne     APL1
        ldx     <ACNT
        bne     APX
APL1    sta     <AID
        sty     <APTR
        sty     <ASTRT
        stu     <ACNT
        stu     <ALEN
        bra     APX
APS     sty     <SPTR           ; an effect
        stu     <SCNT
        bra     APX
APB     sty     <BPTR           ; to the end, polling BREAK once a tick
        stu     <BCNT
APB1    bsr     SLICE
        lda     #$FB            ; BREAK: column 2, row 6
        sta     $FF02
        lda     $FF00
        ldb     #$FF
        stb     $FF02
        bita    #$40
        beq     APBRK
        ldd     <BCNT
        bne     APB1
        puls    a,x,y,u,dp
        andcc   #$FE
        rts
APBRK   clra
        sta     <BCNT
        sta     <BCNT+1
        puls    a,x,y,u,dp
        orcc    #1
        rts
APX     puls    a,x,y,u,dp
        andcc   #$FE
        rts

* A_SLICE: one tick, then samples until the next field sync
A_SLICE pshs    a,x,y,u,dp
        ldb     #DPV
        tfr     b,dp
        bsr     SLICE
        puls    a,x,y,u,dp
        rts

SLICE   lda     $FF02           ; clear the field sync flag: this tick lasts until the next
        bsr     TICK
        ldx     <T1
        ldy     <T2
        ldu     <T3
SL      ldd     <PH1            ; 5
        addd    <INC1           ; 6
        std     <PH1            ; 5
        lsra                    ; 2 x3
        lsra
        lsra
        lda     a,x             ; 5
        sta     <SUM            ; 4
        ldd     <PH2
        addd    <INC2
        std     <PH2
        lsra
        lsra
        lsra
        lda     a,y
        adda    <SUM            ; 4
        sta     <SUM
        ldd     <PH3
        addd    <INC3
        std     <PH3
        lsra
        lsra
        lsra
        lda     a,u
        adda    <SUM
        adda    #$82            ; DAC centre, and bit 1 high (the RS-232 line idles high)
        sta     $FF20           ; 5
        tst     $FF03           ; 7: the field sync flag
        bpl     SL              ; 3   = 111 cycles a sample (mksynth.py LOOP_CYCLES)
        lda     $FF02           ; clear the flag
        lda     #$82            ; the DAC at rest between slices
        sta     $FF20
        rts

* TICK: work out this tick's three voices (a sound that runs to its end has them all; otherwise
* the loop, with the effect's voices over it) and the three table pointers.
TICK    ldx     #V0             ; all voices silent
        ldb     #9
        clra
TK0     sta     ,x+
        decb
        bne     TK0
        ldx     <BCNT
        beq     TK2
        ldx     <BPTR           ; a sound to its end: it has the voices
        bsr     COPY9
        stx     <BPTR
        ldx     <BCNT
        leax    -1,x
        stx     <BCNT
        bra     TK5
TK2     ldx     <ACNT           ; the loop
        beq     TK3
        ldx     <APTR
        bsr     COPY9
        stx     <APTR
        ldx     <ACNT
        leax    -1,x
        stx     <ACNT
        bne     TK3
        ldx     <ALEN          ; the end of it: round again
        stx     <ACNT
        ldx     <ASTRT
        stx     <APTR
TK3     ldx     <SCNT           ; an effect: each voice that has volume replaces the loop's
        beq     TK5
        ldy     <SPTR
        ldu     #V0
        ldb     #3
TK4     lda     2,y
        anda    #$0F
        beq     TK4B
        ldx     ,y
        stx     ,u
        lda     2,y
        sta     2,u
TK4B    leay    3,y
        leau    3,u
        decb
        bne     TK4
        sty     <SPTR
        ldx     <SCNT
        leax    -1,x
        stx     <SCNT
TK5     ldx     #V0             ; the phase steps and the tables
        ldy     #INC1
        ldu     #T1
        lda     #3
        sta     <CNT
TK6     ldd     ,x
        std     ,y++
        lda     2,x
        clrb                    ; A = wave << 4 | volume: pointer = WAVETBL + A * 32
        lsra
        rorb
        lsra
        rorb
        lsra
        rorb
        addd    #WAVETBL
        std     ,u++
        leax    3,x
        dec     <CNT
        bne     TK6
        rts

COPY9   ldy     #V0             ; copy nine bytes from X to the voices, X moves on
        ldb     #9
CP1     lda     ,x+
        sta     ,y+
        decb
        bne     CP1
        rts

WAVETBL includebin "assets/audio/synth/wavetbl.bin"
        include "assets/audio/synth/audio_data.inc"
