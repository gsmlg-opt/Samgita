# Ordinary server-request envelopes and external time

V543 uses real Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux-musl executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Only local model/MCP dependencies are fixtures. No Samgita platform, external
account or paid task is involved. Owned launches retain fixed YOLO setup;
security and permission-related tests remain excluded.

## Exact envelope evidence

| Physical owners | Real behavior and original-frame binding |
| --- | --- |
| 3171, 3173, 3174 | The unchanged ordinary question case joins original incoming bytes and ID to its literal question/options, exact outgoing answer, provider-consumed tool output, resolution and retained cold history. Existing original-frame and question-result qualification supply the evidence; no duplicate scenario is added. |
| 3176 | A small assertion in the new form-values case checks the exact ID/method/literal params root and its selected schema branch against original native bytes. Independent MCP peer/provider consumption, false/zero/empty values and unanswered-form interruption remain required. V539 stays unchanged. |
| 3186, 3187, 3190 | A small additive assertion in the active-injection case joins the original incoming dynamic request to the delivered request on the same connection, then validates its exact selected root. Existing literal arguments, exact reply bytes, provider consumption, FIFO persistence and interrupted cold recovery remain intact. |
| 3201 | Two new ordinary-only cases drive genuine external-clock requests with experimental negotiation false and true, complete original frames and provider effects. The mixed server-interactions module is not executed. |

The ordinary question and dynamic evidence is exercised again in the reviewed
combined selection. These are eight specific physical owners, not alias,
parent-family or global verification. No assertion, lifecycle or bound is
removed from the existing cases.

## External-clock failure, diagnosis and repair

The initial new test assumed a first turn needed one clock response. Both
negotiation profiles failed at their unchanged **5-second** completion deadline:
**5 tests / 2 failures**, seed501432. A failure-only diagnostic retained original
frames before owned cleanup. The clock-only reproduction failed **2/2** at the
same seed: each connection had distinct request IDs0/1, only ID0 answered and
**zero provider requests**. No late model response caused this failure.

Exact pinned source establishes three sequential awaited reads:

1. Initial context construction calls `build_world_state_for_step`, which reads
   the external clock for the environment date.
2. `session/turn.rs:528` records the current-time reminder, awaiting another read.
3. `session/turn.rs:535` rebuilds the step world state, awaiting its environment
   date read before comparing the rendered state.

