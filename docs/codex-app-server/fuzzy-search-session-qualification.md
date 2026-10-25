# Native fuzzy-search session values

One functional scenario qualifies selected session request and notification
fields on immutable `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
All protocol responses and notifications come from that stock executable.
Two files in owned temporary roots provide the independent search oracle; the
loopback model journal remains empty. No Samgita database or endpoint runs.

## Functional effects and synchronization

Two opaque Unicode session IDs initially bind to two roots and one root,
respectively. Actual update notifications match both the requested session ID and
distinct query string. Exact result counts and prescribed root/path pairs prove
multi-root search, case-insensitive matching, empty-query clearing and control
session isolation. File type, basename, positive native score and character-index
reconstruction are checked without imposing unsupported cross-root rank order.

Starting the first ID again with only the second root changes its result set:
the fresh `NEEDLE` query returns just the second file, while the control continues
to return its first file. Stopping that first ID yields the exact native
missing-session error on update; the control still answers another fresh query.
Repeated stop returns `{}`. Captured envelopes prove **3 starts, 8 updates and
3 stops**, including the matching response/error IDs, within a 64-frame/4096-byte
capture bound. Search files and configuration remain unchanged, loaded threads
remain empty, and the native session stays ready without uncertainty or a gap.
Checked owned shutdown confirms its native PID disappears.

The initial `sessionCompleted` payload is exactly `{sessionId:<requested ID>}`.
It denotes scanner idle, without a query or generation. The implementation emits
updated/completed notifications from separately spawned tasks. A completion is
not a query or replacement fence; the independently prescribed updated data is
the effect oracle. Stop does not promise that already spawned notices disappear.
The test uses observable notifications and the retained 10-second deadline,
with a bounded 256-event collector. No sleeps, quiet-window substitute, timeout
increase, fake native messages or discarded retained assertion is introduced.

Pinned [declarations](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/common.rs#L1903)
define required non-null roots/query/session fields. The
[processor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/search.rs#L81)
binds/replaces/removes exact IDs; the
[reporter](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/fuzzy_file_search.rs#L170)
checks the current query and constructs real notifications. Five upstream files
match their archive members in `/tmp/samgita-v176-next-functional-gap/source-evidence.json`.
The source-only implementation and independent notification review are retained
under `/tmp/samgita-v177-fuzzy-session-implementation/` and
`/tmp/samgita-v179-fuzzy-notification-review/`. The final file includes an equivalent
string-sigil formatting correction; its hash is bound to the final runner below.

## Exact owners and final checks

Only these **nine direct physical owners** become implemented:

| Indices | Schema fields | Independent evidence |
| --- | --- | --- |
| 1807–1808 | Start roots/sessionId | Exact envelopes and resulting two-root bindings/replacement |
| 1809 | Stop sessionId | Native absent-session response, repeat stop and working control |
| 1810–1811 | Update query/sessionId | Exact envelopes and distinct prescribed query snapshots/clearing |
| 1806 | Completed sessionId | Exact native initial idle payload for both requested IDs |
| 1812–1814 | Updated files/query/sessionId | Actual method/query/ID selection, exact counts/root-path sets and empty clear map |

One-shot results, shared request/notification aliases, result children and full
branches do not inherit evidence. Schema IDs/hashes and requirement rows stay
unchanged. Contracts become **4,599 implemented / 1,963 missing / 59 blocked**;
requirements remain **462 implemented / 12 missing / 11 blocked**, zero verified
in both inventories.

The final nine-file block is the eight files in
[appearance qualification](thread-section-values-qualification.md#explicit-appearance-field-continuation)
plus `test/native_fuzzy_session_values_test.exs`. Both complete runs with
`--warnings-as-errors --seed 501432` and `--seed 987654` pass **20/0**, in
**37.536/37.750** command seconds. Format, warning-free compile, root strict Credo
and the **232-file** unchanged-source guard pass. The separately reviewed
`python3 scripts/codex/verify_consumer.py --binary <pinned executable>` copies only
the reusable packages outside the umbrella, builds and passes its **1/0**
functional consumer case in **8.793** command seconds. It confirms an actual
native round trip without Repo/Phoenix/Ecto/platform startup, not full consumer
contract coverage. No security/permission tests or audits run.

Exact commands/logs/source: `/tmp/samgita-v178-fuzzy-session-checks/functional/`.
Results/source SHA256:
`d3502bb4fd23a541963f504d75175d6dccd3d7a6dcc020da3f9643db400261e2` /
`294551145bca18258ec9e33318c29edad097c102f69a6bae15a3a3504502919e`.
The adjacent `manifest-binding.json` retains original/current owner records and
the final test hash. No runtime failure or production driver change occurs.

This covers Linux/stdio/local file search with ordinary experimental opt-in as
fixed setup. Negotiation rejection, security/permission behavior, concurrent
query supersession, runtime-session restart persistence, remote transports,
other backends/OS, A11, full compatibility and broad/hosted gates remain
unqualified. The mixed retained fuzzy suite stays intact and unrun under the
user's restriction. No tag, release, publication or deployment occurs.
