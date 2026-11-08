#!/usr/bin/env python3
"""Turn the sound designs (assets/audio/build_audio.py) into the data of the 3-voice synth.

    python3 tools/mksynth.py [--check]

Needs numpy. Writes assets/audio/synth/ : wavetbl.bin (the wave tables, scaled for every
volume), snd00.bin ... (one tick stream a sound) and audio_data.inc (labels and the directory)
for audio.asm. The build itself does not need numpy: it uses these files.

The designs are lists of notes, sweeps and bursts of noise. Each is sampled once a video
field (the synth steps once a field) and given one of three voices: for every tick a voice has
a phase increment (16 bits) and a byte wave<<4 | volume. A tick is 9 bytes (three voices).

Voices: long jingles and the death use all three; effects that play over the siren use voices
1 and 2; the loops that play under everything (siren, fright, eyes) use voices 0 and 1.
"""
import os
import sys
import types

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, 'assets', 'audio', 'synth')

TICK = 1.0 / 60
LOOP_CYCLES = 111                      # audio.asm sample loop, measured in xroar-dev (a 1 kHz test tone came out at 1020 Hz including the tick overhead)
CPU_HZ = 14318180 / 16
RATE = CPU_HZ / LOOP_CYCLES            # samples a second: every pitch is worked out from this
SUMVOL = 30                            # most volume (all voices together, 15 = half the DAC's swing)

# id, name, class, voices
SOUNDS = [
    (0, 'start_music', 'block', (0, 1, 2)),
    (1, 'intermission_music', 'block', (0, 1, 2)),
    (2, 'coin_insert', 'block', (0, 1, 2)),
    (3, 'death', 'block', (0, 1, 2)),
    (4, 'eat_ghost', 'block', (0, 1, 2)),
    (5, 'extra_life', 'sfx', (1, 2)),
    (6, 'eat_dot_1', 'sfx', (1, 2)),
    (7, 'eat_dot_2', 'sfx', (1, 2)),
    (8, 'eat_fruit', 'sfx', (1, 2)),
    (9, 'fruit_bounce', 'sfx', (1, 2)),
    (10, 'siren_1', 'loop', (0, 1)),
    (11, 'siren_2', 'loop', (0, 1)),
    (12, 'siren_3', 'loop', (0, 1)),
    (13, 'siren_4', 'loop', (0, 1)),
    (14, 'siren_5', 'loop', (0, 1)),
    (15, 'power_pellet_fright', 'loop', (0, 1)),
    (16, 'ghost_eyes_return', 'loop', (0, 1)),
]
WAVES = ['pulse', 'triangle', 'softsquare', 'bell', 'saw', 'sin']      # wave numbers 0-5; 6, 7 mixed; 8 noise
LOOP_GAIN = 0.6                        # the loops sit under the effects


def load_designs():
    """Import build_audio.py with a Composer that records the events instead of playing them."""
    sys.modules.setdefault('scipy', types.ModuleType('scipy'))
    sig = types.ModuleType('scipy.signal')
    sig.resample_poly = None
    sys.modules['scipy.signal'] = sig
    sys.path.insert(0, os.path.join(ROOT, 'assets', 'audio'))
    import build_audio as B

    class Rec:
        def __init__(self, duration, seed=0):
            self.duration, self.ev = duration, []

        def note(self, start, dur, pitch, amp=.35, kind='pulse', attack=.003, release=.025, wobble=0.0, detune=0.0):
            f = B.hz(pitch) if isinstance(pitch, str) else pitch
            self.ev.append(dict(t=start, d=dur, f0=f * (1 + detune), f1=f * (1 + detune), amp=amp, kind=kind,
                                att=attack, rel=release, shape='linear', twist=0.0, echo=False))

        def sweep(self, start, dur, fstart, fend, amp=.35, kind='pulse', shape='linear', attack=.002, release=.045,
                  twist=0.0, echo=False):
            self.ev.append(dict(t=start, d=dur, f0=fstart, f1=fend, amp=amp, kind=kind, att=attack, rel=release,
                                shape=shape, twist=twist, echo=echo))

        def hiss(self, start, dur, amp=.18, bright=False):
            self.ev.append(dict(t=start, d=dur, f0=0, f1=0, amp=amp * 0.6, kind='noise', att=.0003, rel=.025,
                                shape='linear', twist=0.0, echo=False, decay=20))

        def thump(self, start, amp=.25):
            self.sweep(start, .105, 155, 51, amp, 'triangle', release=.02)

        def signal(self):
            return self.ev, self.duration

    B.Composer = Rec
    return B


def osc_peak(B, kind):
    ph = np.linspace(0, 2 * np.pi, 4096, endpoint=False)
    return float(np.max(np.abs(B.oscillator(ph, kind)))) if kind != 'noise' else 0.6


