; DE = screen pixel X,Y. HL returns the mutable metatile address.
tile_at:ld a,e
        rrca
        rrca
        rrca
        rrca
        and 15
        ld l,a
        ld a,d
        and $f0
        or l
        ld l,a
        ld h,map/256
        ld a,(hl)
        ret
solid_at:
        ld a,e
        cp 192
        jr nc,.empty
        call tile_at
        ld l,a
        ld h,solids/256
        ld a,(hl)
        or a
        ret
.empty: xor a
        ret
player_solid:
        ld a,(s+State.above)
        or a
        jp z,solid_at
        ld a,e
        cp 16                   ; only the feet can wrap back onto row zero
        jp c,solid_at
        xor a
        ret
move_x: ld a,(s+State.big)
        or a
        jr z,.posture
        ld a,(s+State.floor)
        or a
        jr z,.height
        ld a,(s+State.pad)
        and 2
.posture:ld (s+State.duck),a
.height:ld hl,(s+State.vx)
        ld a,(s+State.pad)
        and $0c
        ld c,a
        ld a,(s+State.big)
        or a
        jr z,.input
        ld a,(s+State.pad)
        bit 1,a
        jr z,.input
        ld a,(s+State.floor)
        or a
        jr z,.input
        ld c,0
.input: ld a,c
        or a
        jr nz,.drive
        ld a,(s+State.floor)
        or a
        jr z,.integrate
        ld de,13
        bit 7,h
        jr nz,.slowleft
        or a
        sbc hl,de
        jr nc,.integrate
.zero:  ld hl,0
        jr .integrate
.slowleft:add hl,de
        jr c,.zero
        jr .integrate
.drive: ld de,9                 ; $98 / 16, NES walk acceleration
        ld b,1                  ; speed cap high byte, low byte always $80
        ld a,(s+State.pad)
        bit 5,a
        jr z,.limit
        ld e,14                 ; $e4 / 16, NES run acceleration
        inc b
.limit: ld a,(s+State.kind)
        or a
        jr nz,.land
        ld b,1
.land:  bit 2,c
        jr nz,.left
        xor a
        ld (s+State.face),a
        bit 7,h
        jr z,.right
        sla e                   ; opposing input: skid
.right: add hl,de
        jr .clamp
.left:  ld a,1
        ld (s+State.face),a
        bit 7,h
        jr nz,.acc_left
        sla e
.acc_left:or a
        sbc hl,de
.clamp: bit 7,h
        push af
        call nz,neg_hl
        ld a,h
        cp b
        jr c,.ok
        jr nz,.cap
        bit 7,l
        jr z,.ok
.cap:   ld h,b
        ld l,$80
.ok:    pop af
        call nz,neg_hl
.integrate:ld (s+State.vx),hl
        ld c,1
        bit 7,h
        jr z,.mag
        call neg_hl
        dec c
        dec c
.mag:   ld a,h
        or l
        ld (s+State.speed),a
        ret z
        ld a,(s+State.xf)
        add a,l
        ld (s+State.xf),a
        ld a,h
        adc a,0
        ret z
        ld b,a
.step:  ld a,(s+State.px)
        add a,c
        cp 235
        ret nc
        push af
        inc a
        bit 7,c
        jr nz,.leading
        add a,12
.leading:ld d,a
        ld a,(s+State.py)
        add a,14
        ld e,a
        call player_solid
        jr nz,.wall
        ld a,e
        sub 12
        ld e,a
        call player_solid
        jr nz,.wall
        ld a,(s+State.big)
        or a
        jr z,.pass
        ld a,(s+State.duck)
        or a
        jr nz,.pass
        ld a,e
        sub 16
        ld e,a
        call player_solid
        jr nz,.wall
.pass:  pop af
        ld (s+State.px),a
        djnz .step
        ret
.wall:  pop af
        ld hl,0
        ld (s+State.vx),hl
        ret
neg_hl: xor a
        sub l
        ld l,a
        sbc a,a
        sub h
        ld h,a
        ret
move_y: ld a,(s+State.edge)
        bit 4,a
        jr z,.gravity
        ld a,(s+State.floor)
        or a
        jr nz,.jump
        ld a,(s+State.kind)
        or a
        jr nz,.gravity
.jump:  ld a,(s+State.kind)
        or a
        ld b,-2
        ld de,$0d0a
        jr z,.launch
        ld hl,(s+State.vx)
        bit 7,h
        call nz,neg_hl
        ld de,$2070
        ld b,-4
        ld a,h
        or a
        jr z,.launch
        ld de,$1e60
        cp 1
        jr z,.launch
        ld de,$2890
        dec b
