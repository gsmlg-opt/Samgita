#!/usr/bin/env python3
"""Fetch the separately pinned official standalone app-server, without starting it.

The combined Codex executable and its pin remain unchanged. This additional
Linux musl profile owns a separate ignored cache and requires no platform app.
"""

import argparse
import hashlib
import json
from pathlib import Path
import tarfile
import tempfile

from fetch_pin import CACHE, COMMIT, TAG_OBJECT, VERSION, digest, fetch

ASSET = "codex-app-server-x86_64-unknown-linux-musl.tar.gz"
MEMBER = "codex-app-server-x86_64-unknown-linux-musl"
ARCHIVE_SHA256 = "bd587a5419f9b6fa488e4950b065c9127f7db0989388210a3785294b460cdf09"
BINARY_SHA256 = "528c11baca43b3be05112c0be1fb1c4a3d5c53f1b6d628f5bf42ebd7803e7a9e"
ARCHIVE_BYTES = 87_120_300
BINARY_BYTES = 228_736_728
STANDALONE_CACHE = CACHE / "standalone"
BINARY = STANDALONE_CACHE / MEMBER


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check cached bytes only; never fetch or install")
    args = parser.parse_args()
    archive_path = STANDALONE_CACHE / ASSET
    for path, expected in ((archive_path, ARCHIVE_SHA256), (BINARY, BINARY_SHA256)):
        if path.exists() and digest(path) != expected:
            raise SystemExit(f"Unexpected existing standalone reference: {path}; left unchanged")
    if args.check:
        if not archive_path.is_file() or not BINARY.is_file():
            raise SystemExit("BLOCKED_ENV: separately pinned standalone reference is not cached")
    else:
        STANDALONE_CACHE.mkdir(parents=True, exist_ok=True)
        fetch(f"https://github.com/openai/codex/releases/download/rust-v{VERSION}/{ASSET}",
              archive_path, ARCHIVE_SHA256)
        if not BINARY.exists():
            with tarfile.open(archive_path) as archive:
                members = archive.getmembers()
                if len(members) != 1 or members[0].name != MEMBER or not members[0].isfile():
                    raise SystemExit("Unexpected standalone archive members; reference not installed")
                payload = archive.extractfile(members[0]).read()
            if len(payload) != BINARY_BYTES or hashlib.sha256(payload).hexdigest() != BINARY_SHA256:
                raise SystemExit("Standalone executable payload does not match the immutable pin")
            with tempfile.NamedTemporaryFile(dir=STANDALONE_CACHE, prefix="app-server-", delete=False) as stream:
                temporary = Path(stream.name)
                stream.write(payload)
            try:
                temporary.chmod(0o755)
                temporary.replace(BINARY)
            finally:
                temporary.unlink(missing_ok=True)
    if archive_path.stat().st_size != ARCHIVE_BYTES or BINARY.stat().st_size != BINARY_BYTES:
        raise SystemExit("Standalone reference size differs from the immutable pin")
    print(json.dumps({"version": VERSION, "source_commit": COMMIT, "tag_object": TAG_OBJECT,
        "profile": "linux-x86_64-musl/standalone-stdio", "archive": str(archive_path),
        "archive_sha256": ARCHIVE_SHA256, "binary": str(BINARY), "binary_sha256": BINARY_SHA256,
        "executed": False}, indent=2))


if __name__ == "__main__":
    main()
