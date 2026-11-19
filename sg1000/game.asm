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
back    byte                    ; name table register: 6 or 7
dirty   byte
sfx     word
song    word
phrase  word
beat    byte
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
        ends
s       equ $c100
        struct Actor
active  byte
x       byte
y       byte
dir     byte
style   byte
        ends
actors  equ $c140                ; two walkers + one mushroom
item    equ actors+2*Actor
shot    equ item+Actor
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
        ld hl,$2000
        ld de,colors
        call three_banks
        ld hl,$3800
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
        ld de,colors-patterns
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
silence:ld hl,0
        ld (s+State.sfx),hl
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
        ld (s+State.retry),a
        ld (s+State.scorelo),a
        ld (s+State.scorehi),a
        ld (s+State.coins),a
        ld (s+State.big),a
        ld a,3
        ld (s+State.lives),a
        ld a,6
        ld (s+State.back),a
        call load_stage
        call redraw
        ld hl,$1845
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
        call wait_button
restart:call load_stage
play:   call vblank
        call input
        ld hl,s+State.tick
        inc (hl)
        call audio
        call clock
        call move_x
        call move_y
        ld a,(s+State.py)
        cp 191
        jp nc,died
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
        jp nc,finish_area
        ld a,(s+State.dirty)
        or a
        call nz,present_map
        call draw_sprites
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
        ld bc,7                 ; column list, spawn list, goal X, environment
        ldir
        ld a,(s+State.kind)
        ld e,a
        ld d,0
        ld hl,sky
        add hl,de
        ld a,(hl)
        out (CTRL),a
        ld a,$87
        out (CTRL),a
        xor a
        ld hl,(s+State.entry)
        ld (s+State.scroll),hl
        ld (s+State.face),a
        ld (s+State.vy),a
        ld (s+State.immune),a
        ld (s+State.floor),a
        ld (s+State.tick),a
        ld (s+State.beat),a
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
        cp 3
        jr nz,.upload
        ld hl,sprites+184*8
.upload:ld de,256
        call transfer
        ld a,(s+State.kind)
        call start_music
        ld a,1
        ld (s+State.dirty),a
        ret
sky:    db 5,4,1,1
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
        ld a,(s+State.px)
        cp 132
        ret c
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

wait_button:
        call vblank
        call input
        and $30
        jr nz,wait_button
.wait:  call vblank
        call input
        and $30
        jr z,.wait
        ret
hud_score: db 'MARIO ',0
hud_time: db 'TIME ',0
hud_world: db 'WORLD ',0
hud_coins: db 'COINS ',0
hud_lives: db 'LIVES ',0
start_text: db ' PRESS BUTTON 1 ',0

; Match the pipe under Mario against the original area's warp links.
try_pipe:
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
        push hl
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

slide_pole:
        ld b,68
.slide: push bc
        call vblank
        ld hl,s+State.flag_y
        inc (hl)
        inc (hl)
        ld a,(s+State.py)
        cp 144
        jr nc,.draw
        inc a
        inc a
        ld (s+State.py),a
.draw:  call draw_sprites
        pop bc
        djnz .slide
        ret

        include "player.asm"
        include "actors.asm"
        include "encounters.asm"
        include "video.asm"
        include "audio.asm"

died:   ld sp,$c400             ; also reachable from nested actor collision
        xor a
        ld (s+State.big),a
        call checkpoint
        ld a,(s+State.scroll+1)
        cp (hl)
        jr c,.life
        ld a,(hl)
        ld (s+State.retry),a
.life:  ld hl,s+State.lives
        dec (hl)
        ld de,lost_text
        ld a,4
        jr nz,.retry
        inc a
        ld de,over_text
        call banner
        jp title
.retry: call banner
        jp restart
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
clear_stage:
        xor a
        ld (s+State.retry),a
        ld a,(s+State.kind)
        cp 1
        call z,slide_pole
        ld a,$10
        call points
        ld hl,s+State.stage
        inc (hl)
        ld a,(hl)
        cp 32
        ld de,clear_text
        ld a,6
        jr c,.next
        inc a
        ld de,win_text
        call banner
        jp title
.next:  ld a,(s+State.kind)
        cp 3
        ld a,6
        jr nz,.course
        ld a,8
.course:call banner
        jp restart
banner: push de
        call start_music
        call silence
        call redraw
        pop de
        ld hl,$1926
        call text
        ld hl,$1988
        ld de,start_text
        call text
        call vblank
        call flip
.release:call vblank
        call audio
        call input
        and $30
        jr nz,.release
.press: call vblank
        call audio
        call input
        and $30
        jr z,.press
        ret
lost_text: db '     TRY AGAIN     ',0
over_text: db '     GAME OVER     ',0
clear_text: db '   COURSE CLEAR    ',0
win_text: db ' PEACH IS RESCUED  ',0

logo:   incbin "../build/sg1000/title.bin"
patterns: incbin "../build/sg1000/patterns.bin"
colors:   incbin "../build/sg1000/colors.bin"
sprites:  incbin "../build/sg1000/sprites.bin"
sprites_end:
outdoor_patterns: incbin "../build/sg1000/outdoor.bin"
super_patterns: incbin "../build/sg1000/super.bin"
        align 256
metatiles: incbin "../build/sg1000/meta.bin"
solids: incbin "../build/sg1000/solid.bin"
        include "../build/sg1000/areas.inc"
        include "../build/sg1000/music.inc"
        assert $ <= $c000
        defs $c000-$,$ff
