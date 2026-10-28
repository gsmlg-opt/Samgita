# Ordinary persisted marketplace removal

V535 continues from `66775db` against stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
One new native case exercises only explicitly owned disposable local fixtures.
Production driver, schemas, platform state and historical data are unchanged.

## Native mutation and durable oracle

The test creates independent synthetic marketplace sources, base-user config
entries and installed snapshots under its temporary root. Stock Codex performs
four explicit `marketplace/remove` operations through the actual native processor
and config editor. A configured-only entry returns `installedRoot:null`; a
snapshot-only entry returns its exact removed path; a combined entry removes both
config and snapshot. After confirmed shutdown, a distinct cold native process
must leave an independent fourth entry unchanged until its explicit removal.

Exact responses, original JSONL frames, Wire/schema validation and correlation
preserve negative/positive numeric IDs and distinct Unicode strings. Persisted
config/table absence and removed snapshots are checked before and after a native
loaded-state barrier. The unrelated config prefix, retained marketplace table,
snapshot and every source directory remain exact. This verifies actual stored
effects rather than an in-memory projection. The removal source directories are
also preserved; no installation, Git clone or remote marketplace call occurs.

Warm capture bytes remain an exact prefix after cold execution. Sixteen outgoing
envelopes and fourteen unique request/reply pairs are accounted for. The provider
journal, workspace and loaded-thread lists stay empty; there is no turn/item/server
interaction or uncertain operation. Both native lifetimes and the inert dependency
require explicit owner/Port/PID completion before temporary-root cleanup.

Only physical ClientRequest owners **1448–1452** gain scoped implemented evidence:
branch70 and its id, method, method-enum and params properties. Existing standalone
parameter/response records and other aliases receive no credit. Fixed yolo setup
is retained with Apps/plugins off. No credential inspection, policy/protection-layer
outcome, approval, selector-edge or traversal probe is included. Only the existing
TurnFixture setup/model-catalog functions are invoked; its other profiles remain
outside this case.

## Immutable source and bounds

The parent independently reviewed the complete draft and verified ten complete
official source/reference files and fifteen excerpts against the pinned archive.
These trace native declaration/dispatch, actual config/snapshot removal, config
editing, installed root derivation, typed IDs and outgoing correlation. The
upstream ordinary positive reference is separate from its unselected protection
tests. All five canonical node hashes agree with the current manifest.

The experimental ClientRequest has 172 branches; the public archive export has
105. The selected experimental branch70 equals public branch36 as parsed JSON;
whole-root archive equality is explicitly false. The raw retained-file hash is
`92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352`,
distinct from its canonical JSON hash
`d3e70b7952ca9ba7f5ee9561592c8c8d7671a1749bdb764a5e22a748092cdc43`.
Both standalone MarketplaceRemove parameter/response exports are archive-byte-equal.

Bounds remain a 60-second case, 5-second RPCs, 256 events/1 MiB, 128 outgoing/768
incoming frames, 4/128 KiB per frame and 4 MiB capture total. Snapshots allow 32
entries/1 MiB per tree and 2 MiB per file. One dependency and two sequential
native processes are owned. No retry, deadline increase or assertion removal is
used. Formatting preserves the reviewed AST; the copied CaptureStdio matches
the earlier reviewed ordinary capture.

## Focused evidence

The first actual-native run passes **1/0**, seed `501432`, in 1.7 seconds:

```sh
mix test test/native_ordinary_marketplace_remove_test.exs --warnings-as-errors --seed 501432
```

| Artifact | SHA256 |
| --- | --- |
| Formatted test | `c0104f91f88a01b26ebbaebcbc50c1d3e1b50f54fccc04bbb7571d3b7f56ce11` |
| `/tmp/samgita-v535-handoff.md` | `ce94380ef6fb1f63555dcfb779ce80664686044f54e15c808f4d00a98dceb245` |
| `/tmp/samgita-v535-source-evidence.json` | `acd4ea4ed8b7d64e30e9933075aed91d9921c038b27ccaae519c69e401a93277` |
| `/tmp/samgita-v535-parent-review.json` | `ebe92bbba876473b24e7ee7d44ad0c849cf8727007a12199f79f3b8fb1817dc7` |
| `/tmp/samgita-v535-focused-501432.log` | `d1d2a25a410ecdbba7656dc359b450813d0dee42191f68a50fad5cda6e67299f` |

The [final combined-source selection](ordinary-plugin-template-metadata-qualification.md#final-combined-source-functional-qualification)
passes all **14 reviewed steps**, including **75 files / 138 actual-native cases
twice**, three selected WebSocket seeds, outside consumer **1/0**, static/build
checks and **1,698** unchanged guarded sources. The binding preserves this case's
exact formatted source and five physical promotions. This local case does not
prove complete marketplace installation/removal behavior, remote providers,
other OS/transports, platform acceptance or full compatibility.

## Rollback and remaining gates

Rollback removes this test and restores the five manifest rows and reviewed
selector/fingerprint. No database or production migration is involved. Required
security/credential/authentication/authorization/permission/sandbox/approval checks,
audits, broad suites and hosted workflows remain unrun under the user's restriction.
A11, unavailable emitters and external/platform/full-goal/release gates stay open;
zero contracts are globally verified. Nothing is published or deployed.
