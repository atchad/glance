#!/usr/bin/env python3
"""Verify installer concurrency and failure gates without signing or contacting Apple."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class InstallerTests(unittest.TestCase):
    def run_packagers(self, failing):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts = root / "scripts"
            scripts.mkdir()
            shutil.copyfile(Path(__file__).with_name("build-installers.sh"), scripts / "build-installers.sh")
            (scripts / "build-app.sh").write_text('[[ "$1" == release ]] || exit 2\ntouch app-ready\n')
            for kind, peer in [("dmg", "pkg"), ("pkg", "dmg")]:
                (scripts / f"build-{kind}.sh").write_text(f'''
set -euo pipefail
[[ "$1" == --use-existing-app && -f app-ready ]] || exit 2
touch {kind}-started
# Rendezvous fails if the coordinator serializes packaging.
for attempt in {{1..100}}; do
  [[ -f {peer}-started ]] && break
  sleep 0.01
done
[[ -f {peer}-started ]] || exit 3
sleep 0.05
touch {kind}-finished
print '{kind} log preserved'
[[ "$FAIL_PACKAGER" != {kind} && "$FAIL_PACKAGER" != both ]]
''')
            result = subprocess.run(
                ["zsh", str(scripts / "build-installers.sh")],
                env={**os.environ, "FAIL_PACKAGER": failing},
                capture_output=True, text=True, timeout=10,
            )
            self.assertTrue((root / "dmg-finished").exists(), result.stderr)
            self.assertTrue((root / "pkg-finished").exists(), result.stderr)
            self.assertIn("dmg log preserved", result.stdout)
            self.assertIn("pkg log preserved", result.stdout)
            self.assertEqual(result.returncode, 0 if failing == "none" else 1, result.stderr)

    def test_parallel_success(self):
        self.run_packagers("none")

    def test_waits_for_both_and_preserves_failure(self):
        for failing in ["dmg", "pkg", "both"]:
            with self.subTest(failing=failing):
                self.run_packagers(failing)

    def test_app_failure_prevents_packaging(self):
        with tempfile.TemporaryDirectory() as directory:
            scripts = Path(directory) / "scripts"
            scripts.mkdir()
            shutil.copyfile(Path(__file__).with_name("build-installers.sh"), scripts / "build-installers.sh")
            (scripts / "build-app.sh").write_text("exit 9\n")
            result = subprocess.run(["zsh", str(scripts / "build-installers.sh")],
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 9)


if __name__ == "__main__":
    unittest.main()
