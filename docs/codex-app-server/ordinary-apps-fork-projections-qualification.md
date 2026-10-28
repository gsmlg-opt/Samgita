# Ordinary app inputs and fixed fork projection

The target is real Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux-musl executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Both owning ordinary cases already have original-frame and independent native
effect oracles. These additive assertions retain all prior behavior, limits,
fixtures and cleanup. No production interface or shared helper changes.

## Exact app parameter slice

Only physical owners3331–3333 under `v2/AppsReadParams.json` gain evidence:

| Input | Independently observed native behavior |
| --- | --- |
| `appIds` | Nine warm/cold calls retain prescribed nonempty request order, deduplicate repeated IDs, report missing IDs and produce four exact backend batches. |
| `includeTools` | Explicit false/true values produce exact summary-hiding/promotion effects and backend bodies; richer cached metadata survives later false reads. |
| `threadId` | Explicit null only; empty loaded-thread lists before/after each process and exact native results prove the no-thread config route. |

The same original parameter map is directly validated against the exact
physical schema; its bytes are added to the test's unchanged-input snapshot.
The schema SHA256 `61e6a9d35515f3164a7f7e7a5b0c5ac92817c5a3b5d7fb27e9a704fe2935ddf7`
matches its unique official archive member. This does not qualify empty/100-limit
arrays, omitted/default booleans, non-null thread/session layers or schema aliases.

The immutable
[read handler](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/apps_processor/read.rs#L13)
deduplicates while preserving order and passes `include_tools` to connector
metadata. The
[config selection](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/apps_processor.rs#L357)
chooses latest config for the null thread. No tool execution or permission
decision is involved.

## Exact native fork result

Only owner5228, `ThreadForkResponse.multiAgentMode/allOf/0`, gains evidence.
Both the Session result and Wire-decoded original incoming reply must contain
the independent literal `explicitRequestOnly`. The genuine
[fork constructor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L5685)
assigns that value literally. It is a deprecated fixed projection, with no
claim of active delegation or another mode/default branch.

The original persistent child read/path, parent byte preservation, real local
Git facts, request→reply→notification order, frozen input/provider journals and
confirmed owner/Port/PID cleanup remain. Only the physical `allOf[0]` and its
local definition are validated; the whole response and unrelated families are
not newly tested.

The retained experimental schema SHA256
`e63cfbeb846304309c9c64fa1235abb1723f8a0abd413aef2d342598bbaf902c`
matches committed native-export provenance. The archive's default schema omits
this experimental property and differs. Its equal local mode definition is
reference-only corroboration. Initial source extraction incorrectly assumed
whole-file equality and stopped; corrected extraction preserves that distinction
and succeeds. No schema generator or synthetic app-server emitter is used.

## Review and focused evidence

Five complete official source files are bound separately for each slice. The
independent source review finds no concrete defect in either additive draft:
`/tmp/samgita-apps-fork-independent-review.md`, SHA256
`ccf1cd616c81093d8252f28e2506859c794313ecf88bbe6d089745e67ab32eb7`.

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-apps-fork-focused-20261028.py
```

The exact two owning files pass **2/0 at seeds501432 and987654**, without a
retry, timeout increase or removed assertion. Formatting passes in the verified
test environment. Logs and source-only bindings:

| Artifact | SHA256 |
| --- | --- |
| Apps input source evidence | `daf8a814fcf7c049c840983721bc09807f50a23bbc289b3f1c1a9ee804d28f88` |
| Fork result source evidence | `7f339431fadc90f61fe75bbec74dabcf70433ce35971eb2d6d03bff5bcbd7bd7` |
| Focused seed501432 log | `8ca27c95b9f1278e2ceb11c28fa526ef22140a85a46e1f5ff757e209254ed10f` |
| Focused seed987654 log | `7bcf191a8aba51d8799f6f9c2d32ae5bb98c7565199eef9825221dd82fc4b05f` |

Final combined-source qualification is recorded with the
[ordinary reconcile case](ordinary-plugin-reconcile-qualification.md#final-combined-source-functional-qualification):
all14 reviewed steps pass, including144 real-native cases twice, the three-seed
WebSocket selection, isolated consumer and static/build checks. Exactly four
physical owners from this slice move missing→implemented,
without globally verified, alias, method-family or other transport/OS credit.
Prohibited tests/audits, broad/hosted checks, A11, unavailable emitters and
external success, full compatibility and release remain incomplete.

Rollback restores these four manifest rows and removes only the additive
assertions/schema snapshots. No historical database, runtime or external state
changes occur. The known backwards-cursor defect stays outside this slice.