def wave_tables(B, fine=False):
    """9 waves of 32 samples (unit peak), mapped to signed bytes for every volume: (wave<<4 | vol) * 32 bytes."""
    xs = np.linspace(0, 2 * np.pi, 32, endpoint=False)
    waves = [B.oscillator(xs, n) for n in WAVES]
    waves.append(.65 * B.oscillator(xs, 'triangle') + .35 * B.oscillator(xs * 2, 'saw'))
    waves.append(.8 * np.sin(xs) + .22 * np.cos(xs * 3))
    rng = np.random.default_rng(5)
    waves.append(rng.uniform(-1, 1, 32))
    tbl = bytearray(144 * 32)
    for w, wave in enumerate(waves):
        wave = wave / np.max(np.abs(wave))
        wave = wave - wave.mean() * (w != 8)
        wave = wave / np.max(np.abs(wave))
        for vol in range(16):
            for i in range(32):
                if fine:                                                 # Orchestra-90: 8 bits, every step
                    v = int(round(wave[i] * 64 * vol / 15))
                else:
                    v = int(round(wave[i] * 64 * vol / 15 / 4)) * 4      # the 6-bit DAC: a multiple of 4, -64 .. 64
                tbl[(w << 4 | vol) * 32 + i] = v & 255
    return bytes(tbl)


def env(t, dur, att, rel):
    up = min(1.0, t / max(att, 1e-6))
    down = min(1.0, max(0.0, (dur - t) / max(rel, 1e-6)))
    return up * down


def comp_at(B, e, t0, t1):
    """The loudness and pitch of an event over one tick, or None."""
    a, b = max(t0, e['t']), min(t1, e['t'] + e['d'])
    if b <= a:
        return None
    cover = (b - a) / (t1 - t0)
    tm = (a + b) / 2 - e['t']
    frac = tm / e['d']
    if e['kind'] == 'noise':
        f = 2600.0
        amp = e['amp'] * env(tm, e['d'], e['att'], e['rel']) * np.exp(-tm * e.get('decay', 0))
    else:
        if e['shape'] == 'exp':
            f = e['f0'] * np.exp(np.log(e['f1'] / e['f0']) * frac)
        else:
            f = e['f0'] + (e['f1'] - e['f0']) * frac
        f *= 1 + e['twist'] * np.sin(2 * np.pi * (11.0 * frac + 7.0 * frac ** 2))
        amp = e['amp'] * env(tm, e['d'], e['att'], e['rel']) * osc_peak(B, e['kind'])
        if e['echo']:
            amp *= .70 + .30 * np.cos(2 * np.pi * 12.0 * tm)
    return f, amp * cover, 8 if e['kind'] == 'noise' else WAVES.index(e['kind'])


def convert(B, name, voices, loop):
    ev, dur = B.sound(name)
    n = int(np.ceil(dur / TICK - 1e-9))
    ticks = []                          # per tick: {voice: (f, amp, wave)}
    slot = {}                           # event index -> voice
    for k in range(n):
        t0, t1 = k * TICK, (k + 1) * TICK
        act = []
        for j, e in enumerate(ev):
            c = comp_at(B, e, t0, t1)
            if c and c[1] > 0.004:
                act.append((j, c))
        for j in list(slot):
            if j not in [a[0] for a in act]:
                del slot[j]
        for j, c in sorted(act, key=lambda a: -a[1][1]):
            if j in slot:
                continue
            free = [v for v in voices if v not in slot.values()]
            if free:
                slot[j] = free[0]
            else:                       # steal the quietest voice, if this one is louder
                vj = min(slot, key=lambda q: dict(act).get(q, (0, 0, 0))[1])
                if dict(act).get(vj, (0, 0, 0))[1] < c[1]:
                    slot[j] = slot.pop(vj)
        row = {}
        for j, c in act:
            if j in slot:
                row[slot[j]] = c
        ticks.append(row)
    peak = max(sum(c[1] for c in row.values()) for row in ticks if row)
    scale = SUMVOL / 15 / peak * (LOOP_GAIN if loop else 1.0)
    out = bytearray()
    for row in ticks:
        for v in range(3):
            if v in row:
                f, amp, w = row[v]
                vol = max(0, min(15, int(round(amp * scale * 15))))
                inc = max(0, min(65535, int(round(f * 65536 / RATE))))
                if vol == 0:
                    out += bytes([0, 0, 0])
                else:
                    out += bytes([inc >> 8, inc & 255, w << 4 | vol])
            else:
                out += bytes([0, 0, 0])
    return bytes(out), n


def main():
    B = load_designs()
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, 'wavetbl.bin'), 'wb').write(wave_tables(B))
    open(os.path.join(OUT, 'wavetbl8.bin'), 'wb').write(wave_tables(B, True))
    lines = ['; made by tools/mksynth.py from assets/audio/build_audio.py: do not edit', '']
    dirl = ['SNDDIR']
    total = 0
    for sid, name, cls, voices in SOUNDS:
        data, n = convert(B, name, voices, cls == 'loop')
        fn = 'snd%02d.bin' % sid
        open(os.path.join(OUT, fn), 'wb').write(data)
        lines += ['SND%02d    includebin "%s"' % (sid, fn)]
        dirl += ['        fdb     SND%02d,%d          ; %2d %s (%s)' % (sid, n, sid, name, cls)]
        total += len(data)
        print('%2d %-22s %-5s %4d ticks %5d bytes' % (sid, name, cls, n, len(data)))
    lines += [''] + dirl
    open(os.path.join(OUT, 'audio_data.inc'), 'w').write('\n'.join(lines) + '\n')
    print('rate %.1f Hz, %d bytes of streams, wave tables %d' % (RATE, total, 144 * 32))


if __name__ == '__main__':
    main()
