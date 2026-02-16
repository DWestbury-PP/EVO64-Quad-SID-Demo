#!/usr/bin/env python3
"""
SID Processor Tool for the EVO64 Super Quattro Quad-SID Player
==============================================================

This tool processes .sid files for the Quad-SID Player project:
  1. Parses PSID/RSID file headers
  2. Extracts the C64 binary (code + data)
  3. Uses RECURSIVE DESCENT disassembly from known entry points to
     accurately distinguish code regions from data regions
  4. Relocates code to a new base address (only within confirmed code)
  5. Patches SID register addresses ($D400 -> $D4xx)
  6. Precisely identifies pointer tables in data regions via code analysis
  7. Generates output binaries and KickAssembler include files

Usage:
    python3 sid_processor.py [--analyze-only]

Author: EVO64 Super Quattro Project, 2026
"""

import struct
import sys
import os
from pathlib import Path
from collections import defaultdict

# =============================================================================
# 6502/6510 INSTRUCTION SET
# =============================================================================

# Addressing modes
IMP = 'IMP'   # Implicit / Implied (1 byte)
ACC = 'ACC'   # Accumulator (1 byte)
IMM = 'IMM'   # Immediate (2 bytes)
ZP  = 'ZP'    # Zero Page (2 bytes)
ZPX = 'ZPX'   # Zero Page,X (2 bytes)
ZPY = 'ZPY'   # Zero Page,Y (2 bytes)
ABS = 'ABS'   # Absolute (3 bytes) -- 16-bit address, RELOCATABLE
ABX = 'ABX'   # Absolute,X (3 bytes) -- RELOCATABLE
ABY = 'ABY'   # Absolute,Y (3 bytes) -- RELOCATABLE
IND = 'IND'   # Indirect (3 bytes, JMP only) -- RELOCATABLE
IZX = 'IZX'   # (Indirect,X) (2 bytes, zero page pointer)
IZY = 'IZY'   # (Indirect),Y (2 bytes, zero page pointer)
REL = 'REL'   # Relative (2 bytes, branches)

# Instruction length by addressing mode
MODE_SIZE = {
    IMP: 1, ACC: 1,
    IMM: 2, ZP: 2, ZPX: 2, ZPY: 2, IZX: 2, IZY: 2, REL: 2,
    ABS: 3, ABX: 3, ABY: 3, IND: 3,
}

# Modes with 16-bit absolute addresses in the operand
ABS_MODES = frozenset({ABS, ABX, ABY, IND})

