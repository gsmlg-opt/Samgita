# Native import and local catalog lifecycle qualification

The later [success-only session profile](native-session-import-success-qualification.md)
adds actual native import/persistence, completed-source deduplication and cold
reads from synthetic foreign-format input, with zero inference. It does not
rerun this original mixed suite or qualify every import variant.

This unit targets immutable Codex `rust-v0.163.0`, source commit
`83086188ae0614bd882818ff1aa23f3194962012`, using the actual Linux stdio
app-server through the reusable driver. The test operates only on synthetic
files under its disposable root. It does not import or inspect the operator's
real home or any sibling repository.

## Source contract

Paths below are relative to pinned `codex-rs/`:

- `app-server-protocol/src/protocol/common.rs:904–908,1210–1216,1436–1456`
  keeps hooks and the four import methods stable, marks collaboration listing
  experimental, and serializes import mutation/history against configuration.
  `app-server-protocol/src/protocol/v2/config.rs:774–1098` distinguishes source
  selection, caller attribution, detected items, grouped progress/completion,
  flattened durable history, connectors and explicit external result recording.
- `app-server/src/external_agent_migration/processor.rs:125–265` applies source
  and session limits, rejects disabled memory import before work, sends the
  import ID response before progress and completion, and treats empty selection
  specially: it returns an ID without completion or history. `374–445` reads and
  records history; recording accepts reported facts without performing imports.
  `448–535` canonicalizes approved session roots before parsing; `548–584`
  records completed results before emitting completion. `670–712` flattens
  successes/failures while retaining each entry's identity and optional title.
- `app-server/src/external_agent_migration/protocol.rs:278–324` groups completed
  results by item type, retaining each success/failure, then sorts types in
  native-defined order. Progress remains per selected item;
  `processor.rs:238–247` emits session-validation progress before synchronous
  item progress. Progress order and completion grouping are separate contracts.
- `external-agent-migration/src/migration_source.rs:57–75` uses a
  case-insensitive Cursor selector and defaults all other values to Claude.
  The deprecated `source` field does not select migration code.
  `service.rs:193–458,553–605,681–807` preserves individual success/failure
  results, merges missing configuration, skips existing target skills and
  nonempty instructions, rewrites supported source terms and resolves HOME from
  the explicitly supplied environment. `utils.rs:44–97` rewrites SKILL.md while
  copying ordinary assets unchanged.
- `external-agent-migration/src/scope.rs:22–91` rechecks repository destination
  redirects during both detection and import; a redirected destination is
  skipped. `detect/mod.rs:39–75,193–260` defines home/repository selection and
  missing skill/command details.
- `state/src/runtime/external_agent_config_imports.rs:49–130` persists import
  records and orders reads by completion time descending, then import ID
  ascending. Caller provider identity is independent of source selection.
- `app-server/src/request_processors/catalog_processor.rs:332–345,614–688`
  lists builtin collaboration presets and resolves hooks separately for each
  requested cwd, preserving ordering and isolating configuration-load errors.
  `models-manager/src/collaboration_mode_presets.rs:6–26` defines exact Plan
  and Default metadata. `app-server-protocol/src/protocol/v2/plugin.rs:53–65,559–612`
  and `v2/hook.rs:19–66` define hook handler fields, source and trust metadata.
- Native reference journeys are in
  `app-server/tests/suite/v2/external_agent_config.rs:93–225,337–458,697–870,1218–1362`
  and `app-server/tests/suite/v2/hooks_list.rs:190–248,1114–1210`.

Existing `additional_method_families_test.exs:573–607` checks an empty hooks
list, presence of a plan preset, empty import detection and a history record
with no outcomes. Those checks do not establish the lifecycle below.

## Eight scoped cases

`apps/samgita_codex_driver/test/native_import_lifecycle_test.exs` owns:

1. Synthetic home/repository detection, home exclusion, canonical nested cwd,
   unknown/default/deprecated selector behavior, secondary-source selection and
   an actual local configuration import with independent attribution/provider.
2. Correlated instruction-import progress/completion and history, supported term
   rewriting with URL preservation, nonempty target protection, repeat import
   without overwrite and cold native history persistence.
