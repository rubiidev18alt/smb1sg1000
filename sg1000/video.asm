; The 9918 has no scroll registers. Compose a fresh name table in the
; other VRAM page, then swap it in as a unit at vertical blank.
present_map:
        call redraw
        call hud
        ld a,1
        ld (s+State.ready),a
        ret
flip:   ld a,(s+State.back)
        out (CTRL),a
        ld a,$82
        out (CTRL),a
        ld a,$c2                ; show the fully composed area after a palette swap
        out (CTRL),a
        ld a,$81
        out (CTRL),a
        ld a,(s+State.back)
        xor 1
        ld (s+State.back),a
        xor a
        ld (s+State.dirty),a
        ld (s+State.ready),a
        ret
redraw: ; Reserve one blank overscan row plus two HUD rows. Do not draw
        ; the first 96 world tiles only to overwrite them immediately.
        ld hl,$1860
        call back_address
        ld a,(s+State.yview)
        rrca
        rrca
        rrca
        ld b,a
        ld a,3
        sub b
        ld ixh,21
        jr nc,.start
        neg
        ld c,a
.clear_row:ld b,32
        ld a,36
.clear: out (VDP),a
        nop
        nop
        djnz .clear
        dec ixh
        dec c
        jr nz,.clear_row
        xor a
.start: ld ixl,a
.row:   ld a,ixl
        srl a
        ld c,a
        ld e,a
        ld d,map/256
        ld h,metatiles/256
        jr nc,.half
        inc h
        inc h
.half:  call half_row
        inc ixl
        dec ixh
        jr nz,.row
        ret
half_row:
        ld b,16
        ld a,(s+State.phase)
        or a
        jr z,.tile
        ld a,(de)
        ld l,a
        inc h
        ld a,(hl)
        out (VDP),a
        dec h
        ld a,e
        add a,16
        ld e,a
        dec b
.tile:  ld a,(de)
        ld l,a
        ld a,(hl)
        out (VDP),a
        inc h
        nop
        nop                     ; space active-display VDP writes >= 29 T
        ld a,(hl)
        out (VDP),a
        dec h
        ld a,e
        add a,16
        ld e,a
        djnz .tile
        ld a,(s+State.phase)
        or a
        ret z
        push hl
        ld hl,(s+State.nextcol)
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        add hl,bc               ; B=0, C=row
        ld a,(hl)
        pop hl
        ld d,map/256            ; the bottom half-row reuses the map page
        ld l,a
        ld a,(hl)
        out (VDP),a
        ret
back_address:
        ld a,(s+State.back)
        and 1
        add a,a
        add a,a
        or h
        ld h,a
        jp address
text:   call back_address
.char:  ld a,(de)
        or a
        ret z
        inc de
        cp ' '
        jr nz,.letter
        ld a,36
        jr .emit
.letter:cp 'A'
        jr nc,.alpha
        sub '0'
        jr .emit
.alpha: sub 'A'-10
.emit:  out (VDP),a
        jr .char
hud:    ld hl,$1800
        call back_address
        ld b,96
        ld a,36
.clear: out (VDP),a
        nop
        nop
        djnz .clear
        ld hl,$1822
        ld de,hud_score
        call text
        ld hl,$1832
        ld de,hud_world
        call text
        ld hl,$183a
        ld de,hud_time
        call text
        ld hl,$1842
        call back_address
        ld a,(s+State.scorehi)
        call digits
        ld a,(s+State.scorelo)
        call digits
        xor a
        call digits
        ld hl,$184b
        call back_address
        ld a,HUD_COIN
        out (VDP),a
        ld a,33                 ; X
        nop
        nop
        nop
        out (VDP),a
        ld a,(s+State.coins)
        call digits
        ld hl,$1853
        call back_address
        call stage_digits
        ld hl,$185b
        call back_address
        ld a,(s+State.hundred)
        out (VDP),a
        ld a,(s+State.timer)
        jp digits
selector_label:
        ld hl,$1a46             ; write only selector text on the visible page
        ld a,(s+State.back)
        xor 1
        ld (s+State.back),a
        ld de,select_prompt
        call text
        call stage_digits
        ld hl,$1853
        call back_address
        call stage_digits
        ld a,(s+State.back)
        xor 1
        ld (s+State.back),a
        ret