# Complete 6502 opcode table (all 256 entries mapped)
# Format: opcode -> (mnemonic, addressing_mode)
OPCODES = {
    # --- Official opcodes ---
    0x00: ('BRK', IMP), 0x01: ('ORA', IZX), 0x05: ('ORA', ZP),
    0x06: ('ASL', ZP),  0x08: ('PHP', IMP), 0x09: ('ORA', IMM),
    0x0A: ('ASL', ACC), 0x0D: ('ORA', ABS), 0x0E: ('ASL', ABS),
    0x10: ('BPL', REL), 0x11: ('ORA', IZY), 0x15: ('ORA', ZPX),
    0x16: ('ASL', ZPX), 0x18: ('CLC', IMP), 0x19: ('ORA', ABY),
    0x1D: ('ORA', ABX), 0x1E: ('ASL', ABX),
    0x20: ('JSR', ABS), 0x21: ('AND', IZX), 0x24: ('BIT', ZP),
    0x25: ('AND', ZP),  0x26: ('ROL', ZP),  0x28: ('PLP', IMP),
    0x29: ('AND', IMM), 0x2A: ('ROL', ACC), 0x2C: ('BIT', ABS),
    0x2D: ('AND', ABS), 0x2E: ('ROL', ABS),
    0x30: ('BMI', REL), 0x31: ('AND', IZY), 0x35: ('AND', ZPX),
    0x36: ('ROL', ZPX), 0x38: ('SEC', IMP), 0x39: ('AND', ABY),
    0x3D: ('AND', ABX), 0x3E: ('ROL', ABX),
    0x40: ('RTI', IMP), 0x41: ('EOR', IZX), 0x45: ('EOR', ZP),
    0x46: ('LSR', ZP),  0x48: ('PHA', IMP), 0x49: ('EOR', IMM),
    0x4A: ('LSR', ACC), 0x4C: ('JMP', ABS), 0x4D: ('EOR', ABS),
    0x4E: ('LSR', ABS),
    0x50: ('BVC', REL), 0x51: ('EOR', IZY), 0x55: ('EOR', ZPX),
    0x56: ('LSR', ZPX), 0x58: ('CLI', IMP), 0x59: ('EOR', ABY),
    0x5D: ('EOR', ABX), 0x5E: ('LSR', ABX),
    0x60: ('RTS', IMP), 0x61: ('ADC', IZX), 0x65: ('ADC', ZP),
    0x66: ('ROR', ZP),  0x68: ('PLA', IMP), 0x69: ('ADC', IMM),
    0x6A: ('ROR', ACC), 0x6C: ('JMP', IND), 0x6D: ('ADC', ABS),
    0x6E: ('ROR', ABS),
    0x70: ('BVS', REL), 0x71: ('ADC', IZY), 0x75: ('ADC', ZPX),
    0x76: ('ROR', ZPX), 0x78: ('SEI', IMP), 0x79: ('ADC', ABY),
    0x7D: ('ADC', ABX), 0x7E: ('ROR', ABX),
    0x81: ('STA', IZX), 0x84: ('STY', ZP),  0x85: ('STA', ZP),
    0x86: ('STX', ZP),  0x88: ('DEY', IMP), 0x8A: ('TXA', IMP),
    0x8C: ('STY', ABS), 0x8D: ('STA', ABS), 0x8E: ('STX', ABS),
    0x90: ('BCC', REL), 0x91: ('STA', IZY), 0x94: ('STY', ZPX),
    0x95: ('STA', ZPX), 0x96: ('STX', ZPY), 0x98: ('TYA', IMP),
    0x99: ('STA', ABY), 0x9A: ('TXS', IMP), 0x9D: ('STA', ABX),
    0xA0: ('LDY', IMM), 0xA1: ('LDA', IZX), 0xA2: ('LDX', IMM),
    0xA4: ('LDY', ZP),  0xA5: ('LDA', ZP),  0xA6: ('LDX', ZP),
    0xA8: ('TAY', IMP), 0xA9: ('LDA', IMM), 0xAA: ('TAX', IMP),
    0xAC: ('LDY', ABS), 0xAD: ('LDA', ABS), 0xAE: ('LDX', ABS),
    0xB0: ('BCS', REL), 0xB1: ('LDA', IZY), 0xB4: ('LDY', ZPX),
    0xB5: ('LDA', ZPX), 0xB6: ('LDX', ZPY), 0xB8: ('CLV', IMP),
    0xB9: ('LDA', ABY), 0xBA: ('TSX', IMP), 0xBC: ('LDY', ABX),
    0xBD: ('LDA', ABX), 0xBE: ('LDX', ABY),
    0xC0: ('CPY', IMM), 0xC1: ('CMP', IZX), 0xC4: ('CPY', ZP),
    0xC5: ('CMP', ZP),  0xC6: ('DEC', ZP),  0xC8: ('INY', IMP),
    0xC9: ('CMP', IMM), 0xCA: ('DEX', IMP), 0xCC: ('CPY', ABS),
    0xCD: ('CMP', ABS), 0xCE: ('DEC', ABS),
    0xD0: ('BNE', REL), 0xD1: ('CMP', IZY), 0xD5: ('CMP', ZPX),
    0xD6: ('DEC', ZPX), 0xD8: ('CLD', IMP), 0xD9: ('CMP', ABY),
    0xDD: ('CMP', ABX), 0xDE: ('DEC', ABX),
    0xE0: ('CPX', IMM), 0xE1: ('SBC', IZX), 0xE4: ('CPX', ZP),
    0xE5: ('SBC', ZP),  0xE6: ('INC', ZP),  0xE8: ('INX', IMP),
    0xE9: ('SBC', IMM), 0xEA: ('NOP', IMP), 0xEC: ('CPX', ABS),
    0xED: ('SBC', ABS), 0xEE: ('INC', ABS),
    0xF0: ('BEQ', REL), 0xF1: ('SBC', IZY), 0xF5: ('SBC', ZPX),
    0xF6: ('INC', ZPX), 0xF8: ('SED', IMP), 0xF9: ('SBC', ABY),
    0xFD: ('SBC', ABX), 0xFE: ('INC', ABX),

    # --- Illegal/Undocumented opcodes ---
    # SLO (ASL + ORA)
    0x03: ('SLO', IZX), 0x07: ('SLO', ZP),  0x0F: ('SLO', ABS),
    0x13: ('SLO', IZY), 0x17: ('SLO', ZPX), 0x1B: ('SLO', ABY),
    0x1F: ('SLO', ABX),
    # RLA (ROL + AND)
    0x23: ('RLA', IZX), 0x27: ('RLA', ZP),  0x2F: ('RLA', ABS),
    0x33: ('RLA', IZY), 0x37: ('RLA', ZPX), 0x3B: ('RLA', ABY),
    0x3F: ('RLA', ABX),
    # SRE (LSR + EOR)
    0x43: ('SRE', IZX), 0x47: ('SRE', ZP),  0x4F: ('SRE', ABS),
    0x53: ('SRE', IZY), 0x57: ('SRE', ZPX), 0x5B: ('SRE', ABY),
    0x5F: ('SRE', ABX),
    # RRA (ROR + ADC)
    0x63: ('RRA', IZX), 0x67: ('RRA', ZP),  0x6F: ('RRA', ABS),
    0x73: ('RRA', IZY), 0x77: ('RRA', ZPX), 0x7B: ('RRA', ABY),
    0x7F: ('RRA', ABX),
    # SAX (store A & X)
    0x83: ('SAX', IZX), 0x87: ('SAX', ZP),  0x8F: ('SAX', ABS),
    0x97: ('SAX', ZPY),
    # LAX (LDA + LDX)
    0xA3: ('LAX', IZX), 0xA7: ('LAX', ZP),  0xAF: ('LAX', ABS),
    0xB3: ('LAX', IZY), 0xB7: ('LAX', ZPY), 0xBF: ('LAX', ABY),
    # DCP (DEC + CMP)
    0xC3: ('DCP', IZX), 0xC7: ('DCP', ZP),  0xCF: ('DCP', ABS),
    0xD3: ('DCP', IZY), 0xD7: ('DCP', ZPX), 0xDB: ('DCP', ABY),
    0xDF: ('DCP', ABX),
    # ISC/ISB (INC + SBC)
    0xE3: ('ISC', IZX), 0xE7: ('ISC', ZP),  0xEF: ('ISC', ABS),
    0xF3: ('ISC', IZY), 0xF7: ('ISC', ZPX), 0xFB: ('ISC', ABY),
    0xFF: ('ISC', ABX),
    # ANC, ALR, ARR, ANE, LXA, SBX, USBC
    0x0B: ('ANC', IMM), 0x2B: ('ANC', IMM), 0x4B: ('ALR', IMM),
    0x6B: ('ARR', IMM), 0x8B: ('ANE', IMM), 0xAB: ('LXA', IMM),
    0xCB: ('SBX', IMM), 0xEB: ('USB', IMM),
    # SHA/SHY/SHX/TAS/LAS
    0x93: ('SHA', IZY), 0x9F: ('SHA', ABY),
    0x9C: ('SHY', ABX), 0x9E: ('SHX', ABY), 0x9B: ('TAS', ABY),
    0xBB: ('LAS', ABY),
    # Multi-byte NOP variants
    0x04: ('NOP', ZP),  0x14: ('NOP', ZPX), 0x34: ('NOP', ZPX),
    0x44: ('NOP', ZP),  0x54: ('NOP', ZPX), 0x64: ('NOP', ZP),
    0x74: ('NOP', ZPX), 0x80: ('NOP', IMM), 0x82: ('NOP', IMM),
    0x89: ('NOP', IMM), 0xC2: ('NOP', IMM), 0xD4: ('NOP', ZPX),
    0xE2: ('NOP', IMM), 0xF4: ('NOP', ZPX),
    0x0C: ('NOP', ABS), 0x1C: ('NOP', ABX), 0x3C: ('NOP', ABX),
    0x5C: ('NOP', ABX), 0x7C: ('NOP', ABX), 0xDC: ('NOP', ABX),
    0xFC: ('NOP', ABX),
    # Single-byte NOP variants
    0x1A: ('NOP', IMP), 0x3A: ('NOP', IMP), 0x5A: ('NOP', IMP),
    0x7A: ('NOP', IMP), 0xDA: ('NOP', IMP), 0xFA: ('NOP', IMP),
    # JAM/KIL (halt CPU) - treat as 1 byte
    0x02: ('JAM', IMP), 0x12: ('JAM', IMP), 0x22: ('JAM', IMP),
    0x32: ('JAM', IMP), 0x42: ('JAM', IMP), 0x52: ('JAM', IMP),
    0x62: ('JAM', IMP), 0x72: ('JAM', IMP), 0x92: ('JAM', IMP),
    0xB2: ('JAM', IMP), 0xD2: ('JAM', IMP), 0xF2: ('JAM', IMP),
}


