# Native configuration and lifecycle notice qualification

Five local native cases pass with two seeds against the immutable target below.
One isolated deterministic text-only provider request materializes real native
history for the positive deprecation case; the other four cases forbid inference.
This evidence does not establish full Codex compatibility, hosted qualification,
real provider integration, publication or deployment.

## Immutable target and scope

Target: Codex `rust-v0.163.0`, source commit
`83086188ae0614bd882818ff1aa23f3194962012`, Linux binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The source-review baseline is `d88a28e21e78f12071146c53277f1ebc35ef97ba`;
the parent subsequently committed the independent background-terminal unit
as `2a2189d`. This unit has Sol repair rounds 2 / Astra repairs 0.

Owned files are `apps/samgita_codex_driver/test/native_configuration_notice_test.exs`,
`scripts/codex/configuration_notice_fixture.py`, and this document. No protocol
implementation, shared manifest, workflow, sibling service or platform domain
behavior changes in this unit.

Every app-server response and notification must originate from the pinned
native binary over a borrowed Unix-domain socket. The Stdio transport owns
only the Python fixture controller. The fixture reuses the existing isolated
controller and static synthetic model catalog; it does not emulate app-server
messages or history. Only the separately authorized history scenario issues
one `turn/start`, using fixed synthetic text input and fixed assistant text
output. No hook, tool, command, MCP action or approval response is issued.

## Cases and semantic limits

| Case | Required native observation | Runtime result |
| --- | --- | --- |
| Ignored startup key | One warning includes ignored `network_proxy`, excludes a private marker value, and does not repeat after plain thread registration | Passed both seeds |
| Post-initialize rule error | Writing owned `prefix_rule(` then registering a thread produces the native parse warning, owned path, exact 1:13 start/end range and parser details | Passed both seeds |
| Empty paginated registration | Metadata read succeeds with empty turns; full hydration returns exact native -32601 `list_turns is not supported yet` and emits no deprecation notice | Passed both seeds |
| Persisted paginated thread | One completed native text-only turn appears in the native persisted list; metadata reads emit no notice, full hydration emits the pinned deprecation notice and actual completed turn/user and assistant items | Passed both seeds |
| Unsupported priority tier | Empty advertised service-tier lists and configured `priority` produce the exact native warning with the actual created thread ID | Passed both seeds |

Startup `configWarning.details` is explicitly null, while absent `path` and
`range` are omitted keys. Tests distinguish null from omission. Located rule
warnings assert non-null parser details, path and range. The paginated
deprecation notice has explicit null details. The tier warning must carry the
actual thread identity rather than a null or fixture-selected identity.

The priority case proves warning delivery only. It cannot prove omission from
an outgoing inference request because inference is forbidden in that scenario.
No hosted profile, paid provider, real credential, external model execution or complete
Codex compatibility is claimed. Schema and source conformance remain distinct
from runtime behavior and from publication/deployment.

## Isolation and cleanup

Each case creates disposable HOME, CODEX_HOME, workspace, temporary directory
and shell copy. The controller starts native inside a private Linux user and
network namespace, with loopback only and no IPv4 or IPv6 default route.
Environment inheritance is explicit; account/provider URLs point only at the
owned loopback peer and no authentication is required. Remote control, remote
models, shell tools, unified execution, hooks, apps, plugins and shell snapshot
are disabled. Existing credentials and platform configuration are not read.

The provider records each actual Responses request before responding. Only
the history branch permits index one with the exact synthetic input marker;
it supplies a fixed assistant message and rejects a second request or unexpected
input. All other inference raises and writes an explicit unexpected-inference
marker. Cleanup requires exactly one request for history and zero otherwise,
with no marker. Unexpected native server requests always fail. The four
no-inference cases also reject turn/item starts. The history case requires a
completed actual native turn, persisted-list membership, hydrated turn identity,
fixed assistant output and only user/assistant message item types. The tests close their
borrowed Session before stopping the owned controller, then prove disappearance
of all recorded native, controller and namespace-owner PIDs. The shared
controller terminates/reaps only its own native child; no unrelated process
is signalled.

