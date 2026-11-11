#!/bin/sh
# Robustness checks on the built game. Run ./build.sh first (this uses dist/PAKFAN.DSK and
# dist/pakfan.sym), then:
#
#   tools/checks.sh                  every check
#   tools/checks.sh break fuzz       just those
#
#   break    BREAK is noticed at 29 moments across a game start, a death, the flash and
#            READY! (a 300 ms tap each); and leaving mid-tune, mid-flash and mid-READY!
#            gives back a working BASIC from which EXEC restarts the game (CoCo 2 and 3)
#   basic    after BREAK, BASIC works as before: a typed program lists and runs (CoCo 2 and 3)
#   fuzz     nothing depends on leftover RAM: the variable area is filled with different
#            patterns at START and the screens and game state must come out identical
#            (title and autopilot play, CoCo 2 and 3)
#   speed    CoCo 3 left at high speed (POKE 65497,0): the game runs at normal speed and
#            high speed is back after BREAK. Also checks normal speed is left alone.
#   tune     the speaker output of the intro tune is in tune (every note within 2%) on a CoCo 2,
#            a CoCo 3 and a CoCo 3 left at high speed (needs numpy)
#   sound    eating dots is audible
#   lap      clearing level 40 goes round to level 1 at top speed
#   menu     CONTROL and SOUND change (wrapping both ways), ABOUT pages through and comes back, PLAY starts
#   joy      a scripted stick moves the menu and steers the player
#   score    the score on screen equals the score after many updates, and rolls over past 999,999
#   eyes     on every level, from every tile, the way-home map leads the eyes back to the house
#   protect  both the game and the autopilot build, all 40 levels, under -protect-mode (CoCo 3):
#            no write into code, no jump into data, stack within 64 bytes (it uses under 20)
#   overrun  frames that run past one video field in the real game (random arrow keys, all
#            40 levels, 100 s each, -DOVR=1 build): fails above 0.05% of frames. Frames that
#            eat a ghost are not counted: their sound blocks on purpose. Takes about 2 minutes.
#
# SYM, DSK and SRC (the .sym, the .DSK and the .asm; LST the listing, default beside the .sym)
# can be set to check another build.
# Needs XROAR and ROMS as for the other tools; the CoCo 3 checks also need coco3.rom in ROMS
# and are skipped without it. Each check prints PASS or FAIL; the exit status is 1 on a FAIL.
. "$(dirname "$0")/emu.sh"
D=$WORK/checks; mkdir -p "$D"
SYM=${SYM:-$HERE/dist/pakfan.sym}; DSK=${DSK:-$HERE/dist/PAKFAN.DSK}; SRC=${SRC:-$HERE/pakfan.asm}
LWASM=${LWASM:-lwasm}
FAILED=0
have3() { [ -f "$ROMS/coco3.rom" ]; }
# emu MACHINE ARGS...: c2 = CoCo 2 NTSC 32K, c3 = CoCo 3. Traps use px MACHINE: the CoCo 3's
# MMU puts logical $0000-$FFFF at physical $70000-$7FFFF.
# (a CoCo 3 copies BASIC's ROM into the upper RAM as it starts, so the engine goes in when the game starts)
emu() { m=$1; shift
  case $m in c2) set -- -machine cocous -ram 64 -load-ram "$AUDRAW,addr=0x8000" "$@";; c3) set -- -machine coco3 -trap "xpc=0x73202" -trap-load "$AUDRAW,format=raw,addr=0x78000" "$@";; esac
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
    printf 'wait 3000\ntype LOADM"PAKFAN":EXEC\\r\nwait 8000\nkey space down\nwait 300\nkey space up\nwait %s\nkey break down\nwait 300\nkey break up\nwait 2500\n' "$d" > "$O/in_$d.txt"
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
      printf 'wait 3000\ntype LOADM"PAKFAN":EXEC\\r\nwait 8000\nkey space down\nwait 300\nkey space up\nwait %s\nkey break down\nwait 300\nkey break up\nwait 1500\ntype PRINT 2+2\\r\nwait 800\ntype EXEC\\r\nwait 9000\n' "$d" > "$O/x_${m}_$n.txt"
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
  "$LWASM" -9 -DBOT=1 --format=decb --list="$B/pakfan.lst" --symbol-dump="$B/pakfan.sym" -o "$B/PAKFAN.BIN" "$SRC" || return 1
  python3 "$HERE/mkdsk.py" "$B/PAKFAN.DSK" "$B/PAKFAN.BIN" >/dev/null
}

