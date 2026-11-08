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
        jmp     A_ABOUT         ; $800D  the story pages (A = 1 on a CoCo 3); C = 1 if BREAK
        jmp     A_SETMODE       ; $8010  B = 0 DAC, 1 Orchestra-90

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
AMODE   equ     $FD48           ; 0 DAC, 1 Orchestra-90
ABT3    equ     $FD49
PAGE    equ     $FD4A
NPAGE   equ     $FD4B
LINEY   equ     $FD4C           ; (2 bytes) screen offset of the line being drawn
TXTP    equ     $FD4E           ; (2) the line's text
LN      equ     $FD50
COL     equ     $FD51
GROW    equ     $FD52
TMPD    equ     $FD54
TMPE    equ     $FD56
LNP     equ     $FD58
FOOTBUF equ     $FD60

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
        lbsr    TICK
        ldx     <T1
        ldy     <T2
        ldu     <T3
        tst     <AMODE
        lbne    SLO
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

* the Orchestra-90 loop: the same samples to its two DACs ($FF7A left, $FF7B right), 116 cycles a
* sample; TICK stretches every phase step by 116/111 so the pitches stay
SLO     ldd     <PH1
        addd    <INC1
        std     <PH1
        lsra
        lsra
        lsra
        lda     a,x
        sta     <SUM
        ldd     <PH2
        addd    <INC2
        std     <PH2
        lsra
        lsra
        lsra
        lda     a,y
        adda    <SUM
        sta     <SUM
        ldd     <PH3
        addd    <INC3
        std     <PH3
        lsra
        lsra
        lsra
        lda     a,u
        adda    <SUM
        adda    #$80            ; unsigned 8-bit DACs: the middle is $80
        sta     $FF7A
        sta     $FF7B
        tst     $FF03
        bpl     SLO
        lda     $FF02
        lda     #$80
        sta     $FF7A
        sta     $FF7B
        lda     #$82
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
        lbsr    COPY9
        stx     <BPTR
        ldx     <BCNT
        leax    -1,x
        stx     <BCNT
        bra     TK5
TK2     ldx     <ACNT           ; the loop
        beq     TK3
        ldx     <APTR
        lbsr    COPY9
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
        tst     <AMODE
        beq     TK8
        ldx     #INC1           ; Orchestra-90: step * 116/111 (about + 1/32 + 1/64)
        lda     #3
        sta     <CNT
TK7     ldd     ,x
        std     <TMPD
        lsra
        rorb
        lsra
        rorb
        lsra
        rorb
        lsra
        rorb
        lsra
        rorb
        std     <TMPE
        ldd     <TMPD
        lsra
        rorb
        lsra
        rorb
        lsra
        rorb
        lsra
        rorb
        lsra
        rorb
        lsra
        rorb
        addd    <TMPE
        addd    <TMPD
        std     ,x++
        dec     <CNT
        bne     TK7
TK8     rts

COPY9   ldy     #V0             ; copy nine bytes from X to the voices, X moves on
        ldb     #9
CP1     lda     ,x+
        sta     ,y+
        decb
        bne     CP1
        rts


* A_SETMODE: B = 0 DAC, 1 Orchestra-90
A_SETMODE
        stb     AMODE
        rts