# =============================================================================
# SID FILE HEADER PARSER
# =============================================================================

class SIDHeader:
    """Parsed SID file header"""
    def __init__(self):
        self.magic = ''
        self.version = 0
        self.data_offset = 0
        self.load_address = 0
        self.init_address = 0
        self.play_address = 0
        self.songs = 0
        self.start_song = 0
        self.speed = 0
        self.name = ''
        self.author = ''
        self.released = ''
        self.flags = 0
        self.start_page = 0
        self.page_length = 0
        self.second_sid_address = 0
        self.third_sid_address = 0

    def __str__(self):
        lines = [
            f"  Magic:       {self.magic}",
            f"  Version:     {self.version}",
            f"  Data Offset: ${self.data_offset:04X}",
            f"  Load Addr:   ${self.load_address:04X} {'(from data)' if self.load_address == 0 else ''}",
            f"  Init Addr:   ${self.init_address:04X}",
            f"  Play Addr:   ${self.play_address:04X}",
            f"  Songs:       {self.songs}",
            f"  Start Song:  {self.start_song}",
            f"  Speed:       ${self.speed:08X} ({'VBI' if self.speed == 0 else 'CIA'})",
            f"  Name:        {self.name}",
            f"  Author:      {self.author}",
            f"  Released:    {self.released}",
        ]
        if self.version >= 2:
            clock_bits = (self.flags >> 2) & 0x03
            clock_str = ['Unknown', 'PAL', 'NTSC', 'PAL+NTSC'][clock_bits]
            sid_bits = (self.flags >> 4) & 0x03
            sid_str = ['Unknown', 'MOS6581', 'MOS8580', '6581+8580'][sid_bits]
            lines.extend([
                f"  Flags:       ${self.flags:04X} (b{self.flags:016b})",
                f"    Clock:     {clock_str}",
                f"    SID Model: {sid_str}",
                f"  Start Page:  ${self.start_page:02X}",
                f"  Page Length: ${self.page_length:02X}",
                f"  2nd SID:     ${self.second_sid_address:02X}",
                f"  3rd SID:     ${self.third_sid_address:02X}",
            ])
        return '\n'.join(lines)


def parse_sid_header(filepath):
    """Parse a SID file header and return a SIDHeader object"""
    with open(filepath, 'rb') as f:
        data = f.read()

    h = SIDHeader()
    h.magic = data[0:4].decode('ascii', errors='replace')
    if h.magic not in ('PSID', 'RSID'):
        raise ValueError(f"Not a valid SID file: magic='{h.magic}'")

    h.version = struct.unpack('>H', data[4:6])[0]
    h.data_offset = struct.unpack('>H', data[6:8])[0]
    h.load_address = struct.unpack('>H', data[8:10])[0]
    h.init_address = struct.unpack('>H', data[10:12])[0]
    h.play_address = struct.unpack('>H', data[12:14])[0]
    h.songs = struct.unpack('>H', data[14:16])[0]
    h.start_song = struct.unpack('>H', data[16:18])[0]
    h.speed = struct.unpack('>I', data[18:22])[0]
    h.name = data[0x16:0x36].split(b'\x00')[0].decode('latin-1', errors='replace').strip()
    h.author = data[0x36:0x56].split(b'\x00')[0].decode('latin-1', errors='replace').strip()
    h.released = data[0x56:0x76].split(b'\x00')[0].decode('latin-1', errors='replace').strip()

    if h.version >= 2 and len(data) >= 0x7C:
        h.flags = struct.unpack('>H', data[0x76:0x78])[0]
        h.start_page = data[0x78]
        h.page_length = data[0x79]
        h.second_sid_address = data[0x7A]
        h.third_sid_address = data[0x7B]

    return h


def extract_binary(filepath, header):
    """Extract the C64 binary data from a SID file.
    Returns (load_address, binary_data)."""
    with open(filepath, 'rb') as f:
        data = f.read()

    raw = data[header.data_offset:]

    if header.load_address == 0:
        load_addr = struct.unpack('<H', raw[0:2])[0]
        binary = raw[2:]
    else:
        load_addr = header.load_address
        binary = raw

    return load_addr, binary


# =============================================================================
# RECURSIVE DESCENT CODE FINDER
# =============================================================================

