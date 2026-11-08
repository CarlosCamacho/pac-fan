# PAK FAN | ORIGINAL SOUND DESIGN NOTES

This refresh retains the same **17 gameplay sound IDs** used by Pak Fan so
no event remapping is required. The acoustic arrangements are new rather than
being small changes to a pre-existing master track.

| Cue | New arrangement | Gameplay recognition |
|---|---|---|
| `start_music` | Fast D-centered 48-step melody, pitched bass accents, and crisp pulse-wave lead | Starting a new round |
| `intermission_music` | Eight-bar A-Dorian syncopated groove at 180 BPM, bass and digital percussion | A short celebratory interlude |
| `coin_insert` | Rising sweep, high bell, and an added overtone | Credit accepted |
| `extra_life` | New eight-note bonus fanfare, with bell over a lower supporting tone | Additional life |
| `siren_1` | Slow 3-pitch warning cycle | Low-threat chase |
| `siren_2` | Faster 3-pitch warning cycle at a higher register | Rising threat |
| `siren_3` | More urgent three-note pulse | Mid-threat chase |
| `siren_4` | Faster jagged pulse with scratchy accent | High-threat chase |
| `siren_5` | Highest-pitched, fastest triple warning with accent | Maximum-threat chase |
| `power_pellet_fright` | Staccato low sawtooth-based growl and rhythmic pitch bends | Temporary power-up mode |
| `ghost_eyes_return` | Fluttering upward run of triangular bells | Defeated enemy returning |
| `eat_dot_1` | Rising two-part click and chirp | Small pickup, first variant |
| `eat_dot_2` | Falling click followed by a rebound chirp | Small pickup, alternate variant |
| `eat_fruit` | Three bright bell notes and a short hiss sparkle | Bonus collected |
| `eat_ghost` | Grainy pitched-down sweep layered with a softer bell | Enemy captured |
| `death` | Descending note groups, a fading sweep, and digital static bits | Player life lost |
| `fruit_bounce` | Up-and-down quick spring sweep | Small bouncing object |

All sounds originate from analytic waveforms, pitch envelopes, and note event
lists authored in `build_audio.py`. The CoCo previews are quantized copies of
these new syntheses, not audio reconstructed from external wave tables.

These creative changes establish distinctive new sound assets, but legal
clearance is not conferred by this document.
