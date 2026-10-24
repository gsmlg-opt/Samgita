# Native review delivery and persisted history

Scoped implementation evidence against stock Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, official Linux musl executable
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Eight actual-native cases pass at both recorded seeds. This does not qualify
review quality, a live model/backend, all review targets or full compatibility.

## Actual producer and independent oracles

The stock binary handles every request and emits every app-server message. An
owned Responses peer supplies fixed assistant text only. It replaces the
existing BEM fixture's provider before native startup; the unused realtime peer
must receive no traffic. The existing namespace, Unix WebSocket bridge, restart
and confirmed process guardian remain unchanged. Every case proves loopback-only
network isolation, no IPv4/IPv6 default route, no auth file or bearer, exact
request budgets, no tool invocation and no forbidden HTTP request. Only isolated
synthetic workspaces and local native history are used; no Samgita data changes.

- Legacy detached delivery starts a distinct child using the actual AgentRunner.
  The response is held until the native child introduction and deprecation
  notice are observed. The exact system review-agent prompt and inherited
  parent input reach the model. Full parent history remains equal before/after
  child completion and after confirmed native shutdown/cold restart. Child
  result, identities, completion and cold persistence are independently checked.
- Paginated detached delivery produces the exact `-32600` error and deprecation
  notice, with zero provider requests or execution lifecycle. This error does
  not qualify detached success in that history mode.
- Omitted, explicit null and explicit inline delivery each run in both legacy
  and paginated modes. Exact native entered/exited review markers, trimmed
  instructions, held-response barrier, original thread/turn association and
  completion are asserted. Cold native reads do not regenerate the result.
  Legacy persisted items equal the two exact review markers, including their
  live UUIDs; its entire warm/cold Turn must remain equal. Paginated history
  separately requires the exact assistant answer. Choosing `historyMode` needs
  experimental negotiation; `review/start` itself is stable at this pin.

Pinned source anchors:

- [Review dispatch](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/turn_processor.rs#L342)
  emits the detached deprecation notice; the paginated rejection is at1487,
  omitted/null defaults at1589 and real detached AgentRunner at1595 onward.
- [Legacy review processing](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tasks/review.rs#L145)
  intentionally suppresses the final assistant message in favor of review output.
- [Legacy history reduction](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/thread_history.rs#L1184)
  preserves review IDs and rendered review output. Its official test at1980–2027
  requires precisely the entered/exited marker pair.

## Retained failures, correction and checks

The first runner, `/tmp/samgita-native-review-delivery-20261024/`, stopped at
strict Credo before native execution: nested cleanup checks exceeded the depth
rule. The same await/PID assertions were extracted into a helper. The next
runner, `/tmp/samgita-native-review-delivery-v2-20261024/`, passed all static
checks but failed **three of eight** native cases at seed501432. All three
legacy inline cases incorrectly expected a persisted assistant-message item.
The actual complete item list contained the exact entered/exited review markers.

The correction follows the pinned reducers and their official test. Legacy
inline now requires the complete exact marker pair and full warm/cold Turn
equality; paginated and detached assistant assertions remain. The stronger full
parent-history equality, held response, cleanup guardians, all deadlines and
request/effect assertions are retained. No timeout increase, alternative-shape
fallback or assertion skip is used. Diagnosis and correction are retained as
`/tmp/samgita-review-delivery-legacy-oracle-{diagnosis,repair}-20261024.*`.

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-native-review-delivery-v3-20261024.py
```

That runner's matching directory records every command, exit and full executable
source snapshot, including untracked source. Compile with warnings as errors,
scoped format and root strict Credo (**415 files**) pass. Native seeds501432 and
987654 each pass **8/0**, no exclusions, in22.8/22.4s. The final source guard
matches. Both test and native/controller/namespace processes must finish with
confirmed reaping; evidence roots contain synthetic data and are retained.

| File | Final SHA256 |
| --- | --- |
| `native_review_delivery_profile.exs` | 61c14c4b4424824e39e134c70eff39bf0092ee8adbf0664300d4fbd7552e33d5 |
| `isolated_review_delivery_fixture.py` | c25f078f84824ddfe36b943e3dddc418784544b94b399f5acc791c2af1821c99 |

The initial index covers the positively exercised detached enum and two delivery alternatives;
these gain scoped implemented evidence: three exact canonical owners, with explicit
hashes and assertion references. Their final audit is
`/tmp/samgita-review-delivery-physical-owner-audit-final-20261024.json`, SHA256
`177343027b6ddf72be0317e065eb0b282bd83986a3f1bc7aa2d4af7a40ac76fd`.
No other target, nested payload, live review
quality, transport/OS, whole lifecycle or fully verified promotion follows.
The complete combined-source and hosted matrices remain required. A11,
upstream-unreachable production emitters and external/OS acceptance remain
incomplete. No release, publication, deployment or production migration occurs.

## Supplemental owner index

Five further missing physical notification owners gain scoped implemented
evidence from the same unchanged eight cases: the detached child's exact
`Thread.sessionId`, and the entered/exited review variant objects plus their
IDs. Native child identity is directly checked at 126–139. The three legacy inline
cases bind live marker IDs at 238 to distinct UUIDv7 values at 347–350, exact
three-field persisted maps at 354–357 and complete warm/cold Turn equality.
No paginated marker-ID check or uncalled `thread/items/read` owner is inferred.

The direct source hashes above match both 237-case isolated-profile repeats in
the [frozen 7a5de5e matrix](repair-qualification.md#frozen-local-matrix-at-7a5de5e).
This is an evidence-only index, not new runtime. Exact candidates/pointers/hashes
and exclusions are in
`/tmp/samgita-review-additional-owner-candidates-v1-20261024.json`, SHA256
`6bdef35e454696770f8ec27db1097b7a2d1562a2b649080c9dea052fda4f6705`.
No other bundled definition, global alias/enum, unasserted field, review quality,
external/OS success or whole lifecycle is promoted. Zero rows become fully
verified, and A11/full compatibility remain incomplete.

## Selective enteredReviewMode across native restart

An additive ninth case reuses the held inline-review provider and the existing
private namespace/UDS/restart guardians. A paginated persistent thread receives
the exact custom review request with padded input. Both actual entered-marker
notifications must have the prescribed type and trimmed review literal, one
generated UUID, matching thread/turn and exact started/completed timestamp
fields. Only identity/times come from observations; history supplies no expected
review text or item shape.

After explicit provider release and the native includeTurns store barrier,
`thread/items/read` must return one exact four-key entry with the independently
constructed marker. Duplicate IDs plus an absent ID return that singleton;
missing-only and wrong-turn queries return empty data. Following checked owned
restart, the first thread-content operation repeats these queries before
resume/read/history hydration. The loaded-thread list remains empty and the
complete provider request list remains exactly the original one. Existing safe
workspace, no-server-request, no-uncertainty and process cleanup assertions stay.

The pinned producer is `core/src/session/review.rs:164-171`; projection is
`v2/item.rs:1020-1023`; native history/store upserts are
`thread_history.rs:632-662` and `thread-store/src/local/thread_history.rs:433-460`.
`thread_processor.rs:3639-3669` filters by exact thread/turn/item identities.
This genuine cold selective-read case passes in the complete nine-file native
block61/0 at both fixed seeds; exact commands/source hashes are in
`/tmp/samgita-native-stop-cwd-authority-v2-20261025/`.
Five primary selected-response owners gain implemented evidence, zero verified.
Detached/legacy selection, all review targets, real review quality, other
OS/transports/services and A11/full compatibility remain unqualified.
