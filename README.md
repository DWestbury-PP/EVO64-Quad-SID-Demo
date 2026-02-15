# EVO64 Super Quattro - Quad SID Player

**The first-ever fully playable 4-SID music track for the Commodore 64!**

This project creates a simultaneous quad-SID music player for the [EVO64 Super Quattro](https://evo64.com) — a modern hardware reimagining of the Commodore 64 that supports up to four SID audio chips, delivering 12 voices of polyphonic chiptune goodness.

![EVO64 Super Quattro](assets/EVO64-SuperQuattro-4SID.png)
*The EVO64 Super Quattro board with four SID chip sockets, dual CIAs, onboard audio amps, and the custom QAPLA PLA — ready for 12-voice polyphonic playback.*

## Overview

Four independent SID tunes play simultaneously, each driving a separate SID chip:

| Tune | SID Address | Voices | Memory Location |
|------|------------|--------|----------------|
| 1    | `$D400`    | 3      | `$1000-$1FD5`  |
| 2    | `$D420`    | 3      | `$3000-$3FDC`  |
| 3    | `$D440`    | 3      | `$5000-$5F17`  |
| 4    | `$D460`    | 3      | `$7000-$8224`  |

Playback is driven by a raster interrupt chain that divides the PAL video frame (312 raster lines) into four equal segments, triggering each tune's play routine in sequence every ~78 lines.

## Music

All four tunes are by **László Vincze (Vincenzo)** of **Singular Crew** (2017), created with **SID-WIZARD 1.7**. The tunes are configured for the **MOS 8580** SID chip at **PAL** timing (50Hz VBI).

## How It Works

### The Challenge

No one had ever made a single playable 4-SID track before. The C64 normally has one SID chip at address `$D400`. The EVO64 Super Quattro maps four SIDs at `$D400`, `$D420`, `$D440`, and `$D460`.

Standard SID tunes are compiled with hardcoded references to `$D400`. To play four tunes simultaneously, we need to:

1. **Relocate** each tune to a unique memory location (they all originally load at `$1000`)
2. **Patch** each tune's SID register writes to target different SID addresses
3. **Orchestrate** playback with a raster interrupt chain

### The Solution

#### 1. SID Processing Tool (`tools/sid_processor.py`)

A custom Python tool that:
- **Parses** PSID v2 file headers to extract metadata
- **Analyzes** the binary using **recursive descent disassembly** from known entry points to accurately distinguish code regions (~45%) from data regions (~55%)
- **Relocates** all absolute address references within confirmed code (329 instruction-level patches per tune)
- **Patches** SID register addresses (`$D400-$D41F` → target SID base)
- **Scans** data regions for split hi/lo byte address tables using heuristics (for pattern and instrument pointer tables)

#### 2. Raster Interrupt Chain (`src/QuadSID_Player.asm`)

A KickAssembler program that:
- Initializes all four tunes
- Banks out ROMs (`$01 = $35`) for direct hardware IRQ vectors
- Sets up a circular raster interrupt chain:
  - **IRQ 1** @ raster line 0: plays Tune 1
  - **IRQ 2** @ raster line 78: plays Tune 2
  - **IRQ 3** @ raster line 156: plays Tune 3
  - **IRQ 4** @ raster line 234: plays Tune 4
- Displays a title screen with SID configuration info

## Building

### Prerequisites

- **Python 3** (for the SID processor tool)
- **Java** (for KickAssembler) — install via `brew install openjdk`
- **KickAssembler** (included in `KickAssembler/KickAss.jar`)

### Build Commands

```bash
# Full build (process SIDs + compile assembly)
./build.sh

# Build and launch in VICE emulator
./build.sh run

# Only process SID files (no compilation)
./build.sh process

# Clean build artifacts
./build.sh clean
```

### Output

The build produces `build/QuadSID_Player.prg` (~31KB), ready to load on a real C64 or in an emulator.

## Testing in VICE

VICE 3.10 supports up to 8 SID chips. Launch with quad-SID configuration:

```bash
x64sc -sidextra 3 \
  -sid2address 0xD420 \
  -sid3address 0xD440 \
  -sid4address 0xD460 \
  build/QuadSID_Player.prg
```

## Running on Real Hardware

Load the `.prg` file onto the EVO64 Super Quattro via SD2IEC, Ultimate II+, or other storage device. The board must have four SID chips installed with the QAPLA PLA configured for the `$D400`/`$D420`/`$D440`/`$D460` addressing scheme.

## Project Structure

```
quad-sid-player/
├── src/
│   └── QuadSID_Player.asm      # Main KickAssembler source
├── tools/
│   └── sid_processor.py         # Python SID analysis & patching tool
├── QuadCore-SIDs/               # Source SID music files
│   ├── Quad_Core_tune_1.sid
│   ├── Quad_Core_tune_2.sid
│   ├── Quad_Core_tune_3.sid
│   └── Quad_Core_tune_4.sid
├── build/                       # Generated build artifacts
│   ├── QuadSID_Player.prg       # Final C64 executable
│   ├── tune1.bin - tune4.bin    # Patched tune binaries
│   └── tune_config.inc          # Auto-generated KickAssembler config
├── KickAssembler/               # KickAssembler cross-assembler
│   ├── KickAss.jar
│   └── Examples/                # KickAssembler example projects
├── docs/                        # Reference documentation
│   ├── SID-file-format.txt      # HVSC SID file format specification
│   ├── Exotic-SID-formats.txt   # Extended SID format (v4E) docs
│   ├── VICE-README.txt          # VICE emulator documentation
│   └── vice.pdf                 # VICE full manual
├── assets/                      # Project assets
│   └── EVO64-SuperQuattaro.jpeg # EVO64 Super Quattro board photo
├── build.sh                     # Build script
└── README.md                    # This file
```

## Technical Details

### Memory Map

```
$0801-$080C  BASIC SYS startup stub
$0810-$0ABE  Main program (IRQ harness + title screen)
$1000-$1FD5  Tune 1 (original location, SID @ $D400)
$3000-$3FDC  Tune 2 (relocated +$2000, SID @ $D420)
$5000-$5F17  Tune 3 (relocated +$4000, SID @ $D440)
$7000-$8224  Tune 4 (relocated +$6000, SID @ $D460)
```

### SID-WIZARD Player Analysis

The recursive descent disassembler identified:
- **1845 code bytes** per tune (identical player engine across all 4)
- **822 instructions** per tune
- **16 SID register references** per tune (voices via indexed addressing)
- **329 internal absolute address references** requiring relocation
- Code region: `$1000-$1A19` | Data region: `$1A1A` onwards

### SID Register Patch Map

```
Voice 1: $D400-$D406 → $D4x0-$D4x6  (freq, pulse width, control, ADSR)
Filter:  $D415-$D418 → $D4x5-$D4x8  (cutoff, resonance, mode/volume)
```

Where `x` = `0` (SID 1), `2` (SID 2), `4` (SID 3), `6` (SID 4).

## The EVO64 Super Quattro

The EVO64 is a hardware reimagining of the Commodore 64 that brings together decades of community modifications:

- Support for 4 SID chips with flexible address selection
- ClearVideo64 enhanced video circuit
- Switchable PAL/NTSC clock
- SRAM main memory (eliminates VSP bug)
- Custom QAPLA PLA for multi-SID, multi-ROM support
- Optional vacuum tube audio preamps
- Full backwards compatibility with original C64 software

## Credits

- **Hardware**: EVO64 Super Quattro by the EVO64 Project
- **Music**: László Vincze (Vincenzo) / Singular Crew, 2017
- **Player Engine**: SID-WIZARD 1.7
- **Quad SID Player & Tooling**: EVO64 Project, 2026

## License

This project is for educational and demonstration purposes as part of the EVO64 project.
