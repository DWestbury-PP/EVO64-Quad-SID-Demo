#!/bin/bash
# ============================================================
#  EVO64 Super Quattro - VICE Quad SID Launcher
# ============================================================
#
#  Launches the Quad SID Player in VICE with 4 SID chips enabled.
#
#  Configuration:
#    Set the VICE_PATH environment variable to your x64sc binary.
#    You can export it in your shell profile (~/.zshrc) or pass
#    it inline:
#
#      export VICE_PATH="/path/to/x64sc.app"
#      ./vice-quad-sid-play.sh
#
#    Or:
#      VICE_PATH="/path/to/x64sc.app" ./vice-quad-sid-play.sh
#
# ============================================================

# Default VICE path (arm64 VICE 3.10 binary)
VICE_PATH="${VICE_PATH:-/Users/dwestbury/Documents/Tech_Stuff/Electronics/Commodore Projects/C64 Emulation/vice-arm64-gtk3-3.10/bin/x64sc}"

# Project paths
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
PRG_FILE="$PROJECT_ROOT/build/QuadSID_Player.prg"

# Quad SID addressing configuration
SID_OPTS="-sidextra 3 -sid2address 0xD420 -sid3address 0xD440 -sid4address 0xD460"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  EVO64 Super Quattro - Quad SID Launcher${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

# Check that the PRG exists
if [ ! -f "$PRG_FILE" ]; then
    echo -e "${RED}ERROR: Build output not found: $PRG_FILE${NC}"
    echo "Run ./build.sh first to compile the project."
    exit 1
fi

# Resolve the actual x64sc binary
if [[ "$VICE_PATH" == *.app ]]; then
    # Try both common .app bundle layouts
    VICE_BIN="$VICE_PATH/Contents/Resources/bin/x64sc"
    if [ ! -x "$VICE_BIN" ]; then
        VICE_BIN="$VICE_PATH/Contents/MacOS/x64sc"
    fi
    if [ ! -x "$VICE_BIN" ]; then
        echo -e "${RED}ERROR: Could not find x64sc binary inside app bundle.${NC}"
        echo "  VICE_PATH: $VICE_PATH"
        echo ""
        echo "  Set VICE_PATH to the x64sc binary directly:"
        echo "    export VICE_PATH=\"/path/to/vice/bin/x64sc\""
        exit 1
    fi
else
    VICE_BIN="$VICE_PATH"
fi

# Verify the binary exists and is executable
if [ ! -x "$VICE_BIN" ]; then
    echo -e "${RED}ERROR: VICE binary not found or not executable.${NC}"
    echo "  VICE_PATH: $VICE_PATH"
    echo "  Binary:    $VICE_BIN"
    echo ""
    echo "  Set VICE_PATH to point to your x64sc installation:"
    echo "    export VICE_PATH=\"/path/to/x64sc.app\""
    echo "    export VICE_PATH=\"/path/to/x64sc\"        (direct binary)"
    exit 1
fi

echo -e "  VICE:  ${CYAN}$VICE_BIN${NC}"
echo -e "  PRG:   ${CYAN}$PRG_FILE${NC}"
echo ""
echo -e "  SID Configuration:"
echo -e "    SID 1: ${GREEN}\$D400${NC} (primary)"
echo -e "    SID 2: ${GREEN}\$D420${NC} (extra 1)"
echo -e "    SID 3: ${GREEN}\$D440${NC} (extra 2)"
echo -e "    SID 4: ${GREEN}\$D460${NC} (extra 3)"
echo ""

echo -e "${YELLOW}Launching VICE...${NC}"
echo ""

"$VICE_BIN" $SID_OPTS "$PRG_FILE" &

echo -e "${GREEN}VICE launched! (PID: $!)${NC}"
echo ""