3. Skill and command detection details, supported command conversion, rewritten
   skill instructions, unchanged binary asset copy, collision preservation,
   unsupported command exclusion, unchanged sources and post-import detection.
4. Destination revalidation after detection: an owned repository `.codex`
   directory becomes a symlink to an owned sentinel. Native import skips writes
   and records empty outcomes; the sentinel is unchanged.
5. Mixed valid instructions, an owned target configuration made invalid after
   detection and an owned session path outside the approved synthetic projects
   root. Native failure taxonomy, source/cwd metadata, successful side effects,
   progress/completion identity and persisted outcomes are separately asserted.
6. External result recording with nested successes/failures, titles, provider,
   flattened history, native order and cold persistence. Source/target metadata
   does not cause file copies or imported threads.
7. Hooks listing preserves full command metadata, duplicate/default cwd order,
   per-cwd feature exclusion and isolated malformed-config errors. The command
   is metadata only; its owned sentinel effect must remain absent.
8. Exact Plan/Default metadata, absent/false experimental rejection of
   collaboration listing, continued stable hooks/import/history APIs, empty
   import acknowledgement without fabricated completion, malformed-wire errors
   and direct rejection of disabled memory import.

## Isolation and evidence limits

The test reuses `TurnFixture`, `ModelFixture` and `StdioSessionFixture` unchanged.
Each case owns HOME, CODEX_HOME, workspace, synthetic sources/destinations,
loopback provider and pinned-native processes. All explicit source/destination
and rejected-session paths stay within the scratch root. No hook is run, no
thread turn is started and every case requires an empty Responses request
journal and ready driver without pending or uncertain requests. Cleanup is
registered immediately after each native start. Import IDs and matching native
completion notifications are distinct evidence; no sleep is used as evidence
that an asynchronous operation completed.

Validated on 2026-10-24 at repository baseline
`bc437ca91d52b19bc98e8f74f179d9e3edee296f`, with the coordinating agent's
concurrent documentation and plugin qualification changes preserved. Binary
`tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl` has SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

The initial seed 501432 run completed eight tests with two failures: the draft
incorrectly expected flattened progress to equal completion without grouping
or sorting. The raw responses and pinned source above established the native
contract. One repair added explicit assertions for individual collision progress
and session/config/instruction progress order, and reconstructed native-defined
grouped completion without dropping any outcomes. No runtime, deadline or
fixture changes were made.

After that repair, independent package compilation with warnings as errors,
formatting and both actual-native runs passed: seed 501432, eight tests with
zero failures in 4.6 seconds; seed 987654, eight tests with zero failures in
4.5 seconds. Root `MIX_ENV=test mix compile --warnings-as-errors`, the scoped
format check and strict Credo covering this unit and the plugin profile passed
(317 files, 69 checks, no issues). The plugin profile was separately rerun after
its cleanup extraction: eight tests with zero failures under each seed, in
18.0 and 17.3 seconds. These runs were serialized in the exclusive validation
slot. Import repair counters: Sol one successful round, zero unsuccessful
rounds; Astra zero.

Local evidence logs are `/tmp/samgita-native-import-initial.log`,
`/tmp/samgita-native-import-repair-1.log` and
`/tmp/samgita-import-plugin-final-validation.log`. Exact candidate manifest IDs
and schema IDs, with installed test anchors, are in
`/tmp/samgita-import-candidate-schema-pointers.json`: 70 actual-positive schema
contracts are separated from 12 native-failure-only contracts and 27
record/null/empty/rejection-only contracts. The latter groups do not qualify
missing import-success branches. All 14 method/response/notification IDs and
109 referenced schema IDs resolve in the current manifest; the coordinating
agent owns shared-ledger decisions.

Actual imported session/thread success, plugin/marketplace import success,
remote connector discovery and import, MCP startup, memory import success,
other hook handler/event/trust execution paths, non-Linux/platform/external
success profiles and A11 remain unqualified. Manually recording a session or
connector-shaped result does not qualify an actual import. These selected
local checks cannot establish full compatibility, publication or production
readiness.
