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
move_x: ld a,(s+State.pad)
        and $0c
        ld (s+State.speed),a
        ret z
        ld c,1
        bit 2,a
        jr z,.right
        ld c,-1
.right: ld a,c
        and 36
        ld (s+State.face),a
        ld b,2
        ld a,(s+State.pad)
        bit 5,a
        jr z,.step
        inc b
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
        call solid_at
        jr nz,.wall
        ld a,e
        sub 12
        ld e,a
        call solid_at
        jr nz,.wall
        ld a,(s+State.big)
        or a
        jr z,.pass
        ld a,e
        sub 16
        ld e,a
        call solid_at
        jr nz,.wall
.pass:  pop af
        ld (s+State.px),a
        djnz .step
        ret
.wall:  pop af
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
.jump:  ld a,-10
        ld (s+State.vy),a
        ld a,$85
        call effect
.gravity:
        ld a,(s+State.vy)
        ld b,a
        ld a,(s+State.pad)
        bit 4,a
        jr nz,.accel
        ld a,b
        cp -4
        jr nc,.accel
        bit 7,b
        jr z,.accel
        ld b,-4                 ; release jump for a shorter arc
.accel: ld a,(s+State.tick)
        and 1
        jr nz,.velocity
        ld a,b
        cp 7
        jr z,.velocity
        inc b
.velocity:ld a,b
        ld (s+State.vy),a
        or a
        ret z                   ; retain support on the half-gravity tick
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
        cp $ff
        jp z,.stop
        ld e,a
        ld a,(s+State.big)
        or a
        ld a,e
        jr z,.probe
        sub 16
        jp c,.stop
        jr .probe
.feet:  add a,15
.probe: ld e,a
        ld a,(s+State.px)
        add a,2
        ld d,a
        call solid_at
        jr nz,.hit
        ld a,d
        add a,10
        ld d,a
        call solid_at
        jr nz,.hit
        ld a,(s+State.py)
        add a,c
        ld (s+State.py),a
        djnz .pixels
        ret
.hit:   bit 7,c
        jr nz,.head
        ld a,1
        ld (s+State.floor),a
        call tile_at
        cp $68
        jr nz,.stop
        ld a,-17                ; 2-1 spring clears the high wall
        ld (s+State.vy),a
        ret
.head:  call tile_at
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
        jr nz,.stop
.brick:
        ld a,(s+State.big)
        or a
        jr z,.stop
        ld (hl),0
        call mark
        jr .stop
.power: ld a,d
        and $f0
        ld (item+Actor.x),a
        ld a,e
        and $f0
        sub 16
        ld (item+Actor.y),a
        ld a,1
        ld (item+Actor.active),a
        ld (item+Actor.dir),a
        ld a,(s+State.big)
        ld (item+Actor.style),a
        jr .used
.coin:  call earn_coin
.used:  ld (hl),$c4
        call mark
.stop:  xor a
        ld (s+State.vy),a
        ret
collect:ld a,(s+State.px)
        add a,8
        ld d,a
        ld a,(s+State.py)
        add a,8
        ld e,a
        call tile_at
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
.sound: ld a,$82
        jp effect

