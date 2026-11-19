; Stock SG-1000: 48K linear cartridge, 1K work RAM, TMS9918A, SN76489.
        org 0
        di
        jp boot
        defs $38-$
        reti
        defs $66-$
        retn                    ; console Pause NMI

VDP     equ $be
CTRL    equ $bf
PAD     equ $dc
PSG     equ $7f
; Each of the sixteen on-screen columns occupies one aligned 16-byte slot.
map     equ $c000
        struct State
stage   byte
lives   byte
coins   byte                    ; packed BCD
px      byte
py      byte                    ; top of small Mario / lower half of Super Mario
vy      byte
floor   byte
big     byte
immune  byte
face    byte
pad     byte
edge    byte
tick    byte
speed   byte
scroll  word                    ; pixel coordinate of left edge
nextcol word
spawn   word
goal    word
kind    byte
lifts   word                    ; follows environment in compiled area descriptor
back    byte                    ; name table register: 6 or 7
dirty   byte
bonus   byte
entry   word
exitcam word
exity   byte
scorelo byte                    ; packed BCD, in hundreds
scorehi byte
timer   byte                    ; packed BCD tens and ones
hundred byte
divider byte
flag_y  byte
retry   byte
phase   byte                    ; half-metatile camera phase (0 or 8)
ready   byte
vx      word                    ; signed 8.8 pixels per tick
xf      byte
yf      byte
vf      byte                    ; fractional part of vy
above   byte                    ; player is in the page above the playfield
rise    byte
fall    byte
star    word
lastpose byte
forced  byte                    ; pose override + 1 (death, climb, growth)
throwing byte
walkphase byte
starvel byte
animcount byte
yview   byte
tall    byte
morph   byte
theme   byte                    ; last uploaded theme + 1
scene   byte                    ; 0 gameplay, 1 lives card, 2 pipe entrance, 3 time up, 4 game over
pipeclip byte                   ; pixels hidden by the pipe mouth
duck    byte
spring_y byte                   ; 0 if no spring is visible
spring_x byte
spring_t byte                   ; compression/rebound countdown
satpage byte                    ; 0 or 4: SAT at $1b00 or $1f00
posetab byte                    ; 0 or 104: active pose pattern base
scorefrac byte                  ; packed BCD points below one hundred
endphase byte                   ; goal sprite state
bursts byte
effect_y byte
effect_x byte
quest byte                      ; cleared on power-on, earned by rescuing Peach
outside byte                    ; emerged from an underground/water exit
expired byte                    ; set only by the timer, not by enemy/pit deaths at 000
hard    byte                    ; SecondaryHardMode (Quest 2, or 5-3 onward)
liftwidth byte                  ; 32 or 48 pixels, shared by SAT and collision
        ends
s       equ $c100
        struct Actor
active  byte
x       byte
y       byte
dir     byte
style   byte
        ends
actors  equ $c150                ; two walkers + one mushroom
item    equ actors+2*Actor
shot    equ item+Actor
; Parallel records for the two enemy slots (same stride as Actor). The
; visible style changes to a shell, but its species and wake timer survive.
birth   equ 4*Actor
wake_lo equ birth+1
wake_hi equ birth+2
throw_cd equ birth+3
        assert actors+2*Actor+throw_cd < $c180
sat     equ $c180

boot:   ld sp,$c400
        xor a
        ld hl,map
        ld (hl),a
        ld de,map+1
        ld bc,1023
        ldir
        call silence
        ld hl,vdp_init
        ld b,8
        ld c,$80
.reg:   ld a,(hl)
        out (CTRL),a
        ld a,c
        out (CTRL),a
        inc hl
        inc c
        djnz .reg
        ld hl,0
        call address
        ld bc,$4000
.clear: xor a
        out (VDP),a
        dec bc
        ld a,b
        or c
        jr nz,.clear
        ld hl,0
        ld de,patterns
        call three_banks
        ld hl,$3800+24*8
        call address
        ld hl,sprites
        ld de,sprites_end-sprites
        call transfer
        jp title
