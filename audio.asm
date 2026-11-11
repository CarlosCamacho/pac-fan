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
VINC    equ     $FD70           ; the voice being worked on: step (2), volume, wave, number
VVOL    equ     $FD72
VWAV    equ     $FD73
VK      equ     $FD74
NZON    equ     $FD75
DV0     equ     $FD76           ; (three bytes) the dividend, then the quotient
DV1     equ     $FD77
DV2     equ     $FD78
RM      equ     $FD79           ; (2) the remainder
MIXR    equ     $FD7B
SSCD    equ     $FD7C           ; the S/SC did not answer: no more tries
SLOTCUR equ     $FD7D           ; the Multi-Pak value ($FF7F) the chip in use needs
GP      equ     $FD7E           ; (2)
GCH     equ     $FD80
TMPB    equ     $FD81
SB      equ     $FD82
GQ      equ     $FD83           ; (2)
K24     equ     909318          ; 111,861 * 65536 / 8062: period = K24 / step (the GMC and the S/SC)
TBLBASE equ     $FD5A
FOOTBUF equ     $FD60

A_INIT  ldx     #$FD00
        clra
AI1     sta     ,x+
        cmpx    #$FE00
        bne     AI1
        ldx     #WAVETBL        ; the DAC's tables to begin with
        stx     >TBLBASE
        rts

* A_PLAY
A_PLAY  cmpa    #$FE
        bne     AP1
        ldx     #$FD00          ; stop everything: the playing state only (the mode, the tables
        clra                    ; and the chip's slot above $FD30 must stay)
APS0    sta     ,x+
        cmpx    #$FD30
        bne     APS0
        rts
AP1     cmpa    #$FF
        bne     AP2
        clr     >ACNT           ; (DP is the game's here: the variables need extended addressing)
        clr     >ACNT+1
        clr     >AID
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
        lda     <AMODE
        beq     SL              ; 0: the 6-bit DAC
        cmpa    #1
        lbne    CHIPSL          ; 2-4: a sound chip
        lbra    SLO             ; 1: Orchestra-90
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
        addd    <TBLBASE
        std     ,u++
        leax    3,x
        dec     <CNT
        bne     TK6
        lda     <AMODE
        cmpa    #1
        bne     TK8
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
        pshs    a,b,x,y,u,dp
        ldb     #DPV
        tfr     b,dp
        lda     <AMODE
        cmpa    #2
        blo     ASM0
        lda     <SLOTCUR        ; the chip we are leaving: select its slot and quiet it
        sta     $FF7F
        lda     <AMODE
        lbsr    SILENCE
ASM0    lda     ,s              ; the new Multi-Pak value
        ldb     1,s             ; the new mode
        sta     $FF7F
        sta     <SLOTCUR
        stb     <AMODE
        ldx     #WAVETBL        ; the 6-bit DAC's tables, or the Orchestra-90's finer ones
        cmpb    #1
        bne     ASM1
        ldx     #WAVETBL8
ASM1    stx     <TBLBASE
        lda     $FF03           ; CB2 high (with CA2 low) sends a cartridge's audio (a chip's) to the speaker
        anda    #$F7
        cmpb    #2
        blo     ASM2
        ora     #8
ASM2    sta     $FF03
        cmpb    #2
        blo     ASMX
        lbsr    CHIPINIT
ASMX    puls    a,b,x,y,u,dp
        rts

* ---- the sound chips: one tick of the voices becomes register writes ----
* VOICE: voice VK's step, volume and wave
VOICE   lda     <VK
        asla
        ldx     #INC1
        ldd     a,x
        std     <VINC
        lda     <VK
        ldb     #3
        mul
        ldx     #V0+2
        lda     b,x
        tfr     a,b
        andb    #15
        stb     <VVOL
        lsra
        lsra
        lsra
        lsra
        sta     <VWAV
        rts

* PERIOD: D = K24 / VINC, the chip's period (24-bit by 16-bit, shift and subtract)
PERIOD  lda     #K24/65536
        sta     <DV0
        lda     #(K24/256)&255
        sta     <DV1
        lda     #K24&255
        sta     <DV2
        ldd     #0
        std     <RM
        lda     #24
        sta     <CNT
PD1     asl     <DV2
        rol     <DV1
        rol     <DV0
        rol     <RM+1
        rol     <RM
        ldd     <RM
        subd    <VINC
        blo     PD2
        std     <RM
        inc     <DV2
PD2     dec     <CNT
        bne     PD1
        ldd     <DV1
        rts

* silence the chip of mode A (its slot is selected)
SILENCE cmpa    #2
        bne     SIL3
        lda     #$9F            ; GMC: all four attenuations to 15
        lbsr    GMW
        lda     #$BF
        lbsr    GMW
        lda     #$DF
        lbsr    GMW
        lda     #$FF
        lbra    GMW
