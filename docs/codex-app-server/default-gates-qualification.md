# Native defaults and experimental-presence differentials

Five stock-binary cases pass at seeds `501432` and `987654`. Python AST,
namespace preflight, warnings-as-errors compilation, formatting and scoped
strict Credo pass. Broad `lifecycle:missing-null-default` and
`lifecycle:experimental-negotiation` remain **missing**; selected differentials
do not establish the exhaustive negotiation/default contract.

The source is immutable Codex `rust-v0.163.0`, commit
`83086188ae0614bd882818ff1aa23f3194962012`; executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The work remains on the existing `main`; no branches, worktrees, live
credentials, external calls or production migration were created.

## Existing evidence audited before selecting this scope

- `apps/samgita_protocol_codex/test/schema_test.exs:155-213` locally tests false,
  null, empty optional vectors, empty strings and nested approval variants. It
  does not demonstrate native dispatch or enabled semantic results.
- `apps/samgita_codex_driver/test/turn_parameters_test.exs:54-80` covers disabled
  native negotiation for **nonempty** additional context and client metadata.
  Its tier test already covers sticky/per-turn tier inheritance and clearing.
- `native_active_turn_settings_test.exs:74-115` covers null settings on an
  already active turn, with a dynamic-tool barrier; this draft does not repeat it.
- `native_metadata_test.exs:180-242` covers metadata-update Daybreak gates and
  persistence; this draft instead tests `thread/start` input presence.
- `native_response_metadata_test.exs:260-325` already enables raw response items
  and verifies output. This draft tests raw-events input false/null/true presence
  without claiming additional raw-event output coverage.
- Existing thread-event/history tests exercise explicit ephemeral/history
  settings, but do not provide this omitted/null/configured-default comparison.

## Exact selected source contracts

Paths below are relative to the pinned `codex-rs` tree.

| Input | Omitted / null / concrete semantics | Native observation |
| --- | --- | --- |
| `thread/start.allowProviderModelFallback` and `.experimentalRawEvents` | Nonoptional Rust `bool` with serde default: omitted and `false` inactive; `null` invalid; `true` requires experimental negotiation. | Stable accepted false/omitted; local rejection sends nothing; wire bypass gets exact native gate or boolean-deserialization error; enabled true creates thread. No model fallback/raw-output behavior is inferred. |
| `thread/start.daybreakEnabled` | `Option<bool>`: omitted/null inactive and unset; both `false` and `true` active and gated. | Enabled response retains exact false/true choice. No access permission or cyber program is conferred. |
| `thread/start.dynamicTools` | Custom deserializer maps null to None, but `[]` to Some(empty); omitted/null inactive, empty vector gated. | Enabled empty vector creates thread; no tool registration/use is inferred beyond this empty-input case. |
| `thread/start.mockExperimentalField` | `Option<String>`: null inactive; even empty string is Some and gated. | Enabled empty/nonempty string creates thread. Processor intentionally ignores this test-only value; there is no product-side effect assertion. |
| `thread/start.historyMode` | Omitted/null inactive; any explicit legacy/paginated value gated. With this local state-db store, durable and ephemeral omission/null choose paginated. | Actual thread summary retains explicit/default history choice. The local store overrides the trait's legacy default; this is not a universal backend default. |
| `thread/start.ephemeral` | `Option<bool>` feeds config `unwrap_or_default`: omission/null/false create durable thread; true creates ephemeral thread. | Exact response boolean and history default. No production storage/backup claim. |
| `thread/start.serviceTier` | Double option: omitted inherits configured `flex`; explicit null becomes native `default`; explicit `default` or `flex` stays selected; unsupported string drops to null at session config. | Actual ThreadStartResponse tier and exact sent params. This is native normalization, not a driver default. No actual tier billing/enforcement is tested. |
| `turn/start.additionalContext` and `.responsesapiClientMetadata` | `Option<HashMap>`: omitted/null inactive; even `{}` is Some and gated. Enabled empty maps are accepted. | Exactly one fixed assistant-only synthetic provider request for each accepted turn; rejected gates create no provider request/turn. Existing nonempty-context tests remain separate. |

Source references:

