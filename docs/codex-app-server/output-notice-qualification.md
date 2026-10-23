# Native output notice qualification

Source review began on main at 598cced78d4552134d464f2331228ce12f62fc46;
the coordinating agent advanced independent work to
4fb9125a5024236ee25738be98dac689ba47a8ab before the final draft checks.

Four cases passed twice against the actual pinned binary with a provider-only
synthetic SSE peer. They directly assert selected behavior for seven active
notices from immutable Codex
rust-v0.163.0, source 83086188ae0614bd882818ff1aa23f3194962012, binary SHA256
399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215.

## Owned reviewed installation

- /tmp/samgita-native-output-notice-lifecycle-test.exs, installed as
  apps/samgita_codex_driver/test/native_output_notice_lifecycle_test.exs.
- /tmp/samgita-output-notice-fixture.py, installed as
  scripts/codex/output_notice_fixture.py.
- /tmp/samgita-output-notice-qualification.md, installed in this documentation
  directory's output-notice-qualification.md.

Shared runtime, fixtures, config, schemas, manifests, CI, notes and Git remain
outside contributor ownership. Existing local-history and plugin-share work and
samgita-codex-repair-followup.txt are preserved. Parent source review approved
installation of these three files via apply_patch and subsequently granted the
exclusive native validation slot. That slot was released after validation and
actual owned-process shutdown.

## Pinned contracts read

Paths are relative to the pinned codex-rs directory.

- codex-api/src/sse/responses.rs:350–404,482–496 parses output item, summary
  part, summary/raw text and custom tool input events. Function argument delta
  events alone are ignored; the patch fixture uses custom_tool_call_input.delta.
- core/tests/common/responses.rs:866–929,1046–1055 supplies upstream reasoning
  item/text shapes and actual freeform apply_patch calls.
- core/src/session/turn.rs:2659–2663,2930–3012,3170–3267 requires an active
  streamed item for reasoning notices. Concurrent summaries plus an OpenAI
  provider selects a different done-event path. This profile disables that flag
  and uses a local non-OpenAI provider. Completed synthetic reasoning data is
  intentionally labeled; no real model's private reasoning is involved.
- app-server-protocol/src/protocol/event_mapping.rs:374–405,422–430 maps core
  events into plan/reasoning/patch notices with thread/turn/item/index payloads.
- app-server/tests/suite/v2/plan_item.rs:33–94,133–170 uses Plan collaboration
  mode, streamed proposed_plan blocks and a turn-ID-derived plan item. Only this
  selected fixture expects concatenated deltas to equal its final plan; clients
  must still treat completed plan items as authoritative.
- core/src/tools/handlers/plan.rs:83–98 rejects update_plan in Plan mode and
  emits checklist PlanUpdate otherwise. core/src/config/mod.rs:2766–2772 and
  config/config_tests.rs:611–630 require explicit tools.update_plan.enabled.
- app-server/src/bespoke_event_handling.rs:1278–1314 emits actual turn diff and
  checklist plan updates. Checklist response statuses are pending/inProgress/
  completed, distinct from provider tool arguments' in_progress spelling.
- app-server/tests/suite/v2/turn_start.rs:4080–4225 streams freeform patch input
  with apply_patch_streaming_events enabled and a model freeform tool catalog.
- core/src/tools/handlers/apply_patch.rs:83–145,153–207 parses incremental patch
  input, coalesces updates for 500ms and flushes pending data on completion.
  The test asserts the final selected patch update, without prescribing update
  count or intermediate batching.
- core/src/turn_diff_tracker.rs:122–181,309–399 renders final Git-style diffs,
  relative to the environment root and with full Git blob SHA1 IDs.
- core/src/tools/events.rs:599–650 supplies canonical completion/tracked diff.
  Those upstream tests and native functions were read, not run here.

## Four verified native cases

1. Active synthetic reasoning item emits two summary-part notices, three exact
   summary fragments with indices 0/1 and two raw fragments at content index2.
   Assert native thread/turn/item identity, all payload fields and lifecycle
   ordering around the reasoning item.
