# Shared settings for the emulator tests -- source it, do not run it.
#   XROAR  path to xroar-dev (https://github.com/milliluk/xroar-dev)
#   ROMS   folder holding bas13.rom, extbas11.rom, disk11.rom (not in this repo: copyright)
XROAR=${XROAR:-xroar-dev}
ROMS=${ROMS:?set ROMS to the folder with the CoCo 2 ROMs}
HERE=$(cd "$(dirname "$0")/.." && pwd)
WORK=${WORK:-$HERE/dist/test}
mkdir -p "$WORK"
# sym NAME [SYMFILE]: hex address of a label from an lwasm --symbol-dump
sym() { grep "^$1 " "${2:-$HERE/dist/pacfan.sym}" | sed 's/.*\$//'; }
# A CoCo 2, 32K, Disk BASIC. Traps: xpc= is a physical address (5 hex digits), seconds=
# is emulated time. NB: -trap-range N means "from hit N on"; use N-N for one hit.
# A screenshot name may or may not get a number appended (shot.png -> shot1.png):
# glob for it.
coco() { timeout 1200 "$XROAR" -headless -rompath "$ROMS" -machine cocous -ram 32 "$@"; }
# keystrokes: LOADM the game and press SPACE at the title
printf 'wait 3000\ntype LOADM"PACFAN":EXEC\\r\nwait 8000\nkey space down\nwait 300\nkey space up\nwait 2000000\n' > "$WORK/start.txt"
