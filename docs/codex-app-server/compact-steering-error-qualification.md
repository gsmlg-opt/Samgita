# Native compact steering rejection

The driver preserves the complete real Codex RPC error when `turn/steer`
targets a running compact turn. This supplements existing implemented
`turn/steer`, RPC envelope and untyped `error.data` contracts. It promotes no
owner and does not establish an `ErrorNotification` producer.

## Real native behavior

`apps/samgita_codex_driver/test/native_compact_steering_error_test.exs` launches
the immutable Linux/musl binary directly with fixed yolo setup and the unchanged
local Responses provider `scripts/codex/compaction_control_fixture.py`, scenario
`hold`. The provider does not construct app-server notifications or RPC errors.

One seed inference completes. After `thread/compact/start`, separate provider
`compaction_held` and native `contextCompaction`/turn-start barriers establish
that the second request is genuinely running. The submission ACK alone is not
readiness. One explicitly correlated `turn/steer` then returns this whole native
error, compared against an independent literal:

```json
{
  "id": "owned-nonsteerable-compact-163",
  "error": {
    "code": -32600,
    "message": "cannot steer a compact turn",
    "data": {
      "message": "cannot steer a compact turn",
      "codexErrorInfo": {"activeTurnNotSteerable": {"turnKind": "compact"}},
      "additionalDetails": null,
      "misalignment": null
    }
  }
}
```

Rejection leaves the same compaction active, with two unchanged provider
requests and no completion. A separate explicit interruption produces exactly
one interrupted terminal. Releasing the held late output cannot add inference
or persist its checkpoint. An ordinary continuation and then a second owned
native process's cold continuation retain the accepted messages and exclude
the rejected input and cancelled checkpoint, both in requests and durable
history. The request budget is **1 → 2 → 2 → 3 → 3 → 4**. No client callback,
workspace effect, pending/uncertain operation or automatic retry occurs.

The original 20-second barrier/event bounds remain. Event count/bytes, provider
notice bytes, journal requests/bytes and native history lines/bytes are bounded.
Explicit close/reap, the retained process guardian and provider owner/completion
checks precede removal of the owned random root. Script/configuration bytes
remain unchanged. No runtime, shared fixture or cleanup implementation changes.

## Pinned producer and schema ownership

Pin: `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`; binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The official source archive SHA256 remains
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Ten complete producer files were byte-compared against that archive:

- `app-server/src/request_processors/thread_processor.rs:2461–2477` submits
  `Op::Compact` and returns an empty acknowledgement.
- `core/src/tasks/compact.rs:21–44,64–75` starts a real Compact task and selects
  remote-v2 compaction.
- `core/src/session/turn_input.rs:805–844` rejects Compact/Review steering
  before merging the submitted input.
- `app-server/src/request_processors/turn_processor.rs:1121–1183` serializes
  `TurnError` into invalid-request RPC data and returns the error.
- `app-server-protocol/src/protocol/v2/thread_data.rs:429–438` defines the four
  error fields, retaining null optional fields on serialization.
- `app-server-protocol/src/protocol/v2/shared.rs:64–67,116–120`,
  `app-server-protocol/src/rpc.rs:82–89` and `app-server/src/error_code.rs:3,16–17`
  define the exact kind, untyped data and numeric code.
- `protocol/src/protocol.rs:2005–2009` and
  `app-server/src/bespoke_event_handling.rs:1039–1040` distinguish this RPC path
  from turn-affecting error notification production.

Supplemental records are existing entries168/187/188 and owner1818
`JSONRPCErrorError.json#/properties/data`, whose literal schema node is `true`.
The request's `/oneOf/100` pointer identifies its location, while the inventory
hashes the complete `ClientRequest.json` export. Field contracts hash their
physical node. The evidence script's initial node-versus-export hash assertion
was corrected to reproduce `scripts/codex/inventory.py`; no schema was changed.

Blocked notification owners2076–2078 and queue-response owners5778–5780 remain
byte-identical. RPC data has no typed child owners for this payload. Its real
success cannot qualify those different wire locations. See
[producer limitations](native-error-producer-limitations.md).

## Verification and limits

The initial draft used reserved Elixir attribute name `@after`; parsing failed
before any native execution. Renaming it to `@continuation` preserves its value
and all assertions. The corrected owning test passes **1/0**, seed501432, in
2.2 seconds. Both logs are retained under `/tmp/samgita-v307-compact*501432.log`.

Final integrated verification is recorded with the exact commands, environment,
source guard and results under `/tmp/samgita-v307-functional-checks/`, driven by
`/tmp/samgita-v307-run.py`. The final **42-file matrix passes 80/0 twice** at
seeds501432/987654 in **144.083/136.891 seconds**. Scoped format, warnings-as-errors
compile, strict Credo on492 sources, outside actual-binary consumer **1/0**,
twenty fixture AST checks and the **283-source** unchanged-byte guard pass.
The selected files contain functional scenarios only;
prohibited security/permission/approval tests and broad/hosted workflows are not
run. Those gates are retained and incomplete.

| Evidence | SHA256 |
| --- | --- |
| New owning test | `9b82e6b7711b6ce8391cfb4b8b9227739f8b869ab0496d79d527b90ea0aabe75` |
| Results | `481fb7aa81d0a20e114bd765ab8e752f8d8bcf87b941e5d441aa9078f926bbb7` |
| Source guard | `75166f7e69471e6983c5836da3108295286b05f13148d862dc874ee7dac643f6` |
| Pinned producers and exact schema locations | `0b4ac67dd9afb17e73dc8c7cd15d32828b79f43dbd79b79124387c6ad57fedf9` |
| Resulting manifest | `8b22434b1743ab8b25f74bd0b9c6ea87e7a6c1b4d10a874e705122de2f190ab4` |

Unique whole-record patching and final binding prove that only the four named
records gain supplemental evidence; schema identities, states, counts, planned
tests and all blocked records remain unchanged. Inventory consistency passes;
strict completeness exits **1**, retaining the incomplete full goal.

This profile establishes only the literal Compact-kind RPC error and stated
Linux/stdio continuations. It does not establish arbitrary `error.data`,
Review-kind behavior, absent native notification producers, other OS/transports
or external services, A11, full compatibility, publication or deployment.
Requirements remain **462 implemented / 12 missing / 11 blocked**; contracts
remain **4,897 implemented / 1,658 missing / 66 blocked**, with zero verified.
The complete goal and release gates remain incomplete.
