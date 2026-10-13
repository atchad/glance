#!/usr/bin/env python3
"""Generate the shared GitHub and Sparkle notes from release history."""

import argparse
import plistlib
import re
import subprocess
from pathlib import Path

from conventional_commits import description, is_breaking


RELEASE_PREPARATION = re.compile(
    r"Prepare Glance (?:release )?v?\d+\.\d+\.\d+(?: release)?(?: \(#\d+\))?",
    re.IGNORECASE,
)
REPOSITORY_URL = "https://github.com/atchad/glance"


def git(repo, *arguments):
    return subprocess.check_output(["git", "-C", str(repo), *arguments])


def generate(repo, revision):
    info = plistlib.loads(git(repo, "show", f"{revision}:support/Info.plist"))
    version = info["CFBundleShortVersionString"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError(f"Invalid release version: {version}")
    tag = f"v{version}"
    current_version = tuple(map(int, version.split(".")))
    previous_tags = []
    for candidate in git(repo, "tag", "--merged", revision).decode().splitlines():
        if re.fullmatch(r"v\d+\.\d+\.\d+", candidate):
            candidate_version = tuple(map(int, candidate[1:].split(".")))
            if candidate_version < current_version:
                previous_tags.append((candidate_version, candidate))
    previous_tag = max(previous_tags)[1] if previous_tags else None
    history = f"{previous_tag}..{revision}" if previous_tag else revision
    messages = git(repo, "log", "--first-parent", "--format=%B%x00", history).decode().split("\0")
    changes = []
    for message in messages:
        message = message.strip("\n")
        if not message:
            continue
        subject = description(message.splitlines()[0])
        if not RELEASE_PREPARATION.fullmatch(subject):
            changes.append(f"**Breaking change:** {subject}" if is_breaking(message) else subject)
    notes = "## What's Changed\n\n"
    if changes:
        notes += "\n".join(f"- {subject}" for subject in changes) + "\n\n"
    else:
        notes += "See the full changelog for details.\n\n"
    changelog = (
        f"{REPOSITORY_URL}/compare/{previous_tag}...{tag}"
        if previous_tag else f"{REPOSITORY_URL}/commits/{tag}"
    )
    return notes + f"[Full changelog]({changelog})\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--revision", default="HEAD")
    arguments = parser.parse_args()
    print(generate(arguments.repo, arguments.revision), end="")
