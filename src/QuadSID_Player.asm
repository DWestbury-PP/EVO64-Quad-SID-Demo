// ============================================================
//
//   EVO64 SUPER QUATTRO - QUAD SID PLAYER
//   ======================================
//
//   The first-ever fully playable 4-SID music track!
//
//   This program plays four independent SID tunes simultaneously,
//   each targeting a separate SID chip on the EVO64 Super Quattro:
//
//     SID 1 @ $D400  |  SID 2 @ $D420
//     SID 3 @ $D440  |  SID 4 @ $D460
//
//   Playback is driven by a raster interrupt chain that divides
//   the PAL frame (312 raster lines) into 4 equal segments,
//   triggering each tune's play routine in sequence.
//
//   Music:  László Vincze (Vincenzo) / Singular Crew, 2017
//   Player: SID-WIZARD 1.7
//   System: EVO64 Super Quattro / Quad SID Player Harness, 2026
//
// ============================================================

// Load auto-generated tune configuration
#import "../build/tune_config.inc"

// BASIC SYS startup line (generates "10 SYS xxxx" at $0801)
BasicUpstart2(start)

// ============================================================
//  CONSTANTS
// ============================================================

// VIC-II registers
.const VIC_CTRL1     = $D011    // Control register 1 (raster bit 8 in bit 7)
.const VIC_RASTER    = $D012    // Raster line register
.const VIC_IRQ_EN    = $D01A    // IRQ enable (bit 0 = raster)
.const VIC_IRQ_FLAG  = $D019    // IRQ flag (write $FF to ack)
.const VIC_BORDER    = $D020    // Border color
.const VIC_BGCOLOR   = $D021    // Background color

// CIA registers
.const CIA1_PORTA    = $DC00    // CIA 1 Port A (keyboard column select)
.const CIA1_PORTB    = $DC01    // CIA 1 Port B (keyboard row read)
.const CIA1_ICR      = $DC0D    // CIA 1 interrupt control
.const CIA2_ICR      = $DD0D    // CIA 2 interrupt control

// Processor port
.const PROC_PORT     = $01

// C64 Keyboard matrix positions for keys 1-4:
//   "1" = Column 0 (bit 0), Row 7 (bit 7)
//   "2" = Column 3 (bit 3), Row 7 (bit 7)
//   "3" = Column 0 (bit 0), Row 1 (bit 1)
//   "4" = Column 3 (bit 3), Row 1 (bit 1)
.const KEY_COL0      = $FE      // Select column 0 (keys 1, 3)
.const KEY_COL3      = $F7      // Select column 3 (keys 2, 4)
.const KEY_ROW7_MASK = %10000000   // Row 7 mask (keys 1, 2)
.const KEY_ROW1_MASK = %00000010   // Row 1 mask (keys 3, 4)


// IRQ vectors (Kernal banked out → use hardware vectors)
.const IRQ_LO        = $FFFE
.const IRQ_HI        = $FFFF

// Screen RAM (default location)
.const SCREEN        = $0400

// Status display position (row 20)
.const STATUS_ROW    = SCREEN + 40*20
.const COLOR_ROW     = $D800 + 40*20

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

// Debug border colors for timing visualization
// (shows CPU time spent in each tune's play routine)
.const DEBUG_COLOR1  = RED
.const DEBUG_COLOR2  = GREEN
.const DEBUG_COLOR3  = LBLUE
.const DEBUG_COLOR4  = YELLOW


// ============================================================
//  MAIN PROGRAM
// ============================================================

            * = $0810 "Main Program"

start:
            sei                         // Disable interrupts during setup

            // -- Set up display --
            lda #BLACK
            sta VIC_BORDER              // Black border
            sta VIC_BGCOLOR             // Black background

            // -- Clear all 4 SID chips --
            // Write $00 to all writable registers ($00-$18) on each SID
            ldx #$18
            lda #$00
