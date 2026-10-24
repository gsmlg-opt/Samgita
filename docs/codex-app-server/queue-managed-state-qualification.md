# Queue-start snapshots and inert managed requirements

This unit supplies selected actual-native
implementation evidence for exactly **46 new contracts: 15 queue-start
response contracts and 31 extension/header/hook requirements contracts**.
No existing owner is recounted and no row gains fully verified status. Final
combined-source, release/CI and hosted checks remain pending.

Target: official Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux musl binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Tests ran on local baseline `1715d1c` plus the named
scoped edits; this is not a committed/final-source run.

| Exact owner | New contracts | Behavior and independent assertions |
| --- | ---: | --- |
| `native_queue_lifecycle_test.exs:219-229,250-260,398-417,541-555` | 15 | Existing selected-item cold restart and omitted-ID head restart now require the complete one-key response and nine-field Turn snapshot. Nonempty native id/root agree with later queued user-item and provider turn IDs; items are empty, itemsView is notLoaded, status is inProgress, and error/all three timing fields are explicitly null. Existing queue drain and error checks remain. |
| `native_managed_extension_hook_requirements_test.exs:82-112` | 5 | Repeated header names retain exact order, literal `ChatGPT/{{session_id}}` and Unicode values; explicit empty list, omitted extension with a present null member, restoration and owned restart differ observably. |
| Same file `114-192` | 14 | Command metadata moves from PreToolUse to PostToolUse, leaving the old event empty. Independently prescribed matcher and command fields change, persist after restart and disappear as a present null hooks member. Shared hooks/matcher/list owners are counted once. |
| Same file `195-251` | 12 | PermissionRequest retains exact MCP server/tool/nested input/timeout/status, prompt and agent discriminators, then reverses handler order, removes/restores metadata and survives restart. Shared hooks/matcher/list owners are not counted again. |

The managed read helper (`254-267`) requires unchanged owned config/source bytes,
empty loaded threads, no server request, pending work, interaction or uncertain
operation, and absent command sentinel files. Hooks, browser/computer, Apps and
plugins are explicitly disabled (`40-69`). The existing managed fixture proves
private user/mount/network namespaces, loopback-only routing, read-only managed
requirements and the pinned binary. Close confirms both owned native and
namespace-owner PIDs disappear before restart (`272-277` plus fixture close).
No new fixture, production interface, shutdown guardian or deadline is changed.

The native requirements projection reloads thread-agnostic layers on each read:
`app-server/src/config_manager_service.rs:179-192` and
`app-server/src/request_processors/config_processor.rs:133-149`. Header mapping
at `628-644` preserves the vector and exact names/values. Hook mapping at
`701-792` preserves event groups, matcher, handler order and selected metadata;
TOML `timeout` becomes API `timeoutSec`. Reading requirements invokes no hook,
MCP server, browser or model. All source paths are within the immutable pin.

The other **57 queue-start response contracts remain missing**. The sole
successful production constructor at
`app-server/src/request_processors/thread_queue_processor.rs:232-244` fixes:

```rust
items: vec![],
items_view: TurnItemsView::NotLoaded,
error: None,
status: TurnStatus::InProgress,
started_at: None,
completed_at: None,
duration_ms: None,
```

It also always supplies `root_turn_id: Some(root_turn_id)`. Earlier declined
starts return JSON-RPC errors (`208-227`), not successful Turn.error objects.
Thus 32 CodexErrorInfo, 8 TurnError, 6 MisalignmentErrorDetails, 1
MisalignmentSteer, 2 NonSteerableTurnKind, 1 nonnull error alternative, 4
summary/full itemsView alternatives and 3 terminal-status alternatives have no
producer in this response at the pin. Later completion/error notifications and
thread reads own separate schemas; a fast model race cannot rewrite this fixed
response value. Nonempty items, nonnull timing and null root ID also remain
unqualified values of their whole fields. Repeating tests/platforms or emitting
synthetic app-server frames cannot qualify these branches.

Validation ran serially from `apps/samgita_codex_driver` with `MIX_ENV=test` and
the exact binary. The exact commands were:

```sh
CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl MIX_ENV=test \
devenv shell --no-tui -- mix test test/native_queue_lifecycle_test.exs test/native_managed_extension_hook_requirements_test.exs --warnings-as-errors --seed 501432 > /tmp/samgita-native-queue-managed-501432-20261024.log 2>&1

CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl MIX_ENV=test \
devenv shell --no-tui -- mix test test/native_queue_lifecycle_test.exs test/native_managed_extension_hook_requirements_test.exs --warnings-as-errors --seed 987654 > /tmp/samgita-native-queue-managed-987654-20261024.log 2>&1
```

Both commands completed with exit 0: **11/0**, 13.4s / 13.3s (eight existing
queue cases plus three new managed cases). The second seed is terminal and
passed. Driver formatting and the root strict Credo invocation also passed;
final combined-source and hosted outcomes for the integrated source remain
**pending**.

The exact mapping is `/tmp/samgita-queue-managed-contracts-20261024.json`:
46 physical IDs, recomputed canonical node hashes, formatted test SHA256,
assertion/independent-expectation line ranges, selected behavior and limits.
Every selected row was still missing before integration. The test hashes are
`a6c009f16a247d575781e13453a26405c47a00aa53923c801284c3e34b6c02f2`
and `0fa0f20663e4878aa5c6bf4783a9f5b2e3ffe1c555d647df213332b20f7a2908`.
Log hashes are `747b2fee6c7ca8e0effe4459dfeea192e7d28d6c9e4cf65244175cfdaa5425ba`
and `c52dc8b6f2cd39a524cc61e3ac7e306f7cb823ecb86cac70e65a737ccdb03c70`.

Managed evidence is inert metadata: no hook/command execution, MCP connection,
browser header injection, template expansion, Windows execution, layer
precedence or unasserted event/handler sibling gains evidence. Queue evidence
covers the selected Linux stdio start snapshot and existing synthetic-provider
journeys. Other deployment/transport/platform and external success profiles,
whole unions, A11, full compatibility and production readiness remain
incomplete. This unit establishes no release, publication or deployment.
