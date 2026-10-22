#!/bin/sh
# For every level, start a game on it in the emulator, dump RAM at the first frame and
# compare the background the engine built with gen.py's (dist/expected_bg.pickle).
# Also writes dist/test/sheet.png, every level as drawn. Run after ./build.sh.
. "$(dirname "$0")/emu.sh"
N=$(grep '^NLEV ' "$HERE/tables.inc" | awk '{print $3}')
WS=$(sym WSPACE); LV=$(sym LEVEL); FR=$(sym FRAME)
i=0
while [ $i -lt $N ]; do
  printf "\\$(printf %03o $i)" > "$WORK/lv$i.bin"
  coco -load-fd0 "$HERE/dist/PACFAN.DSK" -input-script "$WORK/start.txt" \
    -trap "xpc=0x0$WS" -trap-range 1-1 -trap-load "$WORK/lv$i.bin,format=raw,addr=0x$LV" \
    -trap "xpc=0x0$FR" -trap-range 1-1 -trap-ram "$WORK/bg$i.ram" -trap-screenshot "$WORK/shot${i}_.png" \
    -trap-timeout 1 >/dev/null 2>&1 &
  i=$((i+1))
done
wait
python3 - "$WORK" "$N" "$HERE" <<'PY'
import pickle, sys, os
work, n, here = sys.argv[1], int(sys.argv[2]), sys.argv[3]
exp = pickle.load(open(os.path.join(here, "dist", "expected_bg.pickle"), "rb"))
bad = [i + 1 for i in range(n) if open("%s/bg%d.ram" % (work, i), "rb").read()[0x2600 + 192:0x2600 + 3072] != exp[i]]
print("levels checked: %d  mismatches: %s" % (n, bad or "none"))
try:
    from PIL import Image
    import glob
    ims = [Image.open(sorted(glob.glob("%s/shot%d_*.png" % (work, i)))[-1]).convert("RGB").crop((60, 40, 580, 430)).resize((260, 195)) for i in range(n)]
    s = Image.new("RGB", (5 * 262, ((n + 4) // 5) * 197), "white")
    for k, im in enumerate(ims): s.paste(im, ((k % 5) * 262, (k // 5) * 197))
    s.save("%s/sheet.png" % work); print("wrote", "%s/sheet.png" % work)
except ImportError:
    pass
sys.exit(1 if bad else 0)
PY
