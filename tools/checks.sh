#!/bin/sh
# Robustness checks on the built game. Run ./build.sh first (this uses dist/PACFAN.DSK and
# dist/pacfan.sym), then:
#
#   tools/checks.sh                  every check but "overrun"
#   tools/checks.sh break fuzz       just those
#
#   break    BREAK is noticed at 29 moments across a game start, a death, the flash and
#            READY! (a 300 ms tap each); and leaving mid-tune, mid-flash and mid-READY!
#            gives back a working BASIC from which EXEC restarts the game (CoCo 2 and 3)
#   fuzz     nothing depends on leftover RAM: the variable area is filled with different
#            patterns at START and the screens and game state must come out identical
#            (title and autopilot play, CoCo 2 and 3)
#   speed    CoCo 3 left at high speed (POKE 65497,0): the game runs at normal speed and
#            high speed is back after BREAK. Also checks normal speed is left alone.
#   lap      clearing level 40 goes round to level 1 at top speed
#   overrun  REPORT ONLY: how many frames run past one video field (-DOVR=1 build)
#
# SYM, DSK and SRC (the .sym, the .DSK and the .asm) can be set to check another build.
# Needs XROAR and ROMS as for the other tools; the CoCo 3 checks also need coco3.rom in ROMS
# and are skipped without it. Each check prints PASS or FAIL; the exit status is 1 on a FAIL.
. "$(dirname "$0")/emu.sh"
D=$WORK/checks; mkdir -p "$D"
SYM=${SYM:-$HERE/dist/pacfan.sym}; DSK=${DSK:-$HERE/dist/PACFAN.DSK}; SRC=${SRC:-$HERE/pacfan.asm}
LWASM=${LWASM:-lwasm}
FAILED=0
have3() { [ -f "$ROMS/coco3.rom" ]; }
# emu MACHINE ARGS...: c2 = CoCo 2 NTSC 32K, c3 = CoCo 3. Traps use px MACHINE: the CoCo 3's
# MMU puts logical $0000-$FFFF at physical $70000-$7FFFF.
emu() { m=$1; shift
  case $m in c2) set -- -machine cocous -ram 32 "$@";; c3) set -- -machine coco3 "$@";; esac
  timeout 900 "$XROAR" -headless -rompath "$ROMS" "$@"; }
px() { [ "$1" = c3 ] && echo 7 || echo 0; }
s() { sym "$1" "${2:-$SYM}"; }
say() { echo "$1 $2"; [ "$1" = FAIL ] && FAILED=1; return 0; }
byte() { printf "\\$(printf %03o "$1")"; }       # one byte, for -trap-load files

