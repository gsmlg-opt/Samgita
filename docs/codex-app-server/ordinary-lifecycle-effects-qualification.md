# Ordinary native terminal, Hook source and memory-reset effects

This unit follows `1a8b84f` on `main`. Official Codex remains
`rust-v0.163.0`, commit `83086188ae0614bd882818ff1aa23f3194962012`, executable
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Tests check both executable bytes before launch and the actual native PID.
Every app-server envelope comes from that executable. Local deterministic
dependencies supply model responses, owned stdin readers and Hook observers.

Fixed YOLO (`never` / `danger-full-access`) is ordinary positive setup. No
security, credential, authentication, authorization, approval, permission,
sandbox or trust outcome is tested. Historical mixed profiles remain unrun;
audits, broad suites and hosted workflows stay prohibited and incomplete.

| Physical owner | Actual native evidence |
| --- | --- |
|1254, ClientRequest root35/id|One omitted-params memory/reset, integer ID -1254, nonempty synthetic inputs and independent cold observations|
|1289, ClientRequest root41/id|String-ID background clean followed by original item completion and independently observed process exit|
|1299, ClientRequest root43/id|Integer-ID targeted terminate stops A while the independently observed B remains alive|
|2261, ServerNotification HookSource enum4|Cold native Hook started/completed report sessionFlags for an actual CLI declaration|

Each request selects its unique method and physical reference with unchanged
RequestId definitions; exact original sent/received bytes, strict typed
correlation and full result validation remain. The Hook enum is selected from
the original definition and validated against actual delivered/captured data.
Equal references, aliases, unions and full methods gain no new promotion.
Eight already implemented request/response/notification entries receive scoped
supplements without state changes.

## Background terminal effects

One real native turn launches two separate owned Python stdin readers through
unified exec. Exactly three model requests produce reader A, reader B and one
answer. Actual tool output contains each independently prescribed READY marker
and its original native process/session ID. Readers record their own PID, name
and cwd; the dependency opens Linux pidfds before returning the final answer.

Exactly one terminate request, integer1299001, targets A. Its ACK is followed
by the original command item's completion and an independent pidfd exit
observation. B must still be running and the native list must retain only B.
Exactly one clean request, string `owned-background-clean-1289`, then produces
the original B completion, independently observed B exit and an empty native
list. List emptiness or ACK alone cannot establish exit or reaping. Actual
reader/native PID absence is required after shutdown.

The dependency emits Responses SSE only, never app-server frames. Original SSE
bytes, model inputs and native output are compared independently. There are
exactly ten outgoing native frames, three Responses requests and three read-only
pidfd controls. Reader natural expiry/EOF/input writes a rejected unexpected
marker. Reader lifetime35s exceeds the behavior deadline30s; the peer has50s
total lifetime. No sleeps, desired-state retries or repeated mutations occur.
The case has60s total/5s request limits,256 events/2MiB queues and64KiB messages.

Immutable producer chain: `thread_processor.rs:2480-2542` submits clean before
returning; `process_manager.rs:1822-1904` drains the process store before
termination; `async_watcher.rs:156-247` emits the original command end after
output draining. `event_mapping.rs:459-465`, `item_builders.rs:117-148` and
`thread_history.rs:694-705` preserve its identity and original turn. These
semantics explain why ACK/list/turn completion need separate effect checks.

## CLI Hook source

The existing finite tool/Hook dependency supplies ordinary command and observer
inputs unchanged. The test requires exactly one terminal PostToolUse declaration
in its owned user TOML, removes only that suffix and retains PreToolUse as a
user-source control. The same post declaration is supplied through a bounded
`-c hooks.PostToolUse=[...]` CLI argument. It is never inserted into a synthetic
ConfigLayer or emitted notification.

Warm native performs descriptive listing and fixed positive setup, then closes
fully. A distinct cold PID receives the same CLI declaration and unchanged user
config. Only the cold process executes the command journey: two turns, one
finite command and three model requests. Real Hook started/completed pairs must
contain `sessionFlags` and `/<session-flags>/config.toml`. Actual Hook stdin,
command PID, file/stdout effects, causal IDs and delivered/captured native frames
remain independently checked. CLI declarations are not claimed to persist into
user TOML, nor is a warm command journey claimed.

Config loader/override code creates SessionFlags; Hook discovery/dispatcher and
core Hook runtime preserve that provenance. The synthetic path is output
metadata, never created or read as a file. Bounds remain60s case,20s behavior,
5s request/startup,1s observers,128 frames/events and2MiB queues/capture. Setup
does not vary, inspect or assert permission or trust outcomes.

