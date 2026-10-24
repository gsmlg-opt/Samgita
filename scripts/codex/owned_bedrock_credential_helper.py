"""Fixed synthetic credential helper; installed only as an exclusive scratch bin/aws.

The fixture prepends an absolute Python shebang with -I. This helper accepts no
paths, commands, credential input, shell syntax or model-selected arguments.
"""
import hashlib
import json
import os
from pathlib import Path
import sys


SHA256 = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
OLD = {"Version": 1, "AccessKeyId": "OWNED_BEDROCK_OLD_KEY",
       "SecretAccessKey": "owned-bedrock-old-secret-canary",
       "SessionToken": "owned-bedrock-old-session-canary"}
NEW = {"Version": 1, "AccessKeyId": "OWNED_BEDROCK_NEW_KEY",
       "SecretAccessKey": "owned-bedrock-new-secret-canary",
       "SessionToken": "owned-bedrock-new-session-canary"}


def write_json(path, value):
    pending = path.with_suffix(".pending")
    pending.write_text(json.dumps(value))
    pending.replace(path)


def main():
    assert len(sys.argv) == 2 and sys.argv[1] in ["--owned-refresh", "--owned-export"]
    root = Path(__file__).resolve(strict=True).parent.parent
    owner = json.loads((root / "native-owner.json").read_text())
    parent = os.getppid()
    assert owner["pid"] == parent
    assert hashlib.sha256(Path(f"/proc/{parent}/exe").read_bytes()).hexdigest() == SHA256
    assert os.getpgid(0) == os.getpgid(parent) == owner["pgid"]
    namespace = os.readlink("/proc/self/ns/net")
    assert namespace == owner["netns"] and namespace != owner["parent_netns"]
    assert Path(os.environ["CODEX_HOME"]).resolve() == root / "codex"
    # The pinned native arg0 launcher prepends its own locked alias directory.
    # Accept only that exact owned directory plus the exclusive helper bin;
    # no ambient search directory or alternate aws may participate.
    search = [Path(value) for value in os.environ["PATH"].split(os.pathsep)]
    assert len(search) == 2 and search[1] == root / "bin"
    aliases = search[0]
    assert aliases.parent == root / "codex/tmp/arg0-linux"
    assert aliases.name.startswith("codex-arg0") and aliases.is_dir()
    assert {entry.name for entry in aliases.iterdir()} == {
        ".lock", "apply_patch", "applypatch", "codex-linux-sandbox"}
    for entry in aliases.iterdir():
        if entry.name != ".lock":
            assert entry.is_symlink()
            assert hashlib.sha256(entry.read_bytes()).hexdigest() == SHA256
    assert not (aliases / "aws").exists()
    assert Path(__file__).resolve() == root / "bin/aws"
    assert not any(key in os.environ for key in ["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY",
        "AWS_BEARER_TOKEN_BEDROCK", "AWS_WEB_IDENTITY_TOKEN_FILE", "AWS_ROLE_ARN",
        "DBUS_SESSION_BUS_ADDRESS", "SSH_AUTH_SOCK"])
    mode = sys.argv[1].removeprefix("--owned-")
    state = json.loads((root / "credential-state.json").read_text())
    if mode == "refresh":
        assert owner["scenario"] in ["profile", "export"] and state == "old"
        assert not list((root / "helpers").glob("*-refresh.json"))
        credentials = root / "aws/credentials"
        pending = credentials.with_suffix(".pending")
        pending.write_text("[owned]\naws_access_key_id = " + NEW["AccessKeyId"] +
            "\naws_secret_access_key = " + NEW["SecretAccessKey"] +
            "\naws_session_token = " + NEW["SessionToken"] + "\n")
        pending.chmod(0o600)
        pending.replace(credentials)
        write_json(root / "credential-state.json", "new")
    else:
        assert owner["scenario"] == "export"
        assert state in ["old", "new"]
        assert len(list((root / "helpers").glob("*-export.json"))) < 2
        print(json.dumps(OLD if state == "old" else NEW), flush=True)
    write_json(root / f"helpers/{os.getpid()}-{mode}.json", {
        "pid": os.getpid(), "ppid": parent, "pgid": os.getpgid(0), "netns": namespace,
        "mode": mode, "state": state, "success": True,
        "parent_binary_verified": True, "fixed_arguments_verified": True,
        "owned_search_path_verified": True,
        "no_descendants": True})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
