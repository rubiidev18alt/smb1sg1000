"""Run the assembled cartridge in a Gearsystem libretro core, without a GUI.

Usage from the repository root: python3 sg1000/smoke.py /path/to/gearsystem_libretro.so
The test reads symbols and observes emulated RAM but drives the game only via pad 1.
"""

import ctypes as C
import json
import re
import sys
from pathlib import Path

ROM = Path("build/smb1.sg")
assert ROM.stat().st_size == 48 * 1024
symbols = {
    k: int(v, 16)
    for k, v in re.findall(
        r"^(\S+): EQU 0x(\w+)", Path("build/sg1000/game.sym").read_text(), re.MULTILINE
    )
}
if len(sys.argv) != 2:
    sys.exit(__doc__)
core = C.CDLL(sys.argv[1])
callbacks = []
buttons = ()
audible_batches = 0
video_frames = 0
video_sizes = set()
sample_sea = False
sea_pixels = []


def register(name, result, args, fn):
    callback = C.CFUNCTYPE(result, *args)(fn)
    callbacks.append(callback)  # keep function pointers alive
    getattr(core, "retro_set_" + name)(callback)


def video(data, width, height, pitch):
    global video_frames
    video_sizes.add((width, height))
    video_frames += 1
    if sample_sea:
        # Left edge of the opening water screen: sky, crest below HUD, sea.
        sea_pixels[:] = [
            C.c_uint16.from_address(data + pitch * y).value
            for y in (0, *range(24, 32), 40, 80, 144)
        ]


def audio(data, count):
    global audible_batches
    if any(C.string_at(data, count * 4)):
        audible_batches += 1
    return count


p, u, z = C.c_void_p, C.c_uint, C.c_size_t
register("environment", C.c_bool, [u, p], lambda command, data: command == 10)  # RGB565
register("video_refresh", None, [p, u, u, z], video)
register("audio_sample_batch", z, [p, z], audio)
register("input_poll", None, [], lambda: None)
register(
    "input_state",
    C.c_int16,
    [u, u, u, u],
    lambda port, dev, idx, key: port == 0 and key in buttons,
)


class Game(C.Structure):
    _fields_ = [("path", C.c_char_p), ("data", p), ("size", z), ("meta", p)]


core.retro_init()
game = Game(str(ROM.resolve()).encode(), None, 0, None)
assert core.retro_load_game(C.byref(game))
core.retro_get_memory_data.restype = C.POINTER(C.c_ubyte)
ram = core.retro_get_memory_data(2)
base = symbols["s"] - 0xC000
replays = json.loads(Path("sg1000/replays.json").read_text())


def st(name):
    return ram[base + symbols["State." + name]]


def scroll():
    offset = base + symbols["State.scroll"]
    return ram[offset] + 256 * ram[offset + 1]


def frame(n, *keys):
    global buttons
    buttons = keys
    for _ in range(n):
        core.retro_run()


def select(slot=0, *, second=False):
    frame(120)
    assert ram[symbols["playing"] - 0xC000] == 0
    assert st("stage") == 0 and st("lives") == 3
    for _ in range(slot):
        frame(2, 8)
        frame(2)
    if second:
        frame(3, 4)  # Up on the title
        frame(2)
    frame(3, 0)
    wait_entry(slot)
    assert st("quest") == int(second)


def wait_entry(slot, *, retry=False):
    scenes = set()
    walk = []
    clipped = False
    lead = False
    for _ in range(800):
        sc = st("scene")
        if sc:
            scenes.add(sc)
        if sc == 2 and st("px") >= 32:
            walk.append(st("px"))
            clipped |= 0 < st("pipeclip") < 16
            p = symbols["playlist"] - 0xC000
            lead |= ram[p] + 256 * ram[p + 1] == symbols["song10"] + 2
        if not sc and 1 in scenes and st("tick") == 47:
            break
        frame(1)
    assert st("scene") == 0 and st("tick") == 47 and st("stage") == slot
    if slot in (1, 5, 13, 25) and not retry:
        assert (
            scenes == {1, 2}
            and min(walk) <= 33
            and max(walk) == 160
            and clipped
            and lead
        )
    else:
        assert scenes == {1}
    if slot == 0:
        p = symbols["playlist"] - 0xC000
        assert ram[p] + 256 * ram[p + 1] == symbols["song1"] + 2


