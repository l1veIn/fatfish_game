"""Narrow packaging regressions; actual texture quality is checked by build_toy."""
from pathlib import Path
import json
import tempfile
import unittest
import zipfile

import build_toy as build


class ToyPackagingTests(unittest.TestCase):
    def test_fingerprints_keep_engine_urls_stable_when_only_game_data_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            results = []
            for number, data in enumerate([b"same game", b"same game", b"fixed helper"]):
                web = root / str(number)
                web.mkdir()
                for name in ["index.js", "index.wasm", "index.audio.worklet.js", "index.audio.position.worklet.js", "toy_bridge.js"]:
                    (web / name).write_bytes(name.encode())
                (web / "index.data").write_bytes(data)
                config = {"executable": "index", "mainPack": "index.data", "fileSizes": {"index.data": len(data), "index.wasm": 10}}
                (web / "index.html").write_text('<script src="toy_bridge.js"></script><script src="index.js"></script>const GODOT_CONFIG = ' + json.dumps(config) + ';', encoding="utf-8")
                result = build.fingerprint_web_assets(web)
                results.append(result)
                for old, new in result["renamed"].items():
                    self.assertFalse((web / old).exists())
                    self.assertTrue((web / new).is_file())
                self.assertIn(f'src="{result["executable"]}.js"', (web / "index.html").read_text())
                self.assertEqual(result["file_sizes"][result["main_pack"]], len(data))
            self.assertEqual(results[0], results[1])
            self.assertEqual(results[0]["executable"], results[2]["executable"])
            self.assertNotEqual(results[0]["main_pack"], results[2]["main_pack"])

    def test_loader_patch_refuses_an_unrecognized_template_without_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            loader = root / "index.js"
            loader.write_text("unexpected future loader", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "loader error handling changed"):
                build.repair_loader_errors(root)
            self.assertEqual(loader.read_text(encoding="utf-8"), "unexpected future loader")

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