check_break() {
  O=$D/break; rm -rf "${O:?}"; mkdir -p "$O"
  Q=$(s QUIT); WS=$(s WSPACE); LV=$(s LEVEL); FR=$(s FRAME); ST=$(s STATE); SA=$(s START)
  byte 0 > "$O/lv.bin"; byte 1 > "$O/die.bin"
  # 29 taps, 0 to 14 s after SPACE is released; a death is forced at the 90th frame
  for d in $(python3 -c "print(' '.join(str(int(x * 500)) for x in range(29)))"); do
    printf 'wait 3000\ntype LOADM"PACFAN":EXEC\\r\nwait 8000\nkey space down\nwait 300\nkey space up\nwait %s\nkey break down\nwait 300\nkey break up\nwait 2500\n' "$d" > "$O/in_$d.txt"
    emu c2 -load-fd0 "$DSK" -input-script "$O/in_$d.txt" \
      -trap "xpc=0x0$WS" -trap-range 1-1 -trap-load "$O/lv.bin,format=raw,addr=0x0$LV" \
      -trap "xpc=0x0$FR" -trap-range 90-90 -trap-load "$O/die.bin,format=raw,addr=0x0$ST" \
      -trap "xpc=0x0$Q" -trap-range 1-1 -trap-ram "$O/quit_$d.ram" -trap-timeout 1 -timeout 120 >/dev/null 2>&1 &
  done
  wait
  miss=$(ls "$O"/quit_*.ram 2>/dev/null | wc -l)
  if [ "$miss" -eq 29 ]; then say PASS "break: all 29 taps noticed"; else say FAIL "break: only $miss of 29 taps noticed"; fi
  # leave mid-tune / mid-flash / mid-READY!, then BASIC must work and EXEC must restart the game
  for m in c2 c3; do
    [ $m = c3 ] && ! have3 && { echo "SKIP break/exit on CoCo 3 (no coco3.rom)"; continue; }
    P=$(px $m)
    for st in tune:1000 flash:7000 ready:8800; do
      n=${st%%:*}; d=${st##*:}
      printf 'wait 3000\ntype LOADM"PACFAN":EXEC\\r\nwait 8000\nkey space down\nwait 300\nkey space up\nwait %s\nkey break down\nwait 300\nkey break up\nwait 1500\ntype PRINT 2+2\\r\nwait 800\ntype EXEC\\r\nwait 9000\n' "$d" > "$O/x_${m}_$n.txt"
      emu $m -load-fd0 "$DSK" -input-script "$O/x_${m}_$n.txt" \
        -trap "xpc=0x$P$WS" -trap-range 1-1 -trap-load "$O/lv.bin,format=raw,addr=0x$P$LV" \
        -trap "xpc=0x$P$FR" -trap-range 90-90 -trap-load "$O/die.bin,format=raw,addr=0x$P$ST" \
        -trap "xpc=0x$P$Q" -trap-range 1-1 -trap-ram "$O/xq_${m}_$n.ram" \
        -trap "xpc=0x$P$SA" -trap-range 2-2 -trap-ram "$O/xs_${m}_$n.ram" -timeout 60 >/dev/null 2>&1 &
    done
  done
  wait
  for m in c2 c3; do
    [ $m = c3 ] && ! have3 && continue
    for n in tune flash ready; do
      if [ -f "$O/xq_${m}_$n.ram" ] && [ -f "$O/xs_${m}_$n.ram" ]; then say PASS "break: $m leaves mid-$n and EXEC restarts"
      else say FAIL "break: $m mid-$n (left: $([ -f "$O/xq_${m}_$n.ram" ] && echo yes || echo NO), restarted: $([ -f "$O/xs_${m}_$n.ram" ] && echo yes || echo NO))"; fi
    done
  done
}

# the autopilot build (-DBOT=1), for a game that plays itself deterministically
botbuild() {
  B=$D/bot; mkdir -p "$B"
  "$LWASM" -9 -DBOT=1 --format=decb --symbol-dump="$B/pacfan.sym" -o "$B/PACFAN.BIN" "$SRC" || return 1
  python3 "$HERE/mkdsk.py" "$B/PACFAN.DSK" "$B/PACFAN.BIN" >/dev/null
}

# fuzz NAME MACHINE BUILD(real|bot) SECONDS LEVEL SCOPE(screen|state): screen compares only
# the screens (all the title has set up); state adds the score, lives, map, ghosts...
fuzz() {
  name=$1; m=$2; build=$3; secs=$4; lvl=$5; scope=$6
  O=$D/fuzz_$name; rm -rf "${O:?}"; mkdir -p "$O"
  if [ $build = bot ]; then SY=$D/bot/pacfan.sym; DK=$D/bot/PACFAN.DSK; else SY=$SYM; DK=$DSK; fi
  P=$(px $m); SA=$(s START "$SY"); WS=$(s WSPACE "$SY"); LV=$(s LEVEL "$SY"); V0=$(s SAVES0 "$SY"); VE=$(s ENDVARS "$SY"); BS=$(s BSEED "$SY")
  python3 -I - "$O" "$V0" "$VE" <<'PY'
import sys, random
o, v0, ve = sys.argv[1], int(sys.argv[2], 16), int(sys.argv[3], 16)
n = ve - v0; random.seed(7)
for k, v in {'00': bytes(n), 'ff': b'\xff' * n, 'aa': b'\xaa' * n, 'r1': bytes(random.randrange(256) for _ in range(n))}.items():
    open('%s/fill_%s.bin' % (o, k), 'wb').write(v)
PY
  byte "$lvl" > "$O/lv.bin"; byte 1 > "$O/sd.bin"
  for p in 00 ff aa r1; do
    extra=""; [ $build = bot ] && extra="-trap xpc=0x$P$WS -trap-range 1-1 -trap-load $O/sd.bin,format=raw,addr=0x$P$BS"
    emu $m -load-fd0 "$DK" -input-script "$WORK/start.txt" \
      -trap "xpc=0x$P$SA" -trap-range 1-1 -trap-load "$O/fill_$p.bin,format=raw,addr=0x$P$V0" \
      -trap "xpc=0x$P$WS" -trap-range 1-1 -trap-load "$O/lv.bin,format=raw,addr=0x$P$LV" $extra \
      -trap "seconds=$secs" -trap-ram "$O/ram_$p.ram" -trap-timeout 1 -timeout $((secs + 60)) >/dev/null 2>&1 &
  done
  wait
  # screens and background ($0E00-$31FF) plus the game state that matters
  python3 -I - "$O" "$SY" "$P" "$scope" <<'PY'
import sys
o, sy, px, scope = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
sym = {l.split()[0]: int(l.split('$')[1], 16) for l in open(sy) if len(l.split()) >= 3 and l.split()[1] == 'EQU'}
base = int(px, 16) << 16
ram = {p: open('%s/ram_%s.ram' % (o, p), 'rb').read() for p in ('00', 'ff', 'aa', 'r1')}
fields = [(0x0E00, 0x3200 - 0x0E00)]
if scope == 'state':
    fields += [(sym[n], k) for n, k in (('SCORE', 3), ('LIVES', 1), ('LEVEL', 1), ('DOTS', 1), ('LAP', 1), ('GSPD', 1), ('FRIGHT', 2), ('GMODE', 1), ('ENTS', 50), ('MAP', 240))]
bad = [p for p in ('ff', 'aa', 'r1') if any(ram[p][base + a:base + a + k] != ram['00'][base + a:base + a + k] for a, k in fields)]
print(' '.join(bad) or 'same')
PY
}

check_fuzz() {
  botbuild || { say FAIL "fuzz: the autopilot build failed"; return; }
  for t in "title c2 real 10 0 screen" "play-c2 c2 bot 45 0 state" "late-c2 c2 bot 45 20 state"; do
    set -- $t; r=$(fuzz "$@" | tail -n 1)
    if [ "$r" = same ]; then say PASS "fuzz: $1 identical for every fill"; else say FAIL "fuzz: $1 differs with fill: $r"; fi
  done
  if have3; then
    r=$(fuzz play-c3 c3 bot 45 0 state | tail -n 1)
    if [ "$r" = same ]; then say PASS "fuzz: play-c3 identical for every fill"; else say FAIL "fuzz: play-c3 differs with fill: $r"; fi
  else echo "SKIP fuzz on CoCo 3 (no coco3.rom)"; fi
}

check_speed() {
  have3 || { echo "SKIP speed (no coco3.rom)"; return; }
  O=$D/speed; rm -rf "${O:?}"; mkdir -p "$O"
  Q=$(s QUIT); FF=$(s FASTF)
  [ -n "$FF" ] || { say FAIL "speed: no FASTF in the symbol file"; return; }
  for v in normal fast; do
    python3 -I - "$O" $v <<'PY'
import sys
o, v = sys.argv[1], sys.argv[2]
loop = 'type TIMER=0:FOR I=1 TO 1500:NEXT:PRINT TIMER\\r\nwait 6000\n'
pre = 'type POKE 65497,0\\r\nwait 500\n' if v == 'fast' else ''
open('%s/%s.txt' % (o, v), 'w').write('wait 3000\n' + pre + loop + 'type LOADM"PACFAN":EXEC\\r\nwait 8000\nkey space down\nwait 300\nkey space up\nwait 12000\nkey break down\nwait 300\nkey break up\nwait 1500\n' + loop + 'wait 2000\n')
PY
    emu c3 -load-fd0 "$DSK" -input-script "$O/$v.txt" -trap "xpc=0x7$Q" -trap-range 1-1 -trap-ram "$O/${v}_quit.ram" \
      -trap "seconds=70" -trap-ram "$O/${v}_end.ram" -trap-timeout 1 -timeout 120 >/dev/null 2>&1 &
  done
  wait
  python3 -I - "$O" "$FF" <<'PY' || FAILED=1
import sys
o, ff = sys.argv[1], int(sys.argv[2], 16)
def ticks(path):
    d = open(path, 'rb').read()[0x70400:0x70600]        # the text screen
    out = []
    for r in range(16):
        row = ''.join(chr((c & 0x3F) + (64 if (c & 0x3F) < 32 else 0)) for c in d[r * 32:r * 32 + 32])
        if row.strip().isdigit(): out.append(int(row))
    return out
ok = True
for v, want in (('normal', 0), ('fast', 1)):
    f = open('%s/%s_quit.ram' % (o, v), 'rb').read()[0x70000 + ff]
    t = ticks('%s/%s_end.ram' % (o, v))
    good = f == want and len(t) == 2 and abs(t[0] - t[1]) <= 0.05 * t[0]
    ok &= good
    print('%s speed: FASTF=%d (want %d), BASIC loop ticks before/after the game %s -> %s' % ('PASS' if good else 'FAIL', f, want, t[0] if t else '?', t[1] if len(t) > 1 else '?'))
sys.exit(0 if ok else 1)
PY
}

check_lap() {
  O=$D/lap; rm -rf "${O:?}"; mkdir -p "$O"
  WS=$(s WSPACE); LV=$(s LEVEL); FR=$(s FRAME); ST=$(s STATE); LP=$(s LAP); GS=$(s GSPD); FT=$(s FRTIME)
  byte 39 > "$O/lv.bin"; byte 2 > "$O/clr.bin"
  emu c2 -load-fd0 "$DSK" -input-script "$WORK/start.txt" \
    -trap "xpc=0x0$WS" -trap-range 1-1 -trap-load "$O/lv.bin,format=raw,addr=0x0$LV" \
    -trap "xpc=0x0$FR" -trap-range 90-90 -trap-load "$O/clr.bin,format=raw,addr=0x0$ST" \
    -trap "seconds=24" -trap-ram "$O/after.ram" -trap-timeout 1 -timeout 60 >/dev/null 2>&1
  python3 -I - "$O" "$LV" "$LP" "$GS" "$FT" <<'PY' && say PASS "lap: level 40 cleared goes to level 1 at speed 19, blue 2 s" || say FAIL "lap: wrong state after clearing level 40"
import sys
o = sys.argv[1]; lv, lp, gs, ft = [int(x, 16) for x in sys.argv[2:6]]
d = open(o + '/after.ram', 'rb').read()
sys.exit(0 if (d[lv], d[lp], d[gs], d[ft] * 256 + d[ft + 1]) == (0, 1, 19, 120) else 1)
PY
}

check_overrun() {
  O=$D/overrun; rm -rf "${O:?}"; mkdir -p "$O"
  "$LWASM" -9 -DBOT=1 -DOVR=1 --format=decb --symbol-dump="$O/pacfan.sym" -o "$O/PACFAN.BIN" "$SRC" || return 1
  python3 "$HERE/mkdsk.py" "$O/PACFAN.DSK" "$O/PACFAN.BIN" >/dev/null
  WS=$(s WSPACE "$O/pacfan.sym"); LV=$(s LEVEL "$O/pacfan.sym"); BS=$(s BSEED "$O/pacfan.sym")
  byte 1 > "$O/sd.bin"; l=0
  while [ $l -lt 40 ]; do
    byte $l > "$O/lv$l.bin"
    emu c2 -load-fd0 "$O/PACFAN.DSK" -input-script "$WORK/start.txt" \
      -trap "xpc=0x0$WS" -trap-range 1-1 -trap-load "$O/lv$l.bin,format=raw,addr=0x0$LV" \
      -trap "xpc=0x0$WS" -trap-range 1-1 -trap-load "$O/sd.bin,format=raw,addr=0x0$BS" \
      -trap "seconds=100" -trap-ram "$O/r$l.ram" -trap-timeout 1 -timeout 160 >/dev/null 2>&1 &
    l=$((l + 1))
  done
  wait
  python3 -I - "$O" "$(s OVRN "$O/pacfan.sym")" "$(s TOTF "$O/pacfan.sym")" <<'PY'
import sys
o, ov, tf = sys.argv[1], int(sys.argv[2], 16), int(sys.argv[3], 16)
long_ = tot = 0
for l in range(40):
    d = open('%s/r%d.ram' % (o, l), 'rb').read()
    long_ += d[ov] * 256 + d[ov + 1]; tot += d[tf] * 256 + d[tf + 1]
print('overrun (report only): %d of %d frames (%.1f%%) ran past one video field' % (long_, tot, 100.0 * long_ / max(tot, 1)))
PY
}

[ -f "$SYM" ] && [ -f "$DSK" ] || { echo "build first: ./build.sh"; exit 2; }
[ $# -gt 0 ] || set -- break fuzz speed lap
for c in "$@"; do
  case $c in break|fuzz|speed|lap|overrun) "check_$c";; *) echo "unknown check: $c"; exit 2;; esac
done
exit $FAILED
