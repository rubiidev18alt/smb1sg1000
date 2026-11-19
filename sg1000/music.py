"""Translate the vanilla melody and bass streams to timed SN76489 writes."""

import re
from itertools import pairwise


def compile_music(root, out):
    src = (root / "src/music_drivers/vanilla_music.s").read_text()
    headers = {
        n: (int(tempo, 16), name, int(tri, 16))
        for n, tempo, name, tri in re.findall(
            r"^(\w+Hdr):\s+\.byte \$(\w+), <(\w+), >\w+, \$(\w+)", src, re.MULTILINE
        )
    }
    # Some phrases intentionally fall through into the next ca65 label.
    blob, labels = [], {}
    for line in src[src.index(";music headers") :].splitlines():
        line = line.split(";")[0].strip()
        if ":" in line:
            label, line = line.split(":", 1)
            labels[label] = len(blob)
        if line.strip().startswith(".byte") and "<" not in line:
            blob.extend(int(v, 16) for v in re.findall(r"\$([\da-fA-F]+)", line))
    freq = labels["FreqRegLookupTbl"]
    lengths = labels["MusicLengthLookupTbl"]
    ground = re.findall(
        r"(GroundLevel\w+Hdr)-MHD",
        src.split(";ground level music layout")[1].split(";music headers")[0],
    )
    ground.insert(0, "GroundLevelLeadInHdr")
    songs = [
        ["WaterMusHdr"],
        ground,
        ["UndergroundMusHdr"],
        ["CastleMusHdr"],
        ["DeathMusHdr"],
        ["GameOverMusHdr"],
        ["EndOfLevelMusHdr"],
        ["VictoryMusHdr"],
        ["WinCastleMusHdr"],
    ]
    asm = ["song_list: dw " + ",".join(f"song{i}" for i in range(len(songs)))]
    for i, song in enumerate(songs):
        asm += [
            f"song{i}: dw " + ",".join(song),
            " dw 0," + (f"song{i}" if i < 4 else "quiet_song"),
        ]
    asm += [
        "quiet_song: dw quiet_phrase,0,quiet_song",
        "quiet_phrase: db 255,2,$bf,$df,0",
    ]
    for hdr in sorted({hdr for song in songs for hdr in song}):
        tempo, base, tri = headers[hdr]
        events = {}
        end = 65535
        for channel, offset in [(1, 0), (2, tri)]:
            t = 0
            p = labels[base] + offset
            length = 1
            while t < end:
                n = blob[p]
                p += 1
                if not n:
                    break
                if n & 128:
                    length = blob[lengths + tempo + (n & 7)]
                    continue
                period = (blob[freq + n] << 8) | blob[freq + n + 1]
                latch = 128 + channel * 32
                if period:
                    # Master clocks are in a 2:1 ratio, but PSG divides by
                    # 32 vs 16 for NES pulse. Triangle plays an octave lower.
                    period = (period + 1) * channel
                    while period > 1023:
                        period //= 2
                    cmds = [
                        latch + (period & 15),
                        period >> 4,
                        latch + 16 + (5 if channel == 1 else 9),
                    ]
                else:
                    cmds = [latch + 31]
                events.setdefault(t, []).extend(cmds)
                t += length
            if channel == 1:
                end = t
        times = sorted(events) + [end]
        asm += [hdr + ":"]
        for t, u in pairwise(times):
            asm += [" db " + ",".join(map(str, [u - t, len(events[t])] + events[t]))]
        asm += [" db 0"]
    (out / "music.inc").write_text("\n".join(asm) + "\n")
