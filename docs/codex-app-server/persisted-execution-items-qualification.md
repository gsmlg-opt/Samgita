# Direct persisted execution items

Three cases in `native_persisted_execution_items_test.exs` use the stock pinned
Codex `rust-v0.163.0` binary. Existing owned providers prescribe one fixed printf,
one fixed added-file patch or one MCP titled-enum selection. Only those local
model/MCP dependencies are synthetic; the app-server, command, patch and durable
item projection are real.

Each case explicitly answers its original generation-bound interaction and
checks independent output before reading persisted history:

- Command: exact stdout/exit/cwd/argv, with an unchanged empty workspace.
- Patch: exact added-file path/kind/diff and independently checked regular-file
  bytes, with no second file.
- MCP: exact requested schema and explicit selection, one tools/call and one
  effect journal entry, plus exact selected result in the continued model input.

`thread/read` supplies one completed-turn store barrier; it supplies no expected
item values. Direct `thread/items/read` selects the fixed original call ID and
rejects missing/wrong-turn selectors while deduplicating repeated IDs. After
confirmed owned process-group shutdown, a different native process reads the
same persisted entry without resume, hydration or another turn. Exact prescribed
fields and identity equality are checked again. Threads stay unloaded, model
requests/effects remain unchanged, and cleanup retains all existing guardians.

The first combined attempt was **17 tests / 1 failure**, because the command
draft expected source=agent. Pinned
`core/src/tools/runtimes/unified_exec/launch.rs:41-46` explicitly emits
UnifiedExecStartup, retained by
`app-server-protocol/src/protocol/v2/item.rs:920-945`; the precise
expected literal is now unifiedExecStartup. This was a test-oracle correction,
not a driver normalization or removal of the source assertion. No runtime,
deadline, capability or security guard changed.

The corrected combined block passes **17/0** at both seeds `501432` and `987654`,
with warnings-as-errors, format, strict Credo and source guards. Failure and
success logs remain respectively in
`/tmp/samgita-native-followup-projections-v2-20261024/` and `v3-20261024/`.
Other pinned producers are `app-server/src/request_processors/thread_processor.rs:3622-3677,6173-6187`,
`app-server-protocol/src/protocol/v2/item.rs:1028-1069` and
`app-server-protocol/src/protocol/item_builders.rs:342-370`.

Only selected physical ThreadItemsReadResponse fields gain scoped evidence.
Whole item alternatives, full status enums, arbitrary optional MCP result
content, time/duration accuracy, sibling schemas, other transports/OSes and
complete approval lifecycle remain unqualified. Native completion is not
Samgita Task acceptance. Full compatibility, external integration and A11 remain
incomplete.
