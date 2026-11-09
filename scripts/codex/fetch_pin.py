#!/usr/bin/env python3
"""Fetch the official Codex release named by the current schema snapshot into tmp/.

No global installation, user configuration, credentials, or service is touched.
Downloads must match the recorded SHA-256 before extraction or execution.
"""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
SNAPSHOT = ROOT / "apps/samgita_protocol_codex/priv/upstream/current"
# The current schema snapshot names the release; refresh_snapshot.py replaces it.
PIN = json.loads((SNAPSHOT / "source.json").read_text())
VERSION = PIN["version"]
COMMIT = PIN["commit"]
TAG_OBJECT = PIN["tag_object"]
ASSET = PIN["release_asset"]
ARCHIVE_SHA256 = PIN["release_asset_sha256"]
BINARY_SHA256 = PIN["binary_sha256"]
BWRAP_ASSET = "bwrap-x86_64-unknown-linux-musl.tar.gz"
BWRAP_MEMBER = "bwrap-x86_64-unknown-linux-musl"
BWRAP_ARCHIVE_SHA256 = PIN["bwrap_asset_sha256"]
BWRAP_SHA256 = PIN["bwrap_sha256"]
SOURCE_SHA256 = PIN["source_archive_sha256"]
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


def install_bwrap(archive_path, destination):
    """Install unchanged release bytes, never an archive-selected path/link."""
    if destination.is_symlink() or destination.parent.is_symlink():
        raise SystemExit("Pinned bubblewrap destination must not use symlinks")
    if not destination.exists() or digest(destination) != BWRAP_SHA256:
        with tarfile.open(archive_path) as archive:
            members = archive.getmembers()
            if len(members) != 1 or members[0].name != BWRAP_MEMBER or not members[0].isfile():
                raise SystemExit("Unexpected pinned bubblewrap archive members")
            contents = archive.extractfile(members[0]).read()
        if hashlib.sha256(contents).hexdigest() != BWRAP_SHA256:
            raise SystemExit("Pinned bubblewrap payload SHA-256 mismatch")
        destination.parent.mkdir(exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=destination.parent, prefix="bwrap-", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(contents)
        try:
            temporary.chmod(0o755)
            temporary.replace(destination)
        finally:
            temporary.unlink(missing_ok=True)
    if digest(destination) != BWRAP_SHA256 or destination.stat().st_mode & 0o111 == 0:
        raise SystemExit("Installed pinned bubblewrap verification failed")


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
        # The bare executable archive omits resources. The unchanged matching
        # release sidecar is also checked by Codex's embedded expected digest.
        bwrap_archive = CACHE / BWRAP_ASSET
        fetch(f"https://github.com/openai/codex/releases/download/rust-v{VERSION}/{BWRAP_ASSET}",
              bwrap_archive, BWRAP_ARCHIVE_SHA256)
        bwrap = CACHE / "codex-resources/bwrap"
        install_bwrap(bwrap_archive, bwrap)
        version = subprocess.check_output([str(binary), "--version"], text=True).strip()
        if version != f"codex-cli {VERSION}":
            raise SystemExit(f"Unexpected executable version: {version}")
        result.update(binary=str(binary), binary_sha256=BINARY_SHA256,
                      bundled_bwrap=str(bwrap), bundled_bwrap_sha256=BWRAP_SHA256)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
