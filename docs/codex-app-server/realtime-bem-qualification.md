# Native realtime BEM promotion and backing history

The three public BEM presentation branches now have stock-native qualification:
WholeItem from a successful registered dynamic tool, InlineMarkdown from its
exact assistant directive and InlineVisualization indices 0/1 from two unfenced
directives. Backtick/tilde-fenced directives are excluded. Both seeds pass
**3/0**, first attempts, 6.3s / 6.8s. Streaming and completed assistant content
exercise native presentation deduplication, rather than returning a scripted
app-server promotion.

Target remains official `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
This qualifies selected native behavior with synthetic local backends, not a
real model account, live provider integration or visualization rendering.

## Ownership, producers and assertions

`isolated_realtime_bem_fixture.py` composes the existing realtime peer and
Responses fixture inside a private user/network namespace. It verifies only
loopback routing, starts the pinned owned native UDS server and admits exactly
one assistant request or two dynamic-tool/continuation requests. The provider
rejects excess requests or an unexpected tool result; the realtime HTTP endpoint
continues rejecting model requests. Only fixed restart/barrier/close controls
are exposed. No shell, media fetch, account, remote MCP or external inference is
used. The existing no-inference realtime profile remains separate.

Each test explicitly starts realtime and a normal turn on one paginated root
thread. It checks the actual generation-bound dynamic-tool interaction where
applicable, full independently prescribed source items, exact native promotion
maps and fresh UUIDv7 promotion IDs. Native `turnId` and backing `itemId` must
match the separately checked ordinary items. Warm/cold `thread/items/read`
preserves every backing item. Closing a borrowed UDS session leaves its server
alive; an explicit fixture restart must reap that process before a distinct
native process reads the same complete durable timeline without loading work or
making another model request.

The whole unfiltered timeline has exactly the known realtime boundaries,
promotions, ordinary items and completed turn boundaries. Every payload is
checked. Realtime and ordinary suborders, nonnegative ordered positions and
turnStarted < item/promotion < turnCompleted are asserted independently, without
inventing an ordering between streaming promotion and backing materialization.
All native/controller/namespace PIDs disappear after the final acknowledged
graceful close and unchanged owner-death guardian cleanup.

At the immutable pin, `core/src/realtime_history/presentation.rs:28-126` selects
these producers, with distinct dynamic-tool active-session and assistant-message
conditions. `core/src/realtime_history.rs:181-199,224-234,307-337` owns the
turn/session mapping, fresh identities and `(itemId,presentation,index)`
deduplication. Raw `thread/injectItems` bypasses the ordinary producer path and
is not used. Official reducer tests at `core/src/realtime_history_tests.rs`
corroborate the rules but are source references, not executed proof here.

The official JSON exports spell BEM references `turn_id`/`item_id`; actual Rust
serde and native TypeScript use `turnId`/`itemId`. The existing pinned
`source/realtime-output-semantics.json` records this discrepancy. All 13 new
canonical owner IDs/hashes retain the official JSON spelling and their bounded
native-wire correction; no schema is rewritten to manufacture conformance.

## Exact checks and limits

The complete commands are in
`/tmp/samgita-realtime-bem-qualification-20261024.json`. From the repository root:

```sh
devenv shell -- bash -c 'cd apps/samgita_codex_driver && MIX_ENV=test mix format test/native_realtime_bem_profile.exs'
devenv shell -- bash -c 'cd apps/samgita_codex_driver && MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl mix test test/native_realtime_bem_profile.exs --include real_codex --seed 501432'
devenv shell -- bash -c 'cd apps/samgita_codex_driver && MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl mix test test/native_realtime_bem_profile.exs --include real_codex --seed 987654'
```

Both commands terminated with exit 0 and no excluded cases. Logs:
`/tmp/samgita-bem-seed{501432,987654}-first-20261024.log`. Python AST parsing
and root strict Credo passed. Fixture/test SHA256 values are
`bf098785f8950f8405a7cbd5ff64dbd1bbaa98e8ad3d4b5ade9c7ffb8ba60a13`
and `c31ff3b445c2ecfe000f9c5afb7012d257e0d00c23e72565333156d3e45e2f4d`.
The conformance workflow now requires this profile separately; hosted and final
combined-source outcomes remain pending.

Thirteen selected `ThreadTimelineListResponse` contracts gain implemented
evidence only. Image/subagent/MCP BEM producers, late-after-replacement mapping,
transcript continuation splits, every markdown/parser input and rendered
visualization behavior remain separate obligations. Equal schema hashes do not
transfer evidence to notification/shared owners. Real backend/account, other
OS/transport profiles, A11 and the complete goal remain incomplete. No package,
tag, release or deployment is produced.

## Physical notification owners

A subsequent source-only audit indexes **19 additional physical owners** from
these unchanged, already executed tests: 16 `ServerNotification` BEM/presentation
owners and three timeline presentation `type` wrappers. `assert_promotions` at
`native_realtime_bem_profile.exs:309-355` explicitly filters the actual completed
notification method and compares its entire parameters with the prescribed
thread, turn, backing item, session and presentation. Those method-specific
assertions own the notification definitions independently of timeline equality
at `358-396` and cold equality at `233-236`. Equal node hashes supply no evidence
transfer. Started-notification/standalone duplicates, whole unrelated unions and
the prior 13 timeline owners receive no new count.

Canonical hashes, exact assertion ranges, unchanged test hashes and both terminal
seed-log fingerprints are in
`/tmp/samgita-realtime-physical-owner-audit-20261024.json`, SHA256
`aff6641cd12ed8fa717bef98acfb91766fcb4894e2bdeb1bce6304c1c753ce63`.
The official snake-case BEM owners retain the existing pinned native camelCase
correction. The already indexed transcript-tail flag is not recounted. This
index adds no executable change, test run or fully verified contract; all producer,
deployment and confidentiality limitations above remain.
