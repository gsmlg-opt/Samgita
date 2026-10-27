# Native ordinary MCP startup notices

V400 starts from `b53c98df9c3e43714029f29a1e0a7f800546dbe1` on `main`.
The new [ordinary test](../../apps/samgita_codex_driver/test/native_mcp_startup_notice_test.exs)
and [dependency-only peer](../../scripts/codex/mcp_startup_notice_fixture.py)
qualify exact stable `McpServerStatusUpdatedNotification.json` owners4391
(`/properties/error`),4392 (`/properties/failureReason`),4394 (its `anyOf/1`
null arm) and4397 (`/properties/threadId`). Runtime, shared fixtures and previous
tests retain their bytes. Other physical aliases receive no inferred evidence.

Target remains official `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
archive SHA256 `e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Seven complete upstream files match their immutable archive members; all four
stable physical nodes independently match their canonical hashes.

## Causal startup and independent payloads

Two sequential profiles use independently created roots, native processes,
peer journals and server names `owned_startup_alpha`/`owned_startup_beta`.
Each fixed-YOLO native process creates one ephemeral thread. The dedicated
stdio MCP peer journals its actual PID and received initialize request, then
withholds its reply until an explicit release marker appears.

The independently prescribed complete starting payload is:

```json
{"threadId":"<returned native thread ID>","name":"<configured name>",
 "status":"starting","error":null,"failureReason":null}
```

Driver events and original incoming JSON must contain that exact payload. A
public `thread/loaded/list` RPC must finish with the known single thread while
the peer journal still contains only startup/initialize receipt, no reply or
release, and no ready notice. This observable barrier proves live responsiveness
during the held dependency; elapsed sleeping is not the noncompletion oracle.

Atomic marker rename explicitly releases the real dependency response. Native
Codex then emits the same complete independently expected payload with status
`ready`. A second public barrier, exact peer request/reply/initialized journals
and ordered original/native-delivered payloads remain required. Distinct thread
IDs and roots prevent one hardcoded identity from satisfying both profiles.

The peer emits MCP initialize/catalog replies only; it contains no app-server
notification producer. Stock `connection_manager.rs:689–713,755–781` emits
Starting before awaiting the client and Ready after success; `startup.rs:42–53`
wraps its event. `bespoke_event_handling.rs:203–229` supplies actual thread ID and
ordinary null diagnostics. `v2/mcp.rs:365–375` serializes those Option fields
without omission. Actual client initialize/catalog awaits are in
`rmcp_client.rs:959–968,1026–1039`.

The selected dependency protocol is explicitly **MCP2025-06-18**, with
`mcp_2026_07_28=false`. No model turn, tools/call, elicitation or server request
occurs. The local model fixture remains inert with byte-exact empty requests;
configuration, helper inputs and empty workspaces remain unchanged. Nonnull
errors, null threadId, other MCP versions and authentication-specific owner4393
remain unqualified. This is real Codex with a fake local dependency, not a real
provider/service acceptance profile.

## Bounds, cleanup and final-source checks

Each profile asserts six correlated native RPC pairs plus initialized. Original
outgoing JSON and incoming response frames bind exact requests/native IDs;
incoming notification payloads bind independently expected driver events.
Frames precede Session decoding after JSONL delimiter removal; OS chunks and
newline preservation are not claimed. Raw capture128frames/2MiB,4KiB outbound/
64KiB inbound, events128/2MiB and snapshots1MiB remain bounded. Peer frames64KiB,
journal64rows/64KiB/4KiB per row and explicit release wait8s are finite. Native
startup10s, ordinary RPC/predicate waits5s and case60s are new scoped bounds;
no retained timeout or assertion changes.

Normal and failure cleanup monitor owned native/provider owners, require
completion and closed Ports, and check native plus journaled MCP child PIDs
have disappeared before root removal. Existing process cleanup remains intact.

Initial focused native **1/0** passes before the style extraction. The first
combined attempt stops at strict Credo: nested reduce/case depth3 in the new
capture wrapper. Extracting that unchanged callback into `record_events/2`
repairs the finding without changing assertions, limits, deadlines or resources.
The failed source/logs remain in `/tmp/samgita-v400-functional-checks/final/`.

Final source passes **23/0** at **501432** and **987654**, no exclusions, plus
Python syntax, scoped format, warning-free driver compile, root strict Credo
and offline inventory consistency. All397 guarded sources remain stable; all395
prior source bytes remain unchanged. Environment remains Elixir1.18.5/
OTP27.3.4.17, test mode, two schedulers and exact native executable.

Runner/results: `/tmp/samgita-v400-final-run.py` and
`/tmp/samgita-v400-functional-checks/final2/`; focused artifacts:
`/tmp/samgita-v400-native/mcp-startup/`. Final test SHA256:
`bb1a1661f8f426a58786bd242195e6d6f77bd6625212595853ccfed6dbcc50c7`;
peer SHA256 `6ade0c9894edad112100fa98e773f3a7e797adf60c355bd39a7201daac244725`.
Results/guard SHA256: `506f0b1e6f583709d401689658824933fc08d419c62d5187c5db7b82e441f589`
and `bc4e619fc06d9930ce35ec68e992cad9967cc64ae6bcf4e74559b4b33c46052c`.
Source binding: `/tmp/samgita-v400-source-final/evidence.json`, SHA256
`254113844ac35d66a68eaf018e1c149f8719ad6d3476a9d50ed8c94abdc4dde8`.
Manifest binding: `/tmp/samgita-v400-bind.py` and
`/tmp/samgita-v400-binding/evidence.json`, SHA256
`9dfd57dd9d1e4436d5b650ceea83a8de92aa33e25a5261a2c79c0028735ac69f`.

Only4391/4392/4394/4397 become scoped implemented: **5,111 implemented
/1,444 missing /66 blocked** contracts; requirements remain **462 implemented
/12 missing /11 blocked**, with **zero verified** in both. Strict completeness
remains red. Security/credentials/authentication/authorization/permission/
approval tests and audits, broad suites and hosted workflows remain unrun.
A11, unavailable native producers and external/platform/full-goal/release gates
remain incomplete. No tag, publication, deployment, production migration or
sibling change occurs. Rollback removes the two new files and four mappings;
retain runtime and historical records. Continue ordinary original command-output
ingress evidence against the unchanged independent binary-stream oracles.
