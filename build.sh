#!/bin/bash
# ============================================================
#  EVO64 Super Quattro - Unified Build Script
# ============================================================
#
#  Builds 4-SID demos for the EVO64 Super Quattro.
#
#  Usage:
#    ./build.sh quadcore          Build QuadCore demo
#    ./build.sh megachase         Build Mega Chase demo
#    ./build.sh all               Build all demos
#    ./build.sh clean             Remove all build artifacts
#    ./build.sh list              List available demos
#    ./build.sh <demo> run        Build and launch in VICE
#
# ============================================================

set -e

# Ensure Java is on PATH (Homebrew OpenJDK)
if [ -d "/opt/homebrew/opt/openjdk/bin" ]; then
    export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
fi

# Project paths
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
SRC_DIR="$PROJECT_ROOT/src"
TOOLS_DIR="$PROJECT_ROOT/tools"
SIDS_DIR="$PROJECT_ROOT/sids"
KICKASS_JAR="$PROJECT_ROOT/KickAssembler/KickAss.jar"

# VICE emulator
VICE_PATH="${VICE_PATH:-/Users/dwestbury/Documents/Tech_Stuff/Electronics/Commodore Projects/C64 Emulation/vice-arm64-gtk3-3.10/bin/x64sc}"

# Resolve VICE binary and c1541 tool
if [[ "$VICE_PATH" == *.app ]]; then
    VICE_CMD="$VICE_PATH/Contents/Resources/bin/x64sc"
    C1541_CMD="$VICE_PATH/Contents/Resources/bin/c1541"
else
    VICE_CMD="$VICE_PATH"
    C1541_CMD="$(dirname "$VICE_PATH")/c1541"
fi

# VICE Quad-SID configuration
VICE_SID_OPTS="-sidextra 3 -sid2address 0xD420 -sid3address 0xD440 -sid4address 0xD460"

# D64 disk image (shared across all demos)
OUTPUT_D64="$BUILD_DIR/EVO64-SuperQuattro.d64"
DISK_NAME="evo64 super quattro"
DISK_ID="eq"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'


# ============================================================
#  HELPER FUNCTIONS
# ============================================================

check_java() {
    if ! command -v java &> /dev/null; then
        echo -e "${RED}ERROR: Java is not installed.${NC}"
        echo "  KickAssembler requires Java. Install with: brew install openjdk"
        exit 1
    fi
}

check_kickass() {
    if [ ! -f "$KICKASS_JAR" ]; then
        echo -e "${RED}ERROR: KickAssembler not found at: $KICKASS_JAR${NC}"
        echo "  Please ensure KickAss.jar is in the KickAssembler/ directory."
        exit 1
    fi
}

compile_asm() {
    local asm_file="$1"
    local output_prg="$2"

    java -jar "$KICKASS_JAR" \
        "$asm_file" \
        -odir "$BUILD_DIR" \
        -o "$output_prg" \
        -showmem \
        -symbolfile
}

compress_exomizer() {
    local input_prg="$1"
    local output_exo="$2"

    if command -v exomizer &> /dev/null; then
        echo ""
        echo -e "${YELLOW}  Compressing with Exomizer...${NC}"
        exomizer sfx sys -t64 -n -o "$output_exo" "$input_prg"

        if [ $? -eq 0 ]; then
            local orig_size=$(wc -c < "$input_prg" | tr -d ' ')
            local exo_size=$(wc -c < "$output_exo" | tr -d ' ')
            local ratio=$(( (orig_size - exo_size) * 100 / orig_size ))
            echo ""
            echo -e "${GREEN}  Compression: ${CYAN}$orig_size${NC} -> ${CYAN}$exo_size bytes${NC}  (${ratio}% reduction)"
        fi
    else
        echo ""
        echo -e "${YELLOW}  Skipping compression (install with: brew install exomizer)${NC}"
    fi
}

