# Native thread-start reasoning effort

Two independent functional cases qualify five response/notification contracts
on immutable `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The stock Codex process owns all protocol output and constructs actual requests
to an assistant-only local synthetic model provider. This is not real external
provider acceptance or a fabricated Codex protocol server.

## Distinct frames and applied effects

Each case gets its own home, catalog, process and journal. The catalog omits a
model reasoning default. Thread creation supplies no effort override; the local
configuration either omits effort or explicitly selects low.

| Configured effort | Native start response | Independently received thread/started | Applied concise settings | Actual model request |
| --- | --- | --- | --- | --- |
| Omitted | Explicit reasoningEffort:null | Explicit nested reasoningEffort:null | effort:null | reasoning.summary:concise; effort key absent |
| low | reasoningEffort:low | Nested reasoningEffort:low | effort:low | reasoning.summary:concise and effort:low |

Exact start and turn envelopes preserve method/parameter maps and matching
response IDs within an eight-frame/4096-byte capture bound. Actual started
notifications match the returned thread ID and require the effort key to exist;
missing data cannot masquerade as null. No response is copied into a notice.
A summary-only update changes auto to concise. Its empty ACK is not the barrier:
the next turn waits for the real applied `thread/settings/updated` snapshot.

Each native turn reaches the prescribed assistant output and correlated
completion, with exactly one provider request and the independent user marker.
The model instructions, reasoning payload and key presence have independent
expectations. Configuration and workspace remain unchanged. Local collectors
retain the 5-second start/settings and 20-second turn deadlines with a 256-event
bound. Fixed experimental opt-in supports diagnostics; checked owned shutdown
confirms the selected binary PID disappears. No unrelated policy or interaction
helper is invoked.

Pinned [start processing](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L1649)
copies configured effort to the response; its
[public Thread builder](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L6610)
sets the distinct object emitted by `thread/started`. Notification construction
clears turns without replacing effort. The absent model default remains None,
and the provider serializer omits an absent effort. Seven source files match
archive bytes in `/tmp/samgita-v185-next-functional-gap/source-evidence.json`.
Implementation/source review are retained in
`/tmp/samgita-v187-thread-effort-implementation/` and
`/tmp/samgita-v189-thread-effort-review/`; the latter includes the final collector
bound and hash `ff070d72e9760a30cc08cba768fedc0d92dbf1c2c68d52da27537b11368ae7cd`.

## Exact owners and final checks

Only five physical owners become implemented:

- **2450–2452**: `ServerNotification.json#/definitions/Thread/properties/reasoningEffort`
  and its concrete/null alternatives, observed through actual `thread/started`.
- **6369–6370**: `v2/ThreadStartResponse.json#/properties/reasoningEffort/anyOf/{0,1}`.

The response parent, request inputs, other ReasoningEffort values, Thread aliases,
snapshot/result siblings and fork/resume/list/restart behavior do not inherit
evidence. Configured public effort is not a claim about every model's resolved
default or its actual reasoning. Schema IDs/hashes and requirement rows remain
unchanged. Contracts become **4,616 implemented / 1,946 missing / 59 blocked**;
requirements remain **462 implemented / 12 missing / 11 blocked**, zero verified
in both inventories.

The final eleven-file block is the ten files in
[one-shot qualification](fuzzy-search-query-qualification.md#final-checks-and-exact-owners)
plus `test/native_thread_start_effort_values_test.exs`. Both complete runs with
`--warnings-as-errors --seed 501432` and `--seed 987654` pass **24/0**, in
**41.513/41.965** command seconds. Format, warning-free compile, root strict
Credo and the **234-file** unchanged-source guard pass. No failed runtime attempt,
timeout increase or weakened assertion occurs in this unit.

Exact commands/logs/source: `/tmp/samgita-v188-thread-effort-checks/functional/`.
Results/source SHA256:
`ce22f1b39e3c14853b6007b4c1e56321ffb6d7f3038f962d78504edc7a8c1221` /
`e14d2938afebe47449755edec0695735f9a8d8732d364db04a8c1d19f3bb22f1`.
The adjacent `manifest-binding.json` binds the original/current records and final
test source. Reusable runtime sources remain unchanged; the earlier outside
consumer's **1/0** is retained rather than counted as a fresh run.

Qualification is Linux/stdio/local synthetic model only. Other transports,
backends/OS, external integration, security/permission tests, A11, broad/hosted
gates and complete compatibility remain incomplete. No publication, production
migration or deployment occurs.
