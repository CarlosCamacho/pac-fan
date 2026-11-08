* COPIER: puts the audio piece just loaded (LOADM of AUDnn.BIN) into the upper 32K, which a LOADM
* cannot reach: the SAM goes to all-RAM mode ($FFDF) while the bytes are copied, and back
* ($FFDE). Each file carries its own source, destination and length (the three words after the first branch). The loader EXECs this after each LOADM; it is loaded with the piece, before the game
* itself (which then takes the place of both).
        org     $7000
CP      bra     CP0
SRC     fdb     0               ; mkpak.py fills these three in, a file at a time
DST     fdb     0
LEN     fdb     0
CP0     pshs    cc
        orcc    #$50
        ldu     SRC
        ldx     DST
        ldy     LEN
        sta     $FFDF           ; all-RAM mode: the ROMs are gone, the upper 32K is RAM
CP1     lda     ,u+
        sta     ,x+
        leay    -1,y
        bne     CP1
        sta     $FFDE           ; ROM mode
        puls    cc,pc
        end     CP