# fuzz NAME MACHINE BUILD(real|bot) SECONDS LEVEL SCOPE(screen|state): screen compares only
# the screens (all the title has set up); state adds the score, lives, map, ghosts...
fuzz() {
  name=$1; m=$2; build=$3; secs=$4; lvl=$5; scope=$6
  O=$D/fuzz_$name; rm -rf "${O:?}"; mkdir -p "$O"
  if [ $build = bot ]; then SY=$D/bot/pakfan.sym; DK=$D/bot/PAKFAN.DSK; else SY=$SYM; DK=$DSK; fi
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
tog = 'type LOADM"TOGGLE":EXEC\\r\nwait 2500\n'     # xroar-dev's CoCo 3 runs BASIC faster after any all-RAM toggle: measure after one
open('%s/%s.txt' % (o, v), 'w').write('wait 3000\n' + pre + tog + loop + 'type LOADM"PAKFAN":EXEC\\r\nwait 8000\nkey space down\nwait 300\nkey space up\nwait 12000\nkey break down\nwait 300\nkey break up\nwait 1500\n' + loop + 'wait 2000\n')
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
    -trap "seconds=42" -trap-ram "$O/after.ram" -trap-timeout 1 -timeout 90 >/dev/null 2>&1
  python3 -I - "$O" "$LV" "$LP" "$GS" "$FT" <<'PY' && say PASS "lap: level 40 cleared goes to level 1 at speed 19, blue 2 s" || say FAIL "lap: wrong state after clearing level 40"
import sys
o = sys.argv[1]; lv, lp, gs, ft = [int(x, 16) for x in sys.argv[2:6]]
d = open(o + '/after.ram', 'rb').read()
sys.exit(0 if (d[lv], d[lp], d[gs], d[ft] * 256 + d[ft + 1]) == (0, 1, 19, 120) else 1)
PY
}

check_overrun() {
  O=$D/overrun; rm -rf "${O:?}"; mkdir -p "$O"
  "$LWASM" -9 -DOVR=1 --format=decb --symbol-dump="$O/pakfan.sym" -o "$O/PAKFAN.BIN" "$SRC" || return 1
  python3 "$HERE/mkdsk.py" "$O/PAKFAN.DSK" "$O/PAKFAN.BIN" >/dev/null
  WS=$(s WSPACE "$O/pakfan.sym"); LV=$(s LEVEL "$O/pakfan.sym"); l=0
  while [ $l -lt 40 ]; do
    byte $l > "$O/lv$l.bin"
    python3 "$HERE/tools/keyplay.py" "$O/in$l.txt" $((l + 1)) 100
    emu c2 -load-fd0 "$O/PAKFAN.DSK" -input-script "$O/in$l.txt" \
      -trap "xpc=0x0$WS" -trap-range 1-1 -trap-load "$O/lv$l.bin,format=raw,addr=0x0$LV" \
      -trap "seconds=114" -trap-ram "$O/r$l.ram" -trap-timeout 1 -timeout 160 >/dev/null 2>&1 &
    l=$((l + 1))
  done
  wait
  python3 -I - "$O" <<'PY' && say PASS "overrun: frames past one field within budget" || say FAIL "overrun: too many frames run past one video field"
import sys
b = sys.argv[1]
S = {l.split()[0]: int(l.split('$')[1], 16) for l in open(b + '/pakfan.sym') if len(l.split()) >= 3 and l.split()[1] == 'EQU'}
T = [0] * 128; X = [0] * 128
for l in range(40):
    d = open('%s/r%d.ram' % (b, l), 'rb').read()
    for i in range(128):
        T[i] += d[S['OVRT'] + 2 * i] * 256 + d[S['OVRT'] + 2 * i + 1]
        X[i] += d[S['OVRX'] + 2 * i] * 256 + d[S['OVRX'] + 2 * i + 1]
def name(i):
    return '%d ghost decisions, %d score redraws%s%s%s' % (i & 3, (i >> 2) & 3, ', ghost eaten' if i & 16 else '', ', pill' if i & 32 else '', ', mode switch' if i & 64 else '')
tot = sum(T); gulp = sum(X[i] for i in range(128) if i & 16); other = sum(X) - gulp
print('  %d frames: %d ran long (%d of them ate a ghost, on purpose), %d others = %.3f%%' % (tot, sum(X), gulp, other, 100.0 * other / max(tot, 1)))
bad = [i for i in sorted(range(128), key=lambda i: -X[i]) if X[i] and not i & 16]
for i in bad[:5]:
    print('  %-52s %7d frames, %4d long (%.1f%%)' % (name(i), T[i], X[i], 100.0 * X[i] / T[i]))
sys.exit(0 if other <= 0.0005 * tot else 1)
PY
}

