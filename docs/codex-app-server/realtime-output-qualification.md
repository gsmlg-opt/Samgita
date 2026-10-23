# Realtime output contract correction

The immutable target remains Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`. This correction addresses a
source/export disagreement; it does **not** establish successful native realtime
backend behavior, audio delivery or a complete realtime lifecycle.

The pinned `app-server-protocol/src/protocol/v2/realtime.rs:20–49` flattens
`ThreadRealtimeItemContent` into `ThreadRealtimeItem` and applies serde
`rename_all_fields = "camelCase"`. Its `BemItemPromoted` variant therefore
serializes `turnId` and `itemId`. The same executable's experimental
`v2/ThreadRealtimeItem.ts` independently contains those names. The unchanged
official JSON exports instead require `turn_id` and `item_id` in this variant.
The discrepancy affects both typed realtime item notifications and embedded
realtime items in `thread/timeline/list`; raw `itemAdded` JSON is separate.

There is a production source path: `core/src/realtime_history.rs:306–337`
constructs the promoted item, `core/src/session/realtime_history.rs:36–52`
emits its lifecycle, and `app-server/src/bespoke_event_handling.rs:468–499`
forwards typed started/completed notifications. These are paths relative to the
matching source archive's `codex-rs/`. Source reachability is not a successful
real-backend acceptance test.

`scripts/codex/generate_output_semantics.py` derives a second, separately labeled
correction from the full pinned Rust source, executable-generated TypeScript and
four official JSON documents. Their SHA-256 identities are recorded in
`source/realtime-output-semantics.json` and package provenance. Generation fails
closed if source naming, flattening, fields, TypeScript or export structure
changes. The original stable and experimental JSON exports remain unchanged.

`Schema.Output` applies the two property/required-name replacements only to
validation contracts. Received protocol values are unchanged. Types, required
identities, integer limits, nullability, presentation unions and experimental
negotiation remain enforced. Supplemental raw-response contracts do not receive
the correction. Manifest field pointers retain their official export identities
and record the effective native names; changed effective output hashes cannot
silently inherit prior progress evidence.

Five protocol cases reproduced three failures before the correction. They then
cover both notifications, nested timeline items, all three promotion
presentations, exporter-only name rejection, missing/wrong identities, numeric
bounds, unrelated realtime variants and capability rejection. Python regressions
also mutate the pinned inputs and require explicit failure rather than accepting
missing fixtures or semantic drift. Full validation passed:

- Standalone protocol compile with warnings as errors and format check.
- `mix test --seed 501432` and `--seed 987654`: **42 tests passed each**.
- `python3 -m unittest discover -s scripts/codex -p 'test_*.py' -v`:
  **23 tests passed**.
- `python3 scripts/codex/inventory.py --check`: passed.

The first full protocol run exposed an overly broad notification correction:
supplemental raw-response documents lack `ThreadRealtimeItem`. Restricting it to
the two affected methods repaired that regression without weakening validation.
The Python check also exposed a local import missing from its CLI entry point;
that import is now explicit. Logs are
`/tmp/samgita-codex-realtime-{red,green,python}.log` and
`/tmp/samgita-codex-realtime-astra-{python,inventory,protocol-round2}.log`.
These passing contract checks do not advance realtime requirements to verified.
Final-source native history, aggregate and hosted evidence belongs in the main
[qualification record](qualification.md).