The relevant immutable callsites are
[`world_state.rs:267`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/session/world_state.rs#L267),
[`time_reminder.rs:173`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/session/time_reminder.rs#L173)
and [`turn.rs:528`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/session/turn.rs#L528).
The initial independent source review missed the environment-date reads; its
zero-findings record is superseded by the diagnosis, not erased. Environment
dates use local time; the reminder uses UTC. No assertion conflates them.

The corrected test answers exactly three distinct requests once each. Before
each response, the actual provider request count must still be zero. All six
original request/reply frames must alternate in order with exact IDs and values.
Only then may one provider request contain the independently authored
`It is 2026-06-17 17:34:15 UTC.` reminder and the native turn complete. Native
requests come from the stock app-server; the helper emits only assistant
Responses data and overrides both generic fixture dispatch methods.

All three response digests remain `sent_unconfirmed` in the driver. The test
observes provider consumption without inventing a transport ACK or
`serverRequest/resolved` notification. A late handle sends nothing. Native and
provider owners/Ports/PIDs must stop before fixture removal; the workspace stays
empty. The 60-second case, 5-second observable/RPC deadlines, 128-frame / 2 MiB
capture and 64 KiB frame bounds remain unchanged. No production driver change
was needed. Strict Credo's explicit-try finding was fixed with an implicit
function rescue; failure diagnostics still unconditionally re-raise the
original assertion.

## Focused and source evidence

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-v543-repair1-focused.py
python3 -B /tmp/samgita-v543-v544-source-review.py
```

The focused recipe runs the active-injection, form-values and ordinary clock
files: **5/0 at seeds501432 and987654**. Final combined-source qualification is
recorded separately below. Parent source binding verifies **58 unique complete
official files** across the envelope, clock diagnosis and persisted-status
investigation. An extraction-key mismatch in the first parent binding script
was corrected; it affected evidence parsing, not runtime assertions.

Seven selected envelope nodes match the archived stable export. CurrentTime's
experimental node is absent from that archive export: its retained complete
file instead matches immutable native-generation provenance, SHA256
`3d7bc481f84dc042984a74420e65c5a8d3c423f37a91b7d5df2365c903a12ac6`,
and the actual pinned Rust method/params/response/constructor. No archived
experimental-root equality is invented.

| Artifact | SHA256 |
| --- | --- |
| `/tmp/samgita-v543-source-evidence.json` | `60f3b1bcff1f019b6221812c00ffcaa91b580ec679ecff3122d61864099b3229` |
| First failed focused run | `5060eea534c271ccc14da38b9f2cfadb6f18f02682640234b7fcc450fd2677ca` |
| Original-frame diagnostic reproduction | `bcae1815907917bc1a1b0ac5d735161b4b5d37b8c88d0c5b272312f17ca6a66c` |
| Clock source diagnosis JSON | `24904ab60374a4a477dc719a0f243a1ccb7239de1f70ead01568c4a0f8be17c8` |
| Corrected independent source review | `92363d490882dc127615fcf4fa8e5bbd02f2d248e53793519b04c10da6e9e6fb` |
| `/tmp/samgita-v543-repair1-focused-501432.log` | `d35f4f736d5ab3c7818fe96854bf3d0f79b186acd90e26bea7ae6489ae5d7dfb` |
| `/tmp/samgita-v543-repair1-focused-987654.log` | `6d19e6e3a7df15d0ab1743ce8f39675e1d6c3b60653113f2da3661d09e100d83` |
| `/tmp/samgita-v543-v544-parent-source-binding.json` | `ffa306ec7abc0fa79a60373c61a21e59bbee3528b4f8be6b933c8e65a7444685` |

## Final combined-source functional qualification

V541–V544 complete all **14 reviewed steps** on unchanged combined source:

```sh
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py \
  --output /tmp/samgita-v541-v544-ordinary-final-20261028
python3 -B /tmp/samgita-v541-v544-final-binding-20261028.py
```

The **79 files / 143 real-native cases** pass at seeds501432 and987654.
Three selected neutral WebSocket overflow/replay cases pass at455834,501432
and987654; the other thirteen cases in that mixed file remain excluded. The
outside-umbrella consumer passes **1/0**, seed529998, using the pinned binary.
Driver/root warnings-as-errors compile, formatting, strict Credo across610
sources, Dialyzer and assets all pass. No audit, broad/hosted suite or
security/permission-related test runs.

All **1,705** guarded sources match before/after and final binding. Four
test/helper sources are added; only active-injection assertions, the manifest
and reviewed selector change among prior sources. All **1,698** other prior
hashes and every previous command remain exact after removing the two new test
arguments. Independent final source review finds no concrete behavioral defect;
SHA256 `ae4188a0f43e51041d84e545dcdd16e0502c6534a281ebf083c0647e6734cafc`.

The preserved cleanup repair also passes its separately source-reviewed ordinary
**3/0** regression file, seed455834, after the combined run:

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-stdio-cleanup-functional-20261028.py
```

This starts only an owned Python stdin reader, with no Codex, model, database
or permission interaction. It proves guardian waiting after linked Session
death, repeated normal/explicit close and owner shutdown during close. Original
assertions and deadlines are unchanged. It is process-cleanup evidence, not
native protocol compatibility evidence.

| Final artifact | SHA256 |
| --- | --- |
| Evidence directory `results.json` | `1a6cd855e482e48a4f502d6dd495faac3976ced0d635b1c27b9a1fc807dd474e` |
| Evidence directory `source.json` | `b1e767c583ba29b33bb1c5d91e91978c77276eb2f436ea016f1e4e2e599209be` |
| `/tmp/samgita-v541-v544-final-binding-20261028.json` | `50ca08effe50044d17150e82beaf497b5021bbfebd42bcefab9ca9c5ce338db7` |
| Ordinary cleanup result JSON | `5524d0a182558fb82de56ca058a2b5693ebeeccb93eab4405f4fd0004a48b9f5` |
| Ordinary cleanup original log | `da320b024106c151f0099e00322515f811feefde5fcdf146a9366513c79091cf` |
| Reviewed source fingerprint | `1607b290540b6a8d38001160fb9d7790a0a957da8a6e27df3dff0835289e0267` |

Only fifteen physical owners gain scoped implemented evidence. Six distinct
source-proven native-output requirements become blocked, including the five
[persisted in-progress leaves](persisted-in-progress-producer-boundary.md).
Counts regenerate to **5,594 implemented / 891 missing / 136 blocked** contracts;
requirements stay **462 implemented / 12 missing / 11 blocked**, both zero
globally verified. No synthetic stock emission or broader lifecycle, transport,
external/OS, A11, hosted, release or deployment acceptance is claimed. Continue
the reviewed AppsReadParams and fork-result drafts; they remain unrun and earn
no state credit from this checkpoint.

Delivery: source and evidence are committed as
[`a603b3f`](https://github.com/gsmlg-opt/Samgita/commit/a603b3fce7c5ccf21ac024d314d5cade7fbd5109).
HEAD, tracking ref and `git ls-remote` converged on that commit after push.
`[skip ci]` suppresses the automatic mixed matrix under the user's restriction;
the read-only Actions query returns zero runs for that commit. This is no
hosted pass, package publication, release or deployment.

## Rollback and limits

Restore the eight selected manifest rows, the additive dynamic assertion and
form envelope assertion; remove the ordinary clock test/helper and restore the
reviewed selector/fingerprint. No database or production resource changes.
Other clock values/errors, multiple subscribers, external sleep/polling,
OS/transports and backend profiles remain unqualified. Prohibited tests/audits,
broad/hosted suites, A11, unavailable emitters and full compatibility/release
gates remain incomplete. No publication or deployment is claimed.