# protect: the shipped game (random arrow keys) and the autopilot build (clears levels, eats
# pills and ghosts), 40 levels each, under xroar-dev's -protect-mode on a CoCo 3: a write into
# code, an instruction fetched from data, or the stack growing more than 64 bytes below where
# BASIC left it ($7F34) stops the run with exit status 70. The map comes from the listing.
check_protect() {
  have3 || { echo "SKIP protect (no coco3.rom)"; return; }
  O=$D/protect; rm -rf "${O:?}"; mkdir -p "$O"
  LST=${LST:-${SYM%.sym}.lst}
  [ -f "$LST" ] || { say FAIL "protect: no listing at $LST (./build.sh writes it)"; return; }
  botbuild || { say FAIL "protect: the autopilot build failed"; return; }
  python3 "$HERE/tools/mksym.py" "$LST" "$SYM" "$O/real.gsym" 0x70000 >/dev/null || return 1
  python3 "$HERE/tools/mksym.py" "$D/bot/pakfan.lst" "$D/bot/pakfan.sym" "$O/bot.gsym" 0x70000 >/dev/null || return 1
  # the audio engine in the upper 32K (physical $78000 up on a CoCo 3) is code too
  python3 "$HERE/tools/mksym.py" "$HERE/dist/audio.lst" "$HERE/dist/audio.sym" "$O/audio.gsym" 0x70000 >/dev/null || return 1
  grep -v '^S ' "$O/audio.gsym" | tail -n +2 >> "$O/real.gsym"
  grep -v '^S ' "$O/audio.gsym" | tail -n +2 >> "$O/bot.gsym"
  for v in real bot; do
    if [ $v = real ]; then SY=$SYM; DK=$DSK; else SY=$D/bot/pakfan.sym; DK=$D/bot/PAKFAN.DSK; fi
    SA=$(s START "$SY"); WS=$(s WSPACE "$SY"); LV=$(s LEVEL "$SY"); BS=$(s BSEED "$SY")
    byte 1 > "$O/sd.bin"; l=0
    while [ $l -lt 40 ]; do
      byte $l > "$O/lv$l.bin"
      python3 "$HERE/tools/keyplay.py" "$O/in$l.txt" $((l + 1)) 80
      extra=""; [ $v = bot ] && extra="-trap xpc=0x7$WS -trap-range 1-1 -trap-load $O/sd.bin,format=raw,addr=0x7$BS"
      ( emu c3 -load-fd0 "$DK" -input-script "$O/in$l.txt" -symbols "$O/$v.gsym" -protect-mode \
          -protect-allow 0x70E00-0x731FF -protect-stack-floor 0x77EF4 -protect-dump "$O/${v}_$l.crash" \
          -trap "xpc=0x7$SA" -trap-range 1-1 -trap-protect-on \
          -trap "xpc=0x7$WS" -trap-range 1-1 -trap-load "$O/lv$l.bin,format=raw,addr=0x7$LV" $extra \
          -trap "seconds=94" -trap-timeout 1 -timeout 160 > "$O/${v}_$l.out" 2>&1; echo $? > "$O/${v}_$l.rc" ) &
      l=$((l + 1))
    done
    wait
    bad=$(grep -L '^0$' "$O/${v}"_*.rc 2>/dev/null | wc -l)
    if [ "$bad" -eq 0 ]; then say PASS "protect: $v build, 40 levels, no write into code, no jump into data, stack within 64 bytes"
    else
      say FAIL "protect: $v build, $bad of 40 levels stopped by protect mode"
      grep -h "protect: " $(grep -L '^0$' "$O/${v}"_*.rc | sed 's/\.rc$/.out/') | grep -v "armed\|checks live" | head -4 | sed 's/^/  /'
    fi
  done
}

