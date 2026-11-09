#!/usr/bin/env python3
"""Replace the bundled Codex schema snapshot with the latest official release.

Codex is not pinned (design §11 version policy). This script resolves the
latest non-prerelease `rust-v*` release (or `--version`), downloads the source
archive at the tag's commit and the release assets the conformance workflow
uses, verifies every asset against the SHA-256 digest GitHub publishes for it,
writes the new pin to `priv/upstream/current/source.json`, and regenerates the
snapshot with `inventory.py --generate` in a fresh process.

The previous snapshot is replaced; it survives only in Git history. Source files
whose derived contracts are reviewed by hash make the generators stop with the
changed path: review the upstream diff, adjust the derivation if needed, update
the reviewed hash and rerun. Downloads go to the ignored tmp/codex/<version>
cache. Nothing is installed globally and no Codex process is left running.
"""

import argparse
import datetime
import hashlib
import json
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
SNAPSHOT = ROOT / "apps/samgita_protocol_codex/priv/upstream/current"
API = "https://api.github.com/repos/openai/codex"
REPOSITORY = "https://github.com/openai/codex"
LINUX = "x86_64-unknown-linux-musl"
HOSTS = {("Darwin", "arm64"): "aarch64-apple-darwin", ("Darwin", "x86_64"): "x86_64-apple-darwin",
         ("Linux", "x86_64"): LINUX, ("Linux", "aarch64"): "aarch64-unknown-linux-musl"}
VERSION = re.compile(r"\A[0-9]+\.[0-9]+\.[0-9]+\Z")
# Release-independent dependency references the generators verify by hash; they
# are carried into the new snapshot instead of being regenerated.
CARRIED = ("source/serde-1.0.228/private-de.rs", "source/serde-1.0.228/LICENSE-MIT")


