#!/usr/bin/env python3
"""Preserve build-input mtimes across fresh checkouts, only for identical content."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


def inputs(root):
    tracked = subprocess.check_output(
        ["git", "ls-files", "-z", "--", "Package.swift", "Package.resolved",
         "Sources", "Tests", "scripts", "support"], cwd=root,
    ).decode().split("\0")
    for name in tracked:
        if not name:
            continue
        path = root / name
        if path.is_file() and not path.is_symlink():
            yield name, path


def synchronize(root, mode):
    manifest = root / ".build" / "glance-input-timestamps.json"
    if mode == "save":
        records = {
            name: {"sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                   "mtime_ns": path.stat().st_mtime_ns}
            for name, path in inputs(root)
        }
        manifest.parent.mkdir(parents=True, exist_ok=True)
        manifest.write_text(json.dumps(records))
        return len(records)
    if mode != "restore":
        raise ValueError("Mode must be restore or save")
    if not manifest.exists():
        return 0
    try:
        records = json.loads(manifest.read_text())
    except (ValueError, OSError):
        return 0
    if not isinstance(records, dict):
        return 0
    restored = 0
    # Iterate CURRENT tracked inputs, never paths supplied by the cache manifest.
    for name, path in inputs(root):
        record = records.get(name)
        if not isinstance(record, dict):
            continue
        timestamp = record.get("mtime_ns")
        if type(timestamp) is not int or not 0 < timestamp < 2**63:
            continue
        if hashlib.sha256(path.read_bytes()).hexdigest() != record.get("sha256"):
            continue
        os.utime(path, ns=(path.stat().st_atime_ns, timestamp))
        restored += 1
    return restored


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) == 2 else ""
    if mode not in {"restore", "save"}:
        sys.exit("Usage: build-cache.py <restore|save>")
    count = synchronize(Path(__file__).resolve().parent.parent, mode)
    print(f"Build input timestamps: {mode}, {count} files.")
