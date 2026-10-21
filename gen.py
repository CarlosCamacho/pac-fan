#!/usr/bin/env python3
"""Generate tables.inc for PAC-FAN (SG12 maze chase).  python3 gen.py

SG12: 64x96 elements, 32 bytes a row, each byte two elements (left $0A, right $05,
both pairs written) and one colour: $80 | colour<<4 | bits.
The maze is 16x15 tiles of 4x6 elements under a one-tile HUD; sprites are one tile.
"""
import json, os, sys
LEVELS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "levels", "pacfan-project.json")
GREEN, YELLOW, BLUE, RED, BUFF, CYAN, MAGENTA, ORANGE = range(8)
TW, TH = 4, 6
W, H = 16, 15

# ---- levels: read from the maze editor's project file (read only, never written)
proj = json.load(open(LEVELS))
assert proj.get("format") == "pacfan-project", "not a pacfan-project file"
levels = proj["levels"]
assert 1 <= len(levels) <= 99

# draw codes: 0-15 joined wall by neighbour mask (R1 L2 U4 D8), 16 solid block, 17 dot,
# 18 power pill, 19 house door, 20 empty (house, tunnel, space)
D_SOLID, D_DOT, D_PILL, D_DOOR, D_EMPTY = 16, 17, 18, 19, 20
def cells_for(code):
    if code < 16:
        cells = {(1, 2), (2, 2), (1, 3), (2, 3)}
        if code & 1: cells |= {(3, 2), (3, 3)}
        if code & 2: cells |= {(0, 2), (0, 3)}
        if code & 4: cells |= {(1, 0), (2, 0), (1, 1), (2, 1)}
        if code & 8: cells |= {(1, 4), (2, 4), (1, 5), (2, 5)}
        return cells
    if code == D_SOLID: return {(x, y) for x in range(4) for y in range(6)}
    if code == D_DOT: return {(1, 3), (2, 3)}
    if code == D_PILL: return {(x, y) for x in (1, 2) for y in (1, 2, 3, 4)}
    if code == D_DOOR: return {(x, 3) for x in range(4)}
    return set()
pats = bytearray()
for code in range(21):
    cells = cells_for(code)
    for y in range(6):
        for bx in (0, 2):
            pats.append((0x0A if (bx, y) in cells else 0) | (0x05 if (bx + 1, y) in cells else 0))
# logic map: 0 open, 1 wall, 2 dot, 3 pill, 4 door (ghosts only)
LOGIC = [1] * 17 + [2, 3, 4, 0]
# colour of each draw code: 0 = the level's wall colour
PCOL = [0] * 17 + [0x80 | BUFF << 4, 0x80 | BUFF << 4, 0x80 | MAGENTA << 4, 0x80]

def solidish(rows, c, r):
    return 0 <= r < H and 0 <= c < W and rows[r][c] in "#BD"
def blocks(ch):
    return ch in "#BD"

