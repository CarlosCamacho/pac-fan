"""Where things sit on the loading screen (SG12: 32 bytes a row, 96 rows, 2 elements a byte).

Shared by tools/mklogo.py (draws the screen) and tools/mkpak.py (writes the BASIC loader that
fills the bar). One screen row of an SG12 byte is 2 scanlines; every byte here holds the same
pair of elements in its top and bottom half ($0A = left element, $05 = right element, $0F = both),
so it does not matter which half of a 6-row character the row falls in.
"""
SCREEN = 0x0E00          # BUF0: where the loading screen lives, and where PAKLOGO.BIN loads
ROWS, COLS = 96, 32
LOGO_ROWS = 30           # the logo is scaled to 64 elements wide by this many element rows
LOGO_ROW = 25            # its first row
BAR_TOP = 63             # top edge of the bar's frame; inner rows BAR_TOP+1..+5, bottom edge +6
BAR_C0, BAR_C1 = 5, 26   # frame bytes, inclusive (left edge = left element of C0, right edge = right of C1)
FILL_COL0, FILL_COLS = 6, 20     # progress fills these 20 bytes (40 elements), three rows tall
FILL_ROW0 = BAR_TOP + 2
FILL_ROWS = 3
# SG colour codes (byte bits 6-4)
GREEN, YELLOW, BLUE, RED, BUFF, CYAN, MAGENTA, ORANGE = range(8)
FRAME_COLOR, FILL_COLOR = BUFF, YELLOW
FILL_BYTE = 0x80 | (FILL_COLOR << 4) | 0x0F        # both elements of a byte, both halves


def fill_address(col, k):
    """Screen address of byte column `col` (0 = first fill column) in fill row k (0..FILL_ROWS-1)."""
    return SCREEN + (FILL_ROW0 + k) * COLS + FILL_COL0 + col
