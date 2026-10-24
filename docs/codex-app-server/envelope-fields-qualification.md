# Native envelope and shared-field evidence

This evidence-only unit links **31 previously missing contracts** to existing
direct native assertions: 28 notification envelope contracts and three canonical
GitInfo output fields. It changes no executable, schema, runtime gate or test.
Every row remains scoped `implemented`, with **zero verified**. The complete
compatibility goal remains incomplete.

The target is stock Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux musl executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
All app-server messages in the owning tests come from that binary; fixed peers
supply model data only. Their qualification records retain the actual commands,
failed drafts, corrections and passing repeats. This audit is not a new run.

## Directly asserted envelopes

`ServerNotification.json` branches 0, 4, 5, 6, 7, 10 and 33 describe `error`,
`thread/archived`, `thread/deleted`, `thread/unarchived`, `thread/closed`,
`thread/name/updated` and `item/agentMessage/delta`. Each contributes only its
outer variant, `method` field, single method discriminator and `params` field.

- `native_provider_errors_test.exs:138-199,242-243` asserts native retry/terminal
  error maps, exact thread/turn identity, explicit recovery and provider counts.
  Its HTTP 200 SSE scenarios do not qualify HTTP 429 or all error variants.
- `native_thread_event_lifecycle_test.exs:159,206-239,410-440,488-493` selects
  the exact named notifications and checks their native transition outcomes,
  identities, parameters and five ordered UTF-8 text deltas.

For each selected branch, its `params` reference resolves to the corresponding
per-method notification schema. Comparison follows each local reference in its
own document and preserves types, defaults, requiredness, nullability, enum
alternatives, reference siblings and additional-property rules. Only export
annotations (`title`, `description`, `$schema`) and definition containers are
excluded from structural comparison. Source capability requirements still apply.
Reference equality alone qualifies no behavior or nested payload contract.

## Canonical shared GitInfo fields

The inventoried `GitInfo` definition under `ServerNotification.json` is the
canonical shared type, although the owning positive assertions use native
ThreadReadResponse and ThreadMetadataUpdateResponse. The pinned definitions have
the same complete structure. `native_metadata_test.exs:22-60,69-86` directly
asserts output `branch`, `sha` and `originUrl`, trimming, replacement, sanitization,
omission preservation, clearing and cold reads. Explicit null **member outputs**
are asserted for `sha` and `originUrl`; clearing the entire GitInfo does not
qualify a null `branch` member. No GitInfo notification producer is established.

## Audit boundary

The 31 exact IDs, subtree hashes and owning assertion ranges are recorded in the
manifest. The reviewed source-only candidate file is
`/tmp/samgita-envelope-alias-candidates-20261024.json`, SHA256
`0eda81273d186b396c78d8afc1e98ef6e34e20192e640eb1052ad87bacbf2b3a`.
All selected rows were missing with matching hashes before indexing.

Named nested definitions are already deduplicated by `inventory.py:323-349`.
Raw leaf-hash matches between unrelated strings, nulls and booleans were rejected.
The audit's 156 client-request and 85 notification reference-closure equivalences
are structural counts, not additional promotions. Uncalled methods, request-ID
alternatives, unasserted fields, experimental/default behavior, other transports,
OS/service profiles, A11 and full lifecycle requirements remain unqualified.
Final combined-source and hosted checks are separate gates. No release,
publication, deployment or production migration is claimed.

## Later client-request wrapper audit

A separate source-only audit links **48 existing positive request contracts**,
four outer rows for each method below: selected ClientRequest branch, method
property, exact discriminator and params wrapper. No new runtime test is
claimed. The owning tests and deterministic Session constructor are unchanged;
their prior native runs remain in the corresponding method qualification records.

| Method | ClientRequest branch | Owning test and positive assertions |
| --- | --- | --- |
| thread/name/set | 15 | native_thread_event_lifecycle_test.exs:152-159,172-182 |
| thread/archive | 10 | native_thread_event_lifecycle_test.exs:206-211 |
| thread/delete | 11 | native_thread_event_lifecycle_test.exs:219-227 |
| thread/unsubscribe | 12 | native_thread_event_lifecycle_test.exs:230-243 |
| thread/loaded/list | 59 | native_diagnostics_memory_test.exs:53 |
| memory/reset | 35 | native_diagnostics_memory_test.exs:88-95 |
| memory/status | 34 | native_diagnostics_memory_test.exs:146-158 |
| collaborationMode/list | 125 | native_import_lifecycle_test.exs:519-536 |
| account/read | 167 | native_account_state_test.exs:44-46,235-238,295-303 |
| account/logout | 144 | native_account_state_test.exs:52-56,295-303 |
| configRequirements/read | 166 | native_config_test.exs:217-220 |
| thread/goal/clear | 19 | native_goal_test.exs:70-75 |

Account tests directly construct native envelopes. Other outgoing evidence
combines explicit helper arguments, the unchanged constructor at
`lib/samgita_codex_driver/session.ex:404-429,588-608`, and exact successful native
results. This audit captures no outgoing bytes. Nine referenced params closures
match their per-method schemas under the normalization described above; three
literal-null wrappers retain their own positive calls. That structural check
establishes no nested payload, default, omission, gate or ID alternative.

Every exact ID/hash, owning source hash and immutable upstream declaration/
dispatch anchor is recorded in
`/tmp/samgita-client-envelope-candidates-20261024.json`, SHA256
`eb8b43260a3fe0d88f13e0c52d76a2a4f7acd5121067d7b85dd16566d995321a`.
All 48 selected rows were missing before indexing. Enabled positive memory and
collaboration profiles are used; disabled/error-only outcomes do not qualify
these wrappers. Status is scoped implemented, with **zero fully verified**.
This adds no runtime/configuration change, full-method claim, external/OS
acceptance, A11 closure or permission to publish. Final source checks remain
separate gates.
