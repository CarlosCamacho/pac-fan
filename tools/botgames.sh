#!/bin/sh
# Difficulty measurement: build the -DBOT=1 autopilot version and play SEEDS games on
# every level (in the current play order), each from a fresh game. Each game ends at the
# level's clear or at game over; results go to dist/test/bot/. Then: python3 tools/rank.py
#   tools/botgames.sh [SEEDS]      (default 10; 40 levels x 10 = 400 games, ~1 hour)
. "$(dirname "$0")/emu.sh"
SEEDS=${1:-10}
B=$HERE/dist/bot; O=$WORK/bot; mkdir -p "$B" "$O"; rm -f "$O"/end_*.ram
LWASM=${LWASM:-lwasm}
$LWASM -9 -DBOT=1 --format=decb --symbol-dump="$B/pacfan.sym" -o "$B/PACFAN.BIN" "$HERE/pacfan.asm"
python3 "$HERE/mkdsk.py" "$B/PACFAN.DSK" "$B/PACFAN.BIN"
S="$B/pacfan.sym"
WS=$(sym WSPACE $S); LV=$(sym LEVEL $S); RN=$(sym RND $S); BS=$(sym BSEED $S); LC=$(sym LCLEAR $S); GO=$(sym GOVER $S)
N=$(grep '^NLEV ' "$HERE/tables.inc" | awk '{print $3}')
sd=1
while [ $sd -le $SEEDS ]; do
  L=0
  while [ $L -lt $N ]; do
    printf "\\$(printf %03o $L)" > "$O/lv${L}_$sd.bin"; printf "\\$(printf %03o $sd)" > "$O/sd${L}_$sd.bin"
    coco -load-fd0 "$B/PACFAN.DSK" -input-script "$WORK/start.txt" \
      -trap "xpc=0x0$WS" -trap-range 1-1 -trap-load "$O/lv${L}_$sd.bin,format=raw,addr=0x$LV" \
      -trap "xpc=0x0$WS" -trap-range 1-1 -trap-load "$O/sd${L}_$sd.bin,format=raw,addr=0x$RN" \
      -trap "xpc=0x0$WS" -trap-range 1-1 -trap-load "$O/sd${L}_$sd.bin,format=raw,addr=0x$BS" \
      -trap "xpc=0x0$LC" -trap-range 1-1 -trap-ram "$O/end_${L}_${sd}_clear.ram" -trap-timeout 0 \
      -trap "xpc=0x0$GO" -trap-range 1-1 -trap-ram "$O/end_${L}_${sd}_over.ram" -trap-timeout 0 \
      -timeout 900 >/dev/null 2>&1 &
    L=$((L+1))
  done
  wait; sd=$((sd+1))
done
echo "games done: $(ls "$O"/end_*.ram | wc -l)"