## Owned memory-reset effects

The existing lifecycle test file gains one case; its two existing cases and all
helpers remain byte-identical. Actual native memory/status creates/migrates its
own SQLite store, then native closes. The unchanged input helper observes its
count0 and seeds count2 only while native is absent. Five independently authored
Unicode text files populate V1/V2/extension roots, including one valid synthetic
summary. These are reader inputs, not generated/consolidated memory.

A second native observes count2/true. Exactly one actual memory/reset sends
integer -1254 with no params member. After its real empty result, all three
roots remain empty directories, authored paths disappear, and the existing
SQLite inode stays unchanged. Status string `"-1254"` observes count0/false.
An independent stopped-native helper read and a third cold native both retain
count0; no thread, turn, model request or second reset occurs. Exact outgoing
inventory is17 frames/14 requests. All inherited bounds and cleanup remain.

`thread_processor.rs:1918-1937` awaits SQL reset and directory clearing;
`memory_versions.rs:28-37`, `memories.rs:1434` onward and
`memories/write/src/control.rs:3-13` implement those effects. This does not prove
cross-resource atomicity, V1 SQL/job combinations, writer success or partial
reset recovery. This fixture is unrelated to Samgita's PostgreSQL recovery:
no shared database, platform task, historical record or activation guard changes.

## Source binding and focused checks

The binding compares26 complete production sources with unique immutable archive
members, nine generated schemas with retained generation/provenance bytes and
exactly the four physical nodes above. No schema regeneration or generated-JSON
archive membership is claimed. Source archive SHA256:
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.

```sh
python3 -B /tmp/samgita-ordinary-lifecycle-effects-source-binding-20261028.py
devenv shell --no-tui -- python3 -B /tmp/samgita-ordinary-lifecycle-effects-focused-v3-20261028.py
```

Focused final source passes **5 tests /0 failures** at seeds501432/987654,
format and strict Credo across625 sources. Earlier focused runs also passed
5/0 twice; their Credo failures remain: exit12 for overquoted CLI text and two
nested blocks, then exit8 for one remaining nested branch. Equivalent sigil
bytes and extracted assertion helpers resolve them without changing assertions,
deadlines, buffers, fixture bytes or cleanup. A separate root format attempt in
the default development environment failed during telemetry_metrics BEAM type
inspection; it made no source change. The verified test environment is used
for the successful focused/final checks; no dependency repair is claimed.

| Evidence | SHA256 |
| --- | --- |
| Source/node binding | `b32dcc248cffc2d0cab108ad8b190b10c2f538357b66bb65de07f7e2869d6c59` |
| Original Credo exit12 | `0ba8463663750691b8b71867f9381f41a5f9ef576fbbf808077b848bc9a0d786` |
| Intermediate Credo exit8 | `cdb264d037534bee8024776b886e95bc6089d6753327d6dd46f77e1eb41b7220` |
| Final focused501432 | `d98181bb5f55c2287f56151c69cbe728e347fc40a6dcb55a4b2462a5dcb4fbd9` |
| Final focused987654 | `9117a3314d298bdba3add881cb86ef44be6e06182e18754aaa23f115d9274a32` |
| Final focused Credo | `6cfd671752dc1075b8ec9b842b43775455eb1ae4dbf7b52e7fc618bfdc5f498b` |
| Terminal dependency | `b149a92976fedfd1f7989f11dfe7111767bf57ecb161b060505e5be4a575d299` |

## Combined-source result and unresolved cleanup

The reviewed selection now has94 files/161 cases. Source preflight proves only
the four promotions/eight supplements, the preserved lifecycle cases/helpers,
1,725 unchanged prior sources and all prior command arguments except the two
added file arguments. All1,731 guarded sources remain identical during checks.

The original run in `/tmp/samgita-ordinary-lifecycle-effects-final-20261028`
passed the three selected WebSocket seeds455834/501432/987654, driver format/
compile and161 native cases at501432 (305.365s). Seed987654 failed one of161
cases (319.302s): the existing environment-connected/disconnected case raised
`owned_process_shutdown_unconfirmed` during cleanup. Its retained journal proves
the inner app/executor/controller stopped and its sockets/workers closed. It
does not prove the outer stdio helper acknowledged complete cleanup. The original
failure log SHA256 is
`b5a682f9eaf985b0c9fe87884d7b0371d2c7e3ab28c79132b9b94ec951ba9fe0`.
This required combined run remains failed, regardless of later diagnostic passes.

