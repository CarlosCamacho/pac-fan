#!/usr/bin/env python3
"""The story for the ABOUT page: assets/about/story.txt -> the engine's font and pages.

    python3 tools/mkabout.py

Writes assets/audio/synth/about_font.bin and about_pages.bin (audio.asm includes them).
The story is plain text, paragraphs separated by a blank line; it is put in capitals,
wrapped to 16 letters a line (the SG24 screen holds 16 glyphs of 4 cells across) and cut
into pages of 14 lines. Letters the 3x5 font lacks (font3x5.py) become spaces.

Font file: 64 glyphs for ASCII 32..95, 10 bytes each: five rows of two bytes. A byte is the
cell pair as a CoCo reads it, $0A = left cell, $05 = right cell (both halves of the byte), to be
or-ed with $80 and the colour << 4; the engine writes each row on two scanlines.
Pages file: the number of pages, then 14 lines of 16 characters (ASCII) a page.
"""
import os
import sys
import textwrap

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from font3x5 import FONT

OUT = os.path.join(ROOT, 'assets', 'audio', 'synth')
COLS, LINES = 16, 14


def glyph_bytes(ch):
    g = FONT.get(ch, FONT[' '])
    out = bytearray()
    for y in range(5):
        row = g[y] + '.'
        out.append((0x0A if row[0] == 'X' else 0) | (0x05 if row[1] == 'X' else 0))
        out.append((0x0A if row[2] == 'X' else 0) | (0x05 if row[3] == 'X' else 0))
    return bytes(out)


def main():
    os.makedirs(OUT, exist_ok=True)
    font = b''.join(glyph_bytes(chr(c)) for c in range(32, 96))
    open(os.path.join(OUT, 'about_font.bin'), 'wb').write(font)
    text = open(os.path.join(ROOT, 'assets', 'about', 'story.txt'), encoding='utf-8').read().upper()
    text = text.replace('’', "'").replace('‘', "'").replace('“', '"').replace('”', '"').replace('—', '-').replace('–', '-')
    lines = []
    for para in [p.strip() for p in text.replace('\r', '').split('\n\n') if p.strip()]:
        para = ' '.join(para.split())
        lines += textwrap.wrap(''.join(c if c in FONT else ' ' for c in para), COLS) + ['']
    while lines and not lines[-1]:
        lines.pop()
    pages = [lines[i:i + LINES] for i in range(0, len(lines), LINES)] or [['']]
    if len(pages) > 99:
        sys.exit('too many pages (%d)' % len(pages))
    data = bytearray([len(pages)])
    for p in pages:
        p = p + [''] * (LINES - len(p))
        data += b''.join(l.ljust(COLS).encode('ascii') for l in p)
    open(os.path.join(OUT, 'about_pages.bin'), 'wb').write(bytes(data))
    print('story: %d lines, %d pages, %d bytes (font %d)' % (len(lines), len(pages), len(data), len(font)))


if __name__ == '__main__':
    main()