vdp_init: db 2,$82,6,$ff,3,$36,7,4 ; Graphics II, 16x16 sprites, IRQ off

three_banks:
        ld b,3
.bank:  push bc
        push hl
        push de
        call address
        ex de,hl
        ld de,patterns_end-patterns
        call transfer
        pop de
        pop hl
        ld bc,$800
        add hl,bc
        pop bc
        djnz .bank
        ret
address:ld a,l
        out (CTRL),a
        ld a,h
        or $40
        out (CTRL),a
        ret
transfer:                       ; HL source, DE byte count
        ld a,(hl)
        out (VDP),a
        inc hl
        dec de
        ld a,d
        or e
        jr nz,transfer
        ret
vblank: in a,(CTRL)
        and $80
        jr z,vblank
        ret
silence:
        ld a,$9f
        out (PSG),a
        ld a,$bf
        out (PSG),a
        ld a,$df
        out (PSG),a
        ld a,$ff
        out (PSG),a
        ret
input:  in a,(PAD)
        cpl
        ld b,a
        ld a,(s+State.pad)
        cpl
        and b
        ld (s+State.edge),a
        ld a,b
        ld (s+State.pad),a
        ret

title:  call silence
        xor a
        ld (s+State.stage),a
        ld (s+State.scene),a
        ld (s+State.retry),a
        ld (s+State.scorefrac),a
        ld (s+State.scorelo),a
        ld (s+State.scorehi),a
        ld (s+State.coins),a
        ld (s+State.big),a
        ld a,3
        ld (s+State.lives),a
        ld a,6
        ld (s+State.back),a
        call load_stage
        xor a
        ld (playing),a          ; start the lead-in on Start, not on the title
        call redraw
        call hud
        ld hl,$1865
        ld de,logo
        ld b,11
.sign:  push bc
        push hl
        call back_address
        ex de,hl
        ld de,22
        call transfer
        ex de,hl
        pop hl
        ld bc,32
        add hl,bc
        pop bc
        djnz .sign
        ld hl,$1a08
        ld de,start_text
        call text
        ld a,$c2
        out (CTRL),a
        ld a,$81
        out (CTRL),a
        call flip
        ld a,160
        ld (s+State.py),a
        call draw_sprites
        call input
.select:call selector_label
.wait:  call vblank
        call music_tick
        call input
        ld a,(s+State.edge)
        bit 4,a
        jr nz,restart
        bit 0,a                  ; Up/Down choose the quest without a save file
        jr z,.down
        ld a,1
        jr .quest
.down:  bit 1,a
        jr z,.cycle
        xor a
.quest: ld (s+State.quest),a
        jr .select
.cycle: bit 5,a
        jr z,.wait
.increment:ld a,(s+State.quest)
        or a
        ld a,(s+State.stage)
        jr z,.next_stage
        and $1c                 ; Quest 2 selects the next world, always at -1
        add a,3
.next_stage:inc a
        and 31
        ld (s+State.stage),a
        jr .select
restart:call lives_card
        call pipe_intro
.resume:xor a
        ld (s+State.scene),a
        ld (s+State.pipeclip),a
        call input              ; consume edges during the intermission
        call load_stage
play:   call prepare_sprites
        call vblank
        call reveal_sprites
        ld a,(s+State.ready)
        or a
        call nz,flip
        call input
        ld hl,s+State.tick
        inc (hl)
        call gameplay_music
        call pulse_tiles
        call anim_tick
        call clock
        call move_lifts
        call carry_lift
        ld a,(s+State.spring_t)
        or a
        jr z,.free
        call spring_recoil
        jr .moved
.free:  call move_x
        call move_y
.moved:
        ld a,(s+State.kind)
        cp 2
        jr nz,.y_done
        ld a,(s+State.py)
        cp 32
        ld a,16
        jr nc,.above_test
        ld a,40
.above_test:ld b,a
        ld a,(s+State.above)
        or a
        ld a,b
        jr z,.y_set
        ld a,40
.y_set: ld hl,s+State.yview
        cp (hl)
        jr z,.y_done
        ld (hl),a
        call mark
