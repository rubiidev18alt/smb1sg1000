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


def select(slot=0):
    frame(120)
    assert ram[symbols["playing"] - 0xC000] == 0
    assert st("stage") == 0 and st("lives") == 3
    for _ in range(slot):
        frame(2, 8)
        frame(2)
    frame(3, 0)
    # Changing all three color banks takes a few video frames; begin the
    # tape at a specific simulation tick, not during the palette upload.
    for _ in range(80):
        if slot == 0 and 2 <= st("tick") <= 6:
            p = symbols["playlist"] - 0xC000
            assert ram[p] + 256 * ram[p + 1] == symbols["song1"] + 2  # lead-in playing
        if st("tick") == 47:
            break
        frame(1)
    assert st("tick") == 47


def run_tape(name):
    """Frame count and RetroPad button mask. No savestates or RAM writes."""
    flags = set()
    riding = 0
    for n, mask in replays[name]:
        for _ in range(n):
            frame(1, *[b for b in range(16) if mask & 1 << b])
            assert st("lives") == 3
            if st("star") or ram[base + symbols["State.star"] + 1]:
                flags.add("star")
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
                    and -12 <= st("px") - x < 46
                ):
                    riding += 1
    return flags, riding


select()
flags, _ = run_tape("star-and-flag")
assert "star" in flags and st("stage") == 1
frame(5)
frame(3, 0)
frame(45)
assert st("kind") == 2 and st("py") == 160
core.retro_reset()
select()
flags, _ = run_tape("bonus-pipe")
assert "bonus" in flags and st("stage") == 1
core.retro_reset()
select(1)
flags, _ = run_tape("roof-warp")
assert "roof" in flags and st("stage") == 4
core.retro_reset()
select(2)
_, riding = run_tape("lifts-1-3")
assert st("stage") == 3 and riding >= 10
core.retro_reset()
sample_sea = True
select(5)
sample_sea = False
assert sea_pixels[0] != sea_pixels[-1] and len(set(sea_pixels[1:9])) >= 2
assert len(set(sea_pixels[-3:])) == 1  # same sea ink in all three banks
assert st("theme") == 1 and ram[1] == 0x8D
flags, _ = run_tape("swim-2-2")
assert {4, 14} <= flags and 9 not in flags and st("stage") == 6
core.retro_reset()
select(25)
flags, _ = run_tape("swim-7-2")
assert {4, 14} <= flags and 9 not in flags and st("stage") == 26
core.retro_reset()
select(17)
flags, _ = run_tape("spring-5-2")
assert {144, 152, 156, "offscreen", "returned"} <= flags
core.retro_reset()
select(7)
flags, _ = run_tape("castle-2-4")
assert {13, 6, 5} <= flags and st("stage") == 8  # Podoboo, firebar, Bowser
core.retro_reset()
frame(120)
for i in range(1, 33):
    frame(4, 8)
    frame(3)
    assert st("stage") == i % 32
for _ in range(4):
    frame(3, 8)
    frame(2)
frame(3, 0)
frame(25)
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
core.retro_reset()
select()
for lives in (2, 1, 0):
    for _ in range(600):
        frame(1, 7, 8)
        if st("lives") == lives:
            break
    assert st("lives") == lives
    frame(20)
    frame(3, 0)
    frame(45)
assert st("lives") == 3 and st("stage") == 0
assert video_sizes == {(256, 192)}
core.retro_deinit()
print(
    f"PASS: {video_frames} frames; 1-1 Starman and bonus routes, 1-2 roof to world 2, 1-3 moving lifts, 2-1 spawn, 2-2 and 7-2 swims, 2-4 castle clear, 5-2 spring and offscreen return, music, selector wrap and restart"
)
