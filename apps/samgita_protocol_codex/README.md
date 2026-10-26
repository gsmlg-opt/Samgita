# SamgitaProtocolCodex

A standalone native wire/schema library for official Codex **0.163.0**, with a
retained convenience adapter for selected Samgita protocol operations. It opens no listener, starts no runtime, and
depends only on the sibling `samgita_protocol` library. It does not depend on
Phoenix, Samgita persistence, providers, Backplane, or umbrella configuration.

## Reference and compatibility boundary

The reference is the official [OpenAI Codex release rust-v0.163.0](https://github.com/openai/codex/releases/tag/rust-v0.163.0),
commit [`83086188ae0614bd882818ff1aa23f3194962012`](https://github.com/openai/codex/tree/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol).
The GitHub release/tag and official [app-server documentation](https://learn.chatgpt.com/docs/app-server)
were verified on 2026-10-22. `priv/upstream/source.json` records immutable source
paths, upstream SHA-256 hashes and vendored SHA-256 hashes. Schemas have only an
added terminal newline; Apache-2.0 LICENSE and NOTICE are preserved byte for byte.
These describe Codex independently of Samgita's neutral event/session protocol.

The complete generated stable and experimental bundles, source gate metadata and
per-file hashes now live in `priv/upstream/0.163.0/`. Generate/check them with
`scripts/codex/inventory.py` from the repository root. The executable is fetched
into ignored scratch storage by `scripts/codex/fetch_pin.py`; it is never installed
globally or included in this package.

The official JSON exporter omits three legacy requests/results and two raw
notifications. A separately labeled locally derived supplement uses the pinned
TypeScript export and matching Rust/serde declarations. Its origins/hashes are
recorded separately; the original 318 stable and 452 experimental JSON artifacts
remain unchanged. The full source inventory contains 485 requirements and 6,621
field/variant contracts; generated examples do not verify their runtime behavior.

The same pin's timeline JSON export disagrees with its native serializer on two
turn-boundary variants. A separately derived, hash-checked output contract uses
the Rust/TypeScript camelCase names while preserving every original export and
all value/type constraints. See
`docs/codex-app-server/thread-history-qualification.md`; received values are
never rewritten to fit an incorrect export.

`thread/start` also uses a custom native decoder for legacy flat `dynamicTools`
without a `type` tag. A separately derived, hash-checked input contract accepts
those declarations and enforces native list-wide format consistency, including
nested tools. Original flags and wire values remain unchanged; native Codex owns
namespace grouping, exposure defaults and flag precedence. The descriptor can
be reproduced with `scripts/codex/generate_input_semantics.py`; see
`docs/codex-app-server/legacy-dynamic-tool-input-qualification.md` for the three
actual-native profiles and remaining limits.

A second input-only descriptor covers the pinned `compaction_summary` alias in
`thread/resume.history`. The driver preserves that caller tag; native Codex alone
serializes, persists and consumes canonical `compaction` items. All original
field constraints and output contracts remain intact. See
`docs/codex-app-server/compaction-input-alias-qualification.md` for genuine
checkpoint import/continuation evidence and its limits.

A third input-only descriptor accepts native `ModeKind::Default` aliases `code`,
`pair_programming`, `execute` and `custom` for `turn/start` and
`thread/settings/update`. Caller values and experimental negotiation stay intact;
Codex owns canonical `default` settings, parser behavior and persistence. See
`docs/codex-app-server/collaboration-input-alias-qualification.md` for actual
applied settings, literal assistant output and first cold history evidence.
The same descriptor also accepts single-key unit objects for `plan`, `default`
and those four aliases, with `null` or `{}` payload. See
`docs/codex-app-server/collaboration-unit-input-qualification.md` for distinct
native Plan/Default parser and canonical history evidence on these forms.

A fourth descriptor covers deprecated `multiAgentMode` inputs: `none` and the
single-key unit objects for `none`, `explicitRequestOnly` and `proactive`, with
`null` or `{}` payload. The actual nested request decoder's pinned serde source
and MIT license are included as references, never compiled. These three request
fields are native no-ops; accepted input does not activate delegation. See
`docs/codex-app-server/deprecated-mode-input-qualification.md` for exact native
sends, applied snapshots and model/history evidence.

Tests distinguish generated schema examples, real executable journeys and the
restricted convenience mapping. See `docs/codex-app-server/qualification.md` for
current evidence and gaps. Complete behavioral compatibility, real account/backend
acceptance and deployed Sigma/Synapsis integration remain unverified.

## Native wire and schemas

```elixir
alias SamgitaProtocolCodex.{Schema, Wire}

wire = %{"id" => "native-1", "method" => "thread/list", "params" => %{"limit" => 10}}
:ok = Schema.validate_request(wire["method"], wire["params"])
{:ok, json} = Wire.encode(wire)
{:ok, ^wire} = Wire.decode(json)
methods = Schema.methods(:client_request, experimental: true)
```

Native contracts cover all four directions and correlated results from the pinned
release. They preserve string/integer IDs, omitted versus null fields, structured
errors, trace metadata and unknown additions. Validation does not insert defaults
or create atoms. Explicit experimental opt-in follows the pinned Rust request gate
semantics, including nullable options and nonempty collections. The schema corpus
provides structural evidence; it does not certify each operation's runtime behavior.

Use `Schema.validate_request/3` with `direction: :server_request` for incoming
interactions, `validate_notification/4` for either notification direction, and
`validate_result/4` for correlated `:server_response` or `:client_response` values.
`Wire` enforces JSON, envelope, nesting and byte bounds independently of transport.
`Error` retains complete upstream error wire for authorized programmatic callers;
Inspect and Exception output redact upstream payloads. Never log raw wire blindly.

The independent sibling `samgita_codex_driver` owns optional processes, transports,
sessions and interactions. Neither loading this library nor validating a schema
starts execution. The following sections describe the retained convenience API;
its restrictions do not limit the native interface.

## Convenience handshake

```elixir
{:ok, initialize} = SamgitaProtocolCodex.initialize_request("init-1", %{
  "name" => "my_client", "version" => "0.1.0"
})
# Send initialize over an already authenticated connection.
{:ok, _metadata} = SamgitaProtocolCodex.decode_initialize_response(response, "init-1")
# Only after a successful response:
initialized = SamgitaProtocolCodex.initialized()
```

The caller owns authentication, handshake order, one initialization per connection,
transport I/O, pending request state, timeout/disconnect uncertainty and reconnect.
`initialized/0` emits `%{"method" => "initialized"}`. Codex omits the `jsonrpc`
version field on its wire. Native `connection/initialize` and native capability
negotiation cannot be translated into Codex negotiation; no capabilities are
inferred from an initialize response. This adapter never enables experimental APIs.

## Convenience requests and responses

`encode_request(native_request)` returns `{:ok, upstream_map}` or
`{:error, %SamgitaProtocol.Error{}}`. Supported methods are available from
`supported_methods/0`:

| Native method/fields | Codex method/fields |
| --- | --- |
| `thread/start` with empty params | `thread/start` with empty params |
| `thread/read`, `thread/resume`: `thread_id` | Same method: `threadId` |
| `turn/start`: `thread_id`, text `input` | Same method: `threadId`, text `input` |
| `turn/steer`: `thread_id`, `turn_id`, text `input` | Same method: `threadId`, `expectedTurnId`, text `input` |
| `turn/interrupt`: `thread_id`, `turn_id` | Same method: `threadId`, `turnId` |

Native `thread/start` title/metadata are rejected explicitly; this subset does not
silently discard them or invent upstream equivalents. Model/provider, working
directory, tool and sandbox configuration stay with the upstream host. Approval
requests/responses, native `request/cancel`, `stream/resume`, and project-event
methods are unsupported. The adapter exposes per-method support rather than
claiming complete native capability-group compatibility.

`decode_message(upstream_map, original_native_request)` correlates a reply to its
exact pending request and returns a native response. Native identity, correlation,
command and reference metadata are copied only from that original request; they
are never inferred from upstream thread IDs. Thread results contain the upstream
thread as optional JSON. Turn start/steer acknowledges a running turn; interruption
acknowledges only `requested`, never proof that tools stopped. Malformed or
mismatched results fail explicitly. Upstream errors map to a safe `upstream_error`
with numeric code only; upstream message/data are not copied into native errors.
Only the documented overload code `-32001` is marked retryable; callers still
must reconcile uncertain mutations before retrying.

`command_id` remains a native reconciliation identity and is **not sent upstream**:
Codex does not thereby supply durable acknowledgement, deduplication, exactly-once
effects, Project/Task mutation or management acceptance. No command is automatically
replayed. Hub references and native envelope metadata are never injected into
Codex messages.

## Convenience notifications

`supported_notifications/0` lists `turn/started`, `turn/completed` and
`item/agentMessage/delta`; the last maps to native `item/delta`. A notification
requires explicit context with `correlation_id`, expected `thread_id` and `turn_id`.
The context may also provide native `causation_id`, `project_ref`, `task_ref` and a
paired `stream_id`/positive `cursor`. Mismatched thread/turn IDs fail before mapping.

Without stream metadata the adapter emits no cursor. Supplied stream metadata is
the caller's local projection position, not an upstream durable cursor or replay
guarantee. The caller owns ordering, retention and authorization. Full item/tool
events, approvals and unknown notifications fail explicitly; codecs never approve
or execute tools. A connection owner may deliberately route other upstream traffic
elsewhere; it must not silently treat an adapter error as a successful translation.

## Build and verify

From this directory, using Elixir 1.18+:

```sh
mix deps.get
mix test
mix compile --warnings-as-errors
mix format --check-formatted
```

The package has its own build/dependency/config/lock paths. Run package commands
from this directory; no umbrella application or database needs to start.
