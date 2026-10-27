# Generic subAgent search with two native producers

V527 continues after `23e4eeb` against stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`. It extends two existing ordinary
fixed-yolo cases. No production runtime, provider, method or migration changes.

## Positive producer and exclusion evidence

The generic `subAgent` search filter previously had only empty subtype results
and a positive VSCode OR control. Those assertions could not distinguish
absent subtypes or establish positive generic filtering. This unit uses two
genuine native producers with independently known content and provenance:

- Native task review creates a Review child. Its exact generic search must
  include that child and exclude an independently matching VSCode thread in
  the same active discovery state, in both warm and cold processes.
- The native collaboration tool creates a ThreadSpawn child with actual
  parent/depth/role/nickname provenance. Its exact generic archived search
  must return that child's independently known identity, content, snippet,
  source and canonical path, warm and cold. The earlier specialized search
  remains the first cold content query, before history hydration.

A Review-only implementation fails the ThreadSpawn positive, and a
ThreadSpawn-only implementation fails the Review positive. The Review case
supplies the matching unrelated-source exclusion. In the ThreadSpawn case,
the parent is active while the query is archived, so parent absence there
alone does not prove source exclusion. The tests do not fabricate stored
source rows or model-supply native child identities.

Eighteen complete relevant files equal the immutable official source archive.
`core/src/tasks/review.rs` and `agent/control.rs` construct the two distinct
native sources; Session/thread-store/rollout preserve them. The app-server
filter selects broad store scanning and explicitly post-filters generic
SubAgent against any native SubAgent source. The real thread search reads
stored content and reconstructs source metadata before applying that filter.
Source citations and hashes are in the evidence artifact below.

Only physical owner **6077** is eligible:
`v2/ThreadSearchParams.json#/definitions/ThreadSourceKind/enum/4`.
The authored literal is `"subAgent"`, canonical node SHA256
`bd480700782209b2a1866a02d4f46f7f0eaafc14d2d98d34745d34a43c85996a`.
The hash-pinned stock binary's documented experimental schema generator
reproduces the complete committed ThreadSearchParams export byte for byte,
SHA256 `5c3bbb9d37d7d83f3f7747423427ff9c8b0f1154ac8cd7c832995a763dfa8e61`.
This is native schema provenance, not behavior evidence by itself.

## Preserved original behavior and focused verification

The Review case retains its complete original request/response bodies and
unique correlation. It adds generic search to both existing discovery
matrices; search queries increase6 to8, while list queries stay6. Every old
source/content/ranking, cold read, persisted byte, provider-count and cleanup
assertion stays required.

The ThreadSpawn case previously lacked encoded-body capture. A test-local
wrapper delegates the same Stdio transport and records original frames with
explicit new bounds: **1,024 records**, **262,144 bytes per frame**, **8 MiB
total**. Each of the two added generic calls retains its complete original
request and reply bytes and a distinct string ID. The existing specialized
searches, independently known child-row helper, provider behavior, archive/
loaded-state/history checks, configuration snapshots, deadlines, event caps
and confirmed process cleanup remain intact. No retry is added.

Both complete owning files and reachable helper paths were independently
reviewed as ordinary fixed-yolo checks, with no security/permission/approval
test execution. The formatter adds one blank line after an Enum.filter;
ThreadSpawn stays byte-identical to its reviewed scratch draft. First focused
execution passes **2/0**, seed `501432`, in 5.4 seconds:

```sh
mix test test/native_review_source_values_test.exs test/native_subagent_search_provenance_test.exs --warnings-as-errors --seed 501432
```

| Artifact | SHA256 |
| --- | --- |
| Final Review test | `ae8c6e1273487712125346e8281073636d62899610b46900f6e4eb21c7e838ac` |
| Final ThreadSpawn test | `c6a2c6fa35b838e2a92a941675620d92caf026b22174b4a0621fd3706dea388c` |
| `/tmp/samgita-v527-source-kind-evidence.json` | `f867e5986c4afeee6987eb0750f2ea79172990ea3e89a499294efec95e898fb0` |
| `/tmp/samgita-v527-independent-review.json` | `7f8dd35943efbe9245d46112e63e2aaed18b27401b7224d12456f577e7afa73f` |
| `/tmp/samgita-v527-schema-reference.json` | `d7f0a26a6ba6d36a685a5be9fdcdc3f77c13b631bf6a8c4681e56afefec96754` |
| `/tmp/samgita-v527-focus-501432.log` | `86af9649e7a95807939a53de32cde5205d89adf9ff831a71bda383f2c41b8be6` |