add_to_d64() {
    local prg_file="$1"
    local d64_name="$2"

    if [ ! -x "$C1541_CMD" ]; then
        echo -e "${YELLOW}  Skipping D64 (c1541 not found)${NC}"
        return
    fi

    # Create disk image if it doesn't exist
    if [ ! -f "$OUTPUT_D64" ]; then
        echo -e "  Creating D64 disk image..."
        "$C1541_CMD" \
            -format "$DISK_NAME,$DISK_ID" d64 "$OUTPUT_D64" \
            2>&1 | grep -v "OPENCBM\|libopencbm"
    fi

    # Delete existing file if present, then write new one
    "$C1541_CMD" \
        -attach "$OUTPUT_D64" \
        -delete "$d64_name" \
        -write "$prg_file" "$d64_name" \
        2>&1 | grep -v "OPENCBM\|libopencbm"

    echo -e "  ${GREEN}Added to D64:${NC} ${CYAN}$d64_name${NC}"
}

launch_vice() {
    local prg_file="$1"

    echo ""
    echo -e "${YELLOW}Launching VICE with Quad-SID configuration...${NC}"

    if [ ! -x "$VICE_CMD" ]; then
        echo -e "${RED}WARNING: VICE not found at: $VICE_CMD${NC}"
        echo "  Set VICE_PATH to your x64sc installation."
        return
    fi

    "$VICE_CMD" $VICE_SID_OPTS "$prg_file" &
    echo -e "${GREEN}VICE launched! (PID: $!)${NC}"
}


# ============================================================
#  BUILD: QUADCORE
#  4 separate single-SID tunes → relocate/patch → assemble
# ============================================================

build_quadcore() {
    local DO_RUN="$1"

    echo ""
    echo -e "${CYAN}────────────────────────────────────────────${NC}"
    echo -e "${CYAN}  Building: QuadCore (Vincenzo / Singular Crew)${NC}"
    echo -e "${CYAN}────────────────────────────────────────────${NC}"
    echo ""

    # Step 1: Process SID files (relocate + patch)
    echo -e "${YELLOW}  [1/4] Processing SID files...${NC}"
    python3 "$TOOLS_DIR/sid_processor.py" quadcore
    echo ""

    # Step 2: Compile
    echo -e "${YELLOW}  [2/4] Compiling with KickAssembler...${NC}"
    check_java
    check_kickass

    local OUTPUT_PRG="$BUILD_DIR/QuadSID_Player.prg"
    compile_asm "$SRC_DIR/QuadSID_Player.asm" "$OUTPUT_PRG"

    local FILE_SIZE=$(wc -c < "$OUTPUT_PRG" | tr -d ' ')
    echo ""
    echo -e "${GREEN}  Build OK:${NC} ${CYAN}$FILE_SIZE bytes${NC}"

    # Step 3: Compress
    echo -e "${YELLOW}  [3/4] Compressing...${NC}"
    local OUTPUT_EXO="$BUILD_DIR/QuadSID_Player_exo.prg"
    compress_exomizer "$OUTPUT_PRG" "$OUTPUT_EXO"

    # Step 4: Add to D64
    echo ""
    echo -e "${YELLOW}  [4/4] Updating D64 disk image...${NC}"
    if [ -f "$OUTPUT_EXO" ]; then
        add_to_d64 "$OUTPUT_EXO" "quad sid player"
    else
        add_to_d64 "$OUTPUT_PRG" "quad sid player"
    fi

    # Launch if requested
    if [ "$DO_RUN" = "run" ]; then
        if [ -f "$OUTPUT_EXO" ]; then
            launch_vice "$OUTPUT_EXO"
        else
            launch_vice "$OUTPUT_PRG"
        fi
    fi
}


# ============================================================
#  BUILD: MEGACHASE
#  Native 4-SID PSID v4E → extract binary → assemble
# ============================================================

