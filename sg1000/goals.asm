; Completion owns the pad, clock and SAT until the next area starts.
; Scenes 5..8: flagpole/castle door, bridge, rescue room, final message.
clear_stage:
        ld a,(s+State.kind)
        cp 3
        jp z,axe_goal
        cp 1
        jp z,pole_goal
        ; All four side exits link to GroundArea6, page $0b. Keep the
        ; current stage number, timer and suit; the flag is still playable.
        ld a,1
        ld (s+State.outside),a
        ld hl,$0b00
        ld (s+State.entry),hl
        ld hl,GroundArea6
        call load_area
        ld a,52                 ; pipe column 179 in entrance page 11
        ld (s+State.px),a
        ld a,128
        ld (s+State.py),a
        jp play

start_goal:
        ld (s+State.scene),a
        xor a
        ld (s+State.endphase),a
        ld (s+State.bursts),a
        ld (s+State.immune),a
        ld (s+State.above),a
        ld (s+State.star),a
        ld (s+State.star+1),a
        ld (s+State.face),a
        ld (s+State.throwing),a
        ld (s+State.retry),a
        ld (playing),a
        jp silence
next_stage:
        call finish_song
        ld hl,s+State.stage
        inc (hl)
        jp restart

goal_rel:ld hl,(s+State.goal)
        ld de,(s+State.scroll)
        or a
        sbc hl,de
        ret
; Present prepared background and sprites together, then advance the cue.
goal_frame:
        push bc
        ld a,(s+State.dirty)
        or a
        call nz,present_map
        call prepare_sprites
        call vblank
        call reveal_sprites
        ld a,(s+State.ready)
        or a
        call nz,flip
        call music_tick
        pop bc
        ret
goal_wait:call goal_frame
        djnz goal_wait
        ret
walk_step:
        ld hl,s+State.px
        inc (hl)
        ld a,(hl)
        rrca
        rrca
        rrca
        and 1
        add a,2
        ld (s+State.forced),a
        call camera
        jp goal_frame

pole_goal:
        ld a,5
        call start_goal
        call goal_rel
        ld a,l
        sub 6
        ld (s+State.px),a
        ; FlagpoleYPosData is in NES screen coordinates, including its HUD.
        ld a,(s+State.py)
        add a,16
        ld hl,pole_awards
        ld de,pole_numbers
.score: cp (hl)
        jr nc,.award
        inc hl
        inc hl
        ex de,hl
        ld bc,32
        add hl,bc
        ex de,hl
        jr .score
.award: inc hl
        ld a,(hl)
        push de
        call points
        ld hl,$3800+192*8
        call address
        pop hl
        ld de,32
        call transfer
        ld a,(s+State.py)
        ld (s+State.effect_y),a
        cp 145
        jr c,.grip
        ld a,144
        ld (s+State.py),a
.grip:  call mark
        ld b,56
.slide: ld a,b
        rrca
        rrca
        rrca
        and 1
        add a,8
        ld (s+State.forced),a
        ld hl,s+State.flag_y
        inc (hl)
        inc (hl)
        ld hl,s+State.effect_y
        ld a,(hl)
        cp 28
        jr c,.foot
        dec (hl)
.foot:  ld hl,s+State.py
        ld a,(hl)
        cp 144
        jr nc,.draw
        inc (hl)
        inc (hl)
.draw:  call goal_frame
        djnz .slide
.settle:ld hl,s+State.py
        ld a,(hl)
        cp 144
        jr nc,.turn
        inc (hl)
        inc (hl)
        call goal_frame
        jr .settle
.turn:  ld (hl),144
        ld a,1
        ld (s+State.face),a
        ld hl,s+State.px
        ld a,(hl)
        add a,12
        ld (hl),a
        ld b,12
        call goal_wait
        xor a
        ld (s+State.face),a
        ld a,7
        call start_music
        ld a,1
        ld (s+State.endphase),a
        ld b,192
.walk:  push bc
        call walk_step
        call goal_rel
        ld a,(s+State.px)
        sub l
        cp 12
        jr c,.check
        ld hl,s+State.py
        ld a,(hl)
        cp 160
        jr nc,.check
        inc (hl)
        inc (hl)
.check: ld a,(s+State.px)
        add a,8
        ld d,a
        ld e,160
        call tile_at
        cp $4b                  ; door at the foot of this course's castle
        pop bc
        jr z,.inside
        djnz .walk
.inside:ld hl,$3800+184*8
        call address
        ld hl,celebration_art
        ld de,256
        call transfer
        ld a,4
        ld (s+State.immune),a   ; inside castle: omit Mario from the SAT
        ld a,2
        ld (s+State.endphase),a
        call goal_frame
        ld a,(s+State.timer)
        and 15
        cp 1
        jr z,.count
        cp 3
        jr z,.count
        cp 6
        jr z,.count
        xor a