def run_tape(name):
    """Frame count and RetroPad button mask. No savestates or RAM writes."""
    flags = set()
    riding = 0
    for n, mask in replays[name]:
        for _ in range(n):
            before = score_value(), st("scene")
            frame(1, *[b for b in range(16) if mask & 1 << b])
            assert st("lives") == 3
            if st("star") or ram[base + symbols["State.star"] + 1]:
                flags.add("star")
            if before[1] == 0 and st("scene") == 5:
                flags.add(("pole", score_value() - before[0]))
            if st("scene") == 1:
                flags.add("card")
            if st("bonus"):
                flags.add("bonus")
            if (
                st("above")
                and st("floor")
                and st("py") == 240
                and scroll() + st("px") > 2564
                and ram[(st("px") + 8) & 0xF0] == 0x52
            ):
                flags.add("roof")
            if name in ("castle-2-4", "swim-2-2", "swim-7-2"):
                for i in (0, 5):
                    p = symbols["actors"] - 0xC000 + i
                    if ram[p]:
                        flags.add(ram[p + 4])
            if name == "spring-5-2":
                # Inspect the actual sprite list prepared by this cartridge.
                p = symbols["sat"] - 0xC000
                patterns = set()
                for i in range(32):
                    if ram[p + 4 * i] == 0xD0:
                        break
                    patterns.add(ram[p + 4 * i + 2])
                else:
                    raise AssertionError("unterminated sprite table")
                flags.update(patterns & {144, 152, 156})  # extended, half, compressed
                mario = not patterns.isdisjoint({12, 116})
                if st("above") and 32 <= st("py") < 225:
                    assert not mario
                    flags.add("offscreen")
                if "offscreen" in flags and not st("above") and mario:
                    flags.add("returned")
            count = ram[symbols["liftcount"] - 0xC000]
            for i in range(count):
                p = symbols["liftbuf"] - 0xC000 + i * 5
                x = ram[p] + ram[p + 1] * 256
                if x >= 32768:
                    x -= 65536
                if (
                    st("floor")
                    and st("py") + 16 == ram[p + 2]
                    and -13 <= st("px") - x < st("liftwidth") - 2
                ):
                    riding += 1
    return flags, riding


def bcd(name):
    value = st(name)
    return (value >> 4) * 10 + (value & 15)


def score_value():
    return bcd("scorehi") * 10000 + bcd("scorelo") * 100 + bcd("scorefrac")


def finish_pole(stage, expected=None):
    # The tape ends on the pole. No further input is needed. Each timer
    # unit buys 50 points; only 1/3/6 set off 500-point fireworks.
    assert st("scene") == 5 and st("stage") == stage
    assert st("endphase") <= 2
    t = st("hundred") * 100 + bcd("timer")
    initial = score_value()
    digit = t % 10
    count = digit if digit in (1, 3, 6) else 0
    if expected is not None:
        assert count == expected
    flashes = set()
    raised = False
    for _ in range(1400):
        if st("stage") != stage:
            break
        if st("endphase") == 3:
            raised = True
        if st("endphase") == 4:
            flashes.add(st("bursts"))
        frame(1)
    assert raised and len(flashes) == count
    assert st("stage") == stage + 1 and not st("timer") and not st("hundred")
    assert score_value() == initial + t * 50 + count * 500


def finish_castle(stage):
    for _ in range(80):
        if st("scene") == 6:
            break
        frame(1)
    assert st("stage") == stage and st("scene") == 6
    remaining = []
    met_host = False
    for _ in range(1300):
        if st("scene") == 6:
            remaining.append(sum(ram[16 * x + 8] == 0x89 for x in range(13)))
        if st("scene") == 7 and st("forced") == 1:
            met_host = True
        if st("scene") == 8 or st("stage") != stage:
            break
        frame(1)
    assert met_host and len(set(remaining)) >= 10 and remaining[-1] == 0
    if stage != 31:
        assert st("stage") == stage + 1 and st("scene") == 1
    else:
        assert st("stage") == 31 and st("scene") == 8


