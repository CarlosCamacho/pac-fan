#!/usr/bin/env python3
"""Code map for xroar-dev's -protect-mode, from the assembler listing.

    python3 tools/mksym.py dist/pakfan.lst dist/pakfan.sym OUT.gsym [BASE]

Bytes emitted by instructions are code, bytes emitted by fcb/fdb/fcc tables are initialized
data (`rmb` emits nothing, so variables, buffers and the stack stay unclassified). BASE is
added to every address to make it physical: 0 for a CoCo 1/2 (the default), 0x70000 for a
CoCo 3, where the MMU maps logical $0000-$FFFF there. Regenerate after every build: a stale
map reports false faults.
"""
import re
import sys

if len(sys.argv) < 4:
    sys.exit(__doc__)
lst, sym, out = sys.argv[1:4]
base = int(sys.argv[4], 0) if len(sys.argv) > 4 else 0

DATA = {'fcb', 'fdb', 'fcc', 'fcs', 'fqb', 'zmb', 'fill', 'rmb', 'fcr', 'includebin'}
code, data = [], []
cur = None                                   # (kind, next address) for continuation lines
for line in open(lst):
    line = line.rstrip('\n')
    m = re.match(r'^([0-9A-F]{4}) ([0-9A-F]+)\s+\(\s*\S+\):\d+(.*)$', line)
    if m:
        addr, hexb, rest = int(m.group(1), 16), m.group(2), m.group(3)
        src = rest[9:] if len(rest) > 9 else ''
        toks = src.split()
        if not toks:
            cur = None
            continue
        mnem = (toks[1] if not src[:1].isspace() and len(toks) > 1 else toks[0]).lower()
        kind = 'D' if mnem in DATA else 'C'
        n = len(hexb) // 2
        (data if kind == 'D' else code).append((addr, addr + n - 1))
        cur = (kind, addr + n)
        continue
    m = re.match(r'^\s+([0-9A-F]+)\s*$', line)           # more bytes of the line above
    if m and cur:
        n = len(m.group(1)) // 2
        (data if cur[0] == 'D' else code).append((cur[1], cur[1] + n - 1))
        cur = (cur[0], cur[1] + n)
    else:
        cur = None


def merge(rs):
    rs = sorted(rs)
    out = []
    for lo, hi in rs:
        if out and lo <= out[-1][1] + 1:
            out[-1][1] = max(out[-1][1], hi)
        else:
            out.append([lo, hi])
    return out


with open(out, 'w') as f:
    f.write('!gensym 2\n')
    for line in open(sym):
        p = line.split()
        if len(p) >= 3 and p[1] == 'EQU' and p[2].startswith('$'):
            v = int(p[2][1:], 16)
            f.write('S %s PAKFAN %04X %X\n' % (p[0], v & 0xFFFF, v + base))
    for lo, hi in merge(code):
        f.write('M C %X %X\n' % (lo + base, hi + base))
    for lo, hi in merge(data):
        f.write('M D %X %X\n' % (lo + base, hi + base))
print('%s: %d code ranges (%d bytes), %d data ranges (%d bytes)' % (
    out, len(merge(code)), sum(h - l + 1 for l, h in merge(code)), len(merge(data)), sum(h - l + 1 for l, h in merge(data))))
