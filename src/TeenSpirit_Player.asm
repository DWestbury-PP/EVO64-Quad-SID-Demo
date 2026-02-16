// ============================================================
//
//   EVO64 SUPER QUATTRO - TEEN SPIRIT QUAD SID PLAYER
//   ==================================================
//
//   Four-part cover of Nirvana's "Smells Like Teen Spirit"
//   arranged across 4 SID chips on the EVO64 Super Quattro:
//
//     SID 1 @ $D400 - Main Guitar
//     SID 2 @ $D420 - 2nd Guitar
//     SID 3 @ $D440 - Bass & Drums
//     SID 4 @ $D460 - Melody
//
//   Playback is driven by a raster interrupt chain that divides
//   the PAL frame (312 raster lines) into 4 equal segments,
//   triggering each tune's play routine in sequence.
//
//   Music:  John Ames / AmesSoft, 2003
//   System: EVO64 Super Quattro / Quad SID Player Harness, 2026
//
// ============================================================

// Load auto-generated tune configuration
#import "../build/teenspirit_config.inc"

// BASIC SYS startup line (generates "10 SYS xxxx" at $0801)
BasicUpstart2(start)

// ============================================================
//  CONSTANTS
// ============================================================

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

// Screen RAM (default location)
.const SCREEN        = $0400

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
            sei

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

            // -- Initialize all 4 tunes --
            // Init expects song number in A (0 = first song)
            lda #$00
            jsr TUNE1_INIT
            lda #$00
            jsr TUNE2_INIT
            lda #$00
            jsr TUNE3_INIT
            lda #$00
            jsr TUNE4_INIT

            // -- Configure IRQ system --
            // Bank out BASIC + Kernal ROMs, keep I/O visible
            lda #$35
            sta PROC_PORT

            // Set first IRQ handler
            lda #<irq1
            sta IRQ_LO
            lda #>irq1
            sta IRQ_HI

            // Set VIC-II raster compare to first trigger line
            lda #$1B
            sta VIC_CTRL1
            lda #RASTER_IRQ1
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
//  RASTER IRQ HANDLERS
//  Each handler: ack IRQ -> play tune -> set next raster/handler
// ============================================================

// -----------------------------------------------------------
//  IRQ 1: Play Tune 1 - Main Guitar (SID @ $D400)
// -----------------------------------------------------------
irq1:
            pha
            txa
            pha
            tya
            pha

            lda #$FF
            sta VIC_IRQ_FLAG

            inc VIC_BORDER
            jsr TUNE1_PLAY
            lda #BLACK
            sta VIC_BORDER

            // Chain to next IRQ
            lda #RASTER_IRQ2
            sta VIC_RASTER
            lda #<irq2
            sta IRQ_LO
            lda #>irq2
            sta IRQ_HI

            pla
            tay
            pla
            tax
            pla
            rti

// -----------------------------------------------------------
//  IRQ 2: Play Tune 2 - 2nd Guitar (SID @ $D420)
// -----------------------------------------------------------
irq2:
            pha
            txa
            pha
            tya
            pha

            lda #$FF
            sta VIC_IRQ_FLAG

            inc VIC_BORDER
            jsr TUNE2_PLAY
            lda #BLACK
            sta VIC_BORDER

            lda #RASTER_IRQ3
            sta VIC_RASTER
            lda #<irq3
            sta IRQ_LO
            lda #>irq3
            sta IRQ_HI

            pla
            tay
            pla
            tax
            pla
            rti

// -----------------------------------------------------------
//  IRQ 3: Play Tune 3 - Bass & Drums (SID @ $D440)
// -----------------------------------------------------------
irq3:
            pha
            txa
            pha
            tya
            pha

            lda #$FF
            sta VIC_IRQ_FLAG

            inc VIC_BORDER
            jsr TUNE3_PLAY
            lda #BLACK
            sta VIC_BORDER

            lda #RASTER_IRQ4
            sta VIC_RASTER
            lda #<irq4
            sta IRQ_LO
            lda #>irq4
            sta IRQ_HI

            pla
            tay
            pla
            tax
            pla
            rti

// -----------------------------------------------------------
//  IRQ 4: Play Tune 4 - Melody (SID @ $D460)
// -----------------------------------------------------------
irq4:
            pha
            txa
            pha
            tya
            pha

            lda #$FF
            sta VIC_IRQ_FLAG

            inc VIC_BORDER
            jsr TUNE4_PLAY
            lda #BLACK
            sta VIC_BORDER

            // Chain back to first IRQ (circular)
            lda #RASTER_IRQ1
            sta VIC_RASTER
            lda #<irq1
            sta IRQ_LO
            lda #>irq1
            sta IRQ_HI

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
            ldx #$00
