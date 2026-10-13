#!/usr/bin/env python3
"""Parse Conventional Commit subjects and validate a PR title."""

import os
import re
import sys
import subprocess


HEADER_PATTERN = (
    r"^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)"
    r"(\([^()\r\n]+\))?(!)?: (\S[^\r\n]*)$"
)
HEADER = re.compile(HEADER_PATTERN)


def description(subject):
    match = HEADER.fullmatch(subject)
    return match.group(4) if match else subject


def is_breaking(message):
    match = HEADER.fullmatch(message.splitlines()[0])
    return bool((match and match.group(3)) or re.search(r"(?m)^BREAKING[ -]CHANGE: \S", message))


if __name__ == "__main__":
    title = os.environ.get("PR_TITLE", "")
    valid = True
    if not HEADER.fullmatch(title):
        print(
            "PR titles must use <type>[optional scope][optional !]: <description>.\n"
            "Types: build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test.\n"
            "Example: fix(settings): anchor shortcut search",
            file=sys.stderr,
        )
        valid = False
    base = os.environ.get("PR_BASE_SHA")
    head = os.environ.get("PR_HEAD_SHA")
    if base or head:
        if not all(value and re.fullmatch(r"[0-9a-f]{40,64}", value) for value in (base, head)):
            print("Both PR_BASE_SHA and PR_HEAD_SHA must be full commit hashes.", file=sys.stderr)
            sys.exit(1)
        # Integration merges (including GitHub's Update branch action) have
        # generated subjects. Validate the ordinary commits on every parent
        # branch, but do not require a Conventional Commit merge subject.
        commits = subprocess.check_output(
            ["git", "log", "--no-merges", "--format=%H", f"{base}..{head}"]
        ).decode().splitlines()
        for commit in commits:
            subject = subprocess.check_output(
                ["git", "show", "-s", "--format=%s", commit]
            ).decode().rstrip("\n")
            if not HEADER.fullmatch(subject):
                print(f"Commit {commit[:12]} needs a Conventional Commit subject: {subject}", file=sys.stderr)
                valid = False
    sys.exit(0 if valid else 1)
