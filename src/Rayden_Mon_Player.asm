// ============================================================
//
//   EVO64 SUPER QUATTRO - A-D MON 4SID
//   ====================================
//
//   A native 4-SID music player for the EVO64 Super Quattro.
//
//   This program plays "A-D Mon" by Rayden (Patrick Zeh),
//   composed natively for 4 SID chips using the DMC music
//   editor with 4-SID export (RSID v4E format).
//
//   The binary contains 4 independent player instances,
//   each pre-configured for its own SID chip:
//
//     Tune 1: $0900 (init) / $0903 (play)  ->  SID @ $D400
//     Tune 2: $1500 (init) / $1503 (play)  ->  SID @ $D420
//     Tune 3: $2200 (init) / $2203 (play)  ->  SID @ $D440
//     Tune 4: $3200 (init) / $3203 (play)  ->  SID @ $D460
//
//   NOTE: The tune binary loads at $08B0, which overlaps the
//   usual harness location ($0810). The harness code is placed
//   after the tune binary at $3D30.
//
//   Music:  Patrick Zeh (Rayden) / Alpha Flight, 1998
//   System: EVO64 Super Quattro / Player Harness, 2026
//
// ============================================================

// BASIC SYS startup line (auto-targets the start label at $3D30)
BasicUpstart2(start)

// ============================================================
//  CONSTANTS
// ============================================================

// Sub-tune entry points
.const TUNE1_INIT    = $0900
.const TUNE1_PLAY    = $0903
.const TUNE2_INIT    = $1500
.const TUNE2_PLAY    = $1503
.const TUNE3_INIT    = $2200
.const TUNE3_PLAY    = $2203
.const TUNE4_INIT    = $3200
.const TUNE4_PLAY    = $3203

// SID chip base addresses
.const SID1_BASE     = $D400
.const SID2_BASE     = $D420
.const SID3_BASE     = $D440
.const SID4_BASE     = $D460

// VIC-II registers
.const VIC_CTRL1     = $D011
.const VIC_RASTER    = $D012
.const VIC_IRQ_EN    = $D01A
.const VIC_IRQ_FLAG  = $D019
.const VIC_BORDER    = $D020
.const VIC_BGCOLOR   = $D021

// CIA registers
.const CIA1_ICR      = $DC0D
.const CIA2_ICR      = $DD0D

// Processor port
.const PROC_PORT     = $01

// IRQ vectors (Kernal banked out -> use hardware vectors)
.const IRQ_LO        = $FFFE
.const IRQ_HI        = $FFFF

// Screen RAM
.const SCREEN        = $0400
.const COLOR_RAM     = $D800

// Raster line for the play interrupt
.const RASTER_PLAY   = 0

// C64 color codes
.const BLACK  = 0
.const WHITE  = 1
.const RED    = 2
.const CYAN   = 3
.const PURPLE = 4
.const GREEN  = 5
.const BLUE   = 6
.const YELLOW = 7
.const ORANGE = 8
.const BROWN  = 9
.const LRED   = 10
.const DGREY  = 11
.const GREY   = 12
.const LGREEN = 13
.const LBLUE  = 14
.const LGREY  = 15


// ============================================================
//  TUNE DATA (native 4-SID binary)
//  Loaded first since it occupies the lower address range.
//  The wrapper at $08B0-$08FF is included but never called.
// ============================================================

            * = $08B0 "A-D Mon 4SID"
            .import binary "../build/rayden_mon.bin"


// ============================================================
//  MAIN PROGRAM (placed after tune data)
// ============================================================

            * = $3D30 "Main Program"

start:
            sei

            // -- Set up display --
            lda #BLACK
            sta VIC_BORDER
            sta VIC_BGCOLOR

            // -- Bank out BASIC + Kernal ROMs, keep I/O --
            lda #$35
            sta PROC_PORT

            // -- Clear all 4 SID chips --
            ldx #$18
            lda #$00
!clear:     sta SID1_BASE,x
            sta SID2_BASE,x
            sta SID3_BASE,x
            sta SID4_BASE,x
            dex
            bpl !clear-

            // -- Initialize all 4 sub-tunes --
            lda #$00
            jsr TUNE1_INIT
            lda #$00
            jsr TUNE2_INIT
            lda #$00
            jsr TUNE3_INIT
            lda #$00
            jsr TUNE4_INIT

            // -- Configure IRQ system --

            // Set IRQ handler
            lda #<irq_play
            sta IRQ_LO
            lda #>irq_play
            sta IRQ_HI

            // Set VIC-II raster compare
            lda #$1B
            sta VIC_CTRL1
            lda #RASTER_PLAY
            sta VIC_RASTER

            // Enable raster IRQ in VIC-II
            lda #$81
            sta VIC_IRQ_EN

            // Disable all CIA IRQs
            lda #$7F
            sta CIA1_ICR
            sta CIA2_ICR

            // Acknowledge any pending IRQs
            lda CIA1_ICR
            lda CIA2_ICR
            lda #$FF
            sta VIC_IRQ_FLAG

            // -- Print title to screen --
            jsr print_title

            // -- Enable interrupts and idle --
            cli