# joystick: with CONTROL set to JOYSTICK, a scripted stick (xroar-dev's -joy-right script) moves the menu
# (down a row, right on SOUND, fire presses) and steers the player in the game.
check_joy() {
  O=$D/joy; rm -rf "${O:?}"; mkdir -p "$O"
  cat > "$O/menu.txt" <<'EOF'
wait 3000
type LOADM"PAKFAN":EXEC\r
wait 8000
move 32767 32767
wait 500
key down down
wait 300
key down up
wait 300
key right down
wait 300
key right up
wait 500
move 32767 65535
wait 600
move 32767 32767
wait 600
move 65535 32767
wait 600
move 32767 32767
wait 600
down
wait 400
up
wait 800
EOF
  cat > "$O/game.txt" <<'EOF'
wait 3000
type LOADM"PAKFAN":EXEC\r
wait 8000
move 32767 32767
wait 300
key down down
wait 300
key down up
wait 300
key right down
wait 300
key right up
wait 500
key up down
wait 300
key up up
wait 500
key space down
wait 300
key space up
wait 6000
move 65535 32767
wait 9000
EOF
  emu c2 -joy-right script -load-fd0 "$DSK" -input-script "$O/menu.txt" -trap "seconds=22" -trap-ram "$O/menu.ram" -trap-timeout 1 -timeout 60 >/dev/null 2>&1 &
  emu c2 -joy-right script -load-fd0 "$DSK" -input-script "$O/game.txt" -trap "seconds=28" -trap-ram "$O/game.ram" -trap-timeout 1 -timeout 60 >/dev/null 2>&1 &
  # reading the stick works the DAC: the speaker must be off meanwhile (a silent menu with the stick on stays silent)
  emu c2 -joy-right script -load-fd0 "$DSK" -input-script "$O/menu.txt" -audio-record-source mix -trap "seconds=15" -trap-audio-start "$O/quiet.wav" \
    -trap "seconds=18" -trap-audio-stop -trap "seconds=19" -trap-timeout 1 -timeout 60 >/dev/null 2>&1 &
  wait
  python3 -I - "$O" "$SYM" <<'PY' && say PASS "joystick: the stick moves the menu (down, right, fire), steers the player, and makes no noise" || say FAIL "joystick"
import sys
o = sys.argv[1]
S = {l.split()[0]: int(l.split('$')[1], 16) for l in open(sys.argv[2]) if len(l.split()) >= 3 and l.split()[1] == 'EQU'}
m = open(o + '/menu.ram', 'rb').read(); g = open(o + '/game.ram', 'rb').read()
e = S['ENTS']
got = (m[S['OPTCTL']], m[S['MSEL']], m[S['OPTSND']], g[e + 2], g[e + 3])
print('  OPTCTL, MSEL, OPTSND, player dir, want: %s (wanted 1, 2, 5, 0, 0)' % (got,))
import wave
import numpy as np
w = wave.open(o + '/quiet.wav'); x = np.frombuffer(w.readframes(w.getnframes()), dtype='<i2').astype(float)[int(0.3 * w.getframerate()):]
print('  speaker rms while the stick is read in a silent menu: %.0f (want < 20)' % x.std())
sys.exit(0 if got == (1, 2, 5, 0, 0) and x.std() < 20 else 1)
PY
}

# orch: with SOUND set to ORCH90 the sound must leave by the Orchestra-90's DACs, not the 6-bit one (a missing
# direct-page prefix once left the engine in DAC mode and nobody heard the difference): silent with no cartridge
# in the Multi-Pak, the start music right with it.
check_orch() {
  python3 -c 'import numpy' 2>/dev/null || { echo "SKIP orch (no numpy)"; return; }
  O=$D/orch; rm -rf "${O:?}"; mkdir -p "$O"
  SB=$(s STARTMUS); MO=$(s MSGOFF)
  printf 'wait 3000\ntype LOADM"PAKFAN":EXEC\\r\nwait 7000\nkey down down\nwait 200\nkey down up\nwait 400\nkey down down\nwait 200\nkey down up\nwait 400\nkey right down\nwait 200\nkey right up\nwait 800\nkey up down\nwait 200\nkey up up\nwait 400\nkey up down\nwait 200\nkey up up\nwait 600\nkey space down\nwait 300\nkey space up\nwait 9000\n' > "$O/in.txt"
  for v in none cart; do
    x=""; [ $v = cart ] && x="-cart mpi -mpi-load-cart rsdos -mpi-load-cart orch90 -mpi-slot 0"
    emu c2 $x -load-fd0 "$DSK" -input-script "$O/in.txt" -audio-record-source mix \
      -trap "xpc=0x0$SB" -trap-range 1-1 -trap-audio-start "$O/$v.wav" \
      -trap "xpc=0x0$MO" -trap-range 1-1 -trap-audio-stop -trap "seconds=30" -trap-timeout 1 -timeout 60 >/dev/null 2>&1 &
  done
  wait
  r=$(python3 -I - "$O/none.wav" <<'PY'
import sys, wave
import numpy as np
w = wave.open(sys.argv[1]); d = np.frombuffer(w.readframes(w.getnframes()), dtype='<i2').astype(float)
print('%.0f' % d.std())
PY
)
  if [ -n "$r" ] && [ "$r" -lt 50 ] && python3 "$HERE/tools/audiocheck.py" "$O/cart.wav" "$HERE/assets/audio/synth/snd00.bin" >/dev/null 2>&1; then
    say PASS "orch: ORCH90 is silent without the cartridge (rms $r) and plays the start music right with it"
  else say FAIL "orch: without the cartridge rms=${r:-none} (want < 50); with it: $(python3 "$HERE/tools/audiocheck.py" "$O/cart.wav" "$HERE/assets/audio/synth/snd00.bin" 2>&1 | tail -n 1)"; fi
}