build_megachase() {
    local DO_RUN="$1"

    echo ""
    echo -e "${CYAN}────────────────────────────────────────────${NC}"
    echo -e "${CYAN}  Building: Mega Chase Theme (SHAD0WFAX)${NC}"
    echo -e "${CYAN}────────────────────────────────────────────${NC}"
    echo ""

    local SID_FILE="$SIDS_DIR/megachase/megachase.sid"

    if [ ! -f "$SID_FILE" ]; then
        echo -e "${RED}ERROR: SID file not found: $SID_FILE${NC}"
        exit 1
    fi

    # Step 1: Extract binary from PSID v4E
    echo -e "${YELLOW}  [1/4] Extracting binary from SID file...${NC}"
    python3 -c "
import struct
with open('$SID_FILE', 'rb') as f:
    data = f.read()
version = struct.unpack('>H', data[4:6])[0]
data_offset = struct.unpack('>H', data[6:8])[0]
load_addr = struct.unpack('<H', data[data_offset:data_offset+2])[0]
binary = data[data_offset+2:]
print(f'  Format: PSID v{version:X} | Load: \${load_addr:04X} | Size: {len(binary)} bytes (\${len(binary):04X})')
with open('$BUILD_DIR/megachase.bin', 'wb') as f:
    f.write(binary)
"
    echo ""

    # Step 2: Compile
    echo -e "${YELLOW}  [2/4] Compiling with KickAssembler...${NC}"
    check_java
    check_kickass

    local OUTPUT_PRG="$BUILD_DIR/MegaChase_Player.prg"
    compile_asm "$SRC_DIR/MegaChase_Player.asm" "$OUTPUT_PRG"

    local FILE_SIZE=$(wc -c < "$OUTPUT_PRG" | tr -d ' ')
    echo ""
    echo -e "${GREEN}  Build OK:${NC} ${CYAN}$FILE_SIZE bytes${NC}"

    # Step 3: Compress
    echo -e "${YELLOW}  [3/4] Compressing...${NC}"
    local OUTPUT_EXO="$BUILD_DIR/MegaChase_Player_exo.prg"
    compress_exomizer "$OUTPUT_PRG" "$OUTPUT_EXO"

    # Step 4: Add to D64
    echo ""
    echo -e "${YELLOW}  [4/4] Updating D64 disk image...${NC}"
    if [ -f "$OUTPUT_EXO" ]; then
        add_to_d64 "$OUTPUT_EXO" "mega chase"
    else
        add_to_d64 "$OUTPUT_PRG" "mega chase"
    fi

    # Launch if requested
    if [ "$DO_RUN" = "run" ]; then
        if [ -f "$OUTPUT_EXO" ]; then
            launch_vice "$OUTPUT_EXO"
        else
            launch_vice "$OUTPUT_PRG"
        fi
    fi
}


# ============================================================
#  BUILD: TEEN SPIRIT
#  4 separate single-SID tunes → relocate/patch → assemble
# ============================================================

build_teenspirit() {
    local DO_RUN="$1"

    echo ""
    echo -e "${CYAN}────────────────────────────────────────────${NC}"
    echo -e "${CYAN}  Building: Smells Like Teen Spirit (John Ames)${NC}"
    echo -e "${CYAN}────────────────────────────────────────────${NC}"
    echo ""

    # Step 1: Process SID files (relocate + patch)
    echo -e "${YELLOW}  [1/4] Processing SID files...${NC}"
    python3 "$TOOLS_DIR/sid_processor.py" teenspirit
    echo ""

    # Step 2: Compile
    echo -e "${YELLOW}  [2/4] Compiling with KickAssembler...${NC}"
    check_java
    check_kickass

    local OUTPUT_PRG="$BUILD_DIR/TeenSpirit_Player.prg"
    compile_asm "$SRC_DIR/TeenSpirit_Player.asm" "$OUTPUT_PRG"

    local FILE_SIZE=$(wc -c < "$OUTPUT_PRG" | tr -d ' ')
    echo ""
    echo -e "${GREEN}  Build OK:${NC} ${CYAN}$FILE_SIZE bytes${NC}"

    # Step 3: Compress
    echo -e "${YELLOW}  [3/4] Compressing...${NC}"
    local OUTPUT_EXO="$BUILD_DIR/TeenSpirit_Player_exo.prg"
    compress_exomizer "$OUTPUT_PRG" "$OUTPUT_EXO"

    # Step 4: Add to D64
    echo ""
    echo -e "${YELLOW}  [4/4] Updating D64 disk image...${NC}"
    if [ -f "$OUTPUT_EXO" ]; then
        add_to_d64 "$OUTPUT_EXO" "teen spirit"
    else
        add_to_d64 "$OUTPUT_PRG" "teen spirit"
    fi

    # Launch if requested
    if [ "$DO_RUN" = "run" ]; then
        if [ -f "$OUTPUT_EXO" ]; then
            launch_vice "$OUTPUT_EXO"
        else
            launch_vice "$OUTPUT_PRG"
        fi
    fi
}


# ============================================================
#  BUILD: SIGGRAPH INVITRO
#  Native 4-SID PSID v4E → extract binary → assemble
# ============================================================