.y_done:
        ld a,(s+State.py)
        cp 191
        jr c,.alive
        ld a,(s+State.above)
        or a
        jp z,pit_death
.alive:
        call collect
        call try_pipe
        call camera
        call update_actors
        call fireball
        ld hl,(s+State.scroll)
        ld a,(s+State.px)
        ld e,a
        ld d,0
        add hl,de
        ld de,14                ; compare leading edge, also for sideways exits
        add hl,de
        ld de,(s+State.goal)
        or a
        sbc hl,de
        jr c,.render
        ld a,(s+State.kind)
        cp 3
        jr nz,.not_axe
        ; Contact with the axe, not an invisible line above the bridge.
        ld a,h
        or a
        jr nz,.render
        ld a,l
        cp 38
        jr nc,.render
        ld a,(s+State.py)
        cp 81
        jr c,.render
        cp 113
        jp c,finish_area
        jr .render
.not_axe:ld a,(s+State.kind)
        cp 1
        jr nz,.side
        ld a,h
        or a
        jr nz,.render
        ld a,l
        cp 30
        jr nc,.render
        ld a,(s+State.above)
        or a
        jr nz,.render
        ld a,(s+State.py)
        cp 156                  ; the stone base is not the pole
        jp c,finish_area
        jr .render
.side:  or a
        jr nz,.underground
        ld a,(s+State.py)
        cp 64                   ; swimmer intersects the two-row pipe mouth
        jr c,.render
        cp 112
        jp c,finish_area
        jr .render
.underground:cp 2
        jp nz,finish_area
        ld a,(s+State.bonus)
        or a
        jp nz,finish_area
        ; In 1-2 the sideways pipe is an exit, not a finish line across
        ; the whole screen. Run over it on the roof to reach the warp pipes.
        ld a,h
        or a
        jr nz,.render
        ld a,l
        cp 32
        jr nc,.render
        ld a,(s+State.above)
        or a
        jr nz,.render
        ld a,(s+State.py)
        cp 80
        jp nc,finish_area
.render:
        ld a,(s+State.dirty)
        or a
        call nz,present_map
        jp play

checkpoint:
        ld a,(s+State.stage)
        add a,a
        add a,a
        ld e,a
        ld d,0
        ld hl,checkpoints
        add hl,de
        ret
load_stage:
        call checkpoint
        ld e,(hl)
        inc hl
        ld b,(hl)
        inc hl
        ld c,(hl)
        inc hl
        ld a,(hl)
        ld (s+State.hundred),a
        ld a,24
        ld (s+State.divider),a
        xor a
        ld (s+State.timer),a
        ld (s+State.outside),a
        ld (s+State.expired),a
        ld (s+State.bonus),a
        ld l,a
        ld h,a
        ld a,(s+State.retry)
        or a
        jr z,.start
        ld h,e
        ld (s+State.entry),hl
        push bc
        call main_area
        pop bc
        ld a,b
        ld (s+State.px),a
        ld a,c
        ld (s+State.py),a
        ret
.start: ld (s+State.entry),hl
main_area:
        ld a,(s+State.stage)
        add a,a
        ld e,a
        ld d,0
        ld hl,stage_list
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
load_area:
        xor a
        ld (s+State.flag_y),a
        ld de,s+State.nextcol
        ld bc,9                 ; column list, spawn list, goal X, environment
        ldir
        ld a,(s+State.stage)
        cp 18                   ; the late first-quest courses use hard objects too
        ld a,(s+State.quest)
        jr c,.difficulty
        ld a,1
.difficulty:ld (s+State.hard),a
        or a
        jr nz,.small_lifts
        ld a,(s+State.kind)
        cp 3
        ld a,48
        jr nz,.lift_width
.small_lifts:ld a,32
.lift_width:ld (s+State.liftwidth),a
        ld a,(s+State.bonus)
        or a
        ld a,1
        jr nz,.backdrop
        ld a,(s+State.stage)
        ld e,a
        ld d,0
        ld hl,stage_sky
        add hl,de
        ld a,(hl)
