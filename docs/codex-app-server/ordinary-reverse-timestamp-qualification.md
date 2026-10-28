# Native millisecond reverse pagination

This unit adds one ordinary actual-Codex test for `thread/list` reverse
pagination under `updated_at` and `recency_at`. It supplies partial evidence
for owner5702, which stays **missing** because the retained `created_at`
precision-loss failure remains unresolved. No production code or cursor is
rewritten. Baseline is `af982ae6e45b457ee7cfaf51057a06f8640204de` on `main`.

## Independent timestamps, original cursors and cold readback

`apps/samgita_codex_driver/test/native_thread_sort_values_test.exs` retains its
existing case/helpers and adds one case with narrowly named reverse helpers.
It runs the official pinned Linux/musl binary with fixed YOLO setup and the
unchanged finite loopback Responses provider. The provider supplies assistant
output, rather than app-server responses or cursor values.

Two genuine paginated threads complete one turn each; a third turn updates the
first thread. Native full-history reads establish persistence before a
query-only, read-only observation of the owned SQLite timestamp rows. Independent
inequalities require first-thread updated/recency time to exceed both its old
value and the second thread's value, with two distinct timestamps. Created time
stays unchanged. Expected ascending `[second,first]` and descending `[first,second]`
orders come from those independent rows, rather than list output.

For each sort key and direction, four limit1 native requests assert:

1. Page1 contains the prescribed first ID and a nonempty nextCursor.
2. Passing that cursor unchanged yields only the second ID and terminal null
   nextCursor. Its original backwardsCursor is nonempty.
3. Passing that backwardsCursor unchanged in the opposite direction includes
   the **exact page2 anchor ID**, with a nonempty nextCursor.
4. Passing the latter cursor unchanged returns the original preceding ID,
   completing the reverse prefix with terminal null nextCursor.

All16 list pages repeat in a distinct cold native process, while both threads
remain unloaded and before history hydration. Cold requests consume the
**original warm cursor bytes** and compare their own generated values against
them; stable row/cursor projections equal the warm values. Each captured request
and correlated native response retains the exact request ID/method/parameters.
Original histories, rollout bytes, config/catalog/source/provider journal and
all observed timestamps remain exact through retained-history checks. There
are precisely three inference requests and37 captured setup/list operations:
two thread starts, three turn starts and32 list requests, with no search request.
Owned close/reap precedes fixture removal. Existing deadlines, capture bounds,
native cleanup and process guardians stay unchanged.

## Why these branches do not repair created_at

The pinned recorder at `rollout/src/recorder.rs:2141–2173` serializes created_at
with Seconds but updated_at/recency_at with Millis. The helper at
`app-server/src/request_processors/thread_processor.rs:5902–5930` offsets the
row time by exactly1ms in the reverse direction. Parsing at
`thread-store/src/local/helpers.rs:130–142` and strict SQL timestamp predicates
at `state/src/runtime/threads.rs:1509–1542` preserve the latter branches' anchor
when native timestamps are distinct. Their order at1563–1591 uses the selected
timestamp; recency has a UUID tie-breaker, while updated does not. Ties remain
outside this fixture's independently checked preconditions.

Public cursor construction and sort selection occur at
`thread_processor.rs:2697–2736`; `thread-store/src/local/list_threads.rs:25–89`
preserves the actual native timestamp branch and opaque forward cursors.
`app-server-protocol/src/protocol/v2/thread.rs:1573–1578` defines opposite-sort
backwardsCursor semantics. All six complete causal files match the pinned
archive. The source report is
`/tmp/samgita-backwards-cursor-scenario-20261029-report.md`, SHA256
`6ff558a965348e217b608d24862386b79141227c700e6ebee9e0f00cf6d1ced7`.

The [original created_at failure](thread-list-fields-qualification.md) and
[integer section-rank evidence](section-rank-cursor-qualification.md) stay intact.
Nothing lowers their expectations, repairs upstream precision, changes native
state, edits histories or treats a smaller returned prefix as success. No
cross-wire/equal-hash field receives evidence.

## Focused verification

From `apps/samgita_codex_driver`:

```sh
devenv shell --no-tui -- mix format test/native_thread_sort_values_test.exs
CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl MIX_ENV=test ERL_FLAGS='+S 2:2' \
devenv shell --no-tui -- mix test test/native_thread_sort_values_test.exs --warnings-as-errors --seed 501432
```

Both cases pass, **2/0**, in5.8s. Log
`/tmp/samgita-reverse-timestamps-focused-501432-20261029.log` has SHA256
`d5a113b195c8956b60ea603f24a1be5e9005d8efcc43350ca578dd1f8a4823fa`.
Initial formatted test SHA256 was
`78654eb96bde87dc12938a065cc8f0b4697d892f2a9d0eeb5607f047e182eb39`.
The original case, assertion counts and helpers remain byte-identical;
the diff is insertion-only. No failed new native attempt preceded this pass.

