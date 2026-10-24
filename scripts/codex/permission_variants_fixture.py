#!/usr/bin/env python3
"""Fixed model output for native permission variants, never app-server frames.

No listener or native process is started by importing this module.
"""
import argparse
import json
from pathlib import Path

from model_fixture import ModelFixture


class PermissionVariantsFixture(ModelFixture):
    def response_item(self, index, request):
        reviewer = request.get("client_metadata", {}).get("x-openai-subagent") == "guardian"
        reviews = [r for r in self.requests if
                   r.get("client_metadata", {}).get("x-openai-subagent") == "guardian"]
        parents = len(self.requests) - len(reviews)
        if index > 4:
            raise ValueError("Unexpected extra native provider request")
        if reviewer:
            assert self.scenario in {"strict_allow", "strict_deny"}
            assert len(reviews) == 1 and parents == 2
            assert "printf samgita_strict_turn" in json.dumps(request)
            allowed = self.scenario == "strict_allow"
            return self.message("owned-guardian-result", json.dumps({
                "risk_level": "low" if allowed else "high",
                "user_authorization": "high" if allowed else "unknown",
                "outcome": "allow" if allowed else "deny",
                "rationale": "Fixed local permission variant review only.",
            }))
        if parents == 1:
            return self.function("request_permissions", "permission-variant-1", {
                "reason": "Owned permission variant only",
                "permissions": self.requested_permissions(),
            })
        if self.scenario.startswith("strict_") and parents == 2:
            return self.function("exec_command", "permission-variant-command", {
                "cmd": "printf samgita_strict_turn", "workdir": self.workspace,
                "login": False,
            })
        if self.scenario == "empty_grant" and parents == 2:
            patch = "*** Begin Patch\n*** Add File: must-not-exist.txt\n+owned rejected patch\n*** End Patch"
            return self.function("exec_command", "permission-variant-patch", {
                "cmd": f"apply_patch <<'EOF'\n{patch}\nEOF\n",
                "workdir": self.workspace, "login": False,
            })
        expected = 3 if self.scenario.startswith("strict_") or self.scenario == "empty_grant" else 2
        assert parents == expected
        return self.message("owned-variant-finished", "Owned permission variant finished.")

    def requested_permissions(self):
        if self.scenario.startswith("network_"):
            return {"network": {"enabled": self.scenario != "network_requested_false"}}
        if self.scenario == "read_only":
            return {"file_system": {"read": [str(Path(self.workspace) / "readable")]}}
        if self.scenario == "canonical":
            root = Path(self.workspace)
            return {"file_system": {"entries": [
                self.entry("read", str(root / "readable")),
                self.entry("write", str(root / "writable")),
                self.entry("deny", str(root / "writable/secrets")),
                {"path": {"type": "glob_pattern", "pattern": str(root / "writable/**/*.blocked")},
                 "access": "deny"},
            ], "glob_scan_max_depth": 2}}
        return {"file_system": {"write": ["."]}}

    @staticmethod
    def entry(access, path):
        return {"path": {"type": "path", "path": path}, "access": access}

    @staticmethod
    def message(identity, text):
        return {"type": "message", "role": "assistant", "id": identity,
                "content": [{"type": "output_text", "text": text}]}

    @staticmethod
    def function(name, identity, arguments):
        return {"type": "function_call", "name": name, "call_id": identity,
                "arguments": json.dumps(arguments)}

    def config(self, codex_home):
        super().config(codex_home)
        path = Path(codex_home, "config.toml")
        text = 'approvals_reviewer = "user"\n' + path.read_text()
        text += ('\n[features]\nshell_snapshot = false\nrequest_permissions_tool = true\n'
                 'guardian_approval = true\nenable_request_compression = false\n'
                 '[features.guardianv2]\nenabled = false\n')
        path.write_text(text)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", required=True, choices=[
        "network_allow", "network_false", "network_null", "network_omitted",
        "network_requested_false", "read_only", "canonical", "empty_grant",
        "strict_allow", "strict_deny", "strict_control",
    ])
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--requests-file", required=True)
    args = parser.parse_args()
    fixture = PermissionVariantsFixture(args.scenario, args.workspace, args.requests_file).start()
    fixture.config(args.codex_home)
    print(json.dumps({"url": fixture.url}), flush=True)
    try:
        input()
    except EOFError:
        pass
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
