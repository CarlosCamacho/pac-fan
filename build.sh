#!/bin/sh
# Build PAKFAN.DSK (the game, and the loader that shows the logo while it loads). Needs LWTOOLS 4.24 or 4.25 (same bytes) and python3.
set -e
LWASM=${LWASM:-lwasm}
$LWASM --version | grep -qE "4\.2[45]" || { echo "need lwasm 4.24 or 4.25 (set LWASM=)"; exit 1; }
python3 gen.py
python3 tools/mkabout.py        # the story pages and the font for the engine
mkdir -p dist
$LWASM -9 --format=decb --list=dist/pakfan.lst --symbol-dump=dist/pakfan.sym -o dist/PAKFAN.BIN pakfan.asm
$LWASM -9 --format=decb --list=dist/audio.lst --symbol-dump=dist/audio.sym -o dist/AUDIO.BIN audio.asm
$LWASM -9 --format=decb -o dist/COPIER.BIN copier.asm
python3 tools/mkpak.py          # the loader, the logo screen, the pieces, and the disk image
