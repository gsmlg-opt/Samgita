# Ordinary executor skills, feedback context and native echo

This checkpoint uses unchanged stock Codex `rust-v0.163.0`, commit
`83086188ae0614bd882818ff1aa23f3194962012`, Linux-musl binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
It follows pushed checkpoint `a2a11af`. The complete compatibility goal remains
active. Fixed owned launches use `approval_policy="never"` and
`sandbox_mode="danger-full-access"`; no security, permission, authentication,
authorization, approval or audit checks are selected.

## Required executor catalog and explicit replacement

One real app-server registers one real owned exec-server with
`skills: {required: ["owned:review"]}`. A thread selects an owned populated
content root. A passive bounded observer forwards the original WebSocket bytes
and records only real filesystem method/path calls: traversal, namespace read
and SKILL read. Actual model input must contain the literal qualified catalog
name and description, and one prescribed prompt. A fixed local Responses
dependency supplies the first assistant message; the native turn must complete.

The second explicit registration replaces the same environment ID with
`skills: null`. A fresh thread selects a different valid empty content root.
Actual traversal, absence of the previous catalog entry, the second prescribed
prompt/assistant result and successful native completion prove that the old
requirement did not survive replacement. An empty root without clearing the
old requirement could not reach this inference under the pinned required-skill
validation. Neither skill execution nor the missing-skill rejection path runs.
Empty discovery returns before namespace reading, so only populated-root
namespace reading is asserted.

The client supplies the actual public executor URL before normal schema
validation. Opaque connection bootstrap is added internally by the fixture;
only id/method/environmentId/skills are journaled. This cannot qualify a complete
credential-bearing request envelope. Exactly two registrations, two threads,
two explicit turns and two model requests/responses are required. Original
typed IDs, native lifecycle associations, unchanged files, idle driver state,
closed sockets/workers/Ports and reaped owned children remain checked.

Pinned source: `environment_processor.rs:22-28` normalizes null to an empty
required list; `exec-server/src/environment.rs:570-584` replaces the same-ID
manager entry. `environment_selection.rs:1222-1246`,
`ext/skills/src/required.rs:15-57` and `session/turn.rs:535-546` validate actual
availability before inference. `provider/executor.rs:86-139` and
`loader/environment.rs:113-199` implement genuine executor discovery;
`render.rs:196-265` renders its catalog. Roots identify discovery content.

Only physical owners **3899/3900**, the selected object/null skills variants,
gain implemented credit. Omitted/empty lists, invocation, old-thread captured
state, other roots/platforms/transports and live services remain unqualified.

## Feedback from actual persisted turn context

One real paginated thread starts one explicit assistant-only turn against an
owned Responses dependency. The test checks actual provider input, assistant
output and the native persisted SessionMeta/TurnContext. A real
`thread/read(includeTurns=true)` is the source-backed persistence barrier; no
rollout is seeded or rewritten by the fixture.

Two explicit `feedback/upload` requests, integer `-1` and string `"-1"`, select
that actual thread and turn. The owned peer consumes original native Sentry
Event envelopes before returning HTTP200. Independently parsed bodies must
contain distinct report identities, prescribed ordinary tags/reason, the actual
thread/turn/model and the fixed normalized prompt hash
`89d3502a7c23cdd91d264767194cdda94c703bcadc54ca929b6b49832ecccb32`.
The hash comes from independently literal base text with doubled space, CRLF,
tab and Unicode, not returned history or client-supplied prompt_hash.

The pin hardcodes its HTTPS Sentry destination. The fixture uses the official
upstream test's loopback CONNECT/custom-CA process setup; it opens no remote
forwarding socket. TLS/headers/authentication/permissions are not asserted.
`includeLogs=false` and omitted extra files mean exactly two Event uploads and
zero attachment items. Native app-server messages are never manufactured.
HTTP acceptance does not establish real Sentry persistence.

`feedback_processor.rs:90-113,275-311,395-421` selects real persisted metadata,
uploads and returns after success. `core/client.rs:996-1005` renders base text
as a developer input fragment; `codex-api/common.rs:276-303` has no top-level
instructions field. `protocol/models.rs:1649-1667` and
`core/config/mod.rs:4125-4127` preserve explicit base text with custom provenance.
`thread_processor.rs:3164-3173` and `thread-store` standard persistence complete
before paginated history returns. `feedback/src/lib.rs:61-62,613-679` and
`upload.rs:27-100` bind the real fixed destination and uploader.

Stable schema root90 equals experimental root150. Selection uses exact method,
not an assumed shared array index. Only root150 owners **1038-1042**, ordinary
tags/threadId owners **3992/3993** and non-null promptHash owner **3994** gain
implemented credit. Root149 is `account/sendAddCreditsNudgeEmail` and receives
none. Logs/attachments, failure profiles, arbitrary tags, cancellation/restart,
real remote storage and other platforms remain unqualified.

An explicit atomic close control lets the helper reap native, join readers and
close both peers before Session.close invokes its retained group owner. Both
normal and assertion-failure cleanup use this barrier and keep the original
driver fallback. No process-owner implementation or deadline is changed.

## Shipped experimental diagnostic echo