# menu: UP/DOWN pick a row (PLAY starts the game at level 1), LEFT/RIGHT change CONTROL (keyboard/joystick) and SOUND (DAC, Orchestra-90, OFF,
# wrapping both ways), ENTER on ABOUT shows the story (any key turns the pages, then back at the menu).
check_menu() {
  O=$D/menu; rm -rf "${O:?}"; mkdir -p "$O"
  n=0
  # keys : OPTCTL OPTSND HAVEAUD STARTLV (-1: not checked)
  for sc in "down,right:1:0:1:-1" "down,down,right:0:3:1:-1" "down,down,right,right:0:5:0:-1" "down,down,right,right,right:0:0:1:-1" "down,down,left:0:5:0:-1" \
            "down,down,down,enter,a,a,up,up,up,space:0:0:1:0"; do
    n=$((n + 1)); echo "${sc#*:}" > "$O/want$n"
    python3 -I - "$O/in$n.txt" "${sc%%:*}" <<'PY'
import sys
out, keys = sys.argv[1], sys.argv[2].split(',')
L = ['wait 3000', 'type LOADM"PAKFAN":EXEC\\r', 'wait 8000']
for k in keys:
    L += ['key %s down' % k, 'wait 300', 'key %s up' % k, 'wait 1200' if k in ('enter', 'a') else 'wait 300']
open(out, 'w').write('\n'.join(L + ['wait 6000']) + '\n')
PY
    emu c2 -load-fd0 "$DSK" -input-script "$O/in$n.txt" -trap "seconds=44" -trap-ram "$O/r$n.ram" -trap-timeout 1 -timeout 80 >/dev/null 2>&1 &
  done
  wait
  python3 -I - "$O" "$SYM" $n <<'PY' && say PASS "menu: CONTROL and SOUND change, ABOUT pages through and comes back, PLAY starts" || say FAIL "menu"
import sys
o = sys.argv[1]; N = int(sys.argv[3])
S = {l.split()[0]: int(l.split('$')[1], 16) for l in open(sys.argv[2]) if len(l.split()) >= 3 and l.split()[1] == 'EQU'}
ok = True
for n in range(1, N + 1):
    want = [int(x) for x in open('%s/want%d' % (o, n)).read().strip().split(':')]
    try:
        d = open('%s/r%d.ram' % (o, n), 'rb').read()
        got = [d[S['OPTCTL']], d[S['OPTSND']], d[S['HAVEAUD']], d[S['STARTLV']]]
    except OSError:
        got = None
    good = got is not None and all(w < 0 or w == g for w, g in zip(want, got))
    ok &= good
    if not good: print('  scenario %d: wanted %s, got %s' % (n, want, got))
sys.exit(0 if ok else 1)
PY
}

