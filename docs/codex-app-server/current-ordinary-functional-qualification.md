# Current-client ordinary functional qualification

## Runnable selection

Run from the repository root in the reviewed Elixir/OTP environment.

```sh
python3 -B scripts/codex/check_current_ordinary.py --list
python3 -B scripts/codex/check_current_ordinary.py --fingerprint
python3 -B scripts/codex/check_current_ordinary.py \
  --binary "$(command -v codex)" \
  --output /tmp/samgita-current-ordinary-new-evidence
```

The output directory must be new. The runner checks the reviewed source
fingerprint, copies the four reusable packages into a disposable directory,
resolves their existing lockfiles, and executes only the listed checks. A
changed lockfile, unexpected test count, failure, source change or executable
change stops qualification. `source.json` records the source hashes, selected
client path/version/SHA-256, schema snapshot and Elixir/OTP output. Each step
has its own log and entry in `results.json`.

The executable is an explicitly selected installed Codex client. The profile
records its observed version and bytes. The native tests use fresh disposable
HOME/CODEX_HOME/workspaces, the existing deterministic loopback Responses
provider and fixed `approval_policy="never"` / `sandbox_mode="danger-full-access"`
launch inputs. They create synthetic Projects and threads. They require no
paid inference or production task.

| Ordinary coverage | Selected tests | Required result |
| --- | --- | --- |
| Snapshot refresh staging | `scripts/codex/test_refresh_snapshot.py` | 2 cases |
| Project schema compatibility | `samgita_protocol_codex/test/project_output_compatibility_test.exs` | 3 cases |
| Driver schema drift and correlation | `samgita_codex_driver/test/compatible_schema_test.exs` | 25 cases |
| Query uncertainty and explicit recovery | `samgita_codex_driver/test/query_uncertainty_test.exs` | 41 cases |
| Owned stdio cleanup phases | `samgita_codex_driver/test/stdio_owner_lifecycle_test.exs` | 4 cases |
| Actual Project create/list, streamed chat, history and reconnect | `samgita_codex_driver/test/current_ordinary_workflows_test.exs` | 2 cases at each of seeds 501432 and 987654 |
| Loopback replay, bounded overflow and retention gap | Three named locations in `samgita_protocol_websocket/test/integration_test.exs` | 16 registered cases, 0 failures, 13 excluded at each of seeds 455834, 501432 and 987654 |

The runner verifies the exact names at each selected WebSocket line before
execution. The source fingerprint covers exactly the copied inputs from the
four reusable packages, `scripts/codex` and the compatibility manifest. It
includes uncommitted files, package documentation, configuration, lockfiles,
complete schema evidence and Rust source. The same exclusions apply to copying
and hashing for dependency directories, build outputs and caches. Umbrella Web
assets and other files outside those inputs do not affect this profile.
Changing that fingerprint requires review of the resulting selection and
source diff. Security, credential, authentication, authorization and approval
tests remain outside this selection. Browser journeys and live remote-host
connections require their own evidence.

## Snapshot migration to 0.172.0

The repository tracks upstream commit `3d86e43b075adeba2193ec5c22ac92f55afd82e6`.
All 331 stable and 483 experimental JSON files matched an independent export of
the release executable byte for byte. The refresh stages the official schemas,
source-derived metadata, inventory and fixtures together. A changed guard stops
generation before installation. Repeating generation from the same recorded
release produced identical bytes for all 880 installed files.

- The surface now contains 192 client requests, 10 server requests, 89 server
  notifications and one client notification, including the source-derived
  supplement. The ordinary runtime notification surface remains at 64.
- Project results use the official schema in both validation modes. Numeric
  `position` disappeared from the Project output, while `position` remains a
  valid `project/list` sort key.
- `thread/search/stream` shares the search parameters. Its native sort-key,
  direction and source-kind forms follow the same Rust declarations as
  `thread/search`. The original request bytes are retained.
- Realtime items can carry `observedAtMs` and a frame, accepted turn input or
  saved session input. The runtime maps the two new input variants' native
  camelCase field names for live notifications, timeline results and realtime
  history. The raw export and the Rust/TypeScript evidence are kept separately.
- The validator accepts unsigned 8-bit integers in the range 0–255. This format
  occurs in nested message displays. The vocabulary check traverses definitions
  before validating a payload, so a missing format also broke ordinary thread
  responses and strict sessions that received a notification after initialization.
- Upstream retired the `currentTime/read` callback. With an external clock
  selected and no native provider, the official server returns an error at
  `thread/start`. Stable and experimental sessions both exercised this path.
- The driver classifies streamed thread searches, realtime history and provider
  listing as queries. A lost response records no uncertain execution and never
  resends the request. Search cancellation and provider configuration writes
  retain mutation semantics.

`inventory.py --check` passed for 519 requirements and 7,298 field/variant
contracts. The generated corpus contains 494 synthetic message examples. The
manifest still records missing and blocked work.

## Verification on 2026-11-26

Elixir 1.18.5 and OTP 28 completed all 12 current-profile steps for both
clients against the installed 0.172.0 snapshot. Each run passed 86 Elixir
cases across the selected seeds and two Python staging cases. The before/after
hashes matched for all 1,598 source inputs and each client binary. The
reviewed source fingerprint is
`c65ca6a53e6ceeec19c9154bc8a1b405144b56ba2c69d5970e740cd72d96244f`.

| Client | Executable SHA-256 |
| --- | --- |
| Official Linux 0.172.0 | `ad83b94c093f0cdd8176a6bc8005a461bdf23a759863e157d40f562b8a9d664d` |
| Installed Linux 0.171.0 | `b76a027d6b210f9a8da7aaf321dd235c700f0ef7a794d4a5314b9af6c134f0f0` |

In a separate disposable driver copy, `SAMGITA_CODEX_SCHEMA_MODE=strict`
passed both current Project/chat workflows on 0.172.0. A further strict
probe read the fixture model catalog and thread list, listed its configured
provider, streamed a search with no matches and read an empty realtime
history from an ordinary text thread. Reconnecting recovered the completed
turn with one model request in total. Populated realtime frames and session
inputs were checked against the derived wire contracts with synthetic tests.

The standalone protocol checks also passed 77 input and alias cases, 14
output and integer-format cases, and three selected stable response,
notification and surface cases. Full conformance and security tests were
outside the selection.

## Historical selections

The replay repair explicitly consumes the owner's disconnect notification and
observes the acknowledged WebSocket frame. Its three named tests cover retained
events, bounded overflow and retention gaps. On 2026-11-25, before the snapshot
upgrade, the old 0.167.0 schema passed the previous 12-step current-client
profile on clients 0.171.0 and 0.172.0 (74 Elixir cases plus two Python cases
per client).

The historical `check_ordinary.py` selection retains its 166 main and 26
extension cases. Some depend on 0.163.0 source hashes, field layouts and the
retired current-time callback. Its prior results apply to that recorded source
and client. Full native compatibility, security checks and remote-host
conformance have separate gates.