.backdrop:
        ld b,a
        ld a,(s+State.outside)
        or a
        ld a,b
        jr z,.ink
        ld a,5
.ink:
        out (CTRL),a
        ld a,$87
        out (CTRL),a
        ld a,(s+State.bonus)
        or a
        ld a,2
        jr nz,.palette
        ld a,(s+State.stage)
        ld e,a
        ld d,0
        ld hl,stage_theme
        add hl,de
        ld a,(hl)
.palette:ld b,a
        ld a,(s+State.outside)
        or a
        ld a,b
        jr z,.apply
        ld a,1
.apply: call set_theme
        xor a
        ld hl,(s+State.entry)
        ld (s+State.scroll),hl
        ld (s+State.face),a
        ld (s+State.vy),a
        ld (s+State.immune),a
        ld (s+State.floor),a
        ld (s+State.tick),a
        ld (s+State.vx),a
        ld (s+State.vx+1),a
        ld (s+State.xf),a
        ld (s+State.yf),a
        ld (s+State.vf),a
        ld (s+State.phase),a
        ld (s+State.ready),a
        ld (s+State.yview),a
        ld (s+State.above),a
        ld (s+State.forced),a
        ld (s+State.morph),a
        ld (s+State.duck),a
        ld (s+State.throwing),a
        ld (s+State.star),a
        ld (s+State.star+1),a
        ld (s+State.starvel),a
        ld (liftcount),a
        ld (s+State.spring_t),a
        ld (s+State.spring_y),a
        ld (s+State.speed),a
        ld (s+State.walkphase),a
        ld (s+State.animcount),a
        ld (actors),a
        ld (actors+Actor),a
        ld (item),a
        ld (shot),a
        ld a,24
        ld (s+State.px),a
        ld a,(s+State.kind)
        cp 3
        ld a,96
        jr nz,.spawn_y
        ld a,64                 ; castle entrance staircase
.spawn_y:ld (s+State.py),a
        ld hl,(s+State.entry)
        rept 3
        srl h
        rr l
        endr
        ld de,(s+State.nextcol)
        add hl,de
        ld de,map
        ld b,16
.col:   call unpack
        djnz .col
        ld (s+State.nextcol),hl
        call player_gfx
        ld hl,$3800+184*8
        call address
        ld hl,outdoor_patterns
        ld a,(s+State.kind)
        or a
        jr nz,.land_art
        ld hl,swim_patterns
        jr .upload
.land_art:cp 3
        jr nz,.upload
        ld hl,sprites+(184-24)*8
.upload:ld de,256
        call transfer
        ld a,(s+State.quest)
        or a
        ld hl,sprites+(216-24)*8
        jr z,.walk_art
        ld hl,beetle_art
.walk_art:push hl
        ld hl,$3800+216*8
        call address
        pop hl
        ld de,128
        call transfer
        ; Podoboos occur only in castles, and no castle has jumpsprings.
        ; Borrow two 16x16 patterns for a Buzzy shell and restore the other
        ; bank on every area change (including a change back to Quest 1).
        ld de,sprites+(128-24)*8
        ld hl,sprites+(144-24)*8
        ld a,(s+State.quest)
        or a
        jr z,.env
        ld a,(s+State.kind)
        cp 3
        jr z,.castle_shell
        ld de,beetle_shell
        jr .env
.castle_shell:ld hl,beetle_shell
.env:   push hl
        ld hl,$3800+128*8
        call address
        ex de,hl
        ld de,64
        call transfer
        ld hl,$3800+144*8
        call address
        pop hl
        ld de,64
        call transfer
.music: ld a,(s+State.kind)
        call start_music
        ld a,1
        ld (s+State.dirty),a
        ret
unpack: push bc
        ld c,(hl)
        inc hl
        ld b,(hl)
        inc hl
        push hl
        ld h,b
        ld l,c
        ld bc,12
        ldir
        inc de
        inc de
        inc de
        inc de
        pop hl
        pop bc
        ret