lvdata, headers, report, homes, drawcodes = [], [], [], [], []
for li, lv in enumerate(levels):
    name = lv.get("name", "Level %d" % (li + 1))
    rows = [r.ljust(W)[:W] for r in lv["rows"]]
    assert lv["w"] == W and lv["h"] == H and len(rows) == H, "%s: must be 16x15 (SG12 holds no more)" % name
    notes = []
    if any(ch != "-" for row in lv.get("colors", []) for ch in row):
        notes.append("per-wall colours ignored (one wall colour a level)")
    house = sorted((c, r) for r in range(H) for c in range(W) if rows[r][c] == "H")
    doors = sorted((c, r) for r in range(H) for c in range(W) if rows[r][c] == "D")
    assert house, "%s: no ghost house" % name
    hy = house[0][1]
    hx = min(c for c, r in house if r == hy)
    hcols = [c for c, r in house if r == hy]
    above = [(c, r) for c, r in doors if r == hy - 1 and c in hcols]
    assert above, "%s: the engine wants the house door directly above the house" % name
    dc = min(c for c, r in above)
    er = hy - 2
    assert rows[er][dc] not in "#BDH", "%s: the tile above the door must be open" % name
    two = (dc + 1, hy - 1) in doors and rows[er][dc + 1] not in "#BDH"
    ps = [(c, r) for r in range(H) for c in range(W) if rows[r][c] == "P"]
    if ps:
        pc, pr = ps[0]
    else:                                   # no 'P': the open tile nearest bottom-middle
        cand = [(abs(c - 7.5) + 2 * abs(r - 13), c, r) for r in range(H) for c in range(1, W - 1)
                if rows[r][c] in ". o"]
        _, pc, pr = min(cand)
    assert not blocks(rows[pr][pc]) and rows[pr][pc] != "H", "%s: player start (%d,%d) is a wall" % (name, pc, pr)
    # reachability for the player: both axes wrap (tunnels); doors and walls block
    seen, todo = {(pc, pr)}, [(pc, pr)]
    while todo:
        c, r = todo.pop()
        for dc_, dr_ in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = ((c + dc_) % W, (r + dr_) % H)
            if not blocks(rows[n[1]][n[0]]) and rows[n[1]][n[0]] != "H" and n not in seen:
                seen.add(n); todo.append(n)
    rows = [list(r) for r in rows]
    lost = [(c, r) for r in range(H) for c in range(W) if rows[r][c] in ".o" and (c, r) not in seen]
    for c, r in lost:
        rows[r][c] = " "
    if (dc, er) not in seen:
        notes.append("WARNING: the ghosts' exit (%d,%d) is cut off from the player" % (dc, er))
    if lost:
        notes.append("%d unreachable dot(s) removed: %s" % (len(lost), lost))
    def nopen(c, r):
        return sum(1 for a, b in ((1,0),(-1,0),(0,1),(0,-1)) if not blocks(rows[(r+b) % H][(c+a) % W])
                   and rows[(r+b) % H][(c+a) % W] != "H")
    dead = sorted((c, r) for (c, r) in seen if nopen(c, r) < 2)
    if dead:
        notes.append("dead ends at %s (play fine; ghosts turn round there)" % dead)
    # stored as 4-bit tile types, two a byte (high nibble first): 0 open, 1 wall line,
    # 2 solid block, 3 dot, 4 pill, 5 door. The engine works out each wall line's joins at
    # level start (BUILDBG/TCODE); `data` below is the same result, kept for checking.
    TT = {"#": 1, "B": 2, ".": 3, "o": 4, "D": 5}
    types = [TT.get(rows[r][c], 0) for r in range(H) for c in range(W)]
    nib = bytearray((types[i] << 4) | types[i + 1] for i in range(0, 240, 2))
    data = bytearray()
    for r in range(H):
        for c in range(W):
            ch = rows[r][c]
            if ch == "#":
                m = (1 if solidish(rows, c + 1, r) else 0) | (2 if solidish(rows, c - 1, r) else 0) \
                    | (4 if solidish(rows, c, r - 1) else 0) | (8 if solidish(rows, c, r + 1) else 0)
                data.append(m)
            elif ch == "B": data.append(D_SOLID)
            elif ch == ".": data.append(D_DOT)
            elif ch == "o": data.append(D_PILL)
            elif ch == "D": data.append(D_DOOR)
            else: data.append(D_EMPTY)          # ' ', 'H', 'T', 'P'
    # eyes' way home: breadth-first from the house tile under the door, over every tile a
    # ghost may cross (the door included; both axes wrap), each tile storing the direction
    # (0 R, 1 L, 2 U, 3 D) of its neighbour one step nearer. Straight-line targeting looped
    # forever under a house walled off from below (level 2, found in a soak).
    home = (dc, hy)
    dist = {home: 0}; q = [home]
    for c, r in q:
        for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = ((c + a) % W, (r + b) % H)
            if rows[n[1]][n[0]] not in "#B" and n not in dist:
                dist[n] = dist[(c, r)] + 1; q.append(n)
    homed = []
    for r in range(H):
        for c in range(W):
            best = 2
            if (c, r) in dist and dist[(c, r)] > 0:
                for d, (a, b) in ((2, (0, -1)), (1, (-1, 0)), (3, (0, 1)), (0, (1, 0))):   # ties U L D R
                    n = ((c + a) % W, (r + b) % H)
                    if dist.get(n, 999) == dist[(c, r)] - 1:
                        best = d; break
            homed.append(best)
    packed = bytearray(sum(homed[i + k] << (2 * k) for k in range(4)) for i in range(0, 240, 4))
    ndots = sum(1 for v in data if v in (D_DOT, D_PILL))
    assert 0 < ndots < 256
    wc = int(lv.get("wallColor", BLUE)) & 7
    hdr = [0x80 | wc << 4, ndots,
           pc * 4, pr * 6 + 6,                                   # player
           dc * 4 + (2 if two else 0), er * 6 + 6,               # red, above the door
           hy * 6 + 6, hx * 4,                                   # house row; pink
           (hx + 1) * 4 if len(hcols) > 1 else hx * 4,           # cyan
           hx * 4 + 2 if len(hcols) > 1 else hx * 4,             # orange
           dc, er, er * 6 + 6,                                   # exit tile, its element row
           dc, hy, dc * 4, hy * 6 + 6]                           # home tile (eyes), elements
    assert rows[hy][dc] == "H", "%s: no house tile under the door" % name
    lvdata.append(nib); drawcodes.append(data); headers.append(hdr); homes.append(packed)
    report.append("%-10s colour %d  %3d dots  %s" % (name, wc, ndots, "; ".join(notes) or "ok"))

