# Native idle-thread settings

Four new cases extend `native_thread_future_settings_test.exs`, preserving its
two active-turn scenarios and unchanged provider fixture. They use the existing
assistant scenario without starting any turn or model request. The target is
stock Codex `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`,
Linux musl executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

The native `{}` response acknowledges queued settings. Every dependent assertion
waits for an exact matching `thread/settings/updated` snapshot. An actual summary
change supplies the applied barrier for null or deprecated no-op probes; tests
never wait for an ignored-only notification or infer success from a sleep.
All four cases assert zero provider requests, zero server interactions, no
turn/item events and no pending/uncertain Session state throughout.

- Granular approval fields retain the supplied booleans and native false
  defaults for the two omitted optional fields. Reviewer `guardian_subagent`
  normalizes to `auto_review`; user/friendly/pragmatic settings persist.
  Invalid reviewers and incomplete granular policies preserve saved state.
- Collaboration settings override simultaneous top-level model/effort. Null
  nested instructions select the exact bundled default-mode text, checked by
  its pinned SHA256; nested null effort remains null. This is distinct from
  root nulls, which preserve the prior values.
- Deprecated proactive/custom multiAgentMode inputs are ignored; applied
  snapshots remain `explicitRequestOnly`. Accepting this field does not launch
  delegation. Seven explicit root nulls preserve the prior settings/profile.
- A test-owned named read-only permissions profile retains its id/extends.
  Applying the legacy readOnly sandbox clears named provenance while retaining
  networkAccess false. Simultaneous permissions/sandboxPolicy rejects exact
  `-32600`; wrong-typed networkAccess rejects without changing saved state.

The pinned contracts and application path are
`app-server-protocol/src/protocol/v2/thread.rs:236-324`,
`protocol/v2/shared.rs:206-262`, `protocol/src/config_types.rs:183-200`,
`app-server/src/request_processors/turn_processor.rs:406-421,820-937`,
`core/src/session/step_settings.rs:260-292`,
`core/src/session/session.rs:275-301,450-509`,
`core/src/config/resolved_permission_profile.rs:79-85` and
`app-server/src/request_processors/thread_summary.rs:175-195`.
Default instructions are exact `collaboration-mode-templates/templates/default.md`
bytes; hash `1042cc643eb0147ca1039b19287c7462ceb297502f7f310d9664ac323a12feca`.

In verified Devenv with the immutable CODEX_BINARY, all six settings cases passed
at both seeds `501432` and `987654`. The full five-module native block then
passed **25/0** twice, with exact commands/logs/exits in
`/tmp/samgita-native-followup-units-20261024/`. Strict Credo passed all 69 checks
over 364 source files before the final one-map URL expectation correction;
final aggregate checks remain required. Scoped formatting passed.

Only 47 directly submitted/asserted settings contracts gain scoped implemented
evidence. Saved reviewer/personality settings do not prove automatic reviews or
generated prose. No broader sandbox alternative, permissions escalation,
inference effect, complete default/negotiation behavior, deployment/OS profile,
A11 or fully verified promotion is implied. This remains a bounded qualification
unit inside the active full compatibility goal.

## Later exact-leaf indexing

A source-only follow-up links five additional missing contracts to these same
native assertions, without adding a runtime test. The canonical ThreadSettings
output type is owned by `ServerNotification.json`: its `effort` null branch is
directly asserted at test lines 304-305; `activePermissionProfile` null is asserted
at 458-466. The applied-snapshot helper at 479-503 supplies the native event
barrier. Root `effort: null` remains a preservation operation; only nested
collaboration reasoning effort produces the asserted null output here.

The request ReasoningSummary variants `auto`, `concise` and `detailed` are
explicitly submitted and matched in native applied output at 224-230, 374-385
and 186-192 respectively. This establishes selected saved values, not model
reasoning generation, the `none` alternative or an entire referenced schema.
Canonical ownership was checked through complete local reference semantics.
The missing ConfigLayerMetadata.version was excluded: the existing config
helper reads layers[].version, whose ConfigLayer.version is already indexed.
Identical string-node hashes cannot establish metadata-origin coverage.

Exact IDs, hashes, source mappings, assertion ranges and exclusions are in
`/tmp/samgita-config-settings-leaf-candidates-20261024.json`, SHA256
`84c8d3102911d7a5bcecfe43c22d1b343454c8a7fd5f2c6e5ecdf64cca412393`.
All five were missing before indexing. They remain scoped implemented with
zero fully verified; this is no new native run or broader lifecycle claim.