build_siggraph() {
    local DO_RUN="$1"

    echo ""
    echo -e "${CYAN}────────────────────────────────────────────${NC}"
    echo -e "${CYAN}  Building: Siggraph Invitro 4SID (Narciso)${NC}"
    echo -e "${CYAN}────────────────────────────────────────────${NC}"
    echo ""

    local SID_FILE="$SIDS_DIR/siggraph-invitro/Siggraph_Invitro_4SID.sid"

    if [ ! -f "$SID_FILE" ]; then
        echo -e "${RED}ERROR: SID file not found: $SID_FILE${NC}"
        exit 1
    fi

    # Step 1: Extract binary from PSID v4E
    echo -e "${YELLOW}  [1/4] Extracting binary from SID file...${NC}"
    python3 -c "
import struct
with open('$SID_FILE', 'rb') as f:
    data = f.read()
version = struct.unpack('>H', data[4:6])[0]
data_offset = struct.unpack('>H', data[6:8])[0]
load_addr = struct.unpack('<H', data[data_offset:data_offset+2])[0]
binary = data[data_offset+2:]
print(f'  Format: PSID v{version:X} | Load: \${load_addr:04X} | Size: {len(binary)} bytes (\${len(binary):04X})')
with open('$BUILD_DIR/siggraph_invitro.bin', 'wb') as f:
    f.write(binary)
"
    echo ""

    # Step 2: Compile
    echo -e "${YELLOW}  [2/4] Compiling with KickAssembler...${NC}"
    check_java
    check_kickass

    local OUTPUT_PRG="$BUILD_DIR/SiggraphInvitro_Player.prg"
    compile_asm "$SRC_DIR/SiggraphInvitro_Player.asm" "$OUTPUT_PRG"

    local FILE_SIZE=$(wc -c < "$OUTPUT_PRG" | tr -d ' ')
    echo ""
    echo -e "${GREEN}  Build OK:${NC} ${CYAN}$FILE_SIZE bytes${NC}"

    # Step 3: Compress
    echo -e "${YELLOW}  [3/4] Compressing...${NC}"
    local OUTPUT_EXO="$BUILD_DIR/SiggraphInvitro_Player_exo.prg"
    compress_exomizer "$OUTPUT_PRG" "$OUTPUT_EXO"

    # Step 4: Add to D64
    echo ""
    echo -e "${YELLOW}  [4/4] Updating D64 disk image...${NC}"
    if [ -f "$OUTPUT_EXO" ]; then
        add_to_d64 "$OUTPUT_EXO" "siggraph invitro"
    else
        add_to_d64 "$OUTPUT_PRG" "siggraph invitro"
    fi

    # Launch if requested
    if [ "$DO_RUN" = "run" ]; then
        if [ -f "$OUTPUT_EXO" ]; then
            launch_vice "$OUTPUT_EXO"
        else
            launch_vice "$OUTPUT_PRG"
        fi
    fi
}


# ============================================================
#  BUILD: RAYDEN HAMMER
#  Native 4-SID RSID v4E → extract binary → assemble
#  (Category C: 4 sub-tunes with individual init/play)
# ============================================================