2. Plan collaboration mode streams a split proposed_plan tag and Unicode plan.
   Assert nonempty plan deltas, exact selected contents and turn-derived item
   identity, plus the authoritative completed plan item. No checklist notice is
   expected from proposed-plan text.
3. Ordinary mode runs only the built-in update_plan checklist tool. Assert exact
   explanation and three nonempty steps covering completed/inProgress/pending,
   correlated to the actual native turn. No proposed-plan delta is expected.
4. workspace-write/on-request mode streams a fixed freeform update patch for
   existing owned-notice.txt only. Assert patch update identity, exact final
   update kind/path/diff, actual canonical turn diff and completed native file
   change; prove the file remains regular, exact final bytes and untouched
   sentinel/directory membership. No shell or approval response is sent.

## Isolation and ownership

The new script reuses unchanged isolated_tool_interactions_fixture.run,
configure and isolation primitives, plus ModelFixture. It handles its own
namespace re-exec, then substitutes the provider/config/isolation functions in
memory only. No shared source is edited. The reused controller verifies the
pinned binary, starts a private Linux user/network namespace with loopback only,
starts actual native UDS and a loopback Responses provider, and owns cleanup.
An additional source assertion checks no IPv6 default route. Both namespace
proof and recorded process ownership are asserted by the native tests.

Native environment is allowlisted by the existing controller. HOME, CODEX_HOME,
TMPDIR, workspace, requests and provider event journal are disposable owned paths;
no real account, API key, proxy or remote service route is available. The static
model catalog avoids remote discovery. Plugins/apps/hooks/remote_models/shell
snapshot/concurrent summaries are disabled. The provider route admits only
/v1/responses, exact synthetic markers, at most one inference for text cases and
two for tool cases. The follow-up requires an actual native tool output.

Provider SSE is journaled before delivery and has only response.* events. It
never constructs app-server JSON-RPC or modifies native stdout. The native
Session connects to the actual borrowed UDS; an unexpected server request fails
immediately without approval. The patch text is a source constant containing one
relative fixed filename. A preflight rejects symlinks/nonregular source files or
changed initial bytes. No dynamic path/command comes from a request, and only
the scratch workspace is writable for the patch case.

Cleanup registration precedes initialization. Session cleanup closes only its
connection; the controller remains the owner of native resources. Controller
cleanup terminates/reaps native and closes both loopback peers. It joins the
provider/forbidden-peer serve loops; existing daemon request-thread semantics
remain owned by the reused fixture. The tests additionally wait for recorded
native/controller/namespace-owner PIDs to disappear. Both passing runs exercised
that cleanup, and the final audit found no owned processes or scratch directories.

## Deprecated non-emission boundary

app-server-protocol/src/protocol/v2/item.rs:1517–1529 explicitly documents
item/fileChange/outputDelta as deprecated and says the server no longer emits
it. No native producer was found by the earlier bounded audit. This remains a
visible source-defined limit; absence in four selected cases cannot establish
universal non-emission, and no positive native mapping will be fabricated.

## Validation and limits

The parent authorized installation and exclusive validation. Initial independent
compile/format/check passed; native seed501432 ran four cases in 7.5 seconds,
with three passes and one patch-case failure. Codex emitted three identical exact
turn/diff/updated payloads; the draft incorrectly required a singleton list.
core/src/tools/events.rs:639–649 emits after tracked patch completion, and
core/src/session/turn.rs:3300–3313 emits the retained diff at the end of each
sampling pass, including the tool response and final assistant passes. These
are repeated native snapshots of the same turn, not different file effects.

Repair1 replaces the unsupported cardinality assumption with a nonempty list,
exact equality for every complete thread/turn/diff payload, an explicit exact
final payload, and ordering of every diff before turn completion. All native
identities, indices, patch payloads, file effects and original deadlines remain.
The first command exited2; seed987654/root compile/Credo were not reached.
Initial log: /tmp/samgita-native-output-notice-initial.log. A /proc audit after
that run found no owned fixture/native processes.