SIL3    cmpa    #3
        bne     SIL4
        lda     #$AF            ; S/SC: amplitudes 0, every tone and noise off
        lbsr    SSCB
        ldx     #SSCQ
SIL3A   lda     ,x+
        cmpa    #$FF
        beq     SIL3B
        lbsr    SSCB
        bra     SIL3A
SIL3B   lbra    SSCB
SIL4    ldb     #4              ; SID: gates off, volume 0
        clra
        ldb     #4
        lbsr    SIDW
        ldb     #11
        clra
        lbsr    SIDW
        ldb     #18
        clra
        lbsr    SIDW
        ldb     #$18
        clra
        lbra    SIDW
SSCQ    fcb     7,$3F,8,0,9,0,10,0,$FF

* CHIPINIT: B = mode
CHIPINIT
        cmpb    #3
        beq     CI3
        cmpb    #4
        beq     CI4
        lda     #$9F            ; GMC (it powers up making noise): silence it first
        lbsr    GMW
        lda     #$BF
        lbsr    GMW
        lda     #$DF
        lbsr    GMW
        lda     #$FF
        lbra    GMW
CI3     clr     <SSCD           ; S/SC: reset it, then the AY: noise period 12, nothing sounding
        lda     #1
        sta     $FF7D
        ldx     #3000
CI3A    leax    -1,x
        bne     CI3A
        clr     $FF7D
        ldx     #12000
CI3B    leax    -1,x
        bne     CI3B
        lda     #$AF
        lbsr    SSCB
        lda     #6
        lbsr    SSCB
        lda     #12
        lbsr    SSCB
        ldx     #SSCQ
CI3C    lda     ,x+
        lbsr    SSCB
        cmpa    #$FF
        bne     CI3C
        rts
CI4     ldx     #SIDINI         ; SID: pulse width 50%, no envelope, volume 15
CI4A    ldb     ,x+
        cmpb    #$FF
        beq     CI4B
        lda     ,x+
        pshs    x
        lbsr    SIDW
        puls    x
        bra     CI4A
CI4B    rts
SIDINI  fcb     2,0,3,8,4,0,5,0,6,0,9,0,10,8,11,0,12,0,13,0,16,0,17,8,18,0,19,0,20,0,$18,$0F,$FF

* a byte to the GMC (SN76489 at $FF41): it needs a moment between writes
GMW
        ifdef   TESTLOG
        ldb     #1
        lbsr    LOGW
        endc
        sta     $FF41
        nop
        nop
        nop
        nop
        rts
* a byte to the S/SC, waiting for BUSY* (not for ever: if nothing answers, it is given up)
SSCB
        ifdef   TESTLOG
        pshs    b
        ldb     #2
        lbsr    LOGW
        puls    b
        endc
        tst     <SSCD
        bne     SSBX
        pshs    x
        ldx     #2500           ; about 50 ms: a PIC that is busy that long is not there
SSB1    tst     $FF7E
        bmi     SSB2
        leax    -1,x
        bne     SSB1
        inc     <SSCD
        puls    x,pc
SSB2    sta     $FF7E
        puls    x,pc
SSBX    rts
* SID register B <- A (the CoCoXSID answers at $FF40 + register)
SIDW
        ifdef   TESTLOG
        pshs    a,b
        tfr     b,a
        ldb     #3
        lbsr    LOGW
        ldb     1,s
        lda     ,s
        pshs    a
        ldb     #4
        lbsr    LOGW
        puls    a
        puls    a,b
        endc
        ldx     #$FF40
        abx
        sta     ,x
        nop
        nop
        rts

CHIPSL
        ifdef   TESTLOG
        lda     <V0+2
        ora     <V1+2
        ora     <V2+2
        anda    #15
        sta     >LOGEN
        clra
        clrb
        lbsr    LOGW
        endc
        lda     <AMODE
        cmpa    #2
        bne     CS3
        lbsr    GMCOUT
        bra     CSW
CS3     cmpa    #3
        bne     CS4
        lbsr    SSCOUT
        bra     CSW
CS4     lbsr    SIDOUT
CSW     tst     $FF03           ; no samples: the rest of the field is the chip's
        bpl     CSW
        lda     $FF02
        rts

GMCOUT  clr     <VK
        clr     <NZON
GM1     lbsr    VOICE
        lda     <VK
        asla
        asla
        asla
        asla
        asla
        sta     <GCH
        tst     <VVOL
        beq     GMQ
        lda     <VWAV
        cmpa    #8
        beq     GMN
        lbsr    PERIOD
GM1B    cmpd    #1023           ; the SN76489's 10 bits stop at about 109 Hz: lower notes an octave up
        bls     GM2
        lsra
        rorb
        bra     GM1B
