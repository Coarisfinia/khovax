"""Tests asset_credits_check.py (#2585) on a small pack: a fully credited one passes; an asset
folder without its note, a listed asset no note covers, a note missing a field and every way an
asset can be under the Quaternius Asset License (#1954) fail; the owner's OK lets the last through.

    uv run --locked --package khovax-game-checks src/game-checks/test_asset_credits_check.py
"""

import os
import tempfile
import unittest
from pathlib import Path

from asset_credits_check import problems

NOTE = """# Wolf

- **Author:** someone (https://example.org)
- **Source:** https://example.org/wolf, the file
  `wolf.glb`
- **License:** CC0 1.0, see `LICENSE.md` next to this file.
"""
QAL_TEXT = "Quaternius Asset License\n\nYou may not redistribute the assets.\n"


class AssetCreditsTest(unittest.TestCase):
    def setUp(self) -> None:
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.addCleanup(os.chdir, os.getcwd())
        os.chdir(folder.name)
        self.root = "pack/"
        self.write("models/wolf/SOURCE.md", NOTE)
        self.write("models/wolf/wolf.glb", "")
        self.write("models/wolf/LICENSE.md", "CC0 1.0 Universal\n")
        self.manifest: dict[str, object] = {"textures": {}, "models": {"model_wolf": "pack/models/wolf/wolf.glb"}, "audio": {}}

    def write(self, path: str, text: str) -> None:
        target = Path(self.root, path)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")

    def messages(self) -> list[str]:
        return [message for message, _ in problems(self.manifest, self.root)]

    def test_a_credited_pack_passes(self) -> None:
        self.assertEqual(self.messages(), [])

    def test_a_note_in_a_folder_above_credits_an_asset(self) -> None:
        self.write("models/wolf/lod/wolf_far.glb", "")
        self.manifest["models"] = {"model_wolf": "pack/models/wolf/lod/wolf_far.glb"}
        self.assertEqual(self.messages(), [])

    def test_an_asset_folder_without_a_note_fails(self) -> None:
        self.write("textures/icons/cog.svg", "")
        self.manifest["textures"] = {"icon_cog": "pack/textures/icons/cog.svg"}
        found = problems(self.manifest, self.root)
        self.assertIn(("has no SOURCE.md crediting its author, source and license", "pack/textures/icons"), found)
        self.assertTrue(any(file == "pack/textures/icons/cog.svg" for _, file in found))

    def test_an_asset_loose_in_its_kind_folder_fails(self) -> None:
        self.write("audio/theme.ogg", "")
        self.manifest["audio"] = {"music_theme": "pack/audio/theme.ogg"}
        self.assertEqual(self.messages(), ["audio music_theme's file has no SOURCE.md beside it or above it in the pack"])

    def test_a_missing_or_empty_field_fails(self) -> None:
        for line in ("- **Author:** someone (https://example.org)\n", "# Wolf\n"):
            with self.subTest(line=line):
                self.write("models/wolf/SOURCE.md", NOTE.replace(line, ""))
                self.assertEqual(len(self.messages()), 1)
        self.write("models/wolf/SOURCE.md", NOTE.replace("CC0 1.0, see `LICENSE.md` next to this file.", ""))
        self.assertEqual(self.messages(), ["has no - **License:** line, or leaves it empty (#70)"])

    def test_the_qal_is_refused(self) -> None:
        cases = {
            "source": NOTE.replace("https://example.org/wolf", "https://quaternius.com/packs/wolf.html"),
            "license": NOTE.replace("CC0 1.0", "the Quaternius Asset License"),
            "short name": NOTE.replace("CC0 1.0", "QAL"),
        }
        for what, note in cases.items():
            with self.subTest(what=what):
                self.write("models/wolf/SOURCE.md", note)
                found = self.messages()
                self.assertEqual(len(found), 1, found)
                self.assertIn("(#1954)", found[0])
        self.write("models/wolf/SOURCE.md", NOTE)
        self.write("models/wolf/build/LICENCE.txt", QAL_TEXT)
        self.assertIn("LICENCE.txt is the Quaternius Asset License", self.messages()[0])

    def test_poly_pizzas_cc0_pages_pass(self) -> None:
        self.write("models/wolf/SOURCE.md", NOTE.replace("https://example.org/wolf", "https://poly.pizza/m/x by Quaternius"))
        self.assertEqual(self.messages(), [])

    def test_the_owners_ok_lets_the_qal_through(self) -> None:
        self.write("models/wolf/SOURCE.md", NOTE.replace("CC0 1.0", "QAL") + "- **Owner's OK:** khovax #1954\n")
        self.assertEqual(self.messages(), [])


if __name__ == "__main__":
    unittest.main()
