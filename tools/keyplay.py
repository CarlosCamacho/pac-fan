#!/usr/bin/env python3
"""Write an xroar input script that loads the game, starts it and then plays with random arrow
keys for a while, pressing SPACE now and then so a game over starts a new game.

    python3 tools/keyplay.py OUT.txt SEED [SECONDS]

For measuring the real build (not the autopilot): the player wanders, eats dots, gets chased and
dies, much like a person at the keys. The same SEED gives the same script.
"""
import random
import sys

if len(sys.argv) < 3:
    sys.exit(__doc__)
out, seed = sys.argv[1], int(sys.argv[2])
secs = int(sys.argv[3]) if len(sys.argv) > 3 else 100
rnd = random.Random(seed)
lines = ['wait 3000', 'type LOADM"PAKFAN":EXEC\\r', 'wait 8000', 'key space down', 'wait 300', 'key space up']
t = 0
while t < secs * 1000:
    d = rnd.choice(['up', 'down', 'left', 'right'])
    hold = rnd.randrange(300, 1800)
    lines += ['key %s down' % d, 'wait %d' % hold, 'key %s up' % d, 'wait %d' % rnd.randrange(0, 150)]
    t += hold
    if rnd.random() < 0.05:                      # a new game after game over
        lines += ['key space down', 'wait 200', 'key space up']
open(out, 'w').write('\n'.join(lines) + '\nwait 2000\n')
