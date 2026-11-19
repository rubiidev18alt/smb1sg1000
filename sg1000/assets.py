"""Compile SMB1Base's ca65 area streams and NES CHR into SG cartridge data."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/sg1000"
SOURCE = (ROOT / "src/level_tiles.s").read_text()


def table(name, source=SOURCE):
    body = re.search(
        r"^" + name + r":([^\n]*(?:\n(?:\s*\.byte[^\n]*|;[^\n]*))*)",
        source,
        re.MULTILINE,
    )[1]
    return [
        int(v[1:], 16 if v[0] == "$" else 2)
        for line in body.splitlines()
        for v in re.findall(r"\$[\da-fA-F]+|%[01]+", line.split(";")[0])
    ]


def objects(data, enemy=False, links=None):
    page = i = 0
    page_selected = False
    while data[i] != (255 if enemy else 253):
        a, b = data[i : i + 2]
        i += 2
        row = a & 15
        if b & 128 and not page_selected:
            page_selected = True
            page += 1
        can_select = not page_selected
        page_selected = False
        b &= 127
        if (enemy and row == 15 and can_select) or (not enemy and row == 13 and b < 64):
            page = b & 31
            page_selected = True
        elif enemy and row == 14:
            if links is not None:
                links.append((page * 16 + (a >> 4), b, data[i]))
            i += 1  # area link includes an entrance byte
        else:
            yield page * 16 + (a >> 4), row, b


def area(name, kind):
    data = table("L_" + name)
    # Some vanilla enemy streams share a terminator with the next labeled area.
    enemies = table("E_" + name) + [255]
    objs = list(objects(data[2:]))
    width = max(x for x, _, _ in objs) + 20
    cols = [[0] * 12 for _ in range(width)]

    def put(x, y, tile):
        if 0 <= y < 12 and 0 <= x < width:
            cols[x][y] = tile

    foreground = data[0] & 7
    fore_tiles = table("ForeSceneryData")
    fore_at = {x: b & 7 for x, y, b in objs if y == 14 and b & 64}
    terr = table("TerrainRenderBits")
    scene = table("BackSceneryData")
    mts = table("BackSceneryMetatiles")
    header = data[1]
    changes = {x: b for x, y, b in objs if y == 14 and b < 64}
    for x, col in enumerate(cols):
        header = changes.get(x, header)
        scenery = header >> 4 & 3
        if scenery:
            s = scene[(scenery - 1) * 48 + x % 48]
            if s:
                for j in range(3):
                    put(x, (s >> 4) + j, mts[3 * ((s & 15) - 1) + j])
        foreground = fore_at.get(x, foreground)
        if 1 <= foreground <= 3:
            for y in range(12):
                tile = fore_tiles[(foreground - 1) * 13 + y]
                if tile:
                    col[y] = tile
        k = 2 * (header & 15)
        for y in range(12):
            if terr[k + y // 8] & 1 << (y % 8):
                col[y] = [0x69, 0x54, 0x52, 0x62][kind]
    goal = None
    for x, y, b in objs:
        op, n = b >> 4, (b & 15) + 1
        if y < 12:
            if op == 0:
                if b == 11:
                    put(x, y + 1, 0x68)  # foot of the two-row jumpspring
                if kind == 0 and b == 9:
                    goal = x
                    put(x, y + 1, 0x6C)
                put(
                    x,
                    y,
                    [
                        0xC1,
                        0xC0,
                        0xC0,
                        0xC1,
                        0x55,
                        0x55,
                        0x57,  # brick containing Starman
                        0x58,
                        0x55,
                        0x6B,
                        0xC4,
                        0x67,
                        0,
                        0,
                        0,
                        0,
                    ][b],
                )
            elif op == 4 and kind == 0:
                for j in range(n):
                    put(x + j, y, 0xC3)  # underwater coin
            elif op == 7:
                for j in range(2):
                    put(x + j, y, (0x10 if b & 8 else 0x12) + j)
                    for k in range(1, (b & 7) + 1):
                        put(x + j, y + k, 0x14 + j)
            elif op == 1 and data[1] >> 6 == 2:
                for j in range(n):
                    put(x, y + j, min(0x66, 0x64 + j))
            else:
                brick = [0x22, 0x51, 0x52, 0x52][kind]
                stone = [0x69, 0x61, 0x61, 0x62][kind]
                tile = [0, 0x17, brick, stone, 0xC2, brick, stone][op]
                for j in range(n):
                    xx, yy = (x, y + j) if op in (5, 6) else (x + j, y)
                    put(
                        xx,
                        yy,
                        tile
                        if op != 1
                        else (0x19 if data[1] >> 6 == 1 else 0x16)
                        + (0 if j == 0 else 2 if j == n - 1 else 1),
                    )
                    if op == 1:
                        mushroom = data[1] >> 6 == 1
                        if (mushroom and j == n // 2) or (
                            not mushroom and 0 < j < n - 1
                        ):
                            for k in range(y + 1, 11):
                                if cols[xx][k] in (0, 0x4C):
                                    put(
                                        xx,
                                        k,
                                        (0x4F if k == y + 1 else 0x50)
                                        if mushroom
                                        else 0x4C,
                                    )
        elif y == 12:
            for xx in range(x, x + n):
                if op in (0, 5):
                    for k in range(8, 12):
                        put(
                            xx,
                            k,
                            0x86
                            if op == 5 and k == 10
                            else 0x87
                            if op == 5 and k == 11
                            else 0x87
                            if kind == 0
                            else 0,
                        )
                elif op in (2, 3, 4):
                    yy = [6, 7, 9][op - 2]
                    put(xx, yy, 11)
                    put(xx, yy + 1, 0x63)
                elif op in (6, 7):
                    put(xx, 3 if op == 6 else 7, 0xC0)
        elif y == 15 and op == 3:
            for j in range(n):
                for yy in range(max(3, 10 - j), 11):
                    put(x + j, yy, 0x61)
        elif y == 15 and op == 2:
            castle = table("CastleMetatiles")
            for yy in range(b & 15, 11):
                for j in range(5):
                    put(x + j, yy, castle[(yy - (b & 15)) * 5 + j])
        elif (y, b) == (13, 0x41) or (y == 15 and op == 5):
            goal = x
            for yy in range(11):
                put(
                    x,
                    yy,
                    0 if yy == 0 else 0x24 if yy == 1 else 0x61 if yy == 10 else 0x25,
                )
        elif y == 13 and b == 0x42:
            goal = x
            put(x, 6, 0xC5)
        elif y == 13 and b == 0x43:
            put(x, 7, 0x0C)  # bridge chain beneath the axe
        elif y == 13 and b == 0x44:
            for j in range(13):
                put(x + j, 8, 0x89)
        elif y == 15 and op == 4:
            for j in range(4):
                yy = (b & 15) - 1
                put(x + j, yy, [0x1C, 0x1D, 0x1E, 0x15][j])
                put(x + j, yy + 1, [0x1F, 0x20, 0x21, 0x15][j])
                if j >= 2:
                    for k in range(yy):
                        put(x + j, k, 0x14 + j - 2)
            if kind in (0, 2) and goal is None:
                goal = x
    if goal is None:
        goal = width - 18
        put(goal, 8, 0xC5)
    if kind == 3:
        # Lava shares the water pattern/ink slots. Keep distinct metatile
        # IDs for damage and breakable-brick collision, not separate CHR.
        for col in cols:
            for row, tile in enumerate(col):
                if tile in (0x86, 0x87):
                    col[row] = tile + 4
                elif tile == 0x52:
                    col[row] = 0x8C  # castle brick uses gray mortar
    if kind == 0:
        # The first 24 pixels are HUD on SG. Place the crest in the first
        # visible half-row; leave solid geometry at its source coordinates.
        for col in cols:
            if col[0] == 0x86 and col[1] == 0x87:
                col[1] = 0x8D
    spawns = []
    depths = (
        table("Enemy17YPosData", (ROOT / "src/object.s").read_text())
        if kind == 0
        else []
    )
    for x, y, b in objs:
        if y == 13 and b in (0x48, 0x49):
            end = next(
                (
                    xx
                    for xx, yy, bb in objs
                    if xx > x and yy == 13 and bb in (0x48, 0x49, 0x4A)
                ),
                goal,
            )
            for xx in range(x + 4, end, 9):
                if kind == 0:
                    spawns.append(
                        (xx * 16, max(2, depths[((xx - x) // 9) % 8] // 16 - 1), 4)
                    )
                else:
                    spawns.append((xx * 16, 10, 7 if b == 0x48 else 9))
        elif y < 12 and b >> 4 == 1 and data[1] >> 6 == 2:
            spawns.append((x * 16, y, 9))  # cannon mouth

    for x, y, b in objects(enemies, True):
        if y == 15:
            continue  # row-F advance, below the playable area
        hard = (b & 64) << 2  # encoded separately from Y/style on cartridge
        b &= 63
        if 0x1B <= b <= 0x20:
            spawns.append((x * 16, max(0, min(y - 2, 10)), hard + 6))  # firebar anchor
        elif b == 0x11:
            spawns.append((x * 16, 2, hard + 11))  # Lakitu drops Spinies from his cloud
        elif b in (0, 1, 2, 3, 5, 6, 7, 10, 11, 0x0E, 0x0F) or 0x37 <= b <= 0x3E:
            group = b >= 0x37
            for j in range(2 + (b % 2 == 0) if group else 1):
                style = (
                    4 if kind == 0 else int(b in (0, 1, 2, 3, 0x0E, 0x0F) or b >= 0x3B)
                )
                if kind == 0 and b == 7:
                    style = 14  # Blooper
                if b == 5:
                    style = 10
                spawns.append(
                    (
                        max(0, x * 16 - 48) + j * 24 if group else x * 16,
                        (6 if (b - 0x37) & 2 else 10)
                        if group
                        else max(0, min(y - 1, 10)),
                        style + hard,
                    )
                )
        elif kind == 3 and b == 12:
            spawns.append((x * 16, 11, hard + 13))  # Podoboo erupts at this X
        elif kind == 3 and b == 0x2D:
            spawns.append((x * 16, y - 2, 5))
    return (
        (
            cols
            if name in ("UndergroundArea1", "UndergroundArea3")
            else cols[: goal + 17]
        ),
        goal,
        sorted(spawns),
    )


def pixels(chrdata, tile):
    a = chrdata[tile * 16 : tile * 16 + 16]
    return [
        [(a[y] >> i & 1) + 2 * (a[y + 8] >> i & 1) for i in range(7, -1, -1)]
        for y in range(8)
    ]


def compile_palettes(colors):
    # Only source hues actually used by the SMB background palettes. Index
    # zero of each NES subpalette means the common VDP backdrop.
    tms = {
        0x0F: 1,
        0x00: 1,
        0x10: 14,
        0x12: 4,
        0x15: 13,
        0x16: 8,
        0x17: 6,
        0x1A: 12,
        0x1C: 4,
        0x21: 5,
        0x25: 9,
        0x27: 11,
        0x29: 3,
        0x30: 15,
        0x36: 9,
        0x3A: 3,
        0x3C: 7,
        0x09: 2,
    }
    reset = (ROOT / "src/reset.s").read_text()

    def inks(theme):
        data = table(theme + "PaletteData", reset)[3:19]
        return [tms[v] for i, v in enumerate(data) if i % 4]

    themes = [inks(t) for t in ("Water", "Ground", "Underground", "Castle")]
    themes += [inks(t)[:3] + themes[1][3:] for t in ("DaySnow", "Mushroom")]
    (OUT / "themes.bin").write_bytes(
        bytes(v for row in themes for v in (0, *row, 15, 6, 11))
    )
    rows = {}
    ids = []
    for i in range(0, len(colors), 8):
        ids.append(rows.setdefault(bytes(colors[i : i + 8]), len(rows)))
    (OUT / "color_rows.bin").write_bytes(b"".join(rows))
    (OUT / "color_ids.bin").write_bytes(bytes(ids))


def graphics():
    src = (ROOT / "src/screen_render.s").read_text()
    raw = (ROOT / "chr/mmc3/bg_ground.chr").read_bytes()
    patterns, colors = bytearray(), bytearray()
    cache = {}

    def convert(n, palette):
        # Store logical NES inks, not a particular level's RGB colors. Rank
        # by the NES pixel index so the pattern geometry survives a recolor.
        key = n, palette
        if key in cache:
            return cache[key]
        idx = len(patterns) // 8
        for row in pixels(raw, n):
            counts = sorted(set(row), key=lambda v: (-row.count(v), v))
            bg = 0 if 0 in row else counts[0]
            fg = next((v for v in counts if v != bg), bg)
            if n in (0xAA, 0xAB, 0xBA, 0xBB, 0xAC, 0xAD, 0xBC, 0xBD):
                patterns.append(sum((v == 1) << (7 - i) for i, v in enumerate(row)))
                colors.append(
                    palette[1] << 4
                    | (palette[2] if n in (0xAC, 0xAD, 0xBC, 0xBD) else 0)
                )
                continue
            patterns.append(
                sum(
                    (v == fg or (v != bg and (bg == 0 or v != 3))) << (7 - i)
                    for i, v in enumerate(row)
                )
            )
            colors.append(palette[fg] * 16 + palette[bg])
        if idx >= 37:
            for old in range(idx):
                if (
                    patterns[-8:] == patterns[8 * old : 8 * old + 8]
                    and colors[-8:] == colors[8 * old : 8 * old + 8]
                ):
                    del patterns[-8:]
                    del colors[-8:]
                    idx = old
                    break
        cache[key] = idx
        return idx

    for i in range(37):
        convert(i, (0, 13, 13, 13))
    meta = bytearray(256 * 4)
    flags = bytearray(256)
    palettes = [(0, 1 + 3 * g, 2 + 3 * g, 3 + 3 * g) for g in range(4)]
    for line in src.splitlines():
        m = re.match(r"MTILE_CURRENT_INDEX .set \$(\w+)", line)
        if m:
            idx = int(m[1], 16)
        m = re.match(r"\s*MTileDefine (.*)", line)
        if not m:
            continue
        tiles = [int(v, 16) for v in re.findall(r"\$(\w\w)", m[1])[:4]]
        palette = palettes[idx >> 6]
        for i, j in enumerate([0, 2, 1, 3]):
            tile = convert(tiles[j], palette)
            meta[i * 256 + idx] = tile
            if idx == 0x52:
                meta[i * 256 + 0x8C] = tile
                flags[0x8C] = 1
            if idx in (0x86, 0x87):
                meta[i * 256 + idx + 4] = tile
        if idx == 0x86:
            for i in range(4):
                meta[i * 256 + 0x8D] = meta[(i % 2) * 256 + idx]
        flags[idx] = int("MTILE_SOLID" in line and idx not in (0xC2, 0xC3, 0x24, 0x25))
        idx += 1
    # Add HUD punctuation without consuming another metatile palette group.
    # Unused glyphs at the very end of the pattern bank.
    # Decode only the title sign from the NES PPU update stream, not its
    # attribute table, player selector or copyright line.
    data = (ROOT / "chr/raw/titlescreen.bin").read_bytes()
    i = 0
    logo = bytearray([36]) * (22 * 11)
    while data[i]:
        address, cmd = data[i] * 256 + data[i + 1], data[i + 2]
        i += 3
        count = cmd & 63
        for j in range(count):
            tile = data[i if cmd & 64 else i + j]
            row, col = divmod(address - 0x2000, 32)
            if 4 <= row <= 14 and 5 <= col <= 26:
                logo[(row - 4) * 22 + col - 5] = convert(tile, (0, 15, 14, 12))
            address += 32 if cmd & 128 else 1
        i += 1 if cmd & 64 else count
    for rows, col in [
        ([0, 0, 0, 126, 0, 0, 0, 0], 0xD0),
        ([24, 60, 118, 118, 118, 118, 60, 24], 0xA0),
    ]:
        patterns.extend(rows)
        colors.extend([col] * 8)
    (OUT / "glyphs.inc").write_text(
        f"DASH equ {len(patterns) // 8 - 2}\nHUD_COIN equ DASH+1\n"
    )
    pulse_ids = sorted(
        {
            meta[quarter * 256 + tile]
            for quarter in range(4)
            for tile in (0xC0, 0xC2, 0xC3)
        }
    )
    first, last = pulse_ids[0], pulse_ids[-1] + 1
    (OUT / "pulse.bin").write_bytes(colors[first * 8 : last * 8])
    assert (last - first) * 8 <= 96
    compile_palettes(colors)
    with (OUT / "glyphs.inc").open("a") as out:
        out.write(
            f"PULSE_OFFSET equ {first * 8}\nPULSE_BYTES equ {(last - first) * 8}\n"
        )
    assert len(patterns) <= 2048
    (OUT / "title.bin").write_bytes(logo)
    for name, buf in [
        ("patterns", patterns),
        ("colors", colors),
        ("meta", meta),
        ("solid", flags),
    ]:
        (OUT / (name + ".bin")).write_bytes(buf)
    banks = (ROOT / "chr/mmc3/sprites_mario.chr").read_bytes()
    mario_frames(banks)
    enemy = (ROOT / "chr/mmc3/sprites_overworld.chr").read_bytes()
    sprites = bytearray(24 * 8)  # two streamed 16x16 three-colour Mario halves

    def pair(raw, tiles, masks=((1, 3), (2,))):
        packed = b"".join(raw[i * 16 : i * 16 + 16] for i in tiles)
        for mask in masks:
            sprite(sprites, packed, 0, False, mask)

    # Koopa's head and body are separate 8x16 NES sprite pairs, not a
    # single four-tile box. The head has different IDs in each gait frame.
    for flip in (False, True):
        for tiles in ((0x38, 0x12), (0x18, 0x16), (0x30, 0x32), (0x34, 0x36)):
            half = b"".join(enemy[n * 16 : (n + 2) * 16] for n in tiles)
            for mask in ((1, 3), (2,)):
                sprite(sprites, half, 0, flip, mask)
    misc = (ROOT / "chr/mmc3/sprites_misc.chr").read_bytes()
    for mask in ((1, 3), (2,)):
        sprite(sprites, misc, 0x34, False, mask)  # 88,92: star
    for mask in ((1, 3), (2,)):
        sprite(sprites, misc[0x1A * 16 : 0x1C * 16] * 2, 0, False, mask)  # girder
    sprites.extend(bytes(128 * 8 - len(sprites)))
    boss = (ROOT / "chr/mmc5/sprites_enemies.chr").read_bytes()[2048:]
    bubble = boss[0x18 * 16 : 0x1A * 16]
    pair(bubble + bytes(int(f"{b:08b}"[::-1], 2) for b in bubble), range(4))
    # Mirror each 16-row TMS sprite column for the downward pose.
    up = bytes(sprites[-64:])
    sprites.extend(b"".join(up[i : i + 16][::-1] for i in range(0, 64, 16)))
    # Source spring frames: extended (two halves), half, fully compressed.
    # One shared red cap pattern plus four light-colored coil shapes.
    bank = enemy[1024:]
    for pose in (0x16, 0x36, 0x38, 0x14):
        half = bank[pose * 16 : (pose + 2) * 16]
        right = half if pose == 0x14 else bytes(int(f"{b:08b}"[::-1], 2) for b in half)
        pair(half + right, range(4), ((2, 3),))
    # The original shell uses the same half, mirrored on the right.
    shell = enemy[0x1A * 16 : 0x1C * 16]
    pair(shell + bytes(int(f"{b:08b}"[::-1], 2) for b in shell), range(4))
    water = (ROOT / "chr/mmc3/sprites_water.chr").read_bytes()
    pair(water, [0x2C, 0x2D, 0x2E, 0x2F])
    misc = (ROOT / "chr/mmc3/sprites_misc.chr").read_bytes()
    flower = misc[0x38 * 16 : 0x3A * 16]
    pair(flower + bytes(int(f"{b:08b}"[::-1], 2) for b in flower), range(4))
    boss = (ROOT / "chr/mmc5/sprites_enemies.chr").read_bytes()[2048:]
    # Face left: reflect each 16px half, then place head before shell.
    for pose in (8, 4, 0x28, 0x20):
        for mask in [(1,), (2, 3)]:
            sprite(sprites, boss, pose, True, mask)
    for flip in [False, True]:
        for mask in [(1, 3), (2,)]:
            sprite(sprites, enemy, 0x22, flip, mask)
    misc = (ROOT / "chr/mmc3/sprites_misc.chr").read_bytes()
    for mask in [(1, 3), (2,)]:
        sprite(sprites, misc, 0x3C, False, mask)
    # Each half of a 16x16 sprite occupies sixteen consecutive bytes.
    sprites.extend(bytes(6) + bytes([3, 7, 7, 3]) + bytes(6))
    sprites.extend(bytes(6) + bytes([192, 224, 224, 192]) + bytes(6))
    for mask in ((2,), (1, 3)):
        sprite(sprites, enemy[1024:], 0x32, False, mask)
    assert len(sprites) == 252 * 8
    sprites.extend((bytes([255, 255]) + bytes(14)) * 2)  # 252: spring cap
    (OUT / "sprites.bin").write_bytes(sprites)
    # Swap the castle boss out of VRAM for the outdoor enemy bank.
    sprites = bytearray()
    for raw, pose in (
        (enemy[1024:], 0x0C),
        (enemy, 0x1C),
        (enemy, 8),
        (enemy[1024:], 0x20),
    ):
        for mask in [(1, 3), (2,)]:
            sprite(sprites, raw, pose, False, mask)
    (OUT / "outdoor.bin").write_bytes(sprites)
    sprites = bytearray()
    for pose in (0x1A, 0x3A, 0x18):
        half = water[1024 + pose * 16 : 1024 + (pose + 2) * 16]
        pair(
            half + bytes(int(f"{b:08b}"[::-1], 2) for b in half),
            range(4),
            ((1, 2), (3,)),
        )
    pair(water, [0x2A, 0x2B, 0x2E, 0x2F])
    assert len(sprites) == 256
    (OUT / "swim.bin").write_bytes(sprites)


def mario_frames(banks):
    """Expand the source 8x16 pairs, deduplicating identical 16x16 halves.
    A frame descriptor names just two halves; only changed poses are uploaded.
    """
    src = (ROOT / "src/metasprite.s").read_text()
    frames = []
    halves = {}
    data = bytearray()
    poses = [
        "STANDING",
        "WALKING_1",
        "WALKING_2",
        "WALKING_3",
        "SKIDDING",
        "JUMPING",
        "CROUCHING",
        "CLIMBING_1",
        "CLIMBING_2",
        "DEATH",
        "GROW_INTERMEDIATE",
    ]
    poses += [f"SWIMMING_{n}_{phase}" for phase in ("KICK", "HOLD") for n in (1, 2, 3)]
    for size in ("SMALL", "BIG", "FIRE"):
        for pose in poses:
            obj = size + "_MARIO"
            name = pose
            if pose == "DEATH":
                obj = "SMALL_MARIO"
            if pose == "GROW_INTERMEDIATE":
                obj = "BIG_MARIO"
            if size == "SMALL" and pose == "CROUCHING":
                name = "STANDING"
            if size == "SMALL" and pose == "SWIMMING_3_HOLD":
                name = "SWIMMING_3_KICK"
            if size == "FIRE" and pose.startswith("CLIMB"):
                obj = "BIG_MARIO"
            if obj == "FIRE_MARIO" and pose == "WALKING_1":
                name = "STANDING"
            m = re.search(
                r'^MetaspriteBox "' + obj + '", "' + name + r'",(.*)$',
                src,
                re.MULTILINE,
            )
            ids = [int(n, 16) for n in re.findall(r"\$(\w{2})", m[1])]
            bank = (
                2
                if obj == "SMALL_MARIO"
                else 1
                if obj == "FIRE_MARIO" or pose.startswith(("CLIMB", "SWIM", "GROW"))
                else 0
            )
            if obj == "FIRE_MARIO" and pose == "CROUCHING":
                bank = 3
            bank = banks[bank * 1024 :]
            for flip in (False, True):
                ptrs = []
                for i in range(0, len(ids), 2):
                    raw = b"".join(bank[n * 16 : n * 16 + 32] for n in ids[i : i + 2])
                    buf = bytearray()
                    for mask in ((1,), (2,), (3,)):
                        sprite(buf, raw, 0, flip, mask)
                    if bytes(buf) not in halves:
                        halves[bytes(buf)] = len(data)
                        data.extend(buf)
                    ptrs.append("mario_data+" + str(halves[bytes(buf)]))
                if len(ptrs) == 1:
                    ptrs.insert(0, "0")
                frames.append(" dw " + ",".join(ptrs))
    (OUT / "poses.inc").write_text("pose_list:\n" + "\n".join(frames) + "\n")
    (OUT / "mario.bin").write_bytes(data)


def sprite(out, raw, pose, flip, mask):
    for quadrant in range(4):
        rows = pixels(raw, pose + (quadrant ^ (2 if flip else 0)))
        for row in rows:
            if flip:
                row = row[::-1]
            out.append(sum((v in mask) << (7 - i) for i, v in enumerate(row)))


def bonus_routes(name, ident, world):
    # A row-E enemy command sets the destination for subsequent enterable
    # pipes. Its third byte selects the world and entrance page.
    links = []
    returns = []
    list(objects(table("E_" + name) + [255], True, links))
    list(objects(table("E_UndergroundArea3"), True, returns))
    objs = list(objects(table("L_" + name)[2:]))
    for x, y, b in objs:
        if y >= 12 or b >> 3 != 15:
            continue
        targets = [e for e in links if e[0] <= x and e[2] >> 5 == world]
        if not targets or targets[-1][1] != 0x42:
            continue
        page = targets[-1][2] & 31
        matches = [
            v & 31
            for loc, dest, v in returns
            if loc // 16 in (page, page + 1) and dest == ident & 127 and v >> 5 == world
        ]
        if not matches:
            continue
        exit_page = matches[0]
        pipes = [
            (xx, yy)
            for xx, yy, bb in objs
            if xx // 16 == exit_page and yy < 12 and bb >> 4 == 7
        ]
        if pipes:
            xx, yy = pipes[0]
            yield (x, page // 2, xx, yy)


def compile_game():

    OUT.mkdir(exist_ok=True, parents=True)
    from music import compile_music

    compile_music(ROOT, OUT)
    graphics()

    common = (ROOT / "src/common.s").read_text()
    stages = []
    areas = {}
    pool = {}
    asm = []
    for w in range(1, 9):
        for ident in table(f"World{w}Areas", common):
            if ident == 0x29:
                continue  # pipe entrance cutscene, not a stage
            kind = ident >> 5 & 3
            name = (
                ["Water", "Ground", "Underground", "Castle"][kind]
                + "Area"
                + str((ident & 31) + 1)
            )
            routes = list(bonus_routes(name, ident, w - 1))
            asm += [f"pipes_stage{len(stages)}:"]
            for x, room, xx, yy in routes:
                # Return with the pipe in the middle of the visible screen.
                asm += [
                    f" dw {16 * x}, bonus_room{room}, {16 * (xx - 7)}",
                    f" db {(yy - 1) * 16}",
                ]
            asm += [" dw 65535"]
            stages.append(name)
            if name in areas:
                continue
            cols, goal, spawns = area(name, kind)
            areas[name] = cols
            asm += [
                f"{name}: dw columns_{name}, enemies_{name}, {goal * 16}",
                f" db {kind}",
                f" dw lifts_{name}",
                f"columns_{name}:",
            ]
            ids = [pool.setdefault(tuple(c), len(pool)) for c in cols]
            asm += [
                " dw " + ",".join(f"column{i}" for i in ids[j : j + 12])
                for j in range(0, len(ids), 12)
            ]
            asm += [f"lifts_{name}:"]
            for x, y, b in objects(table("E_" + name) + [255], True):
                if 0x24 <= (b & 63) <= 0x2C:
                    asm += [
                        f" dw {x * 16}",
                        f" db {max(0, min(11, y - 1)) * 16},{b & 63}",
                    ]
            for x, y, b in objects(table("L_" + name)[2:]):
                if y < 12 and b == 11:
                    asm.extend([f" dw {16 * x}", f" db {16 * y},$0b"])
            asm += [" dw 65535", f"enemies_{name}:"]
            for x, y, style in spawns:
                asm += [
                    f" dw {x | (0x8000 if style & 256 else 0)}",
                    f" db {y * 16 + (style & 15)}",
                ]
            asm += [" dw 65535", " db 0"]
    assert len(stages) == 32
    pages = table("HalfwayPageNybbles", (ROOT / "src/player.s").read_text())
    solid = (OUT / "solid.bin").read_bytes()
    asm += ["checkpoints:"]
    for i, name in enumerate(stages):
        page = (pages[i // 2] >> (0 if i & 1 else 4)) & 15
        cols = areas[name]
        # Pick a safe tile at the original halfway page, not inside a pipe
        # or in midair. Mario starts small after losing a life.
        choices = [
            (x, y)
            for x in range(1, 14)
            for y in range(11, 1, -1)
            if solid[cols[page * 16 + x][y]] and not solid[cols[page * 16 + x][y - 1]]
        ]
        x, y = choices[0] if choices else (1, 10)
        timer = [4, 4, 3, 2][table("L_" + name)[0] >> 6]
        asm += [f" db {page},{16 * x},{16 * (y - 1)},{timer}"]
    # NES backdrop $0f is black, $22 is sky blue; bonus rooms override it.
    backgrounds = table("BackgroundColors", (ROOT / "src/screen_render.s").read_text())
    skies = []
    themes = []
    for name in stages:
        kind = next(
            i
            for i, k in enumerate(("Water", "Ground", "Underground", "Castle"))
            if name.startswith(k)
        )
        level = table("L_" + name)
        control = level[0] & 7
        # The opening screen is prefetched before play (e.g. 3-1 sets
        # its night backdrop at column 6 rather than in the header).
        for x, row, cmd in objects(level[2:]):
            if x < 16 and row == 14 and cmd & 64 and cmd & 7 >= 4:
                control = cmd & 7
        themes.append(
            5
            if level[1] >> 6 == 1
            else 4
            if control in (5, 6)
            else 3
            if control == 7
            else kind
        )
        skies.append(1 if backgrounds[control if control >= 4 else kind] == 15 else 5)
    asm += ["stage_theme: db " + ",".join(map(str, themes))]
    asm += ["stage_sky: db " + ",".join(map(str, skies))]
    asm += ["stage_list: dw " + ",".join(stages)]
    asm += ["pipe_list: dw " + ",".join(f"pipes_stage{i}" for i in range(32))]
    bonus, _, _ = area("UndergroundArea3", 2)
    for room in range(5):
        ids = [
            pool.setdefault(tuple(c), len(pool))
            for c in bonus[32 * room : 32 * room + 16]
        ]
        asm += [
            f"bonus_room{room}: dw bonus_cols{room}, empty_enemies,208",
            " db 2",
            " dw empty_enemies",
            f"bonus_cols{room}: dw " + ",".join(f"column{i}" for i in ids),
        ]
    asm += ["empty_enemies: dw 65535"]
    # Overlap equal suffixes/prefixes; unpack still copies 12 raw bytes.
    pending = set(map(bytes, pool))
    packed = bytearray()
    while pending:
        prefix = bytes(packed[-11:])
        col = None
        for size in range(len(prefix), 0, -1):
            candidates = [c for c in pending if c.startswith(prefix[-size:])]
            if candidates:
                col = min(candidates)
                break
        if col is None:
            col = min(pending)
            size = 0
        pending.remove(col)
        packed.extend(col[size:])
    for col, i in pool.items():
        asm.append(f"column{i} equ column_pool+{packed.index(bytes(col))}")
    (OUT / "columns.bin").write_bytes(packed)
    asm.append('column_pool: incbin "columns.bin"')
    (OUT / "areas.inc").write_text("\n".join(asm) + "\n")
    print(len(areas), "distinct main areas;", len(pool), "unique columns")


if __name__ == "__main__":
    compile_game()
