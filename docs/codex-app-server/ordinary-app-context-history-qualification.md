# Ordinary persisted Apps context

V532 continues from `34b53d6` against stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
It adds one new ordinary native case and one self-contained local dependency
fixture. Production driver/schema/platform code and historical data are unchanged.

## Real producer and independent persistence oracle

The local dependency supplies one Apps MCP descriptor, its inert inventory
metadata result and two prescribed model Responses. Stock Codex performs the
actual metadata MCP call and emits all public events, replies, item IDs,
timestamps, measured duration and durable history. No app-server frame or
rollout record is fabricated. Synthetic identity is runtime setup only.

Exact immutable sources trace configured Apps connection, listed connector
metadata, callable namespace mapping, presentation-context extraction, native
typed MCP item completion, canonical serialization and durable selective read.
The case independently prescribes the complete nonnull context, arguments,
structured/text result and final assistant message. Original JSONL/Wire/schema
checks compare exact native maps, including explicit null fields. Generated
times/duration have measured bounds; the complete canonical flat camelCase
`item_completed` must match, with secs/nanos flooring to public milliseconds.

A native metadata read supplies the persistence barrier. Warm selective reads
must return the exact completed entry once for reversed duplicate/absent IDs,
and no entry for an absent-only selection. Confirmed warm shutdown precedes a
distinct cold native process whose first content operation is the selective
read. No resume/read/turn primes it; loaded lists remain empty and rollout/
provider bytes remain unchanged. Explicit subsequent resume retains that exact
selective result and the original rollout prefix/completed event. Exactly two
model-dependency calls and one metadata MCP call occur throughout, with an
empty workspace, unchanged inputs and no server interaction/uncertainty/gap.

The original frame prefixes and twenty outgoing envelopes/eighteen distinct
request-reply IDs remain exact after cold execution and shutdown. Native and
dependency owner/PID/Port completion is required. There is no reconnect retry
or automatic new turn; this proves the selected read/resume case, not general
remote idempotency or every lifecycle.

Only physical owner **5585** gains scoped implemented evidence:
`v2/ThreadItemsReadResponse.json#/definitions/ThreadItem/oneOf/8/properties/appContext/anyOf/0`.
Its nonnull reference node SHA256 is
`eb1116157e85c6093e153f4b64842af82e7b2bebe4c31f945228de36b1f29eb8`.
The response path is data -> entry.item -> McpToolCall -> appContext. Full
actual context equality and response validation establish this branch; five
previously indexed inner properties and other references receive no new credit.

## Source, fixture boundaries and corrections

Twenty-three whole official production files and 34 excerpts match the
immutable archive. The experimental generated ThreadItemsReadResponse JSON
does not exist in that archive. Its exact package export/node is separately
hash-bound; matching official declarations and implementation are documented.
No archive JSON equality is claimed for that absent export.

The retained origin helper automatically checks credential headers and has
mixed profile dependencies. It stays byte-identical and is never imported or
run here. The new fixture is one synchronous HTTP process, with no children or
helper threads. It inspects no credential headers/files and asserts no identity,
authentication, authorization, approval, permission or sandbox outcome. Static
readOnlyHint is presentation data. Native startup uses fixed yolo. Existing
generic process owners and ordinary launch/cleanup helpers are reused; the
bounded inherited CaptureStdio module is copied exactly.

Bounds remain explicit: 60-second case, 20-second turn, 5-second RPC; capture
128 outgoing/768 incoming frames, 4/128 KiB per frame and 4 MiB total; 256
events/1 MiB and 128 rollout lines/2 MiB. The dependency permits 128 HTTP
operations, 256 journal records, 1 MiB bodies/replies/journal and 5-second socket
reads. One dependency and two sequential native executions are owned and reaped.

Two scratch findings were corrected before execution: callable namespace uses
connector_name, and canonical items are flat camelCase. These are static draft
corrections, not failed native tests. Formatter AST equality preserves the
reviewed case; Python syntax parses without import/execution. Independent
source review reports no actionable finding.

## Focused evidence

The first actual-native run passes **1/0**, seed `501432`, in 2.3 seconds:

