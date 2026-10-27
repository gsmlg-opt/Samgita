# Existing realtime assistant transcript role

V524 indexes exact physical owner **2703** after `7d8fb3b`, for stock
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`.
This is an evidence index of an unchanged real-native case, with no new
test, runtime, provider, transport, fixture, method, timeout or buffer.

## Actual producer and independent oracle

The pinned realtime v2 parser converts `response.output_text.delta/done`
backend messages into output-transcript events. The native history reducer
explicitly chooses the Assistant role, starts a typed transcript segment,
accumulates streamed text and seals the segment. The public conversion
explicitly maps core Assistant to public Assistant. Distinct native emitters
produce `thread/realtime/item/started` and `thread/realtime/item/completed`.
Nine complete producer files match the official immutable source archive.
The local backend supplies its documented backend protocol; it does not
manufacture app-server history notifications.

The existing case at
`apps/samgita_codex_driver/test/native_realtime_start_stop_test.exs:339`
independently prescribes `role: "assistant"` in both complete typed history
notification maps. It checks original received bodies through JSON and Wire,
the full aggregate schema, exact order and item/thread association, persisted
rollout and repeated same-process timeline. It distinguishes the streamed text
from the later flat completion's revised text. No cold-process read is claimed.
An additional role assertion would duplicate the complete-map oracle.

The exact physical schema path is
`ServerNotification.json#/definitions/ThreadRealtimeTranscriptRole/enum/1`.
The aggregate's started/completed branches 73/75 reference their required
item, the transcript-segment variant's required role and this enum. Canonical
node SHA256:
`b9f33d63d2896cec87523f3926ae6403081a4f8d1626635fdff5e1edce987a0b`.

The generated experimental aggregate SHA256 is
`c626079776d401d358a8791b74cfe6c978d18aabbb78477ce7bd710a79779bc1`;
the checked-in archive aggregate is
`8e719512bc26bb3871fcf7b378b79abf912d82787609c0ad418b71f179d0883f`.
These whole files differ. The exact role definition is equal; producer files
are independently archive-verified. This index does not claim whole-export
archive equality, alias equivalence or blanket schema coverage.

## Execution binding

The unchanged transcript file SHA256 is
`770f42dc299b9d30c438bd90ca78596c11352ca5c3dd72eab5a52bb5ae3ddf57`.
It ran in the passed V523 **68-file / 129-case** selection at both seeds
`501432` and `987654`. All fourteen reviewed functional steps passed; see
the [combined-source record](ordinary-local-plugin-featured-ids-qualification.md#final-combined-source-functional-qualification).
This index reuses that execution and requires identical executable/test/
schema/config/fixture sources and commands. Only the manifest metadata and
normalized runner fingerprint may differ; no new native run is claimed.

| Source/review artifact | SHA256 |
| --- | --- |
| `/tmp/samgita-v524-next-gap-evidence.json` | `0eecc3063b4c35e19cee3b6e33e9ef3d7840d0835afeb4fac2cea8690561f214` |
| `/tmp/samgita-v524-independent-source-review.json` | `d37e28ca11607d50c002c71698ae3a7145a48f53ac0fd2f90478a60553019e2f` |

Metadata fingerprint:
`b7b2bdbc4785589904c41b6fce0c72f92c909045e914d873dc5ae4a243d1f38f`.
The final metadata binding passes: **1,686** other guarded sources and the
complete fourteen-step command plan remain identical to the passed V523
execution. Every result/log hash, the original owning test, nine archive
producers and the exact schema traversal/node are bound. Fresh inventory
consistency and `git diff --check` pass. Final binding
`/tmp/samgita-v524-final-binding.json` SHA256:
`56a12250674e645340a2e531894e2f4936ba704624a67c0a1dad9e5b3a04d8c4`.

Two patch-generation attempts were rejected before any write: the first used
escaped Unicode instead of the repository JSON encoding, and the second used
numeric unified-diff headers unsupported by this patch interface. Canonical
`inventory.encode` and plain patch headers correct the tooling. No executable
source, test, result or assertion changed during this correction.

Only root owner2703 gains scoped implemented evidence for the assistant typed
output-transcript role on the owned Linux-musl/stdio profile. User roles,
flat/standalone/alias definitions, remote realtime success, cold-process
recovery, other transport/OS and whole-method acceptance receive no inferred
credit. Contracts: **5,497 implemented / 994 missing / 130 blocked**;
requirements **462 implemented / 12 missing / 11 blocked**; **zero verified**.

Rollback restores the one manifest row and runner fingerprint and removes
this index. No runtime, dependency, migration or historical data changes.
Security, credential, authentication, authorization, approval and permission
tests/audits, broad suites and hosted workflows remain unrun and incomplete.
A11, unavailable emitters/external/OS, full compatibility and release gates
stay incomplete. Nothing is published or deployed. Continue the reviewed
local workspace-search discriminator; its scratch proposal is not acceptance.
