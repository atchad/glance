#!/usr/bin/env python3
"""Exercise release note generation against temporary Git histories."""

import plistlib
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from conventional_commits import HEADER, MESSAGE_PATTERN


GENERATOR = Path(__file__).with_name("generate-release-notes.py")


class ReleaseNotesTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="glance-release-notes-")
        self.addCleanup(self.directory.cleanup)
        self.repo = Path(self.directory.name)
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Release notes test")
        self.git("config", "user.email", "test@example.invalid")
        (self.repo / "support").mkdir()
        self.set_version("0.5.2")

    def git(self, *arguments):
        return subprocess.check_output(
            ["git", "-C", str(self.repo), *arguments], stderr=subprocess.PIPE
        ).decode()

    def set_version(self, version):
        (self.repo / "support/Info.plist").write_bytes(
            plistlib.dumps({"CFBundleShortVersionString": version})
        )

    def commit(self, subject):
        self.git("add", ".")
        self.git("commit", "--allow-empty", "-m", subject)

    def baseline(self):
        self.commit("Previous release")
        self.git("tag", "-a", "v0.5.2", "-m", "Glance 0.5.2")
        self.set_version("0.5.3")

    def notes(self, revision="HEAD"):
        return subprocess.check_output(
            [sys.executable, str(GENERATOR), "--repo", str(self.repo), "--revision", revision]
        ).decode()

    def test_excludes_preparation_variants_and_preserves_product_changes(self):
        self.baseline()
        self.commit("Fix overlapping Settings sidebar glass (#81)")
        for subject in (
            "Prepare Glance 0.5.3 release (#82)",
            "Prepare Glance release 0.5.3",
            "Prepare Glance release v0.5.3 (#82)",
        ):
            self.commit(subject)
        self.commit("Fix release notes display (#85)")
        self.commit("Prepare Glance 0.5.3 release notes preview (#86)")
        notes = self.notes()
        self.assertIn("- Fix overlapping Settings sidebar glass (#81)", notes)
        self.assertIn("- Fix release notes display (#85)", notes)
        self.assertIn("- Prepare Glance 0.5.3 release notes preview (#86)", notes)
        self.assertNotIn("- Prepare Glance 0.5.3 release (#82)", notes)
        self.assertNotIn("- Prepare Glance release", notes)
        self.assertNotIn("Previous release", notes)
        self.assertIn("compare/v0.5.2...v0.5.3", notes)

    def test_merge_includes_pr_once_without_internal_commits(self):
        self.baseline()
        self.commit("Prepare Glance 0.5.3 release")
        self.git("checkout", "-b", "feature")
        self.commit("Internal implementation step")
        self.commit("Internal fixup")
        self.git("checkout", "main")
        self.git("merge", "--no-ff", "feature", "-m", "Add anchored search (#84)")
        notes = self.notes()
        self.assertEqual(notes.count("Add anchored search"), 1)
        self.assertNotIn("Internal", notes)
        self.assertNotIn("Prepare Glance", notes)

    def test_first_release_includes_history_before_preparation(self):
        self.set_version("0.1.0")
        self.commit("Add pull request dashboard")
        self.commit("Add keyboard navigation")
        self.commit("Prepare Glance 0.1.0 release")
        notes = self.notes()
        self.assertIn("Add pull request dashboard", notes)
        self.assertIn("Add keyboard navigation", notes)
        self.assertNotIn("Prepare Glance", notes)
        self.assertIn("commits/v0.1.0", notes)

    def test_preparation_only_release_has_changelog_without_empty_bullets(self):
        self.baseline()
        self.commit("Prepare Glance 0.5.3 release")
        notes = self.notes()
        self.assertNotIn("Prepare Glance", notes)
        self.assertNotIn("\n- ", notes)
        self.assertIn("See the full changelog for details.", notes)
        self.assertIn("compare/v0.5.2...v0.5.3", notes)

    def test_historical_revision_uses_its_version_and_changes(self):
        self.baseline()
        self.commit("Fix Settings glass")
        self.git("tag", "v0.5.3")
        self.set_version("0.5.4")
        self.commit("Add later feature")
        notes = self.notes("v0.5.3")
        self.assertIn("Fix Settings glass", notes)
        self.assertNotIn("later feature", notes)
        self.assertIn("compare/v0.5.2...v0.5.3", notes)

    def test_previous_tag_is_chosen_by_numeric_version(self):
        self.set_version("0.9.0")
        self.commit("Old feature")
        self.git("tag", "v0.9.0")
        self.set_version("0.10.0")
        self.commit("Previous feature")
        self.git("tag", "v0.10.0")
        self.set_version("0.11.0")
        self.commit("Current feature")
        self.git("tag", "v0.11.0")
        notes = self.notes()
        self.assertIn("Current feature", notes)
        self.assertNotIn("Previous feature", notes)
        self.assertNotIn("Old feature", notes)
        self.assertIn("compare/v0.10.0...v0.11.0", notes)

    def test_conventional_prefixes_are_removed_and_preparation_is_excluded(self):
        self.baseline()
        self.commit("fix(settings): anchor shortcut search (#84)")
        self.commit("chore(release): prepare Glance 0.5.3 release (#82)")
        notes = self.notes()
        self.assertIn("- anchor shortcut search (#84)", notes)
        self.assertNotIn("fix(settings)", notes)
        self.assertNotIn("prepare Glance", notes)

    def test_breaking_changes_remain_visible(self):
        self.baseline()
        self.commit("feat(config)!: change the keybinding format")
        self.commit("refactor(cache): replace cache schema\n\nBREAKING CHANGE: old cache files are incompatible")
        notes = self.notes()
        self.assertIn("**Breaking change:** change the keybinding format", notes)
        self.assertIn("**Breaking change:** replace cache schema", notes)