* A_ABOUT: the story in SG24 (the screen at $0E00, which is the game's two buffers), a page at a time.
* Any key or the fire button turns the page; after the last page it returns (C = 0), or at BREAK (C = 1).
* A = 1 on a CoCo 3 (then $FF9C = 10 for SG24 and back to 9, SG12, at the end).
A_ABOUT pshs    a,x,y,u,dp
        ldb     #DPV
        tfr     b,dp
        sta     <ABT3
        sta     $FFC5           ; SAM V = 110 (SG24)
        sta     $FFC3
        sta     $FFC0
        lda     $FF22
        anda    #$07
        sta     $FF22
        sta     $FFC7           ; the screen at $0E00: F = 7
        sta     $FFC9
        sta     $FFCB
        sta     $FFCC
        sta     $FFCE
        sta     $FFD0
        sta     $FFD2
        tst     <ABT3
        beq     AB1
        lda     #10
        sta     $FF9C
AB1     lda     ABTPAGES        ; the number of pages
        sta     <NPAGE
        clr     <PAGE
AB2     bsr     DRAWPAGE
        bsr     WAITNONE        ; (the key that brought us here, or that turned the page)
        bcs     ABQ
        bsr     WAITANY
        bcs     ABQ
        inc     <PAGE
        lda     <PAGE
        cmpa    <NPAGE
        blo     AB2
        bsr     WAITNONE
        andcc   #$FE
        bra     ABX
ABQ     orcc    #1
ABX     pshs    cc
        sta     $FFC2           ; SAM V = 100 (SG12) again
        tst     <ABT3
        beq     AB3
        lda     #9
        sta     $FF9C
AB3     puls    cc
        puls    a,x,y,u,dp
        rts

* wait for the next field, polling BREAK (C = 1) and the keys: Z set if none is down
ABKEYS  lda     $FF02
ABK1    tst     $FF03
        bpl     ABK1
        lda     $FF02
        lda     #$FB
        sta     $FF02
        lda     $FF00
        bita    #$40
        beq     ABKB
        clr     $FF02           ; every column: any key or either fire button pulls a row low
        lda     $FF00
        coma
        anda    #$7F
        pshs    cc
        ldb     #$FF
        stb     $FF02
        puls    cc
        andcc   #$FE
        rts
ABKB    ldb     #$FF
        stb     $FF02
        orcc    #1
        rts
WAITNONE bsr    ABKEYS
        bcs     WNX
        bne     WAITNONE
        andcc   #$FE
WNX     rts
WAITANY bsr     ABKEYS
        bcs     WAX
        beq     WAITANY
        andcc   #$FE
WAX     rts

* DRAWPAGE: clear the screen, the 14 lines of this page in white, "PAGE n/N" under them in yellow
DRAWPAGE
        ldx     #$0E00
        ldd     #$8080
DP1     std     ,x++
        cmpx    #$2600
        bne     DP1
        lda     <PAGE           ; this page's text: ABTPAGES + 1 + PAGE * 224
        ldb     #224
        mul
        addd    #ABTPAGES+1
        std     <TXTP
        clr     <LN
        ldd     #$0E00+4*32     ; the first line's rows start at scanline 4
        std     <LINEY
DP2     ldx     <TXTP
        ldy     <LINEY
        lda     #$40            ; white (buff)
        sta     <GROW
        lda     #16
        sta     <COL
        bsr     DRAWLINE        ; X -> the 16 characters, Y = the screen offset
        ldd     <TXTP
        addd    #16
        std     <TXTP
        ldd     <LINEY
        addd    #12*32
        std     <LINEY
        inc     <LN
        lda     <LN
        cmpa    #14
        blo     DP2
* the footer: PAGE n/N
        ldx     #FOOTBUF
        lda     #$20
        ldb     #16
DP3     sta     ,x+
        decb
        bne     DP3
        ldx     #FOOTBUF
        ldd     #$5041          ; "PA"
        std     ,x++
        ldd     #$4745          ; "GE"
        std     ,x++
        lda     #$20
        sta     ,x+
        lda     <PAGE
        inca
        bsr     TWODIG
        lda     #$2F            ; "/"
        sta     ,x+
        lda     <NPAGE
        bsr     TWODIG
        ldx     #FOOTBUF
        ldy     #$0E00+176*32+8 ; (an 8-character line starts 4 characters in)
        lda     #$10            ; yellow
        sta     <GROW
        lda     #8
        sta     <COL
* DRAWLINE: COL characters from X, at screen offset Y, in colour GROW
DRAWLINE
        stx     <LNP
DL1     ldx     <LNP
        lda     ,x+
        stx     <LNP
        suba    #32
        bhs     DL2
        clra
DL2     cmpa    #64
        blo     DL3
        clra
DL3     ldb     #10
        mul
        addd    #ABTFONT
        tfr     d,x             ; X -> the glyph's 10 bytes
        pshs    y
        ldb     #5
DL4     lda     ,x+
        beq     DL5
        ora     <GROW
        ora     #$80
        bra     DL5A
DL5     lda     #$80
DL5A    sta     ,y
        sta     32,y
        lda     ,x+
        beq     DL7
        ora     <GROW
        ora     #$80
        bra     DL7A
DL7     lda     #$80
DL7A    sta     1,y
        sta     33,y
        leay    64,y
        decb
        bne     DL4
        puls    y
        leay    2,y
        dec     <COL
        bne     DL1
        rts
TWODIG  clrb                    ; A = 1..99 -> its digits at X
TD1     cmpa    #10
        blo     TD2
        suba    #10
        incb
        bra     TD1
TD2     tstb
        beq     TD3
        pshs    a
        tfr     b,a
        adda    #$30
        sta     ,x+
        puls    a
TD3     adda    #$30
        sta     ,x+
        rts

ABTFONT includebin "assets/audio/synth/about_font.bin"
ABTPAGES includebin "assets/audio/synth/about_pages.bin"

WAVETBL includebin "assets/audio/synth/wavetbl.bin"
        include "assets/audio/synth/audio_data.inc"