def find_code_regions(binary_data, base_addr, entry_points):
    """Find code regions via recursive descent from known entry points.

    Uses a work queue to follow all reachable code paths including
    JMP targets, JSR targets, and branch targets.

    Returns:
        code_offsets: set of byte offsets (relative to binary start) that
                      are confirmed to be part of instructions
        inst_starts:  set of byte offsets that are instruction start bytes
    """
    data_len = len(binary_data)
    code_offsets = set()      # All byte offsets that are part of code
    inst_starts = set()       # Just the first byte of each instruction
    work_queue = []

    # Seed with entry points (convert addresses to offsets)
    for addr in entry_points:
        offset = addr - base_addr
        if 0 <= offset < data_len:
            work_queue.append(offset)

    processed_starts = set()  # Track which starting offsets we've already processed

    while work_queue:
        start_offset = work_queue.pop()

        if start_offset in processed_starts:
            continue
        if start_offset < 0 or start_offset >= data_len:
            continue

        processed_starts.add(start_offset)
        offset = start_offset

        # Follow linear code flow from this point
        while offset < data_len:
            if offset in inst_starts:
                # Already processed this instruction - we've merged with known code
                break

            opcode = binary_data[offset]
            if opcode not in OPCODES:
                # Unknown opcode - not code, stop following this path
                break

            mnemonic, mode = OPCODES[opcode]
            size = MODE_SIZE[mode]

            if offset + size > data_len:
                break  # Instruction extends past end of data

            # Mark all bytes of this instruction as code
            for j in range(size):
                code_offsets.add(offset + j)
            inst_starts.add(offset)

            # Get absolute address if applicable
            abs_addr = None
            if mode in ABS_MODES and size == 3:
                abs_addr = binary_data[offset + 1] | (binary_data[offset + 2] << 8)

            # Handle control flow
            if mode == REL:
                # Relative branch - add branch target, continue fall-through
                branch_byte = binary_data[offset + 1]
                if branch_byte > 127:
                    branch_byte -= 256
                target_offset = offset + 2 + branch_byte
                if 0 <= target_offset < data_len:
                    work_queue.append(target_offset)
                offset += size  # Continue with fall-through path

            elif mnemonic == 'JMP' and mode == ABS:
                # Unconditional jump - add target, stop linear flow
                if abs_addr is not None:
                    target_offset = abs_addr - base_addr
                    if 0 <= target_offset < data_len:
                        work_queue.append(target_offset)
                break

            elif mnemonic == 'JMP' and mode == IND:
                # Indirect jump - can't follow statically, stop
                break

            elif mnemonic == 'JSR' and mode == ABS:
                # Subroutine call - add target, continue with return
                if abs_addr is not None:
                    target_offset = abs_addr - base_addr
                    if 0 <= target_offset < data_len:
                        work_queue.append(target_offset)
                offset += size

            elif mnemonic in ('RTS', 'RTI'):
                # Return - stop following this path
                break

            elif mnemonic == 'BRK':
                # Break - could be intentional or data; stop
                break

            elif mnemonic == 'JAM':
                # CPU halt - stop
                break

            else:
                # Normal instruction - continue linear flow
                offset += size

    return code_offsets, inst_starts


# =============================================================================
# BINARY RELOCATOR AND SID ADDRESS PATCHER
# =============================================================================

