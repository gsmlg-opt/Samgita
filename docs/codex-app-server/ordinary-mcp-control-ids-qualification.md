# Native MCP reload, status, tool and event-stop request IDs

V504 follows `ca7c3bb` on the existing `main`. The official target remains
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, binary
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
No driver, upstream, peer implementation or platform code changes.

## Original wire identity with genuine operation effects

The retained `native_mcp_request_metadata_test.exs` four-shape warm/cold case
keeps every independent argument/result/metadata assertion, exact1..4 RMCP
token maps, distinct native/thread/peer identities, complete original ingress,
journal-prefix continuity, frozen inputs, no model/replay and owned cleanup.
Actual tool calls now use negative integer, positive integer and Unicode IDs
with disjoint warm/cold values; the fourth shape keeps its generated string.
Complete outgoing bytes, typed native response ID, strict Wire decode and full
request schema are checked for each selected request. The original18 captured
outgoing/20 incoming responses remain unchanged.

A separate case starts one real thread-owned stdio peer, performs an actual
echo, then three unchanged-config reload/full-status pairs:

| Method | Negative ID | Positive ID | Unicode ID |
| --- | --- | --- | --- |
|`config/mcpServer/reload`|`-504930`|`504930`|`owned-reload-λ🙂`|
|`mcpServerStatus/list`|`-504935`|`504935`|`owned-status-雪🙂`|

Reload omits params, matching pinned Option<()>; `{}` would be invalid.
The same exact one-peer PID inventory and journal must remain; independent
review tightened the new case to an explicit singleton assertion before any
native run, leaving the original helper/case unchanged. Reload ACK alone
proves no readiness. Selected status includes both threadId and serverName,
forcing dirty-runtime refresh on the current thread. It must return the
independently prescribed live server/tool/resource projection, and a final
actual echo must still succeed exactly once. AuthStatus remains opaque.

One genuine handshake/tools-list and two echo calls bracket three resource and
three template lists. Actual RMCP token set0..8 and echo tokens1/8 are checked;
resource/template arrival order is intentionally unconstrained. Fixed method
counts, independent full echo-result maps and exact thread references remain.
No model request, extra tool execution, replacement peer or replay is allowed.
The complete14 outgoing frames include initialize/initialized;13 unique
requests must have exactly13 original-ID results. Caps stay24 outgoing,
32 incoming,8KiB outgoing/64KiB incoming and1MiB capture. Original5s operations
and60s cases remain, with a bounded20s aggregate reload journey.

`native_mcp_event_envelope_test.exs` runs its complete genuine delayed stream
journey three times in independently fresh fixtures. Stop IDs are `-504950`,
`504950` and `owned-stop-λ🙂`. Every case must receive actual activation,
release/receive the exact native event, invoke real stop, observe remote
EOF/finished cancellation and retain full native envelopes/causal ordering,
persisted empty-thread bytes, no trailing/replayed event and complete owned
listener/native/peer shutdown. No second stop of an absent subscription
substitutes for a real cancellation. All original caps and deadlines remain.

## Pinned source and physical owners

`app-server-protocol/src/rpc.rs:13–21` defines String/i64 IDs. Actual MCP
dispatch is message_processor1711–1748; mcp_processor56–106,367–389,679–703
retains original IDs through asynchronous operations. outgoing_message706–746
returns the original typed ID. mcp_refresh10–155 publishes current config;
codex_thread1150–1169 and mcp_processor400–412 select the live refreshed runtime.
Full-status resource/template discovery is concurrent in codex-mcp799–839.
Twenty complete producer files match the immutable archive in
`/tmp/samgita-v504-implementation-evidence.json`, SHA256
`86fc41a1c070d693bf2f96e70832af55c570da14d5187e005cbf2bcf526f1d94`.
The new internal token sequence is a native runtime obligation, rather than
an archive-verification claim about external SDK implementation.

Only four exact `ClientRequest.json` physical `id` owners gain scoped
implemented evidence:930 reload,935 status,950 event-stream stop and955 direct
tool call. All reference RequestId and have canonical SHA256
`f1fb3724bb7835add8ed79ef8a7e1acaf3c9c5761502e6ae54c85d0c7f6c82e7`;
each is exercised through its own real method, with no shared-type/alias or
whole-method credit transfer.

## Qualification and remaining gates

The independent-driver focused command for the two owning modules passes
**5/0** at seeds501432/987654,7.2/7.3s, and root strict Credo passes across593
files. Original logs: `/tmp/samgita-v504-focus-501432.log` and
`/tmp/samgita-v504-focus-987654-credo.log`. Final combined-source checks pass
as recorded below. Independent source review has
only the pre-runtime singleton finding described above; no cap, assertion,
deadline or existing case is weakened.

No credential/authentication/authorization/permission/approval test, security
audit, mixed/broad suite or hosted workflow runs. Resource/read940 is outside
this unit. Full compatibility, real-service/OS profiles, A11 and release gates
remain incomplete; nothing becomes verified. Rollback removes test/evidence
extensions without touching persisted platform data. No publication, live
credential change or deployment occurs.

## Final combined-source qualification for V502–V505

The reviewed command is:

```sh
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-v502-v505-qualified
```

All **14/14** steps pass. The **61 selected files / 117 actual-native cases**
pass at seeds `501432` and `987654` in 201.3/199.7s. Selected WebSocket
overflow/replay cases pass at `455834`, `501432` and `987654`. The independent
consumer passes **1/0** outside the umbrella; inventory consistency, driver
and umbrella warning-free compilation, format, strict Credo, Dialyzer and
assets build pass. The runner confirms all **1,680** guarded source files
stay identical, with fingerprint
`3c3b0ac522463c61aeb8bf461710002c0fbb019eaa2409dbb541dddb0db149db`.

| Final evidence | SHA256 |
| --- | --- |
| `/tmp/samgita-ordinary-v502-v505-qualified/results.json` | `77507fd2389453c26596572d76bcfa95dad9c4e2e54fdf80e8445d31ef3e4e1b` |
| `/tmp/samgita-ordinary-v502-v505-qualified/source.json` | `05b8cd0810ac235ca0ff6920a873f58a7677dea7e8cb8bac5b981b1f0aa685c8` |
| `/tmp/samgita-v502-v505-binding/source.json` | `eaa70df1e62cca2d98ed62d176bc410506a00b542286e1f3de435edd802b86fc` |

The binding checks 123 whole producer/reference files, all 5,259 Rust archive
members, 25 precise schema nodes and the owning final test/fixture/launch bytes.
Its first source-only invocation incorrectly indexed `Cargo.lock` as a Rust
file and stopped with `KeyError`; the corrected helper verifies that lock
directly against the hash-pinned source archive. No native test or source
assertion was changed by that evidence-helper correction.

Across these units exactly ten physical owners become scoped implemented and
eleven prediction-notification owners become source-proven blocked. Four
collaboration values stay missing because generic public projection remains
possible without authentic built-in-operation evidence. Totals are **5,475
implemented / 1,016 missing / 130 blocked contracts** and **462 implemented /
12 missing / 11 blocked requirements**, with **zero verified** in both ledgers.

This final functional selection also qualifies the installed-plugin Hook,
Unicode diagnostic range and genuine partial session-import evidence. It
does not execute prohibited tests/audits, broad suites or hosted workflows.
A11, unavailable stock emitters, real external/OS success, complete compatibility
and release remain incomplete. Next is the independently reviewed ordinary
fuzzy query/populated-session stop and cold-recovery profile; its scratch
implementation has not yet run. No package is published or service deployed.
