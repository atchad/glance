#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("build_cache", Path(__file__).with_name("build-cache.py"))
cache = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache)


class BuildCacheTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        (self.root / "Sources").mkdir()
        self.file = self.root / "Sources" / "Example.swift"
        self.file.write_text("let value = 1\n")
        subprocess.run(["git", "-C", str(self.root), "add", "Sources"], check=True)
        self.original = self.file.stat().st_mtime_ns

    def test_restores_only_identical_content(self):
        cache.synchronize(self.root, "save")
        os.utime(self.file, ns=(self.original, self.original + 1_000_000_000))
        self.assertEqual(cache.synchronize(self.root, "restore"), 1)
        self.assertEqual(self.file.stat().st_mtime_ns, self.original)
        self.file.write_text("let value = 2\n")
        changed = self.file.stat().st_mtime_ns
        self.assertEqual(cache.synchronize(self.root, "restore"), 0)
        self.assertEqual(self.file.stat().st_mtime_ns, changed)
        self.assertEqual(self.file.read_text(), "let value = 2\n")

    def test_ignores_untracked_and_deleted_inputs(self):
        cache.synchronize(self.root, "save")
        self.file.unlink()
        (self.root / "Sources" / "New.swift").write_text("new content")
        self.assertEqual(cache.synchronize(self.root, "restore"), 0)

    def test_missing_and_invalid_manifests_are_cache_misses(self):
        self.assertEqual(cache.synchronize(self.root, "restore"), 0)
        manifest = self.root / ".build" / "glance-input-timestamps.json"
        manifest.parent.mkdir()
        for data in ["broken", "[]", json.dumps({"Sources/Example.swift": {"mtime_ns": -1}})]:
            manifest.write_text(data)
            self.assertEqual(cache.synchronize(self.root, "restore"), 0)


if __name__ == "__main__":
    unittest.main()