!clear:     sta SID1_BASE,x
            sta SID2_BASE,x
            sta SID3_BASE,x
            sta SID4_BASE,x
            dex
            bpl !clear-

            // -- Initialize all 4 tunes --
            // SID-WIZARD init expects song number in A (0 = first song)
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
            // This allows us to use the hardware IRQ vector at $FFFE/$FFFF
            lda #$35
            sta PROC_PORT

            // Set first IRQ handler
            lda #<irq1
            sta IRQ_LO
            lda #>irq1
            sta IRQ_HI

            // Set VIC-II raster compare to first trigger line
            lda #$1B                    // Raster bit 8 = 0, screen on, 25 rows
            sta VIC_CTRL1
            lda #RASTER_IRQ1            // First raster line (line 0)
            sta VIC_RASTER

            // Enable raster IRQ in VIC-II
            lda #$81
            sta VIC_IRQ_EN

            // Disable all CIA IRQs (we only want VIC-II raster IRQs)
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
            jsr update_status           // Draw initial toggle status

            // -- Enable interrupts and enter main loop --
            cli

            // ========================================
            //  MAIN LOOP: Keyboard polling for toggles
            //  Keys 1-4 toggle SID channels on/off
            // ========================================
main_loop:
            // --- Scan column 0 (keys "1" and "3") ---
            lda #KEY_COL0
            sta CIA1_PORTA
            lda CIA1_PORTB

            // Check key "1" (row 7)
            tax                         // Save port B state
            and #KEY_ROW7_MASK
            bne !key1_up+               // Bit set = NOT pressed
            // Key 1 pressed - check debounce
            lda key1_prev
            bne !skip1+                 // Already held down, skip
            lda #$01
            sta key1_prev               // Mark as held
            lda tune1_active
            eor #$01                    // Toggle
            sta tune1_active
            beq !mute1+
            // Re-init tune 1 when enabling
            lda #$00
            jsr TUNE1_INIT
            jmp !skip1+
!mute1:     jsr silence_sid1
            jmp !skip1+
!key1_up:   lda #$00
            sta key1_prev               // Key released
!skip1:

            // Check key "3" (row 1)
            txa                         // Restore port B state
            and #KEY_ROW1_MASK
            bne !key3_up+
            lda key3_prev
            bne !skip3+
            lda #$01
            sta key3_prev
            lda tune3_active
            eor #$01
            sta tune3_active
            beq !mute3+
            lda #$00
            jsr TUNE3_INIT
            jmp !skip3+
!mute3:     jsr silence_sid3
            jmp !skip3+
!key3_up:   lda #$00
            sta key3_prev
!skip3:

            // --- Scan column 3 (keys "2" and "4") ---
            lda #KEY_COL3
            sta CIA1_PORTA
            lda CIA1_PORTB

            // Check key "2" (row 7)
            tax
            and #KEY_ROW7_MASK
            bne !key2_up+
            lda key2_prev
            bne !skip2+
            lda #$01
            sta key2_prev
            lda tune2_active
            eor #$01
            sta tune2_active
            beq !mute2+
            lda #$00
            jsr TUNE2_INIT
            jmp !skip2+
!mute2:     jsr silence_sid2
            jmp !skip2+
!key2_up:   lda #$00
            sta key2_prev
!skip2:

            // Check key "4" (row 1)
            txa
            and #KEY_ROW1_MASK
            bne !key4_up+
            lda key4_prev
            bne !skip4+
            lda #$01
            sta key4_prev
            lda tune4_active
            eor #$01
            sta tune4_active
            beq !mute4+
            lda #$00
            jsr TUNE4_INIT
            jmp !skip4+
!mute4:     jsr silence_sid4
            jmp !skip4+
!key4_up:   lda #$00
            sta key4_prev
!skip4:

            // Restore CIA1 port A (so joystick still works)
            lda #$FF
            sta CIA1_PORTA

            // Update on-screen status display
            jsr update_status

            // Small delay to reduce CPU spinning
            ldx #$00
!delay:     dex
            bne !delay-

            jmp main_loop


// ============================================================
//  RASTER IRQ HANDLERS
//  Each handler: ack IRQ → play tune → set next raster/handler
// ============================================================

