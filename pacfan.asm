* PAC-FAN -- a maze-chase game in CoCo 1/2 Semigraphics 12 (64x96 elements, 8 colours)
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
* with SGTEST; tried in XRoar and xroar-dev, not on hardware). Load: LOADM"PACFAN":EXEC
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
        ldd     $FFFE
        cmpd    #$8C1B
        bne     ST3
        inc     COCO3
        lda     #9
        sta     $FF9C
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
* SG12: SAM V = 100, VDG semigraphics (mode bits 0)
        sta     $FFC5           ; V2 set
        sta     $FFC2           ; V1 clear
        sta     $FFC0           ; V0 clear
        lda     $FF22
        anda    #$07
        sta     $FF22
        lda     #$5A
        sta     RND
        clr     WAKAF
        clr     WAKAT
        clr     HISC
        clr     HISC+1
        clr     HISC+2
        clr     LEVEL
        clr     STARTLV

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
        lbsr    CHKBRK
        lbsr    TITLEKEYS       ; up/down: pick the starting level
        lbsr    TITLEANIM
        lbsr    RENDER
        lda     #$7F            ; SPACE: column 7, row 3
        sta     $FF02
        lda     $FF00
        bita    #$08
        bne     WSPACE
        lda     #$FF
        sta     $FF02
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
        ldx     #TUNE
        lbsr    SAWPLAY
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
FRAME   lbsr    WAITVS
        lbsr    FLIP
        inc     FRAMES
        lbsr    CHKBRK
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
LCLEAR  lbsr    PAUSE60         ; (label: test hook, level cleared)
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
        lbsr    DEATHSND
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
CHOOSE  lda     E_MODE,u        ; eyes: follow the level's way-home map (gen.py)
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
SCARE   ldd     FRTIME          ; this level's blue time (NEWLEVEL)
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
HUD     ldx     #0              ; offset: byte column 0, element row 0
        ldy     #SCORE
        lda     #3
        sta     HCNT
HU1     lda     ,y
        lsra
        lsra
        lsra
        lsra
        ldb     #WHITEC
        pshs    x,y
        lbsr    GLYPHAT
        puls    x,y
        leax    2,x
        lda     ,y+
        anda    #$0F
        ldb     #WHITEC
        pshs    x,y
        lbsr    GLYPHAT
        puls    x,y
        leax    2,x
        dec     HCNT
        bne     HU1
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
        lbra    HUD

* ---------------------------------------------------------------- sound (blocking, short)
WAKA    lda     #4              ; four frames of sound
        sta     WAKAF
        lda     #$FE
        sta     DACV
        com     WAKAT
        beq     WK1
        lda     #56             ; "wa": high to low
        ldb     #14
        bra     WK2
WK1     lda     #98             ; "ka": low to high
        ldb     #-14
WK2     sta     WAKAP
        stb     WAKAD
        rts
GULP    ldx     #60
        ldy     #30
        lbra    SWEEP
DEATHSND
        ldx     #30
        ldy     #120
        lbra    SWEEP
* SWEEP: Y half-periods, starting at X delay units, each one unit longer
SWEEP   lda     #$FE
        sta     DACV
SW1     lda     DACV
        sta     $FF20
        eora    #$FC            ; $FE <-> $02 (bit 1 stays high: RS-232 idle)
        sta     DACV
        tfr     x,d
SW2     subd    #1
        bne     SW2
        leax    1,x
        leay    -1,y
        bne     SW1
        lda     #$82
        sta     $FF20
        rts

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
        rts
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
        lda     #2              ; text screen at $0400, SAM V = 0
        lbsr    SETF
        sta     $FFC4
        sta     $FFC2
        sta     $FFC0
        lda     $FF22
        anda    #$07
        sta     $FF22
        tst     COCO3           ; CoCo 3: the GIME back to normal text
        beq     QT1
        lda     #15
        sta     $FF9C
QT1     andcc   #$AF
        rts

* ---------------------------------------------------------------- timing and screens
WAITVS  lda     $FF02           ; clear the field-sync flag, wait for the next (bounded)
        tst     WAKAF
        bne     WVS
        ldx     #0
WV1     tst     $FF03
        bmi     WV2
        leax    -1,x
        bne     WV1
WV2     lda     $FF02
        rts
* WVS: the eat sound, played in the time the frame would spend waiting anyway, so it
* can never make a frame late. A square wave at WAKAP delay units a half-cycle (12
* cycles a unit), polling the field-sync flag inside the delay; the pitch steps by
* WAKAD each frame: falling for "wa", rising for "ka".
WVS     lda     DACV
        eora    #$FC            ; $FE <-> $02 (bit 1 stays high: RS-232 idle)
        sta     DACV
        sta     $FF20
        ldb     WAKAP
WVS1    tst     $FF03           ; 7
        bmi     WVS2            ; 3
        decb                    ; 2
        bne     WVS1            ; 3 -> 15 cycles a unit
        bra     WVS
