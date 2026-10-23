#!/usr/bin/env python3
"""Fetch the immutable official Codex reference into repository-ignored tmp/.

No global installation, user configuration, credentials, or service is touched.
Downloads must match the recorded SHA-256 before extraction or execution.
"""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
VERSION = "0.163.0"
COMMIT = "83086188ae0614bd882818ff1aa23f3194962012"
TAG_OBJECT = "129b8ec7ee6f4511557a4856279f529025c25af4"
ASSET = "codex-x86_64-unknown-linux-musl.tar.gz"
ARCHIVE_SHA256 = "beb339e8ecd9ba057a6bb2dc81ad8ca474812edfbf0fc5056ca818797648dde4"
BINARY_SHA256 = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
SOURCE_SHA256 = "e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567"
CACHE = ROOT / "tmp/codex" / VERSION


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def fetch(url, path, expected):
    if path.exists() and digest(path) == expected:
        return
    temporary = path.with_suffix(path.suffix + ".partial")
    request = urllib.request.Request(url, headers={"User-Agent": "samgita-codex-pin/1"})
    with urllib.request.urlopen(request, timeout=120) as response, temporary.open("wb") as stream:
        while block := response.read(1024 * 1024):
            stream.write(block)
    if digest(temporary) != expected:
        temporary.unlink()
        raise SystemExit(f"SHA-256 mismatch for {url}; reference was not installed")
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    CACHE.mkdir(parents=True, exist_ok=True)
    source_archive = CACHE / "source.tar.gz"
    fetch(f"https://codeload.github.com/openai/codex/tar.gz/{COMMIT}", source_archive, SOURCE_SHA256)
    source = CACHE / f"codex-{COMMIT}"
    if not source.exists():
        with tarfile.open(source_archive) as archive:
            archive.extractall(CACHE, filter="data")
    result = {"version": VERSION, "commit": COMMIT, "source": str(source)}
    if not args.source_only:
        binary_archive = CACHE / ASSET
        fetch(f"https://github.com/openai/codex/releases/download/rust-v{VERSION}/{ASSET}",
              binary_archive, ARCHIVE_SHA256)
        binary = CACHE / ASSET.removesuffix(".tar.gz")
        if not binary.exists() or digest(binary) != BINARY_SHA256:
            with tarfile.open(binary_archive) as archive:
                member = archive.getmember(binary.name)
                archive.extract(member, CACHE, filter="data")
        if digest(binary) != BINARY_SHA256:
            raise SystemExit("Extracted binary SHA-256 mismatch")
        version = subprocess.check_output([str(binary), "--version"], text=True).strip()
        if version != f"codex-cli {VERSION}":
            raise SystemExit(f"Unexpected executable version: {version}")
        result.update(binary=str(binary), binary_sha256=BINARY_SHA256)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
