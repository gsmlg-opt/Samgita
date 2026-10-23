# Native configuration and feature controls

Seven cases in `apps/samgita_codex_driver/test/native_config_test.exs` exercise
the immutable real Codex `rust-v0.163.0` app-server in disposable configuration
homes. Every case requires zero model requests. These are native Codex controls;
they cannot modify Samgita authorization or grant Project roles.

| Profile | Actual behavior |
| --- | --- |
| Reads and origins | Defaults omit layers. Explicit trusted project cwd selects its project layer and origins; null retains ordinary defaults. Relative `.` resolves against native process cwd. |
| Value mutations | Upsert merges an existing table; replace removes old keys. Explicit null deletes a value. Omitted/null file path and version defaults retain their native meanings. Versions and deletion survive restart. |
| Versions and atomicity | Stale single/batch versions reject without disk changes. A later invalid batch edit rolls back all earlier edits. Empty edits keep the version and exact file bytes. |
| Reload | `reloadUserConfig: true` persists a feature change and updates the existing thread's feature catalog. A fresh process observes it. This is not proof of every setting's execution-time hot reload. |
| Invalid mutations | Bad key paths/types, deprecated profile keys, read-only nonuser paths and malformed requests preserve disk state and leave the Session ready with no pending calls. |
| Requirements | Unrestricted policy returns explicit null. A forced local API-login requirement returns the native projection plus independent-speed support. No real login is performed. |
| Feature catalog and runtime state | Full pagination preserves uniqueness, metadata/nulls and stages. Zero limits clamp, invalid cursors/thread identities fail. Runtime updates filter supported keys, retain explicit false, respect disk precedence and reset on process restart without writing configuration. |

The first run passed six of seven cases. Its remaining fixture incorrectly
assumed relative cwd was rejected. Pinned `config_manager_service.rs:126` calls
`AbsolutePathBuf::try_from`, which resolves relative paths via
`utils/absolute-path/src/lib.rs:59-63,308-312`; strict rejection is a different
constructor. The corrected assertion requires identical scoped results for `.`
and the actual absolute workspace. Invalid cwd type rejection is still tested.

Seven cases then passed at seeds `501432` and `987654` with warnings-as-errors
compilation and scoped formatting. Aggregate static review found integer literal
spelling issues in the new config/MCP tests; adding numeric separators changes
no values or assertions. Strict Credo then passed **294 files with no issues**;
logs are `/tmp/samgita-codex-method-static-{check,repair}.log`. Final aggregate
and hosted execution are separate gates.

Pinned source, relative to `codex-rs/` at
`83086188ae0614bd882818ff1aa23f3194962012`:

- `app-server/src/config_manager_service.rs:119-179,195-249`: layer reads,
  requirements, writes and optimistic versions.
- `app-server/src/request_processors/config_processor.rs:104-196,247-282,359`:
  API dispatch, reload and runtime feature filtering.
- `features/src/lib.rs:1950-1953`: the actual enabled default for
  `auth_elicitation`, tested independently of explicit false overrides.

Six methods have selected local Linux/stdio implementation evidence:
`config/read`, `config/value/write`, `config/batchWrite`,
`configRequirements/read`, `experimentalFeature/list` and
`experimentalFeature/enablement/set`. Managed/enterprise requirements, actual
concurrent writers, every key and overridden-layer status, credential remapping,
execution-time enforcement and other transport/OS profiles remain incomplete.
