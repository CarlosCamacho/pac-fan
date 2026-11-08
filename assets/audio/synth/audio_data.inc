; made by tools/mksynth.py from assets/audio/build_audio.py: do not edit

SND00    includebin "snd00.bin"
SND01    includebin "snd01.bin"
SND02    includebin "snd02.bin"
SND03    includebin "snd03.bin"
SND04    includebin "snd04.bin"
SND05    includebin "snd05.bin"
SND06    includebin "snd06.bin"
SND07    includebin "snd07.bin"
SND08    includebin "snd08.bin"
SND09    includebin "snd09.bin"
SND10    includebin "snd10.bin"
SND11    includebin "snd11.bin"
SND12    includebin "snd12.bin"
SND13    includebin "snd13.bin"
SND14    includebin "snd14.bin"
SND15    includebin "snd15.bin"
SND16    includebin "snd16.bin"

SNDDIR
        fdb     SND00,264          ;  0 start_music (block)
        fdb     SND01,645          ;  1 intermission_music (block)
        fdb     SND02,21          ;  2 coin_insert (block)
        fdb     SND03,176          ;  3 death (block)
        fdb     SND04,39          ;  4 eat_ghost (block)
        fdb     SND05,128          ;  5 extra_life (sfx)
        fdb     SND06,10          ;  6 eat_dot_1 (sfx)
        fdb     SND07,10          ;  7 eat_dot_2 (sfx)
        fdb     SND08,32          ;  8 eat_fruit (sfx)
        fdb     SND09,18          ;  9 fruit_bounce (sfx)
        fdb     SND10,96          ; 10 siren_1 (loop)
        fdb     SND11,96          ; 11 siren_2 (loop)
        fdb     SND12,96          ; 12 siren_3 (loop)
        fdb     SND13,96          ; 13 siren_4 (loop)
        fdb     SND14,96          ; 14 siren_5 (loop)
        fdb     SND15,96          ; 15 power_pellet_fright (loop)
        fdb     SND16,96          ; 16 ghost_eyes_return (loop)
