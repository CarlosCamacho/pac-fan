* PAK FAN -- a maze-chase game in CoCo 1/2 Semigraphics 12 (64x96 elements, 8 colours)
*
* Technique (from the GHOSTS demo):
*   - everything shape-related is a pre-built table: the background screen, the maze map,
*     the sprites pre-shifted for both element positions inside a byte (AND/OR pairs that
*     respect SG12's one-colour-per-byte rule), and the font;
*   - full-screen redraws (level start) are stack blasts, PULU/PSHS D,X,Y;
*   - per frame only each sprite's 3x6-byte square is restored from the background copy
*     and redrawn: a 3 KB SG12 screen is too big to blast every frame at 0.89 MHz.
*   - double-buffered, flipped at field sync.
*
* Controls: arrow keys. SPACE starts. BREAK returns to BASIC.
* Needs a 32K CoCo 1, 2 or 3. A CoCo 3 gets SG12 from its GIME through $FF9C = 9 (found
* with SGTEST; tried in XRoar and xroar-dev, not on hardware). Load: RUN"PAKFAN" (logo, progress bar, audio engine); LOADM"PAKFAN":EXEC plays the game without sound
*
* Memory: $0E00 BUF0, $1A00 BUF1, $2600 BG (background copy), code from $3200.

BUF0    equ     $0E00           ; SAM F = 7
BUF1    equ     $1A00           ; SAM F = 13
BG      equ     $2600

* entity record
E_X     equ     0               ; x in elements (0..60)
E_Y     equ     1               ; y in element rows (0..90)
E_DIR   equ     2               ; 0 right 1 left 2 up 3 down
E_WANT  equ     3               ; requested direction (player)
E_ACC   equ     4               ; speed accumulator
E_SPD   equ     5               ; units per frame (an element costs 48, a row 32)
E_MODE  equ     6               ; ghosts: 0 chase 1 frightened 2 eyes
E_REL   equ     7               ; dots to eat before a ghost leaves the house (0 = out)
E_ID    equ     8               ; ghost number 0..3
E_HOUSE equ     9               ; ghosts: 1 = in the house or on the way out through the door
ESIZE   equ     10
NENT    equ     5               ; player + 4 ghosts

HCOST   equ     48
VCOST   equ     32

        org     $3200

START   orcc    #$50            ; interrupts off for the whole game
        clra
        tfr     a,dp
        sts     SAVES0
* CoCo 3? (its reset vector is $8C1B; a CoCo 1/2's is $A027) Then $FF9C = 9 makes the
* GIME show SG12; QUIT puts back 15. On a CoCo 1/2 nothing is written there.
        clr     COCO3
        clr     FASTF
        ldd     $FFFE
        cmpd    #$8C1B
        bne     ST3
        inc     COCO3
        lda     #9
        sta     $FF9C
* ...and the SG colours (palette registers 0-7) set to look like a CoCo 2's. BASIC's own
* values are kept for QUIT. Register 1 (yellow) says which set BASIC has loaded: $36 after
* PALETTE RGB, $24 for composite (the start-up set).
        ldx     #$FFB0
        ldu     #PALSAV
PSV1    lda     ,x+
        anda    #$3F            ; only six bits read back
        sta     ,u+
        cmpx    #$FFB8
        bne     PSV1
        ldu     #PALCMP
        lda     PALSAV+1
        cmpa    #$36
        bne     PSV2
        ldu     #PALRGB
PSV2    lbsr    SETPAL
ST3
* sound: DAC selected (SEL1 = SEL2 = 0), sound enabled ($FF23 bit 3)
        lda     $FF01
        anda    #$F7
        sta     $FF01
        lda     $FF03
        anda    #$F7
        sta     $FF03
        lda     $FF23
        ora     #$08
        sta     $FF23
* the audio engine lives in the upper 32K: the SAM to all-RAM mode ($FFDF), then look for its
* signature. Not there (a 32K machine, or the game was LOADMed on its own): ROM mode again, no sound.
        clr     HAVEAUD
        clr     ENGINE
        clr     MUXB
        lda     $FF7F           ; the Multi-Pak's slots as we found them (QUIT puts them back)
        sta     SAVE7F
        clr     MPIOK           ; is there a Multi-Pak? (the read-back probe: an empty bus cannot hold both patterns)
        lda     #$30
        sta     $FF7F
        lda     $FF7F
        anda    #$33
        cmpa    #$30
        bne     NOMPI
        lda     #$03
        sta     $FF7F
        lda     $FF7F
        anda    #$33
        cmpa    #$03
        bne     NOMPI
        inc     MPIOK
NOMPI   lda     SAVE7F
        sta     $FF7F
        clr     MSEL
        clr     OPTCTL
        clr     OPTSND
        clr     SNDI
        sta     $FFDF
        ldx     #$8000
        ldd     ,x
        cmpd    #$5046          ; 'P' 'F'
        bne     NOAUD
        ldd     2,x
        cmpd    #$4101          ; 'A' 1
        bne     NOAUD
        inc     HAVEAUD
        inc     ENGINE
        clr     CURAMB
        jsr     $8004           ; the engine's own start
        bra     AUDX
NOAUD   sta     $FFDE
AUDX
* SG12: SAM V = 100, VDG semigraphics (mode bits 0)
        sta     $FFC5           ; V2 set
        sta     $FFC2           ; V1 clear
        sta     $FFC0           ; V0 clear
        lda     $FF22
        anda    #$07
        sta     $FF22
        lda     #$5A
        sta     RND
        clr     WAKAT
        clr     LEVEL
        clr     STARTLV
        ifdef   OVR
        clr     OVRN            ; the test counters start at zero (RAM is not)
        clr     OVRN+1
        clr     TOTF
        clr     TOTF+1
        clr     OVRG
        clr     ECHO
        clr     EHUD
        clr     EGUL
        clr     ESCA
        clr     EMOD
        ldx     #OVRT
        ldd     #0
OVRZ    std     ,x++
        cmpx    #OVRX+256
        blo     OVRZ
        endc
        tst     COCO3
        beq     SPD9
* A CoCo 3 left at its high speed (POKE 65497,0)? The tune and the sounds are counted in
* cycles for 0.89 MHz and would play an octave up. Count passes of a 23-cycle loop between
* two field syncs: about 650 at 0.89 MHz and 1300 at 1.79 (PAL 780 and 1560), so 1000 or
* more is fast. Then run slow ($FFD8) and let QUIT put fast back. No sync at all: the loop
* gives up at 4000 and leaves the speed alone. Only a CoCo 3 does this: on a CoCo 1/2
* $FFD9 is a mode that can crash the RAM refresh.
        lbsr    WAITV0          ; start just after a sync
        ldx     #0
SPD1    leax    1,x             ; 5
        tst     $FF03           ; 7
        bmi     SPD2            ; 3
        cmpx    #4000           ; 5
        blo     SPD1            ; 3 = 23 cycles a pass
        bra     SPD9            ; no sync came: leave it
SPD2    cmpx    #1000
        blo     SPD9
        sta     $FFD8           ; normal speed
        inc     FASTF
SPD9

NEWGAME lda     STARTLV         ; the title shows the level the last game started on
        sta     LEVEL
        lbsr    SPLASH          ; the title: credits with the chase running through them
        ldx     #TINIT
        ldu     #ENTS
        ldb     #NENT*ESIZE
TI1     lda     ,x+
        sta     ,u+
        decb
        bne     TI1
        clr     FRAMES
        ldd     #300
        std     TPH
WSPACE  lbsr    WAITVS
        lbsr    FLIP
        inc     FRAMES
        lbsr    MENUIN          ; the menu: keys, joystick
        lbsr    TITLEANIM
        lbsr    RENDER
        tst     MGO
        beq     WSPACE
        clr     MGO
        lda     #2              ; the credit sound
        lbsr    SNDB
        lda     LEVEL
        sta     STARTLV
        clr     SCORE
        clr     SCORE+1
        clr     SCORE+2
        lda     #3
        sta     LIVES
        clr     LAP             ; first time round the levels
        lbsr    NEWLEVEL

* ---------------------------------------------------------------- one life
        lbsr    RESETPOS        ; first life of a game: READY! with the intro tune
        ldx     #TREADY
        lda     #YELLOWC
        lbsr    MSG
        lbsr    DRAWALL
STARTMUS clra                   ; the start music (label: test hook)
        lbsr    SNDB
        lbsr    MSGOFF
        bra     FRAME

NEWLIFE lbsr    RESETPOS
        ldx     #TREADY
        lda     #YELLOWC
        lbsr    MSG
        lbsr    DRAWALL
        ldb     #120            ; two seconds of READY!
RDY     pshs    b
        lbsr    WAITVS
        puls    b
        decb
        bne     RDY
        lbsr    MSGOFF

* ---------------------------------------------------------------- frame loop
FRAME
        ifdef   OVR
        lbsr    OVRCHK          ; test build only: count frames that ran long
        endc
        lbsr    WAITVS
        lbsr    FLIP
        inc     FRAMES
        lbsr    READKEYS
        ldu     #ENTS
        lbsr    MOVEPAC
        lbsr    EAT
        ldu     #ENTS+ESIZE
        lda     #4
        sta     GCOUNT
GM1     lbsr    MOVEGHOST
        leau    ESIZE,u
        dec     GCOUNT
        bne     GM1
        lbsr    FRIGHTTICK
        lbsr    MODETICK
        lbsr    AMBIENT
        lda     IDLEDOT
        cmpa    #255
        beq     FR1
        inc     IDLEDOT
FR1     lbsr    COLLIDE
        lbsr    RENDER
        lda     STATE           ; 1 = caught, 2 = level clear
        beq     FRAME
        cmpa    #1
        beq     DIED
* level clear: flash, new maze (NEWLEVEL sets its ghost speed)
LCLEAR  lda     #$FE            ; (label: test hook, level cleared) every sound stops
        lbsr    SNDS
        clr     CURAMB
        lbsr    PAUSE60
        lda     LEVEL           ; the intermission music after every eighth maze
        inca
        anda    #7
        bne     LC1
        lda     #1
        lbsr    SNDB
LC1     lda     LEVEL           ; next maze; after the last, back to the first
        inca
        cmpa    #NLEV
        blo     LC2
        lda     #1              ; ...at full speed from then on
        sta     LAP
        clra
LC2     sta     LEVEL
        lbsr    NEWLEVEL
        lbra    NEWLIFE

DIED    lbsr    WAITVS          ; show the frame where the player was caught
        lbsr    FLIP
        lda     #$FE            ; the death sound has the voices to itself
        lbsr    SNDS
        clr     CURAMB
        lda     #3
        lbsr    SNDB
        lbsr    DEATHFLASH      ; the maze flashes through every colour
        dec     LIVES
        lbsr    HUD
        lda     LIVES
        lbne    NEWLIFE
GOVER   ldx     #TOVER          ; (label: test hook, game over)
        lda     #REDC
        lbsr    MSG
        lbsr    PAUSE60
        lbsr    PAUSE60
        lbra    NEWGAME

* ---------------------------------------------------------------- level / positions
NEWLEVEL
        lda     LEVEL           ; ghost speed by level: 15 for levels 1-8, then one more
        lsra                    ; every eight levels, 19 for 33-40 (the player is 16);
        lsra                    ; 19 for good once the game has gone round once
        lsra
        adda    #15
        cmpa    #19
        bls     NLS1
        lda     #19
NLS1    tst     LAP
        beq     NLS2
        lda     #19
NLS2    sta     GSPD
        nega                    ; blue time on the same steps: 21 - speed seconds, so
        adda    #21             ; 6 s for levels 1-8 down to 2 s for 33-40 (and after)
        ldb     #60
        mul
        std     FRTIME
        ldb     LEVEL           ; Y -> this level's header (gen.py, from the maze editor)
        lda     #LHSZ
        mul
        addd    #LVTAB
        tfr     d,y
        sty     LVP
        lda     H_WCOL,y
        sta     WCOL
        lda     H_DOTS,y
        sta     DOTS
        sta     DOTST
        clrb                    ; a fifth of them: the siren steps up after each
NL5     suba    #5
        bcs     NL6
        incb
        bra     NL5
NL6     stb     DOTSTEP
        ldd     H_EXITC,y
        std     EXITC           ; EXITC, EXITR
        lda     H_EXITY,y
        sta     EXITY
        ldd     H_HOMEC,y
        std     HOMEC           ; HOMEC, HOMER
        ldd     H_HOMEX,y
        std     HOMEX           ; HOMEX, HOMEY
        clr     ELROY
        lbsr    BUILDBG         ; the map and the background copy, from the level's tiles
        ldu     #BG             ; then both screens: stack blasts
        ldx     #BUF0
        lbsr    COPY3K
        ldu     #BG
        ldx     #BUF1
        lbsr    COPY3K
        lda     #7
        lbsr    SETF
        ldd     #BUF1
        std     BACK
        lbsr    HUD
        rts

RESETPOS
        ldu     #ENTS
        ldx     #EINIT
        ldb     #NENT*ESIZE
RP1     lda     ,x+
        sta     ,u+
        decb
        bne     RP1
        lda     GSPD            ; level speed for the ghosts
        ldu     #ENTS+ESIZE
        ldb     #4
RP2     sta     E_SPD,u
        leau    ESIZE,u
        decb
        bne     RP2
        adda    ELROY           ; red keeps its Elroy boost after a death
        sta     ENTS+ESIZE+E_SPD
        ldy     LVP             ; this level's start positions
        ldd     H_PX,y
        std     ENTS+E_X        ; E_X, E_Y
        ldd     H_RX,y
        std     ENTS+ESIZE+E_X
        lda     H_HY,y
        sta     ENTS+2*ESIZE+E_Y
        sta     ENTS+3*ESIZE+E_Y
        sta     ENTS+4*ESIZE+E_Y
        lda     H_PKX,y
        sta     ENTS+2*ESIZE+E_X
        lda     H_CYX,y
        sta     ENTS+3*ESIZE+E_X
        lda     H_ORX,y
        sta     ENTS+4*ESIZE+E_X
        clr     STATE
        clr     FRIGHT
        clr     FRIGHT+1
        clr     GMODE           ; scatter first
        clr     MTIDX
        ldd     MSCHED
        std     MTIME
        clr     DOTSEATEN
        clr     IDLEDOT
        clr     VALID0          ; nothing to restore in either buffer
        clr     VALID1
        ifdef   OVR
        lda     #1
        sta     OVRG
        endc
        lda     #2              ; redraw both screens from the background
        sta     REDRAW
        rts

* ---------------------------------------------------------------- player
MOVEPAC lda     E_WANT,u        ; reversing is always allowed
        eora    #1
        cmpa    E_DIR,u
        bne     MP0
        lda     E_WANT,u
        sta     E_DIR,u
MP0     lda     E_ACC,u
        adda    E_SPD,u
        sta     E_ACC,u
MP1     lbsr    COST
        cmpa    E_ACC,u
        bhi     MPX
        lbsr    ALIGNED
        bne     MP3
        lda     E_WANT,u        ; at a tile: turn if the wanted way is open
        lbsr    OPEN
        bne     MP2
        lda     E_WANT,u
        sta     E_DIR,u
MP2     lda     E_DIR,u
        lbsr    OPEN
        beq     MP3
        clr     E_ACC,u         ; blocked: stand still
        rts
MP3     lbsr    COST
        nega
        adda    E_ACC,u
        sta     E_ACC,u
        lbsr    STEP
        bra     MP1
MPX     rts

* EAT: at a tile centre, eat what is there
EAT     ldu     #ENTS
        lbsr    ALIGNED
        bne     EATX
        lbsr    TILEADDR        ; X -> map byte under the player
        lda     ,x
        cmpa    #2
        blo     EATX
        cmpa    #3
        bhi     EATX
        clr     ,x
        cmpa    #3
        beq     EATP
        ldd     #$0010          ; dot: 10
        lbsr    ADDSCORE
        lbsr    WAKA
        bra     EAT2
EATP    ldd     #$0050          ; power pellet: 50, ghosts turn blue
        lbsr    ADDSCORE
        lda     #8              ; the bonus sparkle
        lbsr    SNDS
        lbsr    SCARE
EAT2    lbsr    CLEARTILE       ; remove it from the background copy
        inc     DOTSEATEN
        clr     IDLEDOT
        dec     DOTS
        lda     DOTS            ; arcade "Elroy": red speeds up at 20 and 10 dots left
        cmpa    #20
        beq     EL1
        cmpa    #10
        bne     EL2
EL1     inc     ELROY
        lda     ENTS+ESIZE+E_MODE
        bne     EL2
        lda     ENTS+ESIZE+E_SPD
        inca
        sta     ENTS+ESIZE+E_SPD
EL2     lda     DOTS
        bne     EATX
        lda     #2
        sta     STATE
EATX    rts

* ---------------------------------------------------------------- ghosts
MOVEGHOST
        lda     E_REL,u         ; still in the house: leave by dot count, or after
        beq     MG0             ; four seconds with no dot eaten (arcade rule)
        cmpa    DOTSEATEN
        bls     MGREL
        lda     IDLEDOT
        cmpa    #240
        blo     MGW
        clr     IDLEDOT
MGREL   clr     E_REL,u
MGW     rts
MG0     lda     E_SPD,u
        ldb     E_X,u           ; in a tunnel (between an edge tile and its neighbour --
        cmpb    #4              ; only a tunnel opens there) ghosts move at half speed,
        blo     MG0T            ; as in the arcade
        cmpb    #56
        bhi     MG0T
        ldb     E_Y,u
        cmpb    #12
        blo     MG0T
        cmpb    #84
        bls     MG0A
MG0T    lsra
MG0A    adda    E_ACC,u
        sta     E_ACC,u
MG1     lbsr    COST
        cmpa    E_ACC,u
        bhi     MGX
        lbsr    ALIGNED
        bne     MG3
        lda     E_MODE,u        ; eyes home again? then a ghost, leaving by the door
        cmpa    #2
        bne     MGH
        lda     E_X,u
        cmpa    HOMEX
        bne     MG2
        lda     E_Y,u
        cmpa    HOMEY
        bne     MG2
MGREV   clr     E_MODE,u        ; (label: test hook, eyes revived)
        lda     #1
        sta     E_HOUSE,u
        lda     #2              ; facing up, towards the door
        sta     E_DIR,u
        lbsr    SPDFOR
        sta     E_SPD,u
        bra     MG2
MGH     tst     E_HOUSE,u       ; through the door and out: an ordinary ghost again
        beq     MG2
        lda     E_Y,u
        cmpa    EXITY
        bne     MG2
MGOUT   clr     E_HOUSE,u       ; (label: test hook, out of the house)
MG2     lbsr    CHOOSE
MG3     lbsr    COST
        nega
        adda    E_ACC,u
        sta     E_ACC,u
        lbsr    STEP
        bra     MG1
MGX     rts

* SPDFOR: A = normal speed for ghost U (red gets the arcade "Elroy" boost near the end)
SPDFOR  lda     GSPD
        tst     E_ID,u
        bne     SP1
        adda    ELROY
SP1     rts

* CHOOSE: the arcade rule. At a tile, never reverse; of the open ways, take the one whose
* next tile is nearest the target by straight-line distance squared; ties go up, left,
* down, right. Frightened ghosts pick at random (then up, left, down, right).
* Every loop count lives in memory: OPEN clobbers A, B and X.
CHOOSE
        ifdef   OVR
        inc     ECHO
        endc
        lda     E_MODE,u        ; eyes: follow the level's way-home map (gen.py)
        cmpa    #2
        bne     CHN0
        lbsr    HOMEDIR
        sta     E_DIR,u
        rts
CHN0    tst     E_HOUSE,u       ; leaving the house: straight for the door, even when blue
        bne     CH0
        lda     E_MODE,u
        cmpa    #1
        bne     CH0
        lbsr    RANDOM          ; frightened
        anda    #3
        sta     TRY
        lbsr    CHOK
        beq     CHTAKE
        clr     CHN
CHF1    ldx     #ORDER
        ldb     CHN
        lda     b,x
        sta     TRY
        lbsr    CHOK
        beq     CHTAKE
        inc     CHN
        lda     CHN
        cmpa    #4
        blo     CHF1
        bra     CHREV
CH0     lbsr    TARGET          ; TX, TY in tiles (signed)
        ldd     #$FFFF
        std     BESTD
        lda     #$FF
        sta     BEST
        clr     CHN
CH1     ldx     #ORDER
        ldb     CHN
        lda     b,x
        sta     TRY
        lbsr    CHOK
        bne     CH2
        lbsr    DIST2           ; D = squared distance from the next tile
        cmpd    BESTD
        bhs     CH2             ; strictly nearer only: earlier in ORDER wins ties
        std     BESTD
        lda     TRY
        sta     BEST
CH2     inc     CHN
        lda     CHN
        cmpa    #4
        blo     CH1
        lda     BEST
        cmpa    #$FF
        beq     CHREV
        sta     E_DIR,u
        rts
CHTAKE  lda     TRY
        sta     E_DIR,u
        rts
CHREV   lda     E_DIR,u         ; dead end: turn round
        eora    #1
        sta     E_DIR,u
        rts
* HOMEDIR: A = the way home (0 R, 1 L, 2 U, 3 D) from ghost U's tile: the level's map,
* four 2-bit entries a byte, lowest bits first
HOMEDIR lda     E_X,u
        lsra
        lsra
        sta     TMP
        ldx     #YTILE
        ldb     E_Y,u
        lda     b,x
        ldb     #16
        mul                     ; B = row * 16
        addb    TMP
        stb     TIDX
        lsrb
        lsrb
        ldx     LVP
        ldx     H_HOMED,x
        abx
        lda     ,x
        ldb     TIDX
        andb    #3
        beq     HD2
HD1     lsra
        lsra
        decb
        bne     HD1
HD2     anda    #3
        rts

* CHOK: Z when direction TRY is open and is not a reversal
CHOK    lda     TRY
        eora    #1
        cmpa    E_DIR,u
        beq     CK9
        lda     TRY
        lbra    OPEN
CK9     lda     #1
        rts

* TARGET: TX, TY for ghost U.
*   eyes        the house tile under the door; leaving the house: the tile above it
*   scatter     each ghost's own corner (outside the maze, as in the arcade)
*   chase  red     the player's tile
*          pink    four tiles ahead of the player (facing up: also four left -- the
*                  arcade's overflow quirk, kept on purpose)
*          cyan    double the vector from red to the tile two ahead of the player
*          orange  the player while more than 8 tiles away, else its scatter corner
* Red in "Elroy" mode chases even during scatter.
TARGET  lda     E_MODE,u
        cmpa    #2
        bne     TG00
        ldd     HOMEC           ; eyes: the house tile under the door
        lbra    TGS
TG00    tst     E_HOUSE,u
        beq     TG0
        ldd     EXITC           ; leaving: the tile above the door
        lbra    TGS
TG0     lbsr    PACTILE         ; PX, PY
        lda     GMODE
        bne     TGCH
        lda     E_ID,u          ; scatter (red in Elroy keeps chasing)
        bne     TGSC
        tst     ELROY
        bne     TGCH
TGSC    lda     E_ID,u
        asla
        ldx     #SCAT
        ldd     a,x
        lbra    TGS
TGCH    lda     E_ID,u
        bne     TGP
        lda     PX              ; red
        ldb     PY
        lbra    TGS
TGP     cmpa    #1
        bne     TGI
        lda     #4              ; pink: 4 ahead
        lbsr    AHEAD
        lbra    TGS
TGI     cmpa    #2
        bne     TGC
        lda     #2              ; cyan: Q = 2 ahead, target = 2Q - red
        lbsr    AHEAD
        sta     TX
        stb     TY
        ldx     #ENTS+ESIZE     ; red's tile
        lda     E_X,x
        adda    #2
        lsra
        lsra
        sta     TMP
        lda     TX
        asla
        suba    TMP
        sta     TX
        ldb     E_Y,x
        addb    #3
        ldx     #YTILE
        lda     b,x
        sta     TMP
        lda     TY
        asla
        suba    TMP
        sta     TY
        rts
TGC     lda     E_X,u           ; orange: distance squared to the player > 64?
        adda    #2
        lsra
        lsra
        suba    PX
        bpl     TGC1
        nega
TGC1    tfr     a,b
        mul
        std     ROFF
        ldb     E_Y,u
        addb    #3
        ldx     #YTILE
        lda     b,x
        suba    PY
        bpl     TGC2
        nega
TGC2    tfr     a,b
        mul
        addd    ROFF
        cmpd    #64
        bhi     TGC3
        lda     #3*2            ; close: its corner
        ldx     #SCAT
        ldd     a,x
        bra     TGS
TGC3    lda     PX
        ldb     PY
TGS     sta     TX
        stb     TY
        rts

* PACTILE: PX, PY = the tile under the player's centre
PACTILE lda     ENTS+E_X
        adda    #2
        lsra
        lsra
        sta     PX
        ldb     ENTS+E_Y
        addb    #3
        ldx     #YTILE
        lda     b,x
        sta     PY
        rts

* AHEAD: A, B = the tile N (in A) tiles ahead of the player; facing up adds N left
AHEAD   sta     TMP
        ldb     ENTS+E_DIR
        lda     PX
        ldx     #DX1
        tst     b,x
        beq     AH1
        bmi     AH0
        adda    TMP
        bra     AH1
AH0     suba    TMP
AH1     sta     AHX
        lda     PY
        ldx     #DY1
        tst     b,x
        beq     AH3
        bmi     AH2
        adda    TMP
        bra     AH3
AH2     suba    TMP             ; facing up: the arcade also moves the target left
        pshs    a
        lda     AHX
        suba    TMP
        sta     AHX
        puls    a
AH3     tfr     a,b
        lda     AHX
        rts

* DIST2: D = (next col - TX)^2 + (next row - TY)^2 for direction TRY. Tunnel-aware: on a
* row whose edge is open the short way across may be through the tunnel (16 columns
* round), and likewise down a column whose top edge is open (15 rows round), so ghosts
* follow the player through tunnels (the arcade measures straight).
DIST2   ldx     #YTILE
        ldb     E_Y,u
        lda     b,x
        ldx     #DY1
        ldb     TRY
        adda    b,x
        bpl     DS0
        lda     #14             ; up from row 0: row 14
DS0     cmpa    #15
        blo     DS0A
        clra                    ; down from row 14: row 0
DS0A    sta     NROW
        lda     E_X,u
        lsra
        lsra
        ldx     #DX1
        ldb     TRY
        adda    b,x
        anda    #15
        sta     NCOL
        suba    TX
        bpl     DS1
        nega
DS1     cmpa    #8              ; dx 9..15: through a tunnel may be shorter
        bls     DS1A
        cmpa    #16
        bhs     DS1A
        sta     DXY
        ldb     NROW
        lda     #16
        mul
        ldx     #MAP
        abx
        lda     ,x              ; this row's column 0: open means a tunnel
        cmpa    #1
        lda     DXY
        beq     DS1A
        nega
        adda    #16
DS1A    tfr     a,b
        mul
        std     ROFF
        lda     NROW
        suba    TY
        bpl     DS2
        nega
DS2     cmpa    #7              ; dy 8..14: through a tunnel may be shorter
        bls     DS2A
        cmpa    #15
        bhs     DS2A
        sta     DXY
        ldx     #MAP
        ldb     NCOL
        lda     b,x             ; this column's row 0: open means a tunnel
        cmpa    #1
        lda     DXY
        beq     DS2A
        nega
        adda    #15
DS2A    tfr     a,b
        mul
        addd    ROFF
        rts

* MODETICK: the arcade's scatter/chase schedule (level 1: 7 s, 20, 7, 20, 5, 20, 5, then
* chase for good), paused while ghosts are blue. Every switch reverses the ghosts.
MODETICK
        ldd     FRIGHT
        bne     MTX
        ldd     MTIME
        beq     MTX             ; 0 = the last phase, for good
        subd    #1
        std     MTIME
        bne     MTX
        ifdef   OVR
        inc     EMOD
        endc
        lda     GMODE
        eora    #1
        sta     GMODE
        ldb     MTIDX
        incb
        stb     MTIDX
        aslb
        ldx     #MSCHED
        ldd     b,x
        std     MTIME
        ldu     #ENTS+ESIZE     ; reverse every ghost that is out and chasing
        ldb     #4
MT1     lda     E_MODE,u
        bne     MT2
        tst     E_HOUSE,u
        bne     MT2
        lda     E_DIR,u
        eora    #1
        sta     E_DIR,u
MT2     leau    ESIZE,u
        decb
        bne     MT1
MTX     rts

* SCARE: power pellet. Every ghost that is not eyes turns blue, slows and reverses.
SCARE
        ifdef   OVR
        inc     ESCA
        endc
        ldd     FRTIME          ; this level's blue time (NEWLEVEL)
        std     FRIGHT
        ldu     #ENTS+ESIZE
        ldb     #4
SC1     lda     E_MODE,u
        cmpa    #2
        beq     SC2
        lda     #1
        sta     E_MODE,u
        lda     #10             ; arcade: blue ghosts at half speed
        sta     E_SPD,u
        tst     E_HOUSE,u       ; not in the house: they would turn back from the door
        bne     SC2
        lda     E_DIR,u
        eora    #1
        sta     E_DIR,u
SC2     leau    ESIZE,u
        decb
        bne     SC1
        rts

FRIGHTTICK
        ldd     FRIGHT
        beq     FTX
        subd    #1
        std     FRIGHT
        bne     FTX
        ldu     #ENTS+ESIZE     ; time up: back to chasing
        ldb     #4
FT1     lda     E_MODE,u
        cmpa    #1
        bne     FT2
        clr     E_MODE,u
        pshs    b
        lbsr    SPDFOR
        sta     E_SPD,u
        puls    b
FT2     leau    ESIZE,u
        decb
        bne     FT1
FTX     rts

* COLLIDE: player against each ghost (|dx| < 3 elements, |dy| < 4 rows)
COLLIDE ldu     #ENTS+ESIZE
        ldb     #4
CO1     lda     E_X,u
        suba    ENTS+E_X
        bpl     CO2
        nega
CO2     cmpa    #3
        bhs     CON
        lda     E_Y,u
        suba    ENTS+E_Y
        bpl     CO3
        nega
CO3     cmpa    #4
        bhs     CON
        lda     E_MODE,u
        beq     CAUGHT
        cmpa    #2
        beq     CON
        lda     #2              ; eat a blue ghost: 200, it becomes eyes
        sta     E_MODE,u
        lda     #40
        sta     E_SPD,u
        pshs    b,u
        ldd     #$0200
        lbsr    ADDSCORE
        lbsr    GULP
        puls    b,u
CON     leau    ESIZE,u
        decb
        bne     CO1
        rts
CAUGHT  lda     #1
        sta     STATE
        rts

* ---------------------------------------------------------------- movement helpers
* COST: A = cost of one step in the entity's direction
COST    lda     E_DIR,u
        cmpa    #2
        blo     CS1
        lda     #VCOST
        rts
CS1     lda     #HCOST
        rts

* ALIGNED: Z set when the entity sits exactly on a tile
ALIGNED lda     E_X,u
        anda    #3
        bne     AL1
        ldx     #YMOD
        ldb     E_Y,u
        lda     b,x
AL1     rts

* OPEN: Z set when the tile next to the entity in direction A is open. Both axes wrap
* (tunnels). The house door is open only to ghosts leaving the house and to eyes.
* Clobbers A, B, X -- callers must not keep a loop count in B (that hung frightened
* ghosts in dead ends, found from a user's snapshot)
OPEN    pshs    a
        lda     E_X,u
        lsra
        lsra
        ldx     #DX1
        ldb     ,s
        adda    b,x
        anda    #15             ; column -1 and 16 wrap through a tunnel
        sta     TMP             ; next column
        ldx     #YTILE
        ldb     E_Y,u
        lda     b,x
        ldx     #DY1
        ldb     ,s+
        adda    b,x             ; next row, wrapping -1 and 15 the same way
        bpl     OP0
        lda     #14
OP0     cmpa    #15
        blo     OP0A
        clra
OP0A    ldb     #16
        mul                     ; row*16 fits in B
        addb    TMP
        ldx     #MAP
        abx
        lda     ,x
        cmpa    #1
        beq     OP1
        cmpa    #4
        beq     OPD
OPZ     clra                    ; Z = open
        rts
OPD     tst     E_HOUSE,u
        bne     OPZ
        lda     E_MODE,u
        cmpa    #2
        beq     OPZ
OP1     lda     #1              ; NZ = wall
        rts

* STEP: move one element or row in the entity's direction
STEP    lda     E_DIR,u
        beq     ST0
        cmpa    #1
        beq     ST1
        cmpa    #2
        beq     ST2
        inc     E_Y,u           ; off the bottom: come in at the top
        lda     E_Y,u
        cmpa    #90
        bls     STDX
STWD    lda     #6              ; (label: test hook, wrapped bottom to top)
        sta     E_Y,u
STDX    rts
ST0     inc     E_X,u           ; off the right edge: come in at the left
        lda     E_X,u
        cmpa    #60
        bls     ST0X
        clr     E_X,u
ST0X    rts
ST1     dec     E_X,u           ; off the left edge: come in at the right
        bpl     ST1X
        lda     #60
        sta     E_X,u
ST1X    rts
ST2     dec     E_Y,u           ; off the top: come in at the bottom
        lda     E_Y,u
        cmpa    #6
        bhs     ST2X
STWU    lda     #90             ; (label: test hook, wrapped top to bottom)
        sta     E_Y,u
ST2X    rts

* TILEADDR: X -> map byte under entity U (aligned)
TILEADDR
        ldx     #YTILE
        ldb     E_Y,u
        lda     b,x
        ldb     #16
        mul                     ; D = row * 16 (fits in B)
        stb     TMP
        ldb     E_X,u
        lsrb
        lsrb
        addb    TMP
        ldx     #MAP
        abx
        rts

* CLEARTILE: blank the player's tile (2 bytes x 6 rows) in the background copy
CLEARTILE
        ldu     #ENTS
        ldb     E_Y,u
        lda     #32
        mul
        addd    #BG
        tfr     d,x
        ldb     E_X,u
        lsrb
        abx
        ldb     #6
        lda     #$80
CT1     sta     ,x
        sta     1,x
        leax    32,x
        decb
        bne     CT1
        rts

* ---------------------------------------------------------------- drawing
* RENDER: in the back buffer, restore last time's squares from BG, then draw all sprites
RENDER  lda     REDRAW          ; level start or new life: whole screen from BG
        beq     RN0
        dec     REDRAW
        ldu     #BG
        ldx     BACK
        lbsr    COPY3K
        bra     RN2
RN0     ldx     BACK            ; which list belongs to this buffer
        cmpx    #BUF0
        bne     RN1
        tst     VALID0
        beq     RN2
        ldy     #SAV0
        bra     RNR
RN1     tst     VALID1
        beq     RN2
        ldy     #SAV1
RNR     lda     #NENT
        sta     GCOUNT
RNR1    ldb     1,y             ; offset = y*32 + x/2
        lda     #32
        mul
        std     ROFF
        ldb     ,y
        lsrb
        clra
        addd    ROFF
        std     ROFF
        addd    BACK
        tfr     d,x
        ldd     ROFF
        addd    #BG
        tfr     d,u
        pshs    y
        lbsr    RESTORE         ; generated, unrolled
        puls    y
        leay    2,y
        dec     GCOUNT
        bne     RNR1
RN2     ldx     BACK            ; draw: ghosts first, the player on top
        cmpx    #BUF0
        bne     RN3
        ldy     #SAV0
        lda     #1
        sta     VALID0
        bra     RN4
RN3     ldy     #SAV1
        lda     #1
        sta     VALID1
RN4     sty     SAVP
        ldu     #ENTS+ESIZE
        lda     #4
        sta     GCOUNT
RN5     lbsr    GSPRITE         ; Y -> sprite table
        lbsr    DRAWENT
        leau    ESIZE,u
        dec     GCOUNT
        bne     RN5
        ldu     #ENTS
        lbsr    PSPRITE
        lbsr    DRAWENT
        rts

* DRAWENT: draw entity U with sprite Y into the back buffer, record its square
DRAWENT ldx     SAVP
        lda     E_X,u
        ldb     E_Y,u
        std     ,x++
        stx     SAVP
        lda     E_X,u
        lsra
        bcc     DE1
        leay    36,y            ; odd x: the variant shifted one element right
DE1     ldb     E_Y,u
        lda     #32
        mul
        addd    BACK
        tfr     d,x
        ldb     E_X,u
        lsrb
        abx
        lbra    DRAWSPR         ; generated, unrolled

* GSPRITE: Y -> table for ghost U
GSPRITE lda     E_MODE,u
        beq     GS0
        cmpa    #2
        beq     GS2
        lda     #9              ; frightened; flash white in the last two seconds
        ldx     FRIGHT
        cmpx    #120
        bhi     GS1
        ldb     FRAMES
        andb    #8
        beq     GS1
        lda     #10
        bra     GS1
GS2     lda     #11
        bra     GS1
GS0     lda     E_ID,u
        adda    #5
GS1     ldb     #SPRSZ
        mul
        addd    #SPRTAB
        tfr     d,y
        rts

* PSPRITE: Y -> player table: mouth open by direction, closed every other 4 frames
PSPRITE lda     FRAMES
        anda    #4
        beq     PS1
        lda     #4
        bra     PS2
PS1     lda     E_DIR,u
PS2     ldb     #SPRSZ
        mul
        addd    #SPRTAB
        tfr     d,y
        rts

* ---------------------------------------------------------------- HUD and messages
* HUD: score (6 digits, white) and lives (a yellow digit), into BG and both screens
* HUD: everything -- score, level, lives -- into BG and both screens. (A score change alone
* goes to HUDS, which draws only the digits that changed: a dot changes one or two, and
* drawing all ten glyphs three times over cost about 8,000 cycles, over half a field.)
HUD     ldd     SCORE           ; every score digit differs from "the previous score"
        coma
        comb
        std     OLDS
        lda     SCORE+2
        coma
        sta     OLDS+2
        lbsr    HUDS
        lda     #GL_L           ; L and the level number
        ldb     #CYANC
        ldx     #20
        lbsr    GLYPHAT
        lbsr    LVDIG
        pshs    b
        ldb     #CYANC
        ldx     #22
        lbsr    GLYPHAT
        puls    a
        ldb     #CYANC
        ldx     #24
        lbsr    GLYPHAT
        lda     LIVES
        ldb     #YELLOWC
        ldx     #30
        lbra    GLYPHAT

* HUDS: the score digits that differ from OLDS, white, into BG and both screens
HUDS
        ifdef   OVR
        inc     EHUD
        endc
        ldx     #0              ; offset: byte column 0, element row 0
        ldy     #SCORE
        lda     #3
        sta     HCNT
HU1     lda     ,y
        eora    3,y             ; the bits that changed in this byte
        sta     HDIF
        anda    #$F0
        beq     HU2
        lda     ,y
        lsra
        lsra
        lsra
        lsra
        ldb     #WHITEC
        pshs    x,y
        lbsr    GLYPHAT
        puls    x,y
HU2     leax    2,x
        lda     HDIF
        anda    #$0F
        beq     HU3
        lda     ,y
        anda    #$0F
        ldb     #WHITEC
        pshs    x,y
        lbsr    GLYPHAT
        puls    x,y
HU3     leax    2,x
        leay    1,y
        dec     HCNT
        bne     HU1
        rts

* LVDIG: A = tens, B = units of the level number shown (LEVEL + 1)
LVDIG   lda     LEVEL
        inca
        clrb
LVD1    cmpa    #10
        blo     LVD2
        suba    #10
        incb
        bra     LVD1
LVD2    exg     a,b
        rts

* MSG: text X (glyph indices, $FF ends) in colour A, centred on the open row above the player
MSG     sta     MCOL
        stx     MPTR
        ldx     #72*32          ; keep the row (with whatever dots are left) to put back
        ldu     #MSGSAVE
        ldb     #6*32
MG0S    lda     BG,x
        sta     ,u+
        leax    1,x
        decb
        bne     MG0S
        ldx     MPTR
        lda     MCOL
        ldb     #73
* PRINTC: text X (glyph indices, $FF ends) in colour A, centred, top at element row B
PRINTC  sta     MCOL
        stx     MPTR
        lda     #32
        mul
        std     MOFF
        ldx     MPTR
        lda     #16             ; start column = 16 - length (2 bytes a glyph)
MS0     tst     ,x+
        bmi     MS1
        deca
        bra     MS0
MS1     tfr     a,b             ; offset = row*32 + column
        clra
        addd    MOFF
        std     MOFF
MS2     ldx     MPTR
        lda     ,x+
        bmi     MSX
        stx     MPTR
        ldb     MCOL
        ldx     MOFF
        lbsr    GLYPHAT
        ldd     MOFF
        addd    #2
        std     MOFF
        bra     MS2
MSX     rts

* GLYPHAT: glyph A in colour B at offset X (from the buffer start), in BG and both screens
GLYPHAT stb     GCOL
        ldb     #10
        mul
        addd    #FONT
        tfr     d,y
        ldu     #BG
        bsr     GA1
        ldu     #BUF0
        bsr     GA1
        ldu     #BUF1
GA1     pshs    x,y,u
        tfr     x,d
        leau    d,u
        ldb     #5
GA2     lda     ,y+
        ora     GCOL
        sta     ,u
        lda     ,y+
        ora     GCOL
        sta     1,u
        leau    32,u
        decb
        bne     GA2
        puls    x,y,u,pc

* MSGOFF: put the message row back as it was before MSG
MSGOFF  ldx     #72*32
        ldu     #MSGSAVE
        ldb     #6*32
MO1     lda     ,u+
        sta     BG,x
        sta     BUF0,x
        sta     BUF1,x
        leax    1,x
        decb
        bne     MO1
        rts

* DRAWALL: draw the sprites into both screens (title and READY)
DRAWALL lbsr    RENDER
        lbsr    FLIP
        lbsr    RENDER
        lbsr    FLIP
        rts

* ---------------------------------------------------------------- score
* ADDSCORE: add BCD D (A = hundreds, B = tens/units) to SCORE
ADDSCORE
        sta     ADDM
        stb     ADDL
        ldd     SCORE           ; the old score, so HUDS draws only the digits that change
        std     OLDS
        lda     SCORE+2
        sta     OLDS+2
        lda     SCORE+2
        adda    ADDL
        daa
        sta     SCORE+2
        lda     SCORE+1
        adca    ADDM
        daa
        sta     SCORE+1
        lda     SCORE
        adca    #0
        daa
        sta     SCORE
        lda     OLDS            ; 10,000 points: an extra life (the score only goes up)
        bne     ASX
        lda     SCORE
        beq     ASX
        lda     LIVES
        cmpa    #9
        bhs     ASX
        inc     LIVES
        lda     #5              ; the fanfare
        lbsr    SNDS
        lbra    HUD             ; the lives are drawn too
ASX     lbra    HUDS

* ---------------------------------------------------------------- sound
* The sounds are made by the engine in the upper 32K (audio.asm; HAVEAUD = it is there). It
* plays in the idle time of the frames (WAITV0), a tick a field.
* SNDB: A = a sound that plays to its end (0-4); BREAK during it leaves the game.
* SNDS: A = an effect that starts and plays on (5-9), a loop under the game (10-16), $FF = stop
* the loop, $FE = stop everything.
SNDB    tst     HAVEAUD
        beq     SNX
        jsr     $800A
        bcs     SNQ
SNX     rts
SNQ     lbra    QUIT
SNDS    tst     HAVEAUD
        beq     SNX
        jmp     $800A

* WAKA: the eat sound, alternating two chirps
WAKA    lda     #6
        com     WAKAT
        beq     WK1
        inca
WK1     bra     SNDS
GULP                            ; a ghost eaten: the sound to its end (the arcade pauses here too)
        ifdef   OVR
        inc     EGUL
        endc
        lda     #4
        bra     SNDB

* AMBIENT: the loop under the game, once a frame: eyes if a ghost is eyes, else the blue-ghost
* sound, else the siren (5 steps, one after each fifth of the dots)
AMBIENT tst     HAVEAUD
        beq     AMX
        ldu     #ENTS+ESIZE
        ldb     #4
AM1     lda     E_MODE,u
        cmpa    #2
        beq     AMEYE
        leau    ESIZE,u
        decb
        bne     AM1
        ldd     FRIGHT
        bne     AMFR
        lda     DOTST
        suba    DOTS            ; dots eaten
        ldb     #10
AM2     cmpb    #14
        beq     AM3
        suba    DOTSTEP
        bcs     AM3
        incb
        bra     AM2
AM3     tfr     b,a
        bra     AM4
AMEYE   lda     #16
        bra     AM4
AMFR    lda     #15
AM4     cmpa    CURAMB
        beq     AMX
        sta     CURAMB
        lbra    SNDS
AMX     rts

* ---------------------------------------------------------------- input
        ifdef   BOT
* ---- test build only (lwasm -DBOT=1): an autopilot in place of the keyboard, for
* measuring level difficulty. At each tile it takes the first step of the shortest path
* (both axes wrap) to the nearest dot or pill, treating every tile a live ghost is on or
* next to, and the tile two ahead of it, as blocked. With no such path it steps to any
* open tile that is not blocked. Ties between equal paths are broken at random.
READKEYS
        ldu     #ENTS
        lbsr    ALIGNED
        lbne    BKX
        lbsr    PACTILE
        lda     PY
        ldb     #16
        mul
        addb    PX
        stb     BSTART
        ldx     #BFD            ; all unvisited
        lda     #$FF
        ldb     #240
BK0     sta     ,x+
        decb
        bne     BK0
        ldy     #ENTS+ESIZE     ; danger round every live (chasing) ghost
        lda     #4
        sta     BGN
BK1     tst     E_MODE,y
        lbne    BK3
        lda     E_X,y
        adda    #2
        lsra
        lsra
        sta     BTMP
        ldx     #YTILE
        ldb     E_Y,y
        addb    #3
        abx
        lda     ,x
        ldb     #16
        mul
        addb    BTMP
        stb     BGT
        lbsr    BMARK
        clr     BDIR
BK2     ldb     BGT
        lda     BDIR
        lbsr    BNBR
        lbsr    BMARK
        lda     BDIR
        cmpa    E_DIR,y         ; and two ahead in its direction
        bne     BK2A
        lda     BDIR
        lbsr    BNBR
        lbsr    BMARK
BK2A    inc     BDIR
        lda     BDIR
        cmpa    #4
        blo     BK2
BK3     leay    ESIZE,y
        dec     BGN
        lbne    BK1
        ldx     #BFD            ; the start
        ldb     BSTART
        lda     #4
        abx
        sta     ,x
        clr     BQH
        clr     BQT
        lda     ENTS+E_DIR      ; on a tie keep going the same way (a random tie-break
        sta     BD              ; on every tile made it dither between two dots), then
        lbsr    BFIRST          ; the other ways in a per-game rotation (BSEED)
        lda     BSEED
        anda    #3
        sta     BROT
        clr     BDIR
BK4     lda     BDIR
        adda    BROT
        anda    #3
        sta     BD
        lbsr    BFIRST
BK5     inc     BDIR
        lda     BDIR
        cmpa    #4
        blo     BK4
        bra     BK6
* BFIRST: the start's neighbour in direction BD, if open and unvisited, joins the queue
BFIRST  ldb     BSTART
        lda     BD
        lbsr    BNBR
        stb     BN
        lbsr    BPASS
        bne     BFX
        ldx     #BFD
        ldb     BN
        abx
        lda     ,x
        cmpa    #$FF
        bne     BFX
        lda     BD
        sta     ,x              ; X still -> BFD[BN]
        lbra    BPUSH
BFX     rts
BK6     lda     BQH             ; breadth first
        cmpa    BQT
        beq     BKFLEE
        ldx     #BQ
        ldb     BQH
        abx
        ldb     ,x
        stb     BCUR
        inc     BQH
        ldx     #MAP
        abx
        lda     ,x
        cmpa    #2
        blo     BK7
        cmpa    #3
        bhi     BK7
        ldx     #BFD            ; a dot or pill: go its first step
        abx
        lda     ,x
        sta     ENTS+E_WANT
        rts
BK7     clr     BDIR
BK8     lda     BDIR
        ldb     BCUR
        lbsr    BNBR
        stb     BN
        lbsr    BPASS
        bne     BK9
        ldx     #BFD
        ldb     BN
        abx
        lda     ,x
        cmpa    #$FF
        bne     BK9
        ldx     #BFD            ; BFD[BN] = BFD[BCUR]: the same first step
        ldb     BCUR
        abx
        lda     ,x
        ldx     #BFD
        ldb     BN
        abx
        sta     ,x
        lbsr    BPUSH
BK9     inc     BDIR
        lda     BDIR
        cmpa    #4
        blo     BK8
        bra     BK6
BKFLEE  clr     BDIR            ; no safe path: any open, unblocked neighbour
BKF1    lda     BDIR
        ldb     BSTART
        lbsr    BNBR
        stb     BN
        lbsr    BPASS
        bne     BKF2
        ldx     #BFD
        ldb     BN
        abx
        lda     ,x
        cmpa    #$FE
        beq     BKF2
        lda     BDIR
        sta     ENTS+E_WANT
        rts
BKF2    inc     BDIR
        lda     BDIR
        cmpa    #4
        blo     BKF1
BKX     rts
* BMARK: mark tile B blocked (not the player's own)
BMARK   cmpb    BSTART
        beq     BMX
        ldx     #BFD
        lda     #$FE
        abx
        sta     ,x
BMX     rts
* BPUSH: append BN to the queue
BPUSH   ldx     #BQ
        ldb     BQT
        lda     BN
        abx
        sta     ,x
        inc     BQT
        rts
* BPASS: Z when tile BN is open to the player (not wall, not door)
BPASS   ldx     #MAP
        ldb     BN
        abx
        lda     ,x
        cmpa    #1
        beq     BPN
        cmpa    #4
        beq     BPN
        clra
        rts
BPN     lda     #1
        rts
* BNBR: B = the tile next to tile B in direction A (0 R 1 L 2 U 3 D), both axes wrapping
BNBR    cmpa    #1
        blo     BNR
        beq     BNL
        cmpa    #2
        beq     BNU
        cmpb    #224            ; down
        bhs     BND1
        addb    #16
        rts
BND1    subb    #224
        rts
BNU     cmpb    #16
        blo     BNU1
        subb    #16
        rts
BNU1    addb    #224
        rts
BNR     tfr     b,a
        anda    #15
        cmpa    #15
        beq     BNR1
        incb
        rts
BNR1    subb    #15
        rts
BNL     tfr     b,a
        anda    #15
        beq     BNL1
        decb
        rts
BNL1    addb    #15
        rts
        else
READKEYS
        ldu     #ENTS
        lda     #$F7            ; up: column 3
        ldb     #2
        bsr     KEY
        lda     #$EF            ; down: column 4
        ldb     #3
        bsr     KEY
        lda     #$DF            ; left: column 5
        ldb     #1
        bsr     KEY
        lda     #$BF            ; right: column 6
        ldb     #0
        bsr     KEY
        lda     #$FF
        sta     $FF02
        tst     OPTCTL          ; the stick, if the menu says so
        beq     KYX
        lbsr    JOYDIR          ; B: bit 0 up, 1 down, 2 left, 3 right
        ldx     #KYMAP
KJ1     lda     ,x+             ; E_WANT for each bit, 0..3 then 255
        bmi     KYX
        lsrb
        bcc     KJ1
        sta     E_WANT,u
        bra     KJ1
KYMAP   fcb     2,3,1,0,255
KYX     rts
KEY     sta     $FF02
        lda     $FF00
        bita    #$08            ; arrows are all on row 3
        bne     KY1
        stb     E_WANT,u
KY1     rts
        endc

CHKBRK  lda     #$FB            ; BREAK: column 2, row 6
        sta     $FF02
        lda     $FF00
        ldb     #$FF
        stb     $FF02
        bita    #$40
        beq     QUIT
        rts
QUIT    lds     SAVES0          ; leave from anywhere
        tst     ENGINE          ; a sound chip quiet, the Multi-Pak slots and the mux back as they were
        beq     QT00
        clr     OPTSND
        lbsr    SNDSET
QT00    sta     $FFDE           ; the SAM back to ROM mode: BASIC is there again
        lda     #$82            ; DAC at rest (a sound may have been mid-wave)
        sta     $FF20
        lda     #2              ; text screen at $0400, SAM V = 0
        lbsr    SETF
        sta     $FFC4
        sta     $FFC2
        sta     $FFC0
        lda     $FF22
        anda    #$07
        sta     $FF22
        ldx     $0019           ; BASIC's program starts (TXTTAB) where the game's screens and
        cmpx    #BUF0           ; background are, so the game overwrote the empty program's
        blo     QT0             ; marker. Put it back, as NEW leaves it: a zero byte before the
        clr     -1,x            ; program, a zero link at its start, and the variable pointers
        clr     ,x+             ; (VARTAB, ARYTAB, ARYEND) just after it. Without this LIST shows
        clr     ,x+             ; garbage and a typed program will not RUN. (A program that
        stx     $001B           ; lives below $0E00 was not touched: leave it.)
        stx     $001D
        stx     $001F
QT0     tst     COCO3           ; CoCo 3: the GIME back to normal text, BASIC's colours back
        beq     QT1
        lda     #15
        sta     $FF9C
        ldu     #PALSAV
        bsr     SETPAL
        tst     FASTF           ; and the high speed it was found at
        beq     QT1
        sta     $FFD9
QT1     andcc   #$AF
        rts

* SETPAL: CoCo 3 palette registers 0-7 (the SG colours) from the 8 bytes at U
SETPAL  ldx     #$FFB0
SPL1    lda     ,u+
        sta     ,x+
        cmpx    #$FFB8
        bne     SPL1
        rts

* CoCo 3 codes nearest a CoCo 2's SG colours (measured in xroar-dev: CIE Lab, nearest of
* all 64 codes, green and cyan kept apart). Green, yellow, blue, red, buff, cyan, magenta,
* orange.
PALCMP  fcb     $11,$34,$0C,$07,$3F,$1E,$18,$15     ; composite
PALRGB  fcb     $10,$3E,$0E,$21,$3F,$11,$2F,$26     ; RGB monitor

* ---------------------------------------------------------------- timing and screens
* WAITVS: wait for the next field sync, then look at BREAK. Every wait in the game (the
* frame loop, READY!, the death flash, the pauses) goes through here, so BREAK is never
* dead for longer than a frame. (CHKBRK clobbers A and B: callers keep nothing in them.)
WAITVS  bsr     WAITV0
        lbra    CHKBRK
WAITV0  lda     $FF02           ; clear the field-sync flag, wait for the next (bounded)
        tst     HAVEAUD
        bne     WVA
        ldx     #0
WV1     tst     $FF03
        bmi     WV2
        leax    -1,x
        bne     WV1
WV2     lda     $FF02
        rts
* WVA: the audio engine plays through the wait (a tick, then samples until the sync), so a
* sound can never make a frame late; it clears the flag and returns
WVA     jmp     $8007

FLIP    ldd     BACK            ; show the buffer just drawn
        cmpd    #BUF0
        bne     FP1
        lda     #7
        lbsr    SETF
        ldd     #BUF1
        std     BACK
        rts
FP1     lda     #13
        lbsr    SETF
        ldd     #BUF0
        std     BACK
        rts

PAUSE60 ldb     #60
PA1     pshs    b
        bsr     WAITVS
        puls    b
        decb
        bne     PA1
        rts

* DEATHFLASH: every wall and the house door step through the seven wall colours (FLCOLS;
* never buff, which reads as white), twice, FLFR frames a colour, then go back to their own
* colours. Recolouring takes about 1.7 frames, so it is done in the hidden buffer
* and flipped in at field sync: done on the shown one it wiped down the screen.
DEATHFLASH
        ldu     #BUF0           ; copy the shown screen (not BACK) into BACK, so both
        cmpu    BACK            ; buffers hold the moment of death
        bne     DF0
        ldu     #BUF1
DF0     ldx     BACK
        lbsr    COPY3K
        lda     #14             ; 2 passes x 7 colours
        sta     FLN
DF1     ldx     BACK
        stx     FLBUF
        ldb     FLN
        cmpb    #7
        bls     DF1A
        subb    #7
DF1A    ldx     #FLCOLS-1
        lda     b,x             ; FLN 1..7 (small: the signed offset is safe)
        sta     FLD             ; the door flashes with the walls
        lbsr    WALLCOL
        lbsr    WAITVS
        lbsr    FLIP
        ldb     #FLFR-1
DF2     pshs    b
        lbsr    WAITVS
        puls    b
        decb
        bne     DF2
        dec     FLN
        bne     DF1
        lda     #DOORC          ; back to their own colours: hidden one, flip, then the other
        sta     FLD
        ldx     BACK
        stx     FLBUF
        lda     WCOL
        lbsr    WALLCOL
        lbsr    WAITVS
        lbsr    FLIP
        ldx     BACK
        stx     FLBUF
        lda     WCOL
* WALLCOL: recolour every wall tile (MAP = 1) of the buffer at FLBUF to colour byte A,
* and the door (MAP = 4) to FLD
WALLCOL sta     FLW
        ldu     #MAP
        ldx     FLBUF
        leax    192,x           ; the maze starts below the score row
        lda     #15
        sta     BROW
WC1     lda     #16
        sta     BCOL
WC2     lda     ,u+
        ldb     FLW
        cmpa    #1
        beq     WC2A
        ldb     FLD
        cmpa    #4
        bne     WC4
WC2A    stb     FLC
        ldb     #6
        pshs    x
WC3     lda     ,x
        anda    #$0F
        ora     FLC
        sta     ,x
        lda     1,x
        anda    #$0F
        ora     FLC
        sta     1,x
        leax    32,x
        decb
        bne     WC3
        puls    x
WC4     leax    2,x
        dec     BCOL
        bne     WC2
        leax    5*32,x
        dec     BROW
        bne     WC1
        rts

FLCOLS  fcb     $90,$80,$F0,$E0,$D0,$B0,$A0 ; read backwards: blue, red, cyan, magenta,
*                                       orange, green, yellow (gen.py's WALLCYCLE)

* SETF: SAM display offset F6-F0 = A (512-byte units)
SETF    ldx     #$FFC6
        ldb     #7
SF1     lsra
        bcc     SF2
        sta     1,x
        bra     SF3
SF2     sta     ,x
SF3     leax    2,x
        decb
        bne     SF1
        rts

* TITLEANIM: the title-screen chase. Everyone moves one element every other frame across
* the screen, wrapping round; every five seconds the ghosts turn blue (or back) and
* everybody turns round, so the chase runs one way and then the other.
TITLEANIM
        ldd     TPH
        subd    #1
        std     TPH
        bne     TA1
        ldd     #300
        std     TPH
        ldu     #ENTS
        ldb     #NENT
TA0     lda     E_DIR,u
        eora    #1
        sta     E_DIR,u
        cmpu    #ENTS
        beq     TA0N
        lda     E_MODE,u
        eora    #1              ; chasing <-> blue
        sta     E_MODE,u
TA0N    leau    ESIZE,u
        decb
        bne     TA0
TA1     lda     FRAMES
        anda    #1
        bne     TAX
        ldu     #ENTS
        lda     #NENT
        sta     GCOUNT
TA2     lbsr    STEP
        leau    ESIZE,u
        dec     GCOUNT
        bne     TA2
TAX     rts

* SPLASH: the title screen -- credits, with room for the chase on element rows 30-35.
* Text goes into the background copy and both screens, so RENDER can restore under the
* runners. Silent: the intro tune plays when a game starts.
SPLASH  lbsr    FILL3
        lda     #7
        lbsr    SETF
        ldd     #BUF1
        std     BACK
        clr     VALID0
        clr     VALID1
        clr     REDRAW
        ldx     #TT1            ; PAK FAN BY CAMCO
        lda     #YELLOWC
        ldb     #2
        lbsr    PRINTC
        ldx     #TPGM
        lda     #CYANC
        ldb     #78
        lbsr    PRINTC
        ldx     #TNAME
        lda     #CYANC
        ldb     #84
        lbsr    PRINTC
        ldx     #TCOPY
        lda     #CYANC
        ldb     #90
        lbsr    PRINTC
        clr     MPREV
        clr     MGO
* ---------------------------------------------------------------- the title menu
* Rows (text rows at element rows 44, 51, 58, 65): PLAY, CONTROL, SOUND, ABOUT.
* UP/DOWN pick a row, LEFT/RIGHT change what it holds (CONTROL, SOUND), SPACE, ENTER and fire do the row.
MENUDRAW
        clr     MROW
MD1     ldb     MROW
        ldx     #ROWY
        lda     b,x
        sta     MYY
        lda     #YELLOWC
        cmpb    MSEL
        bne     MD2
        lda     #WHITEC
MD2     sta     MCLR
        ldx     #TBL16          ; blank the row, then the text
        lda     MCLR
        ldb     MYY
        lbsr    PRINTC
        lda     MROW
        asla
        ldx     #MTXT
        ldx     a,x             ; the row's text: its own, or for CONTROL and SOUND the chosen one
        lda     MROW
        cmpa    #1
        bne     MD3
        ldx     #TCTLK
        tst     OPTCTL
        beq     MD5
        ldx     #TCTLJ
        bra     MD5
MD3     cmpa    #2
        bne     MD5
        lda     OPTSND
        asla
        ldx     #SNDTX
        ldx     a,x
MD5     lda     MCLR
        ldb     MYY
        lbsr    PRINTC
        inc     MROW
        lda     MROW
        cmpa    #4
        blo     MD1
        rts
ROWY    fcb     44,51,58,65
MTXT    fdb     TPLAY,0,0,TABOUT
* the sound choices in the order of the menu: DAC GMC SSC ORCH90 SIDX OFF (ids into SNDTX)
SNDTX   fdb     TSDAC,TSGMC,TSSSC,TSORC,TSSID,TSOFF
SNDLIST fcb     0,1,2,3,4,5
SNDCNT  equ     6

* MENUIN: read the keys and the stick, and act on a press (not on a key held)
MENUIN  clrb
        ldx     #MKEYS
MI1     lda     ,x+             ; column strobe (0 = end)
        beq     MI6
        sta     $FF02
        lda     $FF00
        anda    ,x+             ; the row's bit
        bne     MI2
        orb     ,x
MI2     leax    1,x
        bra     MI1
MKEYS   fcb     $F7,8,1,$EF,8,2,$DF,8,4,$BF,8,8,$7F,8,16,$FE,$40,16,0
MI6     lda     #$FF
        sta     $FF02
        lda     $FF00
        bita    #1              ; the right fire button
        bne     MI7
        orb     #16
MI7     tst     OPTCTL
        beq     MI8
        pshs    b
        lbsr    JOYDIR          ; B = the stick's directions (bit 0 up, 1 down, 2 left, 3 right)
        orb     ,s+
MI8     stb     MCUR
        lda     MPREV
        coma
        anda    MCUR            ; the newly pressed
        ldb     MCUR
        stb     MPREV
        tsta
        bne     MI9
        rts
MI9     tfr     a,b
        bitb    #1
        beq     MJ1
        lda     MSEL
        deca
        anda    #3
        sta     MSEL
        lbra    MJX
MJ1     bitb    #2
        beq     MJ2
        lda     MSEL
        inca
        anda    #3
        sta     MSEL
        bra     MJX
MJ2     pshs    b
        lda     MSEL
        beq     MJ4             ; PLAY: left and right pick the level
        cmpa    #1
        beq     MJ6
        cmpa    #2
        beq     MJ7
        puls    b               ; ABOUT: only a press
        bitb    #16
        beq     MJX
        lbra    ABOUT
MJ4     puls    b
        bitb    #16
        beq     MJ5
        inc     MGO             ; PLAY
        rts
MJ5     rts             ; PLAY: left and right do nothing
MJ6     puls    b              ; CONTROL: any of left, right, press
        lda     OPTCTL
        eora    #1
        sta     OPTCTL
        clr     JSEEN
        bra     MJX
MJ7     puls    b              ; SOUND: left back, right and press forward
MJ7R    lda     SNDI
        bitb    #4
        bne     MJ7B
        inca
        cmpa    #SNDCNT
        blo     MJ7C
        clra
        bra     MJ7C
MJ7B    tsta
        bne     MJ7D
        lda     #SNDCNT
MJ7D    deca
MJ7C    sta     SNDI
        ldx     #SNDLIST
        lda     a,x
        sta     OPTSND
        tst     MPIOK           ; the GMC and the SID need a Multi-Pak: with the disk controller in the only
        bne     MJ7E            ; slot their registers are the drive latch (a write can halt the machine)
        cmpa    #1
        beq     MJ7R
        cmpa    #4
        beq     MJ7R
MJ7E    lbsr    SNDSET
MJX     lda     #9              ; the bounce for every move
        lbsr    SNDS
        lbsr    MENUDRAW
        rts

* SNDSET: OPTSND decides the engine's output (and whether there is sound at all). The engine's modes:
* 0 DAC, 1 Orchestra-90, 2 Games Master (Multi-Pak slot 2), 3 Speech/Sound (slot 1), 4 CoCoXSID (slot 3,
* a guess: the owner did not say). A chip's slot is selected for the whole game ($FF7F, restored by QUIT).
SNDSET  clr     HAVEAUD
        tst     ENGINE
        beq     SSX
        ldb     OPTSND
        cmpb    #5              ; OFF
        beq     SSX
        inc     HAVEAUD
        ldx     #EMODE
        lda     b,x             ; the engine's mode
        ldx     #SLOTV
        ldb     b,x             ; the $FF7F value: 255 = the one we found
        cmpb    #255
        bne     SS1
        ldb     SAVE7F
        bra     SS2
SS1     cmpb    #254            ; the CoCoXSID: SCS only, CTS stays
        bne     SS2
        ldb     SAVE7F
        andb    #$F0
        orb     #2
SS2     clr     MUXB
        cmpa    #2
        blo     SS3
        pshs    a
        lda     #8
        sta     MUXB            ; a chip's sound comes by the cartridge line: CB2 high
        puls    a
SS3     exg     a,b             ; A = the $FF7F value, B = the mode
        jsr     $8010           ; A_SETMODE
SSX     rts
EMODE   fcb     0,2,3,1,4
SLOTV   fcb     255,$11,$00,255,254

* ABOUT: the story in SG24, page by page (the engine's code): any key or fire turns the page
ABOUT   tst     ENGINE
        lbeq    MJX
        lda     LEVEL
        sta     STARTLV
        lda     COCO3
        jsr     $800D
        lbcs    QUIT
        lbra    NEWGAME

* JOYREAD: the right stick (the DAC and the comparator): A = how far over to the right (X) and B = how
* far down (Y), 0..63. A stick that is not there reads 0,0.
JOYDIR  clrb                    ; (directions)
        lbsr    JOYXY
        sta     TMP             ; X
        stb     TX              ; Y
        tst     JSEEN
        bne     JD1
        cmpa    #20             ; wait until the stick has been seen near the middle
        blo     JDZ
        cmpa    #44
        bhs     JDZ
        cmpb    #20
        blo     JDZ
        cmpb    #44
        bhs     JDZ
        inc     JSEEN
JDZ     clrb
        rts
JD1     clrb
        cmpa    #20
        bhs     JD2
        orb     #4              ; left
JD2     cmpa    #44
        blo     JD3
        orb     #8              ; right
JD3     lda     TX
        cmpa    #20
        bhs     JD4
        orb     #1              ; up
JD4     cmpa    #44
        blo     JD5
        orb     #2              ; down
JD5     rts

* JOYXY: A = X, B = Y of the right stick, by successive approximation with the 6-bit DAC
JOYXY   lda     $FF23           ; the speaker off while the DAC is the comparator's reference,
        sta     SV23            ; or every trial value is heard as a buzz at the frame rate
        anda    #$F7
        sta     $FF23
        lda     $FF01
        anda    #$F7            ; axis X (CA2 = 0) of the right stick (CB2 = 0)
        sta     $FF01
        lda     $FF03
        anda    #$F7
        sta     $FF03
        bsr     JOYAX
        pshs    a
        lda     $FF01
        ora     #8              ; axis Y
        sta     $FF01
        bsr     JOYAX
        tfr     a,b
        lda     $FF01
        anda    #$F7            ; back to the DAC (sound source)
        sta     $FF01
        lda     #$82
        sta     $FF20
        lda     SV23            ; the speaker back on
        sta     $FF23
        lda     $FF03           ; CB2 was cleared above: a sound chip needs it high
        ora     MUXB
        sta     $FF03
        puls    a
        rts
JOYAX   clr     TMP2
        lda     #32
        sta     SBIT
JA1     lda     TMP2
        ora     SBIT
        asla
        asla
        ora     #2              ; (bit 1: the RS-232 line idles high)
        sta     $FF20
        nop                     ; the comparator takes a moment (and a CoCo 3 more after a mux switch)
        nop
        nop
        nop
        tst     $FF00           ; bit 7: the stick is above the DAC
        bpl     JA2
        lda     TMP2
        ora     SBIT
        sta     TMP2
JA2     lsr     SBIT
        bne     JA1
        lda     TMP2
        rts

* TCODE: B = draw code for the tile type at Y (in TILES; BCOL 16..1 and BROW 15..1 say
* where it is): a wall line gets its join mask (R1 L2 U4 D8) from neighbouring walls,
* blocks and doors, as gen.py does. Keeps Y.
TCODE   lda     ,y
        ldx     #TDC
        ldb     a,x
        cmpb    #$FF
        bne     TCX
        clrb
        lda     BCOL
        cmpa    #1              ; column 15: nothing to the right
        beq     TC1
        lda     1,y
        bsr     ISW
        bcc     TC1
        orb     #1
TC1     lda     BCOL
        cmpa    #16             ; column 0
        beq     TC2
        lda     -1,y
        bsr     ISW
        bcc     TC2
        orb     #2
TC2     lda     BROW
        cmpa    #15             ; row 0
        beq     TC3
        lda     -16,y
        bsr     ISW
        bcc     TC3
        orb     #4
TC3     lda     BROW
        cmpa    #1              ; row 14
        beq     TCX
        lda     16,y
        bsr     ISW
        bcc     TCX
        orb     #8
TCX     rts
* ISW: C set when tile type A joins a wall line (wall, block, door)
ISW     cmpa    #1
        beq     ISY
        cmpa    #2
        beq     ISY
        cmpa    #5
        beq     ISY
        andcc   #$FE
        rts
ISY     orcc    #1
        rts
* tile type -> draw code ($FF: a wall line, joined by TCODE)
TDC     fcb     20,$FF,16,17,18,19

* BUILDBG: fill MAP and the background copy from this level's draw codes (gen.py): per
* tile, MAP gets the logic code and the background two bytes x six rows of pattern in the
* code's colour (0 in PCOLT = the level's wall colour). The HUD rows start black.
BUILDBG ldx     #BG
        ldd     #$8080
BB0     std     ,x++
        cmpx    #BG+192
        blo     BB0
        ldy     LVP
        ldy     ,y              ; the level's 240 tile types, two a byte
        ldx     #TILES
        ldb     #120
BU1     lda     ,y
        lsra
        lsra
        lsra
        lsra
        sta     ,x+
        lda     ,y+
        anda    #15
        sta     ,x+
        decb
        bne     BU1
        ldy     #TILES
        ldu     #MAP
        ldx     #BG+192
        stx     SCRP
        lda     #15
        sta     BROW
BB1     lda     #16
        sta     BCOL
BB2     lbsr    TCODE           ; B = draw code
        leay    1,y
        stb     TIDX
        ldx     #LOGIC
        lda     b,x
        sta     ,u+
        ldx     #PCOLT
        lda     b,x
        bne     BB3
        lda     WCOL
BB3     sta     GCOL
        lda     TIDX
        ldb     #12
        mul
        addd    #PATS
        pshs    u,y
        tfr     d,y
        ldx     SCRP
        ldb     #6
BB4     lda     ,y+
        ora     GCOL
        sta     ,x
        lda     ,y+
        ora     GCOL
        sta     1,x
        leax    32,x
        decb
        bne     BB4
        puls    u,y
        ldx     SCRP
        leax    2,x
        stx     SCRP
        dec     BCOL
        bne     BB2
        ldx     SCRP            ; 16 tiles took it 32 bytes on; the next tile row is 192
        leax    5*32,x
        stx     SCRP
        dec     BROW
        bne     BB1
        rts

* FILL3: clear both screens and the background copy ($0E00-$31FF) to black
FILL3   ldx     #BUF0
        ldd     #$8080
FL3     std     ,x++
        cmpx    #BG+3072
        blo     FL3
        rts

* COPY3K: copy 3072 bytes from U to X with the stack: PULU D,X,Y / PSHS D,X,Y
COPY3K  sts     SAVES
        leas    6,x             ; PSHS fills the 6 bytes below S
        lda     #64
        sta     CCOUNT
CK1     pulu    d,x,y
        pshs    d,x,y
        leas    12,s
        pulu    d,x,y
        pshs    d,x,y
        leas    12,s
        pulu    d,x,y
        pshs    d,x,y
        leas    12,s
        pulu    d,x,y
        pshs    d,x,y
        leas    12,s
        pulu    d,x,y
        pshs    d,x,y
        leas    12,s
        pulu    d,x,y
        pshs    d,x,y
        leas    12,s
        pulu    d,x,y
        pshs    d,x,y
        leas    12,s
        pulu    d,x,y
        pshs    d,x,y
        leas    12,s
        dec     CCOUNT
        bne     CK1
        lds     SAVES
        rts

RANDOM  lda     RND             ; 8-bit LFSR
        lsla
        bcc     RD1
        eora    #$1D
RD1     sta     RND
        rts

* ---------------------------------------------------------------- data
DX1     fcb     1,-1,0,0
DY1     fcb     0,0,-1,1
ORDER   fcb     2,1,3,0         ; arcade tie order: up, left, down, right
* scatter corners (x, y in tiles, outside the maze): red top right, pink top left,
* cyan bottom right, orange bottom left
SCAT    fcb     14,-3,1,-3,15,16,0,16
* scatter/chase phase lengths in frames, level 1; 0 = for good
MSCHED  fdb     420,1200,420,1200,300,1200,300,0

* tile row of an element row (row 0 of the maze is element rows 6-11), and y mod 6
YTILE
        fcb     $FF,$FF,$FF,$FF,$FF,$FF
        fcb     0,0,0,0,0,0,1,1,1,1,1,1,2,2,2,2,2,2,3,3,3,3,3,3
        fcb     4,4,4,4,4,4,5,5,5,5,5,5,6,6,6,6,6,6,7,7,7,7,7,7
        fcb     8,8,8,8,8,8,9,9,9,9,9,9,10,10,10,10,10,10,11,11,11,11,11,11
        fcb     12,12,12,12,12,12,13,13,13,13,13,13,14,14,14,14,14,14
YMOD
        fcb     0,1,2,3,4,5,0,1,2,3,4,5,0,1,2,3,4,5,0,1,2,3,4,5
        fcb     0,1,2,3,4,5,0,1,2,3,4,5,0,1,2,3,4,5,0,1,2,3,4,5
        fcb     0,1,2,3,4,5,0,1,2,3,4,5,0,1,2,3,4,5,0,1,2,3,4,5
        fcb     0,1,2,3,4,5,0,1,2,3,4,5,0,1,2,3,4,5,0,1,2,3,4,5

* title chase positions (element row 30 of the title, all heading left, ghosts behind)
TINIT   fcb     20,30,1,1,0,0,0,0,0,0
        fcb     30,30,1,1,0,0,0,0,0,0
        fcb     36,30,1,1,0,0,0,0,1,0
        fcb     42,30,1,1,0,0,0,0,2,0
        fcb     48,30,1,1,0,0,0,0,3,0
* start state: x, y, dir, want, acc, speed, mode, release, id, house. Positions are
* overwritten per level from its header (RESETPOS): the player, red above the house door,
* the other three inside the house.
EINIT   fcb     0,0,1,1,0,16,0,0,0,0            ; player
        fcb     0,0,1,1,0,15,0,0,0,0            ; red: out at once
        fcb     0,0,2,2,0,15,0,0,1,1            ; pink: leaves at once
        fcb     0,0,2,2,0,15,0,30,2,1           ; cyan: after 30 dots
        fcb     0,0,0,0,0,15,0,60,3,1           ; orange: after 60 dots

* level header offsets (LVTAB, LHSZ bytes a level)
H_DATA  equ     0
H_WCOL  equ     2
H_DOTS  equ     3
H_PX    equ     4
H_RX    equ     6
H_HY    equ     8
H_PKX   equ     9
H_CYX   equ     10
H_ORX   equ     11
H_EXITC equ     12              ; EXITC, EXITR
H_EXITY equ     14
H_HOMEC equ     15              ; HOMEC, HOMER
H_HOMEX equ     17              ; HOMEX, HOMEY
H_HOMED equ     19              ; -> the eyes' way-home map, 60 bytes

WHITEC  equ     $C0             ; colour 4 (buff) | graphics bit
YELLOWC equ     $90
REDC    equ     $B0
CYANC   equ     $D0
DOORC   equ     $E0             ; colour 6 (magenta), as gen.py draws the door
FLFR    equ     4               ; death flash: frames a colour

        ifdef   OVR
* OVRCHK (test build only, lwasm -DOVR=1): count frames whose work ran past the next field
* sync (the sync flag is already set on arrival), and tabulate them by what the frame did:
* signature = ghost decisions (0-3) | HUD redraws (0-3) << 2 | ghost eaten << 4 | pill << 5
* | scatter/chase switch << 6. OVRT[sig] = frames, OVRX[sig] = long frames (16 bits each).
* The first frame after READY! / the tune is not counted: the flag has been set for a while.
OVRCHK  tst     OVRG
        beq     FRO1
        clr     OVRG
        lda     $FF02
        bra     FRO9
FRO1    lda     ECHO
        cmpa    #3
        bls     FS1
        lda     #3
FS1     sta     OSIG
        lda     EHUD
        cmpa    #3
        bls     FS2
        lda     #3
FS2     asla
        asla
        ora     OSIG
        sta     OSIG
        tst     EGUL
        beq     FS3
        lda     OSIG
        ora     #16
        sta     OSIG
FS3     tst     ESCA
        beq     FS4
        lda     OSIG
        ora     #32
        sta     OSIG
FS4     tst     EMOD
        beq     FS5
        lda     OSIG
        ora     #64
        sta     OSIG
FS5     ldx     #OVRT
        ldb     OSIG
        aslb
        abx
        ldd     ,x
        addd    #1
        std     ,x
        ldd     TOTF
        addd    #1
        std     TOTF
        tst     $FF03
        bpl     FRO9
        ldd     OVRN
        addd    #1
        std     OVRN
        ldx     #OVRX
        ldb     OSIG
        aslb
        abx
        ldd     ,x
        addd    #1
        std     ,x
FRO9    clr     ECHO
        clr     EHUD
        clr     EGUL
        clr     ESCA
        clr     EMOD
        rts
        endc

        include "tables.inc"
        include "drawspr.inc"

* ---------------------------------------------------------------- variables
SAVES0  rmb     2
SAVES   rmb     2
BACK    rmb     2
SAVP    rmb     2
SAV0    rmb     2*NENT
SAV1    rmb     2*NENT
VALID0  rmb     1
VALID1  rmb     1
REDRAW  rmb     1
ENTS    rmb     NENT*ESIZE
MAP     rmb     240
DOTS    rmb     1
SCORE   rmb     3
OLDS    rmb     3               ; the score before the last ADDSCORE (must follow SCORE: HUDS uses 3,y)
HDIF    rmb     1
LIVES   rmb     1
GSPD    rmb     1
STATE   rmb     1
FRIGHT  rmb     2
FRTIME  rmb     2
        ifdef   OVR
OVRN    rmb     2               ; frames that ran long
TOTF    rmb     2               ; frames counted
OVRG    rmb     1               ; 1 = skip the next frame (it follows a wait)
OSIG    rmb     1
ECHO    rmb     1               ; this frame: ghost decisions, HUD redraws, ghost eaten, pill, mode switch
EHUD    rmb     1
EGUL    rmb     1
ESCA    rmb     1
EMOD    rmb     1
OVRT    rmb     256
OVRX    rmb     256
        endc
COCO3   rmb     1
FASTF   rmb     1               ; CoCo 3 only: 1 = it was at high speed (put back by QUIT)
PALSAV  rmb     8               ; CoCo 3: BASIC's palette registers 0-7, put back by QUIT
FRAMES  rmb     1
GCOUNT  rmb     1
CCOUNT  rmb     1
RND     rmb     1
TMP     rmb     1
TX      rmb     1
TY      rmb     1
TRY     rmb     1
GMODE   rmb     1
MTIDX   rmb     1
MTIME   rmb     2
DOTSEATEN rmb   1
IDLEDOT rmb     1
ELROY   rmb     1
PX      rmb     1
PY      rmb     1
AHX     rmb     1
CHN     rmb     1
BEST    rmb     1
BESTD   rmb     2
GCOL    rmb     1
MCOL    rmb     1
MCOLB   rmb     1
MPTR    rmb     2
NROW    rmb     1
WAKAT   rmb     1
HAVEAUD rmb     1               ; 1 = sound on: the audio engine is there and SOUND is not OFF
ENGINE  rmb     1               ; 1 = the audio engine is in the upper 32K
MROW    rmb     1
MYY     rmb     1
MCLR    rmb     1
MCLR0   rmb     1
MSEL    rmb     1               ; the menu row picked
MPREV   rmb     1
MCUR    rmb     1
MGO     rmb     1
OPTCTL  rmb     1               ; 0 keyboard, 1 joystick
OPTSND  rmb     1               ; the sound: id in SNDTX
SNDI    rmb     1               ; ...and its place in SNDLIST
JSEEN   rmb     1
TMP2    rmb     1
SBIT    rmb     1
SV23    rmb     1
MPIOK   rmb     1               ; 1 = a Multi-Pak answers at $FF7F
MUXB    rmb     1               ; 8 when a sound chip is the sound
SAVE7F  rmb     1
CURAMB  rmb     1               ; the loop now playing under the game
DOTST   rmb     1               ; dots in this maze
DOTSTEP rmb     1               ; a fifth of them
TPH     rmb     2
MSGSAVE rmb     6*32
MOFF    rmb     2
ROFF    rmb     2
HCNT    rmb     1
ADDM    rmb     1
ADDL    rmb     1
LEVEL   rmb     1
STARTLV rmb     1
LVP     rmb     2
WCOL    rmb     1
EXITC   rmb     1
EXITR   rmb     1
EXITY   rmb     1
HOMEC   rmb     1
HOMER   rmb     1
HOMEX   rmb     1
HOMEY   rmb     1
NCOL    rmb     1
DXY     rmb     1
SCRP    rmb     2
BROW    rmb     1
BCOL    rmb     1
TIDX    rmb     1
TILES   rmb     240
LAP     rmb     1
FLBUF   rmb     2
FLN     rmb     1
FLC     rmb     1
FLW     rmb     1
FLD     rmb     1
        ifdef   BOT
BFD     rmb     240
BQ      rmb     240
BSTART  rmb     1
BGN     rmb     1
BGT     rmb     1
BTMP    rmb     1
BDIR    rmb     1
BD      rmb     1
BN      rmb     1
BCUR    rmb     1
BQH     rmb     1
BQT     rmb     1
BROT    rmb     1
BSEED   rmb     1
        endc
ENDVARS

        if      LHSZ-21
        error   "level header size disagrees with gen.py"
        endc
        if      OLDS-SCORE-3
        error   "OLDS must follow SCORE: HUDS reads the old score as 3,y"
        endc
        ifdef   BOT
TESTB   set     1
        endc
        ifdef   OVR
TESTB   set     1
        endc
        ifdef   TESTB
        if      ENDVARS>$7C00           ; the test builds may use more; they never ship
        error   "test build runs into the stack area"
        endc
        else
        if      ENDVARS>$7400
        error   "program runs into the stack area"
        endc
        endc

        end     START
