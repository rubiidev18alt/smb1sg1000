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
        ld a,d
        cp $ff
        jr z,.notyet
        bit 7,d
        jr z,.position
        res 7,d
        ld a,(s+State.quest)
        or a
        jr nz,.position
        ld a,(s+State.stage)
        cp 18                   ; secondary hard mode starts at 5-3
        jr c,.consume
.position:ex de,hl
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
        cp 3
        jp z,.star_move
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
        jr z,.run
        ld a,(s+State.quest)
        or a
        jr z,.fall
.run:
        ld a,(ix+Actor.dir)
        add a,(ix+Actor.x)
        bit 7,(ix+Actor.dir)
        jr z,.right_bound
        jr nc,.turn             ; underflow, not a foe entering from the right
        jr .inside
.right_bound:jr c,.turn
        cp 241
        jr nc,.turn
.inside:ld b,a
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
        jr .touch
.star_move:
        ld a,(ix+Actor.dir)
        add a,(ix+Actor.x)
        ld (ix+Actor.x),a
        ld a,(s+State.tick)
        and 3
        jr nz,.bounce
        ld hl,s+State.starvel
        ld a,(hl)
        cp 4
        jr z,.bounce
        inc (hl)
.bounce:ld a,(s+State.starvel)
        add a,(ix+Actor.y)
        ld b,a
        ld d,(ix+Actor.x)
        add a,15
        ld e,a
        call solid_at
        jr z,.rise
        ld a,-4
        ld (s+State.starvel),a
        jr .touch
.rise:  ld (ix+Actor.y),b
        jr .touch
.touch: ld a,(s+State.above)
        or a
        ret nz
        ld a,(s+State.px)
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
        ld hl,(s+State.star)
        ld a,h
        or l
        jr z,.vulnerable
        ld a,2
        call points
        jr .remove
.vulnerable:
        ld a,(s+State.kind)
        or a
        jp z,.hurt              ; underwater enemies cannot be stomped
        ld a,(ix+Actor.style)
        cp 8
        jp z,.hurt
        cp 12
        jp nc,.hurt
        cp 2
        jr z,.kick
        ld a,(s+State.vy)
        bit 7,a
        jp nz,.hurt
        ld a,b
        cp 10
        jr nc,.hurt
        ld a,-6
        ld (s+State.vy),a
        ld a,1
        call points
        ld a,(ix+Actor.style)
        or a
        jr nz,.koopa
        ld a,(s+State.quest)
        or a
        jr nz,.shell
        jr .remove
.koopa: cp 1
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
.grow:  ld a,(ix+Actor.style)
        cp 3
        jr nz,.size
        push ix
        ld a,4
        call start_music
        pop ix
        ld hl,600
        ld (s+State.star),hl
        jr .remove
.size:  ld a,(s+State.big)
        cp 2
        jr z,.grown
        inc a
.grown:
        ld (s+State.big),a
        ld a,24
        ld (s+State.morph),a
        ld a,$10
        call points
        call player_gfx
        jr .remove
.hurt:
hurt_player: ld hl,(s+State.star)
        ld a,h
        or l
        ret nz
        ld a,(s+State.immune)
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
