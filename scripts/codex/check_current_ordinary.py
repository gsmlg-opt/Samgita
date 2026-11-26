#!/usr/bin/env python3
"""Run the reviewed current-client ordinary workflows in disposable package copies.

The historical check_ordinary.py selection remains independent. This profile
covers Projects, streamed text, stored history, explicit reconnect, schema drift,
query uncertainty, owned-process cleanup and three loopback replay scenarios.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import tempfile
import time

import check_ordinary

ROOT = check_ordinary.ROOT
REVIEWED_SOURCE_SHA256 = "c65ca6a53e6ceeec19c9154bc8a1b405144b56ba2c69d5970e740cd72d96244f"
PACKAGES = ("samgita_protocol", "samgita_protocol_codex", "samgita_codex_driver",
            "samgita_protocol_websocket")
INPUT_DIRECTORIES = (*[Path("apps") / package for package in PACKAGES], Path("scripts/codex"))
MANIFEST = Path("docs/codex-app-server/compatibility-manifest.json")
IGNORE_INPUTS = shutil.ignore_patterns("_build", "deps", "__pycache__", ".devenv", ".git",
                                      "node_modules", ".pytest_cache", "*.pyc", "*.pyo")
WS_CASES = {
    384: "overflow leaves an unforwarded event recoverable, then replay and live checkpoints advance",
    443: "a queued owner control consumes capacity and the unforwarded live event remains replayable",
    503: "an oversized replay batch preserves checkpoints and later retention loss reports a gap",
}


def source_snapshot():
    # Hash exactly the inputs copied into the disposable package workspace,
    # including uncommitted files and source evidence without a code suffix.
    paths = [ROOT / MANIFEST]
    for relative in INPUT_DIRECTORIES:
        for directory, subdirectories, filenames in os.walk(ROOT / relative, followlinks=True):
            ignored = IGNORE_INPUTS(directory, subdirectories + filenames)
            subdirectories[:] = sorted(name for name in subdirectories if name not in ignored)
            paths.extend(Path(directory) / name for name in filenames if name not in ignored)
    snapshot = {}
    for path in sorted(paths):
        contents = path.read_bytes()
        if path == Path(__file__).resolve():
            contents, count = re.subn(rb'(?m)^REVIEWED_SOURCE_SHA256 = "[^"]+"$',
                                     b'REVIEWED_SOURCE_SHA256 = "<reviewed>"', contents)
            if count != 1:
                raise SystemExit("Expected one current-profile review fingerprint")
        snapshot[str(path.relative_to(ROOT))] = hashlib.sha256(contents).hexdigest()
    return snapshot


def commands(root):
    protocol = root / "apps/samgita_protocol_codex"
    driver = root / "apps/samgita_codex_driver"
    websocket = root / "apps/samgita_protocol_websocket"
    steps = [
        ("refresh-staging", root, ["python3", "-B", "scripts/codex/test_refresh_snapshot.py"], 30, None),
        ("driver-dependencies", driver, ["mix", "deps.get"], 180, None),
        ("websocket-dependencies", websocket, ["mix", "deps.get"], 180, None),
        ("project-schema", protocol,
         ["mix", "test", "test/project_output_compatibility_test.exs", "--warnings-as-errors"], 120, 3),
        ("driver-compatible", driver,
         ["mix", "test", "test/compatible_schema_test.exs", "--warnings-as-errors", "--seed", "501432"], 180, 25),
        ("query-uncertainty", driver,
         ["mix", "test", "test/query_uncertainty_test.exs", "--warnings-as-errors", "--seed", "501432"], 60, 41),
        ("stdio-cleanup", driver,
         ["mix", "test", "test/stdio_owner_lifecycle_test.exs", "--warnings-as-errors", "--seed", "501432"], 30, 4),
    ]
    for seed in (501432, 987654):
        steps.append((f"current-client-{seed}", driver,
                      ["mix", "test", "test/current_ordinary_workflows_test.exs",
                       "--warnings-as-errors", "--seed", str(seed)], 120, 2))
    for seed in (455834, 501432, 987654):
        steps.append((f"loopback-replay-{seed}", websocket,
                      ["mix", "test", *[f"test/integration_test.exs:{line}" for line in WS_CASES],
                       "--warnings-as-errors", "--seed", str(seed), "--max-cases", "8"], 120, 3))
    return steps


def verify_selection():
    lines = (ROOT / "apps/samgita_protocol_websocket/test/integration_test.exs").read_text().splitlines()
    for number, name in WS_CASES.items():
        if f'test "{name}"' not in lines[number - 1]:
            raise SystemExit(f"Review required: loopback case at line {number} changed")


def verify_result(name, log, count):
    contents = log.read_text()
    if name == "refresh-staging":
        expected = r"Ran 2 tests in [0-9.]+s\n\nOK$"
    elif name.startswith("loopback-replay-"):
        expected = r"^16 tests, 0 failures, 13 excluded$"
    elif count is not None:
        expected = rf"^{count} tests, 0 failures$"
    else:
        return
    if not re.search(expected, contents, re.M):
        raise RuntimeError(f"Reviewed count/result absent for {name}; inspect {log}")


def execute(output, binary, before):
    output.mkdir(parents=True, exist_ok=False)
    selected = {"path": str(binary), "sha256": check_ordinary.digest(binary),
                "version": subprocess.check_output([str(binary), "--version"], text=True,
                                                   timeout=10).strip()}
    env = os.environ.copy()
    for key in ("MIX_BUILD_PATH", "MIX_DEPS_PATH", "MIX_LOCKFILE", "MIX_EXS", "MIX_CONFIG_PATH",
                "MIX_TEST_PARTITION", "ERL_LIBS", "CODEX_MODEL_FIXTURE_SCRIPT"):
        env.pop(key, None)
    env.update(MIX_ENV="test", ERL_FLAGS="+S 2:2", CODEX_BINARY=str(binary),
               SAMGITA_CODEX_SCHEMA_MODE="compatible", PYTHONDONTWRITEBYTECODE="1")
    runtime = subprocess.check_output(["elixir", "--version"], env=env, text=True,
                                      timeout=10).strip()
    results = []
    handlers = {sig: signal.signal(sig, check_ordinary.interrupt)
                for sig in (signal.SIGTERM, signal.SIGHUP)}
    try:
        with tempfile.TemporaryDirectory(prefix="samgita-current-ordinary-") as directory:
            workspace = Path(directory)
            for relative in INPUT_DIRECTORIES:
                shutil.copytree(ROOT / relative, workspace / relative, ignore=IGNORE_INPUTS)
            # The staging regression needs the inventory as an input fixture.
            (workspace / MANIFEST).parent.mkdir(parents=True)
            shutil.copyfile(ROOT / MANIFEST, workspace / MANIFEST)
            locks = {workspace / "apps" / package / "mix.lock":
                     check_ordinary.digest(workspace / "apps" / package / "mix.lock")
                     for package in PACKAGES if (workspace / "apps" / package / "mix.lock").exists()}
            for name, cwd, command, timeout, count in commands(workspace):
                if source_snapshot() != before or check_ordinary.digest(binary) != selected["sha256"]:
                    raise RuntimeError("Reviewed source or selected client changed during checks")
                log = output / f"{name}.log"
                started = time.monotonic()
                with log.open("xb") as stream:
                    code = check_ordinary.run_step(command, cwd, env, stream, timeout)
                results.append({"name": name, "command": command,
                                "cwd": str(cwd.relative_to(workspace)), "expected_cases": count,
                                "exit_code": code, "seconds": round(time.monotonic() - started, 3),
                                "log_sha256": check_ordinary.digest(log)})
                (output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
                print(f"{name}: exit {code}; {log}", flush=True)
                if code:
                    raise RuntimeError(f"Stopped at {name}; no later checks executed")
                verify_result(name, log, count)
                if any(check_ordinary.digest(path) != expected for path, expected in locks.items()):
                    raise RuntimeError("Dependency resolution changed a copied lockfile; review required")
    finally:
        for sig, handler in handlers.items():
            signal.signal(sig, handler)
        after = source_snapshot()
        identical = before == after and selected["sha256"] == check_ordinary.digest(binary)
        (output / "source.json").write_text(json.dumps({"before": before, "after": after,
            "identical": identical, "fingerprint": check_ordinary.fingerprint(before),
            "client": selected, "elixir_otp": runtime,
            "schema_snapshot": json.loads((ROOT /
                "apps/samgita_protocol_codex/priv/upstream/current/source.json").read_text())["version"],
            "completed": len(results), "planned": len(commands(ROOT)),
            "scope": "current-client ordinary workflows in disposable reusable-package copies"},
            indent=2, sort_keys=True) + "\n")
    if not identical:
        raise SystemExit("Source or selected client changed; qualification is incomplete")
    print("Current-client ordinary selection passed. See source.json for the selected client and scope.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--list", action="store_true")
    mode.add_argument("--fingerprint", action="store_true")
    mode.add_argument("--output", type=Path)
    parser.add_argument("--binary", type=Path, help="existing Codex executable for owned synthetic workflows")
    args = parser.parse_args()
    verify_selection()
    if args.list:
        for name, cwd, command, timeout, count in commands(ROOT):
            print(f"{name}: ({cwd.relative_to(ROOT)}) {shlex.join(command)}; "
                  f"timeout={timeout}s expected_cases={count}")
        return
    before = source_snapshot()
    if args.fingerprint:
        print(f"{check_ordinary.fingerprint(before)} ({len(before)} source files)")
        return
    if check_ordinary.fingerprint(before) != REVIEWED_SOURCE_SHA256:
        raise SystemExit("Source differs from the current-profile review; no checks executed")
    if args.binary is None or not args.binary.is_file():
        raise SystemExit("Supply --binary with the selected existing Codex executable")
    execute(args.output.resolve(), args.binary.resolve(), before)


if __name__ == "__main__":
    main()