select_prompt: db 'BUTTON 2  WORLD ',0
stage_digits:
        ld a,(s+State.stage)
        rrca
        rrca
        and 7
        inc a
        out (VDP),a
        ld a,DASH
        nop
        nop
        nop
        out (VDP),a
        ld a,(s+State.stage)
        and 3
        inc a
.write: out (VDP),a
        ret
; Source is one packed BCD byte.
digits: ld b,a
        rrca
        rrca
        rrca
        rrca
        and 15
        out (VDP),a
        ld a,b
        and 15
        nop
        nop
        out (VDP),a
        ret
points: ld hl,s+State.scorelo
        add a,(hl)
        daa
        ld (hl),a
        ret nc
        inc hl
        ld a,(hl)
        add a,1
        daa
        ld (hl),a
        ret
clock:  ld hl,s+State.divider
        dec (hl)
        ret nz
        ld (hl),24
        ld a,(s+State.timer)
        sub 1
        daa
        ld (s+State.timer),a
        jr nc,.test
        ld hl,s+State.hundred
        dec (hl)
.test:  ld hl,s+State.hundred
        or (hl)
        jp z,died
        jp mark

draw_sprites:call prepare_sprites
reveal_sprites:
        ld a,(s+State.satpage)
        add a,a
        or $36
        out (CTRL),a
        ld a,$85
        out (CTRL),a
        ret
prepare_sprites:
        call animate_mario
        ld hl,sat
        ld a,(s+State.immune)
        and 4
        jr nz,.others
        ld a,(s+State.px)
        ld d,a
        ld a,(s+State.py)
        dec a
        ld e,a
        ld a,(s+State.posetab)
        add a,12
        ld c,a
        ld a,(s+State.tall)
        or a
        jr z,.player
        ld a,e
        sub 16
        ld e,a
        ld a,(s+State.posetab)
        ld c,a
        call player_layers
        ld a,e
        add a,16
        ld e,a
        ld a,(s+State.posetab)
        add a,12
        ld c,a
.player:call player_layers
.others:call lift_sprites
        ld ix,actors
        call enemy_sprite
        ld ix,actors+Actor
        call enemy_sprite
        ld a,(item+Actor.active)
        or a
        jr z,.end
        ld a,(item+Actor.x)
        ld d,a
        ld a,(item+Actor.y)
        dec a
        ld e,a
        ld c,232
        ld a,(item+Actor.style)
        or a
        jr z,.mushroom
        cp 3
        ld c,88
        jr z,.mushroom
        ld c,176
.mushroom:ld b,8
        call layer
        ld a,c
        add a,4
        ld c,a
        ld b,15
        call layer
.end:   call pennant
        ld a,(shot+Actor.active)
        or a
        jr z,.submit
        ld a,(shot+Actor.x)
        ld d,a
        ld a,(shot+Actor.y)
        ld e,a
        ld c,240
        ld b,11
        call layer
.submit:ld (hl),$d0
        inc hl
        ld de,sat
        or a
        sbc hl,de
        ld b,l
        ld a,(s+State.satpage)
        xor 4
        ld (s+State.satpage),a
        or $1b
        ld h,a
        ld l,0
        call address
        ld hl,sat
; Active-display transfers must leave at least 29 T-states between writes.
short_upload:
        ld c,VDP
.copy:  outi
        nop
        jp nz,.copy
        ret
player_layers:
        ld b,8                  ; fire suit substitutes white for cap/overalls
        ld a,(s+State.big)
        cp 2
        jr nz,.cap
        ld b,15
.cap:   ld a,(s+State.star)
        ld iyl,a
        ld a,(s+State.star+1)
        or iyl
        jr z,.skin
        ld a,(s+State.tick)
        rrca
        and 7
        add a,7
        ld b,a
.skin:
        call layer
        inc c
        inc c
        inc c
        inc c
        ld b,11
        call layer
        inc c
        inc c
        inc c
        inc c
        ld b,1
layer:  ld a,(s+State.yview)
        add a,e
        cp $d0                  ; reserved SAT terminator, hide clipped layers
        ret z
        ld (hl),a
        inc hl
        ld a,(s+State.phase)
        or a
        ld a,d
        jr z,.x
        sub 8
        jr nc,.x
        add a,32
        ld (hl),a
        inc hl
        ld (hl),c
        inc hl
        ld a,b
        or $80
        ld (hl),a
        inc hl
        ret
.x:     ld (hl),a
        inc hl
        ld (hl),c
        inc hl
        ld (hl),b
        inc hl
        ret
