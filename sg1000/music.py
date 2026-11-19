"""Compile the vanilla SMB score into independently timed PSG parts.

One duration byte (high bit set) is shared by successive notes. Identical
parts share ROM, including the noise ostinatos in the overworld phrases.
"""

import re


def compile_music(root, out):
    src = (root / "src/music_drivers/vanilla_music.s").read_text()
    headers = {
        name: (
            int(tempo, 16),
            base,
            [int(v, 16) for v in re.findall(r"\$(\w+)", offsets)],
        )
        for name, tempo, base, offsets in re.findall(
            r"^(\w+Hdr):\s+\.byte \$(\w+), <(\w+), >\w+, ([^\n]+)", src, re.MULTILINE
        )
    }
    blob = []
    labels = {}
    for line in src.split(";MUSIC DATA", 1)[1].splitlines():
        line = line.partition(";")[0].strip()
        if line.endswith(":"):
            labels[line[:-1]] = len(blob)
        if line.startswith(".byte"):
            blob.extend(int(v, 16) for v in re.findall(r"\$(\w+)", line))
    ground = re.findall(
        r"(GroundLevel\w+Hdr)-MHD",
        src[
            src.rindex("\n", 0, src.index(";ground level music layout")) : src.index(
                ";music headers"
            )
        ],
    )
    songs = [
        ["WaterMusHdr"],
        ground,
        ["UndergroundMusHdr"],
        ["CastleMusHdr"],
        ["Star_CloudHdr"],
        ["DeathMusHdr"],
        ["GameOverMusHdr"],
        ["EndOfLevelMusHdr"],
        ["WinCastleMusHdr"],
        ["VictoryMusHdr"],
    ]
    parts = {}
    asm = ["song_list: dw " + ",".join(f"song{i}" for i in range(len(songs)))]
    freq = blob[labels["FreqRegLookupTbl"] : labels["MusicLengthLookupTbl"]]
    lens = blob[labels["MusicLengthLookupTbl"] :]
    for i, song in enumerate(songs):
        asm += [
            f"song{i}: dw "
            + ",".join(song)
            + ",0,"
            + ("song1+2" if i == 1 else f"song{i}" if i < 5 else "0")
        ]
    for hdr in sorted({hdr for song in songs for hdr in song}):
        tempo, base, offset = headers[hdr]
        tri, sq = offset[:2]
        noise = offset[2] if len(offset) > 2 and hdr != "DeathMusHdr" else 0
        end = 65535
        ptrs = []
        for ch, off in enumerate([0, sq, tri, noise]):
            p = start = labels[base] + off
            t = 0
            duration = 1
            last = 0
            stream = []
            while t < end and (ch in (0, 2) or off):
                n = blob[p]
                p += 1
                if ch in (0, 2):
                    if not n:
                        break
                    if n & 128:
                        duration = lens[tempo + (n & 7)]
                        continue
                    note = n // 2
                else:
                    if not n:
                        if ch == 3:
                            p = start
                        continue
                    duration = lens[tempo + ((n & 1) * 4 + (n >> 6))]
                    note = (n & 62) // 2 if ch == 1 else (n >> 4) & 3
                if duration != last:
                    stream.append(128 + duration)
                    last = duration
                stream.append(note + 1)
                t += duration
            if ch == 0:
                end = t
            stream.append(0)
            ptrs.append("part" + str(parts.setdefault(bytes(stream), len(parts))))
        asm.append(hdr + ": dw " + ",".join(ptrs))
    for data, i in parts.items():
        asm.append(f"part{i}:")
        asm.extend(
            " db " + ",".join(map(str, data[j : j + 64]))
            for j in range(0, len(data), 64)
        )
    for name, mul in [("tone", 1), ("bass", 2)]:
        periods = []
        for hi, lo in zip(freq[::2], freq[1::2]):
            n = (hi * 256 + lo + 1) * mul if hi or lo else 0
            while n > 1023:
                n //= 2
            periods.extend((n & 15, n >> 4))
        asm.append(name + "_period: db " + ",".join(map(str, periods)))
    (out / "music.inc").write_text("\n".join(asm) + "\n")
