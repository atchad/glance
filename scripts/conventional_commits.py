#!/usr/bin/env python3
"""Parse Conventional Commit subjects and validate a PR title."""

import os
import re
import sys


HEADER_PATTERN = (
    r"^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)"
    r"(\([^()\r\n]+\))?(!)?: (\S[^\r\n]*)$"
)
HEADER = re.compile(HEADER_PATTERN)
# GitHub's commit-message restriction evaluates the full message, including its body.
MESSAGE_PATTERN = HEADER_PATTERN[:-1] + r"(\r?\n[\s\S]*)?$"


def description(subject):
    match = HEADER.fullmatch(subject)
    return match.group(4) if match else subject


def is_breaking(message):
    match = HEADER.fullmatch(message.splitlines()[0])
    return bool((match and match.group(3)) or re.search(r"(?m)^BREAKING[ -]CHANGE: \S", message))


if __name__ == "__main__":
    title = os.environ.get("PR_TITLE", "")
    if not HEADER.fullmatch(title):
        print(
            "PR titles must use <type>[optional scope][optional !]: <description>.\n"
            "Types: build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test.\n"
            "Example: fix(settings): anchor shortcut search",
            file=sys.stderr,
        )
        sys.exit(1)
    print("PR title follows Conventional Commits.")
