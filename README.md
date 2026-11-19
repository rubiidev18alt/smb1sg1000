# Super Mario Bros. for the Sega SG-1000

**[Download the playable cartridge: smb1.sg](cartridge/smb1.sg)** (48 KiB). Open the `.sg` file in Gearsystem in SG-1000 mode. No NES ROM, BIOS, or RAM expansion is needed.

![Title screen captured in Gearsystem](sg1000/title.png)

| Controller 1 | Action |
| --- | --- |
| Left / Right | Walk |
| Button 1 | Jump; release early for a short hop. Tap to swim underwater. |
| Button 2 | Hold to run; press to shoot as Fire Mario. |
| Down | Enter a connected pipe while standing on its mouth. |
| Either button | Start or continue after a life loss or course clear. |

This is a native Z80 adaptation of the **32-stage, eight-world main route**. The build reads SMB1Base’s area streams, halfway points, CHR graphics, title sign and music data. The port includes underground coin rooms, mushrooms and fire flowers, shell kicks, flagpoles, castle hazards and Bowser. It is single-player and not frame-identical to the NES game: the camera advances one metatile at a time, lifts are fixed platforms, enemy patterns and boss fights are simplified, and warp zones, vine/cloud routes and castle loops are omitted.

### Rebuild

Use Python 3.10+, GNU Make and [SjASMPlus](https://github.com/z00m128/sjasmplus) (tested with 1.21.1):

```sh
make sg1000-tools   # optional: build a local assembler with Git and a C++ compiler
make sg1000         # writes build/smb1.sg
make sg1000-test    # verify the assembled ROM against the source area tables
```

For a controller-driven emulator test, run `make sg1000-test GEARSYSTEM_CORE=/path/to/gearsystem_libretro.so`. It plays 1-1 both overland and through the bonus pipe, enters 1-2, then tests life loss, game over and restart. Tested in Gearsystem; not verified on a physical console.

The native code is in [`sg1000/`](sg1000/). It uses 1 KiB of work RAM and the 9918A's 16 KiB of VRAM. Only sixteen columns of the map are mutable at once; the rest stream from cartridge ROM. Backgrounds use two alternating Graphics II name tables, sprites use layered 16×16 patterns, and two PSG voices play the converted melody and bass while the third handles effects.

---

## Original NES project: SMB1Base

## ROM Hacking friendly version of SMB1

### What is this project?

Super Mario Bros. for the NES is a classic game and a popular game for ROM hackers to modify.
This repository is a collection of several new features and patches added to the original game to make
it easier to add new content and expand on what the original was capable of.
The goal is to make it both easy and fun to stretch the boundaries of whats possible when making a
mod for Mario!

### Features

- Easy to build; just run `build.sh` or `build.bat`

- Flexible feature set (check out `options.s` for all available options!)

- Multiple optional audio engines available to allow importing songs from modern tools like Famitracker or Famistudio
  - The latest DN famitracker is supported through bhop (https://github.com/Dn-Programming-Core-Management/Dn-FamiTracker/releases/)
  - Famistudio support is kept up to date with the latest (https://famistudio.org/)
  - Also supports using custom music engines along side the vanilla sound effect engine, since nothing can really replicate the crisp SFX from vanilla better than the vanilla engine.

- New code features including the following:
  - 8x16 sprite mode in use to double the maximum number of sprites on screen
  - New metasprite based rendering code to make it easy to add new enemies and animations to the game
  - Anti-lag code to hide lag frames and get smoother gameplay
  - RAM values are relocatable, making it easy to add new content that needs RAM

- Level data importer for use with tools like Greated or SMBUtil

- Code is split into banks of 8kb with only 16kb of fixed space required.
  - This frees up the $c000 region to be used for banked DPCM

- Minor optimizations for the original game, removing residual code and cleaning up some small oddities

- Optional VSCode integration with the following features
  - Syntax highlighting
  - Inline error reporting (error squigglies you can hover to see whats wrong)
  - Automatic compile on save

### How to use

### Features I want to have someday

- Sooner than later
  - Optional bugfixes for the vanilla game to disable
  - CC65 support (add C headers and callback/hook locations that can call into C code)
- Long term goals
  - Optional Tiled based level data for easily making levels without using vanilla mario data
  - Optional 4-way scrolling for interesting new maps
  - Code changes
    - use popslide for faster VRAM updates
    - increase number of enemy slots