The official `mock/experimentalMethod` is shipped unconditionally, despite its
test-only purpose comment: `common.rs:1217-1223`,
`message_processor.rs:1638-1641` and `catalog_processor.rs:506-513` provide the
actual route. Four ordinary calls preserve Unicode/newline, empty string,
explicit null and omitted value with independently exact expected results.
Original outgoing/incoming bytes and numeric/string IDs must agree across
eleven envelopes and ten exchanges. No fake app-server or permission-gating
test is involved. Only root126 owners **899-903** gain implemented credit; this
diagnostic method establishes no other native emission path.

## Development evidence

Source review corrected three draft assumptions before execution: missing
required public execServerUrl, a nonexistent provider instructions field and
close-before-owned-cleanup ordering. The first focused run then fails on the
omitted custom provenance in its expected persisted object (**4 tests, 1 failure**); the exact
upstream object is now asserted. The second fails before upload on assumed
stable root149 (**4 tests, 1 failure**); exact-method selection and correct root150 evidence
repair it. Both failures and original assertions are retained as evidence.
No assertion removal, timeout increase or retry-until-green is used.

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-ordinary-environment-feedback-echo-focused-20261028.py
```

The corrected focused selection passes **4/0 at 501432 and 987654**, in 7.6/7.7s.
It includes the existing ordinary initialization case unchanged. All 28 complete
production source files match archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`,
and all 15 selected physical node hashes match their actual experimental schemas.

| Evidence | SHA256 |
| --- | --- |
| Source binding JSON in `/tmp/samgita-environment-feedback-echo-source-binding-20261028.json` | `6739b6b5ce866417bd2ae25fae16d3c5265dfad868eabe8657731bcee001974d` |
| Original provenance failure log | `a180880d9337c593ce6cd544bf5eb43c5273805ff28bde230377578392090ca9` |
| Original schema-index failure log | `7f06f59a0b3874b6895056549ccacc2966820279cbd86acdf7145ade83875add` |
| Corrected focused seed501432 log | `495d91921901d35e58e79890fdfaee83cf989a5eecc986acd86db41f4e1a5584` |
| Corrected focused seed987654 log | `1d31f268874f2e9417385aa682f8cd2614ded583ccf14046367417d408515886` |

Final combined-source functional checks pass below. The manifest contains
**5,629 implemented / 856 missing / 136 blocked** contracts and **462 implemented /
12 missing / 11 blocked** requirements, **zero globally verified**. No alias,
policy field, inaccessible emitter or whole-family credit follows.

## Final combined-source functional qualification

All **14 reviewed functional steps** pass on the frozen integrated source:

```sh
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py \
  --output /tmp/samgita-ordinary-environment-feedback-final-20261028
python3 -B /tmp/samgita-environment-feedback-final-binding-20261028.py
```

The **85 files / 150 actual-native cases** pass at seeds 501432 and 987654,
in 258.9/258.7 seconds. Three selected WebSocket overflow/replay cases pass at
455834, 501432 and 987654; thirteen other mixed-file cases remain excluded.
The outside-umbrella real-native consumer passes **1/0**, seed 322980.
Driver/root warnings-as-errors compilation and formatting, inventory consistency,
strict Credo across 616 sources, Dialyzer and assets pass. No prohibited test,
audit, broad suite or hosted workflow runs.

All **1,716** guarded source hashes match before/after and the final binding.
Four helper/test files are new. Only the existing initialization test, manifest
and selector differ among prior guarded sources; **1,709** prior hashes remain
exact. Removing the two added file arguments leaves every prior command exact.
Independent review and final metadata comparison confirm exactly 15 physical
state changes and six existing requirement supplements; every root149 owner
remains unchanged and missing. Prior assertions, fixtures, deadlines and
process-owner behavior remain intact.

| Final artifact | SHA256 |
| --- | --- |
| Evidence `results.json` | `d8152c3e48eed714f26364d47b826d09f45766a6b07732e348d819ffb4831994` |
| Evidence `source.json` | `7c26300f3e883a271658af894efb196ec9a1b94128db531b044e90f52fc1f674` |
| Final binding JSON | `b238797242d41655d964a1ae84bc7c375533bf13788c682637d7112cedc9916e` |
| Independent integration review | `872d17614177fc968d75f7adb15ff311c3e6a961ba1d01a0480121969410a991` |
| Reviewed source fingerprint | `353ec07f928efcae6f170a590602723a70951bfeaf9d0d22f31fbef12a6ee677` |

Next ordinary work is remote plugin-search limit effects and explicit-null
remote marketplace reads. Their reviewed scratch drafts remain unrun and
outside the repository; no compatibility credit follows from them yet.
Full/broad/hosted/prohibited gates, A11, unavailable upstream emitters, external
services and other OS success remain incomplete. Database recovery is not rerun.
No package publication, release, tag or deployment follows from these local tests.

Rollback removes the two new test/helper pairs and the added echo case, restores
only these 15 manifest states/six supplemental requirements and prior selector
arguments/count/fingerprint. No platform schema, data, migration, credentials,
external endpoint or prior cleanup/replay/recovery behavior changes.
