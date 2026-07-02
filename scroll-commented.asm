; =====================================================================
;  R-TYPE-STYLE SHMUP  -  STAGE 2: SCROLL + PLAYER SHIP (IJKL) + BULLET (SPACE)
;  Target: Commodore 64 (PAL)   Assembler: ACME
;  Build:  acme -f cbm -o scroll.prg scroll.asm
;  Run:    x64sc scroll.prg    (auto-runs via BASIC stub, or SYS 2064)
; =====================================================================

VIC      = $d000                ; base address of VIC-II register block
RASTER   = $d012                ; VIC-II raster counter / IRQ compare register
SCROLY   = $d011                ; vertical scroll, screen height, bitmap/MCM mode
SCROLX   = $d016                ; horizontal scroll (bits0-2), 38/40-col (bit3), MCM (bit4)
VICMEM   = $d018                ; screen RAM base (top nibble) + charset base (bits1-3)
VICIRQ   = $d019                ; VIC IRQ status latch; write to acknowledge
IRQMASK  = $d01a                ; VIC IRQ enable mask (bit0 = raster IRQ enable)
BORDER   = $d020                ; border color register
BGCOL0   = $d021                ; background color 0 (main background in MCM)
BGCOL1   = $d022                ; background color 1 (multicolor bit-pair 10)
BGCOL2   = $d023                ; background color 2 (multicolor bit-pair 11)

CIA1_ICR = $dc0d                ; CIA 1 interrupt control register; bit7=set/clr, bit0=timer A
CIA2_ICR = $dd0d                ; CIA 2 interrupt control register; same layout as CIA1_ICR

IRQVEC   = $0314                ; KERNAL IRQ vector (lo byte); +1 = hi byte

MUX_LEAD = 16               ; raster lead before sprite Y: must be big enough to
                            ; program a full band (~7) of same-line sprites before
                            ; the raster reaches them. Each costs ~100+ cycles (a
                            ; couple of scanlines), so a band needs a dozen-plus
                            ; lines of lead. Measured: 3 of 7 same-line sprites
                            ; appeared at LEAD=3, all 7 at 16; the late ones were
                            ; missing their turn-on line, not short of hw slots.
SPRSPAN  = 37               ; min Y gap to safely reuse a hw sprite (21 tall + MUX_LEAD)

ENEMY_SPEED   = 2               ; pixels per frame enemies move left
SPAWN_INTERVAL = 45             ; frames between enemy wave spawns
EXPLODE_FRAMES = 8              ; how many frames an enemy explosion lasts
ENEMY_COLOR   = 2          ; red
EXPLODE_COLOR = 1          ; white
HITW          = 12         ; hit box half-width (pixels)
HITH          = 12         ; hit box half-height (pixels)
ENEMY_FIRE_INTERVAL = 30        ; frames between enemy bullet shots
EBULLET_SPEED = 3               ; enemy bullet horizontal speed (pixels/frame, leftward)
EBULLET_COLOR = 3          ; cyan

D016_HUD      = $18        ; MCM=1, 40-col, fine=0  (HUD rows)
D016_PLAY_BASE = $10       ; MCM=1, 38-col          (| fine_x for playfield)
SPLIT_LINE    = 65         ; raster line of the row1/row2 split (tunable)
HUD_COLOR     = 1          ; HUD band color (white)
DIGIT_BASE    = 16         ; screen codes for digit 0..9 (16-25)
SCORE_PER_KILL = $10       ; 10 points per kill (BCD)

BOSS_KILL_THRESHOLD = 5         ; kills required before boss appears
BOSS_HP       = 5               ; boss hit points (5 hits to destroy)
BOSS_COLOR    = 4          ; purple
BOSS_ENTER_SPEED = 2            ; pixels/frame boss moves onto screen during ENTER state
BOSS_FIRE_INTERVAL = 50         ; frames between boss bullet volleys
BOSS_DEATH_FRAMES = 30          ; frames the boss death animation runs
BOSS_FLASH_FRAMES = 4           ; frames per color flash during boss death
BS_INACTIVE = 0                 ; bossState: boss not yet spawned
BS_ENTER    = 1                 ; bossState: boss sliding onto screen from right
BS_FIGHT    = 2                 ; bossState: boss active, bobbing and firing
BS_DYING    = 3                 ; bossState: boss hit-kill animation playing

PLAYER_LIVES    = 3             ; starting lives
PEXPLODE_FRAMES = 24            ; frames for player explosion animation
INVULN_FRAMES   = 100           ; frames of invulnerability after respawn
PHITW           = 14            ; player hit box half-width (pixels)
PHITH           = 16            ; player hit box half-height (pixels)
PS_ALIVE        = 0             ; playerState: ship active, accepting input
PS_EXPLODE      = 1             ; playerState: playing death explosion
PS_INVULN       = 2             ; playerState: respawned, blinking, can't be hit

GS_TITLE = 0                    ; gameState: showing animated title screen
GS_PLAY  = 1                    ; gameState: in-game play
GS_OVER  = 2                    ; gameState: showing game-over / high-score screen
OVER_FRAMES = 250          ; ~5s GAME OVER + TOP SCORES screen (one byte; FIRE skips)

; --- charge beam ---
CHARGE_THRESHOLD  = 40         ; frames held before release fires the beam
CHARGE_MAX        = 90         ; cap for chargeTimer
BEAM_COLOR        = 1          ; white (distinct from yellow-7 normal shots)
SHIP_COLOR_NORMAL = 1          ; white hull (matches SP0COL init)
SHIP_COLOR_CHARGE = 3          ; cyan  (pulses with SHIP_COLOR_NORMAL while charging)
SHIP_COLOR_READY  = 7          ; yellow (steady, charge >= threshold)

LOGO_Y      = 96              ; base raster Y of the title logo band
SLIDE_SPEED = 4               ; px/frame a title letter glides right during slide-in
HS_COUNT    = 5               ; high-score table entries

; ---- two screen buffers (both inside VIC bank 0) -----------------------
BUF_A    = $0400                ; front screen buffer A (VIC default screen page)
BUF_B    = $3800            ; moved from $0c00: program code+tables grew past $0c00 and
                            ; clobbered the row-address tables that lived inside the old BUF_B
COLORRAM = $d800                ; color RAM (fixed at $D800, cannot be relocated by VIC)
CHARSET  = $2000                ; custom charset base address (within VIC bank 0)

; $D018 values: screen ptr in top nibble (units of $0400), charset $2000
D18_A    = %00011000        ; screen $0400, charset $2000
D18_B    = %11101000        ; screen $3800 (VM=14), charset $2000 (CB=4)

; ---- zero page ---------------------------------------------------------
zp_dst   = $f9              ; 16-bit dst pointer
zp_map   = $fb              ; map pointer (next right-edge column, 25 bytes)
zp_fsrc  = $f7              ; front-buffer row src (for building back buffer)
zp_bdst  = $f5              ; back-buffer row dst

fine_x   = $02              ; fine scroll 7..0
build_row= $03              ; next screen row to build this char-step (0..24)
front_is_a = $04            ; 1 = buffer A is front, 0 = buffer B is front
frame_ready = $06           ; nonzero = a frame elapsed; cleared by main loop

; --- music player zp (ported from musical_score.asm $f0-$f9, relocated
;     clear of front_is_a ($04), frame_ready ($06), and the game's
;     zp_bdst/zp_fsrc/zp_dst/zp_map pointer block at $f5-$fe) ---
mus_lead_ptr = $07           ; $07/$08
mus_lead_cd  = $09               ; frames left on the current lead note
mus_bass_ptr = $0a           ; $0a/$0b
mus_bass_cd  = $0c               ; frames left on the current bass note
mus_drum_ptr = $0d           ; $0d/$0e
mus_drum_cd  = $0f               ; frames left on the current drum step
mus_tmp      = $10               ; scratch: note/hit value just read from a stream

ROWS_PER_FRAME = 4          ; build 4 rows/frame -> 25 rows done in ~7 frames

; =====================================================================
;  BASIC stub: 10 SYS 2064
; =====================================================================
* = $0801                       ; BASIC program start address
        !byte $0c,$08,$0a,$00,$9e,$32,$30,$36,$34,$00,$00,$00 ; BASIC line: 10 SYS 2064 + end-of-program sentinel

* = $0810                       ; machine code entry point at $0810 (= decimal 2064, the SYS target)
start                           ; boot entry: reached via BASIC SYS or a direct cold-start
        sei                     ; disable maskable IRQs while setting up interrupt system
        lda #$7f                ; $7F: bit7=0 (clear mode), bits 0-4 select all CIA interrupt sources
        sta CIA1_ICR            ; write $7F to CIA1 ICR: clears all CIA1 interrupt enables (bit7=0 means clear)
        sta CIA2_ICR            ; write $7F to CIA2 ICR: clears all CIA2 interrupt enables (prevents NMI/IRQ from CIAs)
        lda CIA1_ICR            ; read CIA1 ICR to acknowledge and drain any pending CIA1 interrupt flags
        lda CIA2_ICR            ; read CIA2 ICR to acknowledge and drain any pending CIA2 interrupt flags

        jsr show_splash          ; 3-second ARE-TYPE bitmap, before any other init

        jsr build_charset       ; construct custom multicolor charset at $2000 (digits, letters, tile glyphs)
        jsr set_colors          ; set VIC background/border colors and color RAM for playfield
        jsr sid_init            ; initialize SID chip: silence all voices, set volume
        jsr music_init           ; stream ptrs + V1/V2 music voice setup

        ; --- initial state: A is front, fill A from first 40 map columns,
        ;     and copy A->B so both buffers start identical -------------
        lda #1                  ; value 1 = buffer A is front
        sta front_is_a          ; flag buffer A as the current front (visible) buffer

        jsr fill_front_from_map     ; initial starfield fill so scrolling is ready
        jsr copy_a_to_b             ; B starts identical to A (both buffers in sync before first flip)
        jsr enter_title             ; set up logo sprites, enter GS_TITLE

        lda #7                  ; fine scroll starts at 7 = rightmost pixel of the 8-px step; counts down to 0 then coarse-flips
        sta fine_x              ; store initial fine-scroll value in zero page
        lda #2                  ; start back-buffer builds at row 2 (rows 0-1 are HUD, never rebuilt by scroll)
        sta build_row           ; store starting row index for back-buffer construction

        ; --- VIC setup: multicolor, 38-col, show buffer A ---------------
        lda #D18_A              ; D18_A = %00011000: screen $0400 (VM=1), charset $2000 (CB=4)
        sta VICMEM              ; point VIC screen to $0400 (BUF_A) and charset to $2000

        lda #%00011000              ; MCM=1, 38col=0(set later), xscroll=0
        ora #7                      ; fine = 7
        sta SCROLX              ; SCROLX: MCM on, fine X-scroll = 7 (initial fine offset)
        ; switch to 38-column to hide seam (clear bit3)
        lda SCROLX              ; read back SCROLX to preserve existing bits
        and #%11110111          ; clear bit3 to select 38-column mode (hides left/right border seam during scroll)
        sta SCROLX              ; write back: MCM=1, 38-col, fine=7

        lda #%00011011          ; SCROLY value: screen on (bit4), 25 rows (bit3), ECM=0, bitmap=0, vert scroll=3
        sta SCROLY              ; SCROLY: screen on, 25 rows, bitmap=0, ECM=0, vert scroll=3
        and #$7f                ; clear bit7 of last value (raster MSB bit; ensures IRQ compare uses $D012 only, not bit8)
        sta SCROLY              ; write back with bit7 clear (raster MSB = 0, so scroll_irq fires at line < 256)

        lda #0                  ; value 0 = black
        sta BORDER              ; black border (space aesthetic: invisible border merges with background)
        sta BGCOL0              ; black background color 0 (space/starfield background in MCM)

        ; --- raster IRQ at line 250 ------------------------------------
        lda #<scroll_irq        ; low byte of scroll_irq handler address
        sta IRQVEC              ; install scroll_irq as the KERNAL IRQ handler (low byte at $0314)
        lda #>scroll_irq        ; high byte of scroll_irq handler address
        sta IRQVEC+1            ; install scroll_irq handler (high byte at $0315)
        lda #250                ; raster line 250 = bottom of visible area, safe for per-frame work
        sta RASTER              ; set VIC raster IRQ compare to line 250
        lda #%00000001          ; bit0 = raster IRQ enable; all other VIC IRQ sources disabled
        sta IRQMASK             ; enable raster IRQ in VIC ($D01A)
        lda VICIRQ              ; read $D019 VIC IRQ status latch
        sta VICIRQ              ; acknowledge any pending VIC IRQ by writing latch back to itself (clears flags)
        cli                     ; enable IRQs: raster IRQ chain now active

main_loop                       ; main loop: idles on frame_ready flag, then dispatches per game state
        lda frame_ready         ; poll frame flag set by scroll_irq each VBI
        beq main_loop               ; wait for next frame
        lda #0                  ; value 0 = consumed
        sta frame_ready             ; consume it
        lda gameState           ; 0=GS_TITLE, 1=GS_PLAY, 2=GS_OVER
        cmp #GS_PLAY            ; are we in gameplay?
        bne ml_not_play         ; no: branch to title/over dispatch
        jsr player_update       ; read input, move ship, handle fire/explosion/invuln states
        jsr spawn_enemies       ; tick spawn timer; release next wave entry when it fires
        jsr enemy_fire          ; tick enemy fire timer; launch enemy bullet when it fires
        jsr boss_update         ; run boss state machine: ENTER slide-in, FIGHT bob+fire, DYING flash
        jsr update_enemies      ; move active enemies left by ENEMY_SPEED; deactivate when off screen
        jsr update_enemy_bullets ; move enemy bullets left; deactivate when off screen
        jsr update_bullets      ; move player bullets right; deactivate when off screen
        jsr check_hits          ; test player bullets vs enemies/boss; score kills, trigger explosions
        jsr check_player_hit    ; test enemy bullets + enemy bodies vs player; trigger PS_EXPLODE if hit
        jsr sound_update        ; advance all active SID effects one frame (frequency sweep, envelope)
        jsr draw_hud            ; render score (BCD->digits) and lives count into HUD rows of both buffers
        jsr sort_sprites        ; sort virtual sprite array by Y for multiplexer
        jsr build_schedule      ; populate mux IRQ trigger table from sorted virtual sprites
        jmp main_loop           ; loop forever; frame pacing is IRQ-driven via frame_ready flag
ml_not_play                     ; gameState != GS_PLAY: check for TITLE or OVER
        lda gameState               ; re-load: prior cmp may have clobbered A
        cmp #GS_TITLE           ; is it the title screen?
        bne ml_over             ; no: must be GS_OVER
        jsr title_update        ; animate logo, handle FIRE-to-start input
        jsr sound_update        ; keep music running during title
        jmp main_loop           ; back to top of main loop
ml_over                         ; gameState == GS_OVER: show high-score table, wait for FIRE or timeout
        jsr over_update         ; tick the OVER countdown, draw scores, detect FIRE to return to title
        jsr sound_update        ; keep music running during game-over screen
        jmp main_loop           ; back to top of main loop

; start_game: per-run gameplay setup (called on TITLE->PLAY).
start_game                      ; per-run init called on TITLE->PLAY transition
        lda #0                  ; value 0
        sta score               ; clear BCD score byte 0 (ones/tens)
        sta score+1             ; clear BCD score byte 1 (hundreds/thousands)
        sta score+2             ; clear BCD score byte 2 (ten-thousands/hundred-thousands)
        sta bossState           ; boss state = BS_INACTIVE (0): no boss on screen
        sta killCount           ; reset kill counter that triggers boss spawn at BOSS_KILL_THRESHOLD
        sta chargeTimer          ; reset charge so a leftover charge can't fire on first release
        jsr rebuild_playfield    ; sei-guarded (see helper); boot uses raw calls
        jsr init_hud_bar         ; rows 0-1 only, absolute writes — no guard needed
        jsr init_sprites        ; sprite pointers (both buffers), hardware regs, and art data
        lda #PLAYER_LIVES       ; starting lives constant
        sta lives               ; set lives to default at game start
        lda #30                 ; 30-frame delay before first enemy spawn (gives player a moment to orient)
        sta spawnTimer          ; prime enemy spawn countdown
        lda #0                  ; value 0
        sta spawnIndex          ; start at wave entry 0 (first enemy type in spawn table)
        lda #ENEMY_FIRE_INTERVAL ; load enemy fire rate constant
        sta enemyFireTimer      ; prime enemy fire countdown
        lda #6                  ; virtual slot 6 = first enemy slot (after player bullets 0-5)
        sta enemyFireIndex      ; first enemy fire check starts at virtual slot 6
        lda #PS_ALIVE           ; playerState = 0 (alive, accepting input)
        sta playerState         ; mark player as alive at game start
        lda #60                 ; starting X low byte = 60 (left quarter of screen)
        sta player_x            ; set player X position low byte
        lda #0                  ; high bit = 0 (X < 256, no MSB bit needed)
        sta player_x_hi         ; clear 9th bit of player X
        lda #120                ; starting Y = 120 (vertically centred in play area)
        sta player_y            ; set player Y coordinate
        jsr write_player_sprite ; push starting position to VIC-II sprite 0 registers immediately
        rts                     ; return to caller (title_update after FIRE press)

; rebuild_playfield: sei-guarded map fill + A->B copy. copy_a_to_b shares
; zp_fsrc/zp_bdst with the scroll IRQ's build_back_slice — an IRQ mid-copy
; repoints the pointers and the resumed (zp),y writes walk past BUF_B's end
; into the title letter sprites at $3C00. NOT for use at boot: `start` runs
; under its own sei until init ends, and this cli would unmask IRQs early.
rebuild_playfield               ; sei-guarded map fill + A->B copy (safe during active IRQ chain)
        sei                     ; mask IRQs: prevents scroll_irq mid-copy from corrupting zp_fsrc/zp_bdst
        jsr fill_front_from_map ; fill front buffer from map, position zp_map at col 40
        jsr copy_a_to_b         ; copy front buffer to back so both start identical
        cli                     ; re-enable IRQs once both buffers are in sync
        rts                     ; return to caller

; =====================================================================
;  BOOT SPLASH: aretype.kla multicolor bitmap, shown ~3 s at power-on
;  Data lives in VIC bank 1 (colram $5800, screen $5c00, bitmap $6000)
;  so the packed bank-0 layout is untouched. Boot-only: runs under
;  start's sei with IRQs masked, so the wait polls $D012 raster wraps.
;  Exits with the screen blanked (border-only black); the rest of boot
;  rebuilds bank 0, then $D011/$D016/$D018 turn the display back on.
; =====================================================================
show_splash                     ; boot-only: called once from start, still under sei
        ; color RAM <- splash color table. Copies 4 x 256: the last 24
        ; source bytes are zero fill past the 1000-byte table and land
        ; in the unused color-RAM tail at $dbe8-$dbff.
        ldx #0                  ; X counts 0..255; four interleaved page copies per pass
ss_cram lda splash_colram,x     ; page 0 of the Koala color-RAM table (low nibbles used)
        sta $d800,x             ; color RAM page 0: cells 0-255
        lda splash_colram+$100,x ; page 1 of the table
        sta $d900,x             ; color RAM page 1: cells 256-511
        lda splash_colram+$200,x ; page 2 of the table
        sta $da00,x             ; color RAM page 2: cells 512-767
        lda splash_colram+$300,x ; page 3: only 232 real bytes, then zero fill (see above)
        sta $db00,x             ; color RAM page 3: cells 768-999 + unused tail
        inx                     ; next byte within each page
        bne ss_cram             ; wraps to 0 after 256 iterations -> all 4 pages copied

        lda splash_bg            ; Koala background byte (shared bit-pair 00 color)
        sta BGCOL0              ; $d021: bitmap background color
        lda #0                  ; black
        sta BORDER              ; $d020: black border frames the splash

        lda $dd00                ; CIA2 port A: bits 0-1 select the VIC's 16K bank (inverted)
        and #%11111100          ; clear the bank bits...
        ora #%00000010          ; ...and select %10 = bank 1 ($4000-$7fff)
        sta $dd00               ; VIC now fetches all video data from bank 1
        lda #$78                 ; screen $5c00 (7<<4) + bitmap second half -> $6000
        sta VICMEM              ; $d018: bitmap screen RAM / bitmap base within the bank
        lda #%00111011           ; bit5 BMM=1 bitmap mode, bit4 DEN=1 screen on, bit3 25 rows, yscroll=3
        sta SCROLY              ; $d011: turn the bitmap display on
        lda #%00011000           ; bit4 MCM=1 multicolor, bit3 40 columns, xscroll=0
        sta SCROLX              ; $d016: multicolor bitmap = Koala's 160x200 double-wide pixels

        ldx #150                 ; 150 PAL frames = 3.0 s (PAL = 50 frames/s)
ss_wait lda #251                 ; line 251 is unique per frame ($d012 re-values
ss_w1   cmp RASTER               ; for lines 256+ stop at 55)
        bne ss_w1               ; spin until the raster reaches line 251...
ss_w2   cmp RASTER              ; ...then spin until it moves off the line,
        beq ss_w2               ; so one pass of the loop = exactly one frame
        dex                     ; count down the 150 frames
        bne ss_wait             ; keep holding the splash until X hits 0

        lda #%00001011           ; text mode again but screen OFF: black out the
        sta SCROLY               ; transition while boot rebuilds bank 0
        lda $dd00                ; back to VIC bank 0
        ora #%00000011          ; bank bits %11 = bank 0 ($0000-$3fff, the game's bank)
        sta $dd00               ; VIC fetches from bank 0 again (screen still blanked)
        rts                     ; fall back into start; init turns the display on later

; =====================================================================
;  TITLE ROUTINES
; =====================================================================

; enter_title: set up the 8 logo sprites and enter GS_TITLE.
enter_title                     ; called from start (boot) and from over_update (attract loop)
        lda #0                  ; value 0
        sta titleFrame          ; reset frame counter so animations restart from frame 0
        sta titlePhase           ; 0 = slide-in entrance
        ; clear stale mux schedule (Amendment C: stale schedule clobbers logo sprites)
        sta schCount            ; clear mux schedule count for bank 0 (no gameplay sprites queued)
        sta schCount+1          ; clear mux schedule count for bank 1
        ; sprite pointers: sprites 0-7 -> logo letter blocks, both buffers
        ldx #7                  ; 8 logo sprites (indices 7 down to 0)
et_ptr  lda logoPtrs,x         ; load sprite block pointer for logo letter X
        sta BUF_A+$3f8,x       ; write sprite pointer into BUF_A sprite pointer area ($07F8+X)
        sta BUF_B+$3f8,x       ; write same pointer into BUF_B sprite pointer area (keep buffers in sync)
        dex                     ; next logo letter
        bpl et_ptr              ; loop until all 8 letters programmed (X wraps negative after 0)
        ; all hires (not multicolor), Y-expanded, no X-expand, sprites in front
        lda #0                  ; value 0
        sta SPMC                ; $D01C: all sprites hires (not multicolor) — logo uses 1-bit art
        sta XXPAND              ; $D01D: no X-expansion — logo sprites are normal width
        sta $d010                ; MSB clear (all sprites X < 256)
        sta SPBGPR               ; sprites in front of background
        lda #%11111111          ; all 8 bits set
        sta YXPAND              ; $D017: Y-expand all 8 sprites (double height: 21->42px) for bold logo
        sta SPENA               ; $D015: enable all 8 hardware sprites for the title logo
        ; seed slide-in: all letters at X=0, hidden behind the left border;
        ; they enter one at a time (slideIdx counts 7 -> 0, last E first)
        ldx #7                  ; start seed loop at letter index 7 (rightmost letter E)
        stx slideIdx            ; slideIdx = 7: letter 7 (E, rightmost) starts sliding first
et_seed lda #0                  ; all letters start at X=0 (hidden behind the left border)
        sta logoCurX,x          ; set current X for letter X to 0 (off-screen left)
        dex                     ; next letter
        bpl et_seed             ; loop until all 8 letters seeded
        jsr rebuild_playfield    ; wipe the frozen GAME OVER table; fresh starfield
        ; clear HUD rows 0-1 in both buffers so title shows only the prompt
        jsr clear_hud_rows      ; blank HUD rows 0-1 in both buffers
        lda #0                  ; value 0 = black
        sta BORDER               ; ensure border is always black on title entry
        lda #GS_TITLE           ; gameState value 0 = title screen
        sta gameState           ; enter title state: main loop will now call title_update each frame
        rts                     ; return to caller (start at boot, or over_update at attract cycle)

; title_update: per-frame TITLE logic (sprite placement + prompt + start input).
title_update                    ; called once per frame by main loop while gameState = GS_TITLE
        inc titleFrame          ; advance frame counter (drives sine bob, rainbow roll, blink, slide-in)
        ; --- sequential slide-in: one letter at a time, last (E) first ---
        ; letter slideIdx glides from X=0 (behind the left border) to its
        ; home; on arrival the next letter to the left takes its turn.
        ; letters not yet started sit at X=0, hidden by the border.
        lda titlePhase          ; 0=slide-in, 1=all letters home (steady)
        bne tu_pos_setup         ; steady phase: all letters home
        ldx slideIdx            ; X = index of the letter currently sliding in
        lda logoCurX,x          ; current X pixel position of the active sliding letter
        clc                     ; clear carry for addition
        adc #SLIDE_SPEED        ; advance position by SLIDE_SPEED pixels this frame
        cmp logoHomeX,x         ; has this letter reached its home position?
        bcc tu_sl_store          ; still short of home
        lda logoHomeX,x          ; arrived: clamp to home...
        sta logoCurX,x          ; lock letter at its home X (no overshoot)
        dec slideIdx             ; ...and start the letter to the left
        bpl tu_pos_setup        ; slideIdx still >= 0: another letter to animate
        lda #1                   ; letter 0 (A) arrived: entrance done
        sta titlePhase          ; switch to steady phase (1): all letters home, no more sliding
        bne tu_pos_setup        ; A=1: always taken — fall through impossible
tu_sl_store                     ; letter still en route: save updated X and fall into position setup
        sta logoCurX,x          ; store updated sliding X for the active letter
tu_pos_setup                    ; place all 8 logo sprites each frame (whether sliding or steady)
        ; --- precompute logoShift = titleFrame >> 2 (rainbow roll speed) ---
        lda titleFrame          ; load frame counter
        lsr                     ; divide by 2
        lsr                     ; divide by 4: slow the rainbow roll to one color step per 4 frames
        sta logoShift           ; store shift amount for rainbow palette lookup
        ; --- write sprite registers each frame ---
        ldx #7                  ; process 8 letters: X counts 7 down to 0
tu_pos  txa                     ; A = letter index (0-7)
        asl                     ; A = X*2 (each hw sprite uses 2 position registers: Xreg at even, Yreg at odd)
        tay                      ; Y = 2*x (VIC sprite register offset)
        lda logoCurX,x          ; current X pixel for this letter (home or mid-slide)
        sta VIC,y                ; $D000 + 2x  (X low byte)
        ; --- sine bob Y: LOGO_Y + sineTable[(titleFrame + X*8) & 63] ---
        txa                     ; A = letter index X
        asl                     ; *2
        asl                     ; *4
        asl                      ; A = X*8
        clc                     ; clear carry for addition
        adc titleFrame          ; phase-shift each letter by 8 frames so they bob at different heights
        and #%00111111           ; index = (titleFrame + X*8) & 63
        stx tmpSlot             ; save letter index X (A is about to be clobbered by sine table lookup)
        tax                     ; X = sine table index
        lda sineTable,x         ; signed byte offset from sineTable (range -8..+7); negative entries wrap correctly
        ldx tmpSlot              ; restore X = letter index
        clc                     ; clear carry for addition
        adc #LOGO_Y              ; unsigned add; negative entries wrap correctly
        sta VIC+1,y              ; Y register (Y still = 2*x)
        ; --- rainbow color: logoPalette[(logoShift + X) & 7] ---
        txa                     ; A = letter index X
        clc                     ; clear carry for addition
        adc logoShift           ; add rolling offset so colors cycle each 4 frames
        and #7                  ; wrap to palette range 0-7
        stx tmpSlot             ; save letter index X (about to be clobbered by palette lookup)
        tax                     ; X = palette index
        lda logoPalette,x       ; load rainbow color value for this letter
        ldx tmpSlot              ; restore X = letter index
        sta SP0COL,x            ; $D027+X: write color to hardware sprite X color register
        ; --- pulse: every 32 frames, 4-frame white flash overrides rainbow ---
        lda titleFrame          ; load frame counter
        and #%00011111          ; mask to 5-bit cycle (repeats every 32 frames)
        cmp #4                  ; first 4 frames of each 32-frame cycle trigger the white flash
        bcs tu_nopulse          ; >= 4: not in flash window, keep rainbow color
        lda #1                  ; color 1 = white: overrides rainbow for the brief pulse
        sta SP0COL,x            ; $D027+X: force sprite X to white for the pulse flash
