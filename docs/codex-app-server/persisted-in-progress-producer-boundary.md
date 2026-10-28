# Persisted in-progress item producer boundary

V544 closes the current stock-producer investigation for five exact physical
owners at Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`. Their required genuine native persisted
success profile moves **missing→blocked**. These are unmet requirements, with no
native-positive test, transport or globally verified credit. The earlier
[projection investigation](native-projection-boundaries.md) remains history.

| Owner under `v2/ThreadItemsReadResponse.json` | Individually traced current producer |
| --- | --- |
| 5307 `CollabAgentToolCallStatus/enum/0` | V1 spawn/send/resume/close/wait completion is Completed/Failed. V2 public wait completes as Completed; private analytics and public SubAgentActivity are different records. |
| 5336 `CommandExecutionStatus/enum/0` | Tool and user-shell starts are InProgress. Ordinary, error and cancellation completions use terminal statuses, including the separate background watcher. |
| 5352 `DynamicToolCallStatus/enum/0` | The pending callback produces a start only; success/error/lost response/cancellation finish as Completed/Failed. |
| 5406 `McpToolCallStatus/enum/0` | Direct MCP and resource MCP separately start InProgress and finish Completed/Failed; aborted dispatch does not persist the discarded start. |
| 5421 `PatchApplyStatus/enum/0` | Only begin has no terminal status. Every completed patch carries a terminal core status; the public None→InProgress fallback supplies no completed stock producer. |

Each node is `"inProgress"`, canonical SHA256
`e1ef5dedbf5de070e6cf2f148e2d5691ff863f44d4e18533ec8b925e30e244f3`.
No hash-equal sibling or whole response inherits the classification.

## Read, completion, cancellation and historical routes

The selective handler calls the paginated `ThreadStore.list_items`, then
deserializes `thread_items.item_json` unchanged. Materialization projects
`ItemCompleted`; rollout persistence excludes `ItemStarted`. This shared fact
alone was insufficient: V544 separately follows all five completion/error/
cancellation constructors and their final public status mappings.

The principal immutable source boundaries are
[`thread_processor.rs:3622`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L3622),
[`thread_history_projection.rs:78`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/thread_history_projection.rs#L78),
[`dynamic.rs:189`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/dynamic.rs#L189)
and [`events.rs:508`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/events.rs#L508).
The evidence retains complete-file hashes and exact excerpts for the separate
MCP/resource, user-shell, collaboration V1/V2 and patch paths.

The live/legacy history builder can display InProgress begins; the selected
database read does not overlay that builder. Frozen legacy migration converts
completed legacy records only, to terminal statuses; its wildcard does not
convert begins. Legacy round-trip likewise does not create the missing ends.
ResponseItem resume input cannot supply arbitrary completed TurnItems, and the
external session importer produces Legacy message/turn data. Fork lineage
reuses existing projected rows. The generic contributor interface is expressive,
but no production contributor registration exists in this stock source.

Existing canonical ItemCompleted values **are preserved** by canonicalization
and generic storage. Authored/imported InProgress records are representable;
their readback can prove decoding/projection but not a genuine stock-generated
completion. Older or unknown provenance remains unresolved. This is not global
impossibility, a decoder rejection or authority to erase historical records.
Existing live-start and terminal-history tests keep their original scope.

## Evidence, correction and remaining prerequisite

The source investigation verifies **45 complete official files**, classifies
52 constructor-symbol hits and checks each selected physical node. CLI
presentation sinks, type definitions and pattern matches are distinguished from
canonical producers. The parent's integrated source binding rechecks these
files against the official archive without executing code or tests.

The first extraction incorrectly expected experimental
`ThreadItemsReadResponse.json` in the source archive and failed before writing
evidence. The corrected binding uses the actual Rust Read type and retained
native-generation provenance. Its retained export SHA256 is
`6fb3b1feeb9c94ff982e6b69de8d78a3881c6adbe93d9a9b504204d1dc5881d2`.
Archived List enums provide explicitly labeled reference-only corroboration,
not inherited physical-owner acceptance. No schema generator or native profile
was run for this investigation.

| Artifact | SHA256 |
| --- | --- |
| `/tmp/samgita-v544-source-evidence-final.json` | `4752fd79b9a3ed4ec846ed154d3d044aec9d5073e98cfd07b7ebe9225e47841e` |
| `/tmp/samgita-v544-source-supplement.py` | `e095dea0641a2a7e622ad038f5d58f811c475e279454f880915197f3f693af23` |
| Parent integrated source binding | `ffa306ec7abc0fa79a60373c61a21e59bbee3528b4f8be6b933c8e65a7444685` |

Closure requires an independently supported genuine producer/provenance and
matching native evidence, or an explicit target/evidence-contract decision.
Hand-written rollouts, scripted app-server peers and live start notifications
cannot close this required profile. All five remain incomplete. No security or
permission-related test/audit, runtime, database write or external repository
change occurs. Rollback restores exactly these five state/annotation rows;
historical data and runtime behavior are untouched.