- `app-server-protocol/src/protocol/v2/thread.rs:62-182`: all selected thread
  field types, serde defaults and experimental annotations.
- `app-server-protocol/src/protocol/v2/turn.rs:170-247`: selected optional maps.
- `codex-experimental-api-macros/src/lib.rs:256-274`: Option uses `is_some`,
  nonoptional collection uses `!is_empty`, bool uses its actual value.
- `protocol/src/dynamic_tools.rs:163-175`: null -> None; vector -> Some after
  normalization, including empty vector.
- `app-server-protocol/src/protocol/serde_helpers.rs:23-40`: double-option serde.
- `app-server/src/message_processor.rs:965-983`: native gate occurs before
  initialized-request admission/dispatch.
- `app-server/src/request_processors/thread_processor.rs:1141-1178`: test-only
  string ignored; `:1228` forwards optional ephemeral config.
- Same processor `:1359-1363`: any Daybreak choice prohibited on ephemeral
  threads; `:1464-1479` empty tools/default history; `:1588` exact Daybreak summary.
- `core/src/config/mod.rs:4085-4103`: tier double-option, `:4526` ephemeral default.
- `core/src/session/mod.rs:1190-1206`: flex retained; default/supported tiers
  permitted; unsupported tier omitted.
- `app-server/tests/suite/v2/thread_start.rs:1030-1080`: native upstream reference
  for unsupported/default tiers.
- `thread-store/src/local/mod.rs:730-732`: paginated history requires state DB.
- `core/src/session/mod.rs:825-827` falls back to the selected store when no
  history mode was requested. `thread-store/src/local/mod.rs:481-483` returns
  paginated; the trait default at `thread-store/src/store.rs:105-107` is legacy
  but is overridden by this real local store, including ephemeral threads.

## Exact candidate positive contract IDs

These nine existing IDs gain scoped `implemented` evidence, not fully verified
claims:

- `schema:v2/ThreadStartParams.json#/properties/allowProviderModelFallback`
- `schema:v2/ThreadStartParams.json#/properties/experimentalRawEvents`
- `schema:v2/ThreadStartParams.json#/properties/daybreakEnabled`
- `schema:v2/ThreadStartParams.json#/properties/dynamicTools`
- `schema:v2/ThreadStartParams.json#/properties/mockExperimentalField`
- `schema:v2/ThreadStartParams.json#/properties/historyMode`
- `schema:v2/ThreadStartParams.json#/properties/historyMode/anyOf/0`
- `schema:v2/ThreadStartParams.json#/properties/serviceTier`
- `schema:v2/ThreadStartResponse.json#/properties/serviceTier`

The existing implemented contracts for `ThreadStartParams.ephemeral`,
`TurnStartParams.additionalContext`, and
`TurnStartParams.responsesapiClientMetadata` gain differential evidence.
Explicit-null-only schema branches retain their separate evidence policy;
do not promote unrelated nested fields, full enum definitions or all request
fields from whole-map equality. Omitted members have no invented schema node.

## Files and validation boundary

Implemented profile and dependency peer:

- `scripts/codex/isolated_default_gates_fixture.py`
- `apps/samgita_codex_driver/test/native_default_gates_profile.exs`

The Python peer reuses only the retained owned UDS controller and loopback
Responses helper, replacing the provider with a fixed assistant-only response.
Shell/unified execution, hooks, Apps, plugins, remote models and request
compression are disabled. No model tool call or approval is authorized. Every
provider request needs a unique synthetic marker and is bounded to 32 requests.
The child has isolated HOME/CODEX_HOME/TMPDIR, private user/network namespaces,
only loopback and no default route in either IP family. It aborts if managed
host Codex configuration exists; this task does not mount or alter `/etc`.

The test-only recording transport transparently delegates to native UDS and
captures the exact synthetic outbound JSON bytes without normalization. All
app-server responses and notifications originate in the immutable executable.
Local schema rejection is checked separately from a `validation: :wire` native
negative. Rejected thread gates compare loaded IDs and reject started notices;
rejected turn gates verify unchanged provider-request count and no turn-start
notice. The tests do not assume a socket implies Agent health.

