// ============================================================
//
//   EVO64 SUPER QUATTRO - 4SID EXAMPLE-TUNE
//   =========================================
//
//   A native 4-SID music player for the EVO64 Super Quattro.
//
//   This program plays "4SID Example-Tune" by HERMIT
//   (Mihály Horváth), the creator of SID-WIZARD.
//   Composed natively for 4 SID chips using SID-WIZARD 1.9
//   with 4-SID export (PSID v4E format).
//
//     SID 1 @ $D400 (Left)   |  SID 2 @ $D420 (Right)
//     SID 3 @ $D440 (Left)   |  SID 4 @ $D460 (Right)
//
//   Music:  HERMIT, 2022
//   Player: SID-WIZARD 1.9 (4-SID export)
//   System: EVO64 Super Quattro / Player Harness, 2026
//
// ============================================================

// BASIC SYS startup line (generates "10 SYS xxxx" at $0801)
BasicUpstart2(start)

// ============================================================
//  CONSTANTS
// ============================================================

// Tune entry points (embedded in the binary at $1000)
.const TUNE_INIT     = $1000    // Init routine (A = song number)
.const TUNE_PLAY     = $1003    // Play routine (call once per frame)

// SID chip base addresses
.const SID1_BASE     = $D400
.const SID2_BASE     = $D420
.const SID3_BASE     = $D440
.const SID4_BASE     = $D460

// VIC-II registers
.const VIC_CTRL1     = $D011    // Control register 1 (raster bit 8)
.const VIC_RASTER    = $D012    // Raster line register
.const VIC_IRQ_EN    = $D01A    // IRQ enable (bit 0 = raster)
.const VIC_IRQ_FLAG  = $D019    // IRQ flag (write $FF to ack)
.const VIC_BORDER    = $D020    // Border color
.const VIC_BGCOLOR   = $D021    // Background color

// CIA registers
.const CIA1_ICR      = $DC0D    // CIA 1 interrupt control
.const CIA2_ICR      = $DD0D    // CIA 2 interrupt control

// Processor port
.const PROC_PORT     = $01

// IRQ vectors (Kernal banked out -> use hardware vectors)
.const IRQ_LO        = $FFFE
.const IRQ_HI        = $FFFF

// Screen RAM
.const SCREEN        = $0400
.const COLOR_RAM     = $D800

// Raster line for the single play interrupt
// Trigger near the top of the visible area
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
//  MAIN PROGRAM
// ============================================================

            * = $0810 "Main Program"

start:
            sei                         // Disable interrupts during setup

            // -- Set up display --
            lda #BLACK
            sta VIC_BORDER
            sta VIC_BGCOLOR

            // -- Clear all 4 SID chips --
            ldx #$18
            lda #$00
!clear:     sta SID1_BASE,x
            sta SID2_BASE,x
            sta SID3_BASE,x
            sta SID4_BASE,x
            dex
            bpl !clear-

            // -- Initialize the tune --
            // SID-WIZARD init expects song number in A (0 = first song)
            lda #$00
            jsr TUNE_INIT

            // -- Configure IRQ system --
            // Bank out BASIC + Kernal ROMs, keep I/O visible
            lda #$35
            sta PROC_PORT

            // Set IRQ handler
            lda #<irq_play
            sta IRQ_LO
            lda #>irq_play
            sta IRQ_HI

            // Set VIC-II raster compare
            lda #$1B                    // Raster bit 8 = 0, screen on, 25 rows
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

idle:       jmp idle                    // Music plays via raster interrupt


// ============================================================
//  RASTER IRQ HANDLER
//  Single interrupt per frame: call the 4-SID play routine
// ============================================================

irq_play:
            pha
            txa
            pha
            tya
            pha

            lda #$FF                    // Acknowledge VIC-II IRQ
            sta VIC_IRQ_FLAG

            inc VIC_BORDER              // Debug: show CPU time
            jsr TUNE_PLAY               // Play all 4 SIDs in one call
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
            lda #$20                    // Space character
!clr:       sta SCREEN,x
            sta SCREEN+$100,x
            sta SCREEN+$200,x
            sta SCREEN+$2E8,x
            inx
            bne !clr-

            // Print title strings using generic print routine
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
            lda #<(SCREEN + 40*5 + 3)
            sta $FD
            lda #>(SCREEN + 40*5 + 3)
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

            // SID info + model/clock: light grey
            ldx #39
            lda #LGREY
