# Actual unclassified standalone-turn error

V424 implementation starts from `main`
`ae09005088ca947f240afbec676346740bbf3eda`, after the separate V425 index unit.
Only physical owner2776 gains scoped implemented evidence:
`ServerNotification/TurnError.codexErrorInfo/anyOf/1`. A nonnull error object
with an explicit inner null is required; outer `error:null` cannot qualify it.

Pin: official `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
One new ordinary case uses direct fixed YOLO and a normal local manager. It
changes only the thread's selected execution environments, not a permission
policy. No security, permission or approval behavior is exercised or asserted.

## Genuine error, no model request or command effect

Public thread/start explicitly selects `environments:[]` with paginated history.
Exactly one public thread/shellCommand submits a harmless owned marker command.
Its original correlated RPC response must be `{}`. Subsequent original native
events must contain one matched start, one error and one failed completion in
that order. The complete independently prescribed TurnError is:

```json
{
  "message": "shell is unavailable in this session",
  "codexErrorInfo": null,
  "additionalDetails": null,
  "misalignment": null
}
```

The complete error wrapper requires the actual thread/turn, that exact error,
`willRetry:false` and a bounded native emission timestamp. Explicit key presence
and Map.fetch! enforce the inner null. Full independent started/completed Turn
maps require the actual ID/rootTurnId, empty items/notLoaded view, inProgress
then failed status, null then matching nonnull error and bounded start/end/
duration values. Current generation, notification kind, ordering, stock schema
and original pre-Session JSONL equality are checked.

There is no turn/start or model inference. The previously reviewed finite
reasoning/checklist provider is reused only as idle loopback infrastructure;
both request/SSE journals stay byte-for-byte `[]`. Configuration/catalog/script
inputs stay frozen; provider-error evidence is absent; the command marker never
exists and the workspace remains empty before/after checked shutdown. No
synthetic native message or supplied history is involved.

## Exact pinned ordinary producer

`v2/thread.rs:135–144` defines empty selected environments separately from
omitted defaults. `request_processors.rs:643–694`,
`thread_processor.rs:1212–1213,1459–1463,1525` and
`thread_manager.rs:2140–2161` preserve Some(empty), using defaults only for None.
`session/environment.rs:181–213` activates that empty selection; the global
local manager remains configured. `thread_processor.rs:2544–2593` therefore
accepts the shell RPC instead of rejecting it at the manager precheck.

`session/handlers.rs:99–132` starts a standalone UserShellCommandTask when no
turn is active. `tasks/user_shell.rs:116–141` emits start, finds no local shell
in the selected environments and calls the real error helper365–375. That
helper emits ErrorEvent with codex_error_info None. This is resource absence,
not command failure or a sandbox decision. A failing executed command would
produce a different CommandExecution path and cannot substitute.

`protocol.rs:2199–2206` lets the unclassified error affect turn status.
`bespoke_event_handling.rs:1034–1056,1623–1647` preserves None in TurnError,
stores the error and emits willRetry:false. Task completion
`user_shell.rs:83–100` and the app-server completion path1509–1537 produce a
failed turn with that same nonnull error. Actual runtime verifies this chain.

Twelve complete upstream sources match the immutable archive; the exact
canonical null node/export matches the inventory. Node SHA256:
`b7c373d0981a5441c9dd775ad89a68ba691af04e4da70eaeaacaaf54549837fb`.
`/tmp/samgita-v424-source/evidence.json` SHA256:
`f1bb330a2ae30b4b77c923983f9cd75e2b8d182eee5bf7d2ca4b578a29f2a25b`.

## Final permitted checks and remaining limits

Initial focused actual-native run passes **1/0**. Runner
`/tmp/samgita-v424-run.py` uses isolated Elixir1.18.5/OTP27.3.4.17, two schedulers,
pinned binary and cleared inherited Mix path/partition overrides. Final focused
**1/0** takes2.069 command seconds. Reviewed26-module matrix passes **44/0** at
501432/987654,73.135/73.181 seconds, without exclusions. Nine Python syntax
checks, scoped format, warning-free driver compile, root strict Credo and
inventory consistency pass. All409 guarded sources remain stable;all408 prior
source paths retain exact bytes.

Bounds remain128 combined raw frames/events,2MiB buffers,64KiB inbound/8KiB
outbound,5s startup/RPC, one shared20s active deadline and60s case. The exact
outgoing inventory is initialize,initialized,diagnostics,thread/start and
thread/shellCommand. Native/provider executable identities, owner completion,
closed Ports and vanished owned PIDs are checked before temporary deletion.
The existing process-cleanup behavior is preserved.

Final test SHA256:
`9a2a638b15eaf734ff5767294cf5520aeec10b2f9f1dfee7c88c278c4aec6176`.
Unchanged reused provider SHA256:
`d42e156eb535595d63140870db8414f9cde90298c349d378a1d413dd2c2ba5ff`.
Exact commands/logs/membership/source hashes:
`/tmp/samgita-v424-functional-checks/final/{results,source}.json`, SHA256:
`a41102495af0c1a5724434480131b562d2aaf9471a822d068f53e72fbe052afe` /
`f6286e5ef71f72002072d155e6e8248bc8d0fbedb29c4092c91db1197c3671bf`.
Binder `/tmp/samgita-v424-bind.py` validates only2776;
`/tmp/samgita-v424-binding/evidence.json` SHA256:
`076611135dcff7cd157faad4607ad8d63c7e17a01e049cfcc92f56192e08ac58`.
Adjacent error fields/envelopes were already implemented and are not counted
again. No populated misalignment/reference or other error-classification claim.

Contracts: **5,178 implemented /1,377 missing /66 blocked**. Requirements stay
**462 implemented /12 missing /11 blocked**, zero verified. No history, alias,
other environment/producer/OS/transport or external/platform success is inferred.
Prohibited security/permission tests, audits and broad/hosted workflows remain
unrun; pushes suppress CI. A11, unreachable producers and full-goal/release
gates remain incomplete. No publication or deployment. Rollback removes this
new test and one binding, preserving runtime/history. Continue the bounded
ordinary CodexErrorInfo variant audit; authentication/permission variants remain
outside the permitted checks.
