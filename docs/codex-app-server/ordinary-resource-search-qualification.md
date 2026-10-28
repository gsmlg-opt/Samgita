# Ordinary native resources and persisted occurrence search

This unit follows `1e6597c` on `main`. The reference remains official Codex
`rust-v0.163.0`, commit `83086188ae0614bd882818ff1aa23f3194962012`, executable
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The tests hash that executable before launch and at its actual native PID.
App-server requests, responses and notifications use the real executable.
The synthetic dependencies provide MCP resource content or one model answer.

Fixed YOLO (`never` / `danger-full-access`) is inert setup in the owned config,
launch and applicable thread request. No security, credential, authentication,
authorization, approval, permission, sandbox, trust, header, TLS or policy outcome
is tested. Historical mixed profiles stay unrun. No audit or hosted workflow runs.

| Physical owner | Actual native scenario |
| --- | --- |
|940, ClientRequest root133/id|One threadless `mcpServer/resource/read` with a string ID and real local MCP content|
|1379, ClientRequest root58/id|Persisted `thread/searchOccurrences` with typed IDs, Unicode ranges and opaque cold continuation|

Each case selects its unique method in the unchanged experimental request root,
checks the exact physical reference and original RequestId definitions, and
validates the captured actual ID plus full request. Exact sent/received bytes,
Wire decoding, strict typed response correlation and full result validation
remain. Equal reference hashes do not qualify another method, alias or union
alternative. Only these two missing physical owners gain implemented evidence;
four existing method requirements receive supplements without changing state.

## Threadless resource read

One ordinary native read addresses an independently authored resource URI on a
named local stdio MCP peer. The full native result must preserve Unicode text,
MIME types, five independent binary bytes and nested metadata, with the present
native `originCallId:null`. The peer records its original incoming/outgoing JSONL
bytes separately; exact method order, URI, typed IDs and authored content are
checked. It never produces an app-server envelope.

The immutable MCP startup always fetches `tools/list`
(`codex-mcp/src/rmcp_client.rs:668-689,1026-1036`). The peer returns one empty
catalog. The exact sequence is initialize, initialized notification, tools/list,
resources/read: four inputs and three outputs. No tool is invoked. The threadless
path in `mcp_processor.rs:543-682` constructs the real resource response after
the managed client read, then cancels its temporary manager.

Empty loaded registries, unchanged inputs, an empty workspace and absent rollout
files remain observable. An owned in-process loopback listener detects any model
connection without inspecting HTTP or headers; none may occur. The peer's exact
PID/parent, exclusive owner marker and normal closed journal are checked after
native shutdown. Both peer and native PID must be absent. Manager cancellation
alone cannot satisfy cleanup. No model service, thread, turn or replay is started.

The self-contained peer has no children, threads or network operation. It is
bounded to20s, eight messages,16KiB frames,4KiB replies and32 journal events/
128KiB. Its signal loop checks at most50ms; a normal journal close must precede
the owned native process-group cleanup. Unexpected operations fail explicitly.

## Persisted Unicode occurrence search

One non-ephemeral paginated native thread receives the independently prescribed
text `😀 Needle needle NEEDLE`; one local model completion returns a prescribed
answer. The actual completed turn and a subsequent real `thread/read` with
includeTurns prove both items and native identities. The pinned paginated read
path persists the thread before returning (`thread_processor.rs:3155-3185`).
This supplies an explicit persistence barrier before any search request.

Three limit1 pages for `needle` must contain the exact independent UTF16 ranges
3..9,10..16,17..23, original snippet and observed user-item/turn IDs. Two distinct
opaque continuation cursors lead to an explicit null final cursor. The actual
turn cursor must navigate back to that saved turn/item. No cursor is decoded or
manufactured. The immutable history search reads projected visible items and
builds those cursors (`thread-store/src/local/thread_history/search.rs:50-250`).

After confirmed warm shutdown, original rollout bytes are snapshotted. A distinct
cold native process searches the second and third pages using those unchanged
cursors before any read/resume/turn primes history. Full page equality, the
independent ranges and empty loaded registry remain required. Rollout/provider
journal bytes stay exact across cold reads and shutdown, with exactly one model
request. Input files and the workspace remain unchanged. The only generated
history belongs to the disposable test home.

This uses occurrence ordering within one thread. It does not exercise or repair
`thread/search`, its created-at timestamp precision/reverse-cursor defect or
owner5702. Those gates remain incomplete.