select()
flags, _ = run_tape("star-and-flag")
assert {"star", ("pole", 100)} <= flags
finish_pole(0, 6)
wait_entry(1)
assert st("kind") == 2 and st("py") == 160
core.retro_reset()
select()
flags, _ = run_tape("bonus-pipe")
assert {"bonus", ("pole", 2000)} <= flags
finish_pole(0)
core.retro_reset()
select(1)
for _ in range(350):
    frame(1, 7, 8)
    if st("lives") == 2:
        break
assert st("lives") == 2
wait_entry(1, retry=True)  # lives card, no castle walk on an underground retry
core.retro_reset()
select(1)
flags, _ = run_tape("roof-warp")
assert {"roof", "card"} <= flags and st("stage") == 4
core.retro_reset()
# 6-2: approach the first tall pipe (column 19) and jump from a dead stop.
select(21)
for _ in range(230):
    frame(1, 7, 8)
    if scroll() + st("px") == 290:
        break
frame(8, 7)
assert scroll() + st("px") == 290 and st("py") == 160 and st("floor")
frame(8)  # remove the run-up entirely
frame(1, 0)  # a tap must not clear four blocks
for _ in range(60):
    frame(1)
    assert st("py") > 96
assert st("floor") and st("py") == 160
for _ in range(64):
    frame(1, 7, 0)  # hold jump toward the pipe, without Run
assert st("floor") and st("py") == 96 and 304 <= scroll() + st("px") < 336
core.retro_reset()
select(2)
assert st("liftwidth") == 48
_, riding = run_tape("lifts-1-3")
assert riding >= 10
finish_pole(2)
core.retro_reset()
sample_sea = True
select(5)
sample_sea = False
assert sea_pixels[0] != sea_pixels[-1] and len(set(sea_pixels[1:9])) >= 2
assert len(set(sea_pixels[-3:])) == 1  # same sea ink in all three banks
assert st("theme") == 1 and ram[1] == 0x8D
flags, _ = run_tape("swim-2-2")
assert {4, 14} <= flags and 9 not in flags and st("outside")
finish_pole(5)
core.retro_reset()
select(25)
flags, _ = run_tape("swim-7-2")
assert {4, 14} <= flags and 9 not in flags and st("outside")
finish_pole(25)
core.retro_reset()
select(13)  # fourth shared pipe entrance: 4-2
core.retro_reset()
select(17)
flags, _ = run_tape("spring-5-2")
assert {144, 152, 156, "offscreen", "returned"} <= flags
core.retro_reset()
select(7)
flags, _ = run_tape("castle-2-4")
assert {13, 6, 5} <= flags  # Podoboo, firebar, Bowser
finish_castle(7)
core.retro_reset()
select(31)
run_tape("final-8-4")
finish_castle(31)
frame(360)
assert st("scene") == 8
frame(3, 8)
frame(90)
assert st("quest") == 1 and st("stage") == 0
frame(2, 8)
frame(3)
assert st("stage") == 4  # Button 2 selects worlds on the second quest
for _ in range(7):
    frame(2, 8)
    frame(3)
assert st("stage") == 0
frame(3, 0)
wait_entry(0)
assert st("hard") and st("quest") and st("liftwidth") == 32
run_tape("quest2-1-1")
finish_pole(0)
wait_entry(1)
assert st("quest") == 1 and st("lives") == 3

core.retro_reset()
select(2, second=True)
assert st("liftwidth") == 32
_, riding = run_tape("quest2-1-3")
assert riding >= 10
finish_pole(2)

# Stomp the opening Buzzy and leave its shell alone until it revives.
core.retro_reset()
select(second=True)
frame(89, 7, 8)
frame(40, 7, 8, 0)
p = symbols["actors"] - 0xC000
for _ in range(25):
    frame(1)
    if ram[p + 4] == 2:
        break
assert ram[p] and ram[p + 4] == 2 and ram[p + symbols["wake_lo"]] == 231
frame(2)
sat_base = symbols["sat"] - 0xC000
parts = []
for i in range(32):
    j = sat_base + 4 * i
    if ram[j] == 0xD0:
        break
    parts.append(ram[j + 2])
assert {128, 132} <= set(parts)  # actual two-layer Buzzy shell, not a Goomba/Koopa
frame(228)
assert ram[p] and ram[p + 4] == 2
frame(1)
assert ram[p] and ram[p + 4] == 0 and st("lives") == 3

