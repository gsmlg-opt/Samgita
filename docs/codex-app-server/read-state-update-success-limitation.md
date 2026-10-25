# Pinned read-state success response has no turn-position producer

Immutable Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, advertises a turn alternative for
ThreadReadStateUpdateResponse.readState.firstUnread but cannot produce it on a
successful update. This is source evidence of a target limitation. The four
exact contracts remain **missing**, with no runtime pass or scope exception.

| Physical owner | Pointer below /definitions/ThreadUnreadPosition/oneOf/1 |
| --- | --- |
| 5850 | the turn object alternative |
| 5851 | /properties/turnId |
| 5852 | /properties/type |
| 5853 | /properties/type/enum/0 |

All four belong specifically to v2/ThreadReadStateUpdateResponse.json. Their
same-shaped read/list/notification/error counterparts are different evidence
paths and cannot qualify this successful response.

## Complete production path

The pinned
[protocol declaration](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/common.rs#L864)
maps thread/readState/update to this response. The
[dispatcher](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/message_processor.rs#L1521)
calls its single handler. The
[state transaction](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/state/src/runtime/thread_read_state.rs#L86)
first checks the expected revision, then computes a new first_unread solely as
Read→None or Unread→Some(""). Its sole Applied constructor returns that newly
computed value with the new revision.

The handler's
[conversion](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_read_state.rs#L29)
maps None to firstUnread:null and the empty string to type:threadStart. Only a
nonempty stored turn ID could produce type:turn. The
[sole success-response constructor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_read_state.rs#L182)
uses the owned state returned by Applied. It sends a separate database-derived
notification first, but that query cannot replace or mutate the captured
success state. A concurrent attention event therefore does not open this path.

Nonempty turn IDs do enter durable state through
[terminal-attention publication](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/state/src/runtime/thread_read_state.rs#L48).
They can reach read/list snapshots, thread/readState/changed and
[conflict error data](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_read_state.rs#L191).
Conflict returns Err rather than the success response. Validation, unavailable
state and storage errors also cannot supply a successful turn alternative.

A global Rust source search finds only the handler's one production success
constructor and the state's one Applied constructor. The other production
database-update caller is
[revert cleanup](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L2311):
it uses Read and maps the outcome to a boolean, never to this response. Test
constructors and schema declarations do not create production emission paths.

## Evidence and remaining acceptance

All seven complete inspected production/protocol files byte-match source
archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
All four exact node hashes match inventory; response export SHA256
`1ba713b18c3c53c737d503bac5614f2bd35c2ab4d54a8090287555f77634bd0d`
matches pinned provenance. The full constructor-search command/output, complete
file hashes, exact nodes and original/current row bindings are in
`/tmp/samgita-v276-read-state-source/`. source-evidence.json SHA256:
`10ca36c3de25ea9449ab996f5f3b271434cf28f562764c18976d00ec4385eb83`.
The base repository commit is `15ca006`; independent source review agrees.

This documentation/evidence-only unit changes no executable, schema, planned
test, test result or contract state. Inventory --check passes. Totals stay
**4,729 implemented / 1,833 missing / 59 blocked** contracts and
**462 implemented / 12 missing / 11 blocked** requirements, zero verified.
The strict completeness gate still exits **1**. No runtime or security/
permission test runs for this unit. The unchanged executable source retains
the [44/0 twice functional checkpoint](shell-delta-identity-qualification.md);
those passes do not qualify the unreachable response alternative.

A complete acceptance claim would require an explicit decision on how the
immutable target contract classifies an advertised schema-only alternative,
or a deliberately revised upstream target with an actual producer. Neither
decision is made here. The schema remains accessible and retained; fixtures,
generic forwarding, another method's native output or an upstream modification
cannot manufacture acceptance against this pin. Continue independent reachable
ordinary functionality. Full compatibility, prohibited tests/hosted gates,
A11, other source-unreachable paths, real external/platform profiles and release
remain incomplete. No external repository, publication or deployment changes.
