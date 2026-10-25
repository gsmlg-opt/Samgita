# Native MCP results and local thread-list modes

This unit qualifies three physical owners against immutable Codex
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`.
Native frames and history come from the stock executable; local Responses and
MCP fixtures supply only prescribed dependency responses. The profiles use
fixed yolo settings and require neither Samgita nor a platform database.

## MCP result

Owner2641 is the non-null `McpToolCallResult` reference in canonical
`ServerNotification.json#/definitions/ThreadItem/oneOf/8/properties/result/anyOf/0`.
The existing nine cases in `native_persisted_mcp_variants_test.exs` retain their
complete started/completed maps, literal content, structured success, tool
error, UI metadata alternatives and protocol error. Warm and first-cold
selective history preserve the results. Each case checks two actual Responses
requests, one MCP tools/call effect and confirmed native/MCP descendant cleanup.

The only setup change explicitly fixes both native launch and thread settings
to never/danger-full-access. All nine cases pass at seeds501432 and987654 with
no failed repair round. The original MCP backend is unchanged. Test SHA256 is
`5ae0117bd2f513f5443cfff3622ddbf04d8d6ba5b78ca06d62d276f4bbfcb4d3`;
backend SHA256 is
`118b6ae4898051209f9b193f417a2af2728c288368158ddb94f8fde5f33f7b47`.
Focused logs are `/tmp/samgita-v300-mcp-{501432,987654}.log`.

Adjacent owner2626, non-null `appContext`, remains missing and unchanged.
Pinned `core/src/mcp_tool_call.rs:409–434`,
`app-server-protocol/src/protocol/v2/item.rs:1048`,
`codex-mcp/src/mcp/mod.rs:348–350,438–440` and
`ext/mcp/src/lib.rs:49–65` require the Apps server managed by Codex and
backend-capable account state. An ordinary local MCP server cannot establish
this branch by adding connector metadata or changing its name. This is a
prerequisite finding, not a claim of global unreachability or an attempted
external-backend success. The account-dependent profile remains unrun under
the current verification restriction.

## List modes

`native_thread_list_modes_test.exs` qualifies canonical `v2/ThreadListParams.json`
owners5689 (`originators`) and5701 (`useStateDbOnly`). One owned native turn
creates authentic persisted history. A second cold native generation, with
the thread unloaded, receives ten captured and correlated list requests:

| Input | Independent native observation |
| --- | --- |
| `originators` omitted, null or empty | The prescribed thread remains visible with exact literal name, preview, cwd, provider and source. |
| Two different nonempty local originator lists | Exact `-32602`: `originator filtering is not supported by the local app-server`. No inferred hosted filtering success. |
| `useStateDbOnly` omitted or false | Passive inotify observes open, read and close on the authentic rollout. |
| `useStateDbOnly:true` | The same result comes from native state without observed rollout access. |

Nine observer windows use ready/arm/drain/stop barriers, bounded queues and an
empty-queue requirement. Writes, overflow, lost watches and out-of-window
access fail. There is no quiet sleep used as readiness evidence. Snapshots
occur outside observation windows. The test never edits rollout history or
SQLite, preserves original rollout/config/provider bytes, checks exactly one
inference, and confirms both native generations and the observer have exited.
Parent/project/section selectors are absent because they bypass this flag's
normal list branch.

Readiness is source-backed: `app-server/src/lib.rs:660` awaits state
initialization, `rollout/src/state_db.rs:102–127,145–167` awaits completed
backfill and `rollout/src/metadata.rs:185–390` awaits its work. The fixture
explicitly disables background paginated rollout migration and local thread
store compression before startup, excluding detached readers in
`core/src/thread_manager.rs:494–512`. Startup size metrics inspect metadata.
A successful cold DB-only query precedes watcher setup.

The first focused attempt failed because the observer's Stdio launch omitted
the required isolated `CODEX_HOME`. Supplying that existing fixture value
fixed the setup, and the owning file passed twice. The first combined check
then failed strict Credo, exit8, on nested capture code. Extracting private
`capture/3` retained every assertion, bound and operation order; the final
focused file again passes1/0 twice. Neither correction changes deadlines or
suppresses a check. Original failed evidence remains in
`/tmp/samgita-v300-list-initial-failure.log` and
`/tmp/samgita-v300-functional-checks/functional/`.

Final test SHA256:
`6c0446e4ec213d07edf1c141bd12e16233604e5569475c18c565de92469ba20f`.
Observer SHA256:
`a84b618ae0a5e76f9b43fa2359a93ce0b5c3983b173d9beb8178fb4f5aaebe45`.
Final focused logs are
`/tmp/samgita-v300-functional-checks/list-final-{501432,987654}.log`.

## Combined evidence and limits

`/tmp/samgita-v300-run-final.py` records all exact serialized commands in
`/tmp/samgita-v300-functional-checks/final-functional/results.json`.
The final reviewed40-file matrix passes **75/0 twice**, seeds501432/987654,
in131.295/126.359 seconds. Compile with warnings-as-errors, scoped format,
strict Credo on490 sources, the outside actual-binary consumer **1/0**, and
seventeen functional fixture AST checks all pass. The278-source before/after
byte guard and all eight command results match the final tested source.

| Evidence | SHA256 |
| --- | --- |
| Final results | `068e7e48f87066d318721e0a52c86a5b72d063b6962d4d491acbf04816874c24` |
| Final source guard | `cc7b3255cb6642ec76d3531da51734ccb0ba449849cb94d5fae5fd6c6f1faccf` |
| Final pinned-source evidence | `514e2a9c39c3f094485286a9b662e187146511444eab8fce3b756475df176201` |
| Resulting manifest | `e526992f6aa00d11919d1c0e4b547a2ce88e66019c5f19dd5ddd82e5d50d9d7f` |

`final-source-evidence.json` checks eighteen complete archive-matching producer
files and four exact physical nodes, including unchanged owner2626.
`manifest-binding.json` and `final-binding.json` bind only owners2641,5689,5701
to the final source. Complete-record patches use unique IDs. Inventory
consistency passes; strict completeness honestly exits **1**.

Contracts become **4,853 implemented / 1,709 missing / 59 blocked**, with
unchanged **462 implemented / 12 missing / 11 blocked** requirements and zero
verified. This is local Linux stdio functional evidence. Hosted-backend
originator filtering, Apps appContext, other transports/platforms, prohibited
checks, A11, unresolved legacy emitters, unavailable external profiles,
full-goal verification and release gates remain incomplete. No publication,
deployment or production migration occurs.