camera: ld a,(s+State.bonus)
        or a
        ret nz
        ; In main-area descriptors the lift list immediately follows the
        ; column pointers. Do not scroll/read a seventeenth tile past the map.
        ld hl,(s+State.nextcol)
        ld de,(s+State.lifts)
        sbc hl,de
        ret nc
        ld a,(s+State.px)
        cp 132
        jr nc,.stream
        cp 124
        ret c
        ld a,(s+State.phase)
        or a
        ret nz
        ld a,8
        ld (s+State.phase),a
        jp mark
.stream:push af
        xor a
        ld (s+State.phase),a
        pop af
        sub 16
        ld (s+State.px),a
        ld hl,(s+State.scroll)
        ld de,16
        add hl,de
        ld (s+State.scroll),hl
        ld hl,map+16
        ld de,map
        ld bc,240
        ldir
        ld hl,(s+State.nextcol)
        call unpack
        ld (s+State.nextcol),hl
        call move_lifts
        ld ix,actors
        ld b,4
.shift: ld a,(ix+Actor.x)
        sub 16
        ld (ix+Actor.x),a
        jr nc,.ok
        ld (ix+Actor.active),0
.ok:    ld de,Actor
        add ix,de
        djnz .shift
mark:   ld a,1
        ld (s+State.dirty),a
        ret

hud_score: db 'MARIO ',0
hud_time: db 'TIME ',0
hud_world: db 'WORLD ',0
start_text: db ' PRESS BUTTON 1 ',0

; Match the pipe under Mario against the original area's warp links.
try_pipe:
        ld a,(s+State.outside)
        or a
        ret nz
        ld a,(s+State.pad)
        bit 1,a
        ret z
        ld a,(s+State.bonus)
        or a
        ret nz
        ld a,(s+State.py)
        add a,16
        ld e,a
        ld a,(s+State.px)
        add a,8
        ld d,a
        call tile_at
        cp $10
        jr z,.left
        cp $11
        ret nz
        ld a,d
        sub 16
        ld d,a
.left:  ld a,d
        and $f0
        ld e,a
        ld d,0
        ld hl,(s+State.scroll)
        add hl,de
        ld a,(s+State.stage)
        cp 1
        jr nz,.lookup
        ld a,h                  ; world X $0b20/$0b60/$0ba0
        cp $0b
        jr nz,.lookup
        ld a,l
        cp $20
        ld a,12                 ; 4-1
        jr z,.warp
        ld a,l
        cp $60
        ld a,8                  ; 3-1
        jr z,.warp
        ld a,l
        cp $a0
        jr nz,.lookup
        ld a,4                  ; 2-1
.warp:  ld (s+State.stage),a
        xor a
        ld (s+State.retry),a
        ld sp,$c400             ; abandon try_pipe and start the warp destination
        jp restart
.lookup:push hl
        ld a,(s+State.stage)
        add a,a
        ld e,a
        ld hl,pipe_list
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        pop bc
.scan:  ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,d
        cp $ff
        ret z
        cp b
        jr nz,.skip
        ld a,e
        cp c
        jr z,.enter
.skip:  ld de,5
        add hl,de
        jr .scan
.enter: ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        push de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (s+State.exitcam),de
        ld a,(hl)
        ld (s+State.exity),a
        ld a,1
        ld (s+State.bonus),a
        ld hl,0
        ld (s+State.entry),hl
        pop hl
        jp load_area

        include "player.asm"
        include "actors.asm"
        include "encounters.asm"
        include "video.asm"
        include "lifts.asm"

pit_death:
        ; Falling into a hole has no upward kick. Park just below the screen.
        ld a,192
        ld (s+State.py),a
        jr died
expired:
        ld a,1
        ld (s+State.expired),a
; KillPlayer / PlayerDeath: stop the world, select small Mario's death pose,
; freeze for TimerControl $ff..$f0, then move without input or collisions.
died:   ld sp,$c400             ; also reachable from nested actor collision
        xor a
        ld (s+State.big),a
        ld (s+State.immune),a
        ld (s+State.star),a
        ld (s+State.star+1),a
        ld a,10
        ld (s+State.forced),a
        ld a,5
        call start_music
        call draw_sprites
        ld a,(s+State.above)
        or a
        jr nz,.hold
        ld a,(s+State.py)
        cp 192
        jr nc,.gone
