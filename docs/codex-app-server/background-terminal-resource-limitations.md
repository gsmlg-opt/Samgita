# Native background-terminal metrics remain null

V451 records a source-proven nonnull-production limit at `main`
`17c6109efdffcd04e33bf60f8df2e709e27eb609`. Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, cannot emit numeric osPid,
cpuPercent or rssKb through thread/backgroundTerminals/list. Existing
[null-only native evidence](background-terminal-qualification.md) remains
valid partial evidence. Only these three field contracts change from missing to
**blocked**; they do not become implemented or verified.

The immutable [API constructor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L2496)
explicitly assigns all three fields None for every listed terminal:

1. Core BackgroundTerminalInfo/list_processes provides only item_id, logical
   process_id, command and cwd. No resource measurement reaches the API mapper.
2. The sole production ThreadBackgroundTerminal constructor copies those four
   values and hardcodes os_pid/cpu_percent/rss_kb to None (lines 2508–2518).
3. Pagination clones the constructed records. The sole outer response constructor
   and typed dispatch/payload/outgoing routes retain them unchanged.
4. Derived Option serialization has no skip-None attribute on these fields.
   Nonempty responses contain explicit null; empty lists contain no item.
   Neither supplies a numeric measurement. External and in-process serialization
   cannot populate a value removed before pagination.

Whole-source references resolve to these constructors, core producers, ordinary
consumers and test-only examples. No production alternate constructor, custom
serializer or target/feature cfg changes this mapping. Busy processes, longer
polling, OS sampling, another transport, fixture PIDs and other APIs cannot
qualify an original nonnull emission in these exact response fields. Logical
processId is distinct from osPid. This construction invariant does not constitute
runtime qualification of every OS or transport.

## Bound evidence and prerequisite

Only these `schema:v2/ThreadBackgroundTerminalsListResponse.json#` fields change:

| Index | Pointer | Node SHA256 |
| --- | --- | --- |
| 5169 | `/definitions/ThreadBackgroundTerminal/properties/cpuPercent` | `34993fc9dda2f9fc8bf9053ede359d444c24f015df09769d6f12e6fa978d31ac` |
| 5172 | `/definitions/ThreadBackgroundTerminal/properties/osPid` | `80c78c2078367c04c0ef237db981a743ed785ac504a7837582217736021b046e` |
| 5174 | `/definitions/ThreadBackgroundTerminal/properties/rssKb` | `8f759d27691871647f729a7988d8638fcadd6eb4c42b76dcaadb49e493060583` |

All 5,259 Rust files match the official source archive; twelve whole files bind
the producer/serialization chain. Canonical export SHA256
`b56b1cbcb1d60079ee9f9caaeef29cad869a25b4a6d356566f7c9f672faa7bf4`
and each physical node match the generated pin. Source report
`/tmp/samgita-v451-candidate.md`, SHA256
`1959ed80a87ccbc16e5be6e0c43f1aa92bb8d2ff89eef9bd90c846e6750672b9`;
binder `/tmp/samgita-v451-bind.py`; source/node binding SHA256
`75e44966f2040ad0099ddb4b4280d399852a1e060cf1b9b9eb61c1eb7efadbb7`;
evidence SHA256
`982c3dc36f3a6d6a8b1fc4e863811b69d66f8a9bfadd391104d7f4edf816fb62`.

All 417 V450 tested sources and nine successful logs remain exact. No new
runtime/test runs. Old null-only limitations, test references and transport
evidence are retained verbatim as historical partial evidence; this source proof
supersedes their missing classification with a precise nonnull blocker. It adds
no passing-test or transport credit. The broader mixed historical profile remains
unrun under the current restriction. Inventory and diff whitespace are checked.

Contracts: **5,270 implemented / 1,271 missing / 80 blocked**; requirements
remain **462 implemented / 12 missing / 11 blocked**, zero verified in both.
The prerequisite is an upstream-supported measurement/data-to-wire path or an
explicitly accepted immutable target/contract change. No local measurement
workaround, mock emitter, upstream modification or scope waiver is supplied.
Security/permission tests and audits, broad/hosted/release and A11/legacy/external/
platform/full-goal gates remain incomplete. No publication or deployment.
Rollback reverts only these three limitation bindings and documentation;
historical evidence and runtime remain. Continue the existing fork ID evidence.
