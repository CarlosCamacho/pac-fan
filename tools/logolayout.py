"""Where things sit on the loading screen (SG24: 32 bytes a row, 192 rows, 2 cells a byte).

Shared by tools/mklogo.py (draws the screen) and tools/mkpak.py (writes the BASIC loader that
fills the bar). A byte is 1 CCC L R L R: two cells 4 pixels wide and one scanline tall, one colour. A CoCo 1/2 reads
bits 3-2 on the upper 6 scanlines of its 12-line character row and bits 1-0 on the lower 6, so both carry
the same pair (the Studio's export leaves bits 1-0 clear, which shows as black stripes on a CoCo 1/2).
"""
SCREEN = 0x0E00          # where the loading screen lives, and where PAKLOGO.BIN loads (6144 bytes: to $25FF)
ROWS, COLS = 192, 32
LOGO_ROW = 24            # first row of the logo (the art is 64 cells wide and at most about 100 tall)
BAR_TOP = 120            # frame: 2 scanlines top and bottom, one cell at each side
BAR_ROWS = 10            # fill rows between the frame's top and bottom edges
BAR_C0, BAR_C1 = 5, 26   # frame bytes, inclusive (left edge = left cell of C0, right edge = right cell of C1)
FILL_COL0, FILL_COLS = 6, 20     # progress fills these 20 bytes (40 cells)
FILL_ROW0 = BAR_TOP + 2
FILL_ROWS = BAR_ROWS
# SG colour codes (byte bits 6-4)
GREEN, YELLOW, BLUE, RED, BUFF, CYAN, MAGENTA, ORANGE = range(8)
FRAME_COLOR, FILL_COLOR = BUFF, YELLOW
FILL_BYTE = 0x80 | (FILL_COLOR << 4) | 0x0F        # both cells (bits 3-2), repeated in bits 1-0


def fill_address(col, k):
    """Screen address of byte column `col` (0 = first fill column) in fill row k (0..FILL_ROWS-1)."""
    return SCREEN + (FILL_ROW0 + k) * COLS + FILL_COL0 + col