idle:       jmp idle


// ============================================================
//  RASTER IRQ HANDLER
//  Single interrupt per frame: call all 4 sub-tune play routines
// ============================================================

irq_play:
            pha
            txa
            pha
            tya
            pha

            lda #$FF
            sta VIC_IRQ_FLAG

            inc VIC_BORDER
            jsr TUNE1_PLAY
            jsr TUNE2_PLAY
            jsr TUNE3_PLAY
            jsr TUNE4_PLAY
            lda #BLACK
            sta VIC_BORDER

            pla
            tay
            pla
            tax
            pla
            rti


// ============================================================
//  TITLE SCREEN
// ============================================================

print_title:
            // Clear screen
            ldx #$00
            lda #$20
!clr:       sta SCREEN,x
            sta SCREEN+$100,x
            sta SCREEN+$200,x
            sta SCREEN+$2E8,x
            inx
            bne !clr-

            // Print title strings
            lda #<title_line1
            sta $FB
            lda #>title_line1
            sta $FC
            lda #<(SCREEN + 40*1 + 7)
            sta $FD
            lda #>(SCREEN + 40*1 + 7)
            sta $FE
            jsr print_str

            lda #<title_line2
            sta $FB
            lda #>title_line2
            sta $FC
            lda #<(SCREEN + 40*3 + 4)
            sta $FD
            lda #>(SCREEN + 40*3 + 4)
            sta $FE
            jsr print_str

            lda #<title_line3
            sta $FB
            lda #>title_line3
            sta $FC
            lda #<(SCREEN + 40*5 + 4)
            sta $FD
            lda #>(SCREEN + 40*5 + 4)
            sta $FE
            jsr print_str

            lda #<title_line4
            sta $FB
            lda #>title_line4
            sta $FC
            lda #<(SCREEN + 40*8 + 2)
            sta $FD
            lda #>(SCREEN + 40*8 + 2)
            sta $FE
            jsr print_str

            lda #<title_line5
            sta $FB
            lda #>title_line5
            sta $FC
            lda #<(SCREEN + 40*9 + 2)
            sta $FD
            lda #>(SCREEN + 40*9 + 2)
            sta $FE
            jsr print_str

            lda #<title_line6
            sta $FB
            lda #>title_line6
            sta $FC
            lda #<(SCREEN + 40*10 + 2)
            sta $FD
            lda #>(SCREEN + 40*10 + 2)
            sta $FE
            jsr print_str

            lda #<title_line7
            sta $FB
            lda #>title_line7
            sta $FC
            lda #<(SCREEN + 40*11 + 2)
            sta $FD
            lda #>(SCREEN + 40*11 + 2)
            sta $FE
            jsr print_str

            lda #<title_line8
            sta $FB
            lda #>title_line8
            sta $FC
            lda #<(SCREEN + 40*14 + 2)
            sta $FD
            lda #>(SCREEN + 40*14 + 2)
            sta $FE
            jsr print_str

            lda #<title_line9
            sta $FB
            lda #>title_line9
            sta $FC
            lda #<(SCREEN + 40*15 + 2)
            sta $FD
            lda #>(SCREEN + 40*15 + 2)
            sta $FE
            jsr print_str

            lda #<title_line10
            sta $FB
            lda #>title_line10
            sta $FC
            lda #<(SCREEN + 40*18 + 6)
            sta $FD
            lda #>(SCREEN + 40*18 + 6)
            sta $FE
            jsr print_str

            // -- Set text colors --

            // Title: white
            ldx #39
            lda #WHITE
!c1:        sta COLOR_RAM + 40*1,x
            dex
            bpl !c1-

            // Subtitle: cyan
            ldx #39
            lda #CYAN
!c2:        sta COLOR_RAM + 40*3,x
            dex
            bpl !c2-

            // Native 4SID line: light green
            ldx #39
            lda #LGREEN
!c3:        sta COLOR_RAM + 40*5,x
            dex
            bpl !c3-

            // SID info: light grey
            ldx #39
            lda #LGREY
!c4:        sta COLOR_RAM + 40*8,x
            sta COLOR_RAM + 40*9,x
            sta COLOR_RAM + 40*10,x
            sta COLOR_RAM + 40*11,x
            dex
            bpl !c4-

            // Music credits: cyan
            ldx #39
            lda #CYAN
!c5:        sta COLOR_RAM + 40*14,x
            sta COLOR_RAM + 40*15,x
            dex
            bpl !c5-

            // Footer: light green
            ldx #39
            lda #LGREEN
!c6:        sta COLOR_RAM + 40*18,x
            dex
            bpl !c6-

            rts


// ============================================================
//  PRINT STRING ROUTINE
// ============================================================

print_str:
            ldy #$00
!loop:      lda ($FB),y
            beq !done+
            sta ($FD),y
            iny
            bne !loop-
