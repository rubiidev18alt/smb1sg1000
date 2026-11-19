        include "animation.asm"

; Fire suit: button 2 launches one bouncing shot, also usable while running.
fireball:
        ld a,(shot+Actor.active)
        or a
        jr nz,.travel
        ld a,(s+State.big)
        cp 2
        ret nz
        ld a,(s+State.edge)
        and $20
        ret z
        ld a,1
        ld (shot+Actor.active),a
        ld a,9
        ld (s+State.throwing),a
        ld a,(s+State.py)
        ld (shot+Actor.y),a
        ld a,(s+State.px)
        ld (shot+Actor.x),a
        ld a,(s+State.face)
        or a
        ld a,4
        jr z,.shoot
        neg
.shoot: ld (shot+Actor.dir),a
        ld a,2
        ld (shot+Actor.style),a ; signed vertical speed
.travel: ld a,(shot+Actor.dir)
        ld b,a
        ld a,(shot+Actor.x)
        add a,b
        cp 240
        jp nc,.end
        ld (shot+Actor.x),a
        add a,8
        ld d,a
        ld a,(shot+Actor.y)
        add a,7
        ld e,a
        call solid_at
        jr nz,.end
        ld hl,shot+Actor.style
        ld a,(s+State.tick)
        and 1
        jr nz,.drop
        inc (hl)
.drop:  ld a,(shot+Actor.y)
        add a,(hl)
        cp 192
        jr nc,.end
        ld b,a
        add a,9
        ld e,a
        call solid_at
        jr z,.move
        ld a,-4
        ld (shot+Actor.style),a
        jr .hit
.move:  ld a,b
        ld (shot+Actor.y),a
.hit:   ld ix,actors
        call .target
        ld a,(shot+Actor.active)
        or a
        ret z
        ld ix,actors+Actor
.target:ld a,(ix+Actor.active)
        or a
        ret z
        ld a,(ix+Actor.style)
        cp 5
        ret z
        cp 6
        ret z
        cp 9
        ret z
        ld a,(shot+Actor.x)
        sub (ix+Actor.x)
        add a,11
        cp 23
        ret nc
        ld a,(shot+Actor.y)
        sub (ix+Actor.y)
        add a,12
        cp 25
        ret nc
        ld a,(s+State.quest)
        or a
        jr z,.kill
        ld a,(ix+Actor.style)
        cp 4
        jr nc,.kill
        ld a,(ix+birth)         ; walking, resting and kicked Buzzies resist fire
        or a
        jr z,.end
.kill:  ld (ix+Actor.active),0
.end:   xor a
        ld (shot+Actor.active),a
        ret

; Castle hazards are anchored in world space. Sample the same phase for
; collision and graphics; moving the camera shifts the anchor, not the orbit.
hazard_pos:
        ld a,(s+State.tick)
        rrca
        rrca
        and 15
        ld e,a
        ld d,0
        ld hl,orbit
        add hl,de
        ld a,(hl)
        add a,(ix+Actor.x)
        ld b,a
        ld de,4
        add hl,de
        ld a,(hl)
        add a,(ix+Actor.y)
        ld e,a
        ld d,b
        ld a,(ix+Actor.style)
        cp 5
        ret nz
        ld a,(s+State.tick)
        and 63
        bit 5,a
        jr z,.up
        xor 63
.up:    srl a
        ld b,a
        ld a,(ix+Actor.y)
        sub b
        ld e,a
        ret
orbit:  db 0,7,13,17,18,17,13,7,0,-7,-13,-17,-18,-17,-13,-7,0,7,13,17
hazard: call hazard_pos
        ld a,(ix+Actor.style)
        cp 5
        ld b,32
        jr z,.test
        ld b,12
.test:  ld a,(s+State.px)
        sub d
        add a,10
        ld c,a
        ld a,b
        add a,9
        cp c
        ret c
        ld a,(s+State.py)
        sub e
        add a,12
        ld c,a
        ld a,b
        add a,10
        cp c
        jp nc,hurt_player
        ret
hazard_sprite:
        push hl
        call hazard_pos
        pop hl
        dec e
        ld a,(ix+Actor.style)
        cp 5
        jr z,.bowser
        ld b,9
        ld c,240
        call layer
        ld a,(ix+Actor.x)
        add a,d
        rra
        ld d,a
        ld a,e                  ; interpolate signed displacement, not wrapped Y
        sub (ix+Actor.y)
        sra a
        add a,(ix+Actor.y)
        ld e,a
        ld b,11
        jp layer