def relocate_and_patch(binary_data, base_addr, new_base, sid_offset,
                       data_end_addr=None, entry_points=None):
    """Create a relocated and SID-patched version of the binary.

    Uses recursive descent to accurately identify code regions, then:
    - Only applies instruction-level relocation within confirmed code
    - Patches SID register addresses in confirmed code
    - Precisely identifies pointer tables in data regions via code analysis

    Args:
        binary_data:   Original binary bytes
        base_addr:     Original load address (e.g., $1000)
        new_base:      New load address (e.g., $3000)
        sid_offset:    SID address offset (e.g., $20 for $D420)
        data_end_addr: End address of the data range
        entry_points:  List of code entry point addresses

    Returns:
        (patched_data, patch_report, stats)
    """
    reloc_delta = new_base - base_addr
    if data_end_addr is None:
        data_end_addr = base_addr + len(binary_data)
    if entry_points is None:
        entry_points = [base_addr]

    patched = bytearray(binary_data)
    report = []
    stats = {
        'code_bytes': 0,
        'data_bytes': 0,
        'reloc_count': 0,
        'sid_patch_count': 0,
        'data_hib_patches': 0,
        'sid_refs': defaultdict(int),
    }

    # Step 1: Find code regions via recursive descent
    code_offsets, inst_starts = find_code_regions(binary_data, base_addr, entry_points)
    stats['code_bytes'] = len(code_offsets)
    stats['data_bytes'] = len(binary_data) - len(code_offsets)

    # Step 2: Iterate through confirmed instructions and apply patches
    for offset in sorted(inst_starts):
        opcode = binary_data[offset]
        if opcode not in OPCODES:
            continue

        mnemonic, mode = OPCODES[opcode]
        size = MODE_SIZE[mode]

        if mode not in ABS_MODES or size != 3:
            continue

        if offset + 2 >= len(binary_data):
            continue

        addr = binary_data[offset + 1] | (binary_data[offset + 2] << 8)
        new_addr = addr

        # --- SID Register Patching ($D400-$D41F) ---
        if 0xD400 <= addr <= 0xD41F:
            if sid_offset != 0:
                new_addr = addr + sid_offset
                patched[offset + 1] = new_addr & 0xFF
                patched[offset + 2] = (new_addr >> 8) & 0xFF
                stats['sid_patch_count'] += 1
                stats['sid_refs'][f"${addr:04X}"] += 1
                report.append(
                    f"  SID PATCH @ ${base_addr+offset:04X}: "
                    f"{mnemonic} ${addr:04X} -> ${new_addr:04X}"
                )

        # --- Code Relocation (addresses within tune range) ---
        elif base_addr <= addr < data_end_addr:
            if reloc_delta != 0:
                new_addr = addr + reloc_delta
                patched[offset + 1] = new_addr & 0xFF
                patched[offset + 2] = (new_addr >> 8) & 0xFF
                stats['reloc_count'] += 1
                report.append(
                    f"  RELOC    @ ${base_addr+offset:04X}: "
                    f"{mnemonic} ${addr:04X} -> ${new_addr:04X}"
                )

    # Step 3: Precise data pointer relocation
    # Uses code flow analysis (from the SID-WIZARD player architecture) to
    # identify exactly which data tables need relocation patching.
    #
    # SID-WIZARD's native relocator (relodata in exporter.asm) patches:
    #   1. Split hi-byte tables (PPTRHI, INSPTHI) - every byte is a hi-byte
    #   2. Interleaved pointer tables (BIGFXTABLE, SUBTUNES) - every other
    #      byte is a hi-byte of a 16-bit LE address pair
    #
    # Detection strategy:
    #   Phase 1: Find ABX/ABY table accesses in code and trace destinations
    #   Phase 2: Confirm split hi-byte tables (stored to odd ZP address)
    #   Phase 3: Detect interleaved tables (adjacent base pairs, b and b+1)
    #   Phase 4: Determine table sizes
    #   Phase 5: Patch split hi-byte tables (all entries)
    #   Phase 6: Patch interleaved tables (only hi-byte of each pair)
    #   Phase 7: Fallback heuristic for any remaining tables
    #
    if reloc_delta != 0:
        orig_hi_start = (base_addr >> 8) & 0xFF
        orig_hi_end = ((data_end_addr - 1) >> 8) & 0xFF
        hi_delta = (reloc_delta >> 8) & 0xFF
        data_ptr_patches = 0

        # --- Phase 1: Find all ABX/ABY table accesses and trace destinations ---
        table_accesses = {}  # tbl_addr -> list of (code_offset, dest_zp)

        for offset in sorted(inst_starts):
            opcode = binary_data[offset]
            if opcode not in OPCODES:
                continue
            mnemonic, mode = OPCODES[opcode]
            size = MODE_SIZE[mode]
            if mode not in (ABX, ABY) or size != 3:
                continue
            if mnemonic not in ('LDA', 'LDX', 'LDY'):
                continue
            if offset + 2 >= len(binary_data):
                continue
            tbl_addr = binary_data[offset + 1] | (binary_data[offset + 2] << 8)
            tbl_off = tbl_addr - base_addr
            if not (0 <= tbl_off < len(binary_data) and tbl_off not in code_offsets):
                continue

            # Look forward through up to 3 instructions for a STA to ZP
            dest_zp = None
            scan = offset + size
            for _step in range(3):
                if scan not in inst_starts or scan >= len(binary_data):
                    break
                scan_op = binary_data[scan]
                if scan_op not in OPCODES:
                    break
                scan_mnem, scan_mode = OPCODES[scan_op]
                scan_size = MODE_SIZE[scan_mode]
                if scan_mnem == 'STA' and scan_mode == ZP and scan + 1 < len(binary_data):
                    dest_zp = binary_data[scan + 1]
                    break
                if scan_mnem in ('STA', 'STX', 'STY', 'JSR', 'JMP', 'RTS', 'RTI', 'BRK'):
                    break
                scan += scan_size

            if tbl_addr not in table_accesses:
                table_accesses[tbl_addr] = []
            table_accesses[tbl_addr].append((offset, dest_zp))

        # --- Phase 2: Identify confirmed split hi-byte tables ---
        # A table whose values are stored to an ODD zero-page address is
        # feeding the high byte of a pointer pair ($FE/$FF, $FC/$FD, etc.)
        confirmed_hi_tables = set()
        for tbl_addr, accesses in table_accesses.items():
            for _code_off, dest_zp in accesses:
                if dest_zp is not None and dest_zp % 2 == 1:
                    confirmed_hi_tables.add(tbl_addr)
                    break

        # Identify lo-byte tables (stored to even ZP)
        confirmed_lo_tables = set()
        for tbl_addr, accesses in table_accesses.items():
            for _code_off, dest_zp in accesses:
                if dest_zp is not None and dest_zp % 2 == 0:
                    confirmed_lo_tables.add(tbl_addr)
                    break

        # --- Phase 3: Detect interleaved pointer tables ---
        # In SID-WIZARD, interleaved tables (like BIGFXTABLE, SUBTUNES)
        # are accessed by two ABX/ABY instructions whose base addresses
        # differ by exactly 1 byte:  LDA table,Y  and  LDA table+1,Y
        # The lower base reads lo-bytes, the higher reads hi-bytes.
        all_tbl_bases = sorted(table_accesses.keys())
        interleaved_pairs = []  # list of (lo_base, hi_base)
        interleaved_bases = set()

        for b in all_tbl_bases:
            if b + 1 in table_accesses and b not in interleaved_bases:
                interleaved_pairs.append((b, b + 1))
                interleaved_bases.add(b)
                interleaved_bases.add(b + 1)

        # --- Phase 4: Determine table sizes ---
        sorted_tables = sorted(table_accesses.keys())
        table_sizes = {}

        for i, tbl_addr in enumerate(sorted_tables):
            if i + 1 < len(sorted_tables):
                gap = sorted_tables[i + 1] - tbl_addr
                table_sizes[tbl_addr] = min(gap, 64)
            else:
                remaining = (base_addr + len(binary_data)) - tbl_addr
                table_sizes[tbl_addr] = min(remaining, 64)

        # Override sizes for confirmed split hi-byte tables using paired lo table
        for hi_addr in confirmed_hi_tables:
            best_lo = None
            for lo_addr in confirmed_lo_tables:
                if lo_addr < hi_addr:
                    if best_lo is None or lo_addr > best_lo:
                        best_lo = lo_addr
            if best_lo is not None:
                paired_size = hi_addr - best_lo
                if 1 <= paired_size <= 64:
                    table_sizes[hi_addr] = paired_size

        # For interleaved tables, compute span from lo_base to next
        # non-partner table base (skip the adjacent hi_base)
        for lo_base, hi_base in interleaved_pairs:
            next_base = None
            for b in all_tbl_bases:
                if b > hi_base:
                    next_base = b
                    break
            if next_base is not None:
                span = min(next_base - lo_base, 128)
            else:
                span = min((base_addr + len(binary_data)) - lo_base, 128)
            table_sizes[lo_base] = span

        # --- Phase 5: Patch confirmed split hi-byte tables ---
        for tbl_addr in sorted(confirmed_hi_tables):
            tbl_off = tbl_addr - base_addr
            tbl_size = table_sizes.get(tbl_addr, 64)

            for k in range(tbl_size):
                pos = tbl_off + k
                if pos >= len(binary_data) or pos in code_offsets:
                    break
                b = binary_data[pos]
                if orig_hi_start <= b <= orig_hi_end:
                    old_val = patched[pos]
                    new_val = (old_val + hi_delta) & 0xFF
                    if old_val != new_val and old_val == b:
                        patched[pos] = new_val
                        data_ptr_patches += 1
                        report.append(
                            f"  HI-TBL*  @ ${base_addr+pos:04X}: "
                            f"${old_val:02X} -> ${new_val:02X} "
                            f"(confirmed hi-byte table at ${tbl_addr:04X})"
                        )

        # --- Phase 6: Patch interleaved pointer tables ---
        # Scan each interleaved region for 16-bit LE address pairs.
        # Only patch the hi-byte of each valid pair.
        # Require at least 2 valid pairs to confirm it's a real pointer
        # table (not coincidental ASCII or padding data).
        MIN_ILV_PAIRS = 2

        for lo_base, hi_base in interleaved_pairs:
            lo_off = lo_base - base_addr
            span = table_sizes.get(lo_base, 64)

            # First pass: collect valid pairs
            valid_pairs = []
            k = 0
            while k + 1 < span:
                pos_lo = lo_off + k
                pos_hi = lo_off + k + 1
                if pos_hi >= len(binary_data):
                    break
                if pos_lo in code_offsets or pos_hi in code_offsets:
                    break
                lo_byte = binary_data[pos_lo]
                hi_byte = binary_data[pos_hi]
                addr16 = lo_byte | (hi_byte << 8)

                if base_addr <= addr16 < data_end_addr:
                    valid_pairs.append((k, pos_lo, pos_hi, lo_byte, hi_byte))
                k += 2

            if len(valid_pairs) < MIN_ILV_PAIRS:
                continue

            # Second pass: patch hi-bytes of valid pairs
            for _k, pos_lo, pos_hi, lo_byte, hi_byte in valid_pairs:
                if orig_hi_start <= hi_byte <= orig_hi_end:
                    old_val = patched[pos_hi]
                    new_val = (old_val + hi_delta) & 0xFF
                    if old_val != new_val and old_val == hi_byte:
                        patched[pos_hi] = new_val
                        data_ptr_patches += 1
                        report.append(
                            f"  ILV-TBL  @ ${base_addr+pos_lo:04X}: "
                            f"${lo_byte:02X}{old_val:02X} -> "
                            f"${lo_byte:02X}{new_val:02X} "
                            f"(interleaved ptr table at "
                            f"${lo_base:04X}/${hi_base:04X})"
                        )

        # --- Phase 7: Fallback heuristic for remaining tables ---
        # For tables not handled above, apply conservative heuristic:
        # - At least 30% of entries in the hi-byte page range
        # - At least 3 such entries
        # - At least 2 DISTINCT hi-byte values (rejects constant padding)
        # - NOT a sorted/monotonic sequence (rejects parameter tables)
        handled_tables = confirmed_hi_tables | interleaved_bases
        for tbl_addr in sorted(table_accesses.keys()):
            if tbl_addr in handled_tables:
                continue
            tbl_off = tbl_addr - base_addr
            tbl_size = table_sizes.get(tbl_addr, 64)

            tbl_bytes = []
            for k in range(tbl_size):
                pos = tbl_off + k
                if pos >= len(binary_data) or pos in code_offsets:
                    break
                tbl_bytes.append(binary_data[pos])

            if len(tbl_bytes) < 3:
                continue

            in_range = [b for b in tbl_bytes if orig_hi_start <= b <= orig_hi_end]
            hi_count = len(in_range)
            ratio = hi_count / len(tbl_bytes) if tbl_bytes else 0

            if ratio <= 0.30 or hi_count < 3:
                continue

            # Reject if all in-range values are the same (padding/constant)
            if len(set(in_range)) < 2:
                continue

            # Reject if in-range values are sorted (parameter/lookup table)
            if in_range == sorted(in_range) or in_range == sorted(in_range, reverse=True):
                continue

            for k, b in enumerate(tbl_bytes):
                pos = tbl_off + k
                if orig_hi_start <= b <= orig_hi_end:
                    old_val = patched[pos]
                    new_val = (old_val + hi_delta) & 0xFF
                    if old_val != new_val and old_val == b:
                        patched[pos] = new_val
                        data_ptr_patches += 1
                        report.append(
                            f"  HI-TBL   @ ${base_addr+pos:04X}: "
                            f"${old_val:02X} -> ${new_val:02X} "
                            f"(heuristic hi-byte table at ${tbl_addr:04X})"
                        )

        stats['data_hib_patches'] = data_ptr_patches

    return bytes(patched), report, stats


