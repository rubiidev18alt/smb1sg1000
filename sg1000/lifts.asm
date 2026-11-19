; Rebuild the small visible lift list from ROM, independently of the two
; enemy slots. Coordinates stay in the same column-local space as Mario.
liftcount equ $c200
liftbuf   equ $c201             ; x word, y, signed dx, signed dy (max 8)
move_lifts:
        xor a
        ld (liftcount),a
        ld ix,(s+State.lifts)
        ld iy,liftbuf
.scan:  ld l,(ix+0)
        ld h,(ix+1)
        ld a,h
        cp $ff
        ret z
        ld de,(s+State.scroll)
        or a
        sbc hl,de
        ld b,(ix+2)
        ld a,(s+State.tick)
        add a,(ix+0)
        and 127
        ld d,1
        bit 6,a
        jr z,.ascending
        xor 127
        ld d,-1
.ascending:sub 32
        ld e,a
        ld a,(ix+3)
        cp $26
        jr z,.elevator
        cp $27
        jr z,.elevator
        cp $28                  ; horizontal girder
        jr z,.horizontal
        cp $2a
        jr z,.horizontal
        ld a,e
        add a,b
        cp 177
        jr nc,.skip
        ld b,a
        ld (iy+4),d
        ld (iy+3),0
        jr .bounds
.elevator:ld a,(s+State.tick)
        ld d,1
        bit 0,(ix+3)
        jr nz,.e_y
        neg
        dec d
        dec d
.e_y:   add a,b
        cp 192
        jr nc,.skip
        ld b,a
        ld (iy+4),d
        ld (iy+3),0
        jr .bounds
.horizontal:ld (iy+3),d
        ld (iy+4),0
        ld d,0
        bit 7,e
        jr z,.offset
        dec d
.offset:add hl,de
.bounds:ld a,h
        or a
        jr z,.visible
        inc a
        jr nz,.skip
        ld a,l
        cp 209
        jr c,.skip
.visible:ld (iy+0),l
        ld (iy+1),h
        ld (iy+2),b
        ld hl,liftcount
        inc (hl)
        ld a,(hl)
        cp 8
        jr z,.ride
        ld de,5
        add iy,de
.skip:  ld de,4
        add ix,de
        jp .scan
.ride:  ret

; The previous top was new_y-dy. Carry a standing player by the actual
; platform displacement, without overriding a jump or passing through walls.
carry_lift:
        ld a,(s+State.floor)
        or a
        ret z
        ld a,(liftcount)
        or a
        ret z
        ld b,a
        ld ix,liftbuf
.loop:  ld a,(s+State.py)
        add a,16
        add a,(ix+4)
        cp (ix+2)
        jr nz,.next
        call lift_overlap
        jr nc,.next
        ld a,(s+State.px)
        add a,(ix+3)
        cp 235
        ret nc
        ld (s+State.px),a
        ld a,(ix+2)
        sub 16
        ld (s+State.py),a
        ld a,0
        adc a,0
        ld (s+State.above),a
        ret
.next:  ld de,5
        add ix,de
        djnz .loop
        ret

; A is proposed player top; one-way platforms are contacted from above.
on_lift:add a,15
        ld c,a
        ld a,(liftcount)
        or a
        ret z
        ld b,a
        ld ix,liftbuf
.loop:  ld a,c
        cp (ix+2)
        jr nz,.next
        call lift_overlap
        ret c
.next:  ld de,5
        add ix,de
        djnz .loop
        or a
        ret
lift_overlap:
        ld a,(s+State.px)
        ld l,a
        ld h,0
        ld de,13
        add hl,de
        ld e,(ix+0)
        ld d,(ix+1)
        or a
        sbc hl,de
        ld a,h
        or a
        ret nz
        ld a,l
        cp 59
        ret
lift_sprites:
        ld a,(liftcount)
        or a
        ret z
        ld ixl,a
        ld iy,liftbuf
.loop:  ld e,(iy+2)
        dec e
        ld d,(iy+0)
        ld a,(iy+1)
        ld ixh,a
        rept 3
        ld a,ixh
        or a
        jr nz,1F
        ld c,96
        ld b,11
        call layer
1:      ld a,d
        add a,16
        ld d,a
        jr nc,2F
        inc ixh
2:
        endr
        ld bc,5
        add iy,bc
        dec ixl
        jr nz,.loop
        ret