.launch:ld a,d
        ld (s+State.rise),a
        ld a,e
        ld (s+State.fall),a
        xor a
        ld (s+State.floor),a
        ld (s+State.vf),a
        ld (s+State.yf),a
        ld a,b
        ld (s+State.vy),a
.gravity:ld a,(s+State.fall)
        or a
        jr nz,.fall_g
        ld a,$70
.fall_g:ld c,a
        ld a,(s+State.vy)
        bit 7,a
        jr z,.accel
        ld a,(s+State.pad)
        bit 4,a
        jr z,.accel
        ld a,(s+State.rise)
        or a
        jr z,.accel
        ld c,a
.accel: ld a,(s+State.vf)
        add a,c
        ld (s+State.vf),a
        ld a,(s+State.vy)
        adc a,0
        cp 5
        jr c,.velocity
        bit 7,a
        jr nz,.velocity
        ld a,4
.velocity:ld (s+State.vy),a
        ld b,a
        ld a,(s+State.yf)
        ld hl,s+State.vf
        add a,(hl)
        ld (s+State.yf),a
        ld a,b
        adc a,0
        ret z
        ld b,a
        xor a
        ld (s+State.floor),a
        ld a,b
        or a
        ld c,1
        jp p,.pixels
        neg
        ld b,a
        ld c,-1
.pixels:ld a,(s+State.py)
        add a,c
        bit 7,c
        jr z,.feet
        ld e,a
        ld a,(s+State.duck)
        or a
        ld a,e
        jr nz,.probe
        ld a,(s+State.big)
        or a
        ld a,e
        jr z,.probe
        sub 16
        jr .probe
.feet:  push bc
        push af
        call on_lift
        pop de                  ; proposed top in D
        pop bc
        jp c,.landed
        ld a,d
        add a,15
.probe: ld e,a
        ld a,(s+State.px)
        add a,2
        ld d,a
        call player_solid
        jr nz,.hit
        ld a,d
        add a,10
        ld d,a
        call player_solid
        jr nz,.hit
        ld a,(s+State.py)
        add a,c
        ld (s+State.py),a
        bit 7,c
        jr z,.down
        cp $ff
        jr nz,.again
        ld a,1
        ld (s+State.above),a
        jr .again
.down:  or a
        jr nz,.again
        ld (s+State.above),a
.again: djnz .pixels
        ret
.hit:   bit 7,c
        jr nz,.head
        ld a,1
        ld (s+State.floor),a
        call tile_at
        cp $68
        jr nz,.stop
        ld a,-9                ; 2-1 spring clears the high wall
        ld (s+State.vy),a
        ret
.head:  call tile_at
        cp $57
        jr z,.power
        cp $c1
        jr z,.power
        cp $55
        jr z,.power
        cp $c0
        jr z,.coin
        cp $58
        jr z,.coin
        cp $51
        jr z,.brick
        cp $52
        jr z,.brick
        cp $8c
        jr nz,.stop
.brick:
        ld a,(s+State.big)
        or a
        jr z,.stop
        ld (hl),0
        call mark
        jr .stop
.power: ld c,a
        ld a,d
        and $f0
        ld (item+Actor.x),a
        ld a,e
        and $f0
        sub 16
        ld (item+Actor.y),a
        ld a,1
        ld (item+Actor.active),a
        ld (item+Actor.dir),a
        ld a,c
        cp $57
        ld a,3
        jr z,.item
        ld a,(s+State.big)
.item:  ld (item+Actor.style),a
        ld a,-3
        ld (s+State.starvel),a
        jr .used
.coin:  call earn_coin
.used:  ld (hl),$c4
        call mark
        jr .stop
.landed:ld a,1
        ld (s+State.floor),a
.stop:  xor a
        ld (s+State.vf),a
        ld (s+State.yf),a
        ld (s+State.vy),a
        ret
collect:ld a,(s+State.above)
        or a
        ret nz
        ld a,(s+State.px)
        add a,8
        ld d,a
        ld a,(s+State.py)
        add a,8
        ld e,a
        call tile_at
        cp $8a
        jp z,died
        cp $8b
        jp z,died
        cp $c2
        ret nz
        ld (hl),0
        call mark
earn_coin:
        push hl
        ld a,2
        call points
        pop hl
        ld a,(s+State.coins)
        add a,1
        daa
        ld (s+State.coins),a
        jr nc,.sound
        ld a,(s+State.lives)
        cp 9
        jr z,.sound
        inc a
        ld (s+State.lives),a
.sound: ret