!c4:        sta COLOR_RAM + 40*8,x
            sta COLOR_RAM + 40*9,x
            sta COLOR_RAM + 40*10,x
            sta COLOR_RAM + 40*11,x
            dex
            bpl !c4-

            // Music/player credits: cyan
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
//  Source: ($FB/$FC), Dest: ($FD/$FE)
//  Prints until $00 terminator
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
            //      "NATIVE 4-SID EXAMPLE TUNE"
            .byte $0E,$01,$14,$09,$16,$05,$20        // NATIVE_
            .byte $34,$2D                            // 4-
            .byte $13,$09,$04,$20                    // SID_
            .byte $05,$18,$01,$0D,$10,$0C,$05,$20    // EXAMPLE_
            .byte $14,$15,$0E,$05                    // TUNE
            .byte $00

title_line4:
            //      "SID 1: $D400 (L)  SID 2: $D420 (R)"
            .byte $13,$09,$04,$20,$31,$3A,$20,$24,$04,$34,$30,$30  // SID 1: $D400
            .byte $20,$28,$0C,$29,$20,$20                          // _(L)__
            .byte $13,$09,$04,$20,$32,$3A,$20,$24,$04,$34,$32,$30  // SID 2: $D420
            .byte $20,$28,$12,$29                                  // _(R)
            .byte $00

title_line5:
            //      "SID 3: $D440 (L)  SID 4: $D460 (R)"
            .byte $13,$09,$04,$20,$33,$3A,$20,$24,$04,$34,$34,$30  // SID 3: $D440
            .byte $20,$28,$0C,$29,$20,$20                          // _(L)__
            .byte $13,$09,$04,$20,$34,$3A,$20,$24,$04,$34,$36,$30  // SID 4: $D460
            .byte $20,$28,$12,$29                                  // _(R)
            .byte $00

title_line6:
            //      "SID MODEL: MOS 8580"
            .byte $13,$09,$04,$20,$0D,$0F,$04,$05,$0C,$3A,$20      // SID MODEL:_
            .byte $0D,$0F,$13,$20,$38,$35,$38,$30                  // MOS 8580
            .byte $00

title_line7:
            //      "CLOCK: PAL 50HZ (STEREO)"
            .byte $03,$0C,$0F,$03,$0B,$3A,$20                      // CLOCK:_
            .byte $10,$01,$0C,$20                                   // PAL_
            .byte $35,$30,$08,$1A,$20                               // 50HZ_
            .byte $28,$13,$14,$05,$12,$05,$0F,$29                   // (STEREO)
            .byte $00

title_line8:
            //      "MUSIC: HERMIT (2022)"
            .byte $0D,$15,$13,$09,$03,$3A,$20                      // MUSIC:_
            .byte $08,$05,$12,$0D,$09,$14,$20                      // HERMIT_
            .byte $28,$32,$30,$32,$32,$29                           // (2022)
            .byte $00

title_line9:
            //      "PLAYER: SID-WIZARD 1.9 (4SID)"
            .byte $10,$0C,$01,$19,$05,$12,$3A,$20                  // PLAYER:_
            .byte $13,$09,$04,$2D                                  // SID-
            .byte $17,$09,$1A,$01,$12,$04,$20                      // WIZARD_
            .byte $31,$2E,$39,$20                                  // 1.9_
            .byte $28,$34,$13,$09,$04,$29                           // (4SID)
            .byte $00

title_line10:
            //      "EVO64 SUPER QUATTRO 2026"
            .byte $05,$16,$0F,$36,$34,$20                          // EVO64_
            .byte $13,$15,$10,$05,$12,$20                           // SUPER_
            .byte $11,$15,$01,$14,$14,$12,$0F,$20                   // QUATTRO_
            .byte $32,$30,$32,$36                                   // 2026
            .byte $00


// ============================================================
//  TUNE DATA (native 4-SID binary from SID-WIZARD 1.9)
// ============================================================

            * = $1000 "4SID Example-Tune - HERMIT"
            .import binary "../build/hermit4sid.bin"


// ============================================================
//  ASSEMBLER INFO OUTPUT
// ============================================================
.print ""
.print "============================================"
.print "  EVO64 Super Quattro - 4SID Example-Tune"
.print "============================================"
.print ""
.print "  Tune: 4SID Example-Tune by HERMIT"
.print "  Format: PSID v4E (native 4-SID)"
.print "  Init: $1000  Play: $1003"
.print "  SID 1: $D400 (L)  SID 2: $D420 (R)"
.print "  SID 3: $D440 (L)  SID 4: $D460 (R)"
.print ""