```sh
mix test test/native_ordinary_app_context_history_test.exs --warnings-as-errors --seed 501432
```

Root strict Credo passes across **602** source files. The final combined-source
record below covers **71 files / 134 ordinary native cases**.

| Artifact | SHA256 |
| --- | --- |
| Reviewed helper | `2f25436a2b5694390d64305b9566ce3859eea5cb81f8b212c125eb05db4126e1` |
| Formatted test | `36dac33288647d98559a34ca43cea7abe026f302f578a19ec4345a0071bdf35c` |
| `/tmp/samgita-v532-handoff.md` | `eef5c03343ed46002eb9a77807aa662ff70d5ad64e45347d2e94c10fd8c437de` |
| `/tmp/samgita-v532-source-evidence.json` | `23c3f0ea329a7ef87c18cc0700c112803d11e544b9825f3cd6573fd420e44646` |
| `/tmp/samgita-v532-independent-review.json` | `cb9ada92074fb2ad249e876afc0a36818cb59a3e9cc3e862c976c9e04eafd699` |
| `/tmp/samgita-v532-focused-501432.log` | `d179d93e2d63898e9b5c31ac24f72a9b0beb6daa1586bfb94d899eba407b39b0` |
| `/tmp/samgita-v532-strict-credo.log` | `6ac1413e8506bc0ab276e76da2b17d18d5655d0415c8cda9013aa09efa9b70b6` |

## Final combined-source functional qualification

All **14 reviewed functional steps pass**:

```sh
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-v532-final
```

The **71-file / 134-case** actual-native selection passes at `501432` and
`987654` in 239.761 and 232.592 seconds. The outside-umbrella actual-native
consumer passes **1/0**. Three selected neutral WebSocket cases pass at each
of `455834`, `501432`, `987654` (13 other cases excluded). Driver/root format,
driver/umbrella warnings-as-errors compile, inventory, strict Credo, Dialyzer
and assets build pass. No runtime failure/repair or relaxed assertion occurs.

All **1,691** guarded before/after hashes match. Fingerprint:
`28afa82836f9e81ae8170e4a73524442c328293257400298aeec8ffbd62b7d57`.
The final binding checks every command/result/log, the two new files, exact
selection change, only owner5585's metadata, canonical node and 23 official
producers/34 excerpts. All **1,687** other earlier guarded files and sixteen
retained mixed/ordinary source/document inputs remain exact. The absent archive
JSON export remains explicitly distinguished from source/declaration equality.

| Final evidence | SHA256 |
| --- | --- |
| `/tmp/samgita-v532-final-binding.json` | `207e73d2bd97488f8c35f66a1022750ada6f65e3bcecf14efba28eaa42fb7515` |
| `/tmp/samgita-ordinary-v532-final/results.json` | `7553b0d0d7c442af22a049cee47c9ef8ef35687f054ce6bafb08aabe07e35a8a` |
| `/tmp/samgita-ordinary-v532-final/source.json` | `2f46a62c107e71a87693b9c5d7937881fa47d8877da1345f1066979bcc30b7d4` |

Contracts: **5,508 implemented / 983 missing / 130 blocked**; requirements:
**462 implemented / 12 missing / 11 blocked**; **zero verified**. Only the
directly observed nonnull wrapper gains scoped credit. Next: independently
review the metadata-only `app/read` draft covering seventeen precise response
nodes, then integrate and qualify it. It has no native acceptance yet.

## Rollback and remaining prerequisites

Rollback removes the two new files and restores the one metadata row and
reviewed selector/fingerprint. No database, production or history migration
occurs. Other missing selective-response statuses and encrypted ResponseItem
variants remain incomplete. Canonical projection records completed items;
a held callback alone cannot prove a durable inProgress item. That bounded
finding is not global source-unreachability evidence.

The local fixture does not qualify real Apps/backend/media/UI resource success,
other transports/OS or complete MCP lifecycles. Security/credential/
authentication/authorization/approval/permission checks and audits, broad suites
and hosted workflows remain unrun/incomplete. A11, unavailable emitters and
external/full-goal/release gates stay open. No publication or deployment occurs.
