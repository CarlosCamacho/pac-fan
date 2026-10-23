# Handoff from the earlier chat session (October 2026)

This file carries a long earlier working session over to this repository. `CLAUDE.md` covers
how to work on Pac-Fan itself; this file covers who the owner is, what else was built, the
tools, and what is still open. Where the two overlap, `CLAUDE.md` is the one kept current.

## The owner

- Carlos A. Camacho (CAMCO), github.com/CarlosCamacho. Writes 6809 games for the TRS-80 Color
  Computer. Use **US English**.
- **CoCoSDC support is required in every program** unless he says otherwise. Build it in; don't
  offer it as an option.
- **Never reproduce copyrighted or trademarked material.** No Pac-Man name, logo or Namco
  attract screen; no Namco music. Requests for those were declined, and he renamed the game
  Pac-Fan. The intro tune and all art are original.
- When a **skill** he has already been given changes, **bump its version number**. He noticed
  once when this was missed.
- Commit and push finished work. Report what was tested and where. **Nothing here has run on
  real hardware**; he tests on his own machines and in XRoar and sends screenshots.
- He prefers being shown results (screenshots, contact sheets) and short, direct answers.

## Projects and where they are

| What | Where | State |
|---|---|---|
| **Pac-Fan** (SG12 maze game, CoCo 1/2) | this repo | 40 levels, played in order easiest to hardest; see `CLAUDE.md` |
| Maze editor (HTML) | `editor/maze-editor.html`; also published as a web artifact | Saves project JSON; the owner designs levels in it |
| **SGTEST** (SG8/12/24 test cards, CoCo 2 and 3) | `assets/sgtest/` inside the **coco-hardware** skill (v3.26) | Done; results below |
| GHOSTS demo (the stack-blast SG12 technique Pac-Fan grew from) | not in a repo; `ghosts-src.zip` was delivered in chat | Done |
| Early SG12 Pac-Man prototype `pac12` | superseded by Pac-Fan | — |
| CoCo **skills** (16 of them) | installed on his account; delivered as zips | See versions below |
| **Audits** of his CoCo repos (20 of them: Beast in the Shadow, dk, GEM/9, 1942-coco3, Invaders-S24, Wulfenstein3D-24, CoCoTosh, CoCo Baseball 2, Kabomb, Balloon Fighter, Speed Bots, CoCoVille, Crypt Quest, Gataga, Insecta, Planet Miners, SEUCK-CoCo3, EmEsDOS09, CoCo-C-Studio, Wulfenstein 3D) | delivered in chat as `AUDIT-<repo>.md` | Done; each game is worked on in its own session |
| SKILLTST.DSK (hardware test programs for the skills) | delivered in chat | Results folded into the skills |

### Skill versions at handoff

coco-hardware 3.26 · coco1and2-assembly 3.29 · coco-router 3.27 · coco-tooling 3.27 ·
coco3-assembly 3.26 (built on the installed 3.24; the 3.25 listed here was not installed) · 6809-dev 3.24 · disk-basic 3.24 · coco1and2-basic 3.21 · 6309-dev 3.17 ·
coco3-basic 3.17 · 6809-to-68000 3.16 · coco3-basic09 3.11 · 6502-to-6809 3.6 ·
z80-to-6809 3.2 · coco3-os9-assembly 1.3 · flex09-os 1.2.

coco-hardware 3.26 was built on the copy installed on his account, which had CoCoXSID material
from another session. **Before changing any skill, start from the copy installed on his account,
not from an older zip.** Two copies both labelled 3.25 already diverged once. Give him the
complete skill as a zip.

## Toolchain

- **LWTOOLS 4.24** (`lwasm`): no longer packaged for Ubuntu. Build it from source; the
  `stahta01/LWTools` mirror has it.
- **xroar-dev** (<https://github.com/milliluk/xroar-dev>): the emulator with traps, RAM dumps,
  screenshots and input scripts. The skills recommend that every cloud coding session install
  it. ROMs are not distributable: get `bas13.rom`, `extbas11.rom`, `disk11.rom` (CoCo 2) and
  `coco3.rom` from the owner.
- Running it: `-headless -rompath ROMS -machine cocous -ram 32 -load-fd0 X.DSK -input-script S.txt`
  (CoCo 2); `-machine coco3` for a CoCo 3.
- xroar-dev quirks learned the hard way:
  - `-trap-range N` means **from hit N on**; use `N-N` for one hit.
  - `xpc=` takes a physical address (`0x0` + 4 hex digits).
  - A screenshot name may get a digit appended (`shot.png` becomes `shot1.png`): glob for it.
  - `-trap-screenshot-when now` captures mid-frame. It showed "tearing" that wasn't really
    there, so judge tearing from default whole-frame shots.
  - Input-script key names are lower case: `key space down`, `key break up`, `key up down`.
  - Repeated identical trap conditions are unreliable; prefer `seconds=` traps.
- Pac-Fan's own scripts wrap all of this: `tools/checkbg.sh`, `tools/botgames.sh`,
  `tools/rank.py`.

## Findings worth keeping

- **CoCo 3 semigraphics via `$FF9C`** (SGTEST, owner in XRoar and the assistant in xroar-dev; not on
  hardware):
  - 8 gives SG8, 9 gives SG12, 10 gives SG24; 7 gives SG6 row height; 15 is normal and must be
    restored on exit.
  - `$0E` does the same as `$0A`.
  - The SAM V bits make no difference.
  - The display always fills 192 scanlines.
  - Graphics blocks only, no text.
  - Recorded in coco-hardware 3.26, `mc6847-machine-variants.md` §2a.
  - Pac-Fan is all blocks, so it is a candidate to run on a CoCo 3 with `$FF9C` = 9. Not tried.
- **Difficulty measurement**: an autopilot in the real game (`-DBOT=1`), 10 games a level,
  ranked by deaths per 100 dots eaten. The ends of the ranking are firm; the middle is within
  noise.

## Open threads (the owner has not decided)

- Patch an SG24 game (for example Invaders-S24) so one binary runs on a CoCo 2 and a CoCo 3.
- More levels: about 330 bytes are free (October 22), roughly one level. Many more would mean packing
  harder or loading levels from disk (with CoCoSDC support).

Done on October 22: blue time by level (6 s down to 2 s), the door in the death
flash with no white (speed kept at 4 frames a color), CoCo 3 support through `$FF9C` with a
CoCo 2-matching palette, and coco3-assembly v3.26. See `CLAUDE.md`.

## How the session went, briefly

1. Skills review, revised skill zips, audits of his repos, test disks.
2. The GHOSTS stack-blast SG12 demo, then an SG12 Pac-Man, renamed Pac-Fan: splash and title,
   sawtooth DAC music, arcade ghost AI, tunnels, waka sound, title-screen chase.
3. The maze editor (HTML artifact). He designed 25, then 40 levels in it.
4. The engine for his levels: house and door, vertical tunnels, solid walls, per-level colour,
   4-bit packing to fit 40 levels, an eyes-home path map, the death flash, speed by level,
   autopilot difficulty ranking and play order.
5. The CoCo 3 `$FF9C` investigation with SGTEST, and coco-hardware v3.26.
