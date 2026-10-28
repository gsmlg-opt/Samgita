# Ordinary initialize defaults and feature negotiation

V540 uses stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
One standalone driver case exercises ordinary protocol/schema negotiation with
four explicitly owned processes and a disposable native project store. It uses
fixed YOLO, no model/tool execution and no Samgita or external project.

## Observable defaults, decoder recovery and persistence

Normal Session validation rejects `experimentalApi:null` locally, with unchanged
captured output and phase `new`. A separate deliberately malformed request uses
the existing documented `validation: :wire` option to obtain the actual native
bool-decoder error. The same connection then initializes normally with the flag
omitted. Local rejection and native rejection remain distinct evidence.

Omitted and explicit false settings both retain the ordinary connection while
the experimental project method remains unavailable. Normal validation sends
nothing; the separate wire probe receives the exact native feature-negotiation
error. This is feature/schema behavior, with no permission/authorization outcome.
Normal validation remains enabled for all successful operations.

A third process advertises true. Its initially empty project list proves the
earlier rejected requests created no durable record or reserved their shared
idempotency key. Actual native create/read/list return independent literal
name/root/metadata and bounded creation/update times. Exactly one original
timestamped `project/changed` frame reports creation. A distinct cold process
then reads/lists the exact persisted record before any new mutation. Every
connection retains an empty loaded-thread list, no turn/item/server interaction,
no uncertainty or gap, unchanged configuration/workspace and confirmed shutdown.
These definite error/response paths do not qualify ambiguous-disconnect retry.

The final inventory is **19 native request/reply pairs / 23 outgoing envelopes**:
five initialize requests including the malformed one, four initialized client
notifications, three project-create attempts, two diagnostics and the exact
read/list/control calls. All typed IDs and original encoded exchanges agree.
Only physical owner **217**, InitializeCapabilities.experimentalApi, gains scoped
implemented evidence. Lifecycle199/202 receive supplemental ordinary evidence
while remaining missing; no whole negotiation/default completion is claimed.

## Source review, corrections and bounds

Original independent review found two real draft defects before native execution:
`server/diagnostics` itself requires experimental negotiation, and every emitted
native notification includes top-level `emittedAtMs`. Both original draft and
review are preserved. The corrected draft uses the owned Stdio helper's exact
direct child for native identity; true connections independently corroborate it
with normal diagnostics. It never bypasses diagnostics availability. Removing
the two unavailable RPCs correctly changes the expected inventory from21/25 to
19/23, with no replacement calls.

The project notice retains its complete original timestamped frame. Its integer
timestamp must lie within independently sampled create-call bounds; timestamps
are not stripped or invented. Nine complete official source files and three
unchanged local transport/owner bindings support the corrected proof. The selected
boolean schema node matches the archive/manifest; whole experimental request-root
equality is not implied. Independent corrected review finds no actionable defect.

Bounds remain a 60-second case, 5-second RPC/notification deadlines, 96 captured
frames/1MiB total, 8KiB outgoing and 64KiB incoming frames, and32events/128KiB.
Identity lookup reads only the known owned helper and its singleton child with
bounded `/proc` metadata; there is no process-table scan. Every native PID,
Stdio Port and group owner is checked after confirmed close. Existing fallback
cleanup and process-owner code remain unchanged.

## Focused native evidence

The corrected test passes **1/0 at seeds501432 and987654**, 2.1 seconds in the
first run:

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-v540-focused.py
```

The recipe runs `mix test test/native_initialize_experimental_default_test.exs --warnings-as-errors --seed <seed>`
from the independent driver in the verified test environment. The final
[combined-source selection](ordinary-mcp-form-lifecycle-qualification.md#final-combined-source-functional-qualification)
passes all 14 reviewed steps, 77 files / 140 actual-native cases twice, three selected
WebSocket seeds, the outside consumer and static/build checks with 1,701 identical
guarded sources. Security/permission tests, audits and hosted checks stay unrun.

| Artifact | SHA256 |
| --- | --- |
| Original source evidence | `0d0c95fdd7b0d5a7217fadf2ddb21f6b42c0fe98977839aa3000365551b032a2` |
| Original independent review | `2fd97cc44b3bdae3f406f7553a6ef0f2b42344b1f58f37938016abbfe233379b` |
| `/tmp/samgita-v540-repair1-source-evidence.json` | `05ddf7d75b4600a8945840efa6d1459c4b227ba53a49ad11d22d1e28fb8bbc22` |
| `/tmp/samgita-v540-repair1-independent-review.json` | `e805a7b2ef476655c5928c26af8afbcbf2f06c61febea42748dbddf3b28a6813` |
| Formatted test | `8df2f53d02344debcc63926b7422ccbe4622fc7fd47f51eef617e6ac60c65d8c` |
| `/tmp/samgita-v540-focused-501432.log` | `208bd35c06554cdaf948023484d745b1faafd7c66f53dd296855de4abc6eb8ed` |
| `/tmp/samgita-v540-focused-987654.log` | `3f3cc0340423be7e9c1ff0348dd02114cf63849a3cc68d278c4371eeff6c5cbc` |

## Rollback and limits

Rollback removes this case, restores owner217 and the two lifecycle evidence
additions, and restores the reviewed selector/fingerprint. No database/platform
migration or historical data change occurs. Other extensions/fields, OS/transports,
backend success profiles and full compatibility remain unqualified. Prohibited
tests/audits and hosted workflows remain unrun; A11, unavailable emitters,
complete-goal and release gates remain open. Nothing is published or deployed.
