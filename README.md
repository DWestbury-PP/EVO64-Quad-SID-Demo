# EVO64 Super Quattro - 4-SID Demo Collection

**Eight playable 4-SID music demos showcasing 12-voice polyphonic playback on the Commodore 64.**

A showcase collection for the [EVO64 Super Quattro](https://evo64.com) -- a modern hardware reimagining of the Commodore 64 that supports up to four SID audio chips. Each demo drives all four SID chips simultaneously, delivering 12 voices of chiptune audio from a single C64.

![EVO64 Super Quattro](assets/EVO64-SuperQuattro-4SID-2026-02-16.jpg)
*The EVO64 Super Quattro board with four SID chip sockets, dual CIAs, onboard audio amps, and the custom QAPLA PLA -- ready for 12-voice polyphonic playback.*

## The Demo Collection

### QuadCore -- Vincenzo / Singular Crew, 2017

![QuadCore Player](assets/quad-core-player.jpg)

Four energetic SID-WIZARD tunes playing simultaneously -- the demo that started this collection. Each tune was originally a standalone single-SID composition; our toolchain relocates and patches all four to play together across four SID chips.

> MOS 8580 | PAL 50Hz | Four single-SID tunes combined

### Mega Chase Theme -- SHAD0WFAX, 2025

A native 4-SID composition with stereo channel mapping (SIDs 1+3 left, SIDs 2+4 right). Composed in SID-WIZARD 1.9 and exported as a single binary that drives all four chips from one play routine.

> MOS 8580 | PAL 50Hz | Native 4-SID (PSID v4E) | Stereo

### 4SID Example-Tune -- HERMIT, 2022

A demonstration piece by Mihaly Horvath (HERMIT), the creator of SID-WIZARD. Written to showcase the 4-SID capabilities of SID-WIZARD 1.9, with stereo channel mapping across all four chips.

> MOS 8580 | PAL 50Hz | Native 4-SID (PSID v4E) | Stereo

### Siggraph Invitro 4SID -- Narciso / Onslaught, 2023

A native 4-SID composition from the Onslaught demo group. Another SID-WIZARD 1.9 export with a single play call driving all 12 voices.

> MOS 8580 | PAL 50Hz | Native 4-SID (PSID v4E) | Stereo

### Smells Like Teen Spirit -- John Ames / AmesSoft, 2003

A four-part cover of Nirvana's classic, arranged across four SID chips -- main guitar, 2nd guitar, bass & drums, and melody. Like QuadCore, four separate single-SID files are relocated and patched to play together.

> MOS 6581 | NTSC 60Hz | Four single-SID tunes combined

### A-D Hammer -- Rayden / Alpha Flight, 1998

### A-D Mon -- Rayden / Alpha Flight, 1998

### A-D Twice -- Rayden / Alpha Flight, 1998

Three native 4-SID compositions by Patrick Zeh (Rayden), originally created with the DMC music editor. Each file contains four independent player instances pre-configured for their own SID chip -- no relocation needed. Our harness bypasses the original busy-wait wrapper and drives all four sub-tunes from a clean raster interrupt.

> MOS 6581 | PAL 50Hz | Native 4-SID (RSID v4E)

## Quick Start

Pre-built PRG files and a D64 disk image are included in the `build/` directory -- no build step required.

**In the VICE emulator** (3.10+, supports up to 8 SID chips):

```bash
./vice-quad-sid-play.sh quadcore
./vice-quad-sid-play.sh megachase
./vice-quad-sid-play.sh hermit
./vice-quad-sid-play.sh siggraph
./vice-quad-sid-play.sh teenspirit
./vice-quad-sid-play.sh hammer
./vice-quad-sid-play.sh mon
./vice-quad-sid-play.sh twice
```

Or launch any PRG directly:

```bash
x64sc -sidextra 3 \
  -sid2address 0xD420 \
  -sid3address 0xD440 \
  -sid4address 0xD460 \
  build/QuadSID_Player_exo.prg
```

**On real hardware**, copy the D64 disk image or individual `.prg` files onto the EVO64 Super Quattro via SD2IEC, Ultimate II+, or other storage device. The board must have four SID chips installed with the QAPLA PLA configured for the `$D400`/`$D420`/`$D440`/`$D460` addressing scheme.

A **multi-SID tester utility** is also included on the D64 -- it plays a single SID track on a user-selected SID address, useful for confirming that all four chips are responding correctly in your emulator or hardware setup.

## Building from Source

### Prerequisites

- **Python 3** (for the SID processor tool)
- **Java** (for KickAssembler) -- install via `brew install openjdk`
- **KickAssembler** (included in `KickAssembler/KickAss.jar`)
- **Exomizer** (optional, for PRG compression) -- install via `brew install exomizer`

### Build Commands

```bash
./build.sh quadcore       # QuadCore (Vincenzo)
./build.sh megachase      # Mega Chase (SHAD0WFAX)
./build.sh hermit         # 4SID Example (HERMIT)
./build.sh siggraph       # Siggraph Invitro (Narciso)
./build.sh teenspirit     # Teen Spirit (John Ames)
./build.sh hammer         # A-D Hammer (Rayden)
./build.sh mon            # A-D Mon (Rayden)
./build.sh twice          # A-D Twice (Rayden)

./build.sh all            # Build all demos + D64
./build.sh clean          # Remove build artifacts
./build.sh list           # List available demos
./build.sh quadcore run   # Build and launch in VICE
```

### Output

```
build/EVO64-SuperQuattro.d64           # D64 floppy image with all demos
build/QuadSID_Player_exo.prg           # QuadCore        (~7KB from ~31KB)
build/MegaChase_Player_exo.prg         # Mega Chase       (~6KB from ~13KB)
build/Hermit4SID_Player_exo.prg        # 4SID Example     (~5KB from ~11KB)
build/SiggraphInvitro_Player_exo.prg   # Siggraph Invitro (~3KB from  ~7KB)
build/TeenSpirit_Player_exo.prg        # Teen Spirit       (~4KB from ~29KB)
build/Rayden_Hammer_Player_exo.prg     # A-D Hammer        (~7KB from ~18KB)
build/Rayden_Mon_Player_exo.prg        # A-D Mon           (~7KB from ~14KB)
build/Rayden_Twice_Player_exo.prg      # A-D Twice         (~7KB from ~17KB)
```

Compressed PRGs are self-decrunching -- just `LOAD` and `RUN`. If Exomizer is not installed, the build skips compression automatically.

## The EVO64 Super Quattro

The EVO64 is a hardware reimagining of the Commodore 64 that brings together decades of community modifications:

- Support for 4 SID chips with flexible address selection
- ClearVideo64 enhanced video circuit
- Switchable PAL/NTSC clock
- SRAM main memory (eliminates VSP bug)
- Custom QAPLA PLA for multi-SID, multi-ROM support
- Optional vacuum tube audio preamps
- Full backwards compatibility with original C64 software

## Technical Documentation

For those interested in the inner workings:

- **[SID Relocation and Patching Engine](docs/SID-relocation-and-patching.md)** -- How the recursive descent disassembler and three-layer patching engine relocate single-SID tunes to play on different SID chips. Covers code relocation, hi-byte table detection, and the raster interrupt chain.

- **[Integrating 4-SID Tunes](docs/Integrating-4SID-tunes.txt)** -- A practical guide to analyzing and integrating new 4-SID tracks into the collection. Covers the four integration categories (single-SID relocation, native PSID v4E, RSID sub-tune wrappers, and self-playing RSIDs), with a decision tree and known gotchas.

- **[SID File Format](docs/SID-file-format.txt)** -- The HVSC SID file format specification.

- **[PSID v4E Extended Format](docs/Exotic-SID-formats.txt)** -- The extended SID header format used by SID-WIZARD 1.9 for native multi-SID compositions.

## Project Structure

```
quad-sid-player/
├── src/
│   ├── QuadSID_Player.asm          # QuadCore: 4-way raster IRQ chain
│   ├── MegaChase_Player.asm        # Mega Chase: single-call native 4-SID
│   ├── Hermit4SID_Player.asm       # 4SID Example: single-call native 4-SID
│   ├── SiggraphInvitro_Player.asm  # Siggraph Invitro: single-call native 4-SID
│   ├── TeenSpirit_Player.asm       # Teen Spirit: 4-way raster IRQ chain
│   ├── Rayden_Hammer_Player.asm    # A-D Hammer: 4 sub-tune RSID harness
│   ├── Rayden_Mon_Player.asm       # A-D Mon: 4 sub-tune RSID harness
│   └── Rayden_Twice_Player.asm     # A-D Twice: 4 sub-tune RSID harness
├── tools/
│   ├── sid_processor.py             # SID parsing, disassembly, relocation
│   └── multisid-tester.prg          # SID address tester utility (C64)
├── sids/
│   ├── quadcore/                    # 4 separate single-SID tunes (.sid)
│   ├── megachase/                   # Native 4-SID PSID v4E (.sid)
│   ├── hermit-4sid-example/         # Native 4-SID PSID v4E (.sid)
│   ├── siggraph-invitro/            # Native 4-SID PSID v4E (.sid)
│   ├── smells-like-team-spirit/     # 4 separate single-SID tunes (.sid)
│   ├── rayden-hammer/               # Native 4-SID RSID v4E (.sid)
│   ├── rayden-mon/                  # Native 4-SID RSID v4E (.sid)
│   └── rayden-twice/                # Native 4-SID RSID v4E (.sid)
├── build/                           # Pre-built PRGs and D64 disk image
├── KickAssembler/                   # KickAssembler cross-assembler
├── docs/
│   ├── SID-relocation-and-patching.md  # Relocation engine deep dive
│   ├── Integrating-4SID-tunes.txt      # Integration guide (Categories A-D)
│   ├── SID-file-format.txt             # HVSC SID format specification
│   └── Exotic-SID-formats.txt          # PSID v4E extended header format
├── assets/                          # Project images
├── build.sh                         # Unified build script
├── vice-quad-sid-play.sh            # VICE launcher with quad-SID flags
└── README.md
```

## Credits

- **Hardware**: EVO64 Super Quattro by Auroscience
- **Music**: Laszlo Vincze (Vincenzo) / Singular Crew, 2017; SHAD0WFAX, 2025; HERMIT (Mihaly Horvath), 2022; Narciso / Onslaught, 2023; John Ames / AmesSoft, 2003; Patrick Zeh (Rayden) / Alpha Flight, 1998
- **Player Engines**: SID-WIZARD 1.7 / 1.9; DMC 4SID
- **Compression**: [Exomizer](https://bitbucket.org/magli143/exomizer/wiki/Home) by Magnus Lind
- **Quad SID Player & Tooling**: EVO64 Project, 2026

## License

This project is for educational and demonstration purposes as part of the EVO64 project.
