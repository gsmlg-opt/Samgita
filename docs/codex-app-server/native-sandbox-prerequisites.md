# Pinned native Linux sandbox prerequisite

The native output/patch profile requires Codex's actual sandbox launcher as well
as private user/network namespaces. An `unshare` preflight alone cannot qualify
the descriptor mounts, seccomp or bundled bubblewrap launch. This prerequisite
does not approve an unsandboxed retry or qualify every sandbox policy.

## Observed failure and immutable source

Hosted conformance [40031683177](https://github.com/gsmlg-opt/Samgita/actions/runs/40031683177),
at `b592e829149bde647f9953c8950f91d289b38455`, passed namespace setup and all
13 then-selected isolated profiles. The default driver suite failed **388 tests /
1 failure**, seed `354233`, 177.5s. The native patch emitted an unexpected
`item/fileChange/requestApproval` for `owned-patch-call`, reason
`command failed; retry without sandbox?`. The test rejected it without replying.
Its provider/controller discarded native stderr, so the failure alone did not
establish missing bwrap versus another native sandbox failure.

All source anchors refer to Codex `rust-v0.163.0`, commit
`83086188ae0614bd882818ff1aa23f3194962012`, under `codex-rs/`:

- `linux-sandbox/src/launcher.rs:142-162,176-188,213-237` chooses an eligible
  system bwrap, requiring `--as-pid-1` and `--perms`, then the bundled resource.
  `--argv0` is optional; requiring it would misdescribe the pin.
- `sandboxing/src/bwrap.rs:179-255` rejects system executables in replaceable
  policy-writable locations. Merely prepending a writable fixture tool is unsafe.
- `linux-sandbox/src/bundled_bwrap.rs:67-82,109-140,148-199` discovers
  `codex-resources/bwrap` beside the binary, checks its embedded SHA-256 and
  executes the verified descriptor.
- `arg0/src/lib.rs:59-82,175-183` dispatches fixed argv0 `codex-linux-sandbox`
  directly. `linux-sandbox/src/linux_run_main.rs:90-120,160-177,294` implements
  the managed permission profile used by the prerequisite.

The official bare Codex archive contains only the executable. Previously the
fetcher installed no bundled resources, leaving an implicit system dependency.
The exact failed runner's public image inventory omitted bwrap; that inventory
does not prove its live absence or version. Keep that historical cause limit.

## Resource pin and installation

The fetcher now also installs the matching official Cargo release resource from
[the same release](https://github.com/openai/codex/releases/tag/rust-v0.163.0):

| Item | Immutable value |
| --- | --- |
| Asset | `bwrap-x86_64-unknown-linux-musl.tar.gz` |
| Archive SHA-256 | `bcc196b1d25dc2c2b912dcedf780b562deb0552f3c50648761ced145c3466a23` |
| Sole regular member | `bwrap-x86_64-unknown-linux-musl` |
| Payload SHA-256 | `77360cb751ccedc5971391444ac86a8a33c15b04d6b4a6fe45f5d25496e62c4c` |
| Ignored installation path | `tmp/codex/0.163.0/codex-resources/bwrap` |
| Unchanged Codex SHA-256 | `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215` |

The payload digest is embedded in the unchanged native binary. Matching release
build source hashes final bwrap bytes into Codex; package assembly preserves those
bytes (`.github/actions/build-cargo-package-binaries/action.yml:99-114` and
`.github/actions/build-codex-packages/action.yml:145-176`, relative to source root).
No resource is stripped, patched or substituted. Installation validates both
hashes and the sole regular member, rejects destination links and atomically
replaces only its owned cache resource. Source-only fetching remains source-only.
No host package, PATH, sysctl, remote permission or sibling repository is changed.

## Executable prerequisite and local evidence

Run from a verified Elixir/OTP environment, with `CODEX_BINARY` set to the pin:

```sh
python3 -B scripts/codex/fetch_pin.py
python3 -B scripts/codex/check_namespace_prerequisites.py
python3 -B scripts/codex/check_native_sandbox_prerequisites.py
```

The native probe verifies binary/resource hashes and creates one private owned
user/network namespace with loopback only and no default route. It runs the
native helper with fixed Python code, a managed root-read/workspace-write profile
and an empty tool PATH to force the verified bundled fallback. The same invocation
must change its allowed regular file, receive EROFS/EACCES/EPERM writing an owned
sibling outside the workspace, and preserve that outside file's bytes. The
outside file is writable before sandboxing. Missing paths or incidental errors
cannot satisfy the denial. No shell, model, listener, arbitrary command,
app-server approval response or legacy sandbox fallback is available. Failure
captures underlying native stderr from an allowlisted synthetic environment;
bounded timeout cleanup targets only owned process groups.

Local first run passed: bundled fallback launched, allowed write succeeded,
outside write was denied with **EROFS (30)** and outside bytes stayed unchanged.
The host system tool was `/run/current-system/sw/bin/bwrap`; the forced fallback
ensures local success does not depend on that tool. The four native output tests
then passed **4/0**, seed `354233`, **7.0s**, with all original deadlines, diff,
filesystem and unexpected-approval assertions. Log:
`/tmp/samgita-native-sandbox-prerequisite-initial-20261024.log`.

Eight new offline integrity tests plus the existing inventory/fixture tests
passed **31/0**, 3.121s. They use synthetic bytes without execution and test exact
installation/cache reuse, corrupted cache recovery, wrong payload preservation,
extra/traversing/absolute archive members, archive/destination links and a
nonexecutable cache failure. Python 3.10 AST parsing passed. Log:
`/tmp/samgita-pin-sidecar-offline-20261024.log`.

Both hosted native jobs require the same write/deny prerequisite before their
suites. Hosted validation of this resource change is pending; local success and
source correspondence do not claim a repaired hosted run. The strict completeness
gate, A11, external/backend/OS profiles and full compatibility remain incomplete.