build_rayden_hammer() {
    local DO_RUN="$1"

    echo ""
    echo -e "${CYAN}────────────────────────────────────────────${NC}"
    echo -e "${CYAN}  Building: A-D Hammer 4SID (Rayden)${NC}"
    echo -e "${CYAN}────────────────────────────────────────────${NC}"
    echo ""

    local SID_FILE="$SIDS_DIR/rayden-hammer/A-D_Hammer_4SID.sid"

    if [ ! -f "$SID_FILE" ]; then
        echo -e "${RED}ERROR: SID file not found: $SID_FILE${NC}"
        exit 1
    fi

    # Step 1: Extract binary from RSID v4E (skip header + 2-byte load addr)
    echo -e "${YELLOW}  [1/4] Extracting binary from SID file...${NC}"
    python3 -c "
import struct
with open('$SID_FILE', 'rb') as f:
    data = f.read()
version = struct.unpack('>H', data[4:6])[0]
data_offset = struct.unpack('>H', data[6:8])[0]
load_addr = struct.unpack('<H', data[data_offset:data_offset+2])[0]
binary = data[data_offset+2:]
print(f'  Format: RSID v{version:X} | Load: \${load_addr:04X} | Size: {len(binary)} bytes (\${len(binary):04X})')
with open('$BUILD_DIR/rayden_hammer.bin', 'wb') as f:
    f.write(binary)
"
    echo ""

    # Step 2: Compile
    echo -e "${YELLOW}  [2/4] Compiling with KickAssembler...${NC}"
    check_java
    check_kickass

    local OUTPUT_PRG="$BUILD_DIR/Rayden_Hammer_Player.prg"
    compile_asm "$SRC_DIR/Rayden_Hammer_Player.asm" "$OUTPUT_PRG"

    local FILE_SIZE=$(wc -c < "$OUTPUT_PRG" | tr -d ' ')
    echo ""
    echo -e "${GREEN}  Build OK:${NC} ${CYAN}$FILE_SIZE bytes${NC}"

    # Step 3: Compress
    echo -e "${YELLOW}  [3/4] Compressing...${NC}"
    local OUTPUT_EXO="$BUILD_DIR/Rayden_Hammer_Player_exo.prg"
    compress_exomizer "$OUTPUT_PRG" "$OUTPUT_EXO"

    # Step 4: Add to D64
    echo ""
    echo -e "${YELLOW}  [4/4] Updating D64 disk image...${NC}"
    if [ -f "$OUTPUT_EXO" ]; then
        add_to_d64 "$OUTPUT_EXO" "a-d hammer"
    else
        add_to_d64 "$OUTPUT_PRG" "a-d hammer"
    fi

    # Launch if requested
    if [ "$DO_RUN" = "run" ]; then
        if [ -f "$OUTPUT_EXO" ]; then
            launch_vice "$OUTPUT_EXO"
        else
            launch_vice "$OUTPUT_PRG"
        fi
    fi
}


# ============================================================
#  BUILD: RAYDEN MON
#  Native 4-SID RSID v4E → extract binary → assemble
#  (Category C: 4 sub-tunes with individual init/play)
# ============================================================

build_rayden_mon() {
    local DO_RUN="$1"

    echo ""
    echo -e "${CYAN}────────────────────────────────────────────${NC}"
    echo -e "${CYAN}  Building: A-D Mon 4SID (Rayden)${NC}"
    echo -e "${CYAN}────────────────────────────────────────────${NC}"
    echo ""

    local SID_FILE="$SIDS_DIR/rayden-mon/A-D_Mon_4SID.sid"

    if [ ! -f "$SID_FILE" ]; then
        echo -e "${RED}ERROR: SID file not found: $SID_FILE${NC}"
        exit 1
    fi

    # Step 1: Extract binary from RSID v4E
    echo -e "${YELLOW}  [1/4] Extracting binary from SID file...${NC}"
    python3 -c "
import struct
with open('$SID_FILE', 'rb') as f:
    data = f.read()
version = struct.unpack('>H', data[4:6])[0]
data_offset = struct.unpack('>H', data[6:8])[0]
load_addr = struct.unpack('<H', data[data_offset:data_offset+2])[0]
binary = data[data_offset+2:]
print(f'  Format: RSID v{version:X} | Load: \${load_addr:04X} | Size: {len(binary)} bytes (\${len(binary):04X})')
with open('$BUILD_DIR/rayden_mon.bin', 'wb') as f:
    f.write(binary)
"
    echo ""

    # Step 2: Compile
    echo -e "${YELLOW}  [2/4] Compiling with KickAssembler...${NC}"
    check_java
    check_kickass

    local OUTPUT_PRG="$BUILD_DIR/Rayden_Mon_Player.prg"
    compile_asm "$SRC_DIR/Rayden_Mon_Player.asm" "$OUTPUT_PRG"

    local FILE_SIZE=$(wc -c < "$OUTPUT_PRG" | tr -d ' ')
    echo ""
    echo -e "${GREEN}  Build OK:${NC} ${CYAN}$FILE_SIZE bytes${NC}"

    # Step 3: Compress
    echo -e "${YELLOW}  [3/4] Compressing...${NC}"
    local OUTPUT_EXO="$BUILD_DIR/Rayden_Mon_Player_exo.prg"
    compress_exomizer "$OUTPUT_PRG" "$OUTPUT_EXO"

    # Step 4: Add to D64
    echo ""
    echo -e "${YELLOW}  [4/4] Updating D64 disk image...${NC}"
    if [ -f "$OUTPUT_EXO" ]; then
        add_to_d64 "$OUTPUT_EXO" "a-d mon"
    else
        add_to_d64 "$OUTPUT_PRG" "a-d mon"
    fi

    # Launch if requested
    if [ "$DO_RUN" = "run" ]; then
        if [ -f "$OUTPUT_EXO" ]; then
            launch_vice "$OUTPUT_EXO"
        else
            launch_vice "$OUTPUT_PRG"
        fi
    fi
}


