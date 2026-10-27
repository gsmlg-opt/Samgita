#!/usr/bin/env python3
"""Run the reviewed ordinary functional selection, never the full test matrix.

Use --list to inspect exact commands. Source changes require renewed review and
an explicit fingerprint update before execution. No hosted workflow is started.
The complete compatibility, security and release gates remain separate.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import signal
import subprocess
import time

from fetch_pin import BINARY_SHA256, CACHE, ROOT

REVIEWED_SOURCE_SHA256 = "d8327ededacdfa42acc35d7a0116768a85ea7d8d74981a5988985e096f81f6cc"
DRIVER_TESTS = """
native_mcp_request_metadata_test.exs
native_search_input_wait_test.exs
native_plugin_search_scope_test.exs
native_local_plugin_filter_values_test.exs
native_thread_service_name_test.exs
native_creation_snapshot_notification_test.exs
native_resume_collaboration_result_test.exs
native_turn_runtime_roots_test.exs
native_hook_config_error_test.exs
native_plugin_search_logo_test.exs
native_search_creator_roots_test.exs
native_plugin_search_sources_test.exs
native_multi_agent_mode_values_test.exs
native_import_record_history_test.exs
native_mcp_startup_notice_test.exs
native_command_output_stream_values_test.exs
native_process_notification_envelope_test.exs
native_session_import_success_test.exs
native_fuzzy_notification_envelope_test.exs
native_goal_queue_notification_envelope_test.exs
native_reasoning_checklist_envelope_test.exs
native_fs_notification_envelope_test.exs
native_file_change_envelope_test.exs
native_collaboration_lifecycle_values_test.exs
native_collaboration_interrupted_test.exs
native_unclassified_turn_error_test.exs
native_interrupt_hook_test.exs
native_fork_git_notification_test.exs
native_realtime_start_stop_test.exs
native_shell_delta_identity_test.exs
native_failed_dynamic_tool_notification_test.exs
native_thread_revert_profile.exs
native_attachment_envelope_test.exs
native_environment_observation_test.exs
native_initialize_request_ids_test.exs
native_fs_path_values_test.exs
native_hook_plugin_metadata_test.exs
native_collaboration_catalogue_test.exs
native_mcp_status_detail_test.exs
native_local_config_migration_test.exs
native_local_plugin_migration_test.exs
native_local_memory_migration_test.exs
native_config_override_metadata_test.exs
native_turn_plugin_list_test.exs
""".split()
WS_TESTS = ["test/integration_test.exs:" + str(line) for line in (384, 442, 498)]
DRIVER_CASES = 73
SOURCE_SUFFIXES = {".ex", ".exs", ".py", ".json", ".lock", ".toml", ".ts", ".js", ".css"}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_snapshot():
    # Include the test helpers, dependency fixtures, schemas, configs and locks.
    # Merely hashing prohibited test files does not execute their checks.
    directories = [ROOT / "config", ROOT / "scripts/codex"]
    paths = {ROOT / "mix.exs", ROOT / "mix.lock", ROOT / ".formatter.exs",
             ROOT / "docs/codex-app-server/compatibility-manifest.json"}
    for app in sorted((ROOT / "apps").iterdir()):
        if app.is_dir():
            directories.extend(app / name for name in ("lib", "test", "config", "priv", "examples"))
            paths.update(p for p in app.glob("*") if p.is_file() and p.suffix in SOURCE_SUFFIXES)
    for directory in directories:
        if directory.is_dir():
            paths.update(p for p in directory.rglob("*")
                         if p.is_file() and p.suffix in SOURCE_SUFFIXES
                         and not {"_build", "deps", "node_modules", "__pycache__"}.intersection(p.parts))
    snapshot = {}
    for path in sorted(paths):
        content = path.read_bytes()
        if path == Path(__file__).resolve():
            content, count = re.subn(rb'(?m)^REVIEWED_SOURCE_SHA256 = "[^"]+"$',
                                    b'REVIEWED_SOURCE_SHA256 = "<reviewed>"', content)
            if count != 1:
                raise SystemExit("Expected exactly one runner fingerprint declaration")
        snapshot[str(path.relative_to(ROOT))] = hashlib.sha256(content).hexdigest()
    return snapshot


def fingerprint(snapshot):
    return hashlib.sha256(json.dumps(snapshot, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def commands():
    driver = ROOT / "apps/samgita_codex_driver"
    websocket = ROOT / "apps/samgita_protocol_websocket"
    files = ["test/" + name for name in DRIVER_TESTS]
    steps = []
    for seed in (455834, 501432, 987654):
        steps.append(("websocket-" + str(seed), websocket,
                      ["mix", "test", *WS_TESTS, "--seed", str(seed), "--max-cases", "8"], 120))
    steps.extend([
        ("driver-format", driver, ["mix", "format", "--check-formatted", *files], 120),
        ("driver-compile", driver, ["mix", "compile", "--warnings-as-errors"], 320),
    ])
    for seed in (501432, 987654):
        steps.append(("ordinary-" + str(seed), driver,
                      ["mix", "test", *files, "--warnings-as-errors", "--seed", str(seed)], 320))
    steps.extend([
        ("independent-consumer", ROOT, ["python3", "-B", "scripts/codex/verify_consumer.py"], 600),
        ("inventory-consistency", ROOT, ["python3", "-B", "scripts/codex/inventory.py", "--check"], 120),
        ("umbrella-compile", ROOT, ["mix", "compile", "--warnings-as-errors"], 320),
        ("root-format", ROOT, ["mix", "format", "--check-formatted"], 120),
        ("strict-credo", ROOT, ["mix", "credo", "--strict"], 320),
        ("dialyzer", ROOT, ["mix", "dialyzer", "--force-check"], 1200),
        ("assets-build", ROOT, ["mix", "assets.build"], 320),
    ])
    return steps


def check_test_count(name, log):
    text = log.read_text()
    if name.startswith("websocket-"):
        expected = r"^16 tests, 0 failures, 13 excluded$"
    elif name.startswith("ordinary-"):
        expected = rf"^{DRIVER_CASES} tests, 0 failures$"
    elif name == "independent-consumer":
        expected = r"^1 test, 0 failures$"
    else:
        return None
    if not re.search(expected, text, re.M):
        return "Expected reviewed test count/result absent; inspect original log"
    return None


def run_step(command, cwd, env, stream, timeout):
    # Retain the waitable leader until the last group signal, so a recycled
    # PID/PGID can never receive cleanup signals. Detached native descendants
    # retain their existing driver owner-death cleanup; do not replace it here.
    child = subprocess.Popen(command, cwd=cwd, env=env, stdout=stream,
                             stderr=subprocess.STDOUT, start_new_session=True)
    try:
        deadline = time.monotonic() + timeout
        while os.waitid(os.P_PID, child.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT) is None:
            if time.monotonic() >= deadline:
                raise subprocess.TimeoutExpired(command, timeout)
            time.sleep(0.05)
    except BaseException:
        try:
            os.killpg(child.pid, signal.SIGTERM)
            # Give the existing stdio owners time to reap their detached groups.
            time.sleep(5)
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        finally:
            child.wait(timeout=5)
        raise
    return child.wait()


def interrupt(_signal, _frame):
    raise InterruptedError("Ordinary checks interrupted; no further steps will run")


def execute(steps, output, before):
    if os.name != "posix" or not all(hasattr(os, name) for name in ("waitid", "WNOWAIT")):
        raise SystemExit("BLOCKED_ENV: owned POSIX process-group lifecycle required")
    env = os.environ.copy()
    for key in ("MIX_BUILD_PATH", "MIX_DEPS_PATH", "MIX_LOCKFILE", "MIX_EXS", "MIX_CONFIG_PATH",
                "MIX_TEST_PARTITION", "ERL_LIBS", "CODEX_MODEL_FIXTURE_SCRIPT"):
        env.pop(key, None)
    binary = CACHE / "codex-x86_64-unknown-linux-musl"
    if not binary.is_file() or digest(binary) != BINARY_SHA256:
        raise SystemExit("BLOCKED_ENV: immutable Codex executable required; no checks executed")
    env.update(MIX_ENV="test", ERL_FLAGS="+S 2:2", CODEX_BINARY=str(binary), PYTHONDONTWRITEBYTECODE="1")
    output.mkdir(parents=True, exist_ok=False)
    results = []
    handlers = {sig: signal.signal(sig, interrupt) for sig in (signal.SIGTERM, signal.SIGHUP)}
    try:
        for name, cwd, command, timeout in steps:
            if source_snapshot() != before:
                raise SystemExit("Source changed during checks; results are incomplete")
            log = output / (name + ".log")
            started = time.monotonic()
            with log.open("xb") as stream:
                try:
                    code = run_step(command, cwd, env, stream, timeout)
                except subprocess.TimeoutExpired:
                    code = 124
            count_error = check_test_count(name, log) if code == 0 else None
            results.append(dict(name=name, cwd=str(cwd), command=command, exit_code=code,
                                count_error=count_error, seconds=round(time.monotonic() - started, 3),
                                log_sha256=digest(log)))
            (output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
            print(f"{name}: exit {code}; {log}", flush=True)
            if code or count_error:
                raise SystemExit(f"Stopped at {name}; no following checks executed")
    finally:
        for sig, handler in handlers.items():
            signal.signal(sig, handler)
        after = source_snapshot()
        (output / "source.json").write_text(json.dumps(dict(before=before, after=after,
            identical=before == after, fingerprint=fingerprint(before),
            command_plan_sha256=hashlib.sha256(json.dumps([
                [name, str(cwd.relative_to(ROOT)), command, timeout]
                for name, cwd, command, timeout in steps], separators=(",", ":")).encode()).hexdigest(),
            completed=len(results), planned=len(steps)), indent=2, sort_keys=True) + "\n")
    if after != before:
        raise SystemExit("Source changed during checks; final-source qualification is incomplete")
    print("Reviewed ordinary selection passed. Full compatibility and release gates remain incomplete.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--list", action="store_true", help="Print the exact selection without execution")
    mode.add_argument("--fingerprint", action="store_true", help="Print current source fingerprint only")
    mode.add_argument("--output", type=Path, help="Run selection; create this new evidence directory")
    args = parser.parse_args()
    steps = commands()
    if args.list:
        for name, cwd, command, _ in steps:
            print(f"{name}: ({cwd.relative_to(ROOT)}) {shlex.join(command)}")
        return
    before = source_snapshot()
    if args.fingerprint:
        print(f"{fingerprint(before)} ({len(before)} source files)")
        return
    if fingerprint(before) != REVIEWED_SOURCE_SHA256:
        raise SystemExit("Source differs from reviewed selection; review before updating fingerprint. No checks executed.")
    execute(steps, args.output.resolve(), before)


if __name__ == "__main__":
    main()
