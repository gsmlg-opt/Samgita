#!/usr/bin/env python3
"""Probe field-gate behavior on the pinned binary without credentials or model calls.

Only ephemeral thread creation and reads use valid identifiers. Turn probes use
a deliberately nonexistent thread, so an ungated request fails before execution.
All backend configuration points to an unavailable loopback fixture endpoint.
"""

import json
import os
from pathlib import Path
import selectors
import subprocess
import tempfile
import time

from fetch_pin import ASSET, BINARY_SHA256, CACHE, digest


def main():
    binary = CACHE / ASSET.removesuffix(".tar.gz")
    if digest(binary) != BINARY_SHA256:
        raise SystemExit("Reference executable does not match the immutable pin")
    with tempfile.TemporaryDirectory(prefix="samgita-codex-gates-") as temporary:
        root = Path(temporary)
        home, work = root / "home", root / "work"
        home.mkdir()
        work.mkdir()
        environment = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": str(home), "CODEX_HOME": str(home)}
        args = [str(binary), "-c", 'model_provider="fixture"', "-c", 'model="fixture-model"',
                "-c", 'model_providers.fixture={name="fixture",base_url="http://127.0.0.1:9/v1",wire_api="responses"}',
                "app-server"]
        process = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL, cwd=work, env=environment)
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)
        counter = 0

        def request(method, params):
            nonlocal counter
            counter += 1
            wire = {"id": counter, "method": method, "params": params}
            process.stdin.write((json.dumps(wire) + "\n").encode())
            process.stdin.flush()
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                if not selector.select(max(0, deadline - time.monotonic())):
                    break
                line = process.stdout.readline()
                if not line:
                    raise RuntimeError("Pinned process exited before replying")
                result = json.loads(line)
                if result.get("id") == counter:
                    return result
            raise RuntimeError(f"Deadline waiting for {method}")

        try:
            initialized = request("initialize", {"clientInfo": {"name": "samgita_gate_probe", "version": "0"}, "capabilities": {"experimentalApi": False}})
            assert "result" in initialized, initialized
            process.stdin.write(b'{"method":"initialized"}\n')
            process.stdin.flush()
            base = {"ephemeral": True, "cwd": str(work), "model": "fixture-model", "modelProvider": "fixture", "sandbox": "read-only", "approvalPolicy": "on-request"}
            probes = [
                ("bool-false", "thread/start", {**base, "experimentalRawEvents": False}, "success"),
                ("bool-true", "thread/start", {**base, "experimentalRawEvents": True}, "gated"),
                ("bool-null-invalid", "thread/start", {**base, "experimentalRawEvents": None}, "invalid"),
                ("optional-null", "thread/start", {**base, "dynamicTools": None}, "success"),
                ("optional-empty-vec", "thread/start", {**base, "dynamicTools": []}, "gated"),
                ("optional-string-null", "thread/start", {**base, "mockExperimentalField": None}, "success"),
                ("optional-string-empty", "thread/start", {**base, "mockExperimentalField": ""}, "gated"),
                ("filter-null-option", "thread/list", {"parentThreadId": None}, "success"),
                ("filter-double-option-null", "thread/list", {"projectId": None}, "gated"),
                ("custom-empty-path", "thread/resume", {"threadId": "deliberately-missing", "path": ""}, "ungated_error"),
                ("optional-map-null", "turn/start", {"threadId": "deliberately-missing", "input": [], "responsesapiClientMetadata": None}, "ungated_error"),
                ("optional-map-empty", "turn/start", {"threadId": "deliberately-missing", "input": [], "responsesapiClientMetadata": {}}, "gated"),
                ("nested-enum", "thread/start", {**base, "approvalPolicy": {"granular": {"sandbox_approval": False, "rules": False, "mcp_elicitations": False}}}, "gated"),
            ]
            rows = []
            for name, method, params, expected in probes:
                response = request(method, params)
                error = response.get("error", {})
                gated = "requires experimentalApi" in error.get("message", "")
                passed = ("result" in response if expected == "success" else gated if expected == "gated" else "error" in response and not gated)
                rows.append({"name": name, "method": method, "expected": expected, "passed": passed,
                             "result_fields": sorted(response.get("result", {})),
                             "error": error or None})
            report = {"version": "0.163.0", "binary_sha256": BINARY_SHA256,
                      "profile": "experimentalApi=false; isolated HOME/CODEX_HOME; unavailable loopback provider; no valid turn execution",
                      "probes": rows}
            print(json.dumps(report, indent=2))
            if not all(row["passed"] for row in rows):
                raise SystemExit("Pinned binary disagrees with expected source gate semantics")
        finally:
            process.stdin.close()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
            selector.close()


if __name__ == "__main__":
    main()