// -----------------------------------------------------------
//  IRQ 1: Play Tune 1 (SID @ $D400)
//  Triggers at raster line RASTER_IRQ1
// -----------------------------------------------------------
irq1:
            pha                         // Save registers
            txa
            pha
            tya
            pha

            lda #$FF                    // Acknowledge VIC-II IRQ
            sta VIC_IRQ_FLAG

            lda tune1_active            // Check if tune 1 is enabled
            beq !skip_play1+
            inc VIC_BORDER              // Debug: show timing
            jsr TUNE1_PLAY              // Play tune 1
            lda #BLACK
            sta VIC_BORDER
!skip_play1:

            // Chain to next IRQ
            lda #RASTER_IRQ2
            sta VIC_RASTER
            lda #<irq2
            sta IRQ_LO
            lda #>irq2
            sta IRQ_HI

            pla                         // Restore registers
            tay
            pla
            tax
            pla
            rti

// -----------------------------------------------------------
//  IRQ 2: Play Tune 2 (SID @ $D420)
//  Triggers at raster line RASTER_IRQ2
// -----------------------------------------------------------
irq2:
            pha
            txa
            pha
            tya
            pha

            lda #$FF
            sta VIC_IRQ_FLAG

            lda tune2_active
            beq !skip_play2+
            inc VIC_BORDER
            jsr TUNE2_PLAY
            lda #BLACK
            sta VIC_BORDER
!skip_play2:

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
//  IRQ 3: Play Tune 3 (SID @ $D440)
//  Triggers at raster line RASTER_IRQ3
// -----------------------------------------------------------
irq3:
            pha
            txa
            pha
            tya
            pha

            lda #$FF
            sta VIC_IRQ_FLAG

            lda tune3_active
            beq !skip_play3+
            inc VIC_BORDER
            jsr TUNE3_PLAY
            lda #BLACK
            sta VIC_BORDER
!skip_play3:

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
//  IRQ 4: Play Tune 4 (SID @ $D460)
//  Triggers at raster line RASTER_IRQ4
// -----------------------------------------------------------
irq4:
            pha
            txa
            pha
            tya
            pha

            lda #$FF
            sta VIC_IRQ_FLAG

            lda tune4_active
            beq !skip_play4+
            inc VIC_BORDER
            jsr TUNE4_PLAY
            lda #BLACK
            sta VIC_BORDER
!skip_play4:

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
//  SID SILENCE ROUTINES
//  Clear all writable registers on the specified SID chip
// ============================================================

silence_sid1:
            ldx #$18
            lda #$00
!s1:        sta SID1_BASE,x
            dex
            bpl !s1-
            rts

silence_sid2:
            ldx #$18
            lda #$00
!s2:        sta SID2_BASE,x
            dex
            bpl !s2-
            rts

silence_sid3:
            ldx #$18
            lda #$00
!s3:        sta SID3_BASE,x
            dex
            bpl !s3-
            rts

silence_sid4:
            ldx #$18
            lda #$00
!s4:        sta SID4_BASE,x
            dex
            bpl !s4-
            rts


// ============================================================
//  TOGGLE STATE VARIABLES
// ============================================================

tune1_active:   .byte $01          // 1 = playing, 0 = muted
tune2_active:   .byte $01
tune3_active:   .byte $01
tune4_active:   .byte $01

key1_prev:      .byte $00          // Debounce: 1 = held, 0 = released
key2_prev:      .byte $00
key3_prev:      .byte $00
key4_prev:      .byte $00


// ============================================================
//  STATUS DISPLAY
//  Shows which SID channels are active on screen row 20
// ============================================================

update_status:
            // Print status text: "1:xx  2:xx  3:xx  4:xx"
            // Position: row 20, col 4

            // --- SID 1 ---
            lda #$31                        // "1"
            sta STATUS_ROW + 4
            lda #$3A                        // ":"
            sta STATUS_ROW + 5
            lda tune1_active
            beq !off1+
            lda #$0F                        // "O"
            sta STATUS_ROW + 6
            lda #$0E                        // "N"
            sta STATUS_ROW + 7
            lda #$20                        // " "
            sta STATUS_ROW + 8
            lda #LGREEN
            jmp !col1+
