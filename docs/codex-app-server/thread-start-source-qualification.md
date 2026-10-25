# Native thread-start source and retained history

One functional scenario qualifies two request alternatives on the immutable
`rust-v0.163.0` pin, source `83086188ae0614bd882818ff1aa23f3194962012`, executable
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The stock native process creates four isolated persistent threads and performs
four explicit assistant-only turns against a local synthetic model provider.
No Samgita database, endpoint, external provider or hook is used.

## Actual provenance and independent retained records

Exact outbound start envelopes distinguish the four inputs; matching response
IDs, real `thread/started` frames and distinct persistent IDs/paths are checked.
Applied concise settings notifications precede each explicit turn. Actual model
requests contain independently prescribed initialization metadata:

| sessionStartSource input | Provider history_initialization |
| --- | --- |
| Omitted | new |
| null | new |
| startup | new |
| clear | cleared |

Each provider's thread/turn IDs match its owning native operation. Exactly one
case-specific input marker, fixed instructions and actual completed assistant
output are required, with no other case's marker carried over. Starting threads
and changing settings leave the provider journal unchanged; only the four
explicit turns add requests. Eight exact start/turn frames fill the bounded
capture; other read/diagnostic operations do not add a captured execution.

The pinned [start processor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L1514)
defaults omitted/null to Startup, selects InitialHistory::New for startup and
InitialHistory::Cleared for clear. This describes the newly created thread's
initialization provenance. It is not a command to remove an existing thread.
The history initialization serializer and Responses metadata builder produce
the observed `new/cleared` strings. Five source files match archive bytes in
`/tmp/samgita-v190-next-functional-gap/source-evidence.json`.

Public histories first pass independent turn-ID/status, ordered user/assistant
items and exact input/output assertions. Before and after each subsequent source
case, earlier histories must retain those validated turns, previews, IDs, paths
and real files. The clear-source case therefore cannot silently remove earlier
records. The process then closes with checked PID disappearance. A distinct
native process cold-reads all four histories with no loaded runtime, resume or
new turn; their exact validated turns remain. The four-request provider journal
and eight-frame capture remain byte/map-identical. No rollout-byte equality,
flush-barrier assumption, sleep or retry-until-green is used.

The test fixes historyMode to legacy solely for its owned storage fixture. It
does not qualify history-mode defaults, legacy approval emitters, hooks or any
historical Samgita executor. Existing configuration/workspace remain unchanged.
Collectors retain 5-second notice/settings and 20-second turn deadlines with a
256-event bound. Implementation/source review are retained in
`/tmp/samgita-v191-thread-source-implementation/` and
`/tmp/samgita-v193-thread-source-review/`.

## Exact owners and final evidence

Only **6350/6351** become implemented:
`v2/ThreadStartParams.json#/properties/sessionStartSource/anyOf/{0,1}`.
The parent field, ClientRequest aliases, historyMode siblings and other branches
do not inherit evidence. Schema identities/hashes and requirement rows remain
unchanged. Contracts become **4,618 implemented / 1,944 missing / 59 blocked**;
requirements stay **462 implemented / 12 missing / 11 blocked**, zero verified
in both inventories.

The final twelve-file block is the eleven files in
[effort qualification](thread-start-effort-qualification.md#exact-owners-and-final-checks)
plus `test/native_thread_start_source_values_test.exs`. Both complete runs with
`--warnings-as-errors --seed 501432` and `--seed 987654` pass **25/0**, in
**44.489/44.561** command seconds. Format, warning-free compile, root strict
Credo and the **235-file** unchanged-source guard pass. No runtime failure or
existing deadline/assertion change occurs in this unit.

Exact commands/logs/source: `/tmp/samgita-v192-thread-source-checks/functional/`.
Results/source SHA256:
`a7021eb1c6b44ca6c7815c437a6bf01981f826f89adcb4b8bf394162d74ea60b` /
`2a4263919e442cdabec63f690dcbf1f4a2e66858ef8e59a4b599e64312e4da4c`.
The adjacent `manifest-binding.json` binds original/current owners and final
formatted test SHA256
`d6232c081b10b9d75b644cd1d1a1de0bc1280bfefeec0d1a10a9914778cd0899`.
Runtime libraries/dependencies remain unchanged; the earlier outside-consumer
**1/0** is retained and not counted as a fresh run.

This is local Linux/stdio/synthetic-model evidence, not external-service or all
transport/backend/OS qualification. Security/permission tests and related broad
or hosted workflows remain unrun under the user's restriction. Full compatibility,
A11 and release gates remain incomplete. No production migration, publication
or deployment occurs.
