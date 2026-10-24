# Native thread settings, metadata and read-state evidence

Fifteen cases in four independent driver modules exercise stock Codex
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, Linux musl
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
They start only owned disposable processes and synthetic empty threads. Every
case requires zero model-provider requests, zero execution events and no pending
or uncertain operations. No Samgita database or running platform is needed.

## Observable contracts

| Module | Cases | Native evidence |
| --- | ---: | --- |
| `native_thread_resume_settings_test.exs` | 5 | Exact effective start/resume settings; omitted/null defaults and tier sentinel; explicit model/provider/cwd/reviewer/profile overrides; subscribed live settings take precedence; malformed requests preserve the durable parent and permit explicit recovery. |
| `native_thread_fork_settings_test.exs` | 5 | Omitted/null defaults, absent/null/explicit tiers, typed overrides, explicit rollout-path selection and malformed/permission-conflict preservation. Parent identity/history remain intact; each successful child has a distinct identity. |
| `native_read_state_fields_test.exs` | 2 | Legacy and paginated empty-thread read-state CAS, null/threadStart positions, exact conflict data, native change notifications and cold restart. Stale revisions cannot overwrite the winner; a new explicit action uses the freshly read revision. Whole history bytes remain unchanged. |
| `native_thread_response_metadata_test.exs` | 3 | Exact roots, instruction sources, read-only sandbox, plugin lists and loaded collaboration metadata. A parked instruction file proves loaded source metadata is cached. Ordinary forks and explicitly ephemeral prediction-mode forks have different plugin inheritance; neither starts work. |

The metadata tests first require the native prediction-mode rejection without
`ephemeral: true`, preserve the complete parent, then explicitly request a valid
ephemeral child with null rollout path. This does not qualify the separate
source-blocked prediction request or notification entries. Plugin IDs are inert
metadata; no plugin installation, authorization or injection effect is claimed.
Sandbox/profile values are effective metadata, not proof of OS enforcement.

Forty previously missing owning contracts gain scoped `implemented` evidence:
nine `ThreadResumeResponse` settings, five `ThreadStartResponse` settings, nine
`ThreadForkResponse` settings, nine direct resume/fork metadata properties and
eight read-state response contracts. Each row retains its pinned schema hash,
exact owning test and this evidence record. No alias, unexercised union branch,
whole method or requirement is promoted to `verified`. The unread turn-position
branch and additional settings/default/deployment variants remain missing.

## Source-grounded corrections and preserved failures

The initial twelve-case adoption run had six incorrect draft expectations:
`/tmp/samgita-native-followup-adoption-v1-20261024/`. The next eighteen-case
run had one failure because its prediction fork omitted the required ephemeral
flag: `/tmp/samgita-native-thread-adoption-v2-20261024/`. These are failed runs,
not qualification passes. Corrections follow the immutable source:

- `app-server/src/request_processors/thread_processor.rs:4165-4197` clears
  configured reasoning effort on empty cold resume unless an explicit
  model/effort override supplies it. The test now requires the exact null.
- `thread_processor.rs:4620-4637` and
  `thread-store/src/local/read_thread.rs:135-188` reconstruct legacy loaded
  full-history responses by rollout path. The SQLite-only name is null in
  that response while a normal durable read retains it. Legacy explicit-path
  forks likewise have null names; paginated path forks retain SQLite names.
- Cold empty-thread reads have explicit unloaded projections: status
  `notLoaded`, null environments, null direct-input availability and null
  model. No turn persisted a model. All other Thread fields still compare
  exactly, along with unchanged complete history bytes.
- `thread_processor.rs:5114-5117` rejects prediction-mode forks without
  `ephemeral: true`. The rejection and valid explicit prerequisite are both
  tested; no runtime implementation, timeout or validation gate was relaxed.

Settings/metadata source ownership also appears in
`app-server-protocol/src/protocol/v2/thread.rs:437-491,641-680`,
`app-server/src/request_processors/thread_lifecycle.rs:890-934` and
`core/src/codex_thread.rs:992-1003`. Tests check exact top-level values with
`Map.fetch!`, preserving missing versus null. Read-state revisions and positions
are compared separately from Thread runtime projections and task acceptance.

## Executed checks

From `apps/samgita_codex_driver`, in the verified Devenv with pinned
`CODEX_BINARY`, the final commands were:

```sh
mix test test/native_thread_resume_settings_test.exs test/native_thread_fork_settings_test.exs test/native_read_state_fields_test.exs test/native_thread_response_metadata_test.exs test/native_approval_duplicate_replies_test.exs --seed 501432
mix test test/native_thread_resume_settings_test.exs test/native_thread_fork_settings_test.exs test/native_read_state_fields_test.exs test/native_thread_response_metadata_test.exs test/native_approval_duplicate_replies_test.exs --seed 987654
```

Both passed **18 tests / zero failures**, 38.8 seconds each; three are the
separately documented [concurrent approval cases](approval-validation-qualification.md).
Changed-file formatting, warnings-as-errors compile, whole-driver format check
and root strict Credo passed. Exact commands and exit codes are in
`/tmp/samgita-native-thread-adoption-v3-20261024/results.json`; per-command logs
are alongside it. These checks follow the failed drafts above. Full default,
profile, preserved-database and hosted checks must include this final source;
earlier matrices do not qualify these additions.

Ordinary native startup uses the existing test-only plugin isolation helper;
the newly owned configurations also explicitly disable unrelated plugin/app
startup. No production defaults, live credentials, upstream source or external
repositories change. Full compatibility, A11 confidentiality, real-service/OS
success and publication remain incomplete.
