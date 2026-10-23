# Isolated native executor environment profile

This explicit Linux profile runs the immutable Codex `rust-v0.163.0` release
executable as both app-server and authenticated exec-server. It qualifies local
registration, metadata, authentication and connection lifecycle only. It sends no
turn, shell command, remote filesystem request, paid request or live credentials.
It does not qualify execution sandbox enforcement, cloud registries, Noise/AWS
transports, external services, other operating systems or deployment.

Run from `apps/samgita_codex_driver` in the verified Elixir environment:

```sh
MIX_ENV=test CODEX_BINARY=/absolute/path/to/pinned/codex \
  mix test test/native_environment_profile.exs --seed 501432
```

The filename deliberately avoids default `*_test.exs` discovery. Independent
consumer/default tests do not require namespace tooling. Explicit profile runs
fail when Linux, `unshare`, `ip`, namespace permission or native startup is
unavailable. There is no skip, privilege escalation or host-network fallback.

`scripts/codex/isolated_environment_fixture.py` first creates a private user and
network namespace and verifies a distinct namespace, only loopback interfaces and
routes, and no default route. Both native processes, the byte proxy and a deny-all
HTTP sentinel run inside it. Their environments explicitly select disposable
homes, configuration, temporary roots and working directories; inherited
credentials, proxy settings and exporters are absent. A local model catalog
avoids catalog discovery. Every HTTP request fails the profile, and the bridge
allows only initialization, environment metadata/registration and loaded-thread
discovery. Native JSONL is forwarded unchanged. The proxy copies bytes and only
closes owned connections; it cannot manufacture a successful native RPC.

The executor starts through the production CLI:

```text
codex exec-server --listen ws://127.0.0.1:0 \
  --ws-auth capability-token --ws-token-file <absolute-owned-0600-file>
```

The actual bound URL is read from native stdout after binding; no fixed host port
or bind-and-release port allocation is used. Native upgrades must return 401 for
absent/wrong credentials and 101 for the owned synthetic token. The app-server
then connects to this native executor through the owned transparent proxy.
Neither a listening socket nor `/readyz` establishes environment readiness.

Four cases cover:

- Successful asynchronous registration followed by actual `environment/status`
  readiness and `environment/info` matching the executor's controlled cwd/shell.
- Missing/wrong credentials rejected by the native executor, explicit upsert to
  correct stored connection credentials, then recovery after socket interruption
  with the same retained credential and no further registration. Recovery waits
  for an observed new proxy connection and verified native readiness.
- Invalid replacement preserving the existing registration, unknown environment
  errors, and duplicate valid registration behaving as an explicit native upsert.
- Owned executor disappearance yielding `disconnected` and an explicit native
  info error while preserving registration. Failure does not create work or
  silently turn the registered environment into an unknown one.

Each case requires no loaded threads, no HTTP/model traffic, and no synthetic
credential canary in fixture journals or native stderr. The journal stores only
allowlisted observations, method names, owned PIDs and loopback destination
metadata. Close must reap the app-server, executor, namespace controller and
namespace owner before fixture deletion. The existing stdio process-group owner
is unchanged. Local executor mode has independent lifetime: closing its stdin is
insufficient, so the controller explicitly terminates and waits for both children.

Pinned source commit is `83086188ae0614bd882818ff1aa23f3194962012`; binary SHA256 is
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

| Contract | Pinned source |
| --- | --- |
| Production exec-server CLI and dispatch | `cli/src/main.rs:239,1821`; `cli/src/exec_server_command.rs:57-76,165-191,292-344`. |
| Actual native auth/reconnect precedent | `cli/tests/exec_server_websocket_auth.rs:30-145` launches the multicall CLI, rejects bad upgrades, then authenticates multiple connections. |
| Listener URL, readiness, Origin rejection and auth | `exec-server/src/server/transport.rs:178-274`. |
| Add is registration, not health | `app-server/src/request_processors/environment_processor.rs:18-50`; `exec-server/src/environment.rs:509-531,569-584`. |
| Credential retention and secure header rules | `exec-server/src/environment/connect_options.rs:16-19,55-69,99-100`. |
| Status cannot initiate recovery | `exec-server/src/environment.rs:1163-1172`; `exec-server/src/client.rs:474-502`. |
| Info probes and recovery | `exec-server/src/environment.rs:1019-1021`; `exec-server/src/client.rs:516-578`; `exec-server/src/client_recovery.rs:327-355`. |
| Local process lifetime | `cli/src/exec_server_command.rs:325-342`; `cli/src/exec_server_telemetry.rs:58-149`. |

Upstream app-server environment tests use scripted peers in several scenarios
(`app-server/tests/suite/v2/environment_add.rs`, `environment_info.rs`,
`environment_status.rs`, `exec_server_test_support.rs`). They establish intended
contracts but do not count as actual executor qualification. This profile uses
the release executable for both endpoints. Top-level app-server `fs/*` methods
operate on its local filesystem (`fs_processor.rs:54-56`) and are deliberately
excluded from claims about remote environments. Default Linux executor PID
isolation remains enabled; metadata success proves no sandbox execution behavior.

The first explicit run reached each case's final discovery assertion but failed
all four because the fixture omitted `nextCursor: null` from its expected empty
loaded-thread page. Pinned `app-server-protocol/src/protocol/v2/thread.rs:1671-1676`
includes that nullable field. The corrected assertion requires both empty data
and a null continuation cursor. No native runtime, timeout, authentication rule
or cleanup behavior was changed for this fixture correction.

Final local validation ran from the repository root:

```sh
devenv shell --no-tui -- env MIX_ENV=test \
  CODEX_BINARY="$PWD/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl" \
  sh -c 'cd apps/samgita_codex_driver &&
    mix format test/native_environment_profile.exs &&
    mix compile --warnings-as-errors &&
    mix test test/native_environment_profile.exs --seed 501432 &&
    mix test test/native_environment_profile.exs --seed 987654'
```

Formatting and warnings-as-errors compilation passed. Each seed passed **4 tests,
0 failures**, including actual native authentication, reconnection and owned
process-reaping assertions. Python bytecode compilation passed. Initial evidence
is `/tmp/samgita-native-environment-initial.log`; final evidence is
`/tmp/samgita-native-environment-repair-1.log`. This qualifies the local isolated
metadata/authentication/lifecycle profile, with the execution, external-service
and platform limits above still unverified.
