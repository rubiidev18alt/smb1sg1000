; The 9918 has no scroll registers. Compose a fresh name table in the
; other VRAM page, then swap it in as a unit at vertical blank.
present_map:
        call redraw
        call hud
        call vblank
flip:   ld a,(s+State.back)
        out (CTRL),a
        ld a,$82
        out (CTRL),a
        ld a,(s+State.back)
        xor 1
        ld (s+State.back),a
        xor a
        ld (s+State.dirty),a
        ret
redraw: ld hl,$1800
        call back_address
        ld c,0
.row:   ld d,map/256
        ld e,c
        ld h,metatiles/256
        call half_row
        ld e,c
        ld h,metatiles/256+2
        call half_row
        inc c
        ld a,c
        cp 12
        jr nz,.row
        ret
half_row:
        ld b,16
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
hud:    ld hl,$1801
        ld de,hud_world
        call text
        ld a,(s+State.stage)
        rrca
        rrca
        and 7
        inc a
        out (VDP),a
        ld a,36
        nop
        nop
        nop
        out (VDP),a
        ld a,(s+State.stage)
        and 3
        inc a
        out (VDP),a
        ld hl,$180d
        ld de,hud_coins
        call text
        ld a,(s+State.coins)
        rrca
        rrca
        rrca
        rrca
        and 15
        out (VDP),a
        ld a,(s+State.coins)
        and 15
        out (VDP),a
        ld hl,$1818
        ld de,hud_lives
        call text
        ld a,(s+State.lives)
        out (VDP),a
        ld hl,$1821
        ld de,hud_score
        call text
        ld a,(s+State.scorehi)
        call digits
        ld a,(s+State.scorelo)
        call digits
        xor a
        call digits
        ld hl,$1836
        ld de,hud_time
        call text
        ld a,(s+State.hundred)
        out (VDP),a
        ld a,(s+State.timer)
        jp digits
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

draw_sprites:
        ld hl,sat
        ld a,(s+State.immune)
        and 4
        jr nz,.others
        ld a,(s+State.face)
        ld b,a
        ld a,(s+State.vy)
        or a
        jr z,.walk
        ld a,24
        jr .frame
.walk:  ld a,(s+State.speed)
        or a
        jr z,.frame
        ld a,(s+State.tick)
        and 4
        jr z,.frame
        ld a,12
.frame: add a,b
        ld c,a
        ld a,(s+State.px)
        ld d,a
        ld a,(s+State.py)
        dec a                   ; 9918 sprite Y is one scanline early
        ld e,a
        ld a,(s+State.big)
        or a
        jr z,.player
        ld a,e
        sub 16
        ld e,a
        call player_layers
        ld a,e
        add a,16
        ld e,a
        ld a,c
        add a,64                ; previous call advanced pattern by 8
        ld c,a
.player:call player_layers
.others:ld ix,actors
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
        push hl
        ld hl,$1b00
        call address
        pop de
        ld hl,sat
        jp transfer
player_layers:
        ld b,8                  ; fire suit substitutes white for cap/overalls
        ld a,(s+State.big)
        cp 2
        jr nz,.cap
        ld b,15
.cap:
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
layer:  ld (hl),e
        inc hl
        ld (hl),d
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
        cp 240
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
        ld c,144
        jr nz,.anim
        ld c,216
        ld b,6
.anim:  ld a,(s+State.tick)
        and 8
        add a,c
        ld c,a
        jr .pair
.fish:  ld b,8
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
        add a,17
        ld e,a
        ld b,15
        ld c,244
        jp layer
