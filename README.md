# PAC-FAN — a maze-chase game for CoCo 1/2 Semigraphics 12

A maze-chase game in SG12 (64x96 elements, 8 colours), 6809 assembly, by Carlos A. Camacho
(CAMCO). An unofficial fan game; not affiliated with or endorsed by the owners of Pac-Man.

    LOADM"PACFAN":EXEC      arrow keys move, SPACE starts, BREAK returns to BASIC
                            on the title, UP/DOWN pick the starting level (1-40)

Needs a 32K CoCo 1 or 2 (SG12 does not exist on a CoCo 3).

- 40 levels, designed in the maze editor (`editor/maze-editor.html`) and read from
  `levels/pacfan-project.json` at build time. Each has its own wall colour; walls are
  joined lines (`#`) or solid blocks (`B`). Clearing a level goes to the next; after the
  last, back to 1, with the ghosts a little faster each time. The level number is in the
  score bar (L01..L40) and on the title.
- Ghost speed rises with the level number: 15 for levels 1-8, 16 for 9-16, 17 for 17-24,
  18 for 25-32 and 19 for 33-40 (the player moves at 16). Starting on a later level from
  the title starts at that level's speed. After level 40 the game goes round again at 19.
- A test build with an autopilot (`lwasm -DBOT=1`, never shipped) plays the real game for
  measuring level difficulty: shortest path to the nearest dot, avoiding live ghosts.
- Ghost house with a door: red starts above the door, the others inside; they leave
  through the door (by dot count), and eaten ghosts' eyes go back in through it. The
  player can never pass the door.
- Tunnels, horizontal and vertical: an open edge tile wraps to the opposite edge, on
  any row or column. Ghosts use them too, slowing to half speed inside as in the
  arcade, and their distance check counts the way through a tunnel, so they follow the
  player through it (the arcade measures in a straight line, which in a 16-tile maze
  meant the ghosts never chose the tunnel).
- When the player is caught, every wall flashes through all eight colours (twice, about
  1.5 s), then the maze returns to its own colour. Each colour is painted into the hidden
  buffer and flipped in at field sync, so it never wipes down the screen.
- Eyes go home by a shortest-path map gen.py computes per level (60 bytes a level),
  not by straight-line targeting, which in a soak circled forever under a house walled
  off from below.
- Title screen: the credits, PRESS SPACE, and the player and the ghosts chasing across
  the middle; every five seconds the ghosts turn blue and the chase runs the other way.
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

Technique: everything shape-related is a table built by `gen.py` (per-level tile codes
and wall patterns, from which the background screen is built at each level start; sprites pre-shifted for both element positions in a byte with AND/OR masks that
keep SG12's one-colour-per-byte rule, font, the unrolled draw and restore code). Level
redraws are stack blasts (PULU/PSHS D,X,Y). Each frame restores only the sprites' 3x6-byte
squares from a background copy and redraws them, double-buffered and flipped at field sync.

Measured in xroar-dev (XRoar 1.12.1, CoCo NTSC 64K, 0.89 MHz) over a minute of play:
four minutes of random play: average 6,285 cycles of work per 14,915-cycle field (42%);
7 gameplay frames ran 2-23% over (a dropped frame each), all at eat/redraw moments.
Not yet run on hardware.

Build: `LWASM=/path/to/lwasm ./build.sh` → `dist/PACFAN.DSK`.

## Levels and the maze editor

`editor/maze-editor.html` is the browser maze editor: open it in any browser. Save file
downloads the project JSON; the shared library works only in the published copy.

**Play order** is `levels/order.json` (by level name), not the project file's order, so the
editor file can be re-saved over `levels/pacfan-project.json` without losing it. It was
set from 400 autopilot games (10 per level, ghost speed 15 for all): level 1 kept first,
the other 39 ranked easiest to hardest by deaths per 100 dots eaten. The ends of the
ranking are firm; the middle (deaths per 100 dots 2.2-2.9) is within the noise of ten
games, so neighbouring positions there could swap. A level added to the project must
also be added to `order.json`, or gen.py stops with the name it is missing.

To change the levels, save the project over `levels/pacfan-project.json` and run
`./build.sh`. `gen.py` reads that file (it never writes it) and prints a line per level.
What the engine needs and checks:

- 16x15 only (SG12 holds no more); one wall colour a level (per-wall colours are ignored).
- A ghost house (`H`) with a door (`D`) directly above it and an open tile above the door.
- A player start (`P`); without one, the open tile nearest the bottom middle.
- Dots the player cannot reach are removed (otherwise the level could never be cleared),
  and the line says so. If the ghosts' exit is cut off from the player, the line warns:
  the ghosts can never reach the player on that level.

Each level costs 201 bytes (120 of tiles at four bits each -- the engine works out the
wall joins at level start -- 21 of header, 60 of the eyes' way-home map). With 40 levels
the image ends at $6D59 against the build's $7000 limit, so there is room for about three
more levels as things stand.

Current warnings: none -- every level is fully reachable and every ghost house opens
into the maze.
