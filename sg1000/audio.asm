effect: push hl                 ; bump handlers still hold a pointer to the block
        ld hl,jump_fx
        cp $85
        jr z,.set
        ld hl,coin_fx
        cp $82
        jr z,.set
        ld hl,stomp_fx
        cp $8a
        jr z,.set
        ld hl,grow_fx
.set:   ld (s+State.sfx),hl
        pop hl
        ret
jump_fx: db 232,209,185,162,143,127,113,100,90,0
coin_fx: db 57,57,57,43,43,43,43,43,43,43,0
stomp_fx:db 94,115,137,162,211,0
grow_fx: db 214,170,143,107,170,143,107,85,143,107,85,71,0
audio:  ld hl,(s+State.sfx)
        ld a,h
        or l
        jr z,.music
        ld a,(hl)
        or a
        jr z,.mute
        ld b,a
        and 15
        or $80
        out (PSG),a
        ld a,b
        rrca
        rrca
        rrca
        rrca
        and 15
        out (PSG),a
        inc hl
        ld (s+State.sfx),hl
        ld a,$93
        out (PSG),a
        jr .music
.mute:  ld hl,0
        ld (s+State.sfx),hl
        ld a,$9f
        out (PSG),a
.music: ld hl,s+State.beat
        dec (hl)
        ret nz
        ld hl,(s+State.phrase)
        ld a,(hl)
        or a
        jr nz,.event
        call next_phrase
        ld a,(hl)
.event: ld (s+State.beat),a
        inc hl
        ld b,(hl)
        inc hl
.write: ld a,(hl)
        out (PSG),a
        inc hl
        nop                     ; allow the PSG to accept the next data byte
        djnz .write
        ld (s+State.phrase),hl
        ret
start_music:
        add a,a
        ld e,a
        ld d,0
        ld hl,song_list
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (s+State.song),de
        ld a,1
        ld (s+State.beat),a
next_phrase:
        ld hl,(s+State.song)
.read:  ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,e
        or d
        jr nz,.found
        ld e,(hl)               ; end of playlist: loop or enter silence
        inc hl
        ld d,(hl)
        ex de,hl
        jr .read
.found: ld (s+State.song),hl
        ex de,hl
        ld (s+State.phrase),hl
        ret

