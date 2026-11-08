#!/usr/bin/env python3
"""Package PAK FAN for the disk: the game, and the loader that shows the logo while it loads.

    python3 tools/mkpak.py            (after lwasm has made dist/PAKFAN.BIN; build.sh runs it)

Writes into dist/ and builds dist/PAKFAN.DSK with:
    PAKFAN.BIN   the whole game, as before:      LOADM"PAKFAN":EXEC
    PAKFAN.BAS   the loader (plain-text BASIC):  RUN"PAKFAN"
    PAKLOGO.BIN  the loading screen, an SG24 screen (assets/pakfan-logo.bin) for $0E00
    PAK01..PAK10.BIN  the game in ten pieces, so the bar can move after each one

The loader shows the logo, then LOADMs the ten pieces, filling the bar two bytes after each, and
EXECs the game. It uses only BASIC's LOADM, so it works from a floppy, a CoCoSDC or DriveWire
alike. The logo is SG24; the game's own start-up switches to SG12.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.path.insert(0, ROOT)
import logolayout as L
import mkdsk

PIECES = 10                 # the game, in this many files
AUDIO_PIECE = 2000          # bytes of the audio engine and its data in each file
STAGE = 0x3200              # where an audio piece lands before copier.asm moves it up
DIST = os.path.join(ROOT, 'dist')


def parse_bin(data):
    """DECB binary -> ([(load address, bytes)], exec address)."""
    blocks, i = [], 0
    while i < len(data):
        if data[i] == 0:
            n, a = data[i + 1] * 256 + data[i + 2], data[i + 3] * 256 + data[i + 4]
            blocks.append((a, data[i + 5:i + 5 + n]))
            i += 5 + n
        elif data[i] == 0xFF:
            return blocks, data[i + 3] * 256 + data[i + 4]
        else:
            raise ValueError('not a DECB binary')
    raise ValueError('no exec trailer')


def make_bin(addr, payload, exec_addr):
    out = bytearray()
    for off in range(0, len(payload), 0xFFFF):
        part = payload[off:off + 0xFFFF]
        a = addr + off
        out += bytes([0, len(part) >> 8, len(part) & 255, a >> 8, a & 255]) + part
    return bytes(out + bytes([0xFF, 0, 0, exec_addr >> 8, exec_addr & 255]))


def loader(naudio):
    a0 = L.fill_address(0, 0)
    total = naudio + PIECES
    lines = [
        'CLS 0',
        # a layout other than the standard one (the program is not at $2601) would not survive the logo screen: load plainly
        'IF PEEK(25)<>38 OR PEEK(26)<>1 THEN LOADM"PAKFAN":EXEC',
        'LOADM"PAKLOGO"',
        'C3=(PEEK(65534)=140)',                              # a CoCo 3: its reset vector is $8C1B
        'IF C3 THEN GOSUB 1000',
        'POKE 65314,PEEK(65314) AND 7',                      # VDG: semigraphics, colour set 0
        'POKE 65477,0:POKE 65475,0:POKE 65472,0',            # SAM V = 110 (SG24)
        'POKE 65479,0:POKE 65481,0:POKE 65483,0:POKE 65484,0:POKE 65486,0:POKE 65488,0:POKE 65490,0',   # screen at $0E00
        'J=0',
        'FOR I=1 TO %d' % naudio,                            # the audio engine: each piece to the staging area, then up
        'LOADM"AUD"+RIGHT$(STR$(100+I),2):EXEC',
        'GOSUB 1400',
        'NEXT',
        'FOR I=1 TO %d' % PIECES,                            # the game
        'LOADM"PAK"+RIGHT$(STR$(100+I),2)',
        'GOSUB 1400',
        'NEXT',
        'FOR I=1 TO 300:NEXT',                               # a moment on the full bar
        'IF C3 THEN GOSUB 1300',
        'EXEC',
    ]
    nums = [10 * (i + 1) for i in range(len(lines))]
    text = ''.join('%d %s\r' % (n, l) for n, l in zip(nums, lines))
    # CoCo 3: BASIC's colours are kept, the game's are shown for the logo, BASIC's go back before EXEC
    # (the game saves and sets its own; the logo is cleared a frame later anyway)
    cmp_rgb = [(0x11, 0x10), (0x34, 0x3E), (0x0C, 0x0E), (0x07, 0x21), (0x3F, 0x3F), (0x1E, 0x11), (0x18, 0x2F), (0x15, 0x26)]
    sub = [
        'DIM O(7):FOR I=0 TO 7:O(I)=PEEK(65456+I) AND 63:NEXT',
        'POKE 65436,10',                                     # $FF9C = 10: SG24 on the GIME
        'FOR I=0 TO 7:READ A,B:IF O(1)=54 THEN A=B',         # BASIC is in PALETTE RGB: its register 1 is $36
        'POKE 65456+I,A:NEXT:RETURN',
        'DATA ' + ','.join('%d,%d' % p for p in cmp_rgb),
    ]
    text += ''.join('%d %s\r' % (1000 + 10 * i, l) for i, l in enumerate(sub))
    text += '1300 FOR I=0 TO 7:POKE 65456+I,O(I):NEXT:RETURN\r'
    # the bar: after file J of `total`, 20 columns * J / total of it are filled
    text += '1400 J=J+1:FOR C=INT(%d*(J-1)/%d) TO INT(%d*J/%d)-1:FOR R=0 TO %d:POKE %d+C+32*R,%d:NEXT R,C:RETURN\r' % (
        L.FILL_COLS, total, L.FILL_COLS, total, L.FILL_ROWS - 1, a0, L.FILL_BYTE)
    return text.encode('ascii')


def make_blocks(blocks, exec_addr):
    out = bytearray()
    for addr, payload in blocks:
        out += bytes([0, len(payload) >> 8, len(payload) & 255, addr >> 8, addr & 255]) + payload
    return bytes(out + bytes([0xFF, 0, 0, exec_addr >> 8, exec_addr & 255]))


def main():
    game = open(os.path.join(DIST, 'PAKFAN.BIN'), 'rb').read()
    blocks, exec_addr = parse_bin(game)
    assert len(blocks) == 1, 'the game is expected to be one block'
    addr, payload = blocks[0]
    audio_blocks, _ = parse_bin(open(os.path.join(DIST, 'AUDIO.BIN'), 'rb').read())
    assert len(audio_blocks) == 1, 'the audio engine is expected to be one block'
    aaddr, apayload = audio_blocks[0]
    cblocks, cexec = parse_bin(open(os.path.join(DIST, 'COPIER.BIN'), 'rb').read())
    assert len(cblocks) == 1
    naudio = -(-len(apayload) // AUDIO_PIECE)
    files = [('PAKFAN.BAS', loader(naudio)), ('PAKFAN.BIN', game),
             ('PAKLOGO.BIN', make_bin(L.SCREEN, open(os.path.join(ROOT, 'assets', 'pakfan-logo.bin'), 'rb').read(), exec_addr))]
    def copier(src, dst, n):
        code = bytearray(cblocks[0][1])
        code[2:8] = bytes([src >> 8, src & 255, dst >> 8, dst & 255, n >> 8, n & 255])
        return (cblocks[0][0], bytes(code))
    for i in range(naudio):
        part = apayload[i * AUDIO_PIECE:(i + 1) * AUDIO_PIECE]
        assert STAGE + len(part) < cblocks[0][0]
        files.append(('AUD%02d.BIN' % (i + 1), make_blocks([(STAGE, part), copier(STAGE, aaddr + i * AUDIO_PIECE, len(part))], cexec)))
    # test only: SAM map type to all-RAM and back, nothing else. xroar-dev's CoCo 3 runs BASIC about
    # 1.7 times faster after that, so tools/checks.sh speed does it before its first measurement too.
    files.append(('TOGGLE.BIN', make_bin(0x6E00, bytes([0x1A, 0x50, 0xB7, 0xFF, 0xDF, 0xB7, 0xFF, 0xDE, 0x1C, 0xAF, 0x39]), 0x6E00)))
    # test only: the whole engine in one file, so a test loads it in a moment (LOADM"TAUDIO":EXEC)
    assert 0x0E00 + len(apayload) < cblocks[0][0]
    files.append(('TAUDIO.BIN', make_blocks([(0x0E00, apayload), copier(0x0E00, aaddr, len(apayload))], cexec)))
    size = -(-len(payload) // PIECES)
    for i in range(PIECES):
        part = payload[i * size:(i + 1) * size]
        files.append(('PAK%02d.BIN' % (i + 1), make_bin(addr + i * size, part, exec_addr)))
    for name, data in files:
        open(os.path.join(DIST, name), 'wb').write(data)
    open(os.path.join(DIST, 'AUDIO.RAW'), 'wb').write(apayload)       # for the tests: -load-ram puts it in the upper 32K
    mkdsk.write_image(os.path.join(DIST, 'PAKFAN.DSK'), files)
    print('wrote dist/PAKFAN.DSK: %s' % ', '.join('%s %d' % (n, len(d)) for n, d in files[:3]) +
          ', %d audio pieces of about %d bytes, %d game pieces of about %d bytes' % (naudio, AUDIO_PIECE, PIECES, size))


if __name__ == '__main__':
    main()