# ============================================================
#  BUILD: RAYDEN TWICE
#  Native 4-SID RSID v4E → extract binary → assemble
#  (Category C: 4 sub-tunes with individual init/play)
# ============================================================

build_rayden_twice() {
    local DO_RUN="$1"

    echo ""
    echo -e "${CYAN}────────────────────────────────────────────${NC}"
    echo -e "${CYAN}  Building: A-D Twice 4SID (Rayden)${NC}"
    echo -e "${CYAN}────────────────────────────────────────────${NC}"
    echo ""

    local SID_FILE="$SIDS_DIR/rayden-twice/A-D_Twice_4SID.sid"

    if [ ! -f "$SID_FILE" ]; then
        echo -e "${RED}ERROR: SID file not found: $SID_FILE${NC}"
        exit 1
    fi

    # Step 1: Extract binary from RSID v4E
    echo -e "${YELLOW}  [1/4] Extracting binary from SID file...${NC}"
    python3 -c "
import struct
with open('$SID_FILE', 'rb') as f:
    data = f.read()
version = struct.unpack('>H', data[4:6])[0]
data_offset = struct.unpack('>H', data[6:8])[0]
load_addr = struct.unpack('<H', data[data_offset:data_offset+2])[0]
binary = data[data_offset+2:]
print(f'  Format: RSID v{version:X} | Load: \${load_addr:04X} | Size: {len(binary)} bytes (\${len(binary):04X})')
with open('$BUILD_DIR/rayden_twice.bin', 'wb') as f:
    f.write(binary)
"
    echo ""

    # Step 2: Compile
    echo -e "${YELLOW}  [2/4] Compiling with KickAssembler...${NC}"
    check_java
    check_kickass

    local OUTPUT_PRG="$BUILD_DIR/Rayden_Twice_Player.prg"
    compile_asm "$SRC_DIR/Rayden_Twice_Player.asm" "$OUTPUT_PRG"

    local FILE_SIZE=$(wc -c < "$OUTPUT_PRG" | tr -d ' ')
    echo ""
    echo -e "${GREEN}  Build OK:${NC} ${CYAN}$FILE_SIZE bytes${NC}"

    # Step 3: Compress
    echo -e "${YELLOW}  [3/4] Compressing...${NC}"
    local OUTPUT_EXO="$BUILD_DIR/Rayden_Twice_Player_exo.prg"
    compress_exomizer "$OUTPUT_PRG" "$OUTPUT_EXO"

    # Step 4: Add to D64
    echo ""
    echo -e "${YELLOW}  [4/4] Updating D64 disk image...${NC}"
    if [ -f "$OUTPUT_EXO" ]; then
        add_to_d64 "$OUTPUT_EXO" "a-d twice"
    else
        add_to_d64 "$OUTPUT_PRG" "a-d twice"
    fi

    # Launch if requested
    if [ "$DO_RUN" = "run" ]; then
        if [ -f "$OUTPUT_EXO" ]; then
            launch_vice "$OUTPUT_EXO"
        else
            launch_vice "$OUTPUT_PRG"
        fi
    fi
}


# ============================================================
#  BUILD: HERMIT 4SID EXAMPLE
#  Native 4-SID PSID v4E → extract binary → assemble
# ============================================================