tu_nopulse                      ; pulse window done; continue to next letter
        dex                     ; next letter (counting down)
        bpl tu_pos              ; loop while X >= 0 (letters 7 down to 0)
        jsr draw_title_hud      ; blink "PRESS FIRE TO START" in the HUD band
        ; --- scan the Space row ourselves (player_update doesn't run in TITLE) ---
        lda #$7f                ; $7F: select CIA port A row 7 (space bar row)
        sta $dc00                ; select CIA port A row $7f (space key row)
        lda $dc01               ; read CIA port B: column bits for the selected row (0=pressed)
        sta keyrow7             ; cache key row 7 (space bar); also read by update_bullets in PLAY
        ; --- FIRE (space) edge detect -> start game ---
        and #%00010000           ; bit4: 0 = pressed, 1 = not pressed (active-low)
        bne tu_nofire            ; bit set = NOT pressed
        lda prevSpace           ; check if space was already down last frame
        bne tu_held              ; was already down last frame -> no new edge
        ; rising edge: space freshly pressed -> start the game
        lda #1                  ; value 1 = held
        sta prevSpace            ; carry "down" into PLAY so no stray first shot
        jsr start_game          ; initialize all game state for a new run
        lda #GS_PLAY            ; gameState value 1 = playing
        sta gameState           ; switch main loop dispatch to gameplay path
        rts                     ; return; main loop will call player_update next frame
tu_held                         ; space held (not a new press): debounce, don't re-trigger start
        lda #1                  ; value 1 = still held
        sta prevSpace           ; update hold state
        rts                     ; return without starting game
tu_nofire                       ; space not pressed: clear hold state
        lda #0                  ; value 0 = released
        sta prevSpace           ; clear hold state so next press is detected as a fresh edge
        rts                     ; return

; draw_title_hud: blink "PRESS FIRE TO START" in the static HUD band.
; label_press terminates with $ff (interior spaces are screen code 0 = blank tile).
draw_title_hud                  ; called each frame from title_update
        ; --- write chars to both screen buffers, row 1 col 10 ---
        ldx #0                  ; X = character index within label
dth_txt lda label_press,x       ; load next character code from "PRESS FIRE TO START" string
        cmp #$ff                ; $FF = string terminator
        beq dth_done            ; terminator reached: all chars written
        sta BUF_A+40+10,x       ; write char to front buffer: row 1 (offset 40), col 10+
        sta BUF_B+40+10,x       ; write same char to back buffer (kept in sync so it shows in either flip state)
        inx                     ; advance to next character
        bne dth_txt             ; loop (X never reaches 0 before $FF terminator)
dth_done                        ; all text chars written; now set color
        ; --- determine blink color and stash in scratch ---
        ; blink on when titleFrame bit5 = 0, dim when bit5 = 1
        lda titleFrame          ; load frame counter for blink timing
        and #%00100000          ; test bit 5: toggles every 32 frames (~1.5 Hz blink at 50fps)
        beq dth_on               ; bit5 = 0 -> bright
        lda #6                   ; bit5 = 1 -> dim
        jmp dth_savecolor       ; use dim color (6 = dark blue)
dth_on  lda #HUD_COLOR          ; bit5 = 0: use HUD_COLOR (white = 1, bright phase)
dth_savecolor                   ; A holds the blink color (white or dim blue)
        sta dth_col_val          ; save color; reload per-iteration below
        ; --- write color to color RAM for each label char ---
        ldx #0                  ; X = character index for color RAM pass
dth_cl  lda label_press,x       ; read char to detect terminator ($FF)
        cmp #$ff                ; end of string?
        beq dth_cret            ; yes: done writing color
        lda dth_col_val          ; reload color (A was clobbered by label read)
        sta COLORRAM+40+10,x    ; write blink color to color RAM: row 1 col 10+X
        inx                     ; next character
        bne dth_cl              ; loop
dth_cret                        ; color RAM updated
        rts                     ; return
dth_col_val !byte 0              ; scratch: blink color for color-RAM pass (reused by draw_over_hud)
; =====================================================================
;  GAME OVER STATE ROUTINES
; =====================================================================

; over_update: per-frame GS_OVER logic — blink GAME OVER text, then
; return to title after OVER_FRAMES frames.
over_update                     ; per-frame GS_OVER driver: blink text, handle FIRE, count to title
        inc titleFrame           ; reuse titleFrame for blink cadence (drives draw_over_hud flash)
        ; border flash countdown (player_update doesn't run in OVER; without
        ; this the red border sticks and exposes the 40/38-col band offsets)
        lda flashTimer           ; border-flash countdown: non-zero = death flash still pending
        beq ou_noflash           ; zero = flash expired, skip border work
        dec flashTimer           ; tick the flash countdown down one frame
        bne ou_noflash           ; still counting: leave border color unchanged
        lda #0                   ; timer just hit zero: prepare black (color 0)
        sta BORDER               ; $D020: restore border to black when flash expires
ou_noflash                       ; border flash handled; proceed to FIRE key check
        ; --- FIRE skips to the title (after a short lockout) ---
        lda overTimer            ; load frames-remaining counter for GAME OVER display
        cmp #OVER_FRAMES-30      ; first ~0.6 s (30 frames at 50 Hz): ignore fire
        bcs ou_nofire            ; first ~0.6s: ignore fire (death mash guard)
        lda #$7f                 ; %01111111: assert row 7 (PA7 low) — space bar row
        sta $dc00                ; select the space key row (CIA port A)
        lda $dc01                ; read CIA1 port B: column bits for row 7 (0=pressed)
        sta keyrow7              ; cache row 7 (shared with update_bullets fire read)
        and #%00010000           ; bit4: 0 = pressed (active low)
        bne ou_spup              ; bit set = space NOT pressed this frame
        lda prevSpace            ; space is pressed: was it already held last frame?
        bne ou_nofire            ; held, not a fresh press
        lda #1                   ; new press: latch it to block re-edge on continued hold
        sta prevSpace            ; consume the press (title won't re-edge on it)
        jsr enter_title          ; fresh FIRE press: skip straight to title
        rts                      ; enter_title set up new state; we're done here
ou_spup                          ; space released this frame: clear hold latch
        lda #0                   ; prepare zero
        sta prevSpace            ; reset hold latch so next press registers as fresh
ou_nofire                        ; fire-key check done; run per-frame over duties
        lda overTimer            ; first OVER frame: wipe the HUD band here —
        cmp #OVER_FRAMES         ; on the death frame itself draw_hud still ran
        bne ou_noclear           ; after pu_gameover and re-stamped the digits
        jsr clear_hud_rows       ; first frame only: blank HUD band before score table
        jsr draw_score_table     ; stamp TOP SCORES + 5 entries onto frozen playfield (once)
ou_noclear                       ; every frame: refresh GAME OVER blink + new-rank flash
        jsr draw_over_hud        ; blink "GAME OVER" text in HUD row 1 (color via titleFrame)
        jsr hs_flash             ; flash the newly-inserted score row yellow/white (no-op if no new rank)
        dec overTimer            ; count down the GAME OVER display duration
        bne ou_ret               ; still time remaining: return
        jsr enter_title          ; timer expired: back to animated title
ou_ret  rts                      ; return to main loop

; draw_over_hud: stamp flashing "GAME OVER" in HUD row 1 starting at col 16.
; Blinks on titleFrame bit 4: red (color 2) when bit=0, off (color 0) when bit=1.
; Uses $ff-terminated label_gameover; reuses dth_col_val scratch byte.
draw_over_hud                    ; write and blink-color "GAME OVER" text in HUD row 1
        ; --- write chars to both screen buffers, row 1 col 16 ---
        ldx #0                   ; X = character index into label_gameover string
doh_txt lda label_gameover,x     ; load next GAME OVER char code ($ff = end sentinel)
        cmp #$ff                 ; end-of-string sentinel?
        beq doh_done             ; yes: all chars written, proceed to color pass
        sta BUF_A+40+16,x        ; write char to front buffer row 1 (offset 40) col 16+X
        sta BUF_B+40+16,x        ; mirror to back buffer (HUD synced across flip)
        inx                      ; advance character index
        bne doh_txt              ; loop (string < 256 chars; X never wraps in practice)
doh_done                         ; chars written; determine blink-phase color
        ; --- determine blink color ---
        lda titleFrame           ; frame counter incremented each over_update call
        and #%00010000           ; bit 4: toggles every 16 frames -> ~1.6 Hz blink at 50 fps
        beq doh_on               ; bit clear = "on" phase: show text in red
        lda #0                   ; bit set = "off" phase: black (hide text between blinks)
        jmp doh_col              ; go write the chosen color to COLORRAM
doh_on  lda #2                   ; red: VIC-II color 2 (game-over accent)
doh_col sta dth_col_val          ; stash resolved blink color for the COLORRAM write pass
        ; --- write color to color RAM ---
        ldx #0                   ; X = character index for color write pass
doh_cl  lda label_gameover,x     ; reload char code to count characters (same string as text pass)
        cmp #$ff                 ; end of string?
        beq doh_cret             ; yes: color write done
        lda dth_col_val          ; load resolved blink color (red or black)
        sta COLORRAM+40+16,x     ; write color to matching COLORRAM cell (row 1 col 16+X)
        inx                      ; advance to next cell
        bne doh_cl               ; loop over all GAME OVER chars
doh_cret                         ; color pass complete
        rts                      ; return

; draw_score_table: stamp TOP SCORES + 5 entries onto the frozen playfield
; (both buffers + color RAM). Called once, on the first over_update frame.
; Uses zp_dst (main-line only) — never zp_fsrc/zp_bdst (IRQ-shared).
draw_score_table                 ; one-shot: write heading + 5 high-score rows to frozen playfield
        ; --- heading: "TOP SCORES" white at row 8 col 15 ---
        ldx #0                   ; X = char index into label_topscores
dst_head                         ; heading write loop: text + color to both buffers
        lda label_topscores,x    ; load next char of "TOP SCORES" label ($ff = end sentinel)
        cmp #$ff                 ; sentinel?
        beq dst_entries          ; yes: heading done, move to entry rows
        sta BUF_A+HS_HEAD_OFF,x  ; write char to front buffer at heading row/col offset
        sta BUF_B+HS_HEAD_OFF,x  ; mirror to back buffer (playfield frozen; keep both clean)
        lda #1                   ; white
        sta COLORRAM+HS_HEAD_OFF,x ; heading color in color RAM
        inx                      ; next character
        bne dst_head             ; loop (sentinel stops iteration before X wraps)
dst_entries                      ; begin writing 5 score entry rows below the heading
        ; --- 5 entry rows: "<rank>  <6 digits>" light gray ---
        lda #0                   ; start at entry 0 (rank 1)
        sta hsEntry              ; hsEntry: current entry index (0..HS_COUNT-1)
dst_row                          ; outer loop: one pass per score entry row
        ldx hsEntry              ; X = current entry index
        lda hs_row_lo,x          ; low byte of this entry's BUF_A row base address
        sta zp_dst               ; set ZP pointer low: hs_put uses (zp_dst),Y for all three pages
        lda hs_row_hi,x          ; high byte of this entry's BUF_A row base address
        sta zp_dst+1             ; set ZP pointer high (points into BUF_A page for this row)
        ; rank digit (1..5) at col 0 of the row
        txa                      ; A = entry index (0..4)
        clc                      ; clear carry before add
        adc #DIGIT_BASE+1        ; DIGIT_BASE=16; +1+index gives screen code for '1'..'5'
        ldy #0                   ; column 0: rank digit
        jsr hs_put               ; write char to col 0 of both buffers + color RAM (light gray)
        ; two blank cols (screen code 0)
        lda #0                   ; blank tile (screen code 0 = empty cell in custom charset)
        ldy #1                   ; column 1: blank separator
        jsr hs_put               ; write blank at col 1
        lda #0                   ; blank
        ldy #2                   ; column 2: blank separator
        jsr hs_put               ; write blank at col 2
        ; six score digits: hiScores entry bytes hi,mid,lo -> cols 3..8
        lda hsEntry              ; reload entry index to compute byte offset into hiScores
        asl                      ; entry * 2
        clc                      ; clear carry before add
        adc hsEntry              ; A = entry * 3 (three BCD bytes per score: hi, mid, lo)
        tax                      ; X = byte offset of this entry in the hiScores array
        lda hiScores+2,x         ; high BCD byte -> digit cols 3,4
        jsr dh_split             ; split into two digit codes: hundred-thousands + ten-thousands
        lda dhHi                 ; char code for the leftmost digit (hundred-thousands)
        ldy #3                   ; column 3
        jsr hs_put               ; write digit to col 3
        lda dhLo                 ; char code for the ten-thousands digit
        ldy #4                   ; column 4
        jsr hs_put               ; write digit to col 4
        lda hsEntry              ; recompute entry*3 — deliberate: no reliance on X surviving the jsrs
        asl                      ; entry * 2
        clc                      ; clear carry
        adc hsEntry              ; entry * 3
        tax                      ; X = byte offset
        lda hiScores+1,x         ; mid byte -> cols 5,6
        jsr dh_split             ; split into thousands + hundreds digit codes
        lda dhHi                 ; char code for the thousands digit
        ldy #5                   ; column 5
        jsr hs_put               ; write the thousands digit
        lda dhLo                 ; char code for the hundreds digit
        ldy #6                   ; column 6
        jsr hs_put               ; write the hundreds digit
        lda hsEntry              ; recompute entry*3 again (same no-assumptions discipline)
        asl                      ; entry * 2
        clc                      ; clear carry
        adc hsEntry              ; entry * 3
        tax                      ; X = byte offset
        lda hiScores+0,x         ; low byte -> cols 7,8
        jsr dh_split             ; split into tens + ones digit codes
        lda dhHi                 ; char code for the tens digit
        ldy #7                   ; column 7
        jsr hs_put               ; write the tens digit
        lda dhLo                 ; char code for the ones digit (rightmost)
        ldy #8                   ; column 8
        jsr hs_put               ; write the ones digit
        inc hsEntry              ; advance to next score entry
        lda hsEntry              ; reload updated entry index
        cmp #HS_COUNT            ; all HS_COUNT (5) entries written?
        beq dst_done             ; branch-range trampoline: bne dst_row was >127 bytes back
        jmp dst_row              ; not done: jmp because bne would exceed short-branch range
dst_done                         ; all 5 score rows written to both buffers and color RAM
        rts                      ; return

; hs_put: write char A at column Y of the current entry row (zp_dst holds
; the row's BUF_A address). Writes to BUF_A, BUF_B (+$34 page), and
; COLORRAM (+$D4 page) with light gray (15). Preserves Y; restores zp_dst
; to the BUF_A page.
hs_put                           ; write char A at col Y to BUF_A, BUF_B, and COLORRAM
        sta hsChar               ; save char code (A destroyed by page arithmetic below)
        lda zp_dst+1             ; load BUF_A page high byte for this row
        sta hsHi                 ; stash high byte for restoration after two page adjustments
        lda hsChar               ; reload char code
        sta (zp_dst),y           ; BUF_A: write char at column Y of current row
        lda hsHi                 ; recover BUF_A high byte
        clc                      ; clear carry before add
        adc #$34                 ; BUF_B is $3400 above BUF_A in memory ($3800 - $0400 = $3400)
        sta zp_dst+1             ; redirect zp_dst to BUF_B page for this row
        lda hsChar               ; reload char
        sta (zp_dst),y           ; BUF_B: write same char at column Y
        lda hsHi                 ; recover BUF_A high byte again
        clc                      ; clear carry
        adc #$d4                 ; COLORRAM is $D400 above BUF_A ($D800 - $0400 = $D400)
        sta zp_dst+1             ; redirect zp_dst to COLORRAM page for this row
        lda #15                  ; light gray: VIC-II color 15 (readable on dark playfield)
        sta (zp_dst),y           ; COLORRAM: write color at column Y
        lda hsHi                 ; recover original BUF_A high byte
        sta zp_dst+1             ; restore zp_dst to BUF_A page (caller may loop with same pointer)
        rts                      ; return

; hs_flash: flash the newly-inserted row's color cells (yellow/white) on
; titleFrame bit 3. No-op when the run didn't place (newRank = $ff).
hs_flash                         ; flash color cells of the new-rank score row (yellow/white blink)
        ldx newRank              ; X = rank slot that just placed (0..4), or $ff = didn't place
        cpx #HS_COUNT            ; $ff (or >= HS_COUNT=5): sentinel meaning no new placement
        bcs hf_ret               ; no placement this run: skip flash entirely
        lda hs_row_lo,x          ; low byte of the placed row's BUF_A address
        sta zp_dst               ; set ZP pointer low
        lda hs_row_hi,x          ; high byte of placed row's BUF_A address
        clc                      ; clear carry
        adc #$d4                 ; offset to COLORRAM page ($D800 - $0400 = $D400 above BUF_A)
        sta zp_dst+1             ; zp_dst -> COLORRAM row for the newly-placed entry
        lda titleFrame           ; per-frame counter driven by over_update inc each frame
        and #%00001000           ; bit 3: toggles every 8 frames -> ~3 Hz flash at 50 fps
        beq hf_white             ; bit clear = white phase
        lda #7                   ; yellow (VIC-II color 7): alternates with white for attention
        bne hf_paint             ; branch always (yellow != 0) — go write color
hf_white                         ; white phase of the flash cycle
        lda #1                   ; white (VIC-II color 1)
hf_paint                         ; A = flash color for this frame (yellow or white)
        ldy #8                   ; 9 cells: rank digit + 2 blanks + 6 score digits = cols 0..8
hf_loop                          ; write flash color to every cell of the placed row
        sta (zp_dst),y           ; write to COLORRAM cell Y of the new-rank row
        dey                      ; step to next lower column index
        bpl hf_loop              ; loop while Y >= 0 (writes cols 8 down to 0 inclusive)
hf_ret  rts                      ; return (either after flash or from no-placement early exit)

; =====================================================================
;  RASTER IRQ CHAIN
;  scroll_irq: bottom-of-frame work (scroll + frame flag) + arm mux chain
;  mux_irq:    programs hw sprites 1-7 round-robin, chains on raster
; =====================================================================

; --- bottom-of-frame IRQ: scroll work, set HUD $D016, arm split_irq ---
scroll_irq                       ; raster IRQ at line 250: per-frame scroll work + chain hand-off
        lda VICIRQ               ; read $D019: VIC-II IRQ status latch (which IRQ fired)
        sta VICIRQ               ; write latch back: clears raster flag — acknowledges the IRQ
        lda gameState            ; GS_OVER: freeze the world — no fine scroll,
        cmp #GS_OVER             ; no row rebuild, no flip. frame_ready and the
        beq scr_frozen           ; IRQ chain still run so over_update keeps ticking.
        jsr scroll_step          ; GS_PLAY/TITLE: advance fine-x; every 8 steps flip buffers
scr_frozen                       ; join: GS_OVER skips scroll_step; both paths continue here
        inc frame_ready          ; tell main loop a frame has elapsed (poll flag in main_loop)
        ; HUD region (top of next frame): 40-col, no fine scroll
        lda #D016_HUD            ; MCM=1, 40-col, fine=0: correct $D016 for the static HUD rows
        sta SCROLX               ; write to $D016: VIC-II uses 40-col at start of next frame
        ; arm the split IRQ at the HUD/playfield boundary
        lda #<split_irq          ; low byte of split_irq handler address
        sta IRQVEC               ; set KERNAL IRQ vector low byte ($0314) to split_irq
        lda #>split_irq          ; high byte of split_irq handler address
        sta IRQVEC+1             ; set KERNAL IRQ vector high byte ($0315) to split_irq
        lda #SPLIT_LINE          ; scanline 65: where HUD ends and scrolling playfield begins
        sta RASTER               ; arm VIC-II to fire next raster IRQ at the HUD/playfield boundary
        pla                      ; restore Y (IRQ entry pushed Y; pulled in reverse order)
        tay                      ; Y register restored
        pla                      ; restore X from IRQ stack frame
        tax                      ; X register restored
        pla                      ; restore A from IRQ stack frame
        rti                      ; return; split_irq will fire at raster SPLIT_LINE (65)

; --- split IRQ: switch to playfield scroll mode, then arm the mux chain ---
split_irq                        ; raster IRQ at SPLIT_LINE=65: switch to scroll mode, arm mux
        lda VICIRQ               ; read $D019: acknowledge raster IRQ at the HUD/playfield split
        sta VICIRQ               ; write back to clear latch (must do or IRQ re-fires immediately)
        ; playfield region below the split: 38-col + fine scroll
        lda #D016_PLAY_BASE      ; $D016 base: MCM=1, 38-col — base mask for scrolling playfield
        ora fine_x               ; OR in current fine-scroll offset (0-7 pixels) from zero page
        sta SCROLX               ; write to $D016: VIC-II switches to 38-col scrolling mode below HUD
        ; arm next: mux chain (if sprites) else scroll_irq@250
        ; Amendment B: only park mux sprites during GS_PLAY; in TITLE the logo
        ; sprites are written directly each frame and must not be clobbered.
        lda gameState            ; load current game state to decide whether to park sprites
        cmp #GS_PLAY             ; only park hw sprites during GS_PLAY (not title or game-over)
        bne sp_nopark            ; TITLE/OVER: logo sprites are direct-written — leave them alone
        jsr park_mux_sprites     ; GS_PLAY: move hw sprites 1-7 to Y=$F8 before mux reprograms them
sp_nopark                        ; join: park gating done; set up mux schedule pointers
        lda #1                   ; hw sprite 1 is the first mux slot (slot 0 = player, reserved)
        sta muxHW                ; muxHW: which hw sprite slot (1-7) is programmed next
        ldx #0                   ; default: front bank 0 starts at schedule array index 0
        lda schFront             ; which double-buffer bank (0 or 1) is the live front schedule?
        beq sp_base0             ; front==0: base index stays 0
        ldx #15                  ; front==1: second bank occupies array indices 15..29
sp_base0                         ; X = base index of the live front schedule bank
        stx muxIdx               ; muxIdx = first schedule entry to program this frame
        ldy schFront             ; index into schCount by bank (0 or 1)
        txa                      ; A = base index of this bank
        clc                      ; clear carry before add
        adc schCount,y           ; add active-sprite count for this bank
        sta muxEnd               ; muxEnd = one-past-last valid entry (end sentinel for mux_irq)
        lda muxEnd               ; re-read sentinel
        cmp muxIdx               ; equal -> count was 0 -> no virtual sprites this frame
        beq sp_nosprites         ; nothing to display: skip mux chain entirely
        lda #<mux_irq            ; low byte of mux_irq handler address
        sta IRQVEC               ; redirect IRQ vector to mux_irq (low byte)
        lda #>mux_irq            ; high byte of mux_irq handler address
        sta IRQVEC+1             ; redirect IRQ vector to mux_irq (high byte)
        ldx muxIdx               ; X = first schedule entry index
        lda schY,x               ; Y screen position of the first sprite to program this frame
        sec                      ; set carry for subtraction
        sbc #MUX_LEAD            ; fire IRQ MUX_LEAD=16 lines BEFORE sprite Y: allows programming time
        sta spArm               ; desired arm line = schY - lead. The beam is
        lda RASTER              ; already ~2 lines past the split by now, so
        clc                     ; clamp against the LIVE raster, not the split
        adc #2                  ; constant: arming a passed line would not fire
        cmp spArm               ; until NEXT frame (chain stall: sprites stay
        bcc sp_armok            ; parked + no frame tick = half-speed game).
        sta spArm               ; beam+2 >= desired -> arm beam+2 instead; the
sp_armok                       ; mux burst then programs late entries immediately
        lda spArm               ; via its behind-check.
        sta RASTER               ; arm raster IRQ: max(schY-MUX_LEAD, beam+2) — always ahead of beam
        jmp sp_exit              ; sprites exist: skip no-sprites fallback path
sp_nosprites                     ; no sprites this frame: bypass mux chain entirely
        lda #<scroll_irq         ; point IRQ vector straight back to scroll_irq (no mux needed)
        sta IRQVEC               ; restore IRQ vector low byte to scroll_irq
        lda #>scroll_irq         ; high byte of scroll_irq
        sta IRQVEC+1             ; restore IRQ vector high byte to scroll_irq
        lda #250                 ; re-arm at line 250: bottom-of-frame position for next frame
        sta RASTER               ; write raster compare for no-mux path
sp_exit                          ; IRQ armed; restore registers and return from interrupt
        pla                      ; restore Y from IRQ stack frame
        tay                      ; Y register restored
        pla                      ; restore X from IRQ stack frame
        tax                      ; X register restored
        pla                      ; restore A from IRQ stack frame
        rti                      ; return; mux_irq or scroll_irq fires next depending on path taken

; --- multiplex IRQ: program next hw sprite(s), chain to next raster line ---
mux_irq                          ; raster IRQ: program one hw sprite per band, chain to next Y
        lda VICIRQ               ; read $D019: acknowledge the raster IRQ
        sta VICIRQ               ; write back: clears flag — must do or IRQ re-fires immediately
mux_loop                         ; inner loop: program sprites at or behind the current raster
        ldx muxIdx               ; X = schedule index of next virtual sprite to program
        cpx muxEnd               ; compare to end sentinel
        bcc mx_go               ; mux_done is past short-branch range from here
        jmp mux_done             ; muxIdx >= muxEnd: all virtual sprites done for this frame
mx_go
        ; program hw sprite muxHW from schedule entry x
        lda muxHW                ; A = current hardware sprite slot number (1-7)
        asl                      ; multiply by 2: X reg at even offset, Y reg at odd offset
        tay                      ; y = 2*hw (X/Y register index)
        lda schXlo,x             ; low 8 bits of virtual sprite screen X position
        sta $d000,y              ; write to VIC-II sprite X register ($D000 + 2*hw)
        lda schY,x               ; virtual sprite screen Y position
        sta $d001,y              ; write to VIC-II sprite Y register ($D001 + 2*hw)
        ldy muxHW                ; y = muxHW (for bit-table lookup and color register index)
        lda schXhi,x             ; X position MSB: nonzero if sprite X > 255 (right half of screen)
        beq mx_clr               ; zero: X fits in 8 bits — clear MSB bit for this sprite
        lda $d010                ; read $D010: sprite X MSB register (1 bit per hw sprite)
        ora msbset,y             ; RMW: set bit for this hw sprite
        sta $d010                ; write back: sprite can now reach X positions 256-343
        jmp mx_col               ; MSB set; skip the clear path
mx_clr                           ; X fits in 8 bits: clear this sprite's MSB bit in $D010
        lda $d010                ; read $D010 sprite X MSB register
        and msbclr,y             ; RMW: clear bit for this hw sprite (X restricted to 0-255)
        sta $d010                ; write back: sprite constrained to left half of screen
mx_col                           ; color and X-expand setup follow
        ldy muxHW                ; y = muxHW (index into $D027-$D02E color registers)
        lda schColor,x           ; virtual sprite color index (0-15)
        sta $d027,y              ; write to VIC-II sprite color register ($D027 + hw)
        ; per-sprite X-expand: set bit for this hw sprite if beam, else clear
        ; (Y still = muxHW from color write above)
        lda schExpand,x          ; X-expand flag: nonzero = double-wide sprite (beam weapon)
        beq mx_noexp             ; zero: normal width — clear the expand bit
        lda $d01d                ; read $D01D: sprite X-expand register (1 bit per hw sprite)
        ora msbset,y             ; RMW: set bit for this hw sprite — doubles horizontal width
        sta $d01d                ; write back: sprite is now X-expanded (beam weapon visual)
        jmp mx_expdone           ; expand bit set; skip the clear path
mx_noexp                         ; no X-expand: ensure this hw sprite's expand bit is clear
        lda $d01d                ; read $D01D sprite X-expand register
        and msbclr,y             ; RMW: clear bit for this hw sprite (normal single width)
        sta $d01d                ; write back: sprite is standard width
mx_expdone                       ; all registers written; advance to next virtual sprite
        ; advance schedule index + round-robin hw 1..7
        inc muxIdx               ; step to next virtual sprite in the schedule
        ldy muxHW                ; Y = current hw sprite slot
        iny                      ; advance hw slot: 1->2->...->7->wrap
        cpy #8                   ; past slot 7 (mux range is slots 1-7)?
        bne mx_hwok              ; no: slot 2-7 still valid, keep it
        ldy #1                   ; yes: wrap back to slot 1 (slot 0 = player ship, never muxed)
mx_hwok                          ; Y = next valid hw sprite slot (1-7)
        sty muxHW                ; save updated hw sprite number for next iteration
        ; decide next IRQ line or loop
        ldx muxIdx               ; X = next schedule index (just incremented above)
        cpx muxEnd               ; all virtual sprites scheduled?
        bcs mux_done             ; yes: hand chain off to scroll_irq
        lda schY,x               ; Y position of the next virtual sprite to program
        sec                      ; set carry for subtraction
        sbc #MUX_LEAD            ; desired IRQ line = next sprite Y minus MUX_LEAD=16
        cmp RASTER               ; desired line vs. current raster position (live $D012 read)
        bcc mux_ltramp           ; desired < current: beam already past it — loop to program now
        beq mux_ltramp          ; desired == current -> the VIC compared the latch
                                ; at this line's start, so arming the line we're
                                ; ON would not fire until NEXT frame -> program now
        sta RASTER               ; arm next IRQ at (next sprite Y - MUX_LEAD)
        cmp RASTER               ; re-read $D012: race check (did beam pass while storing?)
        bcc mux_ltramp           ; still behind — loop immediately rather than stalling a frame
        beq mux_ltramp          ; raster reached the armed line as we wrote it ->
                                ; its compare already passed -> program now
        jmp mux_exit             ; IRQ armed safely — exit handler and wait for it to fire
mux_done                         ; all virtual sprites programmed; hand chain back to scroll_irq
        ; last sprite done -> hand off to scroll_irq at line 250
        lda #<scroll_irq         ; low byte of scroll_irq address
        sta IRQVEC               ; restore IRQ vector low byte to scroll_irq
        lda #>scroll_irq         ; high byte of scroll_irq address
        sta IRQVEC+1             ; restore IRQ vector high byte to scroll_irq
        lda #250                 ; raster 250 = bottom-of-frame: where next frame's scroll work runs
        sta RASTER               ; arm scroll_irq to fire at line 250 next frame
mux_exit                         ; restore CPU state and return from IRQ
        pla                      ; restore Y from IRQ stack frame
        tay                      ; Y register restored
        pla                      ; restore X from IRQ stack frame
        tax                      ; X register restored
        pla                      ; restore A from IRQ stack frame
        rti                      ; return from interrupt
mux_ltramp                      ; trampoline: mux_loop out of short-branch range after expand insert
        jmp mux_loop             ; beam behind schedule — jump back to program the lagging sprite now

; --- init_hud_bar: fill rows 0-1 of BOTH buffers with char 2 + HUD color ---
; (temporary HUD marker; Task 2 replaces with score/lives digits)
init_hud_bar                     ; initialize 2-row HUD band to blank in both screen buffers
        ldx #0                   ; X = byte offset into screen buffer, start at cell 0
ihb_loop                         ; loop over 80 HUD cells (rows 0-1 x 40 cols)
        cpx #80                  ; 2 rows x 40 cols = 80 cells total
        bcs ihb_done             ; X >= 80: all HUD cells written
        lda #0                   ; blank tile (char 0 = empty cell in custom charset)
        sta BUF_A,x              ; clear cell in front screen buffer (BUF_A = $0400)
        sta BUF_B,x              ; clear same cell in back screen buffer (BUF_B = $3800)
        lda #HUD_COLOR           ; HUD color attribute (white = 1)
        sta COLORRAM,x           ; write color to color RAM ($D800+X); fixed at $D800 always
        inx                      ; advance to next cell
        jmp ihb_loop             ; loop until all 80 HUD cells initialized
ihb_done                         ; HUD cells blanked and colored; now stamp static text labels
        ; --- static labels: "Score: " row 0 col 0, "Ships left: " row 1 col 0 ---
        ldx #0                   ; X = character index within the "Score: " label
ihb_sc                           ; loop: write "Score: " (7 chars) to row 0
        cpx #7                   ; "Score: " is 7 characters (cols 0-6)
        bcs ihb_sc_done          ; X >= 7: all 7 chars written
        lda label_score,x        ; load next character code from "Score: " label data
        sta BUF_A,x              ; write to front buffer row 0
        sta BUF_B,x              ; write to back buffer row 0 (keep both in sync)
        inx                      ; next character
        jmp ihb_sc               ; loop until all 7 chars written
ihb_sc_done                      ; "Score: " label written; now write "Ships left: "
        ldx #0                   ; X = character index within the "Ships left: " label
ihb_sh                           ; loop: write "Ships left: " (12 chars) to row 1
        cpx #12                  ; "Ships left: " is 12 characters (cols 0-11)
        bcs ihb_sh_done          ; X >= 12: all 12 chars written
        lda label_ships,x        ; load next character from "Ships left: " label data
        sta BUF_A+40,x           ; row 1
        sta BUF_B+40,x           ; write to back buffer row 1 (offset 40 = second row start)
        inx                      ; next character
        jmp ihb_sh               ; loop until all 12 chars written
ihb_sh_done                      ; both static labels written to both buffers
        rts                      ; return — HUD rows initialized in both buffers

; clear_hud_rows: blank rows 0-1 in both screen buffers (80 bytes, indices 0-79).
; Writes char 0 (blank tile) so the HUD band shows only what is explicitly stamped.
; Called from enter_title (before title prompt) and pu_gameover (before GAME OVER text).
clear_hud_rows                   ; wipe 80-cell HUD band (rows 0-1) to blank in both screen buffers
        lda #0                   ; blank tile: char code 0 (custom charset empty cell)
        ldx #79                  ; start at last HUD cell (index 79 = row 1 col 39)
chr_lp  sta BUF_A,x              ; clear cell in front buffer (counts down; bpl terminates at 0)
        sta BUF_B,x              ; clear same cell in back buffer
        dex                      ; step to next lower cell index
        bpl chr_lp               ; loop while X >= 0 (clears indices 79 down to 0 inclusive)
        rts                      ; return: both HUD rows are blank in both screen buffers

; ---------------------------------------------------------------------
; draw_hud: write 6 score digits (cols 0..5) + lives digit (col 38) to
; row 0 of both screen buffers. BCD score; score+2 = leftmost pair.
; ---------------------------------------------------------------------
draw_hud                         ; refresh HUD row 0 score digits and row 1 lives count each frame
        ; "Score: " is at row0 cols 0-6; score digits go at cols 7-12.
        ; high pair (score+2) -> cols 7,8
        lda score+2              ; most-significant BCD byte of score (digits 5-4, ten-thousands)
        jsr dh_split             ; A hi-nibble -> dhHi (code), lo-nibble -> dhLo (code)
        lda dhHi                 ; char code for score digit 5 (leftmost displayed digit)
        sta BUF_A+7              ; write to front buffer row 0 col 7
        sta BUF_B+7              ; write same char to back buffer row 0 col 7
        lda dhLo                 ; char code for score digit 4
        sta BUF_A+8              ; write to front buffer row 0 col 8
        sta BUF_B+8              ; write same char to back buffer row 0 col 8
        ; mid pair (score+1) -> cols 9,10
        lda score+1              ; middle BCD byte of score (digits 3-2, hundreds)
        jsr dh_split             ; split into two digit char codes
        lda dhHi                 ; char code for score digit 3
        sta BUF_A+9              ; write to front buffer row 0 col 9
        sta BUF_B+9              ; write same to back buffer
        lda dhLo                 ; char code for score digit 2
        sta BUF_A+10             ; write to front buffer row 0 col 10
        sta BUF_B+10             ; write same to back buffer
        ; low pair (score+0) -> cols 11,12
        lda score+0              ; least-significant BCD byte of score (digits 1-0, ones)
        jsr dh_split             ; split into two digit char codes
        lda dhHi                 ; char code for score digit 1
        sta BUF_A+11             ; write to front buffer row 0 col 11
        sta BUF_B+11             ; write same to back buffer
        lda dhLo                 ; char code for score digit 0 (rightmost)
        sta BUF_A+12             ; write to front buffer row 0 col 12
        sta BUF_B+12             ; write same to back buffer
        ; "Ships left: " is at row1 cols 0-11; lives digit at row1 col 12 (offset 52)
        lda lives                ; current lives count (0-9)
        clc                      ; clear carry before add
        adc #DIGIT_BASE          ; convert raw count to custom charset digit char code (base 16)
        sta BUF_A+52             ; write to front buffer: row 1 col 12 (40+12=52)
        sta BUF_B+52             ; write same to back buffer row 1 col 12
        rts                      ; return — both buffers now show updated score and lives

; split BCD byte A into two digit char codes: dhHi (high nibble), dhLo (low nibble)
dh_split                         ; unpack one BCD byte into two custom-charset digit char codes
        pha                      ; save original BCD byte (need lo nibble after extracting hi)
        lsr                      ; shift right 1
        lsr                      ; shift right 2
        lsr                      ; shift right 3
        lsr                      ; shift right 4: high nibble now in bits 0-3
        clc                      ; clear carry before add
        adc #DIGIT_BASE          ; add charset offset: nibble 0-9 -> digit char code 16-25
        sta dhHi                 ; store high-nibble digit char code (tens/hundreds position)
        pla                      ; restore original BCD byte
        and #$0f                 ; mask off upper nibble: keep only low nibble (bits 0-3)
        clc                      ; clear carry
        adc #DIGIT_BASE          ; convert low nibble to digit char code (16-25)
        sta dhLo                 ; store low-nibble digit char code (ones/tens position)
        rts                      ; return: dhHi = high digit code, dhLo = low digit code
dhHi !byte 0                     ; temp: char code for high (left) BCD digit of the last split
dhLo !byte 0                     ; temp: char code for low (right) BCD digit of the last split
; =====================================================================
;  PLAYER UPDATE  (once per frame from main loop)
;  TEMPORARY heartbeat: tints the border each frame to prove the frame
;  flag + main loop are alive. Replaced by real input/movement in Task 4.
; =====================================================================

; ---------------------------------------------------------------------
; player_update: state dispatcher. ALIVE -> normal play; EXPLODE ->
; frozen+blink+countdown then respawn/game-over; INVULN -> play+blink.
; ---------------------------------------------------------------------
player_update                   ; entry: per-frame state dispatcher, called from main loop
        ; border flash countdown (game over feedback)
        lda flashTimer          ; load border-flash countdown (set to 20 on game over, 0 = no flash)
        beq pu_disp             ; zero = no flash active, skip straight to state dispatch
        dec flashTimer          ; decrement flash timer each frame
        bne pu_disp             ; still counting down, leave border color as-is
        lda #0                  ; timer just hit zero: prepare black (color 0)
        sta BORDER              ; $D020: restore border to black when flash expires
pu_disp                         ; dispatch on playerState: 0=ALIVE, 1=EXPLODE, 2=INVULN
        lda playerState         ; 0=PS_ALIVE, 1=PS_EXPLODE, 2=PS_INVULN
        bne pu_not_alive        ; nonzero = not fully alive, branch away
        jmp pu_normal_play      ; ALIVE: normal play (ends in rts)
pu_not_alive                    ; playerState nonzero: PS_EXPLODE or PS_INVULN
        cmp #PS_INVULN          ; test for invulnerability state (value 2)
        beq pu_invuln           ; branch to invuln handler if so
        ; PS_EXPLODE: frozen, blink, count down
        lda #$ff                ; $FF = all bits set (no key appears pressed)
        sta keyrow7             ; freeze firing during explosion (update_bullets reads keyrow7)
        jsr pu_blink            ; toggle sprite 0 visibility for explosion blink effect
        dec playerTimer         ; count down explosion duration (set to PEXPLODE_FRAMES on hit)
        beq pu_explode_end      ; reached zero: explosion animation finished
        rts                     ; still exploding, nothing more to do this frame
pu_explode_end                  ; explosion timer reached zero: check remaining lives
        lda lives               ; check remaining lives
        beq pu_gameover         ; zero lives -> trigger game over sequence
        jsr player_respawn      ; lives remain: respawn at start position as invulnerable
        rts                     ; return; player is now PS_INVULN
pu_gameover                     ; no lives left: record score, tear down play state, enter GS_OVER
        jsr score_insert         ; record the run before tearing the game down
        jsr clear_actors         ; park all 15 virtual sprite slots
        lda #0                  ; prepare zero: silence all hardware sprites
        sta SPENA                ; blank all hardware sprites (starfield + GAME OVER only)
        ; (HUD band is wiped on the first over_update frame, not here: draw_hud
        ;  still runs later in this same frame and would re-stamp the digits)
        lda #2                   ; red border flash on death
        sta BORDER              ; $D020: flash border red as game-over death feedback
        lda #20                 ; flash duration: 20 frames (~0.4 s at 50 fps)
        sta flashTimer          ; arm flash countdown; player_update clears border when it expires
        lda #OVER_FRAMES        ; load game-over screen display duration (~5 s)
        sta overTimer           ; arm over-screen countdown; over_update decrements then returns to title
        lda #GS_OVER            ; game-over state code (2)
        sta gameState           ; transition main loop to GS_OVER; over_update replaces player_update
        rts                     ; return; main loop now routes each frame through over_update
pu_invuln                       ; INVULN path: player can move and fire while blinking
        jsr pu_normal_play      ; can move/fire while invulnerable
        jsr pu_blink            ; blink sprite 0 to signal invulnerability to player
        dec playerTimer         ; count down invulnerability duration (set to INVULN_FRAMES on respawn)
        bne pu_inv_ret          ; still counting, return
        lda #PS_ALIVE           ; timer expired: transition to fully ALIVE state
        sta playerState         ; write new state (0 = PS_ALIVE)
        lda SPENA               ; $D015: sprite enable register (1 bit per hardware sprite)
        ora #%00000001          ; ensure bit 0 (sprite 0 = player ship) is set
        sta SPENA               ; guarantee player sprite is visible at end of invulnerability
pu_inv_ret                      ; invuln timer still running, or just expired and state updated
        rts                     ; return to player_update caller


pu_normal_play                  ; ALIVE or INVULN: scan keys, apply movement, write sprite registers
        ; --- scan keyboard matrix rows ---
        lda #$ef                ; %11101111: assert row 4 (PA4 low) — contains I, J, K keys
        sta $dc00                ; CIA1 port A ($DC00): select keyboard matrix row for reading
        lda $dc01               ; CIA1 port B ($DC01): read column bits for row 4 (0=pressed)
        sta keyrow4             ; cache row 4: bit1=I(up), bit2=J(left), bit5=K(down)
        lda #$df                ; %11011111: assert row 5 (PA5 low) — contains L key
        sta $dc00                ; CIA1 port A: select keyboard matrix row 5
        lda $dc01               ; read column bits for row 5
        sta keyrow5             ; cache row 5: bit2=L(right)
        lda #$7f                ; %01111111: assert row 7 (PA7 low) — contains space bar
        sta $dc00                ; CIA1 port A: select keyboard matrix row 7
        lda $dc01               ; read column bits for row 7
        sta keyrow7             ; cache row 7: bit4=space(fire); also read by update_bullets

        ; --- vertical: I (bit1)=up, K (bit5)=down ---
        lda keyrow4             ; reload row 4 key state
        and #%00000010          ; isolate bit 1 = I key
        bne pu_not_up           ; bit set = key NOT pressed (C64 matrix: 0=pressed, 1=released)
        lda player_y            ; I held: load current Y pixel position
        sec                     ; set carry for subtraction
        sbc #2                  ; move up 2 pixels per frame
        sta player_y            ; store updated Y (clamped below by clamp_player)
pu_not_up                       ; I not held: check for downward input
        lda keyrow4             ; reload row 4 key state
        and #%00100000          ; isolate bit 5 = K key
        bne pu_not_down         ; bit set = K NOT pressed
        lda player_y            ; K held: load current Y
        clc                     ; clear carry for addition
        adc #2                  ; move down 2 pixels per frame
        sta player_y            ; store updated Y
pu_not_down                     ; vertical movement applied: check horizontal input

        ; --- horizontal: J (row4 bit2)=left, L (row5 bit2)=right ---
        lda keyrow4             ; reload row 4 key state
        and #%00000100          ; isolate bit 2 = J key
        bne pu_not_left         ; bit set = J NOT pressed
        lda player_x            ; J held: load X low byte (player uses 9-bit X: hi:lo)
        sec                     ; set carry for 16-bit subtraction
        sbc #2                  ; subtract 2 from low byte: move left 2 pixels
        sta player_x            ; store updated X low byte
        lda player_x_hi         ; load X high bit (9th bit, 0 or 1)
        sbc #0                  ; propagate borrow from low byte into high bit
        sta player_x_hi         ; store updated high bit (handles crossing 256 boundary)
pu_not_left                     ; J not held: check right movement
        lda keyrow5             ; load row 5 key state
        and #%00000100          ; isolate bit 2 = L key
        bne pu_not_right        ; bit set = L NOT pressed
        lda player_x            ; L held: load X low byte
        clc                     ; clear carry for 16-bit addition
        adc #2                  ; add 2 to low byte: move right 2 pixels
        sta player_x            ; store updated X low byte
        lda player_x_hi         ; load X high bit
        adc #0                  ; propagate carry into high bit (9-bit X: handles crossing 256)
        sta player_x_hi         ; store updated X high bit
pu_not_right                    ; all movement applied: clamp to play area then write sprite

        jsr clamp_player        ; enforce screen boundaries: X in [24,320], Y in [70,229]
        jsr write_player_sprite ; push player_x/player_y to VIC-II sprite 0 hardware registers
        rts                     ; return; movement applied, position written to hardware

; blink sprite 0 by toggling SPENA bit 0 on (playerTimer & 4)
pu_blink                        ; subroutine: toggle player sprite for ~8 Hz blink effect
        lda playerTimer         ; load current state countdown (explosion or invuln timer)
        and #%00000100          ; test bit 2: changes every 4 frames -> ~8 Hz blink at 50 fps
        beq pb_show             ; bit clear = even phase: show the sprite
        lda SPENA               ; odd phase: load sprite enable register ($D015)
        and #%11111110          ; clear bit 0: disable hardware sprite 0 (player ship)
        sta SPENA               ; write back: sprite 0 hidden this frame
        rts                     ; return; sprite hidden for this blink half
pb_show                         ; even phase: turn sprite 0 back on
        lda SPENA               ; even phase: load sprite enable register
        ora #%00000001          ; set bit 0: enable hardware sprite 0 (player ship)
        sta SPENA               ; write back: sprite 0 visible this frame
        rts                     ; return; sprite shown for this blink half

; respawn player at start, become invulnerable
player_respawn                  ; subroutine: place player at start position, enter PS_INVULN
        lda #60                 ; starting X low byte = 60 (left quarter of screen)
        sta player_x            ; set player X lo (9-bit: 60 < 256, so hi=0)
        lda #0                  ; high bit = 0 (X < 256, no MSB needed in $D010)
        sta player_x_hi         ; clear 9th bit of player X
        lda #120                ; starting Y = 120 (vertically centred in play area)
        sta player_y            ; set player Y coordinate
        lda #PS_INVULN          ; enter PS_INVULN state (value 2): can't be hit
        sta playerState         ; write new player state
        lda #INVULN_FRAMES      ; load invulnerability duration constant (frames)
        sta playerTimer         ; set countdown; pu_invuln decrements each frame
        lda SPENA               ; read sprite enable register ($D015)
        ora #%00000001          ; set bit 0: ensure player sprite is on after respawn
        sta SPENA               ; write back sprite enable
        jsr write_player_sprite ; immediately update hardware sprite 0 X/Y registers
        rts                     ; return; player positioned and PS_INVULN active

; player_hit: only acts when ALIVE. lose a life, start explosion.
player_hit                      ; subroutine: register one hit when player is ALIVE
        lda playerState         ; check current player state
        bne ph_ret              ; nonzero = already exploding or invulnerable: ignore hit
        dec lives               ; decrement remaining lives (will be tested on explosion end)
        lda #PS_EXPLODE         ; enter PS_EXPLODE state (value 1): frozen, blinking
        sta playerState         ; write explosion state
        lda #PEXPLODE_FRAMES    ; load explosion animation duration (frames)
        sta playerTimer         ; set countdown; player_update decrements each frame
        jsr sfx_hit             ; trigger hit/explosion sound effect via SID engine
ph_ret                          ; already exploding or invulnerable: ignore the hit
        rts                     ; return; hit registered or silently ignored

; cph_overlap: bounding box between the PLAYER and virtual slot X.
; C set = overlap. Uses chDlo/chDhi scratch.
cph_overlap                     ; subroutine: axis-aligned bounding box test; C set = hit
        lda vsXlo,x             ; 16-bit dX = slotX - player_x
        sec                     ; set carry for 16-bit subtraction
        sbc player_x            ; low byte: vsXlo[x] - player_x lo
        sta chDlo               ; store delta X low byte in scratch
        lda vsXhi,x             ; load virtual sprite X high bit (9th bit)
        sbc player_x_hi         ; high byte: vsXhi[x] - player_x_hi - borrow
        sta chDhi               ; store delta X high byte (sign bit for 9-bit X)
        bpl co_xpos             ; result >= 0: dX is positive, skip negation
        lda #0                  ; dX is negative: negate to get |dX| (two's complement)
        sec                     ; set carry for subtraction from zero
        sbc chDlo               ; negate low byte: 0 - chDlo
        sta chDlo               ; store |dX| low byte
        lda #0                  ; reload zero for high byte negation
        sbc chDhi               ; negate high byte: 0 - chDhi - borrow
        sta chDhi               ; store |dX| high byte
co_xpos                         ; |dX| now absolute: compare against hit-box half-width
        lda chDhi               ; check high byte of |dX|
        bne co_no               ; nonzero = |dX| >= 256: far outside hit box, no overlap
        lda chDlo               ; high byte is 0: check low byte of |dX|
        cmp #PHITW              ; compare against player hit-box half-width constant
        bcs co_no               ; |dX| >= PHITW: outside horizontal hit box, no overlap
        lda vsY,x               ; 8-bit |dY|: load virtual sprite Y
        sec                     ; set carry for subtraction
        sbc player_y            ; dY = vsY[x] - player_y
        bpl co_ypos             ; result >= 0: dY is already positive
        eor #$ff                ; dY negative: one's complement (flip all bits)
        clc                     ; clear carry for +1
        adc #1                  ; complete two's complement negation: |dY|
co_ypos                         ; |dY| now absolute: compare against hit-box half-height
        cmp #PHITH              ; compare |dY| against player hit-box half-height constant
        bcs co_no               ; |dY| >= PHITH: outside vertical hit box, no overlap
        sec                     ; overlap: both axes within hit box — set carry = hit detected
        rts                     ; return C set: caller reads a hit
co_no                           ; no overlap detected: clear carry = miss
        clc                     ; clear carry: caller (bcc) knows there was no hit
        rts                     ; return C clear: caller reads a miss

; ---------------------------------------------------------------------
; check_player_hit: only when ALIVE. Test player vs enemy bullets
; (11..14) and enemy bodies (6..10). On hit -> despawn/explode source,
; call player_hit, return (one hit/frame).
; ---------------------------------------------------------------------
check_player_hit                ; subroutine: detect and apply player-vs-enemy collision
        lda playerState         ; check player state
        bne cph_ret             ; only when ALIVE (0)
        ldx #11                 ; (a) enemy bullets: virtual slots 11-14
cph_eb                          ; enemy bullet scan loop: test slots 11..14
        cpx #15                 ; tested all four enemy bullet slots?
        bcs cph_enemies         ; yes: move on to enemy body checks
        lda vsActive,x          ; is bullet slot X active (1=alive, 0=empty)?
        beq cph_eb_next         ; inactive bullet: skip
        jsr cph_overlap         ; test bounding box: player vs this bullet (C set = hit)
        bcc cph_eb_next         ; no overlap: skip
        jsr ue_despawn          ; enemy bullet gone
        jsr player_hit          ; register the hit: lose a life, start explosion state
        rts                     ; one hit per frame maximum; return immediately
cph_eb_next                     ; no hit on this bullet slot: advance to next
        inx                     ; advance to next bullet slot
        jmp cph_eb              ; continue bullet scan loop
cph_enemies                     ; switch to enemy body scan: virtual slots 6-10
        ldx #6                  ; (b) enemy bodies: virtual slots 6-10
cph_en                          ; enemy body scan loop: test slots 6..10
        cpx #11                 ; tested all five enemy/boss slots?
        bcs cph_ret             ; yes: all checks done, no hit this frame
        lda vsActive,x          ; is enemy slot X active?
        beq cph_en_next         ; inactive: skip
        lda vsState,x           ; check enemy state: 0=alive, 1=exploding
        bne cph_en_next         ; already exploding: don't collide with explosion sprite
        jsr cph_overlap         ; test bounding box: player vs this enemy (C set = hit)
        bcc cph_en_next         ; no overlap: skip
        lda bossState           ; are we currently in a boss fight?
        beq cph_en_kamikaze     ; no boss -> explode enemy
        ; boss piece is solid: damage the player, leave the piece
        jsr player_hit          ; boss body hit: hurt player (boss piece stays on screen)
        rts                     ; return; one hit per frame; boss piece untouched
cph_en_kamikaze                 ; kamikaze: explode enemy and hurt player simultaneously
        ; kamikaze: explode enemy + hit player
        lda #1                  ; vsState value 1 = exploding
        sta vsState,x           ; put enemy into explosion state (stops it firing/moving)
        lda #EXPLODE_FRAMES     ; load explosion animation duration constant
        sta vsExplodeTimer,x    ; set explosion countdown for this enemy slot
        lda #1                  ; white
        sta vsColor,x           ; color 1 = white: bright explosion flash
        jsr player_hit          ; also hurt the player from the kamikaze collision
        rts                     ; return; enemy exploding and player hit, one event per frame
cph_en_next                     ; no hit on this enemy slot: advance to next
        inx                     ; advance to next enemy slot
        jmp cph_en              ; continue enemy body scan loop
cph_ret                         ; no hit detected this frame
        rts                     ; return; player unharmed this frame

; ---------------------------------------------------------------------
; clear_actors: park all 15 virtual sprite slots (vsActive=0, vsY=255).
; Called from pu_gameover when entering GS_OVER.
; ---------------------------------------------------------------------
clear_actors                    ; subroutine: deactivate all 15 virtual sprite slots
        ldx #0                  ; start clearing from virtual sprite slot 0
ca_loop cpx #15                 ; cleared all 15 virtual sprite slots?
        bcs ca_done             ; yes: done clearing
        lda #0                  ; prepare inactive flag
        sta vsActive,x          ; mark slot X as inactive (no sprite rendered)
        lda #255                ; Y=255: well below the visible screen (sprites 21 px tall)
        sta vsY,x               ; park sprite Y off-screen so multiplexer won't schedule it
        inx                     ; advance to next slot
        jmp ca_loop             ; loop over all 15 slots
ca_done rts                     ; all 15 slots cleared; mux will produce an empty schedule

; ---------------------------------------------------------------------
; score_insert: place the finished run's score into the top-5 table.
; hiScores = 5 entries x 3-byte BCD (lo,mid,hi), entry 0 = rank 1.
; Strictly-greater wins the slot; a tie ranks below the older equal
; entry. Sets newRank = 0..4 (inserted rank) or $ff (didn't place).
; Clobbers A/X/Y. Main-line only (no IRQ-shared state).
; ---------------------------------------------------------------------
score_insert                    ; subroutine: rank current score into top-5 BCD high-score table
        lda #$ff                ; prime sentinel: $FF = "did not place" until si_insert fires
        sta newRank             ; newRank stays $ff if score beats no entry
        ldy #0                  ; byte offset of entry under test (0,3,6,9,12)
        ldx #0                  ; rank index 0..4
si_find                         ; compare loop: test score against each rank, best first
        lda score+2             ; compare high BCD byte first
        cmp hiScores+2,y        ; score hi vs this rank's hi byte (BCD digits 5-4)
        bcc si_next             ; score < entry -> try the next rank down
        bne si_insert           ; score > entry -> insert at this rank
        lda score+1             ; high bytes equal: compare mid BCD byte (digits 3-2)
        cmp hiScores+1,y        ; score mid vs this rank's mid byte
        bcc si_next             ; score mid < entry mid: score loses this comparison
        bne si_insert           ; score mid > entry mid: insert at this rank
        lda score+0             ; mid bytes equal: compare low BCD byte (digits 1-0)
        cmp hiScores+0,y        ; score lo vs this rank's lo byte
        bcc si_next             ; score lo < entry lo: score loses
        beq si_next             ; full tie -> ranks below the older score
        bne si_insert           ; low byte greater -> insert (BNE always taken: tie handled above)
si_next                         ; score <= this entry: advance to the next lower rank
        iny                     ; advance byte offset: +1 of the 3-byte per-entry step
        iny                     ; advance byte offset: +2
        iny                     ; advance byte offset: now at next 3-byte entry (Y += 3 total)
        inx                     ; advance rank index (0..4)
        cpx #HS_COUNT           ; compared all HS_COUNT (5) ranks?
        bne si_find             ; no: test next rank
        rts                     ; beaten by all 5 -> newRank stays $ff
si_insert                       ; found insertion rank: X = rank index, Y = byte offset
        stx newRank             ; record the achieved rank (0 = top) for title screen highlight
        sty siStop              ; siStop = byte offset of insertion slot (shift loop stops here)
        ; shift lower ranks down one slot: entry[dst] = entry[dst-3],
        ; dst walking 12,9,6,... until it reaches the insertion offset
        ldx #(HS_COUNT-1)*3     ; X = 12: byte offset of rank 4 (last entry); shift walks up
si_shift                        ; shift loop: copy entry at X-3 into X, then X -= 3
        cpx siStop              ; reached the insertion slot?
        beq si_store            ; reached the insertion slot -> stop shifting
        lda hiScores-3+0,x      ; load lo byte of rank above (entry at X-3)
        sta hiScores+0,x        ; copy lo byte down one slot (X is the destination)
        lda hiScores-3+1,x      ; load mid byte of rank above
        sta hiScores+1,x        ; copy mid byte down one slot
        lda hiScores-3+2,x      ; load hi byte of rank above
        sta hiScores+2,x        ; copy hi byte down one slot: entry at X is now a copy of X-3
        dex                     ; X -= 1 (three decrements = move back one 3-byte entry)
        dex                     ; X -= 2
        dex                     ; X -= 3: point at next rank to displace downward
        jmp si_shift            ; continue shifting until reaching the insertion slot
si_store                        ; insertion slot cleared: write current score at byte offset Y
        lda score+0             ; Y still holds the insertion offset
        sta hiScores+0,y        ; store score lo byte (BCD digits 1-0) into rank entry
        lda score+1             ; load mid BCD byte of final score
        sta hiScores+1,y        ; store score mid byte (BCD digits 3-2)
        lda score+2             ; load hi BCD byte of final score
        sta hiScores+2,y        ; store score hi byte (BCD digits 5-4): entry fully written
        rts                     ; score inserted; newRank holds achieved rank (0-4)

; --- clamp player_x to [24,320], player_y to [70,229] ---
clamp_player                    ; subroutine: enforce play-area bounds on player_x and player_y
        ; Y low bound 70
        lda player_y            ; load current Y pixel position
        cmp #70                 ; compare against upper screen boundary (row below HUD)
        bcs cy_hi               ; Y >= 70: OK or too low, check upper limit
        lda #70                 ; Y < 70: would enter HUD area — clamp to minimum Y
        sta player_y            ; enforce minimum Y (keeps ship below the 2-row HUD)
        jmp cx                  ; skip upper-bound check, proceed to X clamp
cy_hi                           ; Y >= low bound: check upper (bottom-screen) bound
        cmp #230                 ; >=230 -> clamp to 229
        bcc cx                  ; Y < 230: in range, proceed to X clamp
        lda #229                ; Y >= 230: clamp to maximum Y (229 = last safe row)
        sta player_y            ; enforce maximum Y
cx                              ; Y clamped: now clamp X
        ; X low bound 24 (only possible when hi==0)
        lda player_x_hi         ; check high bit of 9-bit X position
        bne cx_high             ; hi != 0 means X >= 256: skip low-bound check
        lda player_x            ; hi==0: load X low byte
        cmp #24                 ; compare against left edge (24 pixels from left border)
        bcs cx_done             ; X >= 24: in range
        lda #24                 ; X < 24: clamp to left screen edge
        sta player_x            ; enforce minimum X
        jmp cx_done             ; done
cx_high                         ; player_x_hi >= 1 (X >= 256): check right-edge maximum
        ; hi>=1: clamp to max 320 ($140)
        lda player_x_hi         ; reload X high bit
        cmp #2                  ; hi >= 2 means X >= 512: way past right edge (320=$140)
        bcs cx_max               ; hi>=2 -> over max
        lda player_x             ; hi==1
        cmp #$41                 ; lo>$40 -> over max (320=$140)
        bcc cx_done             ; lo < $41: X = $100+lo <= 320, still in range
cx_max                          ; X exceeds right edge (320): clamp to ($1,$40) = 320
        lda #$40                ; clamp lo byte to $40 (so X = $0140 = 320)
        sta player_x            ; store clamped X low byte
        lda #1                  ; hi byte = 1 (X = $140 = 320: right edge of play area)
        sta player_x_hi         ; store clamped X high bit
cx_done                         ; X and Y both clamped to play area: return
        rts                     ; return; player_x and player_y safe to write to hardware

; --- write player_x/player_y to sprite 0 registers ---
write_player_sprite             ; subroutine: push player_x/player_y to VIC-II sprite 0 registers
        lda player_x            ; load player X low byte (bits 0-7 of 9-bit X)
        sta $d000               ; $D000: VIC-II sprite 0 X position (low 8 bits)
        lda player_y            ; load player Y coordinate
        sta $d001               ; $D001: VIC-II sprite 0 Y position
        sei                     ; disable IRQs: read-modify-write of $D010 must be atomic
        lda $d010               ; $D010: MSB X bits for all 8 hardware sprites (1 bit each)
        and #%11111110           ; clear sprite 0 MSB
        ldx player_x_hi         ; load player X high bit (0 or 1)
        beq wps_done            ; if zero (X < 256), leave bit 0 clear
        ora #%00000001          ; X >= 256: set bit 0 so sprite 0 appears past the 256px boundary
wps_done                        ; $D010 updated; cli follows (known quirk: callers work around it)
        sta $d010               ; $D010: write updated MSB register (9-bit X for all sprites)
        cli                     ; re-enable IRQs now that $D010 update is complete
        rts                     ; return; sprite 0 hardware registers updated

; park hardware sprites 1-7 below the screen (Y=$f8) so unused ones don't show stale data
park_mux_sprites                ; subroutine: park hw sprites 1-7 off-screen each PLAY frame
        lda #$f8                ; Y=$F8=248: below visible bottom (~230); sprite 21 px tall so safe
        sta $d003               ; $D003: hardware sprite 1 Y position — park off-screen
        sta $d005               ; $D005: hardware sprite 2 Y position — park off-screen
        sta $d007               ; $D007: hardware sprite 3 Y position — park off-screen
        sta $d009               ; $D009: hardware sprite 4 Y position — park off-screen
        sta $d00b               ; $D00B: hardware sprite 5 Y position — park off-screen
        sta $d00d               ; $D00D: hardware sprite 6 Y position — park off-screen
        sta $d00f               ; $D00F: hardware sprite 7 Y position — park off-screen
        rts                     ; return; all mux hw sprite slots parked off-screen

; =====================================================================
;  SORT_SPRITES: insertion-sort sortIdx[0..14] ascending by vsY[sortIdx[i]]
;  Outer index kept in ss_x (memory) to avoid X clobbering across inner loop.
; =====================================================================
sort_sprites                    ; subroutine: Y-sort 15 virtual sprite slots for multiplexer
        ; --- flicker fairness: rotate sortIdx left by 1 each frame before
        ;     sorting. The insertion sort below is STABLE (stops on ==), so
        ;     this only permutes the order of EQUAL-Y entries -> on a band that
        ;     overflows the 7 mux-able hw slots, a different entry is the one
        ;     build_schedule drops each frame. Net: same-scanline overflow
        ;     blinks fairly instead of dropping the same sprite every frame. ---
        lda sortIdx             ; A = sortIdx[0]: the slot we're about to rotate off the front
        sta tmpSlot             ; stash it; it will become the new sortIdx[14]
        ldx #0                  ; X = 0: start of the shift-down loop
fk_rot                          ; rotation loop: shift sortIdx[0..13] left by one position
        lda sortIdx+1,x         ; sortIdx[i] = sortIdx[i+1]
        sta sortIdx,x           ; shift entry left: every element moves one position toward front
        inx                     ; i++
        cpx #14                 ; stop after writing sortIdx[13] (we never read past sortIdx[14])
        bne fk_rot              ; loop for indices 0..13
        lda tmpSlot             ; recover the old sortIdx[0]
        sta sortIdx+14          ; old [0] -> [14]: rotation complete; tie order promoted by one
        lda #1                  ; insertion sort starts at element 1 (element 0 is trivially sorted)
        sta ss_x                ; store outer loop index in memory (X register is used by inner loop)
ss_outer                        ; outer loop: i = 1..14 (elements to insert into sorted portion)
        lda ss_x                ; load outer loop index (i)
        cmp #15                 ; have we processed all 15 virtual sprite slots?
        bcs ss_done             ; yes: sort complete
        ldx ss_x                ; X = i (index into sortIdx)
        lda sortIdx,x           ; load the virtual slot number at position i
        sta tmpSlot             ; key slot: save the slot being inserted into the sorted portion
        tay                     ; Y = key slot number (index into vsY array)
        lda vsY,y               ; load vsY[key slot]: the Y coordinate of the key element
        sta sortKey             ; key value
        lda ss_x                ; load outer index
        sta sortJ               ; j = outer index: inner loop starts here and shifts leftward
ss_inner                        ; inner loop: shift sorted elements right while they exceed key Y
        lda sortJ               ; load inner index j
        beq ss_place            ; j==0 -> place
        tax                     ; X = j
        dex                     ; j-1
        lda sortIdx,x           ; slot at j-1
        tay                     ; Y = slot number at position j-1
        lda vsY,y               ; vsY[sortIdx[j-1]]
        cmp sortKey             ; compare left-neighbour Y against key Y
        bcc ss_place            ; vsY[j-1] < key -> place here
        beq ss_place            ; vsY[j-1] == key: stable sort, don't swap equals, place here
        ; sortIdx[j] = sortIdx[j-1]
        lda sortIdx,x           ; value at j-1: neighbour is larger, shift it right to make room
        ldy sortJ               ; Y = j (destination index)
        sta sortIdx,y           ; sortIdx[j] = sortIdx[j-1]: shift element right
        dec sortJ               ; j--: continue shifting leftward
        jmp ss_inner            ; keep shifting until correct position found
ss_place                        ; insertion position found at sortJ: write key slot there
        ldx sortJ               ; X = j: the insertion position found by inner loop
        lda tmpSlot             ; load the key slot that was being inserted
        sta sortIdx,x           ; place key slot at its correct sorted position
        inc ss_x                ; advance outer index to next unsorted element
        jmp ss_outer            ; process next element
ss_done                         ; all 15 slots sorted ascending by vsY: mux reads top-to-bottom
        rts                     ; return; sortIdx[0..14] ordered for multiplexer

; =====================================================================
;  BUILD_SCHEDULE: emit active sprites from sortIdx (Y order) into the
;  BACK schedule buffer, set schCount, swap schFront.
;  Double-buffered: schFront (read by mux_irq) and schBack (written here)
;  alternate each frame so the IRQ always reads a complete, consistent list.
;  schY/schXlo/schXhi/schColor/schExpand are parallel arrays; each entry
;  corresponds to one active virtual sprite in ascending Y order for mux.
; =====================================================================
build_schedule                  ; entry: build back schedule from Y-sorted virtual-sprite list
        lda schFront            ; load current front buffer index (0 or 1)
        eor #1                  ; toggle: back = 1-front (the buffer safe to write this frame)
        sta schBack             ; schBack = index of the buffer we may freely write this frame
        ; write index -> schBackBase (base = 0 or 15)
        ldx #0                  ; assume back==0: schedule arrays start at offset 0
        lda schBack             ; reload back index to decide which half of the arrays to use
        beq bs_base0            ; back==0: base offset stays 0, skip adjustment
        ldx #15                 ; back==1: base offset = 15 (second half of 30-entry arrays)
bs_base0                        ; X = correct base offset (0 or 15) for this frame's back buffer
        stx schBackBase         ; schBackBase = write pointer into back-buffer schedule arrays
        stx bsBase              ; bsBase = starting write pointer; used below to count emits
        ldy #0                  ; sortIdx position 0..14
bs_loop                         ; per-sprite: walk Y-sorted virtual sprite list from top to bottom
        cpy #15                 ; processed all 15 sorted virtual sprite slots?
        bcs bs_end              ; yes: schedule is complete for this frame
        lda sortIdx,y           ; load virtual slot number at sorted position Y (top-to-bottom)
        sta tmpSlot             ; stash slot number; Y register will be reused for array indexing
        sty sortJ               ; save sortIdx position so Y can be restored after the guard
        ldx tmpSlot             ; X = virtual slot index (into vsActive/vsY/vsXlo/etc.)
        lda vsActive,x          ; is this virtual sprite slot active (1=yes, 0=empty)?
        beq bs_skip             ; inactive slot: don't add to schedule
        ; --- capacity guard: the round-robin mux reuses each hw sprite 7
        ;     emit-slots later. Don't emit if the sprite emitted 7 ago is
        ;     still on screen (Y gap < SPRSPAN); that would overwrite a
        ;     visible sprite. Cleanly DROP the overflow instead. Once >7
        ;     active fall in one SPRSPAN-line band, the surplus is skipped; the
        ;     per-frame sortIdx rotation cycles which one, so it blinks. ---
        lda schBackBase         ; current write pointer (= base + entries emitted so far)
        sec                     ; set carry for subtraction
        sbc bsBase              ; A = number of entries emitted so far this frame
        cmp #7                  ; have we emitted a full hw round-robin cycle (hw sprites 1-7)?
        bcc bs_emit             ; <7 emitted -> a hw slot is free, safe to emit this sprite
        lda schBackBase         ; >=7 emitted: locate the entry from 7 slots ago (shares our hw sprite)
        sec                     ; set carry for subtraction
        sbc #7                  ; index = schBackBase - 7 (entry that last used this hw slot)
        tay                     ; Y = index of entry emitted 7 ago
        lda vsY,x               ; thisY (>= schY[7ago], Y-ascending)
        sec                     ; set carry for subtraction
        sbc schY,y              ; gap = thisY - Y of the prior user of this same hw slot
        cmp #SPRSPAN            ; gap >= SPRSPAN means old sprite has finished drawing, hw slot is free
        bcc bs_skip             ; gap too small -> hw still busy -> DROP
bs_emit                         ; safe to emit: no hw conflict; copy sprite fields to back schedule
        ; src slot = X (tmpSlot); dst = schBackBase
        ldy schBackBase         ; Y = destination index in back-buffer schedule arrays
        lda vsY,x               ; load virtual sprite Y coordinate
        sta schY,y              ; schY[dst] = vsY[slot] (Y position for mux to program $D001 etc.)
        lda vsXlo,x             ; load virtual sprite X position low byte
        sta schXlo,y            ; schXlo[dst] = vsXlo[slot] (low 8 bits of screen X)
        lda vsXhi,x             ; load virtual sprite X high bit (9th bit, 0 or 1)
        sta schXhi,y            ; schXhi[dst] = vsXhi[slot] (drives $D010 MSB register)
        lda vsColor,x           ; load virtual sprite color index (0-15)
        sta schColor,y          ; schColor[dst] = vsColor[slot] (mux writes to $D027-$D02E)
        lda vsExpand,x          ; load X-expand flag (1=double-wide sprite; charge beam uses 1)
        sta schExpand,y         ; schExpand[dst] = vsExpand[slot]; mux programs $D01D for wide beam
        inc schBackBase         ; advance write pointer to next schedule entry
bs_skip                         ; rejoin here for inactive slots and overflow-dropped sprites
        ldy sortJ               ; restore sortIdx position counter
        iny                     ; advance to next sorted virtual sprite
        jmp bs_loop             ; loop back to process remaining sprites
bs_end                          ; all 15 virtual sprite slots have been walked
        ; count = schBackBase - base
        lda schBackBase         ; final write pointer (= base + number of entries emitted)
        ldx schBack             ; which buffer was the back this frame?
        beq bs_cnt0             ; back==0: count = schBackBase directly (base was 0)
        sec                     ; back==1: must subtract base offset 15 to get true count
        sbc #15                 ; count = schBackBase - 15 (active entries in this schedule)
bs_cnt0                         ; A = number of active sprite entries emitted into back buffer
        ldx schBack             ; reload back buffer index (A may have changed after SBC above)
        sta schCount,x          ; schCount[back] = entry count; mux_irq reads this next frame
        ; swap front
        lda schBack             ; load back buffer index
        sta schFront            ; promote back to front: mux_irq will read this list next frame
        rts                     ; schedule built and double-buffer swap complete; return

; ---------------------------------------------------------------------
; spawn_enemies: countdown; on 0, spawn one enemy into a free slot 6..10
; from the wave tables, then reset the timer.
; ---------------------------------------------------------------------
spawn_enemies                   ; entry: decrement spawn timer; when zero spawn one enemy from wave table
        lda bossState           ; load boss-active flag (0=inactive, non-zero=boss present)
        beq se_go               ; boss inactive: proceed with enemy spawning
        rts                     ; boss is live: suppress enemies while boss occupies slots 6-10
se_go                           ; boss not active: run the spawn countdown
        dec spawnTimer          ; count down between-spawn interval
        beq se_fire             ; timer expired: time to spawn a new enemy
        rts                     ; not yet time; return early
se_fire                         ; timer hit zero: find a free slot and spawn next wave entry
        ldx #6                  ; find free enemy slot
se_find                         ; linear search through enemy virtual-sprite slots 6..10
        cpx #11                 ; past end of enemy slot range (6-10)?
        bcs se_reset            ; none free -> just reset timer
        lda vsActive,x          ; is this virtual sprite slot unoccupied?
        beq se_spawn            ; zero = free: spawn here
        inx                     ; slot in use: try next
        jmp se_find             ; continue linear search
se_spawn                        ; X = free slot found; Y = current spawnIndex (set just before branch)
        ldy spawnIndex          ; Y = index into wave descriptor tables (waveY / wavePattern)
        lda #$54                ; X = 340 ($154): lo=$54, hi=1 (right edge)
        sta vsXlo,x             ; store X low byte: enemy enters just off the right edge of screen
        lda #1                  ; X high byte = 1 (340 = $0154, requires 9 bits)
        sta vsXhi,x             ; store X high byte (340 > 255; hi=1 sets the $D010 bit for this slot)
        lda waveY,y             ; fetch this wave entry's Y spawn row
        sta vsY,x               ; set sprite Y position
        sta vsBaseY,x           ; also save as base Y (sine-wave pattern oscillates around this row)
        lda wavePattern,y       ; fetch movement pattern: 0=straight, 1=sine, 2=zigzag
        sta vsPattern,x         ; store pattern in slot for update_enemies to apply each frame
        lda #0                  ; zero for both phase and state fields
        sta vsPhase,x           ; reset sine/zigzag phase counter to 0 for a fresh oscillation start
        sta vsState,x           ; state 0 = alive (non-zero = exploding animation active)
        lda #ENEMY_COLOR        ; load enemy sprite color constant
        sta vsColor,x           ; set enemy sprite color (red)
        lda #1                  ; active flag = 1; also initial zigzag velocity = +1 (downward)
        sta vsActive,x          ; mark slot active (visible and updated each frame)
        sta vsVY,x              ; default zigzag velocity = +1
        iny                     ; advance wave index (wrap at waveN)
        cpy #waveN              ; reached end of wave descriptor table?
        bcc se_idxok            ; no: keep incremented index
        ldy #0                  ; yes: wrap back to start (cyclic enemy wave sequence)
se_idxok                        ; Y = updated wave index (possibly wrapped to 0)
        sty spawnIndex          ; save updated index for the next spawn call
se_reset                        ; reached here after spawn or if all slots were occupied
        lda #SPAWN_INTERVAL     ; reload spawn countdown constant
        sta spawnTimer          ; reset timer for the next wave spawn cycle
        rts                     ; done

; ---------------------------------------------------------------------
; update_enemies: slots 6..10. Exploding -> count down & despawn.
; Alive -> move left by ENEMY_SPEED, despawn off left edge. Vertical
; movement by pattern is added in Task 2 (ue_vert is straight/no-op here).
; ---------------------------------------------------------------------
update_enemies                  ; entry: run one frame of movement or explosion for all enemy slots
        lda bossState           ; check if boss is active
        beq ue_go               ; boss inactive: process enemies normally
        rts                     ; boss active: skip entirely (slots 6-10 belong to boss)
ue_go                           ; boss not active: iterate over enemy slots 6..10
        ldx #6                  ; start at first enemy slot (6)
ue_loop                         ; per-slot loop header: slots 6 through 10
        cpx #11                 ; processed all 5 enemy slots (6-10)?
        bcc ue_notdone          ; no: keep processing
        jmp ue_done             ; yes: all slots handled; exit
ue_notdone                      ; slot X is within the enemy range 6..10
        lda vsActive,x          ; is this slot in use?
        bne ue_isactive         ; non-zero = active: process it
        jmp ue_next             ; inactive: skip to next slot
ue_isactive                     ; slot is active: check whether alive or in explosion animation
        lda vsState,x           ; check slot state: 0=alive, non-zero=exploding
        beq ue_alive            ; state 0: alive; proceed to horizontal movement
        ; exploding: count down, despawn at 0
        dec vsExplodeTimer,x    ; decrement explosion animation frame counter
        bne ue_next             ; still counting: keep the white explosion sprite on screen
        jsr ue_despawn          ; counter reached 0: free the slot and park sprite off-screen
        jmp ue_next             ; advance to next slot
ue_alive                        ; enemy is alive: move left and apply vertical movement pattern
        ; X -= ENEMY_SPEED (16-bit, move left)
        lda vsXlo,x             ; load 16-bit X position low byte
        sec                     ; set carry so SBC borrows correctly for 16-bit subtract
        sbc #ENEMY_SPEED        ; subtract horizontal speed: moves enemy leftward each frame
        sta vsXlo,x             ; store updated low byte
        lda vsXhi,x             ; load X high byte
        sbc #0                  ; propagate borrow from low byte into high byte
        sta vsXhi,x             ; store updated high byte (completes 16-bit X decrement)
        ; off-left despawn: hi==0 and lo<20, or hi==$ff (underflow)
        lda vsXhi,x             ; re-read high byte to test despawn conditions
        bne ue_xhi              ; non-zero: could be underflow ($ff); check separately
        lda vsXlo,x             ; hi==0: X is in range 0-255; test left boundary
        cmp #20                 ; is X low byte < 20 (past left edge of playfield)?
        bcs ue_vert             ; X >= 20: still on screen, proceed to vertical movement
        jsr ue_despawn          ; X < 20 with hi=0: scrolled off left edge, despawn
        jmp ue_next             ; advance to next slot
ue_xhi                          ; hi byte is non-zero: distinguish underflow ($ff) from valid right X (1)
        cmp #$ff                ; A = vsXhi
        bne ue_vert             ; hi==1 -> on right of screen (X in 256-340): do vertical movement
        jsr ue_despawn          ; hi==$ff: X underflowed below zero, enemy exited left edge
        jmp ue_next             ; advance to next slot
ue_vert                         ; enemy is on-screen: dispatch vertical movement by pattern type
        lda vsPattern,x         ; load this enemy's movement pattern
        beq ue_next             ; 0 = straight -> no vertical
        cmp #1                  ; pattern 1 = sine wave?
        beq ue_sine             ; yes: branch to sine-table oscillation code
        ; --- pattern 2: zigzag (Y += vsVY, bounce [54,210]) ---
        lda vsY,x               ; load current sprite Y position
        clc                     ; clear carry for addition
        adc vsVY,x              ; Y += vsVY: +1 moves down, $FF (two's-compl -1) moves up
        sta vsY,x               ; store updated Y
        cmp #70                 ; did Y go below top boundary (Y < 70)?
        bcs ue_zz_top           ; Y >= 70: not at top; check bottom boundary
        lda #70                 ; clamp: force Y to top boundary of play area
        sta vsY,x               ; store clamped Y
        jsr ue_negVY            ; reverse velocity: was moving up, will now move down
        jmp ue_next             ; advance to next slot
ue_zz_top                       ; Y was >= 70 after the add: now check the bottom boundary
        cmp #211                ; did Y exceed bottom boundary (Y >= 211)?
        bcc ue_next             ; Y < 211: within play area, no bounce needed
        lda #210                ; clamp: force Y to bottom boundary of play area
        sta vsY,x               ; store clamped Y
        jsr ue_negVY            ; reverse velocity: was moving down, will now move up
        jmp ue_next             ; advance to next slot
ue_sine                         ; pattern 1: smooth 64-step sine oscillation around vsBaseY
        ; phase = (phase+1)&63; Y = vsBaseY + sineTable[phase]
        lda vsPhase,x           ; load current sine phase counter (0-63)
        clc                     ; clear carry for addition
        adc #1                  ; increment phase by 1 each frame
        and #63                 ; wrap to 0..63: keeps index within the 64-entry table
        sta vsPhase,x           ; save updated phase for next frame
        tay                     ; transfer phase to Y register for table lookup
        lda sineTable,y         ; fetch signed displacement (centered around 0)
        clc                     ; clear carry for addition
        adc vsBaseY,x           ; add to spawn row: Y = baseY + sin(phase)
        sta vsY,x               ; store resulting screen Y (enemy oscillates above and below baseY)
        jmp ue_next             ; advance to next slot
ue_next                         ; bottom of per-slot loop
        inx                     ; advance to next enemy slot (6->7->...->10)
        jmp ue_loop             ; loop back to process remaining slots
ue_done                         ; all five enemy slots processed this frame
        rts                     ; return to caller

; despawn enemy in X: inactive + park Y off-screen
ue_despawn                      ; free slot X: mark inactive and hide sprite below the visible area
        lda #0                  ; inactive flag value (zero = slot free for next spawn)
        sta vsActive,x          ; mark slot inactive so it can be reused by spawn_enemies
        lda #255                ; Y=255: below visible screen bottom (sprite body is 21 px tall)
        sta vsY,x               ; park sprite Y at 255 so sort/mux ignores and hides it
        rts                     ; return (caller typically follows with jmp ue_next)

; negate vsVY[x] (zigzag bounce)
ue_negVY                        ; reverse zigzag vertical velocity for slot X (wall bounce)
        lda #0                  ; set up for two's-complement negation: compute 0 - vsVY
        sec                     ; set carry so SBC performs a correct negation
        sbc vsVY,x              ; A = 0 - vsVY[x]: flips +1 -> $FF (-1) and $FF -> +1
        sta vsVY,x              ; store reversed velocity back into slot
        rts                     ; return

; ---------------------------------------------------------------------
; enemy_fire: countdown; on 0, fire a straight-left bullet from a live
; enemy (cycling via enemyFireIndex 6..10) into a free enemy-bullet slot
; (11..14). X = enemy-bullet slot, Y = enemy slot.
; ---------------------------------------------------------------------
enemy_fire                      ; entry: decrement fire timer; when zero pick a live enemy and fire
        lda bossState           ; check if boss is active
        beq ef_go               ; boss inactive: normal enemies may fire
        rts                     ; boss active: suppress enemy fire (boss_fire handles boss bullets)
ef_go                           ; boss not active: run the enemy fire countdown
        dec enemyFireTimer      ; count down between-shots interval
        beq ef_fire             ; timer expired: fire a bullet now
        rts                     ; not yet time; return
ef_fire                         ; timer hit zero: acquire a free bullet slot, then find a firing enemy
        ldx #11                 ; find free enemy-bullet slot 11..14
ef_findbul                      ; linear search through bullet slots 11..14
        cpx #15                 ; past end of bullet slot range?
        bcs ef_reset            ; none free
        lda vsActive,x          ; is this bullet slot vacant?
        beq ef_havebul          ; zero = free: use this slot
        inx                     ; occupied: try next slot
        jmp ef_findbul          ; continue scanning for a free bullet slot
ef_havebul                      ; X = free bullet slot; now find a live enemy to fire from
        ; scan up to 5 enemies starting at enemyFireIndex for a live one
        ldy enemyFireIndex      ; Y = next enemy slot to try (cycles 6-10 for fair distribution)
        lda #5                  ; try at most 5 enemies (all slots in the range)
        sta ef_scan             ; ef_scan = remaining scan attempts before giving up
ef_findenemy                    ; per-enemy scan: look for a live, non-exploding enemy at slot Y
        cpy #11                 ; wrap y into 6..10
        bcc ef_yok              ; Y is still in valid enemy range
        ldy #6                  ; past slot 10: wrap back to first enemy slot
ef_yok                          ; Y is in valid enemy slot range 6..10
        lda vsActive,y          ; is this enemy slot active?
        beq ef_skipenemy        ; no: slot is empty; skip
        lda vsState,y           ; is this enemy alive (state==0) or exploding (non-zero)?
        beq ef_spawn            ; live enemy at y
ef_skipenemy                    ; enemy at Y is inactive or exploding: try the next slot
        iny                     ; advance to next enemy slot
        dec ef_scan             ; decrement remaining scan counter
        bne ef_findenemy        ; still have tries left: keep scanning
        jmp ef_reset            ; no live enemy
ef_spawn                        ; found a live enemy at slot Y; bullet slot is X; spawn the bullet
        lda vsXlo,y             ; spawn enemy bullet at enemy position
        sta vsXlo,x             ; bullet X low byte = firing enemy X low byte
        lda vsXhi,y             ; load enemy X high byte
        sta vsXhi,x             ; bullet X high byte = enemy X high byte (same 16-bit position)
        lda vsY,y               ; load enemy Y position
        sta vsY,x               ; bullet Y = enemy Y (fired from enemy's vertical center)
        lda #EBULLET_COLOR      ; load enemy bullet color constant
        sta vsColor,x           ; set bullet color (cyan: distinguishes enemy fire from player bullets)
        lda #1                  ; active flag value
        sta vsActive,x          ; activate bullet slot (update_enemy_bullets moves it left each frame)
        iny                     ; advance fire index past this enemy (wrap)
        cpy #11                 ; past slot 10?
        bcc ef_idxok            ; no wrap needed
        ldy #6                  ; wrap fire index back to slot 6
ef_idxok                        ; Y = updated enemyFireIndex (possibly wrapped)
        sty enemyFireIndex      ; save updated cycling index for next fire call
ef_reset                        ; reached here after spawn or if no bullet/enemy slot was available
        lda #ENEMY_FIRE_INTERVAL ; reload fire-rate constant
        sta enemyFireTimer      ; reset timer for the next fire event
        rts                     ; done
; place the 5 boss pieces (slots 6..10) at the anchor: same X, Y spread by bossOffY.
; color = white while bossFlash>0, else BOSS_COLOR.
; NOTE: the boss reuses enemy virtual-sprite slots 6-10 for its 5 body pieces.
; bossState is non-zero whenever the boss is alive, which causes update_enemies and
; enemy_fire to return immediately so there is no conflict over these shared slots.
boss_place_pieces               ; entry: write all 5 boss body pieces into virtual slots 6-10
        ldx #0                  ; piece index 0..4 (5 body segments)
bpp_loop                        ; top of per-piece placement loop
        cpx #5                  ; all 5 pieces placed?
        bcs bpp_done            ; X >= 5: done with all pieces
        txa                     ; A = piece index (0-4)
        clc                     ; clear carry for following addition
        adc #6                  ; A = virtual sprite slot number (piece 0->slot 6 .. piece 4->slot 10)
        tay                     ; Y = slot index into vs* arrays
        lda bossXlo             ; load boss cluster X low byte
        sta vsXlo,y             ; all 5 pieces share the same X lo byte (cluster moves as one)
        lda bossXhi             ; load boss cluster X high byte
        sta vsXhi,y             ; all 5 pieces share the same X hi byte
        lda bossY               ; boss anchor Y (updated each frame by boss_bob)
        clc                     ; clear carry for signed Y-offset addition
        adc bossOffY,x          ; signed Y offset; bossOffY[0..4] spreads pieces vertically around anchor
        sta vsY,y               ; store individual piece Y position into virtual sprite slot
        lda bossFlash           ; hit-flash counter: non-zero = currently in a flash cycle
        beq bpp_normalcol       ; zero: flash not active, use normal boss color
        lda #1                  ; white (flash); VIC-II color 1 = white (hit-damage indicator)
        jmp bpp_setcol          ; skip normal-color load
bpp_normalcol                   ; flash counter is zero: use normal palette
        lda #BOSS_COLOR         ; BOSS_COLOR = purple (color 4)
bpp_setcol                      ; common store: A holds the chosen color index
        sta vsColor,y           ; write color to this piece's virtual sprite slot
        lda #1                  ; active flag value = 1
        sta vsActive,y          ; ensure piece slot is marked active (visible to multiplexer)
        lda #0                  ; state 0 = alive
        sta vsState,y           ; state 0 = alive (not in explosion animation)
        inx                     ; advance to next piece index
        jmp bpp_loop            ; loop until all 5 pieces are placed
bpp_done                        ; all 5 pieces placed; fall through to rts
        rts                     ; return to caller

; bob the anchor Y around bossYCenter via the sine table
boss_bob                        ; advance boss bob phase and recompute bossY
        inc bossPhase           ; advance bob phase counter by 1 each frame
        lda bossPhase           ; reload updated phase (inc doesn't leave result in A)
        and #63                 ; wrap to 0..63: mod-64 keeps index within sine table bounds
        sta bossPhase           ; store wrapped phase (63 entries -> seamless cyclic motion)
        tay                     ; Y = phase index into sineTable
        lda sineTable,y         ; fetch signed 8-bit displacement (~-16..+16 pixels)
        clc                     ; clear carry for sine+center addition
        adc bossYCenter         ; bossY = bossYCenter + sin(phase): smooth vertical oscillation
        sta bossY               ; update boss anchor Y; boss_place_pieces distributes pieces around it
        rts                     ; return; bossY now holds this frame's oscillated Y position

; boss_fire: on timer, spawn straight-left bullets into free slots 11..14
; from successive boss-piece Y positions (a vertical volley).
boss_fire                       ; fire timer countdown; spawn a volley when timer expires
        dec bossFireTimer       ; count down between volleys (BOSS_FIRE_INTERVAL frames between salvos)
        beq bf_fire             ; timer hit zero: launch a volley now
        rts                     ; not yet time; return without firing
bf_fire                         ; timer expired: fill free bullet slots from boss-piece positions
        ldx #11                 ; enemy-bullet slot; start scanning bullet slots from 11
        ldy #6                  ; boss piece slot; start from first boss-piece slot (6)
bf_loop                         ; iterate over enemy-bullet slots 11..14
        cpx #15                 ; all four bullet slots (11-14) checked?
        bcs bf_done             ; X >= 15: volley dispatch complete
        lda vsActive,x          ; is this bullet slot occupied?
        bne bf_nextbul          ; non-zero: slot in use, skip to next bullet slot
        lda vsXlo,y             ; spawn from piece y; bullet inherits boss-piece X lo byte
        sta vsXlo,x             ; write X lo to bullet slot (fires from same X as boss)
        lda vsXhi,y             ; load boss-piece X hi byte
        sta vsXhi,x             ; write X hi to bullet slot
        lda vsY,y               ; load this piece's Y (each piece at different Y -> vertical spread)
        sta vsY,x               ; bullet Y = this piece's Y (creates a vertical fan of bullets)
        lda #EBULLET_COLOR      ; load enemy bullet color constant
        sta vsColor,x           ; set bullet color (e.g. cyan)
        lda #1                  ; active flag value
        sta vsActive,x          ; activate bullet slot (update_enemy_bullets will move it left)
        iny                     ; next piece (wrap 6..10); advance to next boss-piece slot
        cpy #11                 ; past slot 10?
        bcc bf_nextbul          ; Y still in range 6..10: no wrap needed
        ldy #6                  ; wrap piece index back to slot 6 (cycle through all 5 pieces)
bf_nextbul                      ; advance to the next enemy-bullet slot
        inx                     ; X++ (advance through slots 11->12->13->14)
        jmp bf_loop             ; continue filling remaining bullet slots in the volley
bf_done                         ; all bullet slots checked; reload fire timer for next salvo
        lda #BOSS_FIRE_INTERVAL ; load volley interval constant (e.g. 50 frames)
        sta bossFireTimer       ; reload timer; next volley fires in BOSS_FIRE_INTERVAL frames
        rts                     ; return to boss_update caller

; boss_take_hit: despawn the player bullet (slot X), drain HP, flash;
; HP 0 -> dying. Only counts while fighting.
boss_take_hit                   ; entry when bullet X hits a boss piece: despawn bullet, then drain HP
        lda #0                  ; zero = inactive
        sta vsActive,x          ; deactivate the player bullet that struck the boss
        lda #255                ; Y=255 = off-screen sentinel
        sta vsY,x               ; park bullet Y at 255 (off screen; multiplexer sorts it last)
        ; fall through: drain HP without another despawn
boss_drain_hp                   ; alternate entry point: beam hits call here directly (bullet not re-despawned)
        lda bossState           ; read current boss state
        cmp #BS_FIGHT           ; is boss currently in FIGHT state (value 2)?
        bne bth_ret             ; not in FIGHT (still ENTER or already DYING): ignore this hit
        dec bossHP              ; shared HP pool: any of the 5 pieces taking a hit drains this counter
        lda #BOSS_FLASH_FRAMES  ; load flash duration constant (e.g. 4 frames)
        sta bossFlash           ; start hit-flash timer; pieces show white while bossFlash > 0
        lda bossHP              ; check remaining HP after decrement
        bne bth_ret             ; HP > 0: boss damaged but survives this hit; return
        lda #BS_DYING           ; HP exhausted: transition boss to death animation state
        sta bossState           ; write BS_DYING (value 3) to state machine variable
        lda #BOSS_DEATH_FRAMES  ; load death animation duration constant (e.g. 30 frames)
        sta bossDeathTimer      ; set explosion animation countdown
bth_ret                         ; common return for all take-hit and drain-hp paths
        rts                     ; return to check_hits or boss_drain_hp caller

; boss_spawn: initialise an entering boss
boss_spawn                      ; entry: initialise all boss variables and put boss into ENTER state
        lda #BS_ENTER           ; state = ENTER (value 1): boss slides in from right edge
        sta bossState           ; write initial boss state
        lda #BOSS_HP            ; load full hit-point constant (e.g. 5)
        sta bossHP              ; initialise shared HP pool (all pieces share this counter)
        lda #$54                ; X = 340 (hi=1, lo=$54): start just off right edge of screen
        sta bossXlo             ; 16-bit X lo byte ($54 = 84; hi*256+lo = 1*256+84 = 340)
        lda #1                  ; X hi byte = 1 (340 > 255, needs hi=1)
        sta bossXhi             ; 16-bit X hi byte; boss begins at X=340, past right visible edge
        lda #130                ; initial Y = 130: vertical centre of play area
        sta bossY               ; set boss anchor Y (all pieces distributed around this)
        sta bossYCenter         ; bob center locked to 130; boss_bob oscillates bossY around this
        lda #0                  ; zero for phase and flash reset
        sta bossPhase           ; start sine bob phase at 0 (beginning of oscillation cycle)
        sta bossFlash           ; no hit-flash active at spawn (counter = 0)
        lda #BOSS_FIRE_INTERVAL ; load fire interval constant
        sta bossFireTimer       ; arm the first fire-volley timer
        jsr sfx_boss            ; trigger boss-entry SID sound effect (rising pulse sting on V3)
        jsr boss_place_pieces   ; immediately place all 5 pieces so they appear on screen at spawn
        rts                     ; return to boss_update caller; boss is now in ENTER state

; boss_update: state machine, called each frame from main_loop.
boss_update                     ; per-frame boss FSM entry: inactive check or state dispatch
        lda bossState           ; load current boss state (0=INACTIVE, 1=ENTER, 2=FIGHT, 3=DYING)
        bne bu_active           ; non-zero: boss is active; dispatch to appropriate handler
        ; inactive: trigger after enough kills
        lda killCount           ; kills accumulated since last boss defeat (or game start)
        cmp #BOSS_KILL_THRESHOLD ; reached the threshold to spawn the next boss?
        bcc bu_ret              ; not enough kills yet: remain inactive this frame
        jsr boss_spawn          ; threshold reached: spawn and initialise the boss
bu_ret                          ; common return for the inactive (no-boss) path
        rts                     ; return to main_loop
bu_active                       ; boss is alive: dispatch on current state (still in A from lda bossState)
        cmp #BS_ENTER           ; is boss in ENTER (slide-in) state (value 1)?
        beq bu_enter            ; yes: handle leftward slide-in
        cmp #BS_FIGHT           ; is boss in FIGHT (active combat) state (value 2)?
        beq bu_fight            ; yes: bob, fire, and track flash countdown
        jmp bu_dying            ; BS_DYING; value must be BS_DYING (3): run death animation
bu_enter                        ; ENTER state: slide boss leftward until it reaches fight position
        lda bossXlo             ; slide left (hi stays 1 from 340->300); load X lo byte
        sec                     ; set carry for 16-bit subtraction
        sbc #BOSS_ENTER_SPEED   ; subtract entry speed (e.g. 2 px/frame): moves boss leftward
        sta bossXlo             ; store updated X lo byte
        lda bossXhi             ; load X hi byte for borrow propagation
        sbc #0                  ; propagate any borrow from lo subtraction into hi byte
        sta bossXhi             ; store updated X hi byte (stays 1 until boss passes X = 256)
        lda bossXlo             ; reload X lo byte for arrival test
        cmp #$2d                ; lo < $2d -> reached fight X (300=$12c, lo byte = $2c)
        bcs bu_enter_place      ; lo >= $2d: not yet at fight X, keep sliding this frame
        lda #BS_FIGHT           ; arrived at fight X: transition to FIGHT state
        sta bossState           ; write BS_FIGHT (value 2) to state machine variable
bu_enter_place                  ; place pieces each entry frame (or immediately on state change)
        jsr boss_place_pieces   ; update all 5 piece positions to reflect current bossX/bossY
        rts                     ; return to main_loop

bu_fight                        ; FIGHT state: bob + fire + flash countdown each frame
        jsr boss_bob            ; advance sine phase and update bossY (smooth vertical oscillation)
        jsr boss_fire           ; decrement fire timer; spawn bullet volley when timer expires
        lda bossFlash           ; check hit-flash countdown
        beq bu_fight_place      ; zero: no flash pending, skip decrement
        dec bossFlash           ; count down flash duration (pieces show white until this reaches 0)
bu_fight_place                  ; refresh piece colors and positions with latest bob Y
        jsr boss_place_pieces   ; update all 5 pieces: positions + color (white if bossFlash > 0)
        rts                     ; return to main_loop

bu_dying                        ; DYING state: force-flash pieces and count down death animation
        dec bossDeathTimer      ; count down death/explosion animation duration
        beq bd_done             ; timer reached 0: finalize boss and reset to INACTIVE
        ; keep pieces flashing white during the explosion
        lda #BOSS_FLASH_FRAMES  ; reload full flash constant every dying frame
        sta bossFlash           ; force flash counter high: pieces stay white throughout death sequence
        jsr boss_place_pieces   ; update pieces each dying frame (all white, unchanged positions)
        rts                     ; return; boss still dying, more frames remaining
bd_done                         ; death animation complete: despawn all pieces and award kill bonus
        ; despawn boss pieces
        ldx #6                  ; start at first boss-piece virtual sprite slot (6)
bd_clear                        ; loop: deactivate and park boss-piece slots 6..10
        cpx #11                 ; past last boss-piece slot (10)?
        bcs bd_cleared          ; X >= 11: all 5 pieces (slots 6-10) cleared
        lda #0                  ; zero = inactive
        sta vsActive,x          ; deactivate slot: frees it for enemy reuse in next wave
        lda #255                ; Y=255 = off-screen park position
        sta vsY,x               ; park sprite Y at 255: hidden from multiplexer
        inx                     ; advance to next slot (6->7->8->9->10)
        jmp bd_clear            ; continue clearing remaining pieces
bd_cleared                      ; all 5 boss-piece slots are now inactive
        lda #0                  ; zero for state and counter resets
        sta bossState           ; return boss to INACTIVE (0): enemies can now spawn into slots 6-10 again
        sta killCount           ; reset kill counter so next boss spawns after N more kills
        jsr sfx_explosion       ; play large explosion SID sound (noise burst on V2, ~16 frames)
        ; +1000 score bonus (BCD, IRQ-safe)
        ; IRQ-SAFE BCD BONUS:
        ;   The 6502's D (decimal) flag is global: it affects ALL code including IRQ handlers.
        ;   If the raster IRQ fires while D=1, any ADC/SBC inside the handler runs in decimal
        ;   mode and silently corrupts arithmetic (binary results become wrong BCD-format values).
        ;   Guard sequence:
        ;     PHP  -- push all processor flags, saving the current I (interrupt mask) and D bits.
        ;     SEI  -- disable maskable IRQs so the raster IRQ cannot fire during the BCD region.
        ;     SED  -- enable packed-BCD mode (ADC now produces BCD-correct sums).
        ;     <add> -- multi-byte BCD bonus add runs safely with no interrupt risk.
        ;     PLP  -- atomically restore original I and D flags in one instruction: clears D=0
        ;             and restores IRQ enable simultaneously; no window where D=1 and IRQs enabled.
        php                     ; push processor status: preserves I and D for PLP restoration
        sei                     ; disable maskable IRQs: raster IRQ blocked while D flag is set
        sed                     ; set D flag: switch CPU to BCD mode (ADC produces packed-BCD results)
        clc                     ; clear carry before first BCD byte addition
        lda score+1             ; load middle BCD byte of 3-byte score (hundreds/thousands digit pair)
        adc #$10                ; BCD add $10 = decimal 10 in the tens column = +1000 to total score
        sta score+1             ; store updated middle BCD byte
        lda score+2             ; load high BCD byte (ten-thousands digit pair)
        adc #0                  ; propagate BCD carry from middle byte (handles score crossing 9999)
        sta score+2             ; store updated high BCD byte
        plp                     ; restore flags atomically: exits BCD mode, re-enables IRQs together
        rts                     ; return to main_loop; boss cycle complete

; ---------------------------------------------------------------------
; update_enemy_bullets: slots 11..14 move LEFT; despawn off the left edge.
; ---------------------------------------------------------------------
update_enemy_bullets            ; move all 4 enemy/boss bullet slots leftward; despawn at left edge
        ldx #11                 ; enemy-bullet slot; start scanning at first enemy bullet slot (11)
ueb_loop                        ; top of per-slot loop over enemy bullet slots 11..14
        cpx #15                 ; all four enemy bullet slots (11-14) tested?
        bcs ueb_done            ; X >= 15: all slots processed, exit
        lda vsActive,x          ; is this slot live?
        beq ueb_next            ; slot is empty: skip to next slot
        lda vsXlo,x             ; X -= EBULLET_SPEED (16-bit, move left); load X lo byte
        sec                     ; set carry before SBC so borrow is computed correctly
        sbc #EBULLET_SPEED      ; subtract bullet speed; bullet travels leftward EBULLET_SPEED px/frame
        sta vsXlo,x             ; store decremented X lo byte back to virtual sprite
        lda vsXhi,x             ; load X hi byte for 16-bit borrow propagation
        sbc #0                  ; propagate borrow from lo into hi byte (completes 16-bit decrement)
        sta vsXhi,x             ; store updated X hi byte
        lda vsXhi,x             ; off-left despawn; reload hi byte to check off-screen condition
        bne ueb_hi              ; hi != 0: either underflow ($FF) or still right side ($01); check further
        lda vsXlo,x             ; hi == 0: check lo for minimum visible X
        cmp #8                  ; lo < 8 means X < 8: past the left playfield edge
        bcs ueb_next            ; lo>=8 -> on screen; bullet still in visible playfield
        jsr ue_despawn          ; lo < 8 with hi=0: bullet exited left edge (X < 8), remove it
        jmp ueb_next            ; continue to next slot after despawn
ueb_hi                          ; hi was non-zero: distinguish $FF (underflow) from $01 (still on right)
        cmp #$ff                ; A = vsXhi; $ff = underflow -> despawn; 1 = on right; test for wrap-under
        bne ueb_next            ; hi=$01: X is 256-511, bullet still on screen somewhere right
        jsr ue_despawn          ; hi=$FF: X underflowed below 0, bullet has passed left edge
ueb_next                        ; advance to the next enemy bullet slot
        inx                     ; X++ (slot 11->12->13->14)
        jmp ueb_loop            ; check the next enemy bullet slot
ueb_done                        ; all four enemy bullet slots processed
        rts                     ; return to main_loop

; update_bullets: edge-based firing with charge state; move live bullets
; right; despawn past the right edge (X > 344 = $158).
update_bullets                  ; per-frame player bullet update: fire input, charge, move, despawn
        ; --- exploding player: no fire, reset charge, normal ship color ---
        lda playerState         ; load player state (0=ALIVE, 1=EXPLODE, 2=INVULN)
        cmp #PS_EXPLODE         ; is player currently in explosion animation?
        bne ub_input            ; not exploding: proceed to normal input handling
        lda #0                  ; zero for charge and edge-detector reset
        sta chargeTimer         ; clear charge accumulator (cannot hold-fire while exploding)
        sta prevSpace           ; clear previous-frame Space state (reset rising-edge detector)
        jsr restore_ship_color  ; revert ship color to normal (cancel any charge-feedback tint)
        jmp ub_move             ; skip all input; only move already-live player bullets
ub_input                        ; player is alive or invulnerable: process Space key for firing
        lda keyrow7             ; load CIA keyboard row-7 scan byte (cached by player_update)
        and #%00010000          ; Space, active-low: 0 = DOWN; isolate bit 4 (Space key, C64 matrix row 7)
        bne ub_up               ; bit high = Space NOT pressed this frame: go to release handler
        ; ---- Space DOWN this frame ----
        lda prevSpace           ; load previous-frame Space state (1 = was held, 0 = was up)
        bne ub_hold             ; already down -> charging; non-zero: held since last frame, not a new press
        jsr fire_normal_shot    ; rising edge (was up, now down): fire one normal shot immediately
        lda #0                  ; zero for charge reset after tap-fire
        sta chargeTimer         ; reset charge (a tap shot does not accumulate charge)
        jmp ub_downend          ; done with down-edge handling
ub_hold                         ; Space was already held last frame: accumulate charge each frame held
        lda chargeTimer         ; load current charge accumulator value
        cmp #CHARGE_MAX         ; has charge reached the cap?
        bcs ub_downend          ; capped; already at maximum charge: stop incrementing
        inc chargeTimer         ; increment charge accumulator (one unit per frame held)
ub_downend                      ; common tail for Space-down: record state and show feedback
        lda #1                  ; value 1 = Space was down
        sta prevSpace           ; remember Space was down this frame (for next-frame edge detection)
        jsr charge_feedback     ; pulse ship color to reflect current charge level to player
        jmp ub_move             ; proceed to move existing live bullets
ub_up                           ; Space is UP this frame: check for a falling edge (release event)
        ; ---- Space UP this frame ----
        lda prevSpace           ; load previous-frame Space state
        beq ub_move             ; was already up -> nothing to do; no falling edge (no release) this frame
        lda chargeTimer         ; load accumulated charge
        cmp #CHARGE_THRESHOLD   ; did the player hold Space long enough to earn a beam?
        bcc ub_upclear          ; not enough charge -> no beam; charge too low: discard accumulation
        jsr fire_beam           ; charge met threshold on release: fire a charged beam shot
ub_upclear                      ; clear charge state on Space release (beam fired or charge discarded)
        lda #0                  ; zero for charge and edge-detector clear
        sta chargeTimer         ; reset charge accumulator to zero
        sta prevSpace           ; record Space is now up (for next frame's edge detection)
        jsr restore_ship_color  ; restore ship to normal color (cancel charge or ready-color feedback)
        jmp ub_move             ; proceed to move live bullets
ub_move                         ; move all live player bullets rightward; despawn those past right edge
        ; move all live bullets (slots 0..5) right by 4; despawn past $158
        ldx #0                  ; start from slot 0 (first player bullet slot)
ub_mloop                        ; per-bullet movement loop over slots 0..5
        cpx #6                  ; all 6 player bullet slots checked?
        bcs ub_done             ; X >= 6: all slots processed, exit movement loop
        lda vsActive,x          ; is this bullet slot live?
        beq ub_mnext            ; slot inactive: skip movement for this slot
        lda vsXlo,x             ; load bullet X lo byte for movement
        clc                     ; clear carry for 16-bit addition
        adc #4                  ; advance bullet 4 pixels to the right per frame
        sta vsXlo,x             ; store updated X lo byte
        lda vsXhi,x             ; load X hi byte for carry propagation
        adc #0                  ; propagate carry into hi byte (handles 16-bit crossing of 256-px boundary)
        sta vsXhi,x             ; store updated X hi byte
        ; despawn if X > 344 ($158): hi>=2, or (hi==1 and lo>=$59)
        lda vsXhi,x             ; load X hi byte to test right-edge conditions
        cmp #2                  ; hi >= 2 means X >= 512: well past the right edge
        bcs ub_kill             ; hi >= 2: definitely off-screen right, despawn bullet
        cmp #1                  ; is hi == 0?
        bcc ub_mnext            ; hi==0 -> on screen; X < 256, bullet still on visible playfield
        lda vsXlo,x             ; hi == 1: check lo to see if X >= $159 (345 px, past right edge)
        cmp #$59                ; compare lo against $59 (X = $0159 = 345, just past the 344 boundary)
        bcc ub_mnext            ; lo < $59: X = $0100+lo < 345, bullet still on screen
ub_kill                         ; bullet has passed right edge: deactivate and park it
        lda #0                  ; zero = inactive
        sta vsActive,x          ; clear active flag: bullet removed from play
        lda #0                  ; zero for expand/beam flag
        sta vsExpand,x          ; clear expand/beam flag to avoid stale pierce state on slot reuse
        lda #255                ; park (sorts last); Y=255 sentinel
        sta vsY,x               ; Y=255 pushes slot to end of multiplexer sort order
ub_mnext                        ; advance to next player bullet slot
        inx                     ; X++ (slot 0->1->2->3->4->5)
        jmp ub_mloop            ; loop back to process next slot
ub_done                         ; all player bullet slots processed
        rts                     ; return to main_loop

; spawn_player_bullet: find free slot 0..5, spawn at ship nose using
; bulColor / bulExpand. Plays sfx_fire. No-op if no free slot.
spawn_player_bullet             ; entry: find free player bullet slot and spawn bullet at ship nose
        ldx #0                  ; begin linear search from slot 0 (first player bullet slot)
spb_find                        ; scan for a free (inactive) slot
        cpx #6                  ; all 6 player bullet slots checked?
        bcs spb_none            ; X >= 6: all slots occupied, cannot fire this frame
        lda vsActive,x          ; is this slot already in use?
        beq spb_do              ; active==0: this slot is free, use it
        inx                     ; slot occupied: try the next one
        jmp spb_find            ; loop back to check next slot
spb_do                          ; free slot found at X: initialise and activate the bullet
        lda player_x            ; load player ship X position low byte
        clc                     ; clear carry for 16-bit addition
        adc #24                 ; +24 px right of ship origin: places bullet at the ship's right nose
        sta vsXlo,x             ; store bullet spawn X lo byte
        lda player_x_hi         ; load player X high byte (9-bit X)
        adc #0                  ; propagate carry from lo addition into hi byte
        sta vsXhi,x             ; store bullet spawn X hi byte
        lda player_y            ; load player ship Y position
        clc                     ; clear carry for addition
        adc #8                  ; +8 px below ship Y origin: vertically centres bullet on sprite
        sta vsY,x               ; store bullet spawn Y coordinate
        lda bulColor            ; load caller-set bullet color (yellow for normal; beam color for charged)
        sta vsColor,x           ; assign color to this bullet's virtual sprite slot
        lda bulExpand           ; load caller-set expand/pierce flag (0=normal, 1=charged beam)
        sta vsExpand,x          ; 0=non-piercing normal shot; 1=charged beam (check_hits tests this)
        lda #1                  ; active flag value
        sta vsActive,x          ; mark slot as live (bullet is now active and will be moved)
        jsr sfx_fire            ; trigger SID laser sound effect (sawtooth sweep on V1)
spb_none                        ; no free slot found (or bullet just spawned): return either way
        rts                     ; return to fire_normal_shot or fire_beam

fire_normal_shot                ; set up a normal (yellow, non-piercing) bullet then spawn it
        lda #7                  ; yellow; sprite color index 7 = yellow on C64
        sta bulColor            ; set bullet color to yellow for normal tap-fire shot
        lda #0                  ; zero = no expansion, non-piercing
        sta bulExpand           ; expand=0: normal width; also clears beam/pierce flag
        jsr spawn_player_bullet ; find a free slot and spawn the bullet at the ship nose
        rts                     ; return to update_bullets

fire_beam                       ; set up a charged beam (BEAM_COLOR, piercing) bullet then spawn it
        lda #BEAM_COLOR         ; load beam color constant (distinctive color, different from normal)
        sta bulColor            ; set bullet color to charged-beam color
        lda #1                  ; expand=1: marks bullet as a charged beam
        sta bulExpand           ; expand=1: check_hits uses this flag to apply pierce logic
        jsr spawn_player_bullet ; find a free slot and spawn the beam bullet at the ship nose
        rts                     ; return to update_bullets

; charge_feedback: pulse SP0COL while charging, steady READY at threshold.
charge_feedback                 ; update player ship sprite color to reflect charge state
        lda chargeTimer         ; load current charge accumulator value
        cmp #CHARGE_THRESHOLD   ; has charge reached the beam-fire threshold?
        bcs cf_ready            ; charge at or above threshold: show steady READY color
        lda chargeTimer         ; reload charge (cmp does not leave chargeTimer in A)
        and #%00001000          ; ~8-frame pulse; bit 3 toggles every 8 frames -> ~3 Hz blink at 50fps
        bne cf_alt              ; bit 3 set: show alternate (charging-color) phase
        lda #SHIP_COLOR_NORMAL  ; bit 3 clear: normal-color phase of the pulse blink
        sta SP0COL              ; write normal color to sprite-0 color register
        rts                     ; return; ship shows normal color this frame
cf_alt                          ; alternate blink phase: indicate charge is accumulating
        lda #SHIP_COLOR_CHARGE  ; load charging color (e.g. orange): pulse to show charge building
        sta SP0COL              ; write charging color to sprite-0 color register
        rts                     ; return; ship shows charging color this frame
cf_ready                        ; charge at or above threshold: display steady ready-to-fire indicator
        lda #SHIP_COLOR_READY   ; load ready color (e.g. cyan): beam is primed to release
        sta SP0COL              ; write ready color to sprite-0 color register; held steady (no blink)
        rts                     ; return; ship shows READY color until Space is released or charge lost

restore_ship_color              ; reset player ship sprite color to default (cancel all charge feedback)
        lda #SHIP_COLOR_NORMAL  ; load normal (uncharged, non-flashing) ship color
        sta SP0COL              ; write to sprite 0 color register ($D027)
        rts                     ; return to caller

; ---------------------------------------------------------------------
; check_hits: each live bullet (0..5) vs each alive enemy (6..10).
; bounding box |dX|<HITW and |dY|<HITH -> bullet despawns, enemy explodes.
; X = bullet slot, Y = enemy slot.
; ---------------------------------------------------------------------
check_hits                      ; entry: test every live bullet against every alive enemy/boss piece
        ldx #0                  ; start outer (bullet) loop at slot 0
ch_bloop                        ; top of outer loop: iterate bullet slots 0..5
        cpx #6                  ; all 6 bullet slots checked?
        bcc ch_notdone1         ; X < 6: still have bullet slots to check
        jmp ch_done             ; all bullet slots tested: exit routine
ch_notdone1                     ; trampoline (bcc above cannot reach ch_done directly)
        lda vsActive,x          ; is bullet slot X live?
        bne ch_notbnext1        ; bullet active: proceed to test against enemies
        jmp ch_bnext            ; bullet slot empty: skip to next bullet slot
ch_notbnext1                    ; trampoline
        ldy #6                  ; start inner (enemy) loop at slot 6
ch_eloop                        ; top of inner loop: iterate enemy/boss slots 6..10
        cpy #11                 ; all 5 enemy slots (6-10) checked for this bullet?
        bcc ch_notbnext2        ; Y < 11: still have enemy slots to check
        jmp ch_bnext            ; all enemy slots checked for this bullet: advance to next bullet
ch_notbnext2                    ; trampoline
        lda vsActive,y          ; is enemy slot Y active?
        bne ch_notenext1        ; enemy slot active: proceed to collision test
        jmp ch_enext            ; enemy slot empty: skip to next enemy slot
ch_notenext1                    ; trampoline
        lda vsState,y           ; load enemy state (0=alive/collidable, 1=exploding)
        beq ch_state0           ; state 0: alive and collidable, run hit test
        jmp ch_enext            ; enemy already exploding; already dying: cannot be hit again
ch_state0                       ; enemy is alive: compute bounding-box overlap
        ; --- 16-bit dX = enemyX - bulletX ---
        ; Sprite X is 9-bit (vsXhi:vsXlo). Compute signed 16-bit difference, negate if negative
        ; to obtain |dX|. If |dX| >= HITW the sprites miss horizontally.
        lda vsXlo,y             ; load enemy X lo byte for subtraction
        sec                     ; set carry before SBC (required for correct 16-bit borrow)
        sbc vsXlo,x             ; dX_lo = enemyXlo - bulletXlo
        sta chDlo               ; save dX lo byte to scratch variable
        lda vsXhi,y             ; load enemy X hi byte
        sbc vsXhi,x             ; dX_hi = enemyXhi - bulletXhi - borrow (full 16-bit subtract)
        sta chDhi               ; save dX hi byte; N flag set if result negative (enemy left of bullet)
        bpl ch_xpos             ; dX >= 0; N clear: enemy to the right of bullet, no negation needed
        ; negate 16-bit
        ; dX was negative (enemy left of bullet): two's-complement negate to obtain |dX|
        lda #0                  ; prepare to negate lo byte: 0 - chDlo
        sec                     ; set carry so SBC acts as proper two's-complement negate
        sbc chDlo               ; negate lo byte: sets borrow if chDlo was non-zero
        sta chDlo               ; store |dX| lo byte
        lda #0                  ; prepare to negate hi byte
        sbc chDhi               ; negate hi = 0 - chDhi - borrow; completes 16-bit two's-complement negate
        sta chDhi               ; store |dX| hi byte; chDhi:chDlo = |enemyX - bulletX|
ch_xpos                         ; |dX| is now unsigned in chDhi:chDlo
        lda chDhi               ; load |dX| high byte
        bne ch_enext            ; |dX| >= 256 -> no hit; hi != 0 means X separation >= 256 px (wide miss)
        lda chDlo               ; hi==0: |dX| fits in 8 bits, load lo for threshold compare
        cmp #HITW               ; compare |dX| against hit-box half-width constant
        bcs ch_enext            ; |dX| >= HITW -> no hit; sprites too far apart horizontally
        ; --- 8-bit |dY| = |enemyY - bulletY| ---
        ; Y is 8-bit (VIC-II sprite Y is 0-255): single-byte absolute difference is sufficient.
        lda vsY,y               ; load enemy sprite Y position (8-bit)
        sec                     ; set carry for 8-bit subtraction
        sbc vsY,x               ; dY = enemyY - bulletY (signed 8-bit result in A)
        bpl ch_ypos             ; result >= 0: dY already positive, no negation needed
        eor #$ff                ; flip all bits (one's complement; first step of two's-complement abs)
        clc                     ; clear carry before +1
        adc #1                  ; two's complement abs; +1 completes negation -> A = |dY|
ch_ypos                         ; |dY| now in A (always non-negative)
        cmp #HITH               ; compare |dY| against hit-box half-height constant
        bcs ch_enext            ; |dY| >= HITH -> no hit; sprites too far apart vertically
        ; --- HIT ---
        ; Both axes within bounds: |dX| < HITW and |dY| < HITH -> bounding boxes overlap -> collision
        lda vsExpand,x          ; load bullet's expand/pierce flag (0=normal, 1=charged beam)
        bne ch_beamhit          ; piercing beam; non-zero: charged beam, use beam hit logic
        ; ---- normal shot ----
        lda bossState           ; check whether boss is currently active
        beq ch_normalkill       ; bossState==0: no boss on screen, kill the regular enemy
        jsr boss_take_hit       ; despawn bullet + drain 1 HP; boss-piece hit: despawn bullet, drain shared HP
        jmp ch_bnext            ; bullet consumed by boss_take_hit: advance to next bullet slot
ch_normalkill                   ; no boss: explode enemy, despawn bullet, award score via kill_enemy_y
        jsr kill_enemy_y        ; explode enemy Y + score + killCount; set exploding state, SFX, BCD points
        lda #0                  ; zero = inactive
        sta vsActive,x          ; despawn this bullet; deactivate the bullet that scored the kill
        lda #255                ; off-screen Y sentinel
        sta vsY,x               ; park bullet Y at 255 (multiplexer will sort it last)
        jmp ch_bnext            ; this bullet consumed -> next bullet; done with this bullet slot
ch_beamhit                      ; beam bullet: pierces through enemies, drains boss without self-despawning
        lda bossState           ; check whether boss is currently active
        beq ch_beam_enemy       ; bossState==0: no boss, hit a regular enemy
        ; beam vs boss: drain once, DO NOT despawn beam, move to next bullet
        jsr boss_drain_hp       ; drain 1 HP from boss (beam caller; beam stays live this frame)
        jmp ch_bnext            ; beam has handled boss hit this frame: advance to next bullet slot
ch_beam_enemy                   ; beam vs regular enemy: kill enemy but beam pierces through (stays active)
        jsr kill_enemy_y        ; explode enemy Y + score; explode and score same as a normal kill
        jmp ch_enext            ; beam survives -> test next enemy; continues to next enemy slot
ch_enext                        ; inner loop advance: try next enemy slot
        iny                     ; Y++ (slot 6->7->8->9->10)
        jmp ch_eloop            ; test this bullet against the next enemy slot
ch_bnext                        ; outer loop advance: try next bullet slot
        inx                     ; X++ (slot 0->1->2->3->4->5)
        jmp ch_bloop            ; test next bullet against all enemy slots
ch_done                         ; all bullet/enemy pair checks complete
        rts                     ; return to main_loop

; kill_enemy_y: Y = enemy slot. Explode + SFX + BCD score + killCount.
; Preserves X and Y.
kill_enemy_y                    ; entry: put enemy slot Y into exploding state and award score
        lda #1                  ; explosion state value = 1
        sta vsState,y           ; set enemy into exploding state (locks out collision and movement)
        lda #EXPLODE_FRAMES     ; load explosion animation duration constant
        sta vsExplodeTimer,y    ; start explosion countdown; slot freed when this reaches 0
        lda #EXPLODE_COLOR      ; load explosion color constant (bright flash, e.g. white)
        sta vsColor,y           ; switch enemy sprite to explosion color
        jsr sfx_explosion       ; trigger SID explosion sound effect (noise burst on V2)
        ; IRQ-SAFE BCD SCORE ADD:
        ;   On the 6502 the D (decimal) flag is global: it is shared by the main CPU and any
        ;   IRQ handler. If our raster IRQ fires while D=1, ADC/SBC inside the IRQ handler
        ;   produces BCD results instead of binary, silently corrupting mux or scroll arithmetic.
        ;   Guard sequence:
        ;     PHP  -- push all processor flags (saves current I and D) onto the stack.
        ;     SEI  -- disable maskable IRQs so the raster IRQ cannot fire during the BCD section.
        ;     SED  -- enable packed-BCD arithmetic mode (ADC now produces BCD-correct sums).
        ;     <3-byte BCD add> -- safely add SCORE_PER_KILL across the 3 score bytes.
        ;     PLP  -- atomically restore original I and D flags: clears D=0 and restores IRQ
        ;             enable simultaneously; there is no gap where D=1 and IRQs are enabled.
        php                     ; push processor status: saves I and D flags for PLP restoration
        sei                     ; disable maskable IRQs: raster IRQ blocked while D flag is set
        sed                     ; set D flag: switch CPU to BCD mode (ADC produces packed-BCD results)
        clc                     ; clear carry before first BCD byte addition
        lda score               ; load BCD score byte 0 (packed ones/tens digit pair)
        adc #SCORE_PER_KILL     ; BCD add kill-point bonus (e.g. $10 = 10 pts in BCD)
        sta score               ; store updated score lo byte
        lda score+1             ; load BCD score byte 1 (packed hundreds/thousands digit pair)
        adc #0                  ; propagate BCD carry from lo byte into mid byte
        sta score+1             ; store updated score mid byte
        lda score+2             ; load BCD score byte 2 (packed ten-K/hundred-K digit pair)
        adc #0                  ; propagate BCD carry from mid byte into hi byte
        sta score+2             ; store updated score hi byte
        plp                     ; restore flags atomically: exits BCD mode and re-enables IRQs together
        inc killCount           ; increment kill counter (triggers boss spawn after BOSS_KILL_THRESHOLD kills)
        rts                     ; return to check_hits; X and Y preserved throughout
; =====================================================================
;  SCROLL STEP  (once per frame)
;  - always: build a slice of the back buffer
;  - fine_x 7..1: just decrement and set $D016
;  - fine_x 0:    flip buffers, reset fine to 7, reset build_row
; =====================================================================
scroll_step                         ; entry point: called once per frame from scroll_irq
        jsr build_back_slice        ; spread the heavy work every frame; rebuild ROWS_PER_FRAME rows of back buffer

        dec fine_x                  ; count down 7..0; underflow to $FF signals a full 8-pixel char-step
        bpl just_set_fine           ; result ≥ 0 (fine_x now 0..6): fine frame — return so split_irq ORs fine_x into $D016

        ; --- coarse frame: flip to freshly-built back buffer ----------
        ; fine_x decremented through 0 to $FF (N=1): 8 pixel-steps done = one full character-column scrolled
        jsr flip_buffers            ; swap D018 to point VIC-II at back buffer; toggle front_is_a flag
        jsr shift_color_ram         ; bring color RAM in line (sliced below*)
        jsr inject_color_column     ; paint fresh tile colors into the new rightmost color-RAM column
        jsr advance_map             ; step zp_map 25 bytes forward, wrap at map_end, refresh right-col cache

        lda #7                      ; restart fine-scroll: 8 pixel-steps per character column width
        sta fine_x                  ; reset countdown so next 8 frames produce fine_x 7..0 again
        lda #2                      ; rows 0-1 are the static HUD — never rebuilt by scroll engine
        sta build_row               ; reset back-buffer row cursor to row 2 for this char-step

just_set_fine                       ; branch target for fine-scroll frames (coarse path falls through above)
        rts                         ; return to split_irq, which ORs fine_x into $D016 bits 0-2

; =====================================================================
;  BUILD BACK SLICE
;  Build ROWS_PER_FRAME rows of the back buffer as:
;     back[row][0..38] = front[row][1..39]      (shift left one col)
;     back[row][39]    = map column tile for row (fresh right edge)
;  build_row tracks progress 0..24 across the char-step.
; =====================================================================
build_back_slice                    ; builds up to ROWS_PER_FRAME rows of the back buffer per call
        lda #ROWS_PER_FRAME         ; per-frame row budget (e.g. 4); limits CPU time spent here each frame
        sta rpf_left                ; store budget into down-counter
bbs_loop                            ; top of per-row build loop; runs up to ROWS_PER_FRAME times
        ldx build_row               ; X = next row to build (2..24, advancing across the 8-frame char-step)
        cpx #25                     ; have all 25 playfield rows been rebuilt for this char-step?
        bcs bbs_done                ; yes: exit early even if budget remains (no more work to do)

        ; zp_fsrc = front row base, zp_bdst = back row base
        jsr front_row_addr          ; set zp_fsrc -> front-buffer row X (reads front_is_a to pick BUF_A or BUF_B)
        jsr back_row_addr           ; set zp_bdst -> back-buffer row X (opposite buffer to front)

        ; back[0..38] = front[1..39]
        ldx #0                      ; copy-loop column index; runs 0..38 (39 columns)
bbs_col                             ; inner loop: shift one character-column left across 39 dest cells
        ldy bbs_srcidx,x            ; y = col+1 (1..39): source column in front buffer (one right of dest)
        lda (zp_fsrc),y             ; read front-buffer tile at [build_row, col+1]
        ldy bbs_dstidx,x            ; y = col (0..38): destination column in back buffer
        sta (zp_bdst),y             ; write tile into back buffer at [build_row, col] — one-column left shift
        inx                         ; advance column index
        cpx #39                     ; copied all 39 columns (produces dest cols 0..38)?
        bne bbs_col                 ; no: continue copy loop

        ; back[39] = cached right-edge tile for this row
        ldx build_row               ; restore row index (bbs_col loop overwrote X with value 39)
        lda map_rightcol_cache,x    ; fetch pre-cached new map tile for this row's right edge
        ldy #39                     ; rightmost character column index
        sta (zp_bdst),y             ; place new map tile at column 39 of the back buffer row

        inc build_row               ; advance row cursor so next call starts on the following row
        dec rpf_left                ; consume one unit of this frame's row budget
        bne bbs_loop                ; budget not exhausted: build another row this frame
bbs_done                            ; exit: either budget spent or all 25 rows rebuilt
        rts                         ; return to scroll_step

rpf_left !byte ROWS_PER_FRAME       ; per-frame row budget down-counter (re-initialized each call from constant)

; index tables for the column copy (avoids inx/iny juggling above)
bbs_srcidx !for c,0,38 { !byte c+1 }  ; 39 bytes: source offsets 1,2,...,39 — front col (dest+1)
bbs_dstidx !for c,0,38 { !byte c }    ; 39 bytes: dest offsets 0,1,...,38 — back col (shift target)

; =====================================================================
;  FLIP BUFFERS: point VIC at the back buffer, swap front/back flag
; =====================================================================
flip_buffers                        ; swap double-buffer: freshly-built back becomes the visible front
        lda front_is_a              ; non-zero = BUF_A currently visible; zero = BUF_B currently visible
        beq fb_make_a_front         ; BUF_B is front: swap to make BUF_A front
        ; A is front -> show B
        lda #D18_B                  ; D018 value: VIC screen -> BUF_B ($3800), charset stays at $2000
        sta VICMEM                  ; write $D018: VIC-II reads screen data from BUF_B on next raster
        lda #0                      ; clear flag: BUF_B is now front (visible); BUF_A is now back (rebuilding)
        sta front_is_a              ; update front-buffer flag
        rts                         ; return; VIC-II shows BUF_B from next frame
fb_make_a_front                     ; branch target: BUF_B was front, now make BUF_A front
        lda #D18_A                  ; D018 value: VIC screen -> BUF_A ($0400), charset at $2000
        sta VICMEM                  ; write $D018: VIC-II reads screen data from BUF_A on next raster
        lda #1                      ; set flag: BUF_A is now front (visible); BUF_B is now back (rebuilding)
        sta front_is_a              ; update front-buffer flag
        rts                         ; return; VIC-II shows BUF_A from next frame

; =====================================================================
;  ADDRESS HELPERS
;  front_row_addr: zp_fsrc = (front buffer) + row*40, row in X
;  back_row_addr:  zp_bdst = (back  buffer) + row*40, row in X
; =====================================================================
front_row_addr                      ; sets zp_fsrc to the row-X base address of whichever buffer is front
        lda front_is_a              ; check which buffer is front (non-zero = BUF_A, zero = BUF_B)
        bne fra_a                   ; non-zero: BUF_A is front, take A path
        ; front = B
        lda bufb_lo,x               ; BUF_B row X base address lo byte from pre-computed row table
        sta zp_fsrc                 ; store lo to ZP source pointer
        lda bufb_hi,x               ; BUF_B row X base address hi byte
        sta zp_fsrc+1               ; store hi; zp_fsrc now points at BUF_B row X
        rts                         ; return with zp_fsrc set to front-buffer (BUF_B) row X
fra_a                               ; branch target: BUF_A is the current front buffer
        lda bufa_lo,x               ; BUF_A row X base address lo byte from pre-computed row table
        sta zp_fsrc                 ; store lo to ZP source pointer
        lda bufa_hi,x               ; BUF_A row X base address hi byte
        sta zp_fsrc+1               ; store hi; zp_fsrc now points at BUF_A row X
        rts                         ; return with zp_fsrc set to front-buffer (BUF_A) row X

back_row_addr                       ; sets zp_bdst to the row-X base address of whichever buffer is back
        lda front_is_a              ; back is always the buffer opposite to front
        bne bra_back_is_b           ; non-zero: BUF_A is front, so back = BUF_B
        ; front = B -> back = A
        lda bufa_lo,x               ; BUF_A row X base lo byte (BUF_A is the hidden back buffer here)
        sta zp_bdst                 ; store lo to ZP dest pointer
        lda bufa_hi,x               ; BUF_A row X base hi byte
        sta zp_bdst+1               ; store hi; zp_bdst now points at BUF_A row X (back buffer)
        rts                         ; return with zp_bdst set to back-buffer (BUF_A) row X
bra_back_is_b                       ; branch target: BUF_A is front, so BUF_B is the hidden back buffer
        lda bufb_lo,x               ; BUF_B row X base lo byte
        sta zp_bdst                 ; store lo to ZP dest pointer
        lda bufb_hi,x               ; BUF_B row X base hi byte
        sta zp_bdst+1               ; store hi; zp_bdst now points at BUF_B row X (back buffer)
        rts                         ; return with zp_bdst set to back-buffer (BUF_B) row X

; =====================================================================
;  COLOR RAM SHIFT  (sliced)  -- placeholder fixed-color this stage
;  For now color is uniform per tile, so we don't truly need to shift;
;  we keep a stub that maintains a static colored floor/sky split.
; =====================================================================
shift_color_ram                     ; stub: color-RAM left-shift not yet implemented
        rts                         ; (stage 1.5: color handled statically)

inject_color_column                 ; stub: right-edge color-column injection not yet implemented
        rts                         ; returns immediately; color RAM stays as initialized by fill_front_from_map

; =====================================================================
;  MAP ADVANCE + RIGHT-COLUMN CACHE
;  We cache the 25 tiles of the column that will appear on the right edge
;  so build_back_slice can read them by row index cheaply.
; =====================================================================
advance_map                         ; step map pointer one column forward, wrap at map_end, refresh cache
        ; advance zp_map by 25 (one column), wrap at map_end
        clc                         ; clear carry for 16-bit pointer addition
        lda zp_map                  ; load map pointer lo byte
        adc #25                     ; advance 25 bytes = one full map column (25 tile entries, one per row)
        sta zp_map                  ; store updated lo byte
        lda zp_map+1                ; load map pointer hi byte
        adc #0                      ; propagate carry from lo-byte addition into hi byte
        sta zp_map+1                ; store updated hi byte; zp_map now points at the next map column
        lda zp_map+1                ; reload hi byte for boundary comparison
        cmp #>map_end               ; compare hi byte against map_end hi byte
        bcc am_cache                ; hi < map_end hi: still inside map data, no wrap needed
        bne am_wrap                 ; hi > map_end hi: past end of map, wrap unconditionally
        lda zp_map                  ; hi bytes equal: compare lo bytes to detect exact or over boundary
        cmp #<map_end               ; compare lo byte against map_end lo byte
        bcc am_cache                ; lo < map_end lo: still inside map, no wrap
am_wrap                             ; zp_map has reached or passed map_end: loop level map seamlessly
        lda #<map_data              ; lo byte of map_data start address
        sta zp_map                  ; reset map pointer lo to map start
        lda #>map_data              ; hi byte of map_data start address
        sta zp_map+1                ; reset map pointer hi; map loops back to column 0
am_cache                            ; zp_map is valid and in-range; cache its 25 tiles for right-edge use
        jsr cache_right_column      ; read 25 tiles from (zp_map) into map_rightcol_cache[0..24]
        rts                         ; return; zp_map -> next column, right-col cache is fresh

cache_right_column                  ; copy 25 tiles from current map column into map_rightcol_cache
        ldy #0                      ; Y = row index, start at row 0
crc_loop                            ; loop over all 25 rows of the current map column
        lda (zp_map),y              ; load map tile for row Y from the current column at zp_map
        sty crc_tmp                 ; save Y: 6502 has no TYX instruction, must spill through memory
        ldx crc_tmp                 ; transfer row index into X for X-indexed store
        sta map_rightcol_cache,x    ; write tile into right-edge cache at row X
        iny                         ; advance to next row
        cpy #25                     ; all 25 rows cached?
        bne crc_loop                ; no: cache next row
        rts                         ; 25 right-edge tiles cached; return
crc_tmp !byte 0                     ; 1-byte spill: holds Y (row) for transfer to X (no TYX on 6502)

map_rightcol_cache                  ; 25-byte right-edge tile cache; one entry per playfield row
        !fill 25, 0                 ; initialized to zero; refreshed by cache_right_column each coarse step

; =====================================================================
;  INITIAL FILL: BUF_A from first 40 map columns; cache col 40
; =====================================================================
fill_front_from_map                 ; fills all 40 columns of BUF_A from map_data and populates color RAM
        lda #<map_data              ; lo byte of map_data base address
        sta zp_map                  ; set map pointer lo = start of map data (column 0)
        lda #>map_data              ; hi byte of map_data base address
        sta zp_map+1                ; set map pointer hi; zp_map -> map column 0

        lda #0                      ; outer loop starts at column 0
        sta ff_col                  ; reset column counter (outer loop: columns 0..39)
ff_col_loop                         ; outer loop: iterate over all 40 screen columns
        lda #0                      ; inner loop starts at row 0
        sta ff_row                  ; reset row counter (inner loop: rows 0..24)
ff_row_loop                         ; inner loop: fill one cell [ff_row, ff_col] of BUF_A and color RAM
        ldx ff_row                  ; load current row index for address table lookup
        lda bufa_lo,x               ; BUF_A row ff_row base address lo byte (pre-computed table)
        sta zp_dst                  ; store to destination pointer lo
        lda bufa_hi,x               ; BUF_A row ff_row base address hi byte
        sta zp_dst+1                ; store to destination pointer hi; zp_dst -> BUF_A row ff_row
        lda zp_dst                  ; reload pointer lo to add column offset
        clc                         ; clear carry before column offset addition
        adc ff_col                  ; add current column (0..39) to reach cell [ff_row, ff_col]
        sta zp_dst                  ; store updated lo byte
        bcc ff_nohi                 ; no carry: page boundary not crossed, hi byte unchanged
        inc zp_dst+1                ; carry: advance across 256-byte page boundary
ff_nohi                             ; zp_dst now points at BUF_A cell [ff_row, ff_col]
        ldy ff_row                  ; Y = row index within map column (25 bytes/column, indexed by row)
        lda (zp_map),y              ; load map tile for row ff_row from current column at zp_map
        ldy #0                      ; column offset already baked into zp_dst; use offset 0
        sta (zp_dst),y              ; write map tile into BUF_A at [ff_row, ff_col]

        ; color RAM: static sky/floor split
        ldx ff_row                  ; load row index for color-RAM address table lookup
        lda crow_lo,x               ; color-RAM row ff_row base address lo byte
        sta zp_dst                  ; reuse zp_dst for color-RAM pointer lo
        lda crow_hi,x               ; color-RAM row ff_row base address hi byte
        sta zp_dst+1                ; store color-RAM pointer hi; zp_dst -> color-RAM row ff_row
        lda zp_dst                  ; reload color-RAM pointer lo to add column offset
        clc                         ; clear carry before addition
        adc ff_col                  ; add column offset to reach color-RAM cell [ff_row, ff_col]
        sta zp_dst                  ; store updated lo byte
        bcc ff_cnohi                ; no carry: hi byte unchanged
        inc zp_dst+1                ; carry: advance across page boundary in color RAM space
ff_cnohi                            ; zp_dst now points at color-RAM cell [ff_row, ff_col]
        ldx ff_row                  ; reload row index (previous arithmetic may have clobbered X)
        lda floor_color_tbl,x       ; look up sky/floor split color for this row (table encodes split)
        ldy #0                      ; column offset already in zp_dst; use offset 0
        sta (zp_dst),y              ; write color attribute into color RAM at [ff_row, ff_col]

        inc ff_row                  ; advance row counter
        lda ff_row                  ; load updated row counter
        cmp #25                     ; processed all 25 rows of this column?
        bne ff_row_loop             ; no: continue inner loop

        clc                         ; clear carry for 16-bit map pointer advance
        lda zp_map                  ; load map pointer lo byte
        adc #25                     ; advance 25 bytes = one full map column
        sta zp_map                  ; store updated lo byte
        lda zp_map+1                ; load map pointer hi byte
        adc #0                      ; propagate carry from lo addition
        sta zp_map+1                ; store updated hi byte; zp_map -> next column

        inc ff_col                  ; advance column counter
        lda ff_col                  ; load updated column counter
        cmp #40                     ; filled all 40 screen columns?
        bne ff_col_loop             ; no: continue outer loop

        jsr cache_right_column      ; cache column 40 for first right edge
        rts                         ; BUF_A filled; color RAM initialized; scroll engine ready
ff_col !byte 0                      ; outer loop counter: column currently being filled (0..39)
ff_row !byte 0                      ; inner loop counter: row currently being filled (0..24)

; =====================================================================
;  COPY BUFFER A -> BUFFER B  (one-time at init so both start equal)
;  WARNING: zp_fsrc ($F7) and zp_bdst ($F5) are shared with the raster
;  IRQ. Caller MUST mask IRQs (sei before / cli after) — a past bug let
;  the IRQ fire mid-copy and corrupt these ZP pointers, trashing title
;  sprites stored at $3C00 inside BUF_B's memory page.
; =====================================================================
copy_a_to_b                         ; one-time init: clone BUF_A ($0400) into BUF_B ($3800)
        lda #<BUF_A                 ; lo byte of BUF_A = $00 (BUF_A base = $0400)
        sta zp_fsrc                 ; set source pointer lo; shared ZP — caller must hold sei
        lda #>BUF_A                 ; hi byte of BUF_A = $04
        sta zp_fsrc+1               ; set source pointer hi; zp_fsrc -> $0400
        lda #<BUF_B                 ; lo byte of BUF_B = $00 (BUF_B base = $3800)
        sta zp_bdst                 ; set dest pointer lo
        lda #>BUF_B                 ; hi byte of BUF_B = $38
        sta zp_bdst+1               ; set dest pointer hi; zp_bdst -> $3800
        ldx #4                      ; 4 pages covers 1000 bytes (+pad)
        ldy #0                      ; byte index within current 256-byte page
cab_loop                            ; page-copy loop: 4 outer iterations × 256 inner = 1024 bytes copied
        lda (zp_fsrc),y             ; read byte from BUF_A at page offset Y
        sta (zp_bdst),y             ; write same byte to BUF_B at same offset
        iny                         ; advance byte index within page
        bne cab_loop                ; inner loop: 256 bytes (Y wraps $FF->$00; bne catches that as exit)
        inc zp_fsrc+1               ; advance source pointer to next 256-byte page of BUF_A
        inc zp_bdst+1               ; advance dest pointer to next 256-byte page of BUF_B
        dex                         ; one fewer page remaining
        bne cab_loop                ; outer loop: copy all 4 pages (1024 bytes covers 1000-byte screen + pad)
        rts                         ; done: BUF_A ($0400-$07FF) cloned into BUF_B ($3800-$3BFF)

; =====================================================================
;  SPRITE INIT  (one-time)
;   sprite 0 = player ship (multicolor), sprites 1-7 share mux_shape (hi-res)
;   pointers MUST be set in BOTH screen buffers.
; =====================================================================
SPENA   = $d015              ; sprite enable register: bit N = hw sprite N on/off
SPMC    = $d01c              ; sprite multicolor select: bit N = hw sprite N uses multicolor (3-color)
XXPAND  = $d01d              ; sprite X-expand: bit N = hw sprite N doubled horizontally
YXPAND  = $d017              ; sprite Y-expand: bit N = hw sprite N doubled vertically
SPBGPR  = $d01b              ; sprite-background priority: bit N set = sprite N behind background
SPMC0   = $d025              ; shared sprite multicolor 0 (bit-pair 01 color, all MCM sprites)
SPMC1   = $d026              ; shared sprite multicolor 1 (bit-pair 11 color, all MCM sprites)
SP0COL  = $d027              ; sprite 0 color register (bit-pair 10 in MCM; only color in hi-res)
SP1COL  = $d028              ; sprite 1 color register

PLAYER_PTR = 208             ; $3400 / 64

init_sprites                        ; one-time sprite hardware init; must run after BUF_A and BUF_B are set up
        ; --- sprite 0 (player) pointer in both buffers ---
        lda #PLAYER_PTR             ; 208 = $3400/64
        sta BUF_A+$3f8              ; set sprite-0 pointer in BUF_A sprite table ($07F8); player shape at $3400
        sta BUF_B+$3f8              ; same in BUF_B ($3BF8); BOTH buffers must agree so buffer flip keeps player visible
        ; --- sprites 1..7 all point at the shared mux shape, both buffers ---
        lda #209                    ; ptr 209 = $3440/64; shared mux_shape used by every non-player virtual sprite
        ldx #1                      ; start at slot 1 (slot 0 is always the player ship)
ip_loop                             ; loop: write mux_shape pointer into sprite slots 1..7 in both buffers
        sta BUF_A+$3f8,x            ; set sprite-pointer byte in BUF_A table for hw sprite X ($07F9-$07FF)
        sta BUF_B+$3f8,x            ; same in BUF_B ($3BF9-$3BFF); must match BUF_A so flip is transparent
        inx                         ; next sprite slot
        cpx #8                      ; filled all 8 slots (0 done before loop; 1-7 done here)?
        bne ip_loop                 ; no: continue

        lda #%11111111              ; enable all 8 sprites
        sta SPENA                   ; $D015: all 8 hardware sprites active (player + 7 mux-able slots)
        lda #%00000001              ; only bit 0 set: sprite 0 is multicolor; sprites 1-7 are hi-res (1-bit)
        sta SPMC                    ; $D01C: sprite 0 multicolor (3-color ship), mux sprites hi-res
        ; --- no expansion, sprites in front of background ---
        lda #0                      ; zero = disabled for all expansion and priority registers
        sta XXPAND                  ; $D01D: no horizontal 2x expansion on any sprite
        sta YXPAND                  ; $D017: no vertical 2x expansion on any sprite
        sta SPBGPR                  ; $D01B: all sprites in front of background (priority=0)

        ; --- colors (contrast against blue bg) ---
        lda #1               ; hull = white
        sta SP0COL                  ; $D027: player ship main color (bit-pair 10) = white (color 1)
        lda #7               ; shared MC0 = yellow (engine)
        sta SPMC0                   ; $D025: shared multicolor 0 (bit-pair 01) = yellow (7); engine glow
        lda #2               ; shared MC1 = red (cockpit)
        sta SPMC1                   ; $D026: shared multicolor 1 (bit-pair 11) = red (2); cockpit detail
        lda #7               ; sprite 1 default color (yellow)
        sta SP1COL                  ; $D028: hw sprite 1 (first mux slot) default color = yellow

        ; --- CIA1 data direction for keyboard scan (defensive) ---
        lda #$ff                    ; $FF = all bits output direction
        sta $dc02                   ; CIA1 port-A DDR ($DC02): drive all row lines as outputs (keyboard row select)
        lda #$00                    ; $00 = all bits input direction
        sta $dc03                   ; CIA1 port-B DDR ($DC03): read all column lines as inputs (key state)

        ; --- start position comes from player_x/player_y vars ---
        jsr write_player_sprite     ; push initial player_x/player_y values to VIC sprite-0 X/Y registers
        rts                         ; sprite hardware fully initialized; return

; =====================================================================
;  COLORS
; =====================================================================
set_colors                          ; set VIC-II multicolor background registers for scrolling playfield
        lda #6                      ; color 6 = blue (space/sky fill)
        sta BGCOL0                  ; $D021: background color 0 = blue (char bit-pair 00 = transparent bg)
        lda #14                     ; color 14 = light blue
        sta BGCOL1                  ; $D022: multicolor BG 1 = light blue (sky detail; char bit-pair 01)
        lda #11                     ; color 11 = dark gray
        sta BGCOL2                  ; $D023: multicolor BG 2 = dark gray (terrain body; char bit-pair 10)
        rts                         ; return; background registers ready for scrolling playfield

; =====================================================================
;  CHARSET (same 4 tiles as stage 1)
; =====================================================================
build_charset                       ; construct custom charset at $2000 (tiles, digits, letters, uppercase)
        lda #<CHARSET               ; lo byte of charset RAM destination ($2000 lo = $00)
        sta zp_dst                  ; store to ZP dest pointer lo
        lda #>CHARSET               ; hi byte of charset RAM destination ($20)
        sta zp_dst+1                ; store to ZP dest pointer hi; zp_dst -> $2000 (CHARSET base)
        ldx #8                      ; 8 pages = 2048 bytes = 256 chars × 8 rows each
        ldy #0                      ; byte index within current 256-byte page
bc_clear                            ; zero all 2048 bytes of charset RAM before painting tiles
        lda #0                      ; zero = all pixels off = blank character row
        sta (zp_dst),y              ; clear this charset byte
        iny                         ; next byte within current page
        bne bc_clear                ; inner loop: clear 256 bytes of this page
        inc zp_dst+1                ; advance dest pointer to the next 256-byte charset page
        dex                         ; one fewer page remaining
        bne bc_clear                ; outer loop: zero all 8 pages (2048 bytes cleared)

; --- tile 1: sparse star/detail dot (screen code 1) ---
        lda #%00110000              ; two adjacent pixels at bit positions 5-4 (cols 2-3 from MSB)
        sta CHARSET + 1*8 + 3       ; tile 1, row 3 only: small 2-pixel dot near vertical center of char

        ldx #0                      ; row index for tile 2 fill loop (0..7)
bc_block                            ; loop: fill all 8 rows of tile 2 with solid pixels
; --- tile 2: solid block (platforms, floor, ceiling; screen code 2) ---
        lda #%11111111              ; all 8 pixels on = fully solid row
        sta CHARSET + 2*8, x        ; tile 2, row X = solid; after 8 iterations: filled solid rectangle
        inx                         ; next row
        cpx #8                      ; done all 8 rows of tile 2?
        bne bc_block                ; no: continue

; --- tile 3: dithered-top + solid-bottom terrain (screen code 3) ---
        lda #%10101010              ; alternating pixels: cols 0,2,4,6 lit = coarse checkerboard row
        sta CHARSET + 3*8 + 0       ; tile 3, row 0: rough dithered surface (ground texture top)
        sta CHARSET + 3*8 + 1       ; tile 3, row 1: rough dithered surface
        sta CHARSET + 3*8 + 2       ; tile 3, row 2: rough dithered surface
        sta CHARSET + 3*8 + 3       ; tile 3, row 3: rough dithered surface (4 rows of ground texture)
        lda #%11111111              ; all 8 pixels on = solid row
        sta CHARSET + 3*8 + 4       ; tile 3, row 4: solid ground body begins below dithered top
        sta CHARSET + 3*8 + 5       ; tile 3, row 5: solid
        sta CHARSET + 3*8 + 6       ; tile 3, row 6: solid
        sta CHARSET + 3*8 + 7       ; tile 3, row 7: solid bottom (tile = rough surface + solid base)

        ; --- digit glyphs 0-9 at screen codes 16..25 ---
        ldx #0                      ; byte index into digit_glyphs table (10 glyphs × 8 bytes = 80 bytes)
bc_dig                              ; loop: copy all 80 bytes of digit bitmap data into charset RAM
        lda digit_glyphs,x          ; load one pixel row from digit glyph table
        sta CHARSET + DIGIT_BASE*8, x ; write into charset starting at code DIGIT_BASE (16); fills codes 16-25
        inx                         ; next byte
        cpx #80                     ; copied all 80 bytes (10 digits × 8 rows)?
        bne bc_dig                  ; no: continue
        ; --- letter glyphs at screen codes 26.. (S c o r e h i p s l f t :) ---
        ldx #0                      ; byte index into letter_glyphs table (13 glyphs × 8 bytes = 104 bytes)
bc_let                              ; loop: copy all 104 bytes of lowercase/punctuation glyph data
        lda letter_glyphs,x         ; load one pixel row from letter glyph table
        sta CHARSET + 26*8, x       ; write into charset at code 26 onward (S=26 ... :=38)
        inx                         ; next byte
        cpx #104                    ; copied all 104 bytes (13 glyphs × 8 rows)?
        bne bc_let                  ; no: continue
        ; --- uppercase glyphs at codes 39..49 (A E F G I M O P R T V) ---
        ldx #0                      ; byte index into upper_glyphs table (96 bytes = 12 glyphs × 8 rows)
bc_upper                            ; loop: copy uppercase bitmap data for title-screen capitals
        lda upper_glyphs,x          ; load one pixel row from uppercase glyph table
        sta CHARSET + 39*8, x       ; write into charset at code 39 onward (title-screen letter set)
        inx                         ; next byte
        cpx #96                     ; copied all 96 bytes? (12 glyphs × 8 rows: A E F G I M O P R T V + C)
        bne bc_upper                ; no: continue
        rts                         ; charset RAM fully populated; return

; sid_init: master volume max, all gates off, clear sfx timers
sid_init                            ; one-time SID init: silence all voices and reset SFX engine state
        lda #$0f                    ; volume = 15 (maximum output level), no filter routing bits
        sta $d418               ; volume 15, no filter
        lda #0                      ; 0 = waveform disabled, gate bit clear = voice silenced
        sta $d404               ; V1 control (gate off)
        sta $d40b               ; V2 control
        sta $d412               ; V3 control
        sta sfxTimer+0              ; V1 SFX frame-countdown = 0 (idle, no effect playing)
        sta sfxTimer+1              ; V2 SFX frame-countdown = 0 (idle)
        sta sfxTimer+2              ; V3 SFX frame-countdown = 0 (idle)
        rts                         ; SID silenced; SFX engine state cleared; return

; sound_voice: advance one voice (X = 0,1,2). Sweep freq, write SID, gate
; off when the timer expires. Uses $fd/$fe as the SID voice pointer.
sound_voice                         ; advance SFX voice X one frame: sweep frequency, decrement timer, gate off on expiry
        lda sfxTimer,x              ; load frame-countdown for voice X (0 = idle, no effect playing)
        bne sv_active               ; non-zero: effect in progress, advance it
        rts                     ; idle
sv_active                           ; voice X has an active effect; sweep its frequency register
        lda sidbase_lo,x            ; voice-block base offset: V1=$00, V2=$07, V3=$0E (register spacing)
        sta $fd                     ; ZP indirect ptr lo = voice-block base offset within SID page $D4xx
        lda #$d4                    ; SID register page is always $D4xx
        sta $fe                     ; ZP indirect ptr hi = $D4; ($fe:$fd) now addresses this voice's registers
        clc                         ; clear carry before signed 16-bit frequency sweep addition
        lda sfxFreqLo,x             ; current SID frequency lo byte for voice X (updated each frame)
        adc sfxSweepLo,x            ; add per-frame sweep delta lo byte (16-bit signed, lo half)
        sta sfxFreqLo,x             ; save updated frequency lo
        ldy #0                      ; register offset 0 = frequency lo within voice block
        sta ($fd),y             ; SID freq lo
        lda sfxFreqHi,x             ; current SID frequency hi byte for voice X
        adc sfxSweepHi,x            ; add sweep delta hi byte + carry from lo (completes signed 16-bit add)
        sta sfxFreqHi,x             ; save updated frequency hi
        ldy #1                      ; register offset 1 = frequency hi within voice block
        sta ($fd),y             ; SID freq hi
        dec sfxTimer,x              ; decrement frame countdown for this voice
        bne sv_ret                  ; countdown not yet zero: sweep done for this frame, return
        lda sfxRelease,x        ; timer hit 0 -> gate off (release)
        ldy #4                      ; register offset 4 = control register within voice block
        sta ($fd),y                 ; write gate-off control byte -> starts ADSR release phase (tail of sound)
sv_ret                              ; voice X advanced one frame; return
        rts                         ; return to caller (sound_update or direct call)

; sound_update: music tick + the single shared SFX voice (V3).
; (All SFX live on V3 since the music owns V1/V2 — see music block.)
sound_update                        ; called once per frame from main loop; runs music and SFX
        jsr music_tick              ; advance music engine one frame (drives V1 melody, V2 bass/drums)
        ldx #2                      ; voice index 2 = V3 (the sole SFX voice; all sfx_ routines target V3)
        jsr sound_voice             ; sweep V3 frequency, decrement sfxTimer+2, gate off on expiry
        rts                         ; return; music and active SFX advanced one frame

; sfx_fire: short laser "pew" — on V3, stealing the music drums briefly
sfx_fire                            ; trigger laser fire sound: sawtooth sweep down on V3 for 6 frames
        lda #$09                    ; high nibble=0 (instant attack), low nibble=9 (medium-fast decay)
        sta $d413               ; V3 AD: attack 0, decay 9
        lda #$00                    ; sustain=0 (drops immediately after decay), release=0 (instant gate-off)
        sta $d414               ; V3 SR: sustain 0, release 0
        lda #$00                    ; starting frequency lo byte = 0
        sta sfxFreqLo+2             ; save V3 starting freq lo for sound_voice sweep engine
        sta $d40e                   ; write V3 freq lo register ($D40E) = 0
        lda #$28                    ; starting frequency hi byte = $28; freq = $2800 ≈ 601 Hz (~D5)
        sta sfxFreqHi+2             ; save V3 starting freq hi
        sta $d40f               ; start freq $2800
        lda #$00                    ; sweep lo byte = 0 (no sub-byte component in this sweep)
        sta sfxSweepLo+2            ; V3 sweep lo = 0
        lda #$fd                    ; sweep hi = $FD = -3 signed; 16-bit = -$0300 = -768/frame (pitch fall)
        sta sfxSweepHi+2        ; sweep -$0300/frame
        lda #$20                    ; $20 = sawtooth waveform bit, gate=0 = gate-off control value for expiry
        sta sfxRelease+2        ; saw, gate off
        lda #$21                    ; $20 (sawtooth) | $01 (gate on) = start sawtooth note on V3
        sta $d412               ; saw + gate on
        lda #6                      ; duration: 6 frames (~120 ms at 50 Hz PAL)
        sta sfxTimer+2              ; set V3 countdown; sound_voice sweeps freq and gates off at expiry
        rts                         ; sfx_fire armed on V3; return

; sfx_explosion: noise "boom" — on V3, stealing the music drums
sfx_explosion                       ; trigger explosion sound: white-noise sweep down on V3 for 16 frames
        lda #$0a                    ; attack=0 (instant), decay=10 (slower than fire = longer sustained rumble)
        sta $d413               ; V3 AD
        lda #$00                    ; sustain=0, release=0
        sta $d414               ; V3 SR
        lda #$00                    ; starting frequency lo byte = 0
        sta sfxFreqLo+2             ; save V3 starting freq lo
        sta $d40e                   ; write V3 freq lo ($D40E) = 0
        lda #$18                    ; starting frequency hi = $18; freq = $1800 ≈ 361 Hz
        sta sfxFreqHi+2             ; save V3 starting freq hi
        sta $d40f               ; start freq $1800
        lda #$00                    ; sweep lo = 0
        sta sfxSweepLo+2            ; V3 sweep lo = 0
        lda #$ff                    ; sweep hi = $FF = -1 signed; 16-bit sweep = -$0100 = -256/frame (pitch fall)
        sta sfxSweepHi+2        ; sweep -$0100/frame
        lda #$80                    ; $80 = noise waveform bit, gate=0 = gate-off control value for expiry
        sta sfxRelease+2        ; noise, gate off
        lda #$81                    ; $80 (noise) | $01 (gate on) = start noise burst on V3
        sta $d412               ; noise + gate on (V3 ctrl — NOT $d40b/V2:
        lda #16                 ;  the classic remap slip is missing this one)
        sta sfxTimer+2              ; set V3 countdown; sound_voice sweeps freq and gates off at expiry
        rts                         ; sfx_explosion armed on V3; return

; sfx_hit: damage "thud" on V3
sfx_hit                             ; trigger damage hit sound: pulse wave sweep down on V3 for 20 frames
        lda #$0a                    ; attack=0 (instant onset), decay=10 (medium sustain before fall)
        sta $d413               ; V3 AD
        lda #$00                    ; sustain=0, release=0
        sta $d414               ; V3 SR
        lda #$00                    ; pulse width lo byte = 0
        sta $d410               ; pulse width lo
        lda #$08                    ; pulse width hi = $08; full width = $0800/4096 ≈ 50% duty cycle
        sta $d411               ; pulse width hi (~50%)
        lda #$00                    ; starting frequency lo = 0
        sta sfxFreqLo+2             ; save V3 starting freq lo
        sta $d40e                   ; write V3 freq lo ($D40E) = 0
        lda #$0a                    ; starting frequency hi = $0A; freq = $0A00 ≈ 150 Hz (low thud register)
        sta sfxFreqHi+2             ; save V3 starting freq hi
        sta $d40f               ; start freq $0a00
        lda #$c0                    ; sweep lo = $C0 = 192; forms low byte of -$0040 in signed 16-bit
        sta sfxSweepLo+2            ; V3 sweep lo: $C0 part of -$0040 descending-pitch sweep
        lda #$ff                    ; sweep hi = $FF = -1 signed; combined 16-bit = $FFC0 = -64/frame
        sta sfxSweepHi+2        ; sweep -$0040/frame
        lda #$40                    ; $40 = pulse waveform bit, gate=0 = gate-off control value for expiry
        sta sfxRelease+2        ; pulse, gate off
        lda #$41                    ; $40 (pulse) | $01 (gate on) = start pulse note on V3
        sta $d412               ; pulse + gate on
        lda #20                     ; duration: 20 frames (~400 ms at 50 Hz PAL)
        sta sfxTimer+2              ; set V3 countdown; sound_voice sweeps freq and gates off at expiry
        rts                         ; sfx_hit armed on V3; return

; sfx_boss: ominous rising warning sting on V3
sfx_boss                            ; trigger boss-warning sound: pulse wave rising on V3 for 30 frames
        lda #$08                    ; attack=0 (instant), decay=8 (medium fade during rising pitch)
        sta $d413               ; V3 AD
        lda #$00                    ; sustain=0, release=0
        sta $d414               ; V3 SR
        lda #$00                    ; pulse width lo = 0
        sta $d410                   ; V3 pulse width lo ($D410) = 0
        lda #$08                    ; pulse width hi = $08; ~50% duty cycle
        sta $d411               ; pulse width ~50%
        lda #$00                    ; starting frequency lo = 0
        sta sfxFreqLo+2             ; save V3 starting freq lo
        sta $d40e                   ; write V3 freq lo ($D40E) = 0
        lda #$04                    ; starting frequency hi = $04; freq = $0400 ≈ 60 Hz (very low bass entry)
        sta sfxFreqHi+2             ; save V3 starting freq hi
        sta $d40f               ; start freq $0400 (low)
        lda #$30                    ; sweep lo = $30 = +48; positive = pitch RISES each frame
        sta sfxSweepLo+2            ; V3 sweep lo = +$30/frame (rising pitch component)
        lda #$00                    ; sweep hi = 0; combined 16-bit sweep = +$0030 = +48/frame (rising)
        sta sfxSweepHi+2        ; sweep +$0030/frame (rising)
        lda #$40                    ; $40 = pulse waveform bit, gate=0 = gate-off control value for expiry
        sta sfxRelease+2            ; pulse wave gate-off byte, stored for sound_voice to write at timer expiry
        lda #$41                    ; $40 (pulse) | $01 (gate on) = start rising pulse note on V3
        sta $d412               ; pulse + gate on
        lda #30                     ; duration: 30 frames (~600 ms at 50 Hz) = distinctive boss-entry sting
        sta sfxTimer+2              ; set V3 countdown; sound_voice sweeps freq and gates off at expiry
        rts                         ; sfx_boss armed on V3; return
; =====================================================================
;  ROW ADDRESS TABLES
; =====================================================================
bufa_lo  !for row,0,24 { !byte <(BUF_A + row*40) }   ; BUF_A row low-address bytes (25 rows)
bufa_hi  !for row,0,24 { !byte >(BUF_A + row*40) }   ; BUF_A row high-address bytes
bufb_lo  !for row,0,24 { !byte <(BUF_B + row*40) }   ; BUF_B row low-address bytes
bufb_hi  !for row,0,24 { !byte >(BUF_B + row*40) }   ; BUF_B row high-address bytes
crow_lo  !for row,0,24 { !byte <(COLORRAM + row*40) } ; color RAM row low-address bytes
crow_hi  !for row,0,24 { !byte >(COLORRAM + row*40) } ; color RAM row high-address bytes

; static color per row: sky rows light, floor rows brown-ish
floor_color_tbl                  ; per-row color RAM values: sky rows light blue, floor rows brown/yellow
        !for row,0,24 {          ; generate one color byte per screen row (25 rows)
            !if row >= 23 { !byte 8 } else {       ; row 23-24: orange-brown (ground floor)
                !if row = 22 { !byte 7 } else { !byte 14 } ; row 22: yellow (transition), else light-blue (sky)
            }                    ; end floor-vs-sky color pick
        }                        ; end row loop

; Custom 8x8 hi-res digit glyphs (codes 16-25): each glyph is 8 rows of bit patterns,
; row 7 always $00 (blank descender line). Used by build_charset to populate the charset.
digit_glyphs                     ; 8x8 bitmaps for digits 0-9 (screen codes 16-25): HUD score, lives, score table
        !byte %00111100,%01100110,%01101110,%01110110,%01100110,%01100110,%00111100,%00000000  ; 0
        !byte %00011000,%00111000,%00011000,%00011000,%00011000,%00011000,%01111110,%00000000  ; 1
        !byte %00111100,%01100110,%00000110,%00001100,%00110000,%01100000,%01111110,%00000000  ; 2
        !byte %00111100,%01100110,%00000110,%00011100,%00000110,%01100110,%00111100,%00000000  ; 3
        !byte %00001100,%00011100,%00111100,%01101100,%01111110,%00001100,%00001100,%00000000  ; 4
        !byte %01111110,%01100000,%01111100,%00000110,%00000110,%01100110,%00111100,%00000000  ; 5
        !byte %00111100,%01100110,%01100000,%01111100,%01100110,%01100110,%00111100,%00000000  ; 6
        !byte %01111110,%01100110,%00001100,%00011000,%00011000,%00011000,%00011000,%00000000  ; 7
        !byte %00111100,%01100110,%01100110,%00111100,%01100110,%01100110,%00111100,%00000000  ; 8
        !byte %00111100,%01100110,%01100110,%00111110,%00000110,%01100110,%00111100,%00000000  ; 9

; letter glyphs at codes 26.. : S c o r e h i p s l f t  :
; Lowercase + punctuation for HUD labels (Score, Ships left:). 8 rows per glyph; row 0 blank for ascenders.
letter_glyphs                    ; 8x8 bitmaps for the HUD label letters (codes 26-38: S c o r e h i p s l f t :)
        !byte %00111100,%01100110,%01100000,%00111100,%00000110,%01100110,%00111100,%00000000  ; 26 S
        !byte %00000000,%00000000,%00111100,%01100000,%01100000,%01100000,%00111100,%00000000  ; 27 c
        !byte %00000000,%00000000,%00111100,%01100110,%01100110,%01100110,%00111100,%00000000  ; 28 o
        !byte %00000000,%00000000,%01101100,%01110000,%01100000,%01100000,%01100000,%00000000  ; 29 r
        !byte %00000000,%00000000,%00111100,%01100110,%01111110,%01100000,%00111100,%00000000  ; 30 e
        !byte %01100000,%01100000,%01111100,%01100110,%01100110,%01100110,%01100110,%00000000  ; 31 h
        !byte %00011000,%00000000,%00111000,%00011000,%00011000,%00011000,%00111100,%00000000  ; 32 i
        !byte %00000000,%00000000,%01111100,%01100110,%01111100,%01100000,%01100000,%00000000  ; 33 p
        !byte %00000000,%00000000,%00111110,%01100000,%00111100,%00000110,%01111100,%00000000  ; 34 s
        !byte %00111000,%00011000,%00011000,%00011000,%00011000,%00011000,%00111100,%00000000  ; 35 l
        !byte %00011100,%00110000,%01111100,%00110000,%00110000,%00110000,%00110000,%00000000  ; 36 f
        !byte %00110000,%00110000,%01111100,%00110000,%00110000,%00110110,%00011100,%00000000  ; 37 t
        !byte %00000000,%00011000,%00011000,%00000000,%00000000,%00011000,%00011000,%00000000  ; 38 :

; uppercase glyphs at codes 39.. : A E F G I M O P R T V
; Capitals for "PRESS FIRE TO START", "GAME OVER", "TOP SCORES" labels.
upper_glyphs                     ; 8x8 uppercase bitmaps, codes 39-50 (A E F G I M O P R T V + C for TOP SCORES)
        !byte %00111100,%01100110,%01100110,%01111110,%01100110,%01100110,%01100110,%00000000  ; 39 A
        !byte %01111110,%01100000,%01100000,%01111100,%01100000,%01100000,%01111110,%00000000  ; 40 E
        !byte %01111110,%01100000,%01100000,%01111100,%01100000,%01100000,%01100000,%00000000  ; 41 F
        !byte %00111100,%01100110,%01100000,%01101110,%01100110,%01100110,%00111100,%00000000  ; 42 G
        !byte %01111110,%00011000,%00011000,%00011000,%00011000,%00011000,%01111110,%00000000  ; 43 I
        !byte %01100011,%01110111,%01111111,%01101011,%01100011,%01100011,%01100011,%00000000  ; 44 M
        !byte %00111100,%01100110,%01100110,%01100110,%01100110,%01100110,%00111100,%00000000  ; 45 O
        !byte %01111100,%01100110,%01100110,%01111100,%01100000,%01100000,%01100000,%00000000  ; 46 P
        !byte %01111100,%01100110,%01100110,%01111100,%01101100,%01100110,%01100110,%00000000  ; 47 R
        !byte %01111110,%00011000,%00011000,%00011000,%00011000,%00011000,%00011000,%00000000  ; 48 T
        !byte %01100110,%01100110,%01100110,%01100110,%01100110,%00111100,%00011000,%00000000  ; 49 V
        !byte %00111100,%01100110,%01100000,%01100000,%01100000,%01100110,%00111100,%00000000  ; 50 C

; HUD label strings (screen codes; space = code 0)
; Codes reference digit_glyphs (16-25), letter_glyphs (26-38), upper_glyphs (39-50).
label_score !byte 26,27,28,29,30,38,0              ; "Score: " — S,c,o,r,e,:,space
label_ships !byte 26,31,32,33,34,0,35,30,36,37,38,0  ; "Ships left: " — S,h,i,p,s,sp,l,e,f,t,:,sp
; screen codes; space = 0. S reuses existing code 26.
label_press    !byte 46,47,40,26,26,0,41,43,47,40,0,48,45,0,26,48,39,47,48,$ff  ; "PRESS FIRE TO START" ($ff terminator; interior 0=space)
label_gameover !byte 42,39,44,40,0,45,49,40,47,$ff                              ; "GAME OVER" ($ff terminator)
label_topscores !byte 48,45,46,0,26,50,45,47,40,26,$ff                        ; "TOP SCORES" ($ff terminator)
; BUF_A addresses of the 5 table entry rows (rows 10,12,14,16,18, col 15).
; BUF_B = same + $3400 (add $34 to the high byte); COLORRAM = same + $D400.
hs_row_lo !for i,0,4 { !byte <(BUF_A + (10+i*2)*40 + 15) }  ; low bytes of 5 hi-score row addrs
hs_row_hi !for i,0,4 { !byte >(BUF_A + (10+i*2)*40 + 15) }  ; high bytes of 5 hi-score row addrs
HS_HEAD_OFF = 8*40 + 15    ; heading "TOP SCORES" at row 8, col 15

; =====================================================================
;  MAP DATA (column-major, 25 bytes/column), same generator as stage 1
;  Relocated to $2800 (above charset) so it never overlaps BUF_B.
; =====================================================================
* = $2800                        ; map data sits above the runtime charset ($2000-$27FF), below the sprite art
map_data                         ; starfield map: 120 columns x 25 bytes each, column-major
        !for col, 0, 119 {       ; for each of the 120 map columns...
            !for r, 0, 21 {      ; rows 0-21: sparse stars from a (col,row) hash
                !if (((col*7 + r*13) & 31) = 0) { !byte 1 } else { !byte 0 }  ; deterministic sparse enemy tile
            }                    ; end star pick
            !if ((col & 7) = 0) { !byte 2 } else { !byte 0 }  ; every 8th col: structure tile 2
            !byte 3                     ; row 23: ground tile (always solid)
            !byte 3                     ; row 24: ground tile (always solid)
        }                        ; end column loop
map_end                          ; first byte past the map: advance_map wraps the scroll here

; ---- player movement state ----
keyrow4     !byte $ff        ; cached $DC01 for row $EF (I,J,K)
keyrow5     !byte $ff        ; cached $DC01 for row $DF (L)
keyrow7     !byte $ff        ; cached $DC01 for row $7F (space)
player_x    !byte 60         ; sprite 0 X, low 8 bits
player_x_hi !byte 0          ; sprite 0 X, bit 8 (0 or 1)
player_y    !byte 120        ; sprite 0 Y

; =====================================================================
;  SPRITE DATA  (VIC bank 0, 64-byte aligned)
;  Player: 24x21 multicolor wedge pointing right.
;   bit-pairs: 00=transparent 01=SPMC0(yellow) 10=SP0COL(white) 11=SPMC1(red)
; =====================================================================
* = $3400                        ; sprite block 208 ($3400/64): the player ship bitmap
player_sprite                    ; 24x21 multicolor wedge pointing right (01=engine 10=hull 11=cockpit bit-pairs)
        !byte $00,$00,$00   ; row 0  — blank (top margin)
        !byte $00,$00,$00   ; row 1  — blank
        !byte $00,$00,$00   ; row 2  — blank
        !byte $00,$00,$00   ; row 3  — blank
        !byte $00,$00,$00   ; row 4  — blank
        !byte $a0,$00,$00   ; row 5  — wing tip begins (SPMC0 yellow dot, left edge)
        !byte $aa,$00,$00   ; row 6  — wing upper edge widens (yellow pairs)
        !byte $6a,$a0,$00   ; row 7  — white+yellow: body enters, wing spreads
        !byte $6a,$ea,$00   ; row 8  — body+wing, red accent pair appears ($e=11 10)
        !byte $6a,$fa,$a8   ; row 9  — widest upper half: red tip ($f=11 11) + yellow
        !byte $6a,$fa,$aa   ; row 10 — nose row: full-width red nose + body (center)
        !byte $6a,$fa,$a8   ; row 11 — symmetric to row 9 (mirror lower half)
        !byte $6a,$ea,$00   ; row 12 — symmetric to row 8
        !byte $6a,$a0,$00   ; row 13 — symmetric to row 7
        !byte $aa,$00,$00   ; row 14 — symmetric to row 6
        !byte $a0,$00,$00   ; row 15 — symmetric to row 5 (wing tip closes)
        !byte $00,$00,$00   ; row 16 — blank
        !byte $00,$00,$00   ; row 17 — blank
        !byte $00,$00,$00   ; row 18 — blank
        !byte $00,$00,$00   ; row 19 — blank
        !byte $00,$00,$00   ; row 20 — blank (bottom margin)
        !byte $00           ; pad to 64 bytes (byte 64 of sprite block)

* = $3440                        ; sprite block 209: the one shape shared by all multiplexed sprites
mux_shape                    ; shared shape for all multiplexed sprites (ptr 209)
        !fill 8*3, 0         ; rows 0-7 blank (top gap keeps bullet off HUD edge)
        !byte $00,$7e,$00    ; row 8   — oval top cap  (0111 1110)
        !byte $00,$ff,$00    ; row 9   — full-width oval body ($ff = all 8 center bits set)
        !byte $00,$ff,$00    ; row 10  — full-width oval body
        !byte $00,$ff,$00    ; row 11  — full-width oval body
        !byte $00,$7e,$00    ; row 12  — oval bottom cap  (matches row 8)
        !fill 8*3, 0         ; rows 13-20 blank (bottom gap)
        !byte $00            ; pad to 64 bytes

; =====================================================================
;  VIRTUAL SPRITE TABLE + MUX STATE  (free space $3480-$37FF, below BUF_B $3800)
; =====================================================================
* = $3480                        ; runtime data block: MUST end below BUF_B at $3800 (hard ceiling)
vsXlo    !fill 15,0       ; virtual sprite X low (9-bit X = vsXhi:vsXlo)
vsXhi    !fill 15,0       ; virtual sprite X bit8 (0/1)
vsY      !fill 15,255     ; virtual sprite Y (255 = parked/inactive sorts last)
vsColor  !fill 15,0       ; per-slot hi-res color
vsActive !fill 15,0       ; 0=free, 1=live
vsVY     !fill 15,0       ; signed vertical velocity
vsPattern !fill 15,0       ; 0=straight 1=sine 2=zigzag
vsPhase   !fill 15,0       ; sine table index
vsState   !fill 15,0       ; 0=alive 1=exploding
vsExplodeTimer !fill 15,0  ; frames left in explosion
vsBaseY   !fill 15,0       ; sine vertical center
vsExpand !fill 15,0        ; 1 = X-expanded piercing beam; 0 = normal
spawnTimer !byte 30                   ; frames until next enemy wave spawn
spawnIndex !byte 0                    ; which waveY/wavePattern entry to spawn next
enemyFireTimer !byte 30               ; countdown to next enemy bullet shot
enemyFireIndex !byte 6                ; which virtual slot (6-10) fires next round-robin
ef_scan        !byte 0               ; enemy_fire scan cursor (wraps 6..10)
chDlo      !byte 0        ; check_hits scratch: dX low byte
chDhi      !byte 0        ; check_hits scratch: dX high byte
waveY       !byte 90,120,150,100,140,95,170,110    ; spawn Y per wave entry (8 entries)
wavePattern !byte 0,1,2,1,0,2,1,0    ; straight/sine/zigzag mix
waveN = 8                             ; number of wave entries (constant)
sineTable                        ; 64-entry signed sine (+/-16): enemy sine paths, boss bob, title letter bob
; 64-entry signed displacement table for sine-wave enemy movement; ±16 px amplitude.
; Used by update_enemies to oscillate vsBaseY via vsPhase index (advances each frame).
        !byte $00,$02,$03,$05,$06,$08,$09,$0a,$0b,$0c,$0d,$0e,$0f,$0f,$10,$10  ; Q1 ascent (0→+16)
        !byte $10,$10,$10,$0f,$0f,$0e,$0d,$0c,$0b,$0a,$09,$08,$06,$05,$03,$02  ; Q2 descent (+16→0)
        !byte $00,$fe,$fd,$fb,$fa,$f8,$f7,$f6,$f5,$f4,$f3,$f2,$f1,$f1,$f0,$f0  ; Q3 descent (0→-16)
        !byte $f0,$f0,$f0,$f1,$f1,$f2,$f3,$f4,$f5,$f6,$f7,$f8,$fa,$fb,$fd,$fe  ; Q4 ascent (-16→0)
sortIdx  !byte 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14   ; slot order by Y (persists, re-sorted)
; schedule double buffer: buffer 0 = entries 0..14, buffer 1 = entries 15..29
; The mux IRQ reads the "front" bank while the main loop writes the "back" bank — no tear.
schY     !fill 30,0                   ; mux schedule: Y position per entry (both banks)
schXlo   !fill 30,0                   ; mux schedule: X low byte
schXhi   !fill 30,0                   ; mux schedule: X high bit (bit 8)
schColor !fill 30,0                   ; mux schedule: sprite color
schExpand !fill 30,0       ; per-schedule-entry X-expand flag (parallels schColor)
schCount !byte 0,0        ; [buffer] live count (index 0=bank0, 1=bank1)
schFront !byte 0          ; buffer the IRQ reads (0/1)
; multiplex IRQ state
muxIdx   !byte 0          ; current schedule array index (already buffer-offset)
muxEnd   !byte 0          ; stop index (base+count)
muxHW    !byte 1          ; next hardware sprite (1..7, round robin)
spArm    !byte 0          ; split_irq scratch: first mux arm line (schY-MUX_LEAD)
; bullet fire cooldown
fireCool !byte 0                      ; frames before player can fire again
prevSpace   !byte 0        ; 1 if Space was down last frame (edge detect)
chargeTimer !byte 0        ; frames Space held; >=CHARGE_THRESHOLD -> beam on release
; title screen vars
titlePhase  !byte 0        ; 0 = slide-in entrance, 1 = steady loop
slideIdx    !byte 7        ; letter currently sliding in (7=last E ... 0=A)
titleFrame  !byte 0        ; per-frame counter for title animations
logoShift   !byte 0        ; titleFrame>>2, precomputed each frame before tu_pos
logoCurX    !fill 8,0      ; current X per logo letter (for slide-in easing)
bulColor    !byte 0        ; scratch: color for spawn_player_bullet
bulExpand   !byte 0        ; scratch: expand flag for spawn_player_bullet
; sort/build scratch
sortKey  !byte 0                      ; insertion-sort: current key Y being sifted
sortJ    !byte 0                      ; insertion-sort: inner loop index
tmpSlot  !byte 0                      ; insertion-sort: slot being moved
schBack  !byte 0                      ; build_schedule: back bank index (0/1)
schBackBase !byte 0                   ; build_schedule: base offset for back bank entries
bsBase   !byte 0                      ; build_schedule: copy of schBackBase during fill
ss_x     !byte 1                      ; sort_sprites: outer-loop index (starts at 1, in-place)
; bit masks indexed by hardware sprite number 0..7
msbset   !byte $01,$02,$04,$08,$10,$20,$40,$80  ; OR mask to set sprite n's X MSB in $D010
msbclr   !byte $fe,$fd,$fb,$f7,$ef,$df,$bf,$7f  ; AND mask to clear sprite n's X MSB in $D010
; title logo tables
logoHomeX   !byte 104,124,144,164,184,204,224,244  ; home X per letter (A R E - T Y P E)
logoPtrs    !byte 240,241,242,243,244,245,246,242  ; sprite block numbers (A R E - T Y P E)
logoPalette !byte 1,7,8,2,4,3,5,14                ; rainbow cycle colors (Task 4)
playerState !byte 0        ; 0 alive, 1 exploding, 2 invulnerable
gameState   !byte GS_TITLE     ; GS_TITLE / GS_PLAY / GS_OVER
playerTimer !byte 0                   ; countdown: explosion or invuln duration (frames)
lives       !byte 3                   ; remaining lives (0 = game over)
flashTimer  !byte 0        ; border flash countdown (game over)
overTimer   !byte 0        ; GAME OVER display countdown (OVER_FRAMES -> 0)
; hi-score table: 5 entries × 3 BCD bytes each (lo,mid,hi order), rank 0 = highest.
; Sits safely below BUF_B ($3800); total 15 bytes.
hiScores    !fill 15,0     ; top-5 scores, 3-byte BCD each (lo,mid,hi), entry 0 = rank 1
newRank     !byte $ff      ; rank (0-4) the last run entered at; $ff = didn't place
hsEntry     !byte 0        ; draw_score_table: current entry 0..4
hsChar      !byte 0        ; hs_put scratch: char being written
hsHi        !byte 0        ; hs_put scratch: saved BUF_A page
siStop      !byte 0        ; score_insert scratch: byte offset of the insertion slot
score       !byte 0,0,0   ; 3-byte BCD, low byte first (6 digits)
killCount   !byte 0                   ; enemy kills this run (triggers boss at threshold)
bossState   !byte 0                   ; boss FSM state: 0=inactive, 1=enter, 2=fight, 3=dying
bossHP      !byte 0                   ; boss hit points remaining
bossXlo     !byte 0                   ; boss X position low byte
bossXhi     !byte 0                   ; boss X position high bit
bossY       !byte 0                   ; boss Y position (center piece)
bossYCenter !byte 0                   ; boss target Y for bobbing oscillation
bossPhase   !byte 0                   ; boss bobbing sine phase index
bossFireTimer !byte 0                 ; countdown to next boss bullet volley
bossFlash   !byte 0                   ; boss hit-flash frame counter
bossDeathTimer !byte 0                ; boss death animation countdown
bossOffY    !byte $e8,$f4,$00,$0c,$18   ; -24,-12,0,12,24 (signed): Y offsets for 5 boss pieces
sfxTimer    !fill 3,0          ; frames remaining per voice (0 = idle)
sfxFreqLo   !fill 3,0                 ; current SFX frequency low byte per voice
sfxFreqHi   !fill 3,0                 ; current SFX frequency high byte per voice
sfxSweepLo  !fill 3,0          ; signed 16-bit per-frame freq delta (low byte)
sfxSweepHi  !fill 3,0          ; signed 16-bit per-frame freq delta (high byte)
sfxRelease  !fill 3,0          ; control-reg value with gate cleared (note-off)
sidbase_lo  !byte $00,$07,$0e  ; SID voice base low bytes (high byte $d4); V1=$D400, V2=$D407, V3=$D40E

; =====================================================================
;  TITLE LOGO LETTER SPRITES (hires, 16px wide, blocks 240-246 @ $3C00)
;  Baseline art; refine pixel shapes at the screenshot verify step.
; =====================================================================
* = $3c00                        ; sprite blocks 240-246: title logo letters (free bank-0 tail, no ROM shadow)
glyph_A     ; block 240 (21 rows × 3 + 1 pad = 64 bytes)
        !byte $00,$00,$00, $00,$00,$00, $00,$00,$00             ; rows  0- 2 blank (top margin)
        !byte $0f,$c0,$00, $1f,$e0,$00, $38,$1c,$00, $38,$1c,$00  ; rows  3- 6 apex+sides (A peak widens)
        !byte $3f,$fc,$00, $3f,$fc,$00, $38,$1c,$00, $38,$1c,$00  ; rows  7-10 crossbar+sides
        !byte $38,$1c,$00, $38,$1c,$00, $38,$1c,$00, $38,$1c,$00  ; rows 11-14 parallel sides descend
        !byte $38,$1c,$00, $38,$1c,$00, $00,$00,$00              ; rows 15-17 feet + blank
        !byte $00,$00,$00, $00,$00,$00, $00,$00,$00              ; rows 18-20 blank (bottom margin)
        !byte $00                                                 ; pad to 64 bytes
glyph_R     ; block 241 (21 rows × 3 + 1 pad = 64 bytes)
        !byte $00,$00,$00, $00,$00,$00, $00,$00,$00             ; rows  0- 2 blank
        !byte $3f,$fc,$00, $3f,$fc,$00, $38,$1c,$00, $38,$1c,$00  ; rows  3- 6 top bar + right serif
        !byte $38,$1c,$00, $3f,$fc,$00, $3f,$fc,$00, $38,$e0,$00  ; rows  7-10 mid crossbar, leg begins
        !byte $38,$70,$00, $38,$38,$00, $38,$1c,$00, $38,$1c,$00  ; rows 11-14 diagonal leg fans right
        !byte $38,$0e,$00, $38,$0e,$00, $00,$00,$00              ; rows 15-17 leg kicks right + blank
        !byte $00,$00,$00, $00,$00,$00, $00,$00,$00              ; rows 18-20 blank
        !byte $00                                                 ; pad to 64 bytes
glyph_E     ; block 242 (21 rows × 3 + 1 pad = 64 bytes)
; Note: block 242 also used for the second 'E' in "ARE" (logoPtrs index 7 = 242).
        !byte $00,$00,$00, $00,$00,$00, $00,$00,$00             ; rows  0- 2 blank
        !byte $3f,$fc,$00, $3f,$fc,$00, $38,$00,$00, $38,$00,$00  ; rows  3- 6 top bar + left stem
        !byte $3f,$fc,$00, $3f,$fc,$00, $38,$00,$00, $38,$00,$00  ; rows  7-10 mid bar + left stem
        !byte $38,$00,$00, $3f,$fc,$00, $3f,$fc,$00, $00,$00,$00  ; rows 11-14 left stem + bottom bar
        !byte $00,$00,$00, $00,$00,$00, $00,$00,$00              ; rows 15-17 blank
        !byte $00,$00,$00, $00,$00,$00, $00,$00,$00              ; rows 18-20 blank
        !byte $00                                                 ; pad to 64 bytes
glyph_dash  ; block 243 (21 rows × 3 + 1 pad = 64 bytes)
        !byte $00,$00,$00, $00,$00,$00, $00,$00,$00             ; rows  0- 2 blank
        !byte $00,$00,$00, $00,$00,$00, $00,$00,$00, $00,$00,$00  ; rows  3- 6 blank (above dash)
        !byte $0f,$f0,$00, $0f,$f0,$00, $00,$00,$00, $00,$00,$00  ; rows  7-10 dash stroke (centered)
        !byte $00,$00,$00, $00,$00,$00, $00,$00,$00, $00,$00,$00  ; rows 11-14 blank (below dash)
        !byte $00,$00,$00, $00,$00,$00, $00,$00,$00              ; rows 15-17 blank
        !byte $00,$00,$00, $00,$00,$00, $00,$00,$00              ; rows 18-20 blank
        !byte $00                                                 ; pad to 64 bytes
glyph_T     ; block 244 (21 rows × 3 + 1 pad = 64 bytes)
        !byte $00,$00,$00, $00,$00,$00, $00,$00,$00             ; rows  0- 2 blank
        !byte $3f,$fc,$00, $3f,$fc,$00, $03,$c0,$00, $03,$c0,$00  ; rows  3- 6 full-width top bar + stem
        !byte $03,$c0,$00, $03,$c0,$00, $03,$c0,$00, $03,$c0,$00  ; rows  7-10 stem descends
        !byte $03,$c0,$00, $03,$c0,$00, $03,$c0,$00, $00,$00,$00  ; rows 11-14 stem base + blank
        !byte $00,$00,$00, $00,$00,$00, $00,$00,$00              ; rows 15-17 blank
        !byte $00,$00,$00, $00,$00,$00, $00,$00,$00              ; rows 18-20 blank
        !byte $00                                                 ; pad to 64 bytes
glyph_Y     ; block 245 (21 rows × 3 + 1 pad = 64 bytes)
        !byte $00,$00,$00, $00,$00,$00, $00,$00,$00             ; rows  0- 2 blank
        !byte $38,$1c,$00, $38,$1c,$00, $1c,$38,$00, $0e,$70,$00  ; rows  3- 6 arms spread wide
        !byte $07,$e0,$00, $03,$c0,$00, $03,$c0,$00, $03,$c0,$00  ; rows  7-10 arms merge into stem
        !byte $03,$c0,$00, $03,$c0,$00, $03,$c0,$00, $00,$00,$00  ; rows 11-14 stem descends
        !byte $00,$00,$00, $00,$00,$00, $00,$00,$00              ; rows 15-17 blank
        !byte $00,$00,$00, $00,$00,$00, $00,$00,$00              ; rows 18-20 blank
        !byte $00                                                 ; pad to 64 bytes
glyph_P     ; block 246 (21 rows × 3 + 1 pad = 64 bytes)
        !byte $00,$00,$00, $00,$00,$00, $00,$00,$00             ; rows  0- 2 blank
        !byte $3f,$fc,$00, $3f,$fc,$00, $38,$1c,$00, $38,$1c,$00  ; rows  3- 6 top bar + right bump
        !byte $3f,$fc,$00, $3f,$fc,$00, $38,$00,$00, $38,$00,$00  ; rows  7-10 mid bar closes bump, stem
        !byte $38,$00,$00, $38,$00,$00, $38,$00,$00, $00,$00,$00  ; rows 11-14 left stem only
        !byte $00,$00,$00, $00,$00,$00, $00,$00,$00              ; rows 15-17 blank
        !byte $00,$00,$00, $00,$00,$00, $00,$00,$00              ; rows 18-20 blank
        !byte $00                                                 ; pad to 64 bytes

; =====================================================================
;  BACKGROUND MUSIC  (ported from musical_score.asm — Dies Irae battle
;  remix; lead V1 pulse / bass V2 pulse / drums V3 noise+triangle)
;  Lives at $4000: outside VIC bank 0, so neither the <$2000 code
;  ceiling nor the <$3800 data ceiling is affected.
; =====================================================================
* = $4000                        ; music block: OUTSIDE VIC bank 0, exempt from both memory ceilings

; music_init: stream pointers + the music-owned V1/V2 voice setup.
; Called once at boot after sid_init. Does NOT touch $d418 (sid_init owns it).
music_init                       ; one-time music setup: voice programs + stream pointers (boot, after sid_init)
        ; voice 1 (lead) pulse 50%, punchy-singing envelope
        lda #$00                 ; V1 pulse width lo = 0...
        sta $d402               ; V1 pulse width lo — lower byte of pulse width ($0800 = 50%)
        lda #$08                 ; ...hi = 8 -> 50% duty square for the lead
        sta $d403               ; V1 pulse width hi — upper byte: $08xx ≈ 50% duty cycle
        lda #$1a                 ; V1 AD: attack 1, decay 10 — punchy, singing lead envelope
        sta $d405               ; V1 AD: atk1 dec10 — fast attack, medium decay for punchy tone
        lda #$a8                 ; V1 SR: sustain 10, release 8
        sta $d406               ; V1 SR: sus10 rel8 — high sustain, medium release (singing hold)
        ; voice 2 (bass) pulse, plucky
        lda #$00                 ; V2 pulse width lo = 0...
        sta $d409               ; V2 pulse width lo — 50% duty cycle low byte
        lda #$08                 ; ...hi = 8 -> 50% duty for the bass
        sta $d40a               ; V2 pulse width hi — 50% duty cycle high byte
        lda #$0a                 ; V2 AD: attack 0, decay 10 — plucky bass envelope
        sta $d40c               ; V2 AD: atk0 dec10 — instant attack, medium decay (pluck snap)
        lda #$06                 ; V2 SR: sustain 0, release 6
        sta $d40d               ; V2 SR: sus0 rel6 — no sustain, medium release (staccato bass)
        ; stream pointers + countdowns (0 -> load on first tick)
        lda #<mus_lead_data      ; point the lead stream at its first (note,duration) pair
        sta mus_lead_ptr        ; lead stream pointer low — points to first (note,dur) pair
        lda #>mus_lead_data      ; (hi byte of the lead stream address)
        sta mus_lead_ptr+1      ; lead stream pointer high
        lda #<mus_bass_data      ; point the bass stream at its start
        sta mus_bass_ptr        ; bass stream pointer low
        lda #>mus_bass_data      ; (hi byte of the bass stream address)
        sta mus_bass_ptr+1      ; bass stream pointer high
        lda #<mus_drum_data      ; point the drum stream at its start
        sta mus_drum_ptr        ; drum stream pointer low
        lda #>mus_drum_data      ; (hi byte of the drum stream address)
        sta mus_drum_ptr+1      ; drum stream pointer high
        lda #0                   ; countdowns = 0 -> every voice loads its first note on the first tick
        sta mus_lead_cd         ; lead countdown = 0 so first tick immediately loads a note
        sta mus_bass_cd         ; bass countdown = 0 (same: load on first tick)
        sta mus_drum_cd         ; drum countdown = 0 (same)
        rts                      ; silent until the first music_tick fires the streams

; music_tick: advance all three voices one frame (50 Hz).
; Called from sound_update each game frame. Order: lead, bass, drums.
music_tick                       ; per-frame driver: advance all three voices (called from sound_update, 50 Hz)
        jsr mtick_lead          ; advance lead melody voice (V1 pulse)
        jsr mtick_bass          ; advance bass line voice (V2 pulse)
        jsr mtick_drums         ; advance drum voice (V3 noise/triangle, SFX-aware)
        rts                      ; one frame of music done

; ---- LEAD (voice 1, pulse) -----------------------------------------
; Each tick: decrement countdown; when zero, fetch next (note,dur) pair from stream.
; note=0 -> rest (gate off); nonzero -> index into mus_freqLo/Hi tables, gate on.
mtick_lead                       ; lead: (note,duration) stream player on SID voice 1
        lda mus_lead_cd         ; countdown to next note change (frames)
        bne mtl_dec             ; still counting: skip to decrement
        ldy #0                   ; read the stream's next byte: the note index
        lda (mus_lead_ptr),y    ; fetch note index from stream (byte 0 of pair)
        cmp #$ff                ; $ff = loop sentinel
        bne mtl_g              ; not sentinel: use value as-is
        lda #<mus_lead_data : sta mus_lead_ptr    ; rewind stream pointer low byte
        lda #>mus_lead_data : sta mus_lead_ptr+1  ; rewind stream pointer high byte
        ldy #0                   ; re-read byte 0 after wrapping back to the stream start ($ff = loop)
        lda (mus_lead_ptr),y    ; reload first note after rewind
mtl_g   sta mus_tmp             ; stash note index in scratch
        iny                      ; advance to the pair's second byte: duration in frames
        lda (mus_lead_ptr),y    ; fetch duration (byte 1 of pair) in frames
        sta mus_lead_cd         ; store as new countdown
        lda mus_lead_ptr : clc : adc #2 : sta mus_lead_ptr   ; advance ptr past this pair (low)
        bcc mtl_t : inc mus_lead_ptr+1                       ; carry -> bump high byte
mtl_t   lda mus_tmp             ; retrieve note index
        bne mtl_on              ; nonzero = pitched note
        lda #$40 : sta $d404    ; note 0 = rest: pulse waveform, gate off (silence V1)
        jmp mtl_dec             ; skip freq write, just decrement
mtl_on  tax                      ; note index -> X for the frequency table lookup
        lda mus_freqLo,x : sta $d400  ; V1 freq low byte from table (note X)
        lda mus_freqHi,x : sta $d401  ; V1 freq high byte from table
        lda #$40 : sta $d404          ; pulse + gate off: retrigger envelope from zero
        lda #$41 : sta $d404          ; pulse + gate on: start new note (ADSR fires)
mtl_dec dec mus_lead_cd         ; count down this note's remaining frames
        rts                      ; note started; the countdown holds it for its duration

; ---- BASS (voice 2, pulse) -----------------------------------------
; Identical structure to mtick_lead but drives V2 registers ($D407-$D40B).
mtick_bass                       ; bass: same (note,duration) stream player on SID voice 2
        lda mus_bass_cd         ; countdown for bass voice
        bne mtb_dec             ; still counting: decrement only
        ldy #0                   ; read the next note index
        lda (mus_bass_ptr),y    ; fetch note index from bass stream
        cmp #$ff                ; loop sentinel?
        bne mtb_g                ; not the $ff loop terminator -> play it
        lda #<mus_bass_data : sta mus_bass_ptr    ; rewind bass stream low byte
        lda #>mus_bass_data : sta mus_bass_ptr+1  ; rewind bass stream high byte
        ldy #0                   ; re-read after wrapping to the loop start
        lda (mus_bass_ptr),y    ; reload first note after rewind
mtb_g   sta mus_tmp             ; stash note index
        iny                      ; duration byte of the pair
        lda (mus_bass_ptr),y    ; fetch duration in frames
        sta mus_bass_cd         ; store as countdown
        lda mus_bass_ptr : clc : adc #2 : sta mus_bass_ptr   ; advance ptr (low)
        bcc mtb_t : inc mus_bass_ptr+1                       ; carry -> bump high byte
mtb_t   lda mus_tmp             ; retrieve note index
        bne mtb_on              ; nonzero = pitched note
        lda #$40 : sta $d40b    ; rest: V2 pulse + gate off
        jmp mtb_dec              ; rest: gate off only, no new note this step
mtb_on  tax                      ; note index -> X for the freq lookup
        lda mus_freqLo,x : sta $d407  ; V2 freq low byte (note X)
        lda mus_freqHi,x : sta $d408  ; V2 freq high byte
        lda #$40 : sta $d40b          ; V2 pulse + gate off (retrigger)
        lda #$41 : sta $d40b          ; V2 pulse + gate on
mtb_dec dec mus_bass_cd         ; decrement bass countdown
        rts                      ; bass note running

; ---- DRUMS (voice 3, noise/triangle) -------------------------------
; Structured differently: decrement first, load on zero. This means the
; duration byte is a "hold frames" count before the NEXT hit fires.
; SFX steal: if sfxTimer+2 is nonzero, a sound effect owns V3 — advance
; the stream pointer silently so the beat stays in time, but skip all
; V3 register writes so SFX is not interrupted.
mtick_drums                      ; drums: kick/snare/hat hits on SID voice 3 (shared with the SFX engine)
        lda mus_drum_cd         ; frames remaining on current drum entry
        beq mtd_load            ; countdown expired: fetch next entry
        dec mus_drum_cd         ; still counting: decrement and return
        rts                      ; mid-step: nothing to do this frame
mtd_load ldy #0                  ; countdown expired: read the next drum step
        lda (mus_drum_ptr),y    ; fetch hit type: 0=rest, 1=kick, 2=snare, 3=hat; $ff=loop
        cmp #$ff                ; loop sentinel?
        bne mtd_g                ; not the terminator -> use it
        lda #<mus_drum_data : sta mus_drum_ptr    ; rewind drum stream low byte
        lda #>mus_drum_data : sta mus_drum_ptr+1  ; rewind drum stream high byte
        ldy #0                   ; re-read after wrapping the drum pattern
        lda (mus_drum_ptr),y    ; reload first entry after rewind
mtd_g   sta mus_tmp             ; stash hit type
        iny                      ; duration byte
        lda (mus_drum_ptr),y    ; fetch duration (frames until next entry)
        sta mus_drum_cd         ; store countdown
        lda mus_drum_ptr : clc : adc #2 : sta mus_drum_ptr   ; advance ptr (low)
        bcc mtd_t : inc mus_drum_ptr+1                       ; carry -> bump high byte
mtd_t   lda mus_tmp             ; retrieve hit type
        bne mtd_hit                     ; nonzero -> a drum hit
        jmp mtd_dec                     ; 0 -> rest (let prev decay)
mtd_hit ; SFX steal: while an effect owns V3, advance silently (beat stays
        ; in time) but write no V3 registers; drums resume next hit after.
        lda sfxTimer+2          ; check if SFX engine is using V3 (nonzero = owned by SFX)
        beq mtd_free            ; zero = V3 is free for drums
        jmp mtd_dec              ; stolen: skip kick/snare/hat writes
mtd_free                         ; V3 free (no SFX live) -> actually play the hit
        lda mus_tmp              ; reload hit type (sfxTimer+2 check clobbered A)
        cmp #1                   ; hit type 1 = kick drum?
        bne mtd_sn               ; not a kick -> check snare
        ; kick: low triangle, fast decay
        lda #$06 : sta $d413    ; V3 AD: fast attack, short decay (thud envelope)
        lda #$00 : sta $d414    ; V3 SR: no sustain, instant release
        lda #$80 : sta $d40e    ; V3 freq lo = $0080 — very low triangle pitch (kick fundamental)
        lda #$04 : sta $d40f    ; V3 freq hi = $0480 — low bass thud frequency
        lda #$10 : sta $d412    ; V3 ctrl: triangle waveform, gate off (retrigger)
        lda #$11 : sta $d412    ; V3 ctrl: triangle waveform, gate on (kick fires)
        jmp mtd_dec              ; kick started
mtd_sn  cmp #2                  ; hit type 2 = snare?
        bne mtd_hat              ; not a snare -> hi-hat
        ; snare: mid noise
        lda #$06 : sta $d413    ; V3 AD: fast attack, short decay
        lda #$00 : sta $d414    ; V3 SR: no sustain, instant release
        lda #$00 : sta $d40e    ; V3 freq lo = $2000 — mid-range noise pitch
        lda #$20 : sta $d40f    ; V3 freq hi
        lda #$80 : sta $d412    ; V3 ctrl: noise waveform, gate off (retrigger)
        lda #$81 : sta $d412    ; V3 ctrl: noise waveform, gate on (snare fires)
        jmp mtd_dec              ; snare started
mtd_hat ; hi-hat: high noise, very fast decay
        lda #$02 : sta $d413    ; V3 AD: instant attack, very short decay (tick)
        lda #$00 : sta $d414    ; V3 SR: no sustain, instant release
        lda #$00 : sta $d40e    ; V3 freq lo = $7000 — high-pitched noise (hi-hat)
        lda #$70 : sta $d40f    ; V3 freq hi
        lda #$80 : sta $d412    ; V3 ctrl: noise, gate off (retrigger)
        lda #$81 : sta $d412    ; V3 ctrl: noise, gate on (hat fires)
mtd_dec dec mus_drum_cd         ; decrement drum countdown
        rts                      ; drum step done; the countdown times the gap to the next hit

; =====================================================================
;  MUSIC DATA (verbatim from musical_score.asm, labels mus_-prefixed)
; =====================================================================
; Frequency lookup tables: 50 entries (indices 1-49 used; index 0 = rest placeholder).
; Values are SID PAL frequency register words for notes across ~4 octaves.
mus_freqLo                       ; SID frequency lo bytes for note indices 0-49 (pairs with mus_freqHi)
         !byte 0,90,156,226,45,123,207,39,133,232,81,193,55,180,56,196,89,247,157,78,10,208,162,129,109,103,112,137,178,237,59,156,19,160,69,2,218,206,224,17,100,218,118,57,38,64,137,4,180,156  ; freq low bytes, index 0-49
mus_freqHi                       ; SID frequency hi bytes (together: the 16-bit SID frequency per note)
         !byte 0,4,4,4,5,5,5,6,6,6,7,7,8,8,9,9,10,10,11,12,13,13,14,15,16,17,18,19,20,21,23,24,26,27,29,31,32,34,36,39,41,43,46,49,52,55,58,62,65,69  ; freq high bytes, index 0-49

; --- streams: pairs of (value, duration-in-frames); $ff = loop ---
; Lead melody: Dies Irae theme on V1 pulse. Opens with ~6.4s of intro rests,
; then two full 8-note theme statements, an octave-up repeat (indexes 42-49),
; a return to the lower theme, and a descending run before a held final note.
mus_lead_data                    ; lead stream: (note,duration) pairs, $ff = loop — the Dies Irae theme sections
         !byte 0,80,0,80,0,80,0,40,34,10,35,10,37,10,39,10   ; intro rests (240 frames ~4.8s), then Dies Irae opening 4-note motif
         !byte 30,10,30,10,29,10,30,10,27,10,25,10,27,10,27,10  ; theme phrase A, quarter-ish notes at 10 frames each
         !byte 30,10,34,10,32,10,30,10,32,10,29,10,27,10,27,10  ; theme phrase B, descending answering line
         !byte 30,10,30,10,29,10,30,10,27,10,25,10,27,10,27,10  ; theme phrase A repeat
         !byte 30,10,34,10,32,10,30,10,32,10,29,10,27,10,27,10  ; theme phrase B repeat
         !byte 42,10,42,10,41,10,42,10,39,10,37,10,39,10,39,10  ; octave-up phrase A (indexes 39-42 = same intervals)
         !byte 42,10,46,10,44,10,42,10,44,10,41,10,39,10,39,10  ; octave-up phrase B
         !byte 42,10,42,10,41,10,42,10,39,10,37,10,39,10,39,10  ; octave-up phrase A repeat
         !byte 42,10,46,10,44,10,42,10,44,10,41,10,39,10,39,10  ; octave-up phrase B repeat
         !byte 30,10,30,10,29,10,30,10,27,10,25,10,27,10,27,10  ; return to lower register phrase A
         !byte 30,10,34,10,32,10,30,10,32,10,29,10,27,10,27,10  ; lower phrase B
         !byte 30,10,30,10,29,10,30,10,27,10,25,10,27,10,27,10  ; lower phrase A final statement
         !byte 39,5,37,5,35,5,34,5,32,5,30,5,29,5,27,5         ; descending run at half duration (5 frames = faster)
         !byte 27,40,255                                          ; final held note (40 frames ~0.8s), then loop

; Bass line: repeated single-note pedal tones underpinning the Dies Irae harmony.
; Four root-position pedal notes (indexes 15,13,11,10) each repeated 8× at 10 frames.
; Later adds octave-interval leaps (e.g. 15+12=27) for harmonic variation in final section.
mus_bass_data                    ; bass stream: driving 8th-note D-C-Bb-A line, galloping octaves in the climax
         !byte 15,10,15,10,15,10,15,10,15,10,15,10,15,10,15,10  ; pedal note 15 (root), 8× — first chord block
         !byte 13,10,13,10,13,10,13,10,13,10,13,10,13,10,13,10  ; pedal note 13 (minor VI), 8× — second chord
         !byte 11,10,11,10,11,10,11,10,11,10,11,10,11,10,11,10  ; pedal note 11 (IV), 8× — third chord
         !byte 10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10  ; pedal note 10 (III), 8× — fourth chord
         !byte 15,10,15,10,15,10,15,10,15,10,15,10,15,10,15,10  ; chord block 1 repeat
         !byte 13,10,13,10,13,10,13,10,13,10,13,10,13,10,13,10  ; chord block 2 repeat
         !byte 11,10,11,10,11,10,11,10,11,10,11,10,11,10,11,10  ; chord block 3 repeat
         !byte 10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10  ; chord block 4 repeat
         !byte 15,10,15,10,15,10,15,10,15,10,15,10,15,10,15,10  ; chord block 1 third pass
         !byte 13,10,13,10,13,10,13,10,13,10,13,10,13,10,13,10  ; chord block 2 third pass
         !byte 11,10,11,10,11,10,11,10,11,10,11,10,11,10,11,10  ; chord block 3 third pass
         !byte 10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10  ; chord block 4 third pass
         !byte 15,10,15,10,27,10,15,10,15,10,27,10,15,10,15,10  ; block 1 with octave leaps (note 27 = 15+12 = root+oct)
         !byte 13,10,13,10,25,10,13,10,13,10,25,10,13,10,13,10  ; block 2 with octave leaps (25 = 13+12)
         !byte 11,10,11,10,23,10,11,10,11,10,23,10,11,10,11,10  ; block 3 with octave leaps (23 = 11+12)
         !byte 10,10,10,10,22,10,10,10,10,10,22,10,10,10,10,10  ; block 4 with octave leaps (22 = 10+12)
         !byte 255                                                 ; loop sentinel

; Drum pattern: pairs (hit_type, dur=5). Type: 1=kick, 2=snare, 3=hat, 0=rest.
; Pattern per 8-entry row: K-R-H-R-S-R-K-R or K-R-H-R-S-R-K-H (last beat varies).
; Each entry = 5 frames at 50Hz -> 10 entries/second. Rows 1,3,5... end with hat fill.
; Last row before loop ends with four consecutive snares (fill / turnaround).
mus_drum_data                    ; drum stream: (hit,duration) pairs — 1=kick 2=snare 3=hat, $ff = loop
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,0,5   ; bar 1:  K rest H rest S rest K rest
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,3,5   ; bar 2:  K rest H rest S rest K hat (fill)
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,0,5   ; bar 3:  K rest H rest S rest K rest
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,3,5   ; bar 4:  K rest H rest S rest K hat
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,0,5   ; bar 5:  K rest H rest S rest K rest
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,3,5   ; bar 6:  K rest H rest S rest K hat
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,0,5   ; bar 7:  K rest H rest S rest K rest
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,3,5   ; bar 8:  K rest H rest S rest K hat
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,0,5   ; bar 9:  K rest H rest S rest K rest
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,3,5   ; bar 10: K rest H rest S rest K hat
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,0,5   ; bar 11: K rest H rest S rest K rest
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,3,5   ; bar 12: K rest H rest S rest K hat
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,0,5   ; bar 13: K rest H rest S rest K rest
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,3,5   ; bar 14: K rest H rest S rest K hat
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,0,5   ; bar 15: K rest H rest S rest K rest
         !byte 1,5,0,5,3,5,0,5,2,5,2,5,2,5,2,5   ; bar 16: K rest H rest S S S S (snare fill / turnaround)
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,0,5   ; bar 17: K rest H rest S rest K rest
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,3,5   ; bar 18: K rest H rest S rest K hat
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,0,5   ; bar 19: K rest H rest S rest K rest
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,3,5   ; bar 20: K rest H rest S rest K hat
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,0,5   ; bar 21: K rest H rest S rest K rest
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,3,5   ; bar 22: K rest H rest S rest K hat
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,0,5   ; bar 23: K rest H rest S rest K rest
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,3,5   ; bar 24: K rest H rest S rest K hat
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,0,5   ; bar 25: K rest H rest S rest K rest
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,3,5   ; bar 26: K rest H rest S rest K hat
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,0,5   ; bar 27: K rest H rest S rest K rest
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,3,5   ; bar 28: K rest H rest S rest K hat
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,0,5   ; bar 29: K rest H rest S rest K rest
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,3,5   ; bar 30: K rest H rest S rest K hat
         !byte 1,5,0,5,3,5,0,5,2,5,0,5,1,5,0,5   ; bar 31: K rest H rest S rest K rest
         !byte 1,5,0,5,3,5,0,5,2,5,2,5,2,5,2,5   ; bar 32: K rest H rest S S S S (snare fill / loop point)
         !byte 255                                  ; loop sentinel — restart from bar 1

; =====================================================================
;  BOOT SPLASH DATA (VIC bank 1) — aretype.kla, Koala format:
;  2-byte load address, 8000B bitmap, 1000B screen, 1000B colram, 1B bg.
;  Regenerate with: npx retropixels -c yuv -r 16 -d bayer8x8 \
;                       -o aretype.kla aretype.png
;  Screen RAM must be $0400-aligned and the bitmap $2000-aligned inside
;  the bank; $4000 holds the music, so the bitmap takes $6000.
; =====================================================================
* = $5800                       ; color-RAM table: copied to $d800 by show_splash
splash_colram   !binary "aretype.kla",1000,9002   ; 1000 bytes, one low-nibble color per 4x8 cell
* = $5c00                       ; bitmap screen RAM ($0400-aligned slot 7 of bank 1)
splash_screen   !binary "aretype.kla",1000,8002   ; two colors per cell: hi nibble = bit-pair 01, lo = 10
* = $6000                       ; bitmap ($2000-aligned second half of bank 1)
splash_bitmap   !binary "aretype.kla",8000,2      ; 8000 bytes: 40x25 cells x 8 rows of bit-pairs
splash_bg       !binary "aretype.kla",1,10002     ; Koala background byte -> $d021 (bit-pair 00)