## Actual runs and corrected fixture assumption

In verified Devenv, from `apps/samgita_codex_driver` with `MIX_ENV=test` and the
immutable `CODEX_BINARY`:

```sh
mix compile --warnings-as-errors
mix test test/native_default_gates_profile.exs --seed 501432
mix test test/native_default_gates_profile.exs --seed 987654
mix format --check-formatted test/native_default_gates_profile.exs
```

Both final runs pass **5 tests / zero failures**, in 9.0 and 8.8 seconds. Root scoped
`mix credo apps/samgita_codex_driver/test/native_default_gates_profile.exs --strict`
passes. The native processes are reaped before scratch deletion. The initial
five-case run had **one failure**: the draft expected ephemeral omitted history
to be legacy. The actual result was paginated. Following the full source path
above proves that ephemeral omission skips the processor's explicit choice,
then core falls back to `LocalThreadStore.default_history_mode`, which returns
paginated. The generic trait's legacy default does not apply. The single
expectation was corrected to the exact stock-binary/store behavior, retaining
ephemeral/result/wire/no-inference checks. No production code or timeout changed.

Before execution, source review also replaced a file-exists startup check with
the controller's actual `ready` state; its journal exists while startup is still
in progress. This is an observable readiness barrier under the existing bound.
Initial failure log is `/tmp/samgita-default-gates-501432-20261024.log`; final
logs are `/tmp/samgita-default-gates-final-*-20261024.log`. Hosted CI selects the
profile explicitly; aggregate/hosted qualification remains a separate gate.

## Remaining scope

This five-test profile does not qualify all Rust custom deserializers, nested
experimental enum branches, optional capabilities, notification filtering,
all source-specific defaults, arbitrary dynamic tools, model fallback,
nonempty selected roots/environments, alternate stores, transports, backend
success profiles, reconnect/cancellation races, credentials or A11.
The lifecycle rows must remain incomplete even after these selected cases pass.

## New-thread personality instruction differential

One additional actual-native case compares five new ordinary threads with
configured `personality="none"`: request omission, JSON null and string `none`
produce the independent stripped catalog text; `friendly` and `pragmatic`
preserve the full literal template. The owned catalog deliberately contains an
exact `# Personality` H1, nested H2 and following `# Rules` H1. The unchanged
`{{ personality }}` literal proves no style interpolation is inferred.

Pinned `core/src/config/mod.rs:4190` uses request personality or configured
personality; `models-manager/src/model_info.rs:46-98` strips the catalog section
only for effective enum None without custom base instructions.
`prompts/src/model_instructions.rs:8-16` and
`protocol/src/openai_models.rs:545-560` render this template literally.
The test verifies the scratch config has no competing custom instruction keys,
changes only its owned catalog/config, and reuses the existing confirmed native
restart. Shared fixture source and the 32-request bound remain unchanged.

Exact outbound field presence, idle/no-inference state before each explicit
turn, the first real provider developer-message text, distinct user markers,
correlated native completion and full saved text-turn histories are asserted.
Exactly five assistant-only synthetic provider requests occur; the app-server
frames and input construction come from the immutable native executable. This
qualifies request instruction selection, not generated personality/prose quality.

The primary physical owner
`schema:v2/ThreadStartParams.json#/properties/personality`, SHA256
`788a0d55655bf7a122818c80143775b839315a3b174b12d14816ee784788f615`,
gains scoped implemented evidence only. No global enum or nullable child is
promoted. Custom-base precedence, heading edge cases, resume/fork settings and
all-source default semantics remain incomplete.

The full 15-file owning block in verified Devenv passes **91/0** twice, seeds
`501432` and `987654`, including this enlarged profile. Warning-free compile,
format, root strict Credo (431 files) and the unchanged executable-source guard
pass. Exact commands/logs are under
`/tmp/samgita-native-repair-continuation-v2-20261025/`; the read-only source
audit is `/tmp/samgita-thread-start-personality-audit-20261025.md`, SHA256
`cbb1fa41a7322a4827d320bd2262af7b6a24144012a4b640a766408489c9e590`.
Complete final-source local/hosted qualification remains a separate gate.
