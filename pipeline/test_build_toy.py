"""Narrow packaging regressions; actual texture quality is checked by build_toy."""
from pathlib import Path
import json
import tempfile
import unittest
import zipfile

import build_toy as build


class ToyPackagingTests(unittest.TestCase):
    def test_data_rename_updates_engine_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "index.pck").write_bytes(b"GDPC\0test-pack")
            config = {"executable": "index", "fileSizes": {"index.pck": 13, "index.wasm": 123}}
            (root / "index.html").write_text(
                "const GODOT_CONFIG = " + json.dumps(config) + ";\nnew Engine(GODOT_CONFIG);",
                encoding="utf-8")
            (root / "index.js").write_text(
                "const pack = this.config.mainPack; this.preloadFile(pack, pack);",
                encoding="utf-8")
            result = build.platform_package(root)
            self.assertFalse((root / "index.pck").exists())
            self.assertEqual((root / "index.data").read_bytes(), b"GDPC\0test-pack")
            text = (root / "index.html").read_text(encoding="utf-8")
            current, _ = json.JSONDecoder().raw_decode(text.split(" = ", 1)[1])
            self.assertEqual(current["mainPack"], "index.data")
            self.assertEqual(current["fileSizes"], {"index.data": 14, "index.wasm": 123})
            self.assertTrue(result["loader_main_pack_support_checked"])

    def test_zip_is_deterministic_and_rejects_unpublished_suffixes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            web = root / "web"
            web.mkdir()
            (web / "index.html").write_text("hello", encoding="utf-8")
            (web / "LICENSE.md").write_text("full license", encoding="utf-8")
            build.make_zip(web, root / "a.zip")
            build.make_zip(web, root / "b.zip")
            self.assertEqual(build.sha(root / "a.zip"), build.sha(root / "b.zip"))
            with zipfile.ZipFile(root / "a.zip") as archive:
                self.assertEqual(archive.namelist(), ["LICENSE.md", "index.html"])
            (web / "index.pck").write_bytes(b"not published")
            with self.assertRaisesRegex(RuntimeError, "whitelist"):
                build.make_zip(web, root / "invalid.zip")

    def test_compression_preserves_existing_geometry_and_sidecar_flags(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            png = root / "assets/pose.png"
            png.parent.mkdir()
            png.write_bytes(b"x" * 40000)
            sidecar = root / "assets/pose.png.import"
            sidecar.write_text(
                '[remap]\nimporter="texture"\n[params]\ncompress/mode=0\n'
                'compress/lossy_quality=0.7\nprocess/size_limit=1024\n'
                'mipmaps/generate=true\nprocess/fix_alpha_border=true\n',
                encoding="utf-8")
            profile = {"default": {"compression": "lossy", "quality": 0.8}, "rules": []}
            original = png.read_bytes()
            records = build.texture_settings(root, profile, False)
            result = sidecar.read_text(encoding="utf-8")
            self.assertEqual(png.read_bytes(), original)
            self.assertIn("process/size_limit=1024", result)
            self.assertIn("mipmaps/generate=true", result)
            self.assertIn("process/fix_alpha_border=true", result)
            self.assertIn("compress/mode=1", result)
            self.assertEqual(records[0]["settings"]["existing_size_limit"], 1024)

    def test_profile_keeps_functional_ui_and_small_food_lossless(self):
        profile = json.loads(build.PROFILE.read_text(encoding="utf-8"))
        for relative in ["assets/ui/numerals.png", "assets/ui/icon.png",
                         "assets/canteen/food_set_full.png", "assets/canteen/fx_gold.png"]:
            self.assertEqual(build.selection(relative, 500000, profile, False)["compression"], "lossless")
        self.assertEqual(build.selection("assets/ui/premium/logo_zh.png", 1000000, profile, False)["quality"], 0.9)
        self.assertEqual(build.selection("assets/canteen/cork_bg.png", 1000000, profile, True)["compression"], "lossless")


if __name__ == "__main__":
    unittest.main()
