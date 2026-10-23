# Existing native interaction evidence

This audit indexes actual-native assertions already present in the driver. It
changes evidence records, not executable behavior. The target remains immutable
Codex `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, with
the binary hash recorded in [qualification](qualification.md). Every claimed
app-server response, interaction and notification comes from that binary;
synthetic peers supply only model/MCP dependencies.

The twelve cited test sources are unchanged from the complete **343/0** default
driver runs and **74/0** explicit-profile runs at both seeds recorded in the
aggregate checkpoint. Their source hashes were checked during this audit. New
plugin/import/thread-event cases have separate records and supply no evidence
to this audit. The manifest contains exact field IDs, test paths, assertion line
ranges, profile names and residual limits. No entry becomes `verified` here.

## Direct assertions

Paths below are relative to `apps/samgita_codex_driver/test/`.

| Operation or notice | Actual assertions | Limits |
| --- | --- | --- |
| `thread/compact/start` | ACK, correlated contextCompaction item/turn completion and cold history in `compaction_test.exs:15-146,179-196`; interruption/retry fences in `compaction_control_test.exs:44-146`; retention/failure in `compaction_retention_test.exs:14-101` | Submission differs from completion. No inferred `thread/compacted` emission. |
| `review/start` | Exact inline custom instructions, thread/turn identity and entered/exited review items in `additional_method_families_test.exs:205-227` | Detached/Git targets and cancellation remain incomplete. Review completion does not accept a Samgita Task. |
| `thread/settings/update` and notice | Plugin omission/null/empty, tier clear and next-request effort in `additional_method_families_test.exs:250-284`; collaboration notice in `turn_overrides_test.exs:40-93`; injection effects in `plugin_selection_test.exs:93-125` | Selected settings, without complete policy or active-step switching proof. |
| `thread/inject_items` | Exact injected assistant item in the next provider request, generated ID and one request in `additional_method_families_test.exs:327-343` | Other variants, cold durability and active-turn combinations remain incomplete. |
| `thread/items/list`, `thread/items/read` | Actual first-turn history and exact selected agent-message read in `method_families_test.exs:585-628` | One page and item selector; no cursor/backwards/sort or timeline timestamp proof. |
| `currentTime/read` request/reply | Stable/experimental native requests and exact epoch converted into expected UTC model context in `server_interactions_test.exs:293-311` | One positive timestamp, without errors/extremes. |
| v2 command approval request/reply | Accept/decline/cancel/session cache and exact rule amendment in `real_session_test.exs:242-286`, `server_interactions_test.exs:181-244`, `approval_decision_variants_test.exs:43-126,217-228,275-310` | Exact rule survives restart; stale/error replies fail closed. Network amendment and arbitrary edits remain incomplete. |
| v2 file-change approval request/reply | Target absent before decision; accept/session accept applies owned patch; cancel/decline/error preserves target in `server_interactions_test.exs:140-175`, `approval_decision_variants_test.exs:128-145,217-228` | First session-approved patch only; future prompt suppression is not asserted. |
| v2 permissions request/reply | Exact write grant, default turn scope, intersection and error handling in `server_interactions_test.exs:247-289`, `approval_decision_variants_test.exs:148-228,313-337` | Grant transformation, without subsequent filesystem/network action. Strict session success remains missing. |
| MCP form elicitation request/reply | Native form/server/thread identity; accept/decline/cancel reaches owned peer; accepted content reaches peer/provider in `server_interactions_test.exs:316-350`, `mcp_mention_test.exs:78-137,199-213` | URL/verification/auth/alternate schemas and metadata edits remain incomplete. |
| Command output delta | Output before completion and exact item-filtered delta reconstruction in explicit `native_user_shell_profile.exs:103-127,576-583` | `itemId` and `delta` only; thread/turn envelope IDs are not inferred. |
| Error notice | Compaction failure identity/diagnostic, `willRetry=false`, failed turn and preserved history in `compaction_retention_test.exs:64-101` | One deterministic terminal error, not the whole taxonomy. |
| MCP startup notice | Actual starting/ready notices under startup barrier in `mcp_mention_test.exs:62-109` | Name/status only; failed/cancelled/auth/thread fields remain incomplete. |
| Item start/completion | Direct compaction/review/command/patch/MCP assertions above | Shared item shapes and approval timestamps cannot establish unrelated notices or item timeline timestamps. |

Twenty-eight entries gain scoped evidence, including **24 previously missing
entries**. **148** directly asserted positive fields gain implementation
evidence. Eight boundary-only fields retain `missing`. The audit preserves the
five blocked legacy requirements and leaves unasserted operations untouched.

## Explicit remaining gaps

`turn/settings/update` has only disabled-feature rejection and expired
`targetUnavailable` evidence in `additional_method_families_test.exs:287-324`.
Its fields and both entries remain missing; an active `applied` publication,
later-step capture and stale-target races still need actual-native evidence.

The complete approval lifecycle remains missing because all required decisions
and edits are not qualified. Selected positive v2 branches do not qualify the
legacy families. [Legacy reachability](legacy-approval-qualification.md) retains
immutable upstream evidence for their missing production emitters; scripted
contract handlers do not satisfy enabled-native acceptance.

No existing assertion in this audit proves `thread/compacted`, terminal
interaction, file-change delta/patchUpdated, plan/reasoning delta or automatic
approval-review notices. The separate [thread-event record](thread-event-lifecycle-qualification.md)
qualifies its own nine thread/stream notices. Collected envelopes without a
direct assertion are insufficient. Elicitation counters require a separate
actual-native journey.

All evidence remains scoped to the declared synthetic Linux native profiles.
Real accounts/services, other transport/OS variants, Samgita production cutover,
A11 confidentiality, package publication and complete compatibility remain
incomplete. No migration, execution policy or Task acceptance behavior changes.
