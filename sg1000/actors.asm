update_actors:
        ld hl,s+State.immune
        ld a,(hl)
        or a
        jr z,.spawn
        dec (hl)
.spawn: ld hl,(s+State.spawn)
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld b,(hl)
        inc hl
        push hl
        ex de,hl
        ld de,(s+State.scroll)
        or a
        sbc hl,de
        jr c,.consume
        ld a,h
        or a
        jr nz,.notyet
        ld ix,actors
        ld a,(ix+Actor.active)
        or a
        jr z,.allocate
        ld ix,actors+Actor
        ld a,(ix+Actor.active)
        or a
        jr nz,.consume
.allocate:
        ld (ix+Actor.active),1
        ld (ix+Actor.dir),-1
        ld (ix+Actor.x),l
        ld a,b
        and 15
        ld (ix+Actor.style),a
        ld a,b
        and $f0
        ld (ix+Actor.y),a
.consume:pop hl
        ld (s+State.spawn),hl
        jr .walk
.notyet:pop hl
.walk:  ld ix,actors
        call walker
        ld ix,actors+Actor
        call walker
        call shell_hits
        ld ix,item
walker: ld a,(ix+Actor.active)
        or a
        ret z
        push ix
        pop hl
        ld de,item
        or a
        sbc hl,de
        jr nz,.enemy
        ld a,(ix+Actor.style)
        or a
        jr nz,.fall
        jr .normal
.enemy: ld a,(ix+Actor.style)
        cp 7
        jp nc,special_actor
        cp 5
        jp nc,hazard
        cp 2
        jr z,.fall
        cp 3
        jr z,.run
.normal:ld a,(s+State.tick)
        and 1
        jr nz,.fall
.run:
        ld a,(ix+Actor.dir)
        add a,(ix+Actor.x)
        cp 241
        jr nc,.turn
        ld b,a
        ld d,a
        bit 7,(ix+Actor.dir)
        jr nz,.side
        add a,14
        ld d,a
.side:  ld a,(ix+Actor.y)
        add a,13
        ld e,a
        call solid_at
        jr nz,.turn
        ld (ix+Actor.x),b
        jr .fall
.turn:  ld a,(ix+Actor.dir)
        neg
        ld (ix+Actor.dir),a
.fall:  ld a,(ix+Actor.style)
        cp 4
        jr z,.touch
        ld b,3
.drop:  ld a,(ix+Actor.x)
        add a,8
        ld d,a
        ld a,(ix+Actor.y)
        add a,16
        ld e,a
        call solid_at
        jr nz,.touch
        inc (ix+Actor.y)
        ld a,(ix+Actor.y)
        cp 191
        jp nc,.remove
        djnz .drop
.touch: ld a,(s+State.px)
        sub (ix+Actor.x)
        add a,12
        cp 25
        ret nc
        ld a,(s+State.py)
        sub (ix+Actor.y)
        add a,15
        ld b,a
        ld a,(s+State.big)
        or a
        ld a,b
        jr z,.small
        cp 46
        jr .overlap
.small: cp 30
.overlap:ret nc
        push ix
        pop hl
        ld de,item
        or a
        sbc hl,de
        jr z,.grow
        ld a,(ix+Actor.style)
        cp 8
        jr z,.hurt
        cp 12
        jr z,.hurt
        cp 2
        jr z,.kick
        ld a,(s+State.vy)
        bit 7,a
        jr nz,.hurt
        ld a,b
        cp 10
        jr nc,.hurt
        ld a,-6
        ld (s+State.vy),a
        ld a,1
        call points
        ld a,$8a
        call effect
        ld a,(ix+Actor.style)
        cp 1
        jr z,.shell
        cp 3
        jr nz,.remove
.shell: ld (ix+Actor.style),2
        ret
.kick:  ld (ix+Actor.style),3
        ld c,3
        ld a,(s+State.px)
        cp (ix+Actor.x)
        jr c,.away
        ld c,-3
.away:  ld (ix+Actor.dir),c
        ld a,c
        add a,a
        add a,a
        add a,(ix+Actor.x)
        ld (ix+Actor.x),a
        ld a,12
        ld (s+State.immune),a
        ret
.remove:ld (ix+Actor.active),0
        ret
.grow:  ld a,(s+State.big)
        cp 2
        jr z,.grown
        inc a
.grown:
        ld (s+State.big),a
        ld a,$10
        call points
        call player_gfx
        ld a,$83
        call effect
        jr .remove
.hurt:
hurt_player: ld a,(s+State.immune)
        or a
        ret nz
        ld a,(s+State.big)
        or a
        jp z,died
        xor a
        ld (s+State.big),a
        call player_gfx
        ld a,96
        ld (s+State.immune),a
        ret

; A kicked shell can clear the other enemy slot.
shell_hits:
        ld ix,actors
        ld iy,actors+Actor
        ld a,(ix+Actor.style)
        cp 3
        jr z,.pair
        ld ix,actors+Actor
        ld iy,actors
        ld a,(ix+Actor.style)
        cp 3
        ret nz
.pair:  ld a,(ix+Actor.active)
        and (iy+Actor.active)
        ret z
        ld a,(iy+Actor.style)
        cp 5
        ret z
        cp 6
        ret z
        ld a,(ix+Actor.x)
        sub (iy+Actor.x)
        add a,13
        cp 27
        ret nc
        ld a,(ix+Actor.y)
        sub (iy+Actor.y)
        add a,13
        cp 27
        ret nc
        ld (iy+Actor.active),0
        ld a,2
        jp points