!t1:        lda title_line1,x
            beq !done1+
            sta SCREEN + 40*2 + 5,x
            inx
            jmp !t1-
!done1:
            ldx #$00
!t2:        lda title_line2,x
            beq !done2+
            sta SCREEN + 40*4 + 3,x
            inx
            jmp !t2-
!done2:
            ldx #$00
!t3:        lda title_line3,x
            beq !done3+
            sta SCREEN + 40*7 + 2,x
            inx
            jmp !t3-
!done3:
            ldx #$00
!t4:        lda title_line4,x
            beq !done4+
            sta SCREEN + 40*8 + 2,x
            inx
            jmp !t4-
!done4:
            ldx #$00
!t5:        lda title_line5,x
            beq !done5+
            sta SCREEN + 40*10 + 2,x
            inx
            jmp !t5-
!done5:
            ldx #$00
!t6:        lda title_line6,x
            beq !done6+
            sta SCREEN + 40*11 + 2,x
            inx
            jmp !t6-
!done6:
            ldx #$00
!t7:        lda title_line7,x
            beq !done7+
            sta SCREEN + 40*12 + 2,x
            inx
            jmp !t7-
!done7:
            ldx #$00
!t8:        lda title_line8,x
            beq !done8+
            sta SCREEN + 40*13 + 2,x
            inx
            jmp !t8-
!done8:
            ldx #$00
!t9:        lda title_line9,x
            beq !done9+
            sta SCREEN + 40*15 + 2,x
            inx
            jmp !t9-
!done9:
            ldx #$00
!t10:       lda title_line10,x
            beq !done10+
            sta SCREEN + 40*16 + 2,x
            inx
            jmp !t10-
!done10:
            ldx #$00
!t11:       lda title_line11,x
            beq !done11+
            sta SCREEN + 40*19 + 6,x
            inx
            jmp !t11-
!done11:

            // Set text colors
            // Title line: white
            ldx #39
            lda #WHITE
!col1:      sta $D800 + 40*2,x
            dex
            bpl !col1-

            // Subtitle: light grey
            ldx #39
            lda #LGREY
!col2:      sta $D800 + 40*4,x
            dex
            bpl !col2-

            // SID mapping: cyan
            ldx #39
            lda #CYAN
!col3:      sta $D800 + 40*7,x
            sta $D800 + 40*8,x
            dex
            bpl !col3-

            // Info lines: light grey
            ldx #39
            lda #LGREY
!col4:      sta $D800 + 40*10,x
            sta $D800 + 40*11,x
            sta $D800 + 40*12,x
            sta $D800 + 40*13,x
            dex
            bpl !col4-

            // Credits: light green
            ldx #39
            lda #LGREEN
!col5:      sta $D800 + 40*15,x
            sta $D800 + 40*16,x
            dex
            bpl !col5-

            // Footer: dark grey
            ldx #39
            lda #DGREY
!col6:      sta $D800 + 40*19,x
            dex
            bpl !col6-

            rts

// ============================================================
//  SCREEN TEXT DATA
//  C64 screen codes (not PETSCII)
// ============================================================

title_line1:
            //      "EVO64 SUPER QUATTRO"
            .byte $05,$16,$0F,$36,$34,$20
            .byte $13,$15,$10,$05,$12,$20
            .byte $11,$15,$01,$14,$14,$12,$0F
            .byte $00

title_line2:
            //      "QUAD SID PLAYER - 4X12 VOICES"
            .byte $11,$15,$01,$04,$20
            .byte $13,$09,$04,$20
            .byte $10,$0C,$01,$19,$05,$12
            .byte $20,$2D,$20
            .byte $34,$18,$31,$32,$20
            .byte $16,$0F,$09,$03,$05,$13
            .byte $00

title_line3:
            //      "SID 1: $D400  MAIN GUITAR"
            .byte $13,$09,$04,$20,$31,$3A,$20,$24,$04,$34,$30,$30
            .byte $20,$20
            .byte $0D,$01,$09,$0E,$20,$07,$15,$09,$14,$01,$12
            .byte $00

title_line4:
            //      "SID 2: $D420  2ND GUITAR"
            .byte $13,$09,$04,$20,$32,$3A,$20,$24,$04,$34,$32,$30
            .byte $20,$20
            .byte $32,$0E,$04,$20,$07,$15,$09,$14,$01,$12
            .byte $00