def encode(value):
    return json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + "\n"


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def api(path):
    request = urllib.request.Request(API + path, headers={
        "User-Agent": "samgita-codex-refresh/1", "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def download(url, path, expected=None):
    if path.exists() and (expected is None or digest(path) == expected):
        return digest(path)
    temporary = path.with_suffix(path.suffix + ".partial")
    request = urllib.request.Request(url, headers={"User-Agent": "samgita-codex-refresh/1"})
    with urllib.request.urlopen(request, timeout=300) as response, temporary.open("wb") as stream:
        while block := response.read(1024 * 1024):
            stream.write(block)
    actual = digest(temporary)
    if expected is not None and actual != expected:
        temporary.unlink()
        raise SystemExit(f"SHA-256 mismatch for {url}; nothing was installed")
    temporary.replace(path)
    return actual


def extract_single(archive, member, destination):
    """Extract exactly one regular file by name, never an archive-chosen path."""
    with tarfile.open(archive) as stream:
        members = stream.getmembers()
        if len(members) != 1 or members[0].name != member or not members[0].isfile():
            raise SystemExit(f"Unexpected members in {archive.name}")
        contents = stream.extractfile(members[0]).read()
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(contents)
    destination.chmod(0o755)
    return destination


def resolve(version):
    release = api("/releases/latest") if version is None else api(f"/releases/tags/rust-v{version}")
    tag = release["tag_name"]
    if release.get("prerelease") or release.get("draft") or not tag.startswith("rust-v") \
            or not VERSION.match(tag.removeprefix("rust-v")):
        raise SystemExit(f"Not an official stable Codex release: {tag}")
    ref = api(f"/git/ref/tags/{tag}")["object"]
    tag_object = ref["sha"] if ref["type"] == "tag" else None
    commit = api(f"/git/tags/{ref['sha']}")["object"]["sha"] if ref["type"] == "tag" else ref["sha"]
    digests = {}
    for asset in release["assets"]:
        if asset.get("digest", "").startswith("sha256:"):
            digests[asset["name"]] = (asset["digest"].removeprefix("sha256:"), asset["size"])
    return tag.removeprefix("rust-v"), tag, tag_object, commit, digests


def asset(digests, name):
    if name not in digests:
        raise SystemExit(f"Release has no published SHA-256 digest for {name}")
    return digests[name]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", help="an exact stable release instead of the latest")
    parser.add_argument("--dry-run", action="store_true", help="resolve and print the release only")
    args = parser.parse_args()
    version, tag, tag_object, commit, digests = resolve(args.version)
    current = json.loads((SNAPSHOT / "source.json").read_text())
    print(f"current snapshot {current['version']}; release {version} ({commit})")
    if args.dry_run:
        return
    host = HOSTS.get((platform.system(), platform.machine()))
    if host is None:
        raise SystemExit(f"No Codex release asset for this host: {platform.system()} {platform.machine()}")

    cache = ROOT / "tmp/codex" / version
    cache.mkdir(parents=True, exist_ok=True)
    source_archive = cache / "source.tar.gz"
    source_sha = download(f"https://codeload.github.com/openai/codex/tar.gz/{commit}", source_archive)
    source = cache / f"codex-{commit}"
    if not source.exists():
        with tarfile.open(source_archive) as stream:
            stream.extractall(cache, filter="data")

    def binary(name, member, target):
        sha, size = asset(digests, name)
        download(f"{REPOSITORY}/releases/download/{tag}/{name}", cache / name, sha)
        path = extract_single(cache / name, member, target)
        return sha, size, path

    codex = f"codex-{LINUX}.tar.gz"
    codex_sha, _, codex_binary = binary(codex, f"codex-{LINUX}", cache / f"codex-{LINUX}")
    bwrap_sha, _, bwrap = binary(f"bwrap-{LINUX}.tar.gz", f"bwrap-{LINUX}", cache / "codex-resources/bwrap")
    standalone_sha, standalone_size, standalone = binary(
        f"codex-app-server-{LINUX}.tar.gz", f"codex-app-server-{LINUX}",
        cache / f"standalone/codex-app-server-{LINUX}")
    generator = codex_binary if host == LINUX else binary(
        f"codex-{host}.tar.gz", f"codex-{host}", cache / f"host/codex-{host}")[2]
    output = subprocess.check_output([str(generator), "--version"], text=True).strip()
    if output != f"codex-cli {version}":
        raise SystemExit(f"Unexpected executable version: {output}")

    pin = {
        "repository": REPOSITORY, "version": version, "tag": tag, "tag_object": tag_object,
        "commit": commit, "retrieved_on": datetime.date.today().isoformat(),
        "source_archive_url": f"https://codeload.github.com/openai/codex/tar.gz/{commit}",
        "source_archive_sha256": source_sha,
        "artifact_digest_authority": f"{API}/releases/tags/{tag}",
        "build_platform": LINUX, "release_asset": codex,
        "release_asset_url": f"{REPOSITORY}/releases/download/{tag}/{codex}",
        "release_asset_sha256": codex_sha, "binary_sha256": digest(codex_binary),
        "binary_version_output": f"codex-cli {version}",
        "bwrap_asset_sha256": bwrap_sha, "bwrap_sha256": digest(bwrap),
        "standalone_asset_sha256": standalone_sha, "standalone_asset_bytes": standalone_size,
        "standalone_binary_sha256": digest(standalone),
        "standalone_binary_bytes": standalone.stat().st_size,
        "generation_platform": host, "generation_binary_sha256": digest(generator),
        "schema_generation_commands": [
            "codex app-server generate-json-schema --out stable",
            "codex app-server generate-json-schema --experimental --out experimental",
            "codex app-server generate-ts --experimental --out typescript",
            "python3 scripts/codex/generate_supplement.py",
            "python3 scripts/codex/generate_input_semantics.py"],
        "reproduce": ["python3 scripts/codex/refresh_snapshot.py",
                      "python3 scripts/codex/inventory.py --check"],
        "files_sha256": {},
    }
    # Replace the previous snapshot (kept in Git history) and regenerate it from
    # the new pin in a fresh interpreter, so every generator reads the new pin.
    carried = {name: (SNAPSHOT / name).read_bytes() for name in CARRIED}
    shutil.rmtree(SNAPSHOT)
    SNAPSHOT.mkdir(parents=True)
    for name, contents in carried.items():
        (SNAPSHOT / name).parent.mkdir(parents=True, exist_ok=True)
        (SNAPSHOT / name).write_bytes(contents)
    (SNAPSHOT / "source.json").write_text(encode(pin))
    subprocess.run([sys.executable, "-B", str(Path(__file__).with_name("inventory.py")),
                    "--generate", "--binary", str(generator)], check=True)
    subprocess.run([sys.executable, "-B", str(Path(__file__).with_name("generate_fixtures.py"))],
                   check=True)
    print(f"snapshot refreshed to {version}; run inventory.py --check and the package tests")


if __name__ == "__main__":
    main()