.count: ld (s+State.bursts),a
        ld hl,s+State.divider  ; clock is stopped: base for NES firework positions
        ld (hl),0
        cp 6
        jr z,.tally
        ld (hl),3
        cp 3
        jr z,.tally
        ld (hl),5
.tally: ld a,(s+State.timer)
        ld hl,s+State.hundred
        or (hl)
        jr z,.raise
        ld a,(s+State.timer)
        sub 1
        daa
        ld (s+State.timer),a
        jr nc,.points
        dec (hl)
.points:ld a,(s+State.scorefrac)
        add a,$50               ; 50 points per remaining unit of time
        daa
        ld (s+State.scorefrac),a
        ld a,1
        call c,points
        call vblank
        call music_tick
        call visible_page
        call time_value
        call score_value
        call visible_page
        jr .tally
.raise: ld a,3
        ld (s+State.endphase),a
        ld a,96
        ld (s+State.effect_y),a
        ld b,20
.up:    ld hl,s+State.effect_y
        dec (hl)
        call goal_frame
        djnz .up
.burst: ld hl,s+State.bursts
        ld a,(hl)
        or a
        jr z,.done
        dec (hl)
        ld a,(s+State.divider)
        add a,(hl)
        add a,a
        ld e,a
        ld d,0
        ld hl,fire_positions
        add hl,de
        ld a,(s+State.px)
        sub 48
        add a,(hl)
        ld (s+State.effect_x),a
        inc hl
        ld a,(hl)
        ld (s+State.effect_y),a
        ld a,4
.flash: ld (s+State.endphase),a
        ld b,6
        call goal_wait
        ld a,(s+State.endphase)
        inc a
        cp 7
        jr c,.flash
        ld a,5                  ; 500 points per burst
        call points
        call visible_page
        call score_value
        call visible_page
        ld a,3
        ld (s+State.endphase),a
        ld a,76
        ld (s+State.effect_y),a
        ld b,14
        call goal_wait
        jr .burst
.done:  ld b,30
        call goal_wait
        jp next_stage
pole_awards: db $90,$01,$68,$04,$50,$08,$22,$20,0,$50
fire_positions: db 0,64,48,32,96,80,96,32,0,64,32,24
visible_page:
        ld hl,s+State.back
        ld a,(hl)
        xor 1
        ld (hl),a
        ret

axe_goal:
        ld a,6
        call start_goal
        ; Frame the full bridge (13 tiles), with the axe in column 13.
        ; Rewind the streaming cursor along with the camera, not the stage.
        call goal_rel
        ld de,208
        ex de,hl
        or a
        sbc hl,de               ; pixels back to the bridge's first column
        push hl
        ex de,hl
        ld hl,(s+State.scroll)
        or a
        sbc hl,de
        ld (s+State.scroll),hl
        pop hl
        rept 3
        srl h
        rr l
        endr
        ld de,32
        add hl,de
        ex de,hl
        ld hl,(s+State.nextcol)
        or a
        sbc hl,de
        ld de,map
        ld b,16
.cache: call unpack
        djnz .cache
        ld (s+State.nextcol),hl
        xor a
        ld (s+State.phase),a
        ld a,208
        ld (s+State.px),a
        ld a,96
        ld (s+State.py),a
        ld a,1
        ld (s+State.forced),a
        ; Bowser was six columns left of the axe in the source room.
        ld ix,actors
        ld (ix+Actor.x),112
        ld (ix+Actor.y),96
        ld (ix+Actor.style),5
        ld (ix+Actor.active),1
        xor a
        ld (s+State.tick),a     ; stop the boss bobbing during the collapse
        ; Mario is stationary on the pedestal during the collapse. Paint
        ; his pose in the map instead of losing half of Bowser to SAT limits.
        ld a,4
        ld (s+State.immune),a
        ld a,(s+State.big)
        ld hl,bridge_mario
        ld de,128
        or a
        jr z,.stamp
        add hl,de
        dec a
        jr z,.stamp
        add hl,de
.stamp: push hl
        ld hl,$0800+248*8       ; world rows 5/6 are in Graphics II bank 1
        call address
        pop hl
        ld de,64
        call transfer
        push hl
        ld hl,$2800+248*8
        call address
        pop hl
        ld de,64
        call transfer
        ld a,$8e
        ld (map+13*16+5),a
        inc a
        ld (map+13*16+6),a
        call bridge_piece
        ld (map+12*16+7),a
        call bridge_piece
        ld hl,map+12*16+8
        ld b,13
.break: ld (hl),0
        push hl
        push bc
        call bridge_piece
        pop bc
        pop hl
        ld de,-16
        add hl,de
        djnz .break
        ld b,32
.fall:  ld hl,actors+Actor.y
        inc (hl)
        inc (hl)
        inc (hl)
        call goal_frame
        djnz .fall
        xor a
        ld (s+State.immune),a
        ld (map+13*16+5),a
        ld (map+13*16+6),a
        ; Only tiles 248/249 are normally populated (dialogue punctuation).
        ld hl,$0800+248*8
        call address
        ld hl,patterns+248*8
        ld de,16
        call transfer
        ld hl,$2800+248*8
        call address
        ld b,16
        ld a,$f0