# =============================================================================
# ANALYSIS REPORTING
# =============================================================================

def analyze_sid_binary(binary_data, base_addr, entry_points):
    """Perform detailed analysis and return a report string."""
    data_end = base_addr + len(binary_data)
    code_offsets, inst_starts = find_code_regions(binary_data, base_addr, entry_points)

    # Categorize instructions
    sid_refs = defaultdict(int)
    internal_refs = 0
    io_refs = 0
    code_instructions = 0

    for offset in sorted(inst_starts):
        opcode = binary_data[offset]
        if opcode not in OPCODES:
            continue
        mnemonic, mode = OPCODES[opcode]
        code_instructions += 1

        if mode in ABS_MODES and MODE_SIZE[mode] == 3 and offset + 2 < len(binary_data):
            addr = binary_data[offset + 1] | (binary_data[offset + 2] << 8)
            if 0xD400 <= addr <= 0xD41F:
                sid_refs[addr] += 1
            elif base_addr <= addr < data_end:
                internal_refs += 1
            elif 0xD000 <= addr <= 0xDFFF:
                io_refs += 1

    # Find code region boundaries
    if code_offsets:
        code_start = min(code_offsets)
        code_end = max(code_offsets)
    else:
        code_start = 0
        code_end = 0

    lines = [
        f"\n  Recursive Descent Analysis:",
        f"    Code bytes found:      {len(code_offsets)} ({len(code_offsets)*100//len(binary_data)}% of binary)",
        f"    Data bytes found:      {len(binary_data) - len(code_offsets)} ({(len(binary_data)-len(code_offsets))*100//len(binary_data)}% of binary)",
        f"    Code region:           ${base_addr + code_start:04X}-${base_addr + code_end:04X}",
        f"    Instructions in code:  {code_instructions}",
        f"    Internal addr refs:    {internal_refs}",
        f"    I/O register refs:     {io_refs}",
        f"",
        f"  SID Register References ({sum(sid_refs.values())} total):",
    ]
    for addr in sorted(sid_refs.keys()):
        reg_offset = addr - 0xD400
        reg_names = {
            0: 'Freq Lo (V1)', 1: 'Freq Hi (V1)', 2: 'PW Lo (V1)', 3: 'PW Hi (V1)',
            4: 'Ctrl (V1)', 5: 'AD (V1)', 6: 'SR (V1)',
            7: 'Freq Lo (V2)', 8: 'Freq Hi (V2)', 9: 'PW Lo (V2)', 10: 'PW Hi (V2)',
            11: 'Ctrl (V2)', 12: 'AD (V2)', 13: 'SR (V2)',
            14: 'Freq Lo (V3)', 15: 'Freq Hi (V3)', 16: 'PW Lo (V3)', 17: 'PW Hi (V3)',
            18: 'Ctrl (V3)', 19: 'AD (V3)', 20: 'SR (V3)',
            21: 'FC Lo', 22: 'FC Hi', 23: 'Res/Filt', 24: 'Mode/Vol',
            25: 'Pot X', 26: 'Pot Y', 27: 'OSC3 Random', 28: 'ENV3',
        }
        name = reg_names.get(reg_offset, f'Reg {reg_offset}')
        lines.append(f"    ${addr:04X} ({name}): {sid_refs[addr]}x")

    return '\n'.join(lines)