!off1:      lda #$0F                        // "O"
            sta STATUS_ROW + 6
            lda #$06                        // "F"
            sta STATUS_ROW + 7
            lda #$06                        // "F"
            sta STATUS_ROW + 8
            lda #RED
!col1:      sta COLOR_ROW + 4
            sta COLOR_ROW + 5
            sta COLOR_ROW + 6
            sta COLOR_ROW + 7
            sta COLOR_ROW + 8

            // --- SID 2 ---
            lda #$32                        // "2"
            sta STATUS_ROW + 12
            lda #$3A                        // ":"
            sta STATUS_ROW + 13
            lda tune2_active
            beq !off2+
            lda #$0F
            sta STATUS_ROW + 14
            lda #$0E
            sta STATUS_ROW + 15
            lda #$20
            sta STATUS_ROW + 16
            lda #LGREEN
            jmp !col2+
!off2:      lda #$0F
            sta STATUS_ROW + 14
            lda #$06
            sta STATUS_ROW + 15
            lda #$06
            sta STATUS_ROW + 16
            lda #RED
!col2:      sta COLOR_ROW + 12
            sta COLOR_ROW + 13
            sta COLOR_ROW + 14
            sta COLOR_ROW + 15
            sta COLOR_ROW + 16

            // --- SID 3 ---
            lda #$33                        // "3"
            sta STATUS_ROW + 20
            lda #$3A
            sta STATUS_ROW + 21
            lda tune3_active
            beq !off3+
            lda #$0F
            sta STATUS_ROW + 22
            lda #$0E
            sta STATUS_ROW + 23
            lda #$20
            sta STATUS_ROW + 24
            lda #LGREEN
            jmp !col3+
!off3:      lda #$0F
            sta STATUS_ROW + 22
            lda #$06
            sta STATUS_ROW + 23
            lda #$06
            sta STATUS_ROW + 24
            lda #RED
!col3:      sta COLOR_ROW + 20
            sta COLOR_ROW + 21
            sta COLOR_ROW + 22
            sta COLOR_ROW + 23
            sta COLOR_ROW + 24

            // --- SID 4 ---
            lda #$34                        // "4"
            sta STATUS_ROW + 28
            lda #$3A
            sta STATUS_ROW + 29
            lda tune4_active
            beq !off4+
            lda #$0F
            sta STATUS_ROW + 30
            lda #$0E
            sta STATUS_ROW + 31
            lda #$20
            sta STATUS_ROW + 32
            lda #LGREEN
            jmp !col4+
!off4:      lda #$0F
            sta STATUS_ROW + 30
            lda #$06
            sta STATUS_ROW + 31
            lda #$06
            sta STATUS_ROW + 32
            lda #RED
!col4:      sta COLOR_ROW + 28
            sta COLOR_ROW + 29
            sta COLOR_ROW + 30
            sta COLOR_ROW + 31
            sta COLOR_ROW + 32

            rts


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

            // Print title strings
            ldx #$00
!t1:        lda title_line1,x
            beq !done1+
            sta SCREEN + 40*2 + 5,x    // Row 2, col 5
            inx
            jmp !t1-
!done1:
            ldx #$00
!t2:        lda title_line2,x
            beq !done2+
            sta SCREEN + 40*4 + 3,x    // Row 4, col 3
            inx
            jmp !t2-
!done2:
            ldx #$00
!t3:        lda title_line3,x
            beq !done3+
            sta SCREEN + 40*7 + 2,x    // Row 7, col 2
            inx
            jmp !t3-
!done3:
            ldx #$00
!t4:        lda title_line4,x
            beq !done4+
            sta SCREEN + 40*8 + 2,x    // Row 8, col 2
            inx
            jmp !t4-
!done4:
            ldx #$00
!t5:        lda title_line5,x
            beq !done5+
            sta SCREEN + 40*9 + 2,x    // Row 9, col 2
            inx
            jmp !t5-
!done5:
            ldx #$00
!t6:        lda title_line6,x
            beq !done6+
            sta SCREEN + 40*10 + 2,x   // Row 10, col 2
            inx
            jmp !t6-
!done6:
            ldx #$00