out = ["* generated by gen.py from levels/pacfan-project.json -- do not edit"]
def fcb(label, data):
    out.append(label)
    for i in range(0, len(data), 16):
        out.append("        fcb     " + ",".join("$%02X" % v for v in data[i:i + 16]))
out.append("NLEV    equ     %d" % len(levels))
out.append("LHSZ    equ     %d" % (4 + len(headers[0])))
out.append("* level header: data, wall colour, dots, player x y, red x y, house y, pink x,")
out.append("* cyan x, orange x, exit col row y, home col row x y")
out.append("LVTAB")
for i, h in enumerate(headers):
    out.append("        fdb     LV%02d" % i)
    out.append("        fcb     " + ",".join("$%02X" % v for v in h))
    out.append("        fdb     HD%02d" % i)
fcb("PATS", pats)
fcb("LOGIC", LOGIC)
fcb("PCOLT", PCOL)
for i, d in enumerate(lvdata):
    fcb("LV%02d" % i, d)
for i, d in enumerate(homes):
    fcb("HD%02d" % i, d)
for line in report:
    print(line)
# what the engine's BG must be, rows 6..95, for tools/checkbg.py (not used by the build)
import pickle
bgs = []
for li, d in enumerate(drawcodes):
    wcol = headers[li][0]
    bg = bytearray()
    for r in range(H):
        for y in range(6):
            for c in range(W):
                code = d[r * W + c]
                col = PCOL[code] or wcol
                bg += bytes((pats[code * 12 + y * 2] | col, pats[code * 12 + y * 2 + 1] | col))
    bgs.append(bytes(bg))
os.makedirs(os.path.join(os.path.dirname(os.path.abspath(__file__)), "dist"), exist_ok=True)
pickle.dump(bgs, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "dist", "expected_bg.pickle"), "wb"))

# ---- sprites: 4x6 elements -> two x-variants of 6 rows x 3 bytes, 18 AND then 18 OR
def sprite(rows, col):
    tab = bytearray()
    for xo in (0, 1):
        andb, orb = [], []
        for y in range(6):
            lit = [False] * 6
            for x in range(4):
                if rows[y][x] == "X":
                    lit[xo + x] = True
            for b in range(3):
                l, r = lit[2 * b], lit[2 * b + 1]
                if not (l or r):
                    andb.append(0xFF); orb.append(0x00)
                else:
                    keep = (0x0A if not l else 0) | (0x05 if not r else 0)
                    andb.append(0x80 | keep)
                    orb.append(0x80 | (col << 4) | (0x0A if l else 0) | (0x05 if r else 0))
        tab += bytes(andb + orb)
    assert len(tab) == 72
    return tab

