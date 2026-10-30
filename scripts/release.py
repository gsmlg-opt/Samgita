#!/usr/bin/env python3
"""Synchronize release versions and stage standalone Hex sources without workspace paths."""

import argparse
import json
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
PACKAGES = (
    "samgita_protocol",
    "samgita_protocol_websocket",
    "samgita_protocol_codex",
    "samgita_codex_driver",
)
PACKAGE_FILES = {
    name: ("lib", "mix.exs", "README.md", "LICENSE", ".formatter.exs")
    + (() if name == "samgita_protocol_websocket" else ("priv",))
    + (("config",) if name in ("samgita_protocol_codex", "samgita_codex_driver") else ())
    for name in PACKAGES
}
SIBLINGS = {
    "samgita_protocol_websocket": "samgita_protocol",
    "samgita_protocol_codex": "samgita_protocol",
    "samgita_codex_driver": "samgita_protocol_codex",
}
VERSION = re.compile(r'(?m)^(\s*version: ")([^"]+)(",)$')
SEMVER = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)")


def manifests(root=ROOT):
    return (Path("mix.exs"), *sorted(path.relative_to(root) for path in root.glob("apps/*/mix.exs")))


def version_parts(version):
    if not SEMVER.fullmatch(version):
        raise ValueError("version must be M.N.P (without a v prefix)")
    return tuple(map(int, version.split(".")))


def release_channel(version):
    return "prerelease" if version_parts(version)[0] == 0 else "stable"


def version_changes(root, version):
    """Validate the current coordinated release, then calculate every manifest edit."""
    requested = version_parts(version)
    sources = {path: (root / path).read_text() for path in manifests(root)}
    root_version = VERSION.search(sources[Path("mix.exs")])
    if root_version is None:
        raise ValueError("canonical version missing from mix.exs")
    canonical = root_version.group(2)
    if requested < version_parts(canonical):
        raise ValueError(f"version {version} precedes current version {canonical}")
    updated = {}
    for path, source in sources.items():
        versions = [match.group(2) for match in VERSION.finditer(source)]
        expected_count = 2 if path == Path("mix.exs") else 1
        if versions != [canonical] * expected_count:
            raise ValueError(f"unexpected version declarations in {path}: {versions}")
        updated[path] = VERSION.sub(lambda m: m.group(1) + version + m.group(3), source)
    for manifest in manifests(root)[1:]:
        path = manifest.with_name("package.json")
        if not (root / path).exists():
            continue
        metadata = json.loads((root / path).read_text())
        if "version" not in metadata:
            continue
        if metadata["version"] != canonical:
            raise ValueError(f"unexpected asset version in {path}: {metadata['version']}")
        metadata["version"] = version
        updated[path] = json.dumps(metadata, indent=2) + "\n"
    for name, dependency in SIBLINGS.items():
        path = Path("apps") / name / "mix.exs"
        old = f'{{:{dependency}, "~> {canonical}", path: "../{dependency}"}}'
        if updated[path].count(old) != 1:
            raise ValueError(f"expected one versioned sibling dependency in {path}")
        updated[path] = updated[path].replace(
            old, f'{{:{dependency}, "~> {version}", path: "../{dependency}"}}'
        )
    return updated


def prepare(root, version, output):
    """Stage allowlisted publishable files; retain local paths in the working checkout."""
    updated = version_changes(root, version)
    for name, files in PACKAGE_FILES.items():
        for item in files:
            if not (root / "apps" / name / item).exists():
                raise ValueError(f"missing package input: apps/{name}/{item}")
    # A fresh directory makes each attempt's artifacts explicit; never reuse an old tarball.
    output.mkdir(parents=True, exist_ok=False)
    for name, files in PACKAGE_FILES.items():
        target = output / name
        target.mkdir()
        for item in files:
            source = root / "apps" / name / item
            if source.is_dir():
                shutil.copytree(source, target / item, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
            else:
                shutil.copy2(source, target / item)
        staged_manifest = updated[Path("apps") / name / "mix.exs"]
        if name in SIBLINGS:
            dependency = SIBLINGS[name]
            staged_manifest = staged_manifest.replace(f', path: "../{dependency}"', "")
        (target / "mix.exs").write_text(staged_manifest)
    # Only after staging succeeds do we mutate the release checkout.
    for path, source in updated.items():
        (root / path).write_text(source)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--output", type=Path, help="fresh package source directory")
    mode.add_argument("--channel", action="store_true", help="print prerelease for 0.x, stable for >= 1.0")
    args = parser.parse_args()
    try:
        if args.channel:
            print(release_channel(args.version))
            return
        prepare(ROOT, args.version, args.output.resolve())
    except (OSError, ValueError) as error:
        parser.exit(1, f"Release preparation failed: {error}\n")
    print(f"Prepared {args.version}: {', '.join(PACKAGES)} in {args.output}")


if __name__ == "__main__":
    main()