Final combined-source functional results follow. Adding the
already existing ThreadSpawn file to the reviewed selection gives **69 files /
130 cases**; no test case is newly invented or removed.

## Final combined-source functional qualification

All **14 reviewed functional steps pass**:

```sh
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-v527-qualified
```

The **69-file / 130-case** actual-native selection passes at `501432` and
`987654` in 226.232 and 225.578 seconds. Three selected neutral WebSocket
cases pass at each of `455834`, `501432`, `987654` (13 other cases excluded).
The outside-umbrella actual-native consumer passes **1/0**. Driver/root
formatting, driver/umbrella warnings-as-errors compile, inventory consistency,
strict Credo, Dialyzer and assets build pass. No runtime failure or repair,
relaxed bound, skipped selected assertion or provider change occurred.

All **1,687** guarded before/after hashes are identical. Fingerprint:
`19e411c2a7795c22fbfae7423daa1cad5f392c55af500ddac277d5e7b00cc1bb`.
The final binding checks every command/result/log hash, exact reviewed changes
plus the single formatter blank line, all eighteen archive producers, schema
reference, canonical node, independent review and unchanged other source-kind
owners. All **1,683** other guarded sources remain identical to V525; every
command differs only by adding the reviewed existing ThreadSpawn file where
applicable. Only owner6077 changes from `23e4eeb`.

Final binding `/tmp/samgita-v527-final-binding.json` SHA256:
`7cc33b29d8db1f387790f0bcd4094bc818881b40fc4acb73c1dacd8146597449`.

| Final execution artifact | SHA256 |
| --- | --- |
| `/tmp/samgita-ordinary-v527-qualified/results.json` | `80826768d8a55f68b0f740fb3e72c3d849166fb3b7f6eb637367fbdab5d6f09e` |
| `/tmp/samgita-ordinary-v527-qualified/source.json` | `99ae501bc735c8c6883afb583d7ebd5488847ed7f94193454cb38a8dbe20c45c` |

Contracts: **5,499 implemented / 992 missing / 130 blocked**; requirements
**462 implemented / 12 missing / 11 blocked**; **zero verified**. Next is the
new ordinary environment-connection helper and exact native envelopes. Its
two static startup findings are corrected in scratch only; the source-proven
listener subscription permits release after thread/start without a sleep
barrier. That unrun draft is not runtime acceptance.

## Remaining prerequisites and rollback

Owners6076/6079/6081/6082 remain missing. The supplied multicall
`codex app-server` entry hardcodes VSCode as the manager source; initialize
clientInfo only sets connection metadata. It cannot manufacture AppServer.
The separate upstream app-server entry has a source selector, but a separately
published immutable executable with verified provenance is not established
here. Compact/Other lack a permitted positive producer in this bounded search;
that observation is not global source-unreachability proof. No missing owner
becomes blocked from an incomplete search, and no alias gains inferred credit.

The two observed subtypes do not establish every generic subtype, external
provider, transport/OS, schema-default or whole-method profile. Rollback
restores both original tests, the one manifest row and reviewed selection/
fingerprint. No production or historical-data rollback is needed.
Security, credential, authentication, authorization, approval and permission
tests/audits, broad suites and hosted workflows remain unrun and incomplete.
A11, unavailable emitters/external/OS, full compatibility and release gates
remain incomplete. Nothing is published or deployed.

## Current internal memory producer remains a separate source domain

V531 checks eight complete official sources and their excerpts against the
same immutable archive. Current
[`memories/write/src/runtime.rs:398`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/memories/write/src/runtime.rs#L398)
selects `SessionSource::Internal(InternalSessionSource::MemoryConsolidation)`
and a separate `ThreadSource::MemoryConsolidation`. Public source conversion
maps Internal to Unknown; it maps only actual SubAgent values to public
SubAgent. The current memory path therefore cannot establish the retained
SubAgent `memory_consolidation` literal by its name alone. No memory runtime
or synthetic public event is launched to manufacture that evidence.

The manager also excludes Internal sessions from ordinary live-thread APIs;
this source observation does not exhaust every stored/imported/backend route.
The bounded Compact constructor search remains inconclusive. Owners2405/2406/
6109/6110 remain missing; no global unreachability, blocked state, alias or
implemented credit is inferred. Source-only handoff:
`/tmp/samgita-v531-source-handoff.md`, SHA256
`ffd123562e513eab6d5dbf14c5a21427697836a99540f9f550ba2e8678306c06`;
source/schema evidence `/tmp/samgita-v531-source-evidence.json`, SHA256
`d46f62a593db45b7a59a3c5e2305fd78e2325b38520060c2e5f4999238da9208`.