Python AST parsing of the installed fixture passed without imports/startup;
all three installed-file whitespace checks passed. Shared model fixture
SHA256 a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8
and isolated controller SHA256
352752f306849a4a4f4e98ab2c8c4931e9ac9f64efbf532793891dcfacf01658
were recorded unchanged.

Repair1 completed with exit0, logged at
/tmp/samgita-native-output-notice-repair1.log. Through devenv shell --no-tui --,
MIX_ENV=test, and the pinned CODEX_BINARY:

- From apps/samgita_codex_driver: mix compile --warnings-as-errors;
  mix format test/native_output_notice_lifecycle_test.exs;
  mix format --check-formatted test/native_output_notice_lifecycle_test.exs:
  passed.
- From that independent driver: mix test
  test/native_output_notice_lifecycle_test.exs --include real_codex
  --seed 501432: 4 tests, 0 failures, 7.5 seconds.
- Same command with --seed 987654: 4 tests, 0 failures, 7.0 seconds.
- From repository root: mix compile --warnings-as-errors passed;
  mix credo apps/samgita_codex_driver/test/native_output_notice_lifecycle_test.exs
  --strict checked one source file with 69 checks and no issues.
- Final Python AST parse without importing/starting the fixture, whitespace
  checks for all three files, and pinned binary SHA256 passed. A final /proc
  audit found no owned processes and no owned runtime scratch directory.

Validation completed before releasing the exclusive slot. Parent integration
advanced HEAD independently to 83524e4a39ecaabe75e902346d9b0cca3e1da820 by the
post-run audit; shared/runtime/Git changes were not made by this contributor.

No additional indices, null checklist explanation, patch add/delete/rename,
batching guarantees, parallel turns, reconnect/filter profiles, platforms,
external providers, A11 or full compatibility are qualified. Sol repair rounds1,
unsuccessful repair rounds0, Astra rounds0 for this separate unit. Parent owns
all shared evidence promotion and publication.

## Manifest evidence mapping

The coordinating review checked final test/fixture hashes, every assertion
anchor, and six equality checks between exercised and canonical schema
definitions. Seven notice entries gain selected implementation evidence.
Forty-six positive contracts below gain evidence, of which 45 were missing;
none becomes verified. Anchors refer to `native_output_notice_lifecycle_test.exs`.

| Contract group | Positive contracts | Direct assertions |
| --- | ---: | --- |
| ReasoningSummaryPartAddedNotification | 4 | 81, 97–113: exact thread/turn/item IDs, indices 0/1 and lifecycle order |
| ReasoningSummaryTextDeltaNotification | 5 | 83–87, 97–113: three exact fragments and summary indices |
| ReasoningTextDeltaNotification | 5 | 89–98, 101–113: two synthetic raw fragments at content index 2 |
| PlanDeltaNotification | 4 | 123–140: exact plan item ID/contents and authoritative completion |
| TurnPlanUpdatedNotification | 4 | 149–157: exact thread/turn, explanation and three populated steps |
| TurnPlanStep/Status shared definitions | 5 | 154–157: step/status fields and all three native spellings |
| FileChangePatchUpdatedNotification | 4 | 173–190: exact identities and final streamed change |
| FileUpdateChange/PatchChangeKind in ServerNotification | 6 | 180–190: fixed path, hunk, update kind/type/variant |
| Same canonical definitions in ThreadItemsReadResponse | 6 | Same exact structure; no method execution inferred |
| TurnDiffUpdatedNotification | 3 | 194–216, 313–316: every complete retained snapshot and exact Git blob/hunk bytes |

`PatchChangeKind` update `move_path` is observed only as null in both canonical
definitions; those two fields remain missing. No add/delete/rename or populated
move target is inferred. Deprecated `item/fileChange/outputDelta` remains
blocked by its explicit upstream non-emission contract; the four negative
observations here cannot qualify native emission. This default-discovered test
is included by the hosted independent-driver step; local success does not
establish its hosted outcome.
