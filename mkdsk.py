#!/usr/bin/env python3
"""RS-DOS (Disk BASIC) disk images: write one, read files back.

    python3 tools/mkdsk.py OUT.DSK FILE.BIN[=NAME.EXT] ...   # new image
    python3 tools/mkdsk.py --list IMAGE.DSK                   # directory

A 35-track, single-sided image (18 sectors of 256 bytes a track, 161,280
bytes), laid out as DSKINI leaves a disk: track 17 holds the FAT (sector 2)
and the directory (sectors 3-11); the other 34 tracks are 68 granules of 9
sectors. Files ending .BIN are stored as machine-language (type 2, binary),
anything else as data (type 1). Files are read back and compared before
the image is written.
"""
import os, sys

TRACKS, SECTORS, SECSIZE = 35, 18, 256
DIRTRACK, GRANULES, GRANSECS = 17, 68, 9
GRANSIZE = GRANSECS * SECSIZE

def _offset(track, sector):                 # sector numbers start at 1
    return (track * SECTORS + sector - 1) * SECSIZE

def _granule_offset(g):
    track = g // 2 if g < 2 * DIRTRACK else g // 2 + 1   # (track 17 skipped)
    return _offset(track, 1 + (g % 2) * GRANSECS)

def _split_name(name):
    base, _, ext = name.upper().partition('.')
    assert 1 <= len(base) <= 8 and len(ext) <= 3, 'not an 8.3 name: %s' % name
    return base.ljust(8).encode('ascii'), ext.ljust(3).encode('ascii')

def make_image(files):
    """files: [(name 'NAME.EXT', data)] -> image bytes."""
    img = bytearray(b'\xFF' * (TRACKS * SECTORS * SECSIZE))
    fat = bytearray(SECSIZE); fat[:GRANULES] = b'\xFF' * GRANULES
    directory = bytearray(b'\xFF' * (9 * SECSIZE))
    free = list(range(GRANULES))
    assert len(files) <= 72, 'too many files'
    for n, (name, data) in enumerate(files):
        assert data, 'empty file %s' % name
        grans = -(-len(data) // GRANSIZE)
        assert grans <= len(free), '%s does not fit (%d granules, %d free)' % (name, grans, len(free))
        chain = [free.pop(0) for _ in range(grans)]
        for k, g in enumerate(chain):
            part = data[k * GRANSIZE:(k + 1) * GRANSIZE]
            o = _granule_offset(g); img[o:o + len(part)] = part
            fat[g] = chain[k + 1] if k + 1 < grans else 0xC0 + -(-len(part) // SECSIZE)
        last = len(data) % SECSIZE or SECSIZE
        base, ext = _split_name(name)
        ftype = 2 if ext == b'BIN' else (0 if ext == b'BAS' else 1)
        ascii = 0xFF if ext in (b'BAS', b'TXT') else 0x00
        entry = base + ext + bytes([ftype, ascii, chain[0], last >> 8, last & 255]) + bytes(16)
        directory[n * 32:n * 32 + 32] = entry
    o = _offset(DIRTRACK, 2); img[o:o + SECSIZE] = fat
    o = _offset(DIRTRACK, 3); img[o:o + len(directory)] = directory
    return bytes(img)

def read_image(img):
    """{'NAME.EXT': data} from an image."""
    assert len(img) == TRACKS * SECTORS * SECSIZE, 'not a 35-track RS-DOS image'
    fat = img[_offset(DIRTRACK, 2):_offset(DIRTRACK, 2) + GRANULES]
    out = {}
    for n in range(72):
        e = img[_offset(DIRTRACK, 3) + n * 32:_offset(DIRTRACK, 3) + n * 32 + 32]
        if e[0] == 0xFF: break                 # end of the directory
        if e[0] == 0x00: continue              # deleted
        name = e[:8].decode().rstrip() + '.' + e[8:11].decode().rstrip()
        last = (e[14] << 8) | e[15]; g = e[13]; data = bytearray(); seen = set()
        while True:
            assert g < GRANULES and g not in seen, 'bad FAT chain in %s' % name
            seen.add(g); nxt = fat[g]; o = _granule_offset(g)
            if nxt >= 0xC0:
                secs = nxt - 0xC0
                data += img[o:o + (secs - 1) * SECSIZE + last]; break
            data += img[o:o + GRANSIZE]; g = nxt
        out[name] = bytes(data)
    return out

def write_image(path, files):
    img = make_image(files)
    back = read_image(img)
    for name, data in files:
        assert back[name.upper()] == data, '%s does not read back' % name
    open(path, 'wb').write(img)
    return img

if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--list':
        for name, data in read_image(open(sys.argv[2], 'rb').read()).items():
            print('%-12s %7d bytes' % (name, len(data)))
        sys.exit(0)
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    files = []
    for arg in sys.argv[2:]:
        src, _, name = arg.partition('=')
        files.append((name or os.path.basename(src), open(src, 'rb').read()))
    write_image(sys.argv[1], files)
    print('wrote', sys.argv[1])