# score: the score on screen is the score, in BG and both screens, after hundreds of changes
# (HUDS redraws only the digits that changed), and past 999,999 it wraps to 0 without trouble.
check_score() {
  O=$D/score; rm -rf "${O:?}"; mkdir -p "$O"
  botbuild || { say FAIL "score: the autopilot build failed"; return; }
  B=$D/bot; SY=$B/pakfan.sym
  WS=$(s WSPACE "$SY"); LV=$(s LEVEL "$SY"); BS=$(s BSEED "$SY"); FR=$(s FRAME "$SY"); SC=$(s SCORE "$SY")
  byte 0 > "$O/lv.bin"; byte 1 > "$O/sd.bin"; printf '\231\231\220' > "$O/high.bin"      # BCD 99 99 90
  for run in plain high; do
    extra=""; [ $run = high ] && extra="-trap xpc=0x0$FR -trap-range 3-3 -trap-load $O/high.bin,format=raw,addr=0x0$SC"
    emu c2 -load-fd0 "$B/PAKFAN.DSK" -input-script "$WORK/start.txt" \
      -trap "xpc=0x0$WS" -trap-range 1-1 -trap-load "$O/lv.bin,format=raw,addr=0x0$LV" \
      -trap "xpc=0x0$WS" -trap-range 1-1 -trap-load "$O/sd.bin,format=raw,addr=0x0$BS" $extra \
      -trap "seconds=45" -trap-ram "$O/$run.ram" -trap-timeout 1 -timeout 120 >/dev/null 2>&1 &
  done
  wait
  python3 -I - "$O" "$SY" <<'PY' && say PASS "score: HUD matches the score after many changes, and rolls over past 999,999" || say FAIL "score: HUD or rollover"
import sys
o = sys.argv[1]
S = {l.split()[0]: int(l.split('$')[1], 16) for l in open(sys.argv[2]) if len(l.split()) >= 3 and l.split()[1] == 'EQU'}
ok = True
for run in ('plain', 'high'):
    d = open('%s/%s.ram' % (o, run), 'rb').read()
    sc = d[S['SCORE']:S['SCORE'] + 3]
    digits = [(sc[i // 2] >> (4 if i % 2 == 0 else 0)) & 15 for i in range(6)]
    msgs = []
    if any((b >> 4) > 9 or (b & 15) > 9 for b in sc): msgs.append('not valid BCD')
    for name, base in (('BG', S['BG']), ('BUF0', S['BUF0']), ('BUF1', S['BUF1'])):
        for k, g in enumerate(digits):
            for row in range(5):
                for j in range(2):
                    want = d[S['FONT'] + g * 10 + row * 2 + j] | 0xC0
                    if d[base + row * 32 + 2 * k + j] != want:
                        msgs.append('%s digit %d (=%d) differs' % (name, k, g)); break
                else: continue
                break
            else: continue
    score = int(''.join(map(str, digits)))
    if run == 'plain' and score == 0: msgs.append('no points scored in 45 s')
    if run == 'high' and not (score < 20000 and score > 0): msgs.append('did not roll over: %06d' % score)
    print('  %-5s run: score %06d on screen%s' % (run, score, ' -- ' + '; '.join(sorted(set(msgs))) if msgs else ', matches'))
    ok &= not msgs
sys.exit(0 if ok else 1)
PY
}

# eyes: on every level, from every tile a ghost can be on, following the way-home map the
# engine loaded (never into a wall, doors allowed) gets the eyes to the house tile.
check_eyes() {
  O=$D/eyes; rm -rf "${O:?}"; mkdir -p "$O"
  WS=$(s WSPACE); LV=$(s LEVEL); FR=$(s FRAME); l=0
  while [ $l -lt 40 ]; do
    byte $l > "$O/lv$l.bin"
    emu c2 -load-fd0 "$DSK" -input-script "$WORK/start.txt" \
      -trap "xpc=0x0$WS" -trap-range 1-1 -trap-load "$O/lv$l.bin,format=raw,addr=0x0$LV" \
      -trap "xpc=0x0$FR" -trap-range 1-1 -trap-ram "$O/r$l.ram" -trap-timeout 0 -timeout 60 >/dev/null 2>&1 &
    l=$((l + 1))
  done
  wait
  python3 -I - "$O" "$SYM" <<'PY' && say PASS "eyes: from every tile of every level the way-home map leads home" || say FAIL "eyes: a way-home map is wrong"
import sys
o = sys.argv[1]
S = {l.split()[0]: int(l.split('$')[1], 16) for l in open(sys.argv[2]) if len(l.split()) >= 3 and l.split()[1] == 'EQU'}
D = [(1, 0), (-1, 0), (0, -1), (0, 1)]                  # right, left, up, down
def step(c, r, d):
    c = (c + D[d][0]) & 15; r += D[d][1]
    return c, (14 if r < 0 else 0 if r > 14 else r)
bad = []
tiles = 0
for l in range(40):
    ram = open('%s/r%d.ram' % (o, l), 'rb').read()
    mp = ram[S['MAP']:S['MAP'] + 240]
    home = (ram[S['HOMEC']], ram[S['HOMER']])
    hdr = ram[S['LVP'] and (ram[S['LVP']] * 256 + ram[S['LVP'] + 1]):][:21]
    ptr = hdr[19] * 256 + hdr[20]
    table = ram[ptr:ptr + 60]
    seen, todo = {home}, [home]                           # every tile ghosts can reach from home
    while todo:
        c, r = todo.pop()
        for d in range(4):
            n = step(c, r, d)
            if mp[n[1] * 16 + n[0]] != 1 and n not in seen: seen.add(n); todo.append(n)
    for (c, r) in seen:
        pos, ok = (c, r), False
        for _ in range(300):
            if pos == home: ok = True; break
            i = pos[1] * 16 + pos[0]
            d = (table[i >> 2] >> ((i & 3) * 2)) & 3
            pos = step(pos[0], pos[1], d)
            if mp[pos[1] * 16 + pos[0]] == 1: break
        tiles += 1
        if not ok: bad.append((l + 1, (c, r)))
print('  %d tiles checked on 40 levels, %d failures%s' % (tiles, len(bad), (': ' + str(bad[:6])) if bad else ''))
sys.exit(1 if bad else 0)
PY
}

# basic: after BREAK, BASIC works as it did before the game: a typed program lists and runs.
# (The game's screens and background sit where BASIC keeps its program; QUIT puts back the
# empty-program marker. Without it LIST showed garbage and RUN gave ?SN ERROR.)
check_basic() {
  O=$D/basic; rm -rf "${O:?}"; mkdir -p "$O"
  python3 -I - "$O/in.txt" <<'PY'
import sys
L = ['wait 3000', 'type LOADM"PAKFAN":EXEC\\r', 'wait 8000', 'key space down', 'wait 300', 'key space up', 'wait 12000',
     'key break down', 'wait 300', 'key break up', 'wait 1500',
     'type 10 PRINT "HELLO";2*21\\r', 'wait 500', 'type 20 FOR I=1 TO 3:PRINT I:NEXT\\r', 'wait 500', 'type RUN\\r', 'wait 3000']
open(sys.argv[1], 'w').write('\n'.join(L) + '\n')
PY
  for m in c2 c3; do
    [ $m = c3 ] && ! have3 && { echo "SKIP basic on CoCo 3 (no coco3.rom)"; continue; }
    emu $m -load-fd0 "$DSK" -input-script "$O/in.txt" -trap "seconds=42" -trap-ram "$O/$m.ram" -trap-timeout 1 -timeout 100 >/dev/null 2>&1 &
  done
  wait
  for m in c2 c3; do
    [ -f "$O/$m.ram" ] || continue
    python3 -I - "$O/$m.ram" $([ $m = c3 ] && echo 458752 || echo 0) <<'PY' && say PASS "basic: $m after BREAK, a typed program runs (HELLO 42, then 1 2 3)" || say FAIL "basic: $m after BREAK, a typed program does not run"
import sys
d = open(sys.argv[1], 'rb').read()[int(sys.argv[2]) + 0x400:int(sys.argv[2]) + 0x600]
rows = [''.join(chr((c & 0x3F) + (64 if (c & 0x3F) < 32 else 0)) for c in d[r * 32:r * 32 + 32]).strip() for r in range(16)]
i = [k for k, r in enumerate(rows) if r == 'HELLO 42']
ok = bool(i) and rows[i[-1] + 1:i[-1] + 4] == ['1', '2', '3']
if not ok: print('  screen:', ' | '.join(r for r in rows if r)[:200])
sys.exit(0 if ok else 1)
PY
  done
}

# tune: the speaker output of the intro tune (the mix, after the sound-source select and enable
# bits) is in tune: every note's pitch within 2% of the table (tools/tunecheck.py), on a CoCo 2,
# a CoCo 3, and a CoCo 3 left at high speed. Needs numpy.
check_tune() {
  python3 -c 'import numpy' 2>/dev/null || { echo "SKIP tune (no numpy)"; return; }
  O=$D/tune; rm -rf "${O:?}"; mkdir -p "$O"
  SB=$(s STARTMUS); MO=$(s MSGOFF)
  for sc in c2:normal c3:normal c3:fast; do
    m=${sc%%:*}; v=${sc##*:}
    [ $m = c3 ] && ! have3 && continue
    P=$(px $m)
    python3 -I - "$O/$m$v.txt" $v <<'PY'
import sys
pre = 'type POKE 65497,0\\r\nwait 500\n' if sys.argv[2] == 'fast' else ''
open(sys.argv[1], 'w').write('wait 3000\n' + pre + 'type LOADM"PAKFAN":EXEC\\r\nwait 8000\nkey space down\nwait 300\nkey space up\nwait 12000\n')
PY
    # STARTMUS is where the start music is called; MSGOFF follows it
    emu $m -load-fd0 "$DSK" -input-script "$O/$m$v.txt" -audio-record-source mix \
      -trap "xpc=0x$P$SB" -trap-range 1-1 -trap-audio-start "$O/$m$v.wav" \
      -trap "xpc=0x$P$MO" -trap-range 1-1 -trap-audio-stop -trap "seconds=36" -trap-timeout 1 -timeout 80 >/dev/null 2>&1 &
  done
  wait
  for sc in c2:normal c3:normal c3:fast; do
    m=${sc%%:*}; v=${sc##*:}
    [ -f "$O/$m$v.wav" ] || { [ $m = c3 ] && ! have3 && continue; say FAIL "tune: $m $v: no sound recorded"; continue; }
    r=$(python3 "$HERE/tools/audiocheck.py" "$O/$m$v.wav" "$HERE/assets/audio/synth/snd00.bin" 2>&1 | tail -n 1)
    if python3 "$HERE/tools/audiocheck.py" "$O/$m$v.wav" "$HERE/assets/audio/synth/snd00.bin" >/dev/null 2>&1; then say PASS "tune: $m $v: start music, the pitch of every tick is the stream's:$r"; else say FAIL "tune: $m $v: $(echo "$r" | cut -c1-160)"; fi
  done
}

# sound: eating dots makes sound (the waka): in 8 s of autopilot play, at least a quarter of the
# 100 ms windows of the speaker mix are loud.
check_sound() {
  python3 -c 'import numpy' 2>/dev/null || { echo "SKIP sound (no numpy)"; return; }
  O=$D/sound; rm -rf "${O:?}"; mkdir -p "$O"
  botbuild || { say FAIL "sound: the autopilot build failed"; return; }
  B=$D/bot; SY=$B/pakfan.sym; SX=$(s MSGOFF "$SY"); WS=$(s WSPACE "$SY"); BS=$(s BSEED "$SY")
  byte 1 > "$O/sd.bin"
  emu c2 -load-fd0 "$B/PAKFAN.DSK" -input-script "$WORK/start.txt" -audio-record-source mix \
    -trap "xpc=0x0$WS" -trap-range 1-1 -trap-load "$O/sd.bin,format=raw,addr=0x0$BS" \
    -trap "xpc=0x0$SX" -trap-range 1-1 -trap-audio-start "$O/play.wav" \
    -trap "seconds=24" -trap-audio-stop -trap-timeout 1 -timeout 60 >/dev/null 2>&1
  python3 -I - "$O/play.wav" <<'PY' && say PASS "sound: eating dots is audible" || say FAIL "sound: eating dots is (nearly) silent"
import sys, wave
import numpy as np
w = wave.open(sys.argv[1]); r = w.getframerate()
x = np.frombuffer(w.readframes(w.getnframes()), dtype='<i2').astype(float); x -= np.median(x)
win = int(0.1 * r); n = len(x) // win
rms = np.array([np.sqrt((x[i * win:(i + 1) * win] ** 2).mean()) for i in range(n)])
loud = (rms > 300).sum()
print('  %.1f s of play: %d of %d windows loud (%.0f%%)' % (len(x) / r, loud, n, 100.0 * loud / max(n, 1)))
sys.exit(0 if n >= 40 and loud >= 0.25 * n else 1)
PY
}

# loader: RUN"PAKFAN" loads the logo, the audio engine (in 12 pieces, each copied up through all-RAM
# mode) and the game: the engine must be in the upper 32K byte for byte, and the game must have
# found it (HAVEAUD = 1). On a CoCo 2 and a CoCo 3.
check_loader() {
  O=$D/loader; rm -rf "${O:?}"; mkdir -p "$O"
  HV=$(s HAVEAUD)
  printf 'wait 3000\ntype RUN"PAKFAN"\\r\nwait 60000\n' > "$O/in.txt"
  for m in c2 c3; do
    [ $m = c3 ] && ! have3 && { echo "SKIP loader on CoCo 3 (no coco3.rom)"; continue; }
    # not emu: the engine must come from the loader, not from a test shortcut
    case $m in c2) mach="-machine cocous -ram 64";; c3) mach="-machine coco3";; esac
    ( timeout 900 "$XROAR" -headless -rompath "$ROMS" $mach -load-fd0 "$DSK" -input-script "$O/in.txt" \
        -trap "seconds=70" -trap-ram "$O/$m.ram" -trap-timeout 1 -timeout 120 >/dev/null 2>&1 ) &
  done
  wait
  for m in c2 c3; do
    [ $m = c3 ] && ! have3 && continue
    b=0; [ $m = c3 ] && b=$((0x70000))
    if python3 -I - "$O/$m.ram" "$HERE/dist/AUDIO.RAW" $b $((0x$HV)) <<'PY'
import sys
d = open(sys.argv[1], 'rb').read(); a = open(sys.argv[2], 'rb').read(); b, hv = int(sys.argv[3]), int(sys.argv[4])
same = d[b + 0x8000:b + 0x8000 + len(a)] == a
print('  engine in the upper 32K byte for byte: %s, HAVEAUD=%d' % (same, d[b + hv]))
sys.exit(0 if same and d[b + hv] == 1 else 1)
PY
    then say PASS "loader: $m: RUN\"PAKFAN\" puts the engine in the upper 32K and the game finds it"
    else say FAIL "loader: $m: the engine is not (all) there after RUN\"PAKFAN\""; fi
  done
}

[ -f "$SYM" ] && [ -f "$DSK" ] || { echo "build first: ./build.sh"; exit 2; }
[ $# -gt 0 ] || set -- break basic fuzz speed tune orch sound lap menu joy score eyes overrun protect loader
for c in "$@"; do
  case $c in break|basic|fuzz|speed|tune|orch|sound|lap|menu|joy|score|eyes|overrun|protect|loader) "check_$c";; *) echo "unknown check: $c"; exit 2;; esac
done
exit $FAILED