# =============================================================================
# OUTPUT GENERATORS
# =============================================================================

def write_patched_binary(patched_data, output_path):
    """Write the patched binary data to a file"""
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'wb') as f:
        f.write(patched_data)


def generate_kickasm_config(tune_configs, output_path):
    """Generate a KickAssembler include file with tune configuration."""
    lines = [
        "// ============================================================",
        "// Auto-generated by sid_processor.py",
        "// EVO64 Super Quattro - Quad SID Player Configuration",
        "// DO NOT EDIT - Regenerate with: python3 tools/sid_processor.py",
        "// ============================================================",
        "",
        "// SID chip base addresses (EVO64 Super Quattro addressing)",
        ".const SID1_BASE = $D400    // Primary SID",
        ".const SID2_BASE = $D420    // Second SID",
        ".const SID3_BASE = $D440    // Third SID",
        ".const SID4_BASE = $D460    // Fourth SID",
        "",
        "// PAL timing constants",
        ".const PAL_RASTER_LINES = 312   // Total raster lines in PAL",
        ".const RASTER_SPACING   = PAL_RASTER_LINES / 4",
        "",
        "// Raster IRQ trigger lines (evenly spaced across the frame)",
        ".const RASTER_IRQ1 = $00",
        ".const RASTER_IRQ2 = RASTER_SPACING",
        ".const RASTER_IRQ3 = RASTER_SPACING * 2",
        ".const RASTER_IRQ4 = RASTER_SPACING * 3",
        "",
    ]

    for i, tc in enumerate(tune_configs, 1):
        lines.extend([
            f"// Tune {i}: {tc['label']}",
            f".const TUNE{i}_BASE = ${tc['base']:04X}",
            f".const TUNE{i}_INIT = ${tc['init']:04X}",
            f".const TUNE{i}_PLAY = ${tc['play']:04X}",
            f".const TUNE{i}_SIZE = {tc['size']}",
            f".const TUNE{i}_SID  = ${tc['sid_base']:04X}",
            "",
        ])

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'w') as f:
        f.write('\n'.join(lines))


# =============================================================================
# MAIN PROCESSING PIPELINE
# =============================================================================

TUNE_CONFIG = [
    {
        'sid_file': 'sids/quadcore/Quad_Core_tune_1.sid',
        'label': 'Quad Core (tune 1)',
        'new_base': 0x1000,     # Keep at original location
        'sid_offset': 0x00,     # SID 1 at $D400 (no change)
        'output_bin': 'build/tune1.bin',
    },
    {
        'sid_file': 'sids/quadcore/Quad_Core_tune_2.sid',
        'label': 'Quad Core (tune 2)',
        'new_base': 0x3000,     # Relocate to $3000
        'sid_offset': 0x20,     # SID 2 at $D420
        'output_bin': 'build/tune2.bin',
    },
    {
        'sid_file': 'sids/quadcore/Quad_Core_tune_3.sid',
        'label': 'Quad Core (tune 3)',
        'new_base': 0x5000,     # Relocate to $5000
        'sid_offset': 0x40,     # SID 3 at $D440
        'output_bin': 'build/tune3.bin',
    },
    {
        'sid_file': 'sids/quadcore/Quad_Core_tune_4.sid',
        'label': 'Quad Core (tune 4)',
        'new_base': 0x7000,     # Relocate to $7000
        'sid_offset': 0x60,     # SID 4 at $D460
        'output_bin': 'build/tune4.bin',
    },
]