enemy_sprite:
        ld a,(ix+Actor.active)
        or a
        ret z
        ld d,(ix+Actor.x)
        ld e,(ix+Actor.y)
        dec e
        ld a,(ix+Actor.style)
        cp 14
        jp z,blooper_sprite
        cp 7
        jr c,.ordinary
        sub 7
        add a,a
        push hl
        ld hl,special_art
        add a,l
        ld l,a
        jr nc,.art
        inc h
.art:   ld c,(hl)
        inc hl
        ld b,(hl)
        pop hl
        ld a,c
        cp 128
        jr nz,.special
        bit 5,(ix+Actor.dir)
        jr z,.pair
        ld c,136
        jr .pair
.special:cp 240
        jp z,layer
        jp .pair
.ordinary:cp 5
        jp nc,hazard_sprite
        ld b,12
        cp 4
        ld c,168
        jr z,.fish
        cp 2
        ld c,160
        jr nc,.pair
        or a
        jp nz,koopa_sprite
        ld c,216
        ld a,(s+State.kind)
        cp 2
        ld b,6
        jr nz,.anim
        ld b,4
.anim:  ld a,(s+State.tick)
        and 8
        add a,c
        ld c,a
        jr .pair
.fish:  ld a,(s+State.tick)
        and 8
        ld c,168
        jr z,.fish_color
        ld c,208
.fish_color:ld b,14
        ld a,(s+State.stage)
        cp 5
        jr z,.mix
        ld b,8                  ; reverse gray/red predominance in 7-2
.mix:   ld a,(ix+Actor.y)       ; deterministic variant for this swimming lane
        and $30
        cp $30
        jr nz,.fish_ink
        ld a,b
        xor 6                   ; swap TMS gray (14) and red (8)
        ld b,a
.fish_ink:call layer
        ld a,c
        add a,4
        ld c,a
        ld b,15
        jp layer
.pair:  call layer
        ld a,c
        add a,4
        ld c,a
        ld b,11
        jp layer


; Emit the flag only when its column is visible (not inside a bonus room).
pennant:
        ld a,(s+State.kind)
        cp 1
        ret nz
        push hl
        ld hl,(s+State.goal)
        ld de,(s+State.scroll)
        or a
        sbc hl,de
        ld a,h
        or a
        ld d,l
        pop hl
        ret nz
        ld a,d
        sub 8
        ret c
        ld d,a
        ld a,(s+State.flag_y)
        add a,32
        ld e,a
        ld b,15
        ld c,244
        call layer
        ld b,12
        ld c,248
        jp layer

; All four NES Koopa 8x16 pieces, including the head above its hitbox.
koopa_sprite:
        ld c,24
        bit 7,(ix+Actor.dir)
        jr z,.frame
        ld c,56
.frame: ld a,(s+State.tick)
        and 8
        add a,c
        ld c,a
        ld a,e
        sub 16
        ld e,a
        call .half
        ld a,c
        add a,12
        ld c,a
        ld a,e
        add a,16
        ld e,a
.half:  ld a,(s+State.kind)
        cp 2
        ld b,12
        jr nz,.shell_ink
        ld b,4
.shell_ink:call layer
        ld a,c
        add a,4
        ld c,a
        ld b,11
        jp layer

; Pulse coin and question-block inks, one of the three VRAM banks on each
; successive frame. No tilemap redraw and no writes to the music hardware.
pulse_tiles:
        ld a,(s+State.tick)
        and 7
        cp 3
        ret nc
        add a,a
        add a,a
        add a,a
        add a,$20+PULSE_OFFSET/256
        ld h,a
        ld l,PULSE_OFFSET%256
        call address
        ld a,(s+State.tick)
        rrca
        rrca
        rrca
        and 1
        ld hl,pulse_light
        ld de,PULSE_BYTES
        jr z,.upload
        ld hl,pulse_dark
.upload:jp transfer

; Water-bank patterns 184..207 hold the two-part extended squid and the
; contracted pose. Both use the original mirrored left/right CHR halves.
blooper_sprite:
        ld a,(ix+Actor.dir)
        and 32
        ld c,200
        jr nz,.half
        ld c,184
        ld a,e
        sub 16
        ld e,a
        call .half
        ld a,e
        add a,16
        ld e,a
        ld c,192
.half:  ld b,15
        call layer
        inc c
        inc c
        inc c
        inc c
        ld b,1
        jp layer
