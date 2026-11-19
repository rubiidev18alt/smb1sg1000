; Presentation loops do not run the gameplay clock, actor or input handlers.
finish_song:
        ld a,(playing)
        or a
        ret z
        call vblank
        call music_tick
        jr finish_song

lives_card:
        call silence
        xor a
        ld (playing),a
        ld (s+State.tick),a
        ld (s+State.yview),a
        ld (s+State.phase),a
        ld (s+State.above),a
        ld (s+State.immune),a
        ld (s+State.face),a
        ld (s+State.morph),a
        ld (s+State.throwing),a
        ld (s+State.star),a
        ld (s+State.star+1),a
        ld (s+State.pipeclip),a
        inc a
        ld (s+State.forced),a   ; standing, facing right
        ld (s+State.scene),a
        call black_page
        ld hl,$192b
        ld de,hud_world
        call text
        call stage_digits
        ld hl,$198f
        ld de,times_text
        call text
        ld a,(s+State.lives)
        out (VDP),a
        ld a,96
        ld (s+State.px),a
        ld a,92
        ld (s+State.py),a
        ld a,(s+State.big)
        push af
        xor a
        ld (s+State.big),a      ; card always uses small standing Mario
        call prepare_sprites
        call vblank
        call reveal_sprites
        call flip
        ld b,100
        call .hold_wait
        pop af
        ld (s+State.big),a
        ret
.hold_wait:call vblank
        djnz .hold_wait
        ret
black_page:
        ; Blank the display while changing backdrop and building the hidden page.
        ld a,$82
        out (CTRL),a
        ld a,$81
        out (CTRL),a
        ld a,1
        out (CTRL),a            ; black backdrop
        ld a,$87
        out (CTRL),a
        ld hl,$1800
        call back_address
        ld c,3
        ld b,0
        ld a,36
.blank: out (VDP),a
        nop
        nop
        djnz .blank
        dec c
        jr nz,.blank
        call hud
blank_time:
        ld hl,$185b             ; original card leaves TIME empty
        ld de,spaces
        jp text
spaces: db '   ',0
times_text: db 'X  ',0

pipe_intro:
        ld hl,intro_stages
        ld a,(s+State.stage)
        ld b,a
.scan:  ld a,(hl)
        inc hl
        cp $ff
        ret z
        cp b
        jr nz,.scan
.begin: ld a,2
        ld (s+State.scene),a
        ld a,1
        call set_theme
        ld a,5
        out (CTRL),a
        ld a,$87
        out (CTRL),a
        ld hl,intro_columns
        ld de,map
        ld b,16
.col:   call unpack
        djnz .col
        ld a,32
        ld (s+State.px),a
        ld a,160
        ld (s+State.py),a
        call present_map
        call blank_time
        call prepare_sprites
        call vblank
        call reveal_sprites
        call flip
        ld a,10
        call start_music
.walk:  call vblank
        call music_tick
        ld hl,s+State.px
        inc (hl)
        ld a,(hl)
        rrca
        rrca
        rrca
        and 1
        add a,2
        ld (s+State.forced),a
        ld a,(hl)
        sub INTRO_MOUTH-16
        jr c,.sprite
        ld (s+State.pipeclip),a
        call player_gfx
.sprite:call draw_sprites
        ld a,(s+State.px)
        cp INTRO_MOUTH
        jr c,.walk
        jp finish_song

; The game-over, final and time-up messages have no player icon.
message_card:
        push de
        call black_page
        pop de
        ld hl,$1985
        call text
        ld hl,sat
        call prepare_sprites.submit
        call vblank
        call reveal_sprites
        jp flip

time_up_card:
        ld a,(s+State.hundred)
        or a
        ret nz
        ld a,(s+State.timer)
        or a
        ret nz
        call finish_song
        ld de,timeup_text
        call message_card
        ld b,90
        jp lives_card.hold_wait
timeup_text: db '       TIME UP',0
