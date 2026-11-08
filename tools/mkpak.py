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

PIECES = 10
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


def loader():
    a0 = L.fill_address(0, 0)
    step = L.FILL_COLS // PIECES
    assert step * PIECES == L.FILL_COLS, 'the bar must divide evenly into the pieces'
    lines = [
        'CLS 0',
        # a layout other than the standard one (the program is not at $2601) would not survive the logo screen: load plainly
        'IF PEEK(25)<>38 OR PEEK(26)<>1 THEN LOADM"PAKFAN":EXEC',
        'LOADM"PAKLOGO"',
        'C3=(PEEK(65534)=140)',                              # a CoCo 3: its reset vector is $8C1B
        'IF C3 THEN GOSUB 200',
        'POKE 65314,PEEK(65314) AND 7',                      # VDG: semigraphics, colour set 0
        'POKE 65477,0:POKE 65475,0:POKE 65472,0',            # SAM V = 110 (SG24)
        'POKE 65479,0:POKE 65481,0:POKE 65483,0:POKE 65484,0:POKE 65486,0:POKE 65488,0:POKE 65490,0',   # screen at $0E00
        'P=0',
        'FOR I=1 TO %d' % PIECES,
        'LOADM"PAK"+RIGHT$(STR$(100+I),2)',
        'FOR C=P TO %d*I-1:FOR R=0 TO %d:POKE %d+C+32*R,%d:NEXT R,C' % (step, L.FILL_ROWS - 1, a0, L.FILL_BYTE),
        'P=%d*I:NEXT' % step,
        'FOR I=1 TO 300:NEXT',                               # a moment on the full bar
        'IF C3 THEN GOSUB 300',
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
    text += ''.join('%d %s\r' % (200 + 10 * i, l) for i, l in enumerate(sub))
    text += '300 FOR I=0 TO 7:POKE 65456+I,O(I):NEXT:RETURN\r'
    return text.encode('ascii')


def main():
    game = open(os.path.join(DIST, 'PAKFAN.BIN'), 'rb').read()
    blocks, exec_addr = parse_bin(game)
    assert len(blocks) == 1, 'the game is expected to be one block'
    addr, payload = blocks[0]
    files = [('PAKFAN.BAS', loader()), ('PAKFAN.BIN', game),
             ('PAKLOGO.BIN', make_bin(L.SCREEN, open(os.path.join(ROOT, 'assets', 'pakfan-logo.bin'), 'rb').read(), exec_addr))]
    size = -(-len(payload) // PIECES)
    for i in range(PIECES):
        part = payload[i * size:(i + 1) * size]
        files.append(('PAK%02d.BIN' % (i + 1), make_bin(addr + i * size, part, exec_addr)))
    for name, data in files:
        open(os.path.join(DIST, name), 'wb').write(data)
    mkdsk.write_image(os.path.join(DIST, 'PAKFAN.DSK'), files)
    print('wrote dist/PAKFAN.DSK: %s' % ', '.join('%s %d' % (n, len(d)) for n, d in files[:3]) + ', %d pieces of about %d bytes' % (PIECES, size))


if __name__ == '__main__':
    main()
