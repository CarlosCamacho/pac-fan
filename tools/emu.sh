# Shared settings for the emulator tests -- source it, do not run it.
#   XROAR  path to xroar-dev (https://github.com/milliluk/xroar-dev)
#   ROMS   folder holding bas13.rom, extbas11.rom, disk11.rom (not in this repo: copyright)
XROAR=${XROAR:-xroar-dev}
ROMS=${ROMS:?set ROMS to the folder with the CoCo 2 ROMs}
HERE=$(cd "$(dirname "$0")/.." && pwd)
WORK=${WORK:-$HERE/dist/test}
mkdir -p "$WORK"
# sym NAME [SYMFILE]: hex address of a label from an lwasm --symbol-dump
sym() { grep "^$1 " "${2:-$HERE/dist/pakfan.sym}" | sed 's/.*\$//'; }
# A CoCo 2, 32K, Disk BASIC. Traps: xpc= is a physical address (5 hex digits), seconds=
# is emulated time. NB: -trap-range N means "from hit N on"; use N-N for one hit.
# A screenshot name may or may not get a number appended (shot.png -> shot1.png):
# glob for it.
# The game plays its sounds from an engine in the upper 32K, which only RUN"PAKFAN" loads; the tests
# put it there directly (dist/AUDIO.RAW, from mkpak.py) so they need not wait for the loader.
# 64K RAM; on a CoCo 3 the same bytes sit at physical $78000.
AUDRAW=${AUDRAW:-$HERE/dist/AUDIO.RAW}
coco() { timeout 1200 "$XROAR" -headless -rompath "$ROMS" -machine cocous -ram 64 -load-ram "$AUDRAW,addr=0x8000" "$@"; }
# keystrokes: LOADM the game and press SPACE at the title
printf 'wait 3000\ntype LOADM"PAKFAN":EXEC\\r\nwait 8000\nkey space down\nwait 300\nkey space up\nwait 2000000\n' > "$WORK/start.txt"
