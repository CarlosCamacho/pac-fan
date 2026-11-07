#!/usr/bin/env python3
"""Is the intro tune in tune? Compare the pitch of every note in a DAC recording with the table.

    python3 tools/tunecheck.py TUNE.WAV tables.inc [CPU_HZ]

The tune is two sawtooth voices; a record is (samples, step1, step2) and a voice's pitch is
step / 65536 * SAMPLE_RATE, where the sample rate is the CPU clock over the 79-cycle loop in
SAWPLAY (11,328 Hz on an NTSC machine, CPU_HZ 894886). Needs numpy. For each note long enough
to measure, both voices are looked for within 6% of the expected pitch; the report gives the
worst error. Exit status 1 if a voice is missing or off by more than 2%.
"""
import sys
import wave

import numpy as np

if len(sys.argv) < 3:
    sys.exit(__doc__)
wav, tables = sys.argv[1], sys.argv[2]
cpu = float(sys.argv[3]) if len(sys.argv) > 3 else 894886.0
FS = cpu / 79.0                                      # the DAC rate SAWPLAY writes at

lines = open(tables).read().splitlines()
i = [k for k, l in enumerate(lines) if l.startswith('TUNE')][0]
words = []
for l in lines[i + 1:]:
    l = l.strip()
    if not l.startswith('fdb'):
        break
    words += [int(x.strip().lstrip('$'), 16) for x in l[3:].split(',')]
notes = []
for k in range(0, len(words) - 2, 3):
    if words[k] == 0:
        break
    notes.append(tuple(words[k:k + 3]))

w = wave.open(wav)
rate = w.getframerate()
x = np.frombuffer(w.readframes(w.getnframes()), dtype='<i2').astype(float)
x -= x.mean()
ideal = sum(n[0] for n in notes) / FS
scale = (len(x) / rate) / ideal                       # the recording is a little longer: the BREAK poll between notes

t = 0.0
worst, missing, checked = 0.0, [], 0
for n, (count, s1, s2) in enumerate(notes):
    dur = count / FS
    a, b = (t + 0.2 * dur) * scale, (t + 0.8 * dur) * scale            # the middle of the note
    t += dur
    if dur < 0.05:
        continue
    seg = x[int(a * rate):int(b * rate)]
    if len(seg) < 512:
        continue
    seg = seg * np.hanning(len(seg))
    nfft = 1 << 15
    spec = np.abs(np.fft.rfft(seg, nfft))
    freqs = np.fft.rfftfreq(nfft, 1.0 / rate)
    floor = np.median(spec[(freqs > 50) & (freqs < 4000)]) + 1e-9
    for v, step in ((1, s1), (2, s2)):
        if step == 0:
            continue
        f = step / 65536.0 * FS
        band = (freqs > f * 0.94) & (freqs < f * 1.06)
        j = np.argmax(np.where(band, spec, 0))
        checked += 1
        err = (freqs[j] - f) / f
        if spec[j] < 8 * floor:
            missing.append((n, v, round(f)))
        else:
            worst = max(worst, abs(err))
print('%d notes in the table (%.2f s); %d voices measured; worst pitch error %.2f%%; not found: %s' % (
    len(notes), ideal, checked, 100 * worst, missing or 'none'))
sys.exit(1 if missing or worst > 0.02 else 0)