## Pinned upstream source anchors

Paths are relative to the immutable `codex-rs/` tree.

| Behavior | Source |
| --- | --- |
| Ignored-key summary redaction and no plain-thread duplicate | `app-server/tests/suite/strict_config.rs:15-76` |
| Release does not use test-only managed-config override | `app-server/src/main.rs:25-28,95-103`; `config/src/loader/mod.rs:730-744` |
| Initial warning mapping and delivery | `app-server/src/lib.rs:686-694`; `app-server/src/request_processors/initialize_processor.rs:232-252` |
| Nullable details versus omitted location | `app-server-protocol/src/protocol/v2/config.rs:1156-1172` |
| Reloaded rule warning before thread/start response | `app-server/src/request_processors/thread_processor.rs:1429-1458` |
| Error location conversion and native rule regression | `app-server/src/lib.rs:337-369`; `app-server/tests/suite/v2/thread_start.rs:121-184` |
| Paginated deprecation text and trigger | `app-server/src/request_processors/thread_processor.rs:42-43,866-886`; `app-server/tests/suite/v2/thread_read.rs:382-406` |
| Empty native thread full-read persistence fallback | `app-server/src/request_processors/thread_processor.rs:3156-3180` |
| Missing persisted metadata blocks paginated listing | `thread-store/src/local/thread_history/read.rs:203-230` |
| Unsupported tier initial warning | `core/src/session/mod.rs:901-909,1008-1017,1208-1223` |
| Priority gate and explicit model support | `features/src/lib.rs:570-577,1973-1978`; `protocol/src/openai_models.rs:425-428,1004-1012` |
| Warning's actual thread ID and notification shape | `app-server/src/bespoke_event_handling.rs:275-282`; `app-server-protocol/src/protocol/v2/notification.rs:17-38` |

## Verification record

Source inspection and non-importing Python AST syntax validation passed.
Namespace preflight proved changed user/network namespaces, loopback-only
interfaces and no default route. Driver/root warnings-as-errors compile,
scoped format and positional strict Credo checks passed against final code.
Both seeds (501432/987654) passed five tests, zero failures, in 6.6 seconds each.

The parent granted exclusive runtime ownership for these commands. Every Mix
invocation used `MIX_ENV=test`; no competing Mix/native worker was active.

```sh
python3 -c 'import ast; from pathlib import Path; p=Path("scripts/codex/configuration_notice_fixture.py"); ast.parse(p.read_text(), filename=str(p)); print("AST parse passed; fixture not imported")'
devenv shell --no-tui -- python3 scripts/codex/check_namespace_prerequisites.py
devenv shell --no-tui -- env MIX_ENV=test mix compile --warnings-as-errors
devenv shell --no-tui -- env MIX_ENV=test mix credo apps/samgita_codex_driver/test/native_configuration_notice_test.exs --strict
```

Run from `apps/samgita_codex_driver`, with `CODEX_BINARY` set to the absolute
verified binary path (and the same test environment):

```sh
MIX_ENV=test mix format --check-formatted test/native_configuration_notice_test.exs
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix test test/native_configuration_notice_test.exs --seed 501432
MIX_ENV=test mix test test/native_configuration_notice_test.exs --seed 987654
```

Initial run: four tests, two failures. The home requirements file did not load
in the release CLI, and a genuinely empty thread had no persisted metadata for
paginated hydration. Source review corrected the user-key scope and established
that errors return before the deprecation emitter. The parent then explicitly
authorized the one-request synthetic history branch. Repair one passed both
seeds (five tests each, 6.7/6.6 seconds); strict Credo found only the integer
separator spelling. Repair two changed `-32601` to `-32_601` without altering
the asserted wire value. Original five-second barriers and cleanup checks
remain intact. Final logs: `/tmp/samgita-configuration-notice-final.log`;
initial/diagnostic/first-repair logs use the same prefix with `initial`,
`diagnostic` and `repair1`. Logs are local evidence, not published artifacts.