def mirror_h(rows): return [r[::-1] for r in rows]
def mirror_v(rows): return rows[::-1]
PAC_R = [".XX.", "XXXX", "XX..", "XX..", "XXXX", ".XX."]
PAC_C = [".XX.", "XXXX", "XXXX", "XXXX", "XXXX", ".XX."]
PAC_U = ["X..X", "X..X", "XXXX", "XXXX", "XXXX", ".XX."]
pacs = {0: PAC_R, 1: mirror_h(PAC_R), 2: PAC_U, 3: mirror_v(PAC_U)}
GHOST = [".XX.", "XXXX", "X..X", "XXXX", "XXXX", "X..X"]
EYES = ["....", "....", "X..X", "X..X", "....", "...."]
spr = bytearray()
names = []
for d in range(4):                       # 0..3: pac open, by direction (R, L, U, D)
    spr += sprite(pacs[d], YELLOW); names.append("pac%d" % d)
spr += sprite(PAC_C, YELLOW); names.append("pacc")        # 4: closed
for col in (RED, MAGENTA, CYAN, ORANGE):                   # 5..8: ghosts
    spr += sprite(GHOST, col)
spr += sprite(GHOST, BLUE)                                 # 9: frightened
spr += sprite(GHOST, BUFF)                                 # 10: frightened, flashing
spr += sprite(EYES, BUFF)                                  # 11: eaten
fcb("SPRTAB", spr)
for i, n in enumerate(names):
    pass
out.append("SPRSZ   equ     72")

# ---- font: 3x5 glyphs in 4-element cells -> 5 rows x 2 bytes of pair bits (no colour)
FONT = {
 "0": ["XXX", "X.X", "X.X", "X.X", "XXX"], "1": [".X.", "XX.", ".X.", ".X.", "XXX"],
 "2": ["XXX", "..X", "XXX", "X..", "XXX"], "3": ["XXX", "..X", ".XX", "..X", "XXX"],
 "4": ["X.X", "X.X", "XXX", "..X", "..X"], "5": ["XXX", "X..", "XXX", "..X", "XXX"],
 "6": ["XXX", "X..", "XXX", "X.X", "XXX"], "7": ["XXX", "..X", ".X.", ".X.", ".X."],
 "8": ["XXX", "X.X", "XXX", "X.X", "XXX"], "9": ["XXX", "X.X", "XXX", "..X", "XXX"],
 "R": ["XX.", "X.X", "XX.", "X.X", "X.X"], "E": ["XXX", "X..", "XX.", "X..", "XXX"],
 "A": [".X.", "X.X", "XXX", "X.X", "X.X"], "D": ["XX.", "X.X", "X.X", "X.X", "XX."],
 "Y": ["X.X", "X.X", ".X.", ".X.", ".X."], "G": ["XXX", "X..", "X.X", "X.X", "XXX"],
 "M": ["X.X", "XXX", "XXX", "X.X", "X.X"], "O": ["XXX", "X.X", "X.X", "X.X", "XXX"],
 "V": ["X.X", "X.X", "X.X", "X.X", ".X."], "!": [".X.", ".X.", ".X.", "...", ".X."],
 " ": ["...", "...", "...", "...", "..."], "P": ["XX.", "X.X", "XX.", "X..", "X.."],
 "S": ["XXX", "X..", "XXX", "..X", "XXX"], "C": ["XXX", "X..", "X..", "X..", "XXX"],
 "B": ["XX.", "X.X", "XX.", "X.X", "XX."], "F": ["XXX", "X..", "XX.", "X..", "X.."],
 "H": ["X.X", "X.X", "XXX", "X.X", "X.X"], "I": ["XXX", ".X.", ".X.", ".X.", "XXX"],
 "J": ["..X", "..X", "..X", "X.X", "XXX"], "K": ["X.X", "X.X", "XX.", "X.X", "X.X"],
 "L": ["X..", "X..", "X..", "X..", "XXX"], "N": ["XX.", "X.X", "X.X", "X.X", "X.X"],
 "Q": ["XXX", "X.X", "X.X", "XXX", "..X"], "T": ["XXX", ".X.", ".X.", ".X.", ".X."],
 "U": ["X.X", "X.X", "X.X", "X.X", "XXX"], "W": ["X.X", "X.X", "XXX", "XXX", "X.X"],
 "X": ["X.X", "X.X", ".X.", "X.X", "X.X"], "Z": ["XXX", "..X", ".X.", "X..", "XXX"],
 ".": ["...", "...", "...", "...", ".X."], "(": ["..X", ".X.", ".X.", ".X.", "..X"],
 ")": ["X..", ".X.", ".X.", ".X.", "X.."], "-": ["...", "...", "XXX", "...", "..."],
}
order = "0123456789RADYGMOV! EPSCBFHIJKLNQTUWXZ.()-"
out.append("GL_L    equ     %d" % order.index("L"))
font = bytearray()
for ch in order:
    g = FONT[ch]
    for y in range(5):
        row = g[y] + "."
        font.append((0x0A if row[0] == "X" else 0) | (0x05 if row[1] == "X" else 0))
        font.append((0x0A if row[2] == "X" else 0) | (0x05 if row[3] == "X" else 0))