build_hermit() {
    local DO_RUN="$1"

    echo ""
    echo -e "${CYAN}────────────────────────────────────────────${NC}"
    echo -e "${CYAN}  Building: 4SID Example-Tune (HERMIT)${NC}"
    echo -e "${CYAN}────────────────────────────────────────────${NC}"
    echo ""

    local SID_FILE="$SIDS_DIR/hermit-4sid-example/4SID-example.sid"

    if [ ! -f "$SID_FILE" ]; then
        echo -e "${RED}ERROR: SID file not found: $SID_FILE${NC}"
        exit 1
    fi

    # Step 1: Extract binary from PSID v4E
    echo -e "${YELLOW}  [1/4] Extracting binary from SID file...${NC}"
    python3 -c "
import struct
with open('$SID_FILE', 'rb') as f:
    data = f.read()
version = struct.unpack('>H', data[4:6])[0]
data_offset = struct.unpack('>H', data[6:8])[0]
load_addr = struct.unpack('<H', data[data_offset:data_offset+2])[0]
binary = data[data_offset+2:]
print(f'  Format: PSID v{version:X} | Load: \${load_addr:04X} | Size: {len(binary)} bytes (\${len(binary):04X})')
with open('$BUILD_DIR/hermit4sid.bin', 'wb') as f:
    f.write(binary)
"
    echo ""

    # Step 2: Compile
    echo -e "${YELLOW}  [2/4] Compiling with KickAssembler...${NC}"
    check_java
    check_kickass

    local OUTPUT_PRG="$BUILD_DIR/Hermit4SID_Player.prg"
    compile_asm "$SRC_DIR/Hermit4SID_Player.asm" "$OUTPUT_PRG"

    local FILE_SIZE=$(wc -c < "$OUTPUT_PRG" | tr -d ' ')
    echo ""
    echo -e "${GREEN}  Build OK:${NC} ${CYAN}$FILE_SIZE bytes${NC}"

    # Step 3: Compress
    echo -e "${YELLOW}  [3/4] Compressing...${NC}"
    local OUTPUT_EXO="$BUILD_DIR/Hermit4SID_Player_exo.prg"
    compress_exomizer "$OUTPUT_PRG" "$OUTPUT_EXO"

    # Step 4: Add to D64
    echo ""
    echo -e "${YELLOW}  [4/4] Updating D64 disk image...${NC}"
    if [ -f "$OUTPUT_EXO" ]; then
        add_to_d64 "$OUTPUT_EXO" "4sid example"
    else
        add_to_d64 "$OUTPUT_PRG" "4sid example"
    fi

    # Launch if requested
    if [ "$DO_RUN" = "run" ]; then
        if [ -f "$OUTPUT_EXO" ]; then
            launch_vice "$OUTPUT_EXO"
        else
            launch_vice "$OUTPUT_PRG"
        fi
    fi
}


# ============================================================
#  MAIN ENTRY POINT
# ============================================================

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  EVO64 Super Quattro - 4-SID Demo Builder${NC}"
echo -e "${CYAN}============================================${NC}"

# Create build directory
mkdir -p "$BUILD_DIR"

# Parse arguments
DEMO="${1:-}"
ACTION="${2:-}"

