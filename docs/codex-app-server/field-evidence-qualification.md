# Exact native field evidence indexing

This unit indexes previously unrecorded positive assertions in retained actual
native tests. It changes the evidence ledger, not driver behavior or upstream
schemas. All tests run against stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux musl executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The immutable executable hash and unchanged owning test hashes were checked
before/after the runs. No synthetic app-server result is counted as native
evidence; local Python peers supply only model/service dependencies.

## Indexed assertions

The manifest records each exact contract ID, source assertion ranges, exercised
values and limits. A supplied value or emitted variant qualifies only that
assertion's scope. Shared definitions are not evidence for uncalled methods or
their separate result schemas.

| Owning native test | Newly indexed contracts |
| --- | ---: |
| turn_input_test.exs | 36 |
| turn_attachment_test.exs | 18 |
| turn_parameters_test.exs | 4 |
| turn_overrides_test.exs | 16 |
| tool_output_test.exs | 9 |
| native_turn_steering_test.exs | 26 |
| native_response_metadata_test.exs | 2 |
| native_metadata_test.exs | 12 |
| native_thread_event_lifecycle_test.exs | 4 |
| native_local_history_controls_test.exs | 9 |
| thread_search_timeline_test.exs | 74 |
| native_config_test.exs | 62 |
| native_model_discovery_profile.exs | 27 |
| additional_method_families_test.exs | 21 |
| method_families_test.exs | 1 |
| native_configuration_notice_test.exs | 1 |
| Total | 322 |

Turn assertions cover selected seven-way UserInput, UTF-8 byte spans, image
detail values, context kinds, collaboration/settings and standalone/structured
tool output. Native notification content, client/item identity and explicit
raw usage nulls have direct assertions. Media preparation, synthetic encrypted
bytes and catalog modalities do not prove understanding, decryption or external
file resolution. Remote-image success and other unasserted alternatives remain
missing.

History assertions cover selected Git metadata trim/clear/sanitization, local
mode and summary persistence, search/occurrence/cursor values, fork boundaries
and timeline items/turns. Timeline contract IDs retain the official exported
snake_case names and the separately derived native camelCase mapping; no
export is changed. Sort-direction admission and consistent pagination do not
establish every precedence rule. The explicit fork boundary is the sole current
prefix, not a nonlatest-boundary fixture. Position sorting alone is excluded
because absent values could sort equally.

Configuration assertions cover exact merge/replace/delete inputs, versions,
batch persistence/reload, trusted project origins, requirements projections,
feature metadata and local plugin discovery/install. Rich/minimal model maps
establish present nullable metadata, three advertised modalities and v2; they
do not establish model execution or access-program authorization. Conditional
feature-stage checks do not promote every enum branch. Permission-profile
`allowed` is checked for truthiness only, as recorded on that row.
Accepted installAttemptId is not proof of replay/idempotency.

Null alternatives require supplied explicit null or an exact map/presence
assertion. Indexing a missing key as nil is excluded. In particular, unrelated
Turn/error, timeline error/final cursor and unused nullable branches remain
missing. ClientRequest reasoning summary values are not borrowed from fixture
configuration. No uncalled ThreadItemsReadResponse or PluginInstalledResponse
duplicate is promoted.

## Actual runs, 2026-10-24

All commands ran serially from `apps/samgita_codex_driver` in the verified
Devenv environment, with `CODEX_BINARY` pointing at the pinned executable.
Each command ran at both `--seed 501432` and `--seed 987654`:

```sh
mix test test/turn_input_test.exs test/turn_attachment_test.exs test/turn_parameters_test.exs test/turn_overrides_test.exs test/tool_output_test.exs test/native_turn_steering_test.exs test/native_response_metadata_test.exs --seed SEED
mix test test/native_metadata_test.exs test/native_thread_event_lifecycle_test.exs test/native_local_history_controls_test.exs test/thread_search_timeline_test.exs --seed SEED
mix test test/native_config_test.exs test/native_model_discovery_profile.exs test/additional_method_families_test.exs test/method_families_test.exs test/native_configuration_notice_test.exs --seed SEED
```

| Group | Seed 501432 | Seed 987654 | Logs |
| --- | --- | --- | --- |
| Turn/input/output | 48 tests / 0 failures, 38.7s | 48 / 0, 40.6s | /tmp/samgita-turn-fields-SEED-20261024.log |
| History/metadata | 29 / 0, 53.2s | 29 / 0, 52.0s | /tmp/samgita-history-fields-SEED-20261024.log |
| Configuration/discovery | 46 / 0, 41.6s | 46 / 0, 44.4s | /tmp/samgita-config-fields-SEED-20261024.log |

No test, effect assertion or deadline was changed to obtain these results.
The source audit maps had 111, 99 and 112 unique contract IDs with no mutual
overlap; every ID was still missing before its individual update. Their SHA256
values are respectively
`99e645014d5dc0bcdd3e325b1aa59ed79c5cb6b7d6c9e1806cee21ec7476c81c`,
`0842afccaaa94d36375abd40a565e7ae5a326f28fe0ca7db238b7d1cd59e92a5`
and `daf09c92e1bf977a71f36f07bceb0e614ea8dc88298f1ee67ca3cb4abefce245`.
The version-controlled manifest carries the reviewed per-ID evidence; source
audits alone did not cause promotion.

## Remaining gates

All 322 rows become scoped `implemented`, none fully `verified`.
Generated totals are **485 requirements: 460 implemented / 14 missing /
11 blocked; 6,621 contracts: 1,632 implemented / 4,989 missing; zero verified**.
Full negotiation, decision edits, field/default/retention budgets, transport/OS
and real backend profiles still require their own behavior evidence. A11,
source-unreachable legacy events, actual service integration, final aggregate
and hosted checks remain separate. No release, publication or deployment is
established by evidence indexing.
