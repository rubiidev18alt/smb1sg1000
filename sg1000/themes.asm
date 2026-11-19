; At transitions the column cache has not been unpacked yet. Borrow its
; aligned page for a logical-ink -> TMS color-pair lookup (no extra RAM).
pulse_light equ $c260
pulse_dark  equ pulse_light+PULSE_BYTES
set_theme:
        inc a
        ld hl,s+State.theme
        cp (hl)
        ret z
        ld (hl),a
        ; Don't show the old area's tiles changing color bank-by-bank.
        ld a,$82
        out (CTRL),a
        ld a,$81
        out (CTRL),a
        ld a,(hl)
        dec a
        add a,a
        add a,a
        add a,a
        add a,a
        ld e,a
        ld d,0
        ld hl,palette_inks
        add hl,de
        ld de,map
        ld c,16
.fore:  ld a,(hl)
        rlca
        rlca
        rlca
        rlca
        ; All rows start on a 16-byte boundary.
        push hl
        ld b,a
        ld a,l
        and $f0
        ld l,a
.back:  ld a,(hl)
        or b
        ld (de),a
        inc hl
        inc e
        ld a,e
        and 15
        jr nz,.back
        pop hl
        inc hl
        dec c
        jr nz,.fore
        ld hl,$2000
        ld ixh,3
.bank:  push hl
        call address
        ld hl,color_ids
        ld ixl,color_ids_end-color_ids
.tile:  ld a,(hl)
        inc hl
        push hl
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld bc,color_rows
        add hl,bc
        ld d,map/256
        ld b,8
.row:   ld e,(hl)
        ld a,(de)
        out (VDP),a
        inc hl
        djnz .row
        pop hl
        dec ixl
        jr nz,.tile
        pop hl
        ld bc,$800
        add hl,bc
        dec ixh
        jr nz,.bank
        ld hl,pulse_colors
        ld ix,pulse_light
        ld b,PULSE_BYTES
.pulse: ld e,(hl)
        ld a,(de)
        ld (ix+0),a
        ; Only shade the golden foreground; keep the theme's other ink.
        and $f0
        cp $b0
        ld a,(de)
        jr nz,.save
        sub $10
.save:  ld (ix+PULSE_BYTES),a
        inc hl
        inc ix
        djnz .pulse
        ret

        assert pulse_dark+PULSE_BYTES <= $c340 ; leave the top 192 bytes for stack