# The second Podoboo at column 20 in 2-4 is marked hard-only in the
# original enemy stream. The same controller input should expose it in
# the second quest but not on a first-quest visit to that castle.
for second in (False, True):
    core.retro_reset()
    select(7, second=second)
    peak = 0
    for i in range(140):
        frame(1, *((7, 8, 0) if i < 29 else (7, 8)))
        peak = max(peak, sum(bool(ram[p + j] and ram[p + j + 4] == 13) for j in (0, 5)))
        if scroll() + st("px") >= 230:
            break
    assert peak == 1 + int(second) and st("lives") == 3


core.retro_reset()
frame(120)
frame(3, 4)
frame(2)
frame(3, 5)  # Down returns to Quest 1 and the original stage selector
frame(2)
assert not st("quest")
for i in range(1, 33):
    frame(4, 8)
    frame(3)
    assert st("stage") == i % 32
for _ in range(4):
    frame(3, 8)
    frame(2)
frame(3, 0)
wait_entry(4)
assert st("stage") == 4 and not st("bonus") and st("kind") == 1
# The first source enemy of 2-1 is at column $18, row 5. Observe it
# on its allocation tick, before walking/gravity have carried it far.
p = symbols["actors"] - 0xC000
for _ in range(230):
    frame(1, 7, 8)
    if ram[p]:
        break
assert (
    ram[p]
    and ram[p + 4] == 0
    and 383 <= scroll() + ram[p + 1] <= 384
    and 64 <= ram[p + 2] <= 67
)
assert audible_batches > 100
# Running off the opening of 1-3 must not bounce Mario back out of the pit.
core.retro_reset()
select(2)
for _ in range(250):
    frame(1, 7, 8)
    if st("forced") == 10:
        break
assert st("forced") == 10 and st("py") >= 192
for _ in range(250):
    if st("lives") != 3:
        break
    assert st("py") >= 192 and not st("expired")
    frame(1)
assert st("lives") == 2
wait_entry(2, retry=True)

core.retro_reset()
select()
for lives in (2, 1):
    for _ in range(600):
        frame(1, 7, 8)
        if st("lives") == lives:
            break
    assert st("lives") == lives
    wait_entry(0, retry=True)

# Let the real clock expire from spawn on the last life. No RAM injection.
p = symbols["playlist"] - 0xC000
seen_warning = seen_fast = False
zero_frames = 0
for _ in range(10000):
    frame(1)
    if st("expired"):
        break
    if not st("hundred"):
        seen_warning |= ram[p] + 256 * ram[p + 1] == symbols["song11"] + 2
        seen_fast |= seen_warning and ram[symbols["length_offset"] - 0xC000] == 8
        zero_frames += st("timer") == 0
assert seen_warning and seen_fast and zero_frames == 24 and st("expired")
assert st("lives") == 1 and st("forced") == 10
x = scroll() + st("px")
arc = []
for _ in range(250):
    if st("scene") == 3:
        break
    assert scroll() + st("px") == x and st("forced") == 10
    arc.append(st("py"))
    frame(1, 7, 0)  # cannot steer or skip the death animation
assert arc[:16] == [160] * 16 and min(arc) == 106 and arc[-1] >= 192
assert st("scene") == 3 and not st("lives") and not st("expired")
frame(100)
assert st("scene") == 3  # TIME UP holds even on the last life
frame(70)
assert st("scene") == 4 and ram[p] + 256 * ram[p + 1] == symbols["song6"] + 2
frame(3, 0)
frame(45)
assert st("lives") == 3 and st("stage") == 0
assert video_sizes == {(256, 192)}
core.retro_deinit()
print(
    f"PASS: {video_frames} frames; 1-1 Starman and bonus routes, 1-2 roof to world 2, 1-3 moving lifts, 2-1 spawn, 2-2 and 7-2 swims, 2-4 castle clear, 5-2 spring and offscreen return, 6-2 four-block standing jump, lives cards and pipe intros, music, selector wrap, pit death, hurry-up and last-life timeout; timer bonuses, fireworks, bridge collapse, Toad and Peach endings, second-quest clears and Buzzy revival"
)