class ConventionalCommitTests(unittest.TestCase):
    def test_valid_headers(self):
        for title in (
            "fix: repair scrolling",
            "feat(settings): add appearance controls",
            "feat(config)!: change format",
            "chore!: remove legacy config",
            "build(deps): bump Sparkle from 2.9.0 to 2.10.0",
            "ci(deps): bump actions/checkout from 6 to 7",
            "docs: explain releases (#85)",
        ):
            with self.subTest(title=title):
                self.assertIsNotNone(HEADER.fullmatch(title))

    def test_invalid_headers(self):
        for title in (
            "Fix scrolling", "Fix: scrolling", "feature: scrolling", "fix: ",
            "fix:no space", "fix(): scrolling", " fix: scrolling", "fix:  scrolling",
            "fix(settings): scrolling\nextra line", "fix(settings\nother): scrolling",
        ):
            with self.subTest(title=title):
                self.assertIsNone(HEADER.fullmatch(title))

    def test_repository_pattern_accepts_bodies_but_requires_valid_header(self):
        pattern = re.compile(MESSAGE_PATTERN)
        self.assertIsNotNone(pattern.fullmatch("fix: repair scrolling\n\nDetailed explanation.\n"))
        self.assertIsNotNone(pattern.fullmatch("feat!: change format\n\nBREAKING CHANGE: new format"))
        self.assertIsNone(pattern.fullmatch("Repair scrolling\n\nfix: valid line later"))
        self.assertIsNone(pattern.fullmatch("fix: \n\nDescription only in body"))

    def test_title_validator_cli_exit_status(self):
        validator = GENERATOR.with_name("conventional_commits.py")
        for title, expected in (("fix(settings): repair scrolling", 0), ("Repair scrolling", 1)):
            with self.subTest(title=title):
                result = subprocess.run(
                    [sys.executable, str(validator)], env=dict(os.environ, PR_TITLE=title),
                    capture_output=True, text=True,
                )
                self.assertEqual(result.returncode, expected)


if __name__ == "__main__":
    unittest.main()
