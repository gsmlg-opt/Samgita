# Native dynamic-tool history

Two stock Codex `rust-v0.163.0` cases now exercise successful and failed dynamic
tool results through the existing Session, native item APIs and a cold owned
process. The source pin remains `83086188ae0614bd882818ff1aa23f3194962012`,
Linux musl binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Only the loopback model Responses provider is synthetic. Every app-server frame
and persisted item comes from that immutable executable.

`native_persisted_tool_items_test.exs:65-214` checks the exact generation-bound
tool interaction, explicit success/failure reply, user/tool/assistant ordering,
native completion fields, UTF-8 output and precisely two provider calls. Native
`thread/read` supplies the existing flush/projection barrier. Reversed, duplicate
and absent selectors in `thread/items/read` retain canonical order; ascending
and descending one-item pages have bounded, distinct continuation cursors.

The test then confirms owned-process shutdown, starts a different native PID,
and compares complete item entries and the original cursor continuation. Cold
reads do not load the thread or cause additional inference. Persisted timestamps
must exactly equal their native start/completion notifications, not merely be
nonempty. Process, provider and fixture cleanup retain their existing barriers.

The pinned production path is
`core/src/tools/handlers/dynamic.rs:219-270` and
`core/src/session/mod.rs:2709-2765`. Persistence projects **ItemCompleted** via
`app-server-protocol/src/protocol/thread_history_projection.rs:78-86` and
`protocol/v2/item.rs:948-965`; these cases do not establish persisted inProgress
items. Native read and paging behavior is in
`app-server/src/request_processors/thread_processor.rs:3622-3669` and
`thread-store/src/local/thread_history/segment_paging.rs:289-326,469-480`.

From the independent driver directory in verified Devenv, with the pinned
`CODEX_BINARY`, these two tests plus the nine provider-error tests ran at seeds
`501432` and `987654`. All eleven passed at each seed. The first invocation also
ran two new MCP drafts, which failed their own invalid MCP integer fixture; its
overall **13 tests / 2 failures** remains recorded. The separate second run was
**11/0**, 21.0s. Logs and exact commands:
`/tmp/samgita-native-followup-units-20261024/`.

Only eighteen directly asserted contracts under ThreadItemsReadResponse gain
scoped implemented evidence: nine completed dynamic-tool fields and its type
discriminator, completed/failed statuses, inputText content and its discriminator,
and entry turnId/start/completion timestamps. Null namespace is the tested
namespace value. No other ThreadItem branch, complete lifecycle, transport/OS
matrix, external provider, A11 or fully verified promotion is implied. Final
combined-source, static and hosted checks are separate required gates.