## Bounds, source binding and focused evidence

Both cases have60s total bounds and5s initialization/request deadlines; the one
model turn has15s completion. Captures are64/128 frames,8KiB outbound,
64/128KiB inbound and1MiB total. Sessions keep128 events/1MiB queues. No deadline,
buffer, response oracle or owner cleanup changed after a runtime failure.
Native/model cleanup requires owner DOWN, completion atomic, closed Port and
absent owned PIDs, with the retained on-exit fallback. The reused assistant
provider keeps its existing4MiB POST bound and owned shutdown; it is not a new
self-timed backend. Only one model request is permitted in the search case.

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-ordinary-resource-search-focused-20261028.py
python3 -B /tmp/samgita-ordinary-resource-search-source-binding-20261028.py
```

Formatting and Python AST parsing pass. Both focused seeds501432/987654 pass
**2 tests /0 failures** before the equivalent style correction below. The source
binding compares12 whole production files
to their unique immutable archive members, six generated schemas to retained
generated/provenance bytes and exactly two canonical physical nodes. Archive
SHA256 is `e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
No new generation or archive membership of generated JSON is claimed.

| Evidence | SHA256 |
| --- | --- |
| Focused501432 | `6add35fda1f9af6c72177d5a93e37f5a3bd502369552972c767124600cf85b09` |
| Focused987654 | `f300705febd75e897b7c41e7d455efe2cf25b7997cccc8ab332e32e0cd7b25ad` |
| Source/node binding | `7d99d262c4ff01f87fc3b0558db600c29b21e8b91f951e61da31efa4454067c0` |
| Final resource peer | `db73b73e84a4ca14dbef753d93045f765d71f7240d543344495de97c5a0540eb` |
| Final resource test | `ab3ba0863e7de39beaea3726a18d64ed88dc6cbfaa67feb2dc7f6a06c150c9d7` |
| Formatted search test | `9fab5710dff554fc36d5809401202f94d715c53a05c3c7a045f9e6d14823e3ea` |

The first strict Credo check finds one overquoted canonical JSON literal. The
same bytes now use the existing indented heredoc style, retaining both their
canonical hash and decoded-node equality. No semantic assertion, deadline,
buffer or cleanup changes. The first failure is preserved as an explicitly
marked tool transcript, SHA256
`1815111622716bfa75a1cc0d6e1d0ef2330d1f2a556695e2f4d18d324fe01804`.

## Final combined-source functional qualification

All **14 reviewed functional steps pass** on final combined source. The selection
adds only these two native files: **92 files /158 actual-native cases**, each
passing at seeds501432 and987654. Three selected WebSocket cases pass at each
of455834/501432/987654; the independent consumer passes1/0. Driver/root format,
driver/umbrella compile with warnings as errors, inventory consistency, strict
Credo, forced Dialyzer and assets build also pass. The corrected literal passes
its retained hash/equality oracles in both full functional repeats.

```sh
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-resource-search-final-20261028
python3 -B /tmp/samgita-ordinary-resource-search-final-binding-20261028.py
```

Results SHA256 is
`3784308593089f5488dd3b1dc38c1b1ebac88c3e86cf38d9f7eafde73b08c00e`;
source snapshot `cd9ff93c474df08fdf6763f0af846fd1be79d05edd776dd0429168fde5000eea`;
binding report `51778a9607d7db73991748c3b12d12568e56811b6089e7d8cf14c5c52882d232`.
All **1,728** guarded source hashes agree before/after; reviewed fingerprint is
`0ed1f032c67c66203dcfc28b344513f485c04ba25677042736390e5d7cc22702`.
All **1,723** other prior sources and all prior command arguments remain exact.
Only two physical owners gain implemented credit; four requirements gain
supplements. Contracts: **5,648 implemented /837 missing /136 blocked**;
requirements **462 implemented /12 missing /11 blocked**, zero globally verified.
No other state gains credit.

Complete compatibility, prohibited/broad/hosted checks, A11, unavailable emitters,
external services/other OS success, native timestamp cursor, publication, release
and deployment remain incomplete. No database recovery rerun, shared-history
deletion or production migration occurs. Rollback removes these two tests, peer
and selection, reverting only their two promotions/four supplements and this
documentation. Existing runtime and process-cleanup implementations stay exact.
Next: qualify the source-reviewed ordinary background-terminal lifecycle, CLI
hook-source and owned-memory-reset drafts. Their runtime remains unverified
outside the repository.
