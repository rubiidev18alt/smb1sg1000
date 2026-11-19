; Four music parts only: lead, harmony, bass, percussion. Each part has a
; stream pointer, countdown and current note duration; zero countdown = done.
score equ $c230
playlist equ score+16
playing equ playlist+2
length_offset equ playing+1
; Event tracks are finite. Only the warning can end inside the play loop.
gameplay_music:
        call music_tick
        ld a,(playing)
        or a
        ret nz
        ld hl,(s+State.star)
        ld a,h
        or l
        ld a,4
        jr nz,start_music
        ld a,(s+State.kind)
start_music:
        ld b,0
        cp 5
        jr nc,.tempo
        ld c,a
        ld a,(s+State.hundred)
        or a
        jr nz,.normal
        ld b,8                  ; NoteLengthTblAdder after the hurry-up cue
.normal:ld a,c
.tempo: push af
        ld a,b
        ld (length_offset),a
        call silence
        pop af
        add a,a
        ld e,a
        ld d,0
        ld hl,song_list
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        ld a,1
        ld (playing),a
phrase: ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,d
        or e
        jr nz,.found
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        ld a,h
        or l
        jr nz,phrase
        ld (playing),a
        jp silence
.found: ld (playlist),hl
        ex de,hl
        ld ix,score
        ld b,4
.part:  ld a,(hl)
        inc hl
        ld (ix+0),a
        ld a,(hl)
        inc hl
        ld (ix+1),a
        ld (ix+2),1
        ld (ix+3),1
        ld de,4
        add ix,de
        djnz .part
        ret
music_tick:
        ld a,(playing)
        or a
        ret z
        ld ix,score
        ld c,$80
.channel:ld a,(ix+2)
        or a
        jp z,.next
        dec (ix+2)
        jr nz,.decay
        ld l,(ix+0)
        ld h,(ix+1)
        ld a,(hl)
        inc hl
        bit 7,a
        jr z,.note
        and 127
        ld e,a
        ld a,(length_offset)
        add a,e
        ld e,a
        ld d,0
        push hl
        ld hl,note_lengths
        add hl,de
        ld a,(hl)
        pop hl
        ld (ix+3),a
        ld a,(hl)
        inc hl
.note:  ld (ix+0),l
        ld (ix+1),h
        or a
        jr nz,.emit
        ld a,c
        cp $80
        jr nz,.mute
        ld hl,(playlist)
        call phrase
        jp music_tick
.emit:  ld b,(ix+3)
        ld (ix+2),b
        dec a
        ld b,a
        ld a,c
        cp $e0
        jr z,.noise
        ld hl,tone_period
        cp $c0
        jr nz,.pitch
        ld hl,bass_period
.pitch: ld a,b
        cp 2                    ; NES rest ($04)
        jr z,.mute
        add a,a
        ld e,a
        ld d,0
        add hl,de
        ld a,(hl)
        or c
        out (PSG),a
        inc hl
        nop
        nop
        ld a,(hl)
        out (PSG),a
        ld a,c
        cp $80
        ld a,$94
        jr z,.out
        ld a,c
        or $18
        jr .out
.noise: ld a,b
        or a
        jr z,.mute
        and 3
        dec a
        or $e4
        out (PSG),a
        ld a,$f9
        jr .out
.decay: ld a,c
        cp $e0
        jr z,.drum_tail
        ; A short release separates repeated square-wave notes.
        ld a,(ix+2)
        cp 1
        jr z,.mute
        jr .next
.drum_tail:
        ld a,(ix+3)
        sub (ix+2)
        cp 3
        jr nz,.next
.mute:  ld a,c
        or $1f
.out:   out (PSG),a
.next:  ld de,4
        add ix,de
        ld a,c
        add a,$20
        ld c,a
        jp nc,.channel
        ret
        include "../build/sg1000/music.inc"
