# Native thread and turn evidence audit

This audit indexes existing actual-binary assertions against immutable Codex
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012` and the
Linux musl binary pinned in [qualification](qualification.md). It changes the
evidence index, not executable behavior. The complete default driver suite
passed **343/0** at `513498` and `987654` at `bc437ca`; the cited test sources
are unchanged. Later native-profile additions still require final integrated
checks. No entry is marked `verified` by this audit.

## Directly observed methods

Paths in this table are relative to `apps/samgita_codex_driver/test/`.

| Native operation | Actual assertions | Source evidence and limits |
| --- | --- | --- |
| `thread/start` | Requested cwd/provider returned; returned identity drives an actual turn and its completion | `real_session_test.exs:65–83,172–186`; most helper options are constructed rather than independently qualified |
| `thread/read`, `thread/resume` | Persisted turn/content/client identity survives an owned native restart; explicit resume/read adds no model request | `turn_input_test.exs:35–68`; path/history/config override and paginated resume variants remain incomplete |
| `thread/list` | Archive/default visibility, deletion absence, native Project/section selection and durable read-state association | `method_families_test.exs:655–690`, `native_projects_test.exs:114–129`, `additional_method_families_test.exs:373–376`, `native_organization_lifecycle_test.exs:201–212`; cursor/sort/search/provider/source/ancestor combinations are not qualified |
| `thread/loaded/list` | Created persisted identity is loaded; an independent cold process has an empty loaded list | `method_families_test.exs:659`, `native_organization_lifecycle_test.exs:160,216`; pagination is distinct from `thread/list` and remains unqualified here |
| `thread/name/set` | Empty ACK followed by exact persisted name readback | `method_families_test.exs:642–646`; no name-notice, normalization or complete error matrix |
| `thread/unsubscribe` | Exact `unsubscribed` result; read-state notices cease and explicit resume restores the subscription | `method_families_test.exs:659–662`, `native_organization_lifecycle_test.exs:301–308`; other statuses and `thread/closed` remain unasserted |
| `thread/unarchive` | Returned identity matches and becomes visible in the ordinary list again | `method_families_test.exs:675–679`; the separate notification is not inferred |
| `thread/delete` | Empty ACK, list absence and native read rejection; no model execution | `method_families_test.exs:682–690`; deletion events and full loaded/archive combinations remain incomplete |
| `turn/start` | Returned identity joins native user-item lifecycle, captured provider request, completion and cold history; selected model/reasoning, context, causal IDs, metadata, tier and output-schema effects | `turn_input_test.exs:35–68`, `turn_overrides_test.exs:17–93`, `turn_parameters_test.exs:19–204`, `support/turn_fixture.ex:136–146`; this does not qualify every setting/input/environment/transport combination |
| `turn/steer` | Active identity stays one turn; accepted content/context/client identity and filtered metadata reach a later provider request and cold history | `native_turn_steering_test.exs:90–145,342–347`; idle rejection is not enabled success and only selected input variants are exercised |
| `turn/interrupt` | Submission ACK precedes observed matching interrupted completion and pending interaction retirement, with no extra model request | `native_tool_interactions_profile.exs:292–319,461–470`; explicit namespace profile evidence, no implicit retry, effect cancellation or Task acceptance |

The two request/response entries for each of these twelve operations gain scoped
`implemented` evidence. `turn/started` also gains directly correlated native
evidence. Existing `turn/completed`, `item/started` and `item/completed` entries
retain their prior status with these additional assertions. This is **25 newly
implemented entries**, with no full-verification promotion.

## Field and event boundaries

Sixty-eight directly asserted fields/branches gain scoped `implemented`
evidence. The manifest records the specific test and scope for each. These cover
selected request/result fields above, actual turn/item identity association,
canonical shared Thread identity/turns/name/fork parent, canonical Turn
identity/status/root, and `completed`/`interrupted` status variants.

Canonical schema definitions are shared across messages. Observing a Thread
shape in `thread/read` cannot qualify `thread/started` emission. Likewise a
returned final assistant message is not evidence of streamed deltas. The
ordinary model fixture emits `response.output_item.done`, without
`response.output_text.delta`. Item approval or timeline timestamps do not
establish notification `startedAtMs`/`completedAtMs` behavior. Unasserted
timestamps, fields, nullable alternatives and enum branches remain missing.

Nine notices have no direct assertion in these existing tests:
`thread/started`, `thread/status/changed`, `thread/name/updated`,
`thread/closed`, `thread/archived`, `thread/unarchived`, `thread/deleted`,
`thread/tokenUsage/updated` and `item/agentMessage/delta`. Their requirements
remain missing pending actual-native event journeys. Helpers collecting all
envelopes do not replace assertions about a particular native emission.

Pinned source references below are relative to `codex-rs/`:

- `app-server/src/request_processors/thread_processor.rs:671–693,762–779,1664`
  separates responses from name/unarchive/start notices.
- `thread_processor.rs:1034–1060` defines `notLoaded`, `notSubscribed` and
  `unsubscribed`; unsubscribe does not itself emit a closed notice.
- `thread_processor.rs:2887–2932` defines loaded-list ordering, insertion-point
  cursor semantics and minimum-one limit; no evidence is borrowed from the
  different thread-list API.
- `app-server/src/request_processors/thread_delete.rs:68` emits deletion;
  `app-server/src/thread_status.rs:244–247` emits status only on a change.
- `app-server/src/bespoke_event_handling.rs:155–184` clears the started Turn's
  items and sets `itemsView=notLoaded`; a later history snapshot is different.
- `app-server-protocol/src/protocol/event_mapping.rs:363–373` maps native
  agent-message content deltas and their identifiers.

## Qualification limits and next checks

The native process owns every app-server response. The deterministic loopback
Responses backend supplies only synthetic model dependencies and observes
requests; it is not an app-server substitute or a live inference profile.
The interrupt evidence additionally uses its explicit private-network profile.
No platform model, authorization, database, acceptance policy or credential
boundary changes. These operations remain under the existing project and
execution fencing when invoked through Samgita.

Next actual-native cases should directly correlate lifecycle notices, stream
Unicode deltas with exact thread/turn/item identity, distinguish per-connection
opt-out from missing emission, exercise loaded-list pagination and remaining
unsubscribe statuses, and preserve no-reexecution proof across cold resume.
Real external backends/accounts, other OS/transport profiles, A11 and absent
legacy production emitters remain incomplete. This evidence audit neither
publishes a package nor establishes full compatibility or production readiness.
