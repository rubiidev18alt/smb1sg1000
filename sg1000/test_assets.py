"""Cartridge data contracts. Run after the assembler, from the repository root."""

import unittest

from assets import OUT, ROOT, area, bonus_routes, objects, table


class CartridgeTest(unittest.TestCase):
    def test_real_world_one(self):
        cols, goal, enemies = area("GroundArea6", 1)
        self.assertEqual((cols[16][7], cols[21][7]), (0xC0, 0xC1))
        self.assertEqual(cols[28][9:12], [0x12, 0x14, 0x54])
        self.assertEqual(cols[101][7], 0x57)  # Starman brick
        self.assertEqual(cols[69][11], 0)  # first pit
        self.assertIn((22 * 16, 10, 0), enemies)
        self.assertEqual((goal, cols[goal][1]), (198, 0x24))
        self.assertIn((57, 0, 163, 9), bonus_routes("GroundArea6", 0x25, 0))

    def test_page_controls_and_links(self):
        links = []
        commands = list(objects([0x0F, 3, 0x1E, 0xC2, 2, 0x6B, 6, 0xFF], True, links))
        self.assertEqual(links, [(49, 0x42, 2)])
        self.assertEqual(commands, [(54, 11, 6)])

    def test_later_worlds(self):
        # Row F with the advance bit isn't an explicit page reload.
        stream = [0x0F, 7, 0x7B, 0x43, 0xC6, 0xD0, 0x0F, 0x8A, 0xC8, 0x50, 255]
        self.assertEqual(list(objects(stream, True))[-1], (9 * 16 + 12, 8, 0x50))
        _, _, enemies = area("GroundArea9", 1)
        self.assertIn((672, 10, 0), enemies)
        self.assertIn((696, 10, 0), enemies)  # 24-pixel group spacing
        cols, _, enemies = area("CastleArea3", 3)
        self.assertIn((256, 11, 13), enemies)
        self.assertIn((320, 11, 256 + 13), enemies)  # hard-only on revisiting as 5-4
        self.assertIn((2160, 6, 5), enemies)
        self.assertIn(0x8A, {v for col in cols for v in col})
        meta = (OUT / "meta.bin").read_bytes()
        colors = (OUT / "colors.bin").read_bytes()
        body = meta[0x8B] * 8
        self.assertTrue(all(b == 0x88 for b in colors[body : body + 8]))
        self.assertNotEqual(meta[0x8B], meta[0x87])  # overworld water stays blue

    def test_rom_tables(self):
        import re

        symbols = {
            n: int(v, 16)
            for n, v in re.findall(
                r"^(\S+): EQU 0x(\w+)", (OUT / "game.sym").read_text(), re.MULTILINE
            )
        }
        rom = (OUT.parent / "smb1.sg").read_bytes()
        self.assertEqual(len(rom), 49152)

        def word(addr):
            return int.from_bytes(rom[addr : addr + 2], "little")

        common = (ROOT / "src/common.s").read_text()
        stages = []
        for world in range(1, 9):
            stages.extend(v for v in table(f"World{world}Areas", common) if v != 0x29)
        self.assertEqual(len(stages), 32)
        skies = symbols["stage_sky"]
        self.assertEqual((rom[skies + 4], rom[skies + 8]), (5, 1))  # 2-1 day, 3-1 night
        for i, v in enumerate(stages):
            k = (v >> 5) & 3
            name = (
                ("Water", "Ground", "Underground", "Castle")[k]
                + "Area"
                + str((v & 31) + 1)
            )
            desc = word(symbols["stage_list"] + 2 * i)
            self.assertEqual(desc, symbols[name])
            cols, goal, _ = area(name, k)
            self.assertEqual((word(desc + 4), rom[desc + 6]), (goal * 16, k))
            addr = word(desc)
            lift = word(desc + 7)
            self.assertEqual(lift, addr + 2 * len(cols))
            expected = [
                (x * 16, max(0, min(11, y - 1)) * 16, b & 63)
                for x, y, b in objects(table("E_" + name) + [255], True)
                if 0x24 <= b & 63 <= 0x2C
            ]
            for x, y, style in expected:
                self.assertEqual(
                    (word(lift), rom[lift + 2], rom[lift + 3]), (x, y, style)
                )
                lift += 4
            self.assertEqual(word(lift), 65535)
            for x, col in enumerate(cols):
                p = word(addr + 2 * x)
                self.assertEqual(rom[p : p + 12], bytes(col))
        self.assertLessEqual(symbols["s"] + symbols["State"], symbols["actors"])
        self.assertLessEqual(
            symbols["sat"] + 128, 0xC300
        )  # reserve at least 256B stack
        for filename in ["sprites", "patterns", "colors"]:
            self.assertLessEqual((OUT / (filename + ".bin")).stat().st_size, 2048)


if __name__ == "__main__":
    unittest.main()