def process_all(project_root, analyze_only=False):
    """Process all 4 SID files for the Quad-SID Player"""
    print("=" * 70)
    print("  EVO64 Super Quattro - Quad SID Processor")
    print("=" * 70)

    tune_configs_for_asm = []

    for i, tc in enumerate(TUNE_CONFIG):
        sid_path = os.path.join(project_root, tc['sid_file'])
        print(f"\n{'─' * 70}")
        print(f"  Tune {i+1}: {tc['label']}")
        print(f"  Source: {tc['sid_file']}")
        print(f"{'─' * 70}")

        # Parse header
        header = parse_sid_header(sid_path)
        print(f"\n  SID Header:")
        print(str(header))

        # Extract binary
        load_addr, binary = extract_binary(sid_path, header)
        data_end = load_addr + len(binary)
        print(f"\n  Binary Data:")
        print(f"    Load address: ${load_addr:04X}")
        print(f"    Data size:    {len(binary)} bytes (${len(binary):04X})")
        print(f"    End address:  ${data_end - 1:04X}")

        # Determine entry points for recursive descent
        init_addr = header.init_address if header.init_address != 0 else load_addr
        play_addr = header.play_address
        entry_points = [init_addr, play_addr]

        # Also add targets of the jump table at load_addr
        # SID-WIZARD typically has 3-4 JMP instructions at the start
        for j in range(0, min(12, len(binary)), 3):
            if binary[j] == 0x4C and j + 2 < len(binary):  # JMP opcode
                target = binary[j + 1] | (binary[j + 2] << 8)
                if load_addr <= target < data_end:
                    entry_points.append(target)

        entry_points = list(set(entry_points))
        print(f"    Entry points: {', '.join(f'${a:04X}' for a in sorted(entry_points))}")

        # Analysis
        analysis = analyze_sid_binary(binary, load_addr, entry_points)
        print(analysis)

        if analyze_only:
            continue

        # Calculate relocated addresses
        reloc_delta = tc['new_base'] - load_addr
        new_init = init_addr + reloc_delta
        new_play = play_addr + reloc_delta

        print(f"\n  Relocation Plan:")
        print(f"    Original: ${load_addr:04X}-${data_end-1:04X}")
        print(f"    New base: ${tc['new_base']:04X} (delta +${reloc_delta:04X})")
        print(f"    Init: ${init_addr:04X} -> ${new_init:04X}")
        print(f"    Play: ${play_addr:04X} -> ${new_play:04X}")
        print(f"    SID:  $D400 -> ${0xD400 + tc['sid_offset']:04X} (offset +${tc['sid_offset']:02X})")

        # Relocate and patch
        patched, report, stats = relocate_and_patch(
            binary, load_addr, tc['new_base'], tc['sid_offset'],
            data_end, entry_points
        )

        print(f"\n  Patch Results:")
        print(f"    Code bytes analyzed:    {stats['code_bytes']}")
        print(f"    Data bytes (untouched): {stats['data_bytes']}")
        print(f"    Code relocations:       {stats['reloc_count']}")
        print(f"    SID register patches:   {stats['sid_patch_count']}")
        print(f"    Data hi-byte patches:   {stats['data_hib_patches']}")

        # Show SID register patch details
        if stats['sid_refs']:
            print(f"\n  SID Register Patches:")
            for reg, count in sorted(stats['sid_refs'].items()):
                print(f"    {reg} -> ${int(reg[1:], 16) + tc['sid_offset']:04X}: {count}x")

        # Write output
        output_path = os.path.join(project_root, tc['output_bin'])
        write_patched_binary(patched, output_path)
        print(f"\n  Output: {tc['output_bin']} ({len(patched)} bytes)")

        # Store config for assembly generation
        tune_configs_for_asm.append({
            'label': tc['label'],
            'base': tc['new_base'],
            'init': new_init,
            'play': new_play,
            'size': len(patched),
            'sid_base': 0xD400 + tc['sid_offset'],
        })

    if not analyze_only and tune_configs_for_asm:
        config_path = os.path.join(project_root, 'build', 'tune_config.inc')
        generate_kickasm_config(tune_configs_for_asm, config_path)

        print(f"\n{'=' * 70}")
        print(f"  PROCESSING COMPLETE")
        print(f"{'=' * 70}")
        print(f"\n  Generated Files:")
        for tc in TUNE_CONFIG:
            print(f"    {tc['output_bin']}")
        print(f"    build/tune_config.inc")

        print(f"\n  Memory Map:")
        print(f"    $0801-$0900  Main program (BASIC SYS + IRQ harness)")
        for i, tc in enumerate(tune_configs_for_asm, 1):
            end = tc['base'] + tc['size'] - 1
            print(f"    ${tc['base']:04X}-${end:04X}  Tune {i} "
                  f"(init=${tc['init']:04X} play=${tc['play']:04X} "
                  f"SID=${tc['sid_base']:04X})")

        print(f"\n  VICE Launch Command:")
        print(f"    x64sc -sidextra 3 \\")
        print(f"      -sid2address 0xD420 \\")
        print(f"      -sid3address 0xD440 \\")
        print(f"      -sid4address 0xD460 \\")
        print(f"      build/QuadSID_Player.prg")
        print()


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)

    analyze_only = '--analyze-only' in sys.argv

    os.makedirs(os.path.join(project_root, 'build'), exist_ok=True)
    process_all(project_root, analyze_only=analyze_only)


if __name__ == '__main__':
    main()
