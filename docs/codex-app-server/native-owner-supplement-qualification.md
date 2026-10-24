# Supplemental native property and variant index

This source-only index binds **37 previously missing physical owners** to existing
actual-native assertions. It changes no runtime, fixture, deadline, transport or
test. Every row becomes scoped **implemented**, never fully verified. Target:
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, Linux musl
binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

Each exact manifest ID, pointer and subtree hash was checked against its owning
vendored experimental JSON file, using the inventory's canonical encoding.
Equal hashes do not transfer evidence between distinct physical responses.
The final-source hosted checkpoint is
[`0bc98a3`](repair-qualification.md#hosted-checkpoint-at-0bc98a3): both native
execution jobs pass, while mandatory completeness fails. This later index does
not retroactively change that run's manifest counts.

## Notification metadata: seven explicit-null owners

All suffixes below belong to
`schema:ServerNotification.json#/definitions/ThreadItem/oneOf/2/`.

| Suffix | Exact observed value |
| --- | --- |
| `properties/delivery` | Present null |
| `properties/delivery/anyOf/1` | Null branch |
| `properties/memoryCitation` | Present null |
| `properties/memoryCitation/anyOf/1` | Null branch |
| `properties/phase` | Present null |
| `properties/phase/anyOf/1` | Null branch |
| `properties/questions` | Present null; this property has no `anyOf/1` child |

`native_queue_image_snapshot_profile.exs:356–376` selects the actual queued
turn's sole `item/completed` AgentMessage, checks thread/turn association and
compares its entire map to independently specified text and explicit nil keys.
Equality rejects omitted keys and non-null replacements. Its model peer supplies
only assistant/output_text data; the stock binary constructs this metadata.
Driver validation does not manufacture defaults in the incoming envelope.

Both retained scoped runs pass **2/0**, seeds `501432` and `987654`:
`/tmp/samgita-native-queue-image-v4-20261024/`. Profile, peer, Session, validator,
physical schema and inventory hashes match that runner's source snapshot. The
required hosted profile also passes **2/0**. See the
[queue snapshot record](queue-image-snapshot-qualification.md).

This proves explicit null in this completed notification only. Non-null delivery,
citations, phases and questions, omission/default semantics, started messages and
selected-item response copies remain unqualified by this index.

## Configuration projection: eight selected owners

All suffixes belong to `schema:v2/ConfigReadResponse.json#/definitions/`.

| Suffix | Exact observed value |
| --- | --- |
| `AppToolApproval/enum/1` | `prompt` |
| `AppToolApproval/enum/2` | `writes` |
| `AppToolApproval/enum/3` | `approve` |
| `ToolExposureSurface/oneOf/1` | Selected deferred alternative |
| `ToolExposureSurface/oneOf/1/enum/0` | `deferred` |
| `Config/properties/web_search` | Present `disabled` |
| `Config/properties/web_search/anyOf/0` | Selected non-null reference, disabled only |
| `WebSearchMode/enum/0` | `disabled` |

`native_config_apps_projections_test.exs:129–182` prescribes TOML and compares
the complete returned apps map with independent constants using strict equality.
The actual `config/read` call is at189;190–191 preserves configuration and
requirements bytes, and193 fetches and strictly checks the web_search key.
Both scoped runs pass **4/0** in
`/tmp/samgita-native-config-apps-projections-20261024/`; seven relevant current
source hashes match its full snapshot. The complete hosted default driver also
passes at the same executable source. See the
[app projection record](config-apps-projections-qualification.md).

Policy projection does not prove enforcement, inheritance, discovery or web
search execution. Other approval modes, exposure alternatives, cached/indexed/
live modes, null and omission stay outside this evidence. The audit found **zero**
additional `PluginInstalledResponse` owners: existing subset assertions and
flattened summaries do not check its remaining rich metadata or source variants.

## Selected persisted execution: seven owners

All suffixes belong to `schema:v2/ThreadItemsReadResponse.json#/definitions/`.

| Suffix | Exact independently asserted value |
| --- | --- |
| `CommandExecutionSource/enum/2` | `unifiedExecStartup` |
| `CommandExecutionStatus/enum/1` | `completed` command |
| `McpToolCallStatus/enum/1` | `completed` MCP call |
| `ThreadItem/oneOf/6/properties/cwd/allOf/0` | Owned workspace only |
| `ThreadItem/oneOf/6/properties/source/allOf/0` | `unifiedExecStartup` only |
| `PatchChangeKind/oneOf/0` | Complete `{type: add}` object |
| `ThreadItem/oneOf/7` | Complete fixed added-file/completed object |

`native_persisted_execution_items_test.exs:94–105` independently checks the
selected command fields;136–152 compares the complete fileChange object and
physical file bytes;203–219 independently checks the completed MCP result.
The real selective reads at240 and253 each invoke those oracles at271. The cold
read uses a distinct native process, no resume and no additional model request.
The separate `thread/read` is a producer/store barrier, never the item oracle.

The earlier owning block passes **17/0** at both fixed seeds in
`/tmp/samgita-native-followup-projections-v3-20261024/`. That record preserves
test hashes and Git head `063cf65`, rather than a full dependency snapshot; it
cannot alone prove that all dependencies were clean during that run. The later
hosted `0bc98a3` complete default driver passes **366/0 + 299/0 = 665/0**, with
the unchanged owning tests and dependencies checked out at the exact commit.
Current source also passes both local full-driver seeds **665/0** in the
[terminal v15 matrix](repair-qualification.md#frozen-local-matrix-at-0bc98a3).

Only these checked fields and fixed object alternatives gain evidence. Whole
command/MCP alternatives, other enum values, unchecked nullable properties and
timestamp accuracy remain unqualified. Review profiles use `thread/turns/list`,
so contribute **zero** owners for this selective response. No assistant owner is
inferred from their full-history comparisons.

## Native goals: fifteen selected owners

The unchanged `native_goal_test.exs` has actual-native default-driver evidence at
hosted `0bc98a3` (**665/0**) and both local frozen v15 default-driver seeds
(**665/0** each). The profile, TurnFixture, Session and schema validator hashes
match v15's source snapshot. The immutable binary SHA256 above was rechecked.
This documentation-only index adds no test or runtime behavior. Both local
isolated-profile runs subsequently pass **253/0** and all 23 package commands
pass. The separate second populated aggregate retains its GitHub first-page
assertion failure; the complete combined matrix remains failed.

| Physical owner prefix | Selected suffixes and native oracle |
| --- | --- |
| `schema:ClientRequest.json#/definitions/ThreadGoalStatus/enum/` | `1` through `5`: explicit paused, blocked, usageLimited, budgetLimited and complete mutations, independent status/objective/zero-usage assertions and committed readback; no turn or model request |
| `schema:ClientRequest.json#/definitions/ThreadGoalMutationOrigin/enum/` | `0`, `1`: user and automatic origins; exact user instruction order versus absent automatic/missing/null objectives in captured model input, including cold writes before runtime load |
| `schema:ServerNotification.json#/definitions/ThreadGoal/properties/` | `createdAt`, `objective`, `status`, `threadId`, `timeUsedSeconds`, `tokenBudget`, `tokensUsed`: independently asserted first paused goal values, then exact first native update-notification equality |
| `schema:v2/ThreadGoalClearResponse.json#/properties/` | `cleared`: exact whole response true on clear, false on repeat |

The outbound status assertions are at62–68; user/automatic provenance is at
139–207, with exact downstream input assertions at191–205. First-goal values at
44–51 feed the exact owning notification check at54 and215–222. Clear responses
are checked at70–75. Ordinary schema validation remains enabled; these are the
physical ClientRequest and ServerNotification owners, with no evidence copied
to response aliases or sibling definitions. All exact subtree hashes were
independently recomputed from their vendored experimental schema nodes.

Only selected literal/field behavior gains scoped implemented evidence. Setting
usageLimited/budgetLimited does not prove computed limits; native goal complete
does not accept a Samgita Task. No active continuation, nonzero accounting,
budget enforcement, other notification statuses, outer goal-null presence,
omission/default branch, whole goal map or other transport/OS profile is
qualified. In particular the existing `updatedAt >= createdAt` term comparison
does not independently assert an integer timestamp, and bracket access to
`goal` cannot distinguish absent from present null; those owners stay missing.
See the [owning goal qualification](native-goal-qualification.md).

Regenerated ledger: **485 requirements: 0 verified / 462 implemented / 12 missing /
11 blocked; 6,621 contracts: 0 verified / 3,084 implemented / 3,537 missing**.
Complete compatibility, A11, source-unreachable emitters and external/OS success
remain incomplete. No package publication, release, migration or deployment.
