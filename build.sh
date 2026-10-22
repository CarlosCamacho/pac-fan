#!/bin/sh
# Build PACFAN.DSK. Needs LWTOOLS 4.24 or 4.25 (same bytes) and python3.
set -e
LWASM=${LWASM:-lwasm}
$LWASM --version | grep -qE "4\.2[45]" || { echo "need lwasm 4.24 or 4.25 (set LWASM=)"; exit 1; }
python3 gen.py
mkdir -p dist
$LWASM -9 --format=decb --list=dist/pacfan.lst --symbol-dump=dist/pacfan.sym -o dist/PACFAN.BIN pacfan.asm
python3 mkdsk.py dist/PACFAN.DSK dist/PACFAN.BIN
