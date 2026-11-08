#!/usr/bin/env python3
"""Make the loading screen from the logo art. Needs numpy and Pillow; the build does not (it
uses the file this writes).

    python3 tools/mklogo.py ART OUT.BIN [PREVIEW.PNG] [--save-art ART.PNG]

ART is either an SG24 Studio export (.asm: bytes `1 N2 N1 N0 P0 P1 x x`, two cells a byte) or the
art PNG this tool saves with --save-art (one cell is 4 pixels wide and 1 tall, in the eight SG
colours on black, so the PNG looks as it does on a CoCo). The logo is 216 cells wide, 3.4 times the
64 elements of one screen, so it is scaled down: for each SG12 element (4 x 2 pixels) the colour
covering most of its patch of the art wins, black outlines and all. Two elements of a byte must
share a colour (the other is off), so where a pair disagrees the stronger one is used for both.
The result is 3072 bytes (the SG12 screen at $0E00) with the progress bar's empty frame drawn in.
"""
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, __file__.rsplit('/', 1)[0] if '/' in __file__ else '.')
import logolayout as L

# art PNG colours: the eight SG colours at full strength, black = -1
ART_RGB = {-1: (0, 0, 0), 0: (0, 255, 0), 1: (255, 255, 0), 2: (0, 0, 255), 3: (255, 0, 0),
           4: (255, 255, 255), 5: (0, 255, 255), 6: (255, 0, 255), 7: (255, 128, 0)}
# what the emulator shows, for the preview
SHOW_RGB = {-1: (13, 13, 13), 0: (46, 188, 36), 1: (255, 255, 151), 2: (44, 37, 129), 3: (131, 26, 55),
            4: (255, 255, 255), 5: (46, 173, 115), 6: (255, 90, 255), 7: (255, 112, 59)}


def cells_from_asm(path):
    data, width = [], 185
    for line in open(path):
        if 'bytes per row' in line:                     # the Studio's header: "... 185 bytes per row"
            width = int(line.split('bytes per row')[0].split()[-1])
        s = line.split(';')[0].strip()
        if s.startswith('fcb'):
            data += [int(x.strip().lstrip('$'), 16) for x in s[3:].split(',') if x.strip()]
    n = len(data) // width
    cells = np.full((n, width * 2), -1, dtype=int)
    for r in range(n):
        for i in range(width):
            b = data[r * width + i]
            c = (b >> 4) & 7
            if b & 8:
                cells[r, 2 * i] = c
            if b & 4:
                cells[r, 2 * i + 1] = c
    return crop(cells)


def cells_from_png(path):
    im = np.asarray(Image.open(path).convert('RGB')).astype(int)
    im = im[:, 2::4]                              # one sample per cell (cells are 4 pixels wide)
    codes = list(ART_RGB)
    pal = np.array([ART_RGB[c] for c in codes])
    d = ((im[:, :, None, :] - pal[None, None, :, :]) ** 2).sum(axis=3)
    return crop(np.array(codes)[d.argmin(axis=2)])


