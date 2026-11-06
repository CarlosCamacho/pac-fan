#!/usr/bin/env python3
"""Prove an edit left the gameplay alone: compare two runs of tools/botgames.sh game by game.

The autopilot plays deterministically, so an edit that does not touch gameplay (sound, BREAK,
drawing speed, the CoCo 3 path...) must end every game exactly as before: same ending (level
clear or game over), score, lives, level, dots, ghosts and map. Variables move when code is
added, so each side is read with its own symbol file.

    tools/botgames.sh 10                                  # before the edit
    cp -r dist/test/bot /tmp/base; cp dist/bot/pacfan.sym /tmp/base.sym
    ...edit...
    tools/botgames.sh 10                                  # after
    python3 tools/botdiff.py /tmp/base /tmp/base.sym dist/test/bot dist/bot/pacfan.sym

No symbols for the "before" build any more? Build the old source from git into a scratch
folder (with tables.inc and drawspr.inc beside it) with `lwasm -9 -DBOT=1 --symbol-dump=`.
Exit status 1 if any game differs.
"""
import os
import sys

if len(sys.argv) != 5:
    sys.exit(__doc__)
old_dir, old_sym, new_dir, new_sym = sys.argv[1:5]


def syms(path):
    d = {}
    for line in open(path):
        p = line.split()
        if len(p) >= 3 and p[1] == 'EQU':
            d[p[0]] = int(p[2].lstrip('$'), 16)
    return d


so, sn = syms(old_sym), syms(new_sym)
FIELDS = [('SCORE', 3), ('LIVES', 1), ('LEVEL', 1), ('DOTS', 1), ('LAP', 1), ('ELROY', 1), ('GMODE', 1),
          ('MTIDX', 1), ('MTIME', 2), ('FRIGHT', 2), ('GSPD', 1), ('FRTIME', 2), ('DOTSEATEN', 1),
          ('ENTS', 50), ('MAP', 240)]
# FRAMES (the animation phase: mouth, ghost flash, title chase) is left out on purpose. It
# counts title frames until SPACE, so any change at start-up shifts it by a frame in every game
# alike (the 6 Nov edits moved it by exactly -1 in all 400) while nothing in play moves.


def grab(ram, s):
    return {n: bytes(ram[s[n]:s[n] + k]) for n, k in FIELDS if n in s}


old = sorted(f for f in os.listdir(old_dir) if f.startswith('end_'))
new = sorted(f for f in os.listdir(new_dir) if f.startswith('end_'))
ok = True
if old != new:
    ok = False
    print('different games ended, or ended differently: only before %s, only after %s' % (
        sorted(set(old) - set(new))[:5], sorted(set(new) - set(old))[:5]))
same, bad = 0, []
for f in old:
    if f not in new:
        continue
    a = grab(open(os.path.join(old_dir, f), 'rb').read(), so)
    b = grab(open(os.path.join(new_dir, f), 'rb').read(), sn)
    d = [n for n in a if a[n] != b.get(n)]
    if d:
        bad.append((f, d))
    else:
        same += 1
print('games: %d  (%d cleared the level, %d game over)' % (
    len(old), sum('_clear' in f for f in old), sum('_over' in f for f in old)))
print('identical: %d   different: %d' % (same, len(bad)))
for f, d in bad[:10]:
    print('  differs', f, d)
sys.exit(0 if ok and not bad else 1)