!t7:        lda title_line7,x
            beq !done7+
            sta SCREEN + 40*13 + 2,x   // Row 13, col 2
            inx
            jmp !t7-
!done7:
            ldx #$00
!t8:        lda title_line8,x
            beq !done8+
            sta SCREEN + 40*14 + 2,x   // Row 14, col 2
            inx
            jmp !t8-
!done8:
            ldx #$00
!t9:        lda title_line9,x
            beq !done9+
            sta SCREEN + 40*17 + 6,x   // Row 17, col 6
            inx
            jmp !t9-
!done9:

            // Set text colors (write to color RAM at $D800)
            // Title line: white
            ldx #39
            lda #WHITE
!col1:      sta $D800 + 40*2,x
            dex
            bpl !col1-

            // Info lines: light grey
            ldx #39
            lda #LGREY
!col2:      sta $D800 + 40*4,x
            sta $D800 + 40*7,x
            sta $D800 + 40*8,x
            sta $D800 + 40*9,x
            sta $D800 + 40*10,x
            dex
            bpl !col2-

            // SID info: cyan
            ldx #39
            lda #CYAN
!col3:      sta $D800 + 40*13,x
            sta $D800 + 40*14,x
            dex
            bpl !col3-

            // Credits: light green
            ldx #39
            lda #LGREEN
!col4:      sta $D800 + 40*17,x
            dex
            bpl !col4-

            // Help line: row 22 - "KEYS 1-4: TOGGLE SID CHANNELS"
            ldx #$00
!th:        lda help_line,x
            beq !doneh+
            sta SCREEN + 40*22 + 5,x
            inx
            jmp !th-
!doneh:
            // Help text color: dark grey
            ldx #39
            lda #DGREY
!col5:      sta $D800 + 40*22,x
            dex
            bpl !col5-

            rts

// ============================================================
//  SCREEN TEXT DATA
//  Note: C64 screen codes (not PETSCII)
// ============================================================
// Helper: convert ASCII to screen codes
// A-Z = $01-$1A, space = $20, digits = $30-$39
// Special: / = $2F, ( = $28, ) = $29, - = $2D, : = $3A, . = $2E
// @ = $00, # = $23, $ = $24, ! = $21

title_line1:
            //      "EVO64 SUPER QUATTRO"
            .byte $05,$16,$0F,$36,$34,$20  // EVO64_
            .byte $13,$15,$10,$05,$12,$20  // SUPER_
            .byte $11,$15,$01,$14,$14,$12,$0F  // QUATTRO
            .byte $00

title_line2:
            //      "QUAD SID PLAYER - 4X12 VOICES"
            .byte $11,$15,$01,$04,$20      // QUAD_
            .byte $13,$09,$04,$20          // SID_
            .byte $10,$0C,$01,$19,$05,$12  // PLAYER
            .byte $20,$2D,$20             // _-_
            .byte $34,$18,$31,$32,$20     // 4X12_
            .byte $16,$0F,$09,$03,$05,$13 // VOICES
            .byte $00

title_line3:
            //      "SID 1: $D400  SID 2: $D420"
            .byte $13,$09,$04,$20,$31,$3A,$20,$24,$04,$34,$30,$30  // SID 1: $D400
            .byte $20,$20                                          // __
            .byte $13,$09,$04,$20,$32,$3A,$20,$24,$04,$34,$32,$30  // SID 2: $D420
            .byte $00

title_line4:
            //      "SID 3: $D440  SID 4: $D460"
            .byte $13,$09,$04,$20,$33,$3A,$20,$24,$04,$34,$34,$30  // SID 3: $D440
            .byte $20,$20                                          // __
            .byte $13,$09,$04,$20,$34,$3A,$20,$24,$04,$34,$36,$30  // SID 4: $D460
            .byte $00

title_line5:
            //      "SID MODEL: MOS 8580"
            .byte $13,$09,$04,$20,$0D,$0F,$04,$05,$0C,$3A,$20  // SID MODEL:_
            .byte $0D,$0F,$13,$20,$38,$35,$38,$30               // MOS 8580
            .byte $00