Three isolated diagnostic runs passed1/0. A broader diagnostic that shadowed
Python globally violated existing executable/argument identity assertions and
was interrupted; its failures are retained in
`/tmp/samgita-shutdown-ack-probe-20261028/full-seed-987654.log`. It supplies no
compatibility evidence. Restricting that alternate helper to the one target
passed161/0, but also closed the transport earlier than the original case; it
does not settle the original failure.

The subsequent diagnostic preserves every original test, helper executable,
argument, environment and close order. It adds only allowlisted Erlang call
observations of cleanup ACK presence, exit status and the first shutdown result:

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-owned-close-first-result-20261028.py
```

Result:161/0 at987654,281.2s. All389 observed shutdown returns were `ok`; all16
observed natural Port exits already had the ACK. No native payload or environment
value enters this trace. Result/log/trace SHA256 values respectively:
`e6dfb4ad3da65b2fd365e6cbb9176d0c439941da43ffba1fa7e7beb1cf061853`,
`e4d75a135f007c87094e16cc7f5f6e8b08e9f7239e26346fcf9c2c490a51644b`,
`4a7d27cdda0de3999718a45558da66777b69a5e3c52560685b91fee81aa0c000`.
This is a non-reproduction with additional observations, not a repaired runtime.

A separate deterministic helper-only barrier imports the unchanged production
helper and holds its output reader while the actual finite child exits and is
reaped. With the reader held, the real helper returns0 without output or ACK;
released before its unchanged1s join, it emits the exact finite line and real ACK.
Both owned workers/children are absent afterward. Its summary is
`/tmp/samgita-output-drain-barrier-wq0xna_5/summary.json`, SHA256
`dcceb1a0a5dfaf60fda1032bbd5f28e645a36d4f0d28a38cc850ec11cb0a6d4b`.
This proves a concrete no-ACK branch, not that it caused the original failure.
No join deadline, assertion, cleanup guarantee or runtime implementation changes.

The exact installed OTP27.3.4.17 source further rules out the proposed ordinary
stream SIGCHLD-before-data explanation: Unix `sys_drivers.c:741-753,1206-1253,
1338-1349` records child exit, forwards positive reads and reports exit only at
stdout EOF. Official source commit
`79157f447019730504f6f6c43c9b1d1cfa1d4192` matches installed documentation.
Line/EOF options and forced-close/error paths differ. The complete source audit
is `/tmp/samgita-ordinary-port-exit-order-audit-20261028.md`, SHA256
`3c17457f77bb2b208cd2d546190decc17055e2d94bd308575dad2c5045044cde`.
The failure's first helper-side cause remains unresolved; capture that cause
before proposing a repair. Repeating the selection until green cannot close it.

The seven previously unexecuted ordinary consumer/static/build steps run
separately against these same guarded sources. Their result is recorded below;
they cannot replace the failed native combination or the prohibited full matrix.

All seven pass: outside consumer1/0 (13.232s), inventory consistency, warning-free
umbrella compile, root format, strict Credo across625 files, Dialyzer and assets
build. Command: `devenv shell --no-tui -- python3 -B
/tmp/samgita-ordinary-lifecycle-effects-remaining-20261028.py`.
Results/source reports are in
`/tmp/samgita-ordinary-lifecycle-effects-remaining-20261028`, SHA256 respectively
`9c5cc7ff5c80bf3fa2e764e138e57dde1381cff8df06ec6c73f73e7a9451c8f0` and
`462deea289f4450b9bc33e0c5a71a9413e9e08f1a7a81e26a17d236f71cd560e`.
Guarded-source fingerprint is
`027126d79499d7c610cb3702f5e743e41abc481cde9c0f40e3d103f1f5e2d163`.
These are seven completed suffix steps, not a successful14-step original run.
The native cleanup uncertainty remains a separate open gate. Ledger totals are
5,652 implemented/833 missing/136 blocked contracts,462 implemented/12 missing/
11 blocked requirements, and zero globally verified rows.

Complete compatibility, prohibited/broad/hosted checks, A11, unavailable emitters,
external/other OS success, native timestamp cursor, publication, release and
deployment remain incomplete. No platform database recovery rerun or production
migration occurs. Rollback removes the added tests/dependency/selection, reverts
only these four promotions/eight supplements and this documentation. Runtime,
existing cleanup, dependency, WebSocket replay and recovery repairs remain exact.
