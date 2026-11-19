; Cache the last descriptor: only upload the active sprite halves when the
; pose, suit or facing changes. This leaves VRAM for full-height enemies.
player_gfx:
        ld a,$ff
        ld (s+State.lastpose),a
        ret
animate_mario:
        ld a,(s+State.forced)
        or a
        jr z,.choose
        dec a
        jr .pose
.choose:ld a,(s+State.morph)
        and 4
        ld a,10
        jr nz,.pose
        ld a,(s+State.kind)
        or a
        jr nz,.land
        ld a,(s+State.tick)
        rrca
        rrca
        and 7
        cp 6
        jr c,.swim
        sub 6
.swim:  add a,11
        jr .pose
.land:  ld a,(s+State.floor)
        or a
        ld a,5
        jr z,.pose
        ld a,(s+State.pad)
        bit 1,a
        jr z,.walk
        ld a,(s+State.big)
        or a
        ld a,6
        jr nz,.pose
.walk:  ld a,(s+State.speed)
        or a
        jr z,.pose
        ld hl,(s+State.vx)
        ld a,h
        rlca
        and 1
        ld hl,s+State.face
        xor (hl)
        ld a,4
        jr nz,.pose
        ld a,(s+State.walkphase)
        inc a
.pose:  ld b,a
        ld a,(s+State.big)
        or a
        jr z,.index
        ld a,17
        add a,b
        ld b,a
        ld a,(s+State.throwing)
        or a
        jr z,.index
        ld a,17
        add a,b
        ld b,a
.index: ld a,(s+State.face)
        add a,b
        add a,b
        ld hl,s+State.lastpose
        cp (hl)
        ret z
        ld (hl),a
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        ld de,pose_list
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        push hl
        ld a,(s+State.posetab)
        xor 104                 ; other 24-pattern pose slot
        ld (s+State.posetab),a
        ld a,d
        or e
        ld (s+State.tall),a
        jr z,.bottom
        ld hl,$3800
        call .upload
.bottom:pop hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld hl,$3860
.upload:ld a,(s+State.posetab)
        or a
        jr z,.addr
        ld bc,104*8
        add hl,bc
.addr:  call address
        ex de,hl
        ld a,(s+State.pipeclip)
        or a
        ld b,96
        jp z,short_upload
        ; Mask the rightmost columns in each color layer as Mario enters.
        ld b,a
        ld de,$ffff
.mask:  sla e
        rl d
        djnz .mask
        ld c,3
.color: ld b,16
.left:  ld a,(hl)
        and d
        out (VDP),a
        inc hl
        djnz .left
        ld b,16
.right: ld a,(hl)
        and e
        out (VDP),a
        inc hl
        djnz .right
        dec c
        jr nz,.color
        ret

anim_tick:
        ld hl,s+State.morph
        ld a,(hl)
        or a
        jr z,.throw
        dec (hl)
.throw:
        ld hl,s+State.throwing
        ld a,(hl)
        or a
        jr z,.star
        dec (hl)
.star:  ld hl,(s+State.star)
        ld a,h
        or l
        jr z,.gait
        dec hl
        ld (s+State.star),hl
        ld a,h
        or l
        jr nz,.gait
        ld a,(s+State.kind)
        call start_music
.gait:  ld hl,s+State.animcount
        ld a,(hl)
        or a
        jr z,.next
        dec (hl)
        ret
.next:  ld de,(s+State.vx)
        ld a,d
        bit 7,a
        jr z,.speed
        cpl
.speed: or a
        ld a,6
        jr z,.period
        ld a,3
.period:ld (hl),a
        ld hl,s+State.walkphase
        inc (hl)
        ld a,(hl)
        cp 3
        ret c
        ld (hl),0
        ret