GM2     std     <GP
        lda     <GP+1
        anda    #15
        ora     #$80
        ora     <GCH
        lbsr    GMW
        lda     <GP
        asla
        asla
        asla
        asla
        ldb     <GP+1
        lsrb
        lsrb
        lsrb
        lsrb
        stb     <TMPB
        ora     <TMPB
        anda    #$3F
        lbsr    GMW
        lda     #15
        suba    <VVOL
        ora     #$90
        ora     <GCH
        lbsr    GMW
        bra     GM3
GMQ     lda     #$9F
        ora     <GCH
        lbsr    GMW
        bra     GM3
GMN     lda     #$9F            ; a noise voice: its tone is silent and the noise channel carries it
        ora     <GCH
        lbsr    GMW
        lda     #$E5
        lbsr    GMW
        lda     #15
        suba    <VVOL
        ora     #$F0
        lbsr    GMW
        inc     <NZON
GM3     inc     <VK
        lda     <VK
        cmpa    #3
        blo     GM1
        tst     <NZON
        bne     GMX
        lda     #$FF
        lbsr    GMW
GMX     rts

SSCOUT  lda     #$AF            ; direct register access: (register, value) pairs until $FF
        lbsr    SSCB
        clr     <VK
        lda     #$3F
        sta     <MIXR
SS1     lbsr    VOICE
        tst     <VVOL
        beq     SSQ
        lda     <VWAV
        cmpa    #8
        beq     SSN
        lbsr    PERIOD
        cmpd    #4095
        bls     SS2
        ldd     #4095
SS2     std     <GP
        lda     <VK
        asla
        lbsr    SSCB            ; register 2k: fine period
        lda     <GP+1
        lbsr    SSCB
        lda     <VK
        asla
        inca
        lbsr    SSCB            ; register 2k+1: coarse
        lda     <GP
        lbsr    SSCB
        ldb     <VK             ; mixer: tone k on
        ldx     #SSBITS
        lda     b,x
        coma
        anda    <MIXR
        sta     <MIXR
        bra     SS3
SSN     ldb     <VK             ; mixer: noise k on
        addb    #3
        ldx     #SSBITS
        lda     b,x
        coma
        anda    <MIXR
        sta     <MIXR
SS3     lda     <VK
        adda    #8
        lbsr    SSCB            ; amplitude
        lda     <VVOL
        lbsr    SSCB
        bra     SS4
SSQ     lda     <VK
        adda    #8
        lbsr    SSCB
        clra
        lbsr    SSCB
SS4     inc     <VK
        lda     <VK
        cmpa    #3
        lblo    SS1
        lda     #7
        lbsr    SSCB
        lda     <MIXR
        lbsr    SSCB
        lda     #$FF
        lbra    SSCB
SSBITS  fcb     1,2,4,8,16,32

SIDOUT  clr     <VK
SD1     lbsr    VOICE
        ldb     <VK
        ldx     #SIDBASE
        ldb     b,x
        stb     <SB
        ldd     <VINC           ; Fn = step * 2.0639 (8,062 Hz sampling to the SID's 1 MHz scale)
        std     <GP
        aslb
        rola
        std     <GQ
        ldd     <GP
        lsra
        rorb
        lsra
        rorb
        lsra
        rorb
        lsra
        rorb
        addd    <GQ
        std     <GQ
        lda     <GP
        tfr     a,b
        clra
        addd    <GQ
        std     <GP
        lda     <GP+1
        ldb     <SB
        lbsr    SIDW            ; frequency lo
        lda     <GP
        ldb     <SB
        incb
        lbsr    SIDW            ; frequency hi
        lda     <VVOL           ; sustain level = the volume (attack and decay 0)
        asla
        asla
        asla
        asla
        ldb     <SB
        addb    #6
        lbsr    SIDW
        ldb     <VWAV
        ldx     #SIDWAV
        lda     b,x
        tst     <VVOL
        beq     SD2
        ora     #1              ; gate
SD2     ldb     <SB
        addb    #4
        lbsr    SIDW
        inc     <VK
        lda     <VK
        cmpa    #3
        blo     SD1
        rts
SIDBASE fcb     0,7,14
SIDWAV  fcb     $40,$10,$40,$10,$20,$10,$10,$10,$80

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

        ifdef   TESTLOG
LOGP    equ     $FD90
LOGEN   equ     $FD92
* LOGW: log (B = type, A = byte) at $0700 up, for tests (the register stream of a sound chip)
LOGW    pshs    x,a,b
        tst     >LOGEN
        beq     LW9
        ldx     >LOGP
        cmpx    #$0700
        bhs     LW1
        ldx     #$0700
LW1     cmpx    #$0DF0
        blo     LW2
        ldx     #$0700          ; (a ring: the newest stays)
LW2     stb     ,x+
        sta     ,x+
        stx     >LOGP
LW9     puls    x,a,b,pc
        endc
WAVETBL includebin "assets/audio/synth/wavetbl.bin"
WAVETBL8 includebin "assets/audio/synth/wavetbl8.bin"
        include "assets/audio/synth/audio_data.inc"
