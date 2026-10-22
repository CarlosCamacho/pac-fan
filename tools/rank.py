#!/usr/bin/env python3
"""Rank levels by difficulty from tools/botgames.sh results.
    python3 tools/rank.py            print the ranking (positions are the CURRENT play order)
    python3 tools/rank.py --write    also rewrite levels/order.json: first level kept first,
                                     the rest easiest to hardest
Measure: deaths per 100 dots eaten over all games of a level (fewer clears breaks ties).
"""
import glob, json, os, random, sys
here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sym = {l.split()[0]: int(l.split()[-1].strip("$"), 16)
       for l in open(os.path.join(here, "dist", "bot", "pacfan.sym")) if " EQU " in l}
res = {}
for f in glob.glob(os.path.join(here, "dist", "test", "bot", "end_*.ram")):
    _, L, sd, kind = os.path.basename(f)[:-4].split("_")
    r = open(f, "rb").read()
    lvp = r[sym["LVP"]] << 8 | r[sym["LVP"] + 1]
    tot, left, lives = r[lvp + 3], r[sym["DOTS"]], r[sym["LIVES"]]
    res.setdefault(int(L), []).append((kind == "clear", tot - left, 3 - lives if kind == "clear" else 3))
def score(v):
    return (sum(x[2] for x in v) / max(1, sum(x[1] for x in v)) * 100, -sum(x[0] for x in v))
play = json.load(open(os.path.join(here, "levels", "order.json")))["order"]
rest = sorted(range(1, len(play)), key=lambda L: score(res[L]))
random.seed(1)                                      # how firm is each position?
pos = {L: [] for L in rest}
for _ in range(500):
    sc = {L: score([random.choice(res[L]) for _ in res[L]]) for L in rest}
    for p, L in enumerate(sorted(rest, key=lambda L: sc[L])): pos[L].append(p + 2)
print("new  name        deaths/100 dots  clears  likely position")
print("  1  %-10s  (kept first)" % play[0])
for p, L in enumerate(rest):
    s = score(res[L]); ps = sorted(pos[L])
    print("%3d  %-10s  %15.2f  %2d/%-2d   %d-%d" % (p + 2, play[L], s[0], -s[1], len(res[L]),
                                                 ps[len(ps) // 20], ps[-len(ps) // 20]))
if "--write" in sys.argv:
    d = json.load(open(os.path.join(here, "levels", "order.json")))
    d["order"] = [play[0]] + [play[L] for L in rest]
    json.dump(d, open(os.path.join(here, "levels", "order.json"), "w"), indent=1)
    print("levels/order.json rewritten")