title_line6:
            //      "CLOCK: PAL 50HZ"
            .byte $03,$0C,$0F,$03,$0B,$3A,$20  // CLOCK:_
            .byte $10,$01,$0C,$20              // PAL_
            .byte $35,$30,$08,$1A             // 50HZ
            .byte $00

title_line7:
            //      "MUSIC: VINCENZO / SINGULAR CREW"
            .byte $0D,$15,$13,$09,$03,$3A,$20  // MUSIC:_
            .byte $16,$09,$0E,$03,$05,$0E,$1A,$0F  // VINCENZO
            .byte $20,$2F,$20                  // _/_
            .byte $13,$09,$0E,$07,$15,$0C,$01,$12  // SINGULAR
            .byte $00

title_line8:
            //      "PLAYER: SID-WIZARD 1.7"
            .byte $10,$0C,$01,$19,$05,$12,$3A,$20  // PLAYER:_
            .byte $13,$09,$04,$2D                  // SID-
            .byte $17,$09,$1A,$01,$12,$04,$20      // WIZARD_
            .byte $31,$2E,$37                      // 1.7
            .byte $00

title_line9:
            //      "EVO64 SUPER QUATTRO 2026"
            .byte $05,$16,$0F,$36,$34,$20          // EVO64_
            .byte $13,$15,$10,$05,$12,$20           // SUPER_
            .byte $11,$15,$01,$14,$14,$12,$0F,$20   // QUATTRO_
            .byte $32,$30,$32,$36                   // 2026
            .byte $00


help_line:
            //      "KEYS 1-4: TOGGLE SID CHANNELS"
            .byte $0B,$05,$19,$13,$20       // KEYS_
            .byte $31,$2D,$34,$3A,$20       // 1-4:_
            .byte $14,$0F,$07,$07,$0C,$05   // TOGGLE
            .byte $20                       // _
            .byte $13,$09,$04,$20           // SID_
            .byte $03,$08,$01,$0E,$0E,$05,$0C,$13   // CHANNELS
            .byte $00


// ============================================================
//  TUNE DATA (patched binaries, generated by sid_processor.py)
// ============================================================

// Tune 1: Original location, SID @ $D400
            * = TUNE1_BASE "Tune 1 - SID $D400"
            .import binary "../build/tune1.bin"

// Tune 2: Relocated to $3000, SID @ $D420
            * = TUNE2_BASE "Tune 2 - SID $D420"
            .import binary "../build/tune2.bin"

// Tune 3: Relocated to $5000, SID @ $D440
            * = TUNE3_BASE "Tune 3 - SID $D440"
            .import binary "../build/tune3.bin"

// Tune 4: Relocated to $7000, SID @ $D460
            * = TUNE4_BASE "Tune 4 - SID $D460"
            .import binary "../build/tune4.bin"


// ============================================================
//  ASSEMBLER INFO OUTPUT
// ============================================================
.print ""
.print "============================================"
.print "  EVO64 Super Quattro - Quad SID Player"
.print "============================================"
.print ""
.print "  Tune 1: $" + toHexString(TUNE1_BASE) + " init=$" + toHexString(TUNE1_INIT) + " play=$" + toHexString(TUNE1_PLAY) + " SID=$" + toHexString(TUNE1_SID)
.print "  Tune 2: $" + toHexString(TUNE2_BASE) + " init=$" + toHexString(TUNE2_INIT) + " play=$" + toHexString(TUNE2_PLAY) + " SID=$" + toHexString(TUNE2_SID)
.print "  Tune 3: $" + toHexString(TUNE3_BASE) + " init=$" + toHexString(TUNE3_INIT) + " play=$" + toHexString(TUNE3_PLAY) + " SID=$" + toHexString(TUNE3_SID)
.print "  Tune 4: $" + toHexString(TUNE4_BASE) + " init=$" + toHexString(TUNE4_INIT) + " play=$" + toHexString(TUNE4_PLAY) + " SID=$" + toHexString(TUNE4_SID)
.print ""
.print "  Raster IRQs: " + RASTER_IRQ1 + ", " + RASTER_IRQ2 + ", " + RASTER_IRQ3 + ", " + RASTER_IRQ4
.print ""