.bowser:ld c,184
        call .half
        ld a,d
        add a,16
        ld d,a
        call .half
        ld a,d
        sub 16
        ld d,a
        ld a,e
        add a,16
        ld e,a
        call .half
        ld a,d
        add a,16
        ld d,a
.half:  ld b,12
        call layer
        ld a,c
        add a,4
        ld c,a
        ld b,11
        call layer
        ld a,c
        add a,4
        ld c,a
        ret

; Outdoors the eight boss patterns are replaced by Lakitu, Bill, Spiny,
; and Hammer Brother. Slot pressure naturally limits simultaneous attacks.
special_art: db 168,8, 200,8, 192,1, 208,12, 184,12, 240,8, 128,8
; Rise/fall samples are symmetric around the apex. The object keeps its
; source X rather than drifting toward Mario with the flying-enemy path.
bubble_y: db 190,176,163,150,139,128,118,109,101,94,87,82,77,74,71,70,69
special_actor:
        cp 14
        jr nz,.not_squid
        ; Contract and jet toward the swimmer, then sink between strokes.
        inc (ix+Actor.dir)
        ld a,(ix+Actor.dir)
        and 63
        cp 24
        jr nc,.sink
        ld a,(ix+Actor.y)
        cp 44
        jr c,.aim
        dec (ix+Actor.y)
.aim:   ld a,(s+State.px)
        cp (ix+Actor.x)
        jr z,.swimmer
        jr c,.left
        inc (ix+Actor.x)
        jr .swimmer
.left:  dec (ix+Actor.x)
        jr .swimmer
.sink:  and 1
        jr nz,.swimmer
        ld a,(ix+Actor.y)
        cp 160
        jr nc,.swimmer
        inc (ix+Actor.y)
.swimmer:jp walker.touch
.not_squid:
        cp 13
        jr nz,.other
        inc (ix+Actor.dir)
        ld a,(ix+Actor.dir)
        srl a
        and 63
        cp 33
        ld b,190
        jr nc,.bubble_y
        cp 17
        jr c,.index
        neg
        add a,32
.index: ld e,a
        ld d,0
        ld hl,bubble_y
        add hl,de
        ld b,(hl)
.bubble_y:ld (ix+Actor.y),b
        jp walker.touch
.other:
        cp 8
        jp z,walker.normal
        cp 10
        jr z,.bro
        cp 11
        jr z,.cloud
        ld a,(ix+Actor.x)
        sub 2
        jr c,.gone
        ld (ix+Actor.x),a
        ld a,(ix+Actor.style)
        cp 7
        jr z,.arc
        cp 12
        jp nz,walker.touch
.arc:   ld a,(s+State.tick)
        and 63
        bit 5,a
        jr z,.rise
        xor 63
.rise:  add a,a
        add a,a
        ld b,a
        ld a,164
        sub b
        ld (ix+Actor.y),a
        jp walker.touch
.gone:  ld (ix+Actor.active),0
        ret
.bro:   ld c,12
        dec (ix+throw_cd)
        jr nz,.after
        ld a,(s+State.hard)
        or a
        ld a,$30
        jr z,.bro_cd
        ld a,$1c                ; HammerThrowTmrData
.bro_cd:ld (ix+throw_cd),a
        jr .slot
.cloud: ld c,8
        ; Hover ahead of the runner until this cloud leaves the screen.
        ld a,(ix+Actor.x)
        cp 196
        jr nc,.throw
        inc (ix+Actor.x)
.throw: ld a,(s+State.tick)
        and 63
        jr nz,.after
.slot:  ld iy,actors
        ld a,(iy+Actor.active)
        or a
        jr z,.launch
        ld iy,actors+Actor
        ld a,(iy+Actor.active)
        or a
        jr nz,.after
.launch:ld a,(ix+Actor.x)
        ld (iy+Actor.x),a
        ld a,(ix+Actor.y)
        add a,10
        ld (iy+Actor.y),a
        ld (iy+Actor.active),1
        ld (iy+Actor.dir),-1
        ld (iy+Actor.style),c
.after: ld a,c
        cp 8
        jp z,walker.touch
        jp walker.normal