.ink:   out (VDP),a
        nop
        nop
        djnz .ink
        call mark
        ld a,7
        ld (s+State.scene),a
        ld a,8
        call start_music
        ld hl,$3800+184*8
        call address
        ld hl,toad_art
        ld a,(s+State.stage)
        cp 31
        jr nz,.load
        ld hl,peach_art
.load:  ld de,128
        call transfer
        ld b,168                ; walk to the retainer at goal + 12 columns
.walk:  push bc
        ld a,(s+State.px)
        add a,8
        ld d,a
        ld a,(s+State.py)
        add a,16
        ld e,a
        call solid_at
        jr nz,.step
        ld hl,s+State.py
        inc (hl)
        inc (hl)
.step:  call walk_step
        pop bc
        djnz .walk
        ld a,1
        ld (s+State.forced),a
        call goal_frame
        ld hl,$18c8
        ld de,thanks
        call victory_line
        ld b,128
        call goal_wait
        ld a,(s+State.stage)
        cp 31
        jr z,final_rescue
        ld hl,$1925
        ld de,princess_in
        call victory_line
        ld hl,$1968
        ld de,other_castle
        call victory_line
        ld b,192
        call goal_wait
        jp next_stage
bridge_piece:
        call mark
        ld b,4
        call goal_wait
        xor a
        ret
victory_line:
        push hl
        call visible_page
        pop hl
        call text
        jp visible_page
final_rescue:
        ld a,9
        call start_music
        ld hl,$1926
        ld de,quest_over
        call victory_line
        ld b,64
        call goal_wait
        ld hl,$1962
        ld de,new_quest
        call victory_line
        ld b,64
        call goal_wait
        ld hl,$19c9
        ld de,push_two
        call victory_line
        ld hl,$1a07
        ld de,select_world
        call victory_line
        ld a,8
        ld (s+State.scene),a
        call input
.final: call goal_frame
        call input
        ld a,(s+State.edge)
        bit 5,a
        jr z,.final
        ld a,1
        ld (s+State.quest),a
        jp title
thanks: db 'THANK YOU MARIO!',0
princess_in: db 'BUT OUR PRINCESS IS IN',0
other_castle: db 'ANOTHER CASTLE!',0
quest_over: db 'YOUR QUEST IS OVER.',0
new_quest: db 'WE PRESENT YOU A NEW QUEST.',0
push_two: db 'PUSH BUTTON 2',0
select_world: db 'TO SELECT A WORLD',0

; Called with HL = SAT cursor, A = scene. Ending sprites borrow the
; environment-specific patterns; load_area restores them on every retry.
goal_sprites:
        cp 5
        jr z,.pole
        cp 6
        jr nz,.friend
        ld ix,actors
        call enemy_sprite
        jp prepare_sprites.submit
.friend:push hl
        call goal_rel
        ld de,192
        add hl,de
        ld a,h
        or a
        ld d,l
        pop hl
        jp nz,prepare_sprites.submit
        ld e,151
        ld c,184
        call .half
        ld e,167
        call .half
        jp prepare_sprites.submit
.half:  ld a,(s+State.stage)
        cp 31
        ld b,9                  ; pink dress / tan skin
        jr z,.colour
        ld b,8                  ; red cap / white spots
.colour:call .part
        ld a,(s+State.stage)
        cp 31
        ld b,11
        jr z,.part
        ld b,15
.part:  call layer
        inc c
        inc c
        inc c
        inc c
        ret
.pole:  call pennant
        ld a,(s+State.endphase)
        or a
        jr nz,.roof
        push hl
        call goal_rel
        ld a,l
        add a,12
        ld d,a
        pop hl
        ld a,(s+State.effect_y)
        ld e,a
        ld c,192
        ld b,15
        call layer
        jp prepare_sprites.submit
.roof:  cp 3
        jp c,prepare_sprites.submit
        push af
        ld a,(s+State.px)
        ld d,a
        ld e,76
        pop af
        push af
        cp 3
        jr nz,.flag
        ld a,(s+State.effect_y)
        ld e,a
.flag:  ld c,184
        ld b,15
        call .part
        ld b,8
        call layer
        pop af
        sub 4
        jp c,prepare_sprites.submit
        add a,a
        add a,a
        add a,a
        add a,192
        ld c,a
        ld a,(s+State.effect_x)
        ld d,a
        ld a,(s+State.effect_y)
        ld e,a
        ld b,9
        call .part
        ld b,11
        call layer
        jp prepare_sprites.submit
bridge_mario: incbin "../build/sg1000/bridge_mario.bin"
celebration_art: incbin "../build/sg1000/celebration.bin"
pole_numbers: incbin "../build/sg1000/pole_scores.bin"
toad_art: incbin "../build/sg1000/toad.bin"
peach_art: incbin "../build/sg1000/peach.bin"