WVS2    lda     $FF02
        lda     #$82
        sta     $FF20
        ldb     WAKAP
        addb    WAKAD
        stb     WAKAP
        dec     WAKAF
        rts

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
        ldx     #TCAMCO
        lda     #YELLOWC
        ldb     #2
        lbsr    PRINTC
        ldx     #TPRES
        lda     #WHITEC
        ldb     #9
        lbsr    PRINTC
        ldx     #TTITLE
        lda     #YELLOWC
        ldb     #19
        lbsr    PRINTC
        ldx     #TPROG
        lda     #WHITEC
        ldb     #44
        lbsr    PRINTC
        ldx     #TNAME1
        lda     #CYANC
        ldb     #52
        lbsr    PRINTC
        ldx     #TNAME2
        lda     #CYANC
        ldb     #59
        lbsr    PRINTC
        ldx     #TCOPY
        lda     #WHITEC
        ldb     #69
        lbsr    PRINTC
        ldx     #TSPACE
        lda     #YELLOWC
        ldb     #83
        lbsr    PRINTC
        ldx     #TLEVEL
        lda     #WHITEC
        ldb     #76
        lbsr    PRINTC
        clr     TKPREV
        lbra    SHOWLV

* TITLEKEYS: on the title, UP and DOWN step the starting level (one step a press)
TITLEKEYS
        clr     TK
        lda     #$F7            ; up: column 3, row 3
        sta     $FF02
        lda     $FF00
        bita    #$08
        bne     TK1
        lda     #1
        sta     TK
TK1     lda     #$EF            ; down: column 4, row 3
        sta     $FF02
        lda     $FF00
        bita    #$08
        bne     TK2
        lda     #2
        sta     TK
TK2     lda     #$FF
        sta     $FF02
        lda     TK
        cmpa    TKPREV
        beq     TKX
        sta     TKPREV
        cmpa    #1
        beq     TKUP
        cmpa    #2
        bne     TKX
        lda     LEVEL
        bne     TKD1
        lda     #NLEV
TKD1    deca
        sta     LEVEL
        bra     SHOWLV
TKUP    lda     LEVEL
        inca
        cmpa    #NLEV
        blo     TKU1
        clra
TKU1    sta     LEVEL
* SHOWLV: the two digits of "LEVEL nn" on the title
SHOWLV  lbsr    LVDIG
        pshs    b
        ldb     #WHITEC
        ldx     #76*32+20
        lbsr    GLYPHAT
        puls    a
        ldb     #WHITEC
        ldx     #76*32+22
        lbra    GLYPHAT
TKX     rts

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

* SAWPLAY: two sawtooth voices through the DAC. X -> records of (samples, step1, step2),
* ended by a count of 0. Each sample: add each step to its 16-bit phase, sum the two top bytes at
* half amplitude. The loop below is 79 cycles a sample (11,328 Hz); gen.py's SAMPCYC
* must match it. Blocking, interrupts already off.
SAWPLAY clr     PH1
        clr     PH1+1
        clr     PH2
        clr     PH2+1
SWN     ldy     ,x++            ; sample count; 0 ends the tune
        beq     SWX
        ldd     ,x++
        std     F1
        ldd     ,x++
        std     F2
        pshs    x
SL      ldd     PH1             ; 6
        addd    F1              ; 7
        std     PH1             ; 6
        sta     TA              ; 5
        ldd     PH2             ; 6
        addd    F2              ; 7
        std     PH2             ; 6
        lsra                    ; 2
        sta     TB              ; 5
        lda     TA              ; 5
        lsra                    ; 2
        adda    TB              ; 5
        anda    #$FC            ; 2
        ora     #$02            ; 2  (bit 1: RS-232 out idles high)
        sta     $FF20           ; 5
        leay    -1,y            ; 5
        bne     SL              ; 3  = 79
        puls    x
        bra     SWN
SWX     lda     #$82            ; rest the DAC mid-scale
        sta     $FF20
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
HISC    rmb     3
LIVES   rmb     1
GSPD    rmb     1
STATE   rmb     1
FRIGHT  rmb     2
FRTIME  rmb     2
COCO3   rmb     1
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
WAKAF   rmb     1
WAKAP   rmb     1
WAKAD   rmb     1
WAKAT   rmb     1
TPH     rmb     2
PH1     rmb     2
PH2     rmb     2
F1      rmb     2
F2      rmb     2
TA      rmb     1
TB      rmb     1
MSGSAVE rmb     6*32
MOFF    rmb     2
ROFF    rmb     2
HCNT    rmb     1
ADDM    rmb     1
ADDL    rmb     1
DACV    rmb     1
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
TK      rmb     1
TKPREV  rmb     1
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
        ifdef   BOT
        if      ENDVARS>$7800           ; the test build may use more; it never ships
        error   "bot build runs into the stack area"
        endc
        else
        if      ENDVARS>$7000
        error   "program runs into the stack area"
        endc
        endc

        end     START