The first combined run under
`/tmp/samgita-reverse-timestamps-combined-20261029` passed the first14 steps,
including main166/0 twice and extensions23/0 twice. Strict Credo then exited16:
the new zero-search assertion used `Enum.count(...) == 0`. It now uses the
equivalent `refute Enum.any?(...)`; the exact37-capture/32-list assertions and
all original code remain. This changes only a new assertion and removes no
expected behavior. The original failed log remains at `strict-credo.log` in
that directory. Dialyzer/assets were not reached in that attempt.

An additional scoped Credo command omitted `MIX_ENV=test` and entered the
unrelated dev build, failing during telemetry_metrics type checking with a
badarg decoding a dependency BEAM. Its log is
`/tmp/samgita-reverse-timestamps-credo-repair-20261029.log`. No dependency,
dev-cache cleanup or source workaround was attempted. The corrected command
uses the runner's verified `MIX_ENV=test ERL_FLAGS='+S 2:2'` environment; its
outcome and the final full rerun are recorded below. Scoped Credo passes with
no issues in the corrected environment; its log SHA256 is
`8e3b13c8a23a0cfb8d0b06fcfed58269b94d1e0d55cf8b668d3b7a45d60cad81`.
Final test SHA256 is
`647613fa30431fec8e1f58c08bec62bc18c9a09b811a7ab8072afbad05d8007c`.

The reviewed ordinary runner adds this two-case functional module only to its
extension selection, increasing21 to23 cases under the unchanged120s bound.
Main166-case argv/count/bounds and every previous selected profile stay intact.
The final combined-source qualification below passes independently of the
earlier focused result.

## Final combined-source functional qualification

```sh
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py \
  --output /tmp/samgita-reverse-timestamps-combined-corrected-20261029
python3 -B /tmp/samgita-reverse-timestamps-final-binding-20261029.py
```

All17 reviewed steps pass against **1,762 identical before/after guarded
hashes**, fingerprint
`002e2b73ddfb71efa25967d7749a9d822f1dd3fe0892b3a1f5f74a0b1dc10f9b`:

| Check | Final result |
| --- | --- |
| Existing main native selection, seeds501432/987654 |166/0 each;298.407s/286.608s, original320s bounds|
| Ordinary extensions including both timestamp cases, same seeds |23/0 each;40.485s/40.435s, original120s bounds|
| Three selected WebSocket overflow/replay cases |All three recorded seeds pass; each reports16 tests,0 failures,13 excluded|
| Retained stdio-owner cleanup |4/0|
| Actual-binary outside consumer |1/0, isolated from umbrella dependencies|
| Driver/root compile and format, inventory consistency, strict Credo, Dialyzer, assets |All exit0|

The final binding verifies exactly one supplemented physical contract,5702,
with unchanged missing state and requirements. It compares the original test
byte-for-byte through insertion-only reconstruction:177 added lines, all old
code preserved. Six causal source files and the exact node match the immutable
archive/schema. Every prior main argv/deadline stays exact; only the new
two-case extension and its expected count are added. All1,759 other guarded
hashes match the preceding successful functional source. No runtime, schema,
dependency, database safeguard or shared cleanup code changes.

| Artifact | SHA256 |
| --- | --- |
| Final `results.json` |`1b38f16cb3d65941d69a5d6c51748527d5753135c1a58d2e1ca12c1ce4f09a04`|
| Final `source.json` |`d9c9aa4e33cf3fdf73844a47fd20795e1020038872bd14c0271384c1ee07ff08`|
| `/tmp/samgita-reverse-timestamps-final-binding-20261029.json` |`e76e24f86d3ee92cabe991c13b37a756cb4f4654195c08c75336eff439dda152`|

The separate required completeness command
`python3 -B scripts/codex/inventory.py --check --require-verified` exits **1**:
unverified requirements remain. Its original log
`/tmp/samgita-reverse-timestamps-completeness-20261029.log` has SHA256
`8c14de37787f2fa05e8a25dbe96cc1932f9d716f451c257ce98ba73ecbeea0cd`.
This failure remains a required gate; the17 passing functional steps cannot
replace it. Counts stay **5,756 implemented /729 missing /136 blocked contracts**,
462 implemented/12 missing/11 blocked requirements and zero globally verified.
Next: bind the already inspected remaining output prerequisites without native
promotion. No fresh production assembly, package publication or deployment is
credited to this test-only change.

## Limits and rollback

Target is official `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Source archive SHA256 remains
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Physical owner5702 is `v2/ThreadListResponse.json#/properties/backwardsCursor`,
node SHA256 `d6254defacb7b4e783dae209de6bcd9708d18ac0776e1419de89138b182d07d5`.
Only its evidence/test/limitations lists gain supplements; its missing state
and all requirement/contract counts remain unchanged.

No security, credential, authentication, authorization, approval, sandbox or
permission test/audit is run. This qualifies selected frozen millisecond rows
on local Linux/stdio. Timestamp ties, concurrent edits, general repair/scan
semantics, other transports/OS/backend success, A11, prohibited/broad/hosted
checks, full compatibility and release remain incomplete. There is no
publication, migration or deployment. Rollback removes the added case/helpers,
its runner extension and field supplements; durable/runtime behavior is unchanged.
