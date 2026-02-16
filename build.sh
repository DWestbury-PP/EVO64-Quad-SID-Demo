#!/bin/bash
# ============================================================
#  EVO64 Super Quattro - Quad SID Player Build Script
# ============================================================
#
#  Usage:
#    ./build.sh              Build the project
#    ./build.sh run          Build and launch in VICE
#    ./build.sh clean        Remove build artifacts
#    ./build.sh process      Only run SID processor (no compile)
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
KICKASS_JAR="$PROJECT_ROOT/KickAssembler/KickAss.jar"

# Source files
MAIN_ASM="$SRC_DIR/QuadSID_Player.asm"
OUTPUT_PRG="$BUILD_DIR/QuadSID_Player.prg"

# VICE emulator
# Set VICE_PATH env var to your x64sc binary or .app bundle
VICE_PATH="${VICE_PATH:-/Users/dwestbury/Documents/Tech_Stuff/Electronics/Commodore Projects/C64 Emulation/vice-arm64-gtk3-3.10/bin/x64sc}"

# Resolve the binary (handle .app bundles or direct paths)
if [[ "$VICE_PATH" == *.app ]]; then
    VICE_CMD="$VICE_PATH/Contents/Resources/bin/x64sc"
else
    VICE_CMD="$VICE_PATH"
fi

# VICE Quad-SID configuration
VICE_SID_OPTS="-sidextra 3 -sid2address 0xD420 -sid3address 0xD440 -sid4address 0xD460"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  EVO64 Super Quattro - Quad SID Player${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

# Create build directory
mkdir -p "$BUILD_DIR"

# ---- Handle commands ----

case "${1:-build}" in
    clean)
        echo -e "${YELLOW}Cleaning build artifacts...${NC}"
        rm -f "$BUILD_DIR"/*.bin
        rm -f "$BUILD_DIR"/*.prg
        rm -f "$BUILD_DIR"/*.inc
        rm -f "$BUILD_DIR"/*.sym
        rm -f "$BUILD_DIR"/*.vs
        echo -e "${GREEN}Clean complete.${NC}"
        exit 0
        ;;

    process)
        echo -e "${YELLOW}Step 1: Processing SID files...${NC}"
        python3 "$TOOLS_DIR/sid_processor.py"
        echo -e "${GREEN}SID processing complete.${NC}"
        exit 0
        ;;

    run|build)
        # Continue with build
        ;;

    *)
        echo "Usage: $0 [build|run|clean|process]"
        exit 1
        ;;
esac

# ---- Step 1: Process SID files ----
echo -e "${YELLOW}Step 1: Processing SID files...${NC}"
python3 "$TOOLS_DIR/sid_processor.py"
echo ""

# ---- Step 2: Compile with KickAssembler ----
echo -e "${YELLOW}Step 2: Compiling with KickAssembler...${NC}"

if [ ! -f "$KICKASS_JAR" ]; then
    echo -e "${RED}ERROR: KickAssembler not found at: $KICKASS_JAR${NC}"
    echo "Please ensure KickAss.jar is in the KickAssembler/ directory."
    exit 1
fi

# Check for Java
if ! command -v java &> /dev/null; then
    echo -e "${RED}ERROR: Java is not installed.${NC}"
    echo ""
    echo "KickAssembler requires Java. Install it with:"
    echo "  brew install openjdk"
    echo ""
    echo "Or download from: https://adoptium.net/"
    echo ""
    echo -e "${YELLOW}NOTE: SID processing completed successfully.${NC}"
    echo "Patched binaries are in: $BUILD_DIR/"
    echo "Once Java is installed, run this script again to compile."
    exit 1
fi

# Run KickAssembler
# -odir: output directory
# -showmem: show memory map
# -symbolfile: generate symbol file for debugging
java -jar "$KICKASS_JAR" \
    "$MAIN_ASM" \
    -odir "$BUILD_DIR" \
    -o "$OUTPUT_PRG" \
    -showmem \
    -symbolfile

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}Build successful!${NC}"
    echo -e "  Output: ${CYAN}$OUTPUT_PRG${NC}"
    FILE_SIZE=$(wc -c < "$OUTPUT_PRG" | tr -d ' ')
    echo -e "  Size:   ${CYAN}$FILE_SIZE bytes${NC}"
else
    echo -e "${RED}Build FAILED!${NC}"
    exit 1
fi

# ---- Step 3: Compress with Exomizer ----
OUTPUT_EXO="$BUILD_DIR/QuadSID_Player_exo.prg"

if command -v exomizer &> /dev/null; then
    echo ""
    echo -e "${YELLOW}Step 3: Compressing with Exomizer...${NC}"
    exomizer sfx sys -t64 -n -o "$OUTPUT_EXO" "$OUTPUT_PRG"

    if [ $? -eq 0 ]; then
        EXO_SIZE=$(wc -c < "$OUTPUT_EXO" | tr -d ' ')
        RATIO=$(( (FILE_SIZE - EXO_SIZE) * 100 / FILE_SIZE ))
        echo ""
        echo -e "${GREEN}Compression successful!${NC}"
        echo -e "  Original:   ${CYAN}$FILE_SIZE bytes${NC}"
        echo -e "  Compressed: ${CYAN}$EXO_SIZE bytes${NC}  (${RATIO}% reduction)"
        echo -e "  Output:     ${CYAN}$OUTPUT_EXO${NC}"
    else
        echo -e "${RED}WARNING: Exomizer compression failed. Uncompressed PRG still available.${NC}"
    fi
else
    echo ""
    echo -e "${YELLOW}Step 3: Skipping compression (Exomizer not installed)${NC}"
    echo "  Install with: brew install exomizer"
fi

# ---- Step 4: Launch in VICE (if requested) ----
if [ "$1" = "run" ]; then
    echo ""
    echo -e "${YELLOW}Step 4: Launching VICE with Quad-SID configuration...${NC}"

    if [ ! -x "$VICE_CMD" ]; then
        echo -e "${RED}WARNING: VICE not found at: $VICE_CMD${NC}"
        echo ""
        echo "Set VICE_PATH to your x64sc installation:"
        echo "  export VICE_PATH=\"/path/to/x64sc.app\""
        echo ""
        echo "Or use the standalone launcher:"
        echo -e "  ${CYAN}./vice-quad-sid-play.sh${NC}"
        exit 0
    fi

    echo "VICE command:"
    echo "  $VICE_CMD $VICE_SID_OPTS $OUTPUT_PRG"
    echo ""

    $VICE_CMD $VICE_SID_OPTS "$OUTPUT_PRG" &
    echo -e "${GREEN}VICE launched!${NC}"
fi

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Build Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "  Output files:"
echo -e "    ${CYAN}$OUTPUT_PRG${NC}  (uncompressed)"
if [ -f "$OUTPUT_EXO" ]; then
echo -e "    ${CYAN}$OUTPUT_EXO${NC}  (Exomizer compressed)"
fi
echo ""
echo "  To run in VICE:"
echo -e "  ${CYAN}./vice-quad-sid-play.sh${NC}"
echo -e "  ${CYAN}./build.sh run${NC}"
echo ""