fcb("FONT", font)
def text(label, s):
    out.append(label)
    out.append("        fcb     " + ",".join(str(order.index(ch)) for ch in s) + ",$FF")
text("TREADY", "READY!")
text("TOVER", "GAME OVER")
text("TPRESS", "PRESS SPACE")
text("TBLANK", "           ")
text("TCAMCO", "CAMCO")
text("TPRES", "PRESENTS")
text("TTITLE", "PAC-FAN")
text("TSPACE", "PRESS SPACE")
text("TPROG", "PROGRAMMING BY")
text("TNAME1", "CARLOS A.")
text("TNAME2", "CAMACHO")
text("TCOPY", "(C) 2026 CAMCO")
text("TLEVEL", "LEVEL 01")

# ---- music: an original two-voice tune for the sawtooth engine (not from any game).
# The engine runs one sample every SAMPCYC cycles; each record is a sample count, then
# f1, f2 (phase steps). A count of 0 ends the tune.
SAMPCYC = 79                       # counted from the SAWPLAY loop in pacfan.asm
RATE = 894886 / SAMPCYC
def hz(n):
    if n is None: return 0
    names = {"C":0,"D":2,"E":4,"F":5,"G":7,"A":9,"B":11}
    semis = names[n[0]] + 12 * (int(n[1:]) + 1)
    return 440.0 * 2 ** ((semis - 69) / 12)
def step(n):
    return int(round(hz(n) * 65536 / RATE)) & 0xFFFF
E8 = 0.15
mel = "C5 E5 G5 C6 B5 G5 E5 G5 A5 F5 D5 F5 A5 C6 A5 F5 G5 E5 C5 E5 G5 B5 D6 B5 C6 G5 E5 G5 C6 - - -".split()
bas = "C3 C3 G2 C3 F2 F2 C3 F2 G2 G2 D3 G2 C3 G2 C3 -".split()
recs = []
for k in range(32):
    m = None if mel[k] == "-" else mel[k]
    b = bas[k // 2]; b = None if b == "-" else b
    n = int(round(E8 * RATE))
    gap = int(round(0.012 * RATE))           # a short gap so repeated notes articulate
    recs.append((step(m), step(b), n - gap)); recs.append((0, step(b), gap))
words = []
for f1, f2, n in recs:
    words += [n, f1, f2]          # sample count first: 0 ends the tune
words.append(0)
out.append("* original intro tune (samples, f1, f2), %d Hz sample rate" % RATE)
out.append("TUNE")
for i in range(0, len(words), 12):
    out.append("        fdb     " + ",".join("$%04X" % w for w in words[i:i+12]))
open("tables.inc", "w").write("\n".join(out) + "\n")
print("tables.inc: %d levels, %d sprite bytes, %d font bytes" % (len(levels), len(spr), len(font)))

# ---- unrolled draw and restore
d = ["* generated by gen.py -- do not edit",
     "* DRAWSPR: X -> top-left byte in the screen, Y -> 18 AND + 18 OR bytes",
     "DRAWSPR"]
for r in range(6):
    for b in range(3):
        i = r * 3 + b
        d += ["        lda     %d,x" % b, "        anda    %d,y" % i,
              "        ora     %d,y" % (18 + i), "        sta     %d,x" % b]
    if r < 5:
        d.append("        leax    32,x")
d.append("        rts")
d += ["* RESTORE: copy a 3x6-byte square from U (background) to X (screen)", "RESTORE"]
for r in range(6):
    d += ["        ldd     ,u", "        std     ,x", "        lda     2,u", "        sta     2,x"]
    if r < 5:
        d += ["        leax    32,x", "        leau    32,u"]
d.append("        rts")
open("drawspr.inc", "w").write("\n".join(d) + "\n")