title_line5:
            //      "SID 3: $D440  BASS & DRUMS"
            .byte $13,$09,$04,$20,$33,$3A,$20,$24,$04,$34,$34,$30
            .byte $20,$20
            .byte $02,$01,$13,$13,$20,$26,$20,$04,$12,$15,$0D,$13
            .byte $00

title_line6:
            //      "SID 4: $D460  MELODY"
            .byte $13,$09,$04,$20,$34,$3A,$20,$24,$04,$34,$36,$30
            .byte $20,$20
            .byte $0D,$05,$0C,$0F,$04,$19
            .byte $00

title_line7:
            //      "SID MODEL: MOS 6581"
            .byte $13,$09,$04,$20,$0D,$0F,$04,$05,$0C,$3A,$20
            .byte $0D,$0F,$13,$20,$36,$35,$38,$31
            .byte $00

title_line8:
            //      "CLOCK: NTSC 60HZ"
            .byte $03,$0C,$0F,$03,$0B,$3A,$20
            .byte $0E,$14,$13,$03,$20
            .byte $36,$30,$08,$1A
            .byte $00

title_line9:
            //      "MUSIC: JOHN AMES / AMESOFT 2003"
            .byte $0D,$15,$13,$09,$03,$3A,$20
            .byte $0A,$0F,$08,$0E,$20,$01,$0D,$05,$13
            .byte $20,$2F,$20
            .byte $01,$0D,$05,$13,$0F,$06,$14,$20
            .byte $32,$30,$30,$33
            .byte $00

title_line10:
            //      "SONG: SMELLS LIKE TEEN SPIRIT"
            .byte $13,$0F,$0E,$07,$3A,$20
            .byte $13,$0D,$05,$0C,$0C,$13,$20
            .byte $0C,$09,$0B,$05,$20
            .byte $14,$05,$05,$0E,$20
            .byte $13,$10,$09,$12,$09,$14
            .byte $00

title_line11:
            //      "EVO64 SUPER QUATTRO 2026"
            .byte $05,$16,$0F,$36,$34,$20
            .byte $13,$15,$10,$05,$12,$20
            .byte $11,$15,$01,$14,$14,$12,$0F,$20
            .byte $32,$30,$32,$36
            .byte $00


// ============================================================
//  TUNE DATA (patched binaries, generated by sid_processor.py)
// ============================================================

// Tune 1: Main Guitar, SID @ $D400
            * = TUNE1_BASE "Tune 1 - Main Guitar - SID $D400"
            .import binary "../build/ts_tune1.bin"

// Tune 2: 2nd Guitar, SID @ $D420
            * = TUNE2_BASE "Tune 2 - 2nd Guitar - SID $D420"
            .import binary "../build/ts_tune2.bin"

// Tune 3: Bass & Drums, SID @ $D440
            * = TUNE3_BASE "Tune 3 - Bass & Drums - SID $D440"
            .import binary "../build/ts_tune3.bin"

// Tune 4: Melody, SID @ $D460
            * = TUNE4_BASE "Tune 4 - Melody - SID $D460"
            .import binary "../build/ts_tune4.bin"


// ============================================================
//  ASSEMBLER INFO OUTPUT
// ============================================================
.print ""
.print "============================================"
.print "  EVO64 Super Quattro - Teen Spirit Player"
.print "============================================"
.print ""
.print "  Tune: Smells Like Teen Spirit"
.print "  By:   John Ames / AmesSoft (2003)"
.print "  Format: 4x PSID v2 (separate SID files)"
.print ""
.print "  Tune 1: $" + toHexString(TUNE1_BASE) + " init=$" + toHexString(TUNE1_INIT) + " play=$" + toHexString(TUNE1_PLAY) + " SID=$" + toHexString(TUNE1_SID)
.print "  Tune 2: $" + toHexString(TUNE2_BASE) + " init=$" + toHexString(TUNE2_INIT) + " play=$" + toHexString(TUNE2_PLAY) + " SID=$" + toHexString(TUNE2_SID)
.print "  Tune 3: $" + toHexString(TUNE3_BASE) + " init=$" + toHexString(TUNE3_INIT) + " play=$" + toHexString(TUNE3_PLAY) + " SID=$" + toHexString(TUNE3_SID)
.print "  Tune 4: $" + toHexString(TUNE4_BASE) + " init=$" + toHexString(TUNE4_INIT) + " play=$" + toHexString(TUNE4_PLAY) + " SID=$" + toHexString(TUNE4_SID)
.print ""
.print "  Raster IRQs: " + RASTER_IRQ1 + ", " + RASTER_IRQ2 + ", " + RASTER_IRQ3 + ", " + RASTER_IRQ4
.print ""