!done:      rts


// ============================================================
//  SCREEN TEXT DATA
//  C64 screen codes (not PETSCII)
// ============================================================

title_line1:
            //      "EVO64 SUPER QUATTRO"
            .byte $05,$16,$0F,$36,$34,$20           // EVO64_
            .byte $13,$15,$10,$05,$12,$20            // SUPER_
            .byte $11,$15,$01,$14,$14,$12,$0F        // QUATTRO
            .byte $00

title_line2:
            //      "QUAD SID PLAYER - 4X12 VOICES"
            .byte $11,$15,$01,$04,$20                // QUAD_
            .byte $13,$09,$04,$20                    // SID_
            .byte $10,$0C,$01,$19,$05,$12            // PLAYER
            .byte $20,$2D,$20                        // _-_
            .byte $34,$18,$31,$32,$20                // 4X12_
            .byte $16,$0F,$09,$03,$05,$13            // VOICES
            .byte $00

title_line3:
            //      "NATIVE 4-SID COMPOSITION"
            .byte $0E,$01,$14,$09,$16,$05,$20        // NATIVE_
            .byte $34,$2D                            // 4-
            .byte $13,$09,$04,$20                    // SID_
            .byte $03,$0F,$0D,$10,$0F,$13,$09,$14,$09,$0F,$0E  // COMPOSITION
            .byte $00

title_line4:
            //      "SID 1: $D400  SID 2: $D420"
            .byte $13,$09,$04,$20,$31,$3A,$20,$24,$04,$34,$30,$30  // SID 1: $D400
            .byte $20,$20                                          // __
            .byte $13,$09,$04,$20,$32,$3A,$20,$24,$04,$34,$32,$30  // SID 2: $D420
            .byte $00

title_line5:
            //      "SID 3: $D440  SID 4: $D460"
            .byte $13,$09,$04,$20,$33,$3A,$20,$24,$04,$34,$34,$30  // SID 3: $D440
            .byte $20,$20                                          // __
            .byte $13,$09,$04,$20,$34,$3A,$20,$24,$04,$34,$36,$30  // SID 4: $D460
            .byte $00

title_line6:
            //      "SID MODEL: MOS 6581"
            .byte $13,$09,$04,$20,$0D,$0F,$04,$05,$0C,$3A,$20      // SID MODEL:_
            .byte $0D,$0F,$13,$20,$36,$35,$38,$31                  // MOS 6581
            .byte $00

title_line7:
            //      "CLOCK: PAL 50HZ"
            .byte $03,$0C,$0F,$03,$0B,$3A,$20                      // CLOCK:_
            .byte $10,$01,$0C,$20                                   // PAL_
            .byte $35,$30,$08,$1A                                   // 50HZ
            .byte $00

title_line8:
            //      "MUSIC: RAYDEN / ALPHA FLIGHT 1998"
            .byte $0D,$15,$13,$09,$03,$3A,$20                      // MUSIC:_
            .byte $12,$01,$19,$04,$05,$0E                          // RAYDEN
            .byte $20,$2F,$20                                      // _/_
            .byte $01,$0C,$10,$08,$01,$20                          // ALPHA_
            .byte $06,$0C,$09,$07,$08,$14                          // FLIGHT
            .byte $20,$31,$39,$39,$38                               // _1998
            .byte $00

title_line9:
            //      "PLAYER: DMC 4SID (RSID V4E)"
            .byte $10,$0C,$01,$19,$05,$12,$3A,$20                  // PLAYER:_
            .byte $04,$0D,$03,$20                                  // DMC_
            .byte $34,$13,$09,$04,$20                              // 4SID_
            .byte $28,$12,$13,$09,$04,$20                          // (RSID_
            .byte $16,$34,$05,$29                                  // V4E)
            .byte $00

title_line10:
            //      "EVO64 SUPER QUATTRO 2026"
            .byte $05,$16,$0F,$36,$34,$20                          // EVO64_
            .byte $13,$15,$10,$05,$12,$20                           // SUPER_
            .byte $11,$15,$01,$14,$14,$12,$0F,$20                   // QUATTRO_
            .byte $32,$30,$32,$36                                   // 2026
            .byte $00


// ============================================================
//  ASSEMBLER INFO OUTPUT
// ============================================================
.print ""
.print "============================================"
.print "  EVO64 Super Quattro - A-D Mon 4SID"
.print "============================================"
.print ""
.print "  Tune: A-D Mon 4SID by Rayden"
.print "  Format: RSID v4E (native 4-SID, 4 sub-tunes)"
.print "  Sub-tune 1: $0900/$0903 -> SID $D400"
.print "  Sub-tune 2: $1500/$1503 -> SID $D420"
.print "  Sub-tune 3: $2200/$2203 -> SID $D440"
.print "  Sub-tune 4: $3200/$3203 -> SID $D460"
.print "  NOTE: Harness at $3D30 (after tune data)"
.print ""
