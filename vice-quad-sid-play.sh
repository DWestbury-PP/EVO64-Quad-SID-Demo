#!/bin/bash
# ============================================================
#  EVO64 Super Quattro - VICE Quad SID Launcher
# ============================================================
#
#  Launches 4-SID demos in VICE with all 4 SID chips enabled.
#
#  Usage:
#    ./vice-quad-sid-play.sh quadcore        # Launch QuadCore demo
#    ./vice-quad-sid-play.sh megachase       # Launch Mega Chase demo
#    ./vice-quad-sid-play.sh <demo> --debug  # Enable remote monitor
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
#  Debug mode (--debug):
#    Enables VICE's remote monitor on port 6510.
#    Connect with:  telnet 127.0.0.1 6510
#
# ============================================================

# Default VICE path (arm64 VICE 3.10 binary)
VICE_PATH="${VICE_PATH:-/Users/dwestbury/Documents/Tech_Stuff/Electronics/Commodore Projects/C64 Emulation/vice-arm64-gtk3-3.10/bin/x64sc}"

# Project paths
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"

# Quad SID addressing configuration (same for all demos)
SID_OPTS="-sidextra 3 -sid2address 0xD420 -sid3address 0xD440 -sid4address 0xD460"

# Parse arguments
DEMO=""
DEBUG_OPTS=""
DEBUG_MODE=false

for arg in "$@"; do
    case "$arg" in
        --debug)
            DEBUG_MODE=true
            DEBUG_OPTS="-remotemonitor -remotemonitoraddress ip4://127.0.0.1:6510 -keepmonopen"
            ;;
        quadcore|quad)
            DEMO="quadcore"
            ;;
        megachase|mega)
            DEMO="megachase"
            ;;
        *)
            echo "Unknown argument: $arg"
            echo ""
            echo "Usage: $0 [quadcore|megachase] [--debug]"
            exit 1
            ;;
    esac
done

# Show usage if no demo specified
if [ -z "$DEMO" ]; then
    echo ""
    echo "  Usage: $0 <demo> [--debug]"
    echo ""
    echo "  Available demos:"
    echo "    quadcore    QuadCore (Vincenzo / Singular Crew)"
    echo "    megachase   Mega Chase Theme (SHAD0WFAX)"
    echo ""
    exit 0
fi

# Select the PRG file based on demo choice
case "$DEMO" in
    quadcore)
        DEMO_NAME="QuadCore - Vincenzo / Singular Crew"
        PRG_EXO="$PROJECT_ROOT/build/QuadSID_Player_exo.prg"
        PRG_RAW="$PROJECT_ROOT/build/QuadSID_Player.prg"
        BUILD_CMD="./build.sh"
        ;;
    megachase)
        DEMO_NAME="Mega Chase Theme - SHAD0WFAX"
        PRG_EXO="$PROJECT_ROOT/build/MegaChase_Player_exo.prg"
        PRG_RAW="$PROJECT_ROOT/build/MegaChase_Player.prg"
        BUILD_CMD="./build-megachase.sh"
        ;;
esac

# Prefer compressed version if available
if [ -f "$PRG_EXO" ]; then
    PRG_FILE="$PRG_EXO"
else
    PRG_FILE="$PRG_RAW"
fi

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
echo -e "  Demo: ${YELLOW}$DEMO_NAME${NC}"
echo ""

# Check that the PRG exists
if [ ! -f "$PRG_FILE" ]; then
    echo -e "${RED}ERROR: Build output not found.${NC}"
    echo "  Run $BUILD_CMD first to compile the project."
    exit 1
fi

# Resolve the actual x64sc binary
if [[ "$VICE_PATH" == *.app ]]; then
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

if $DEBUG_MODE; then
    echo -e "  ${YELLOW}DEBUG MODE ENABLED${NC}"
    echo -e "    Remote monitor: ${CYAN}telnet 127.0.0.1 6510${NC}"
    echo ""
fi

echo -e "${YELLOW}Launching VICE...${NC}"
echo ""

"$VICE_BIN" $SID_OPTS $DEBUG_OPTS "$PRG_FILE" &

echo -e "${GREEN}VICE launched! (PID: $!)${NC}"
echo ""
echo "  Available demos:"
echo -e "    ${CYAN}./vice-quad-sid-play.sh quadcore${NC}    QuadCore (4 separate SIDs)"
echo -e "    ${CYAN}./vice-quad-sid-play.sh megachase${NC}   Mega Chase (native 4-SID)"
echo ""
