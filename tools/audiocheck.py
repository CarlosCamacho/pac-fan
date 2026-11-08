#!/usr/bin/env python3
"""Does a recording of the speaker mix play the sound stream it should?

    python3 tools/audiocheck.py RECORDING.wav STREAM.bin [TICKS_OFFSET_MAX]

STREAM.bin is one of assets/audio/synth/sndNN.bin (9 bytes a tick: three voices of phase step,
wave << 4 | volume). The recording starts at the call that plays it. Each tick (a video field)
every voice the stream has at a volume of 5 or more must show as a clear peak of the recording's
spectrum (80 ms around the tick) within 4% of its pitch; 85% of the ticks must, allowing the
recording to start a few ticks late. Prints the figures and
exits 0 on a pass.
"""
import sys
import wave

import numpy as np

CPU = 14318180 / 16
LOOP_CYCLES = 111
RATE = CPU / LOOP_CYCLES

w = wave.open(sys.argv[1])
sr = w.getframerate()
x = np.frombuffer(w.readframes(w.getnframes()), dtype='<i2').astype(float)
if w.getnchannels() > 1:
    x = x[::w.getnchannels()]
s = open(sys.argv[2], 'rb').read()
maxoff = int(sys.argv[3]) if len(sys.argv) > 3 else 12
n = len(s) // 9
hop, win = sr / 60.0, int(0.08 * sr)


def present(seg, f):
    """Is there a clear peak of the spectrum at f (within 4% or 10 Hz)?"""
    sp = np.abs(np.fft.rfft(seg * np.hanning(len(seg)), 8 * len(seg)))
    fr = np.fft.rfftfreq(8 * len(seg), 1 / sr)
    band = (abs(fr - f) <= max(0.04 * f, 10))
    ref = np.median(sp[(fr > 100) & (fr < 4000)])
    return sp[band].max() >= 10 * ref


best = None
for off in range(-2, maxoff):
    good = tot = 0
    for k in range(n):
        want = [(s[k * 9 + v * 3] * 256 + s[k * 9 + v * 3 + 1]) * RATE / 65536
                for v in range(3) if (s[k * 9 + v * 3 + 2] & 15) >= 5]
        if not want:
            continue
        i = int((k + off) * hop) - win // 2 + int(hop / 2)
        if i < 0 or i + win > len(x):
            continue
        tot += 1
        if all(present(x[i:i + win], t) for t in want):
            good += 1
    if best is None or good > best[0]:
        best = (good, tot, off)
good, tot, off = best
print('  %d of %d ticks have every voice at the pitch the stream says (recording %d ticks late); %.1f s recorded, stream %.1f s' % (
    good, tot, off, len(x) / sr, n / 60.0))
sys.exit(0 if tot >= 20 and good >= 0.85 * tot else 1)