def crop(cells):
    ys, xs = np.where(cells >= 0)
    return cells[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def save_art(cells, path):
    img = np.zeros(cells.shape + (3,), dtype=np.uint8)
    for c, rgb in ART_RGB.items():
        img[cells == c] = rgb
    Image.fromarray(img).resize((cells.shape[1] * 4, cells.shape[0]), Image.NEAREST).save(path, optimize=True)


def patch_weights(cells, y0, y1, x0, x1):
    h, w = cells.shape
    wt = {}
    for y in range(int(np.floor(y0)), min(int(np.ceil(y1)), h)):
        fy = min(y + 1, y1) - max(y, y0)
        for x in range(int(np.floor(x0)), min(int(np.ceil(x1)), w)):
            fx = min(x + 1, x1) - max(x, x0)
            c = int(cells[y, x])
            wt[c] = wt.get(c, 0) + fy * fx
    return wt


def scale(cells, rows):
    """The art as rows x 64 elements: colour code or -1 (off), two elements of a byte in agreement."""
    h, w = cells.shape
    best = [[None] * 64 for _ in range(rows)]
    for i in range(rows):
        for j in range(64):
            wt = patch_weights(cells, i * h / rows, (i + 1) * h / rows, j * w / 64, (j + 1) * w / 64)
            c = max(wt, key=wt.get)
            best[i][j] = (c, wt[c])
    out = np.full((rows, 64), -1, dtype=int)
    for i in range(rows):
        for k in range(32):
            (a, wa), (b, wb) = best[i][2 * k], best[i][2 * k + 1]
            if a == b:
                out[i, 2 * k] = out[i, 2 * k + 1] = a
            elif a == -1 or b == -1:                   # one element on, one off: the byte takes the colour of the one that is on
                out[i, 2 * k], out[i, 2 * k + 1] = a, b
            else:                                      # two different colours: the stronger takes both
                out[i, 2 * k] = out[i, 2 * k + 1] = a if wa >= wb else b
    return out


def put(screen, row, col, color, left=True, right=True):
    """Set byte (row, col): both halves show the same pair of elements."""
    pair = (0x0A if left else 0) | (0x05 if right else 0)
    screen[row * L.COLS + col] = 0x80 | (color << 4) | pair if pair else 0x80


def build_screen(logo):
    screen = bytearray([0x80]) * (L.ROWS * L.COLS)
    for i in range(logo.shape[0]):
        for k in range(32):
            a, b = logo[i, 2 * k], logo[i, 2 * k + 1]
            color = a if a >= 0 else b
            if color >= 0:
                put(screen, L.LOGO_ROW + i, k, color, a >= 0, b >= 0)
    top, bot = L.BAR_TOP, L.BAR_TOP + 6                       # the empty bar: a frame of one element
    for c in range(L.BAR_C0, L.BAR_C1 + 1):
        put(screen, top, c, L.FRAME_COLOR)
        put(screen, bot, c, L.FRAME_COLOR)
    for r in range(top + 1, bot):
        put(screen, r, L.BAR_C0, L.FRAME_COLOR, True, False)
        put(screen, r, L.BAR_C1, L.FRAME_COLOR, False, True)
    return bytes(screen)


def render(screen, scale_px=2, fill=0):
    """What the CoCo shows (and, with fill > 0, the bar that far along), as an image."""
    scr = bytearray(screen)
    for col in range(fill):
        for k in range(L.FILL_ROWS):
            scr[(L.FILL_ROW0 + k) * L.COLS + L.FILL_COL0 + col] = L.FILL_BYTE
    img = np.zeros((L.ROWS * 2, 256, 3), dtype=np.uint8)
    for r in range(L.ROWS):
        for c in range(L.COLS):
            b = scr[r * L.COLS + c]
            col = (b >> 4) & 7
            for e, bit in ((0, 0x08), (1, 0x04)):
                rgb = SHOW_RGB[col] if b & bit else SHOW_RGB[-1]
                img[r * 2:r * 2 + 2, c * 8 + e * 4:c * 8 + e * 4 + 4] = rgb
    return Image.fromarray(img).resize((256 * scale_px, 192 * scale_px), Image.NEAREST)


def main(argv):
    args = [a for a in argv[1:] if not a.startswith('--')]
    save = argv[argv.index('--save-art') + 1] if '--save-art' in argv else None
    if save:
        args.remove(save)
    if len(args) < 2:
        sys.exit(__doc__)
    src, out = args[0], args[1]
    cells = cells_from_asm(src) if src.endswith('.asm') else cells_from_png(src)
    if save:
        save_art(cells, save)
    screen = build_screen(scale(cells, L.LOGO_ROWS))
    open(out, 'wb').write(screen)
    print('logo art %d x %d cells -> %d rows x 64 elements; %s: %d bytes' % (cells.shape[1], cells.shape[0], L.LOGO_ROWS, out, len(screen)))
    if len(args) > 2:
        render(screen, 2, fill=10).save(args[2])


if __name__ == '__main__':
    main(sys.argv)
