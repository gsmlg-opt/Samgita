# Native AgentMessage history inputs

Two real pinned-native profiles capture a child's actual completion message,
import the original durable user/message maps into a cold process, and consume
them in one explicit followup. They qualify current plaintext AgentMessage
metadata handling, with a separately labeled client-null input. The model
Responses provider is local and deterministic; Codex itself creates the child,
routes its message and persists its native history.

## Genuine producer and cold consumer

`apps/samgita_codex_driver/test/native_supplied_agent_message_history_test.exs`
uses `scripts/codex/supplied_agent_message_history_fixture.py`, which imports
and delegates source replies to the existing unmodified
`test/support/native_subagent_activity_fixture.py`. Its release-child/wait
barrier produces exactly four requests: root spawn, root wait, child final and
root final. Only the new private startup configuration fixes yolo before either
process starts, so the child inherits it. A distinct followup branch alone can
consume request five. No provider code manufactures AgentMessage envelopes,
app-server notifications, rollout rows or child process state.

Native reads independently require one real child and its completed turn.
After source native close/reap, bounded inspection captures complete native
root user and received FINAL_ANSWER maps. Whole-map equality fixes the original
amsg_ ID, child/root paths, literal completion envelope, receiving source turn_id
and host-bounded actual create_time. The original user also has its native ID,
source turn/time and user.text classification. The exact metadata-free received
AgentMessage must already appear in the final original root provider request.
Communication ordering sidecars remain separate and are not imported.

A distinct cold native starts with an empty loaded list. The unchanged profile
passes these two maps intact to unstable `thread/resume.history`; the null
profile changes only AgentMessage passthrough metadata to an explicitly present
client null. Its independently specified durable expectation omits only that
key, with every other field/ID intact. It is not native-null emission.

Import creates a new idle thread/path without a turn or inference. The imported
thread has no child and is the sole loaded thread. One deliberate continuation
then consumes the entire original AgentMessage copy with only non-OpenAI
passthrough removed, preserving its ID, author, recipient and exact content.
It completes with the prescribed literal answer, without new collaboration,
client callback, child or historical message dispatch. Source counters remain
root3/child1 and only one followup observation is added. Requests stay
**4 → 4 → 5** per profile. Full imported originals, root and child source bytes,
config/catalog/scripts and empty workspace remain checked through cold close/reap.

## Physical owners and immutable source

Only these `ClientRequest.json` nodes change under
`/definitions/ResponseItem/oneOf/2/properties/internal_chat_message_metadata_passthrough`:

| Owner | Evidence |
| --- | --- |
|448|Actual native object property, supplemented by separately modified client null|
|449|Object branch with actual receiving turn_id and bounded native create_time|
|450|Explicit client-null branch, canonically omitted after native import|

No AgentMessage sibling, enclosing union, shared reference target or matching
hash receives new coverage. Pin remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Twenty-three complete upstream files again match the official source archive;
the three exact exported nodes independently match their canonical hashes:

- `core/src/agent/control/delivery.rs:27–39`, `completion.rs:93–132`,
  `session_prefix.rs:20–40` and `context/inter_agent_completion_message.rs:40–45`
  establish current plaintext delivery and its literal completion envelope.
- `protocol/src/protocol.rs:987–1020`, `core/src/hook_runtime.rs:766–769` and
  `session/mod.rs:4032–4087` construct and durably record actual AgentMessage.
- `session/mod.rs:3481–3530` and `protocol/src/models.rs:1424,1447–1490,1580–1590`
  establish generated identity and receiving turn/time metadata.
- `core/tests/suite/subagent_notifications.rs:2260–2419` supplies a current
  native plaintext producer reference; those upstream tests were read, not run.
- The pinned thread processor, rollout/history reconstruction and
  `core/src/client.rs:1006–1028,1092–1096` establish copied-prefix persistence
  and the separate provider copy that removes metadata while retaining amsg_ IDs.

## Failures, final checks and limits

The initial owning run fails **2/2** because a type-only completion selector
chooses the genuine child's answer before the root answer. The corrected helper
requires **exactly one** completion matching the target thread, turn and item
type, then checks its literal answer; it accepts neither duplicate nor unrelated
thread completions. That owning rerun passes **2/0** in4.2seconds. The first
combined attempt then fails strict Credo: captured_history complexity13/max9.
Complete user and AgentMessage oracles are extracted into separate helpers,
retaining all ordering, distinct-ID, whole-map and time assertions. No gate,
deadline or production semantics is weakened. Both failed logs remain in
`/tmp/samgita-v314-functional-checks/source-evidence-final.json` and original logs.

Final commands/environment: `/tmp/samgita-v314-final-run.py`; final artifacts:
`/tmp/samgita-v314-functional-checks/functional-final/`. The final reviewed
**45-file matrix passes89/0 twice**, seeds501432/987654, in
**179.626/159.795 seconds**. Format, warnings-as-errors compile, strict Credo
on495 sources, outside actual-binary consumer **1/0**, twenty-four fixture ASTs
and the **290-source** guard pass. Every prior287 guarded source matches
baseline `5b1a2ae5728fd03da975c578d20a8b4053223535` byte-for-byte. Guard additions
are the two new files plus the existing unchanged Python producer dependency.

| Evidence | SHA256 |
| --- | --- |
| Results | `8589e18cd7de2c268f515a92c3f238033e1e3e879fbe527ba98700877c6dd67c` |
| Source guard | `f1cc7758f7f3668d18e0d6f8200cf79e39fa6ff61c3a5dcd0d091085d4998dff` |
| Twenty-three pinned files, three nodes and correction history | `4117dff3d34cf828e9a7f466b7aaf58c460ecfcc33aac47217b10cf26a199f4b` |
| Resulting manifest | `5d70b2ca8f689262fc9d812d40988bc3aa88ac78ca3b7ea8addf6f3f162b62a0` |

Existing Session256event/8MiB defaults, local256event/1MiB capture,1MiB imported
pair,4MiB files/2048rows/262KiB lines and20s/10s/60s stage/barrier/case deadlines
remain. Explicit native executable checks, close/reap, public process guardians
and provider owner/completion/Port cleanup remain. Only owned roots are removed.

Exact binding proves three promotions with unchanged schema identities, planned
tests and requirements. Inventory consistency passes; strict completeness exits
**1**. Contracts become **4,937 implemented / 1,618 missing / 66 blocked**;
requirements stay **462 implemented / 12 missing / 11 blocked**, zero verified.
Arbitrary metadata, protected/encrypted fields, legacy emission, full original
context/collaboration restoration, external services/OS/transports, A11 and the
complete goal remain unqualified. Prohibited safety/auth/permission/approval
tests and broad/hosted workflows stay unrun. No publication or deployment.
