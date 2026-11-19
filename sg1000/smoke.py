"""Run the assembled cartridge in a Gearsystem libretro core, without a GUI.

Usage from the repository root: python3 sg1000/smoke.py /path/to/gearsystem_libretro.so
The test reads symbols and observes emulated RAM but drives the game only via pad 1.
"""

import ctypes as C
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
video_frames = 0
video_sizes = set()
sound = False


def register(name, result, args, fn):
    callback = C.CFUNCTYPE(result, *args)(fn)
    callbacks.append(callback)  # keep function pointers alive
    getattr(core, "retro_set_" + name)(callback)


def video(data, width, height, pitch):
    global video_frames
    video_sizes.add((width, height))
    video_frames += 1


def audio(data, count):
    global sound
    if not sound:
        sound = any(C.string_at(data, count * 4))
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
solid = Path("build/sg1000/solid.bin").read_bytes()


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


def start():
    frame(120)
    assert st("stage") == 0 and st("lives") == 3
    frame(3, 0)
    frame(40)
    assert st("py") == 160 and st("floor") == 1


def run_course(use_pipe):
    start()
    underground = jumped = False
    for _ in range(2000):
        x, y = st("px"), st("py")
        world = scroll() + x
        if st("stage") == 1:
            break
        assert st("lives") == 3

        def wall(dx, dy, x=x, y=y):
            e = y + dy
            return 0 <= e < 192 and solid[ram[((x + dx) & 240) + (e // 16)]]

        actors = symbols["actors"] - 0xC000
        danger = any(
            ram[a] and -8 < ram[a + 1] - x < 50 and abs(ram[a + 2] - y) < 24
            for a in (actors, actors + symbols["Actor"])
        )
        keys = [7, 8]  # right, run
        if (
            st("floor")
            and (danger or any(wall(dx, 12) for dx in (14, 20, 32)) or not wall(22, 16))
            or st("vy") >= 128
        ):
            keys.append(0)
        if use_pipe and not underground and 916 <= world <= 924:
            keys = [5]  # down
        if st("bonus"):
            underground = True
        jumped |= st("vy") >= 128
        frame(1, *keys)
    assert st("stage") == 1 and jumped and underground == use_pipe
    assert st("coins") != 0 and sound
    frame(5)
    frame(3, 0)
    frame(45)  # dismiss course-clear screen
    assert st("kind") == 2 and st("stage") == 1 and scroll() == 0 and st("py") == 160


run_course(False)
core.retro_reset()
run_course(True)
core.retro_reset()
start()
for lives in (2, 1, 0):
    for _ in range(400):
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
    f"PASS: {video_frames} emulator frames; 1-1 overland and bonus routes, 1-2, game over and restart"
)