case "$DEMO" in
    quadcore|quad)
        build_quadcore "$ACTION"
        ;;

    megachase|mega)
        build_megachase "$ACTION"
        ;;

    hermit)
        build_hermit "$ACTION"
        ;;

    siggraph)
        build_siggraph "$ACTION"
        ;;

    teenspirit|teen)
        build_teenspirit "$ACTION"
        ;;

    hammer)
        build_rayden_hammer "$ACTION"
        ;;

    mon)
        build_rayden_mon "$ACTION"
        ;;

    twice)
        build_rayden_twice "$ACTION"
        ;;

    all)
        build_quadcore
        build_megachase
        build_hermit
        build_siggraph
        build_teenspirit
        build_rayden_hammer
        build_rayden_mon
        build_rayden_twice
        # Add SID tester utility to D64
        if [ -f "$TOOLS_DIR/multisid-tester.prg" ]; then
            echo ""
            echo -e "${YELLOW}  Adding SID Tester utility to D64...${NC}"
            add_to_d64 "$TOOLS_DIR/multisid-tester.prg" "sid tester"
        fi
        ;;

    clean)
        echo ""
        echo -e "${YELLOW}Cleaning build artifacts...${NC}"
        rm -f "$BUILD_DIR"/*.bin
        rm -f "$BUILD_DIR"/*.prg
        rm -f "$BUILD_DIR"/*.inc
        rm -f "$BUILD_DIR"/*.sym
        rm -f "$BUILD_DIR"/*.vs
        rm -f "$BUILD_DIR"/*.d64
        echo -e "${GREEN}Clean complete.${NC}"
        exit 0
        ;;

    list)
        echo ""
        echo "  Available demos:"
        echo ""
        echo -e "    ${CYAN}quadcore${NC}    QuadCore by Vincenzo / Singular Crew"
        echo "              4 separate single-SID tunes, relocated + patched"
        echo -e "              Source: ${LGREY}sids/quadcore/${NC}"
        echo ""
        echo -e "    ${CYAN}megachase${NC}   Mega Chase Theme by SHAD0WFAX"
        echo "              Native 4-SID composition (PSID v4E)"
        echo -e "              Source: ${LGREY}sids/megachase/${NC}"
        echo ""
        echo -e "    ${CYAN}hermit${NC}      4SID Example-Tune by HERMIT"
        echo "              Native 4-SID composition (PSID v4E)"
        echo -e "              Source: ${LGREY}sids/hermit-4sid-example/${NC}"
        echo ""
        echo -e "    ${CYAN}siggraph${NC}    Siggraph Invitro 4SID by Narciso"
        echo "              Native 4-SID composition (PSID v4E)"
        echo -e "              Source: ${LGREY}sids/siggraph-invitro/${NC}"
        echo ""
        echo -e "    ${CYAN}teenspirit${NC}  Smells Like Teen Spirit by John Ames"
        echo "              4 separate single-SID tunes, relocated + patched"
        echo -e "              Source: ${LGREY}sids/smells-like-team-spirit/${NC}"
        echo ""
        echo -e "    ${CYAN}hammer${NC}      A-D Hammer 4SID by Rayden"
        echo "              Native 4-SID composition (RSID v4E, 4 sub-tunes)"
        echo -e "              Source: ${LGREY}sids/rayden-hammer/${NC}"
        echo ""
        echo -e "    ${CYAN}mon${NC}         A-D Mon 4SID by Rayden"
        echo "              Native 4-SID composition (RSID v4E, 4 sub-tunes)"
        echo -e "              Source: ${LGREY}sids/rayden-mon/${NC}"
        echo ""
        echo -e "    ${CYAN}twice${NC}       A-D Twice 4SID by Rayden"
        echo "              Native 4-SID composition (RSID v4E, 4 sub-tunes)"
        echo -e "              Source: ${LGREY}sids/rayden-twice/${NC}"
        echo ""
        exit 0
        ;;

    "")
        echo ""
        echo "  Usage: $0 <demo> [run]"
        echo ""
        echo "  Commands:"
        echo -e "    ${CYAN}$0 quadcore${NC}        Build QuadCore demo"
        echo -e "    ${CYAN}$0 megachase${NC}       Build Mega Chase demo"
        echo -e "    ${CYAN}$0 hermit${NC}          Build Hermit 4SID Example demo"
        echo -e "    ${CYAN}$0 siggraph${NC}        Build Siggraph Invitro demo"
        echo -e "    ${CYAN}$0 teenspirit${NC}      Build Teen Spirit demo"
        echo -e "    ${CYAN}$0 hammer${NC}          Build Rayden Hammer demo"
        echo -e "    ${CYAN}$0 mon${NC}             Build Rayden Mon demo"
        echo -e "    ${CYAN}$0 twice${NC}           Build Rayden Twice demo"
        echo -e "    ${CYAN}$0 all${NC}             Build all demos"
        echo -e "    ${CYAN}$0 <demo> run${NC}      Build and launch in VICE"
        echo -e "    ${CYAN}$0 clean${NC}           Remove build artifacts"
        echo -e "    ${CYAN}$0 list${NC}            List available demos"
        echo ""
        exit 0
        ;;

    *)
        echo ""
        echo -e "${RED}Unknown demo: $DEMO${NC}"
        echo "  Run '$0 list' to see available demos."
        echo ""
        exit 1
        ;;
esac

# Show D64 contents if it exists
if [ -f "$OUTPUT_D64" ] && [ -x "$C1541_CMD" ]; then
    echo ""
    echo -e "${GREEN}────────────────────────────────────────────${NC}"
    echo -e "${GREEN}  D64 Disk Image Contents${NC}"
    echo -e "${GREEN}────────────────────────────────────────────${NC}"
    "$C1541_CMD" -attach "$OUTPUT_D64" -list 2>&1 | grep -v "OPENCBM\|libopencbm\|recognised\|attached\|detached"
fi

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Build Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "  To run in VICE:"
echo -e "    ${CYAN}./build.sh <demo> run${NC}"
echo -e "    ${CYAN}./vice-quad-sid-play.sh <demo>${NC}"
echo ""
