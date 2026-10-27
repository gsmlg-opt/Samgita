# Native direct MCP request metadata

The ordinary direct MCP path now has exact original-wire and real-backend
evidence for nested JSON, Unicode and optional-field shapes. Eight real calls
span two distinct native processes and fresh normal root threads. Protocol and
driver runtime and the existing MCP peer fixture are unchanged.
Base: `9ff340ddfea9d261011e3cf5cc7f733bd57d3b6c`.

## Native producer and two boundaries

The immutable Codex target remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`
and source archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Seventeen complete source/archive members, five exact schema nodes and five
members of the separately pinned SDK archive are checked. Cargo.lock pins RMCP
3.5.1 to rust-sdk commit `4048ac40e958fb1a7d614617a2ae8d26666ee2fa`;
its official source archive SHA256 is
`aff9954fec4fee134ff47197189d6f5a626f3a53dc705469c850f4a44af22eb5`.

`app-server/src/request_processors/mcp_processor.rs:680–736` dispatches the
actual public mcpServer/tool/call for a normal loaded thread and adds its native
thread identity to backend metadata. There is no rawMcpToolCall feature at this
pin. The ordinary configured owned stdio echo peer is a dependency fixture;
the immutable native executable produces every app-server response. No model
turn, protected behavior, remote MCP service or resource operation is requested.

Each new ephemeral root thread receives four direct calls: rich nested Unicode
arguments/nonreserved metadata, both optional keys omitted, explicit nulls and
empty objects. Original sent bytes/maps/IDs distinguish omission from null;
the exact backend journal proves those two converge only at the native Option
decoder, while arguments:{} stays present. Independent complete native result
and backend params comparisons retain nested values, array order, zero/false,
content metadata and native thread identity. The cold process starts a distinct
new thread and repeats the calls; it does not resume or replay old work.

## Source-proven progress metadata correction

The initial real test failed because its backend oracle omitted mandatory
progressToken. It was a test-oracle defect, not a driver/native protocol defect.
The original formatted source and failure log remain preserved. Complete map
comparison was retained, with independently derived integer tokens added and
startup controls strengthened.

Pinned SDK `service.rs:478–494,815–823,886–899` gives each fresh Peer a zero-based
progress counter shared by clones, separate from request IDs. Every outgoing
Peer request allocates and injects a token. `service/client.rs:889–947` sends
initialize/initialized directly through the transport, bypassing this counter.
The native one-page startup catalog read therefore has complete params
`{"_meta":{"progressToken":0}}`; the four calls use1–4. Each cold Peer resets
the sequence. Exact startup params, initialization count, protocol2025-06-18
and complete call metadata are now asserted. No arbitrary extra fields or
renumbering from observations is accepted. OTEL exporters are fixed to none as
fixture setup; trace behavior is not a qualification target.

The corrected native run passes **1/0**. A later strict Credo run rejected the
escaped quotes in one configuration string; a byte-equivalent sigil fixes that
style issue. That failed run remains under `before-style-fix/`. Neither change
alters deadlines, SDK/helper behavior or the caller's original wire data.

Eighteen selected requests preserve exact order/maps/bytes and correlated IDs:
eight tool calls, two starts, two diagnostics and six loaded-list queries.
Capture remains24 frames/8KiB, responses65KiB, journals128 rows/1MiB and events
128/1MiB. Initialize/request deadlines stay5s and the case60s; backend limits
stay10s. Config/catalog/provider/peer/support and workspace remain exact, with
no inference or rollout files. Native/helper PIDs are identified only under
the owned native tree with bounded reads; both closes require completion,
closed Port and absent native/matching helper PIDs. Existing failure cleanup
and process-group reaping remain intact. Fixed YOLO is launch setup only.

## Final checks and scope

After the preserved native failure and correction, the final two ordinary
modules pass **2/0 at501432 and987654**. Peer Python syntax, driver compile/
format, strict Credo549 and inventory consistency pass with383 stable sources:
all381 prior sources unchanged, plus the new test and an existing unchanged
peer newly added to the guard.770 exports and15 input descriptors remain exact.
Prior87schema/148ordinary-driver-twice/outside-consumer1/0 and root/static/
assembly evidence retains source equivalence without fresh-run claims.
No mixed/broad suite, prohibited test/audit or hosted workflow was run.

Commands/logs/guard: `/tmp/samgita-v380-run.py` and
`/tmp/samgita-v380-functional-checks/final/`. The initial failure is
`/tmp/samgita-v380-native-initial.log`; corrected run is
`/tmp/samgita-v380-native-after-repair.log`. Source, token and final reviews are
`/tmp/samgita-v380-ordinary-gap.md`,
`/tmp/samgita-v380-progress-token-review.md` and
`/tmp/samgita-v380-final-review.md`. The final binding records their hashes,
initial red source/log, style failure, source/SDK evidence and exact owners
4398–4402 (`McpServerToolCallParams._meta`, arguments, server, threadId, tool).
Only those become scoped implemented; method request/response gain supplemental
evidence. No sibling schema or full MCP family is promoted.

Contracts: **5,065 implemented /1,490 missing /66 blocked**. Requirements remain
**462 implemented /12 missing /11 blocked**, zero verified. Strict completeness
still fails. Modern MCP, all input/result/error/transport/OS/backend variants,
unreachable legacy emitters, prohibited verification, A11 and full-goal acceptance
remain incomplete. Nothing was published or deployed.

Rollback removes this isolated test and exact evidence only; retain the existing
shared peer, process cleanup, runtime, earlier qualification and historical
records. Continue source-supported ordinary groups; no green subset closes the
complete compatibility goal.
