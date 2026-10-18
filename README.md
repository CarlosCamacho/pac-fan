# PAC-FAN — a maze-chase game for CoCo 1/2 Semigraphics 12

A maze-chase game in SG12 (64x96 elements, 8 colours), 6809 assembly, by Carlos A. Camacho
(CAMCO). An unofficial fan game; not affiliated with or endorsed by the owners of Pac-Man.

    LOADM"PACFAN":EXEC      arrow keys move, SPACE starts, BREAK returns to BASIC

Needs a 32K CoCo 1 or 2 (SG12 does not exist on a CoCo 3).

- 16x15-tile maze, 118 dots, 4 power pellets, 3 lives, score, READY!/GAME OVER.
- Tunnels at both ends of the middle row: leave on one side, come back on the other.
  Ghosts use them too, slowing to half speed inside as in the arcade; on the tunnel row
  their distance check counts the way through the tunnel, so they follow the player
  through it (the arcade measures in a straight line, which in a 16-tile maze meant the
  ghosts never chose the tunnel).
- Title screen: the credits, PRESS SPACE, and the player and the ghosts chasing across
  the middle; every five seconds the ghosts turn blue and the chase runs the other way.
- Maze: the generator checks it has no dead ends and no unreachable tiles; the bottom
  half was redesigned so no row is one long straight.
- "Wa-ka" eat sound: alternate falling and rising sweeps, played in the time each frame
  would otherwise spend waiting for vertical sync, so it can never make a frame late.
- Splash screen: CAMCO PRESENTS, the cast, PROGRAMMING BY CARLOS A. CAMACHO,
  (C) 2026 CAMCO, with an original two-voice intro tune (also played at game start).
- Ghost behaviour follows the arcade rules: scatter/chase phases (7/20/7/20/5/20/5 s,
  then chase), every switch reverses the ghosts; red targets the player, pink four tiles
  ahead (with the arcade's facing-up quirk), cyan doubles the vector from red to two tiles
  ahead, orange chases until within 8 tiles and then heads for its corner; choices never
  reverse and pick the nearest next tile by distance squared, ties up/left/down/right;
  blue ghosts move at half speed and choose at random; red speeds up at 20 and 10 dots
  left ("Elroy"); ghosts leave the house by dot count (0, 0, 30, 60) or after 4 s
  without a dot eaten. Each level speeds the ghosts up.
- Music: a sawtooth engine, two voices through the 6-bit DAC at 11,328 Hz (a 79-cycle
  sample loop, measured), blocking, used on the splash and before the first life.

Technique: everything shape-related is a table built by `gen.py` (background screen,
maze map, sprites pre-shifted for both element positions in a byte with AND/OR masks that
keep SG12's one-colour-per-byte rule, font, the unrolled draw and restore code). Level
redraws are stack blasts (PULU/PSHS D,X,Y). Each frame restores only the sprites' 3x6-byte
squares from a background copy and redraws them, double-buffered and flipped at field sync.

Measured in xroar-dev (XRoar 1.12.1, CoCo NTSC 64K, 0.89 MHz) over a minute of play:
four minutes of random play: average 6,285 cycles of work per 14,915-cycle field (42%);
7 gameplay frames ran 2-23% over (a dropped frame each), all at eat/redraw moments.
Not yet run on hardware.

Build: `LWASM=/path/to/lwasm ./build.sh` → `dist/PACFAN.DSK`.

## Levels and the maze editor

`editor/maze-editor.html` is the browser maze editor (open it locally, or use the
published copy). `levels/pacfan-project.json` is the 25-level project made with it; the
game does not read it yet — building those levels into the engine is in progress.