.hold:  ld b,16
.pause: push bc
        call vblank
        call music_tick
        pop bc
        djnz .pause
        ; NES death velocity -4.00, gravity $28/256, terminal speed +4.
        ; D:E is velocity and C is subpixel Y; keep the signed Y page until
        ; Mario has actually crossed the bottom (never wrap back to the top).
        ld de,$fc00
        ld c,0
.arc:   ld a,c
        add a,e
        ld c,a
        ld hl,s+State.py
        ld a,(hl)
        adc a,d
        ld (hl),a
        ld hl,s+State.above
        bit 7,d
        jr z,.down
        jr c,.step
        ld (hl),1
        jr .step
.down:  jr nc,.page
        ld (hl),0
.page:  bit 0,(hl)
        jr nz,.step
        cp 192
        jr nc,.hide
.step:  ld a,d
        cp 4
        jr z,.draw
        ld a,e
        add a,$28
        ld e,a
        ld a,d
        adc a,0
        ld d,a
.draw:  push bc
        push de
        call vblank
        call music_tick
        call draw_sprites
        pop de
        pop bc
        jr .arc
.hide:  call draw_sprites
.gone:  call finish_song        ; even the last life gets the complete death cue
        ld hl,s+State.lives
        dec (hl)
        call time_up_card
        ld a,(s+State.lives)
        or a
        jr z,.over
        call checkpoint
        ld a,(s+State.scroll+1)
        cp (hl)
        ld a,0
        jr c,.retry
        ld a,(hl)
.retry: ld (s+State.retry),a
        call lives_card
        jp restart.resume
.over:  ld a,4
        ld (s+State.scene),a
        ld a,6
        call start_music
        ld de,over_text
        call message_card
        ; GameOverInter sets ScreenTimer to $12 (18 * 21 video frames).
        ld bc,378
        call game_over_wait
        jp title
finish_area:
        ld a,(s+State.bonus)
        or a
        jr z,clear_stage
        xor a
        ld (s+State.bonus),a
        ld hl,(s+State.exitcam)
        ld (s+State.entry),hl
        call main_area
        ld a,120
        ld (s+State.px),a
        ld a,(s+State.exity)
        ld (s+State.py),a
        jp play
        include "goals.asm"
beetle_shell: incbin "../build/sg1000/beetle_shell.bin"
beetle_art: incbin "../build/sg1000/beetle.bin"
game_over_wait:
.wait:  push bc
        call vblank
        call music_tick
        call input
        ld a,(s+State.edge)
        and $30
        pop bc
        ret nz
        dec bc
        ld a,b
        or c
        jr nz,.wait
        ret
over_text: db '      GAME OVER',0


        include "intermission.asm"
        include "music.asm"
        include "themes.asm"
        align 16
palette_inks: incbin "../build/sg1000/themes.bin"
color_rows: incbin "../build/sg1000/color_rows.bin"
color_ids: incbin "../build/sg1000/color_ids.bin"
color_ids_end:
pulse_colors: incbin "../build/sg1000/pulse.bin"
logo:   incbin "../build/sg1000/title.bin"
patterns: incbin "../build/sg1000/patterns.bin"
patterns_end:
sprites:  incbin "../build/sg1000/sprites.bin",24*8
sprites_end:
outdoor_patterns: incbin "../build/sg1000/outdoor.bin"
swim_patterns: incbin "../build/sg1000/swim.bin"
        align 32                ; mirrored pose uploader selects column via bit 4
mario_data: incbin "../build/sg1000/mario.bin"
        include "../build/sg1000/poses.inc"
        include "../build/sg1000/glyphs.inc"
        align 256
mirror_bits: incbin "../build/sg1000/mirror.bin"
metatiles: incbin "../build/sg1000/meta.bin"
solids: incbin "../build/sg1000/solid.bin"
        include "../build/sg1000/areas.inc"

        assert $ <= $c000
        defs $c000-$,$ff
