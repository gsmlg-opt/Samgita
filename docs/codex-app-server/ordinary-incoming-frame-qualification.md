# Original native question and MCP result frames

V394 starts from `6e41547df59baa62394ebb7239638c7eec28e1ac` on the existing
`main`. It strengthens the two ordinary scenarios bound by
[V392](ordinary-question-result-owners.md); no production code, schema, fixture,
configuration, lock or protocol contract changes.

Target: official Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The V392 nine-file immutable-archive/source and canonical-node evidence remains
applicable. This unit adds actual incoming JSON frame bytes to that evidence.

## Capture boundary and independent oracles

Both test transports observe original `{:message, encoded}` events returned by
`Stdio.handle_info/2`, before `Session` decodes them. A separate supervised
capture process has a distinct child ID; outgoing captures, indexes and counts
retain their original meaning. Successful captures return the same transport
events, state and order. Other events and transport failures retain their normal
delivery path. Each incoming ledger is bounded to **32 frames**, **65,536 bytes
per frame** and **1 MiB total**; exceeding a bound returns the explicit
`test_incoming_capture_overflow` error.

The [ordinary input-wait scenario](../../apps/samgita_codex_driver/test/native_search_input_wait_test.exs)
retains exactly one original `item/tool/requestUserInput` frame. Its full decoded
map and native request ID must equal the actual delivered request. The complete
capture remains unchanged through reply, resolution, turn completion and cold
readback. Independent literal question/options, opaque handle, original outgoing
reply bytes and digest, provider function output, histories and checked owned
process cleanup remain asserted. This is an ordinary choice question; it does
not exercise approval or permission behavior.

The [direct MCP scenario](../../apps/samgita_codex_driver/test/native_mcp_request_metadata_test.exs)
retains incoming native response frames. Each unique owned call ID must select
exactly one original frame whose complete decoded value equals its actual
response. Initialization IDs reused by different native generations are not
mistaken for duplicate owned calls. All eight genuine backend calls across warm
and cold processes keep their independently prescribed full results, top-level
`_meta`, backend params, startup negotiation and progress-token checks. Outgoing
bytes and existing cleanup assertions remain required.

Captured bytes are complete JSON frames **after JSONL delimiter removal** by
the transport. No claim is made about preserving OS read chunks or newline
bytes. Decoding the retained original bytes is distinct from re-encoding a
decoded map. Literal value and causal-effect oracles remain independent of the
new capture.

## Final-source functional checks

Environment: Elixir **1.18.5**, OTP **27.3.4.17**, `MIX_ENV=test`,
`ERL_FLAGS='+S 2:2'`, pinned `CODEX_BINARY`, no shared build/deps/partition
override. Ordinary native launches retain the fixed YOLO configuration. Only
the following six reviewed ordinary modules execute; there are no exclusions:

```text
test/native_mcp_request_metadata_test.exs
test/native_search_input_wait_test.exs
test/native_plugin_search_scope_test.exs
test/native_local_plugin_filter_values_test.exs
test/native_thread_service_name_test.exs
test/native_creation_snapshot_notification_test.exs
```

From `apps/samgita_codex_driver`, `mix format --check-formatted` on those files,
`mix compile --warnings-as-errors`, and `mix test <six files>
--warnings-as-errors --seed 501432` / `--seed 987654` all pass. Each test command
reports **6 tests, 0 failures**. Root `mix credo --strict` passes **554 files**;
offline `python3 -B scripts/codex/inventory.py --check` passes. The preceding
focused two-file run also passes **2/0**; it is not a larger-suite result.

Runner: `/tmp/samgita-v394-run.py`; exact commands, log hashes and results:
`/tmp/samgita-v394-functional-checks/final/results.json`; source guard:
`/tmp/samgita-v394-functional-checks/final/source.json`. All **389** guarded
sources remain identical before/after these checks. Exactly the two named test
modules differ from V390; the other **387** retain their bytes. Earlier
154-case results for the edited modules are historical and are not reused as
current exact-source verification. No aggregate, outside-consumer or hosted
rerun is claimed.

Final MCP/question test SHA256 values are respectively
`adb9b4bb9bbc61c66e34505ef86e29a9c43f04567df8ef8e41873b9010a22749` and
`8e48f7815d54d3ae21ad1282c1181031d94809e8bd19023d8763c9167fe45d31`.
Results/guard SHA256 values are respectively
`05026f91f7f08fa1c580752f9f64c5f44dc8660c182e1ee91645f8353b21bfb7` and
`aee7954fca681e1a0a9e02e6c1bd46f4ae33ba92144e99aab43941980ec9bb40`.
Binding program/evidence: `/tmp/samgita-v394-bind.py` and
`/tmp/samgita-v394-binding/evidence.json`.

## Evidence limits and continuation

Only owners **3155** (question text) and **4403** (top-level result metadata)
gain this additional evidence; both remain scoped **implemented**. Counts stay
**5,083 implemented /1,472 missing /66 blocked** schema contracts and
**462 implemented /12 missing /11 blocked** requirements, with **zero verified**
in both. Strict completeness remains failed. No alias, surrounding family,
other value/null/omission branch, transport, OS or backend inherits acceptance.

Security, credential, authentication, authorization, permission and approval
tests/audits, mixed broad suites and hosted workflows remain unrun under the
user's restriction. A11, unavailable upstream producers, real external/OS/
platform success and full-goal/release gates remain incomplete. No publication
or deployment occurs. Continue independently reachable ordinary native gaps;
source-proven unavailable branches remain open with their upstream evidence.
Rollback reverts these test captures and evidence records only; runtime behavior
and historical data are unaffected.
