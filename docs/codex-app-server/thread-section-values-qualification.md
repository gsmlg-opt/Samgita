# Native thread-section values

Three functional cases qualify selected create/update/list/delete values on the
stock immutable `rust-v0.163.0` [pin](design.md), source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
This fills an evidence gap; no production driver defect was established.

## Explicit appearance-field continuation

The 2026-10-26 continuation sends `appearance:{icon:"star",color:null}`
immediately after restoring `folder/purple`. The next update omits appearance;
both native responses and independent lists retain `star/null`. That exact final
state also survives confirmed process replacement and paginated reads. Together
with the retained empty, partial and explicit `icon:null` requests, each field
has actual outgoing omitted/null/string coverage. Expected response nulls alone
are not counted as null inputs. The update sequence now has ten cases.

Exactly two shared request-definition owners, **667/668**, become implemented:
`ClientRequest.json#/definitions/ThreadSectionAppearance/properties/{color,icon}`.
The owning references are `ClientRequest.json#/oneOf/54` (create) and `/oneOf/55`
(update), through their parameter appearance object alternatives. Bounded capture
asserts the exact method and parameter map sent to the stock native executable;
the native persisted state supplies an independent effect oracle. Other schema
aliases and notifications do not inherit promotion. Schema identities/hashes,
requirements and all other contract records are unchanged.

All eight functional files in the [membership block](thread-section-membership-qualification.md#final-integrated-evidence)
pass **19/0** at both seeds 501432/987654, in **45.594/36.544** command seconds.
Format, warning-free compile, root strict Credo and the 231-file unchanged-source
guard pass. No deadline, helper, production source or retained assertion changes.
Exact commands/logs/source: `/tmp/samgita-v175-section-appearance-checks/functional/`.
Results/source SHA256:
`c903dabb51fbc0d8c6de4f7c79ee4fd6abca9d593a49f4aae5f684c5b489982c` /
`5154b50a69609d904fb61bf4e47ad940e26f30aa4edec0841dfe77120a9da86c`.
`/tmp/samgita-v175-section-appearance-checks/manifest-binding.json` binds the two
original/current records to this test source and evidence. Contracts become
**4,590 implemented / 1,972 missing / 59 blocked**; requirements remain
**462 implemented / 12 missing / 11 blocked**, zero verified in both.
The current user restriction leaves security/permission checks and related
broad/hosted workflows unrun. Full compatibility, A11 and release remain incomplete.

## Section-bearing notification gap

The bounded v174 source investigation retains owners **2704–2708** as missing.
Their only schema reference is `thread/started -> ThreadStartedNotification.thread
-> Thread.section -> ThreadSection`. Section create/update/delete and member
moves return results without emitting a section notification. Resume/reconnect
does not re-emit `thread/started` for an existing section member.

The three ordinary pinned production emitters are
[fresh start](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L1580),
[fork](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L5590)
and [detached review](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/turn_processor.rs#L1469).
Fresh builders set section to null; ordinary local fork metadata starts unassigned.
Their notification snapshots are constructed before their responses, so a later
move cannot refresh them. CRUD/move/read evidence is not notification evidence.
No injected message, fabricated state or timing race substitutes for a real emitter.

Thirteen relevant source files match the immutable archive in
`/tmp/samgita-v174-section-notification-gap/source-evidence.json`; the handoff there
records exact paths/lines and connection prerequisites. This is a bounded audit
of ordinary local paths, not proof over all alternative backends or deployments.
No deterministic supported producer of a non-null section at those emitters was
established. The five owners remain missing, without an upstream-unreachable,
blocked or implemented promotion. A future genuine producer must supply its
pre-emission section state and actual native notification evidence.

## Values, persistence and correlation

| Operation | Actual native evidence |
| --- | --- |
| Create | Omitted/null appearance produces null; `{}` produces `{icon:null,color:null}`; full/partial objects retain their explicit values. Names trim, generated identities remain distinct, and exact result wrappers match. |
| Update | Sequential cases distinguish omission preserving the prior value, null clearing it, and objects replacing rather than merging it. Identity remains stable, names trim, and an independent control section remains unchanged after every step. |
| List | Default/explicit-null cursor and limit produce the complete prescribed catalogue. Exact one/two-item pages, zero-limit normalization and every continuation/final null cursor follow native ID order. |
| Delete | Only the selected custom identity disappears. Repeat deletion/update returns the exact native not-found error without recreating it. Empty-name validation preserves other sections. Deleting remaining custom entries leaves the native built-in Pinned section. |

Each case repeats persisted results after confirmed native process replacement:
the old `/proc/<id>` disappears and the new public diagnostics PID differs.
The loopback model fixture receives **zero** calls throughout. No native history
is seeded, imported or fabricated. Bounded test-local capture preserves exact
owning-method parameter maps, including missing versus null. Successful and
error response IDs are checked; ready/pending/uncertainty/gap checks remain.
Existing helpers, driver source and deadlines stay unchanged. The built-in
section's restrictions and all security/permission behavior remain untested.

Pinned [protocol declarations](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/thread.rs#L1313-L1398)
define nullable creation and the update double option. The
[processor and projection](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_sections.rs#L30-L223)
return these native wrappers; the
[store](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/state/src/runtime/thread_sections.rs#L9-L92)
distinguishes preserve from replace, and
[pagination](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/state/src/runtime/thread_section_order.rs#L64-L100)
uses stable ID order. The v155 source map binds six upstream files to archive
bytes and retains all sixteen original manifest nodes/hashes.

## Original direct-owner checks

The final four-file functional block runs at seeds 501432 and 987654:

```sh
mix test test/native_turn_personality_test.exs test/native_turn_plugin_list_test.exs test/native_project_sort_matrix_test.exs test/native_thread_section_values_test.exs --warnings-as-errors --seed 501432
mix test test/native_turn_personality_test.exs test/native_turn_plugin_list_test.exs test/native_project_sort_matrix_test.exs test/native_thread_section_values_test.exs --warnings-as-errors --seed 987654
```

Both runs pass **12/0**, in 19.382/19.412 command seconds. Warning-free compile,
format, root strict Credo and the 227-file source guard pass. No failed runtime
attempt, timeout increase or retained assertion change occurs in this unit.
Results/source in `/tmp/samgita-v157-thread-section-checks/functional/` have
SHA256 `11a1829929378143448f1a408aa2959211f6dc1c94da82765c284d921c1f7c1a` /
`f98c11217b29eb8cf09c1070421f45babc31b027a466c2c1093862833ae3913c`.

Exactly sixteen direct parameter/result owners, indices **6200–6209 and
6213–6218**, become implemented. The three move/membership owners, shared
definitions, ClientRequest aliases, notifications and broader requirements do
not inherit evidence. Contracts become **4,566 implemented / 1,996 missing /
59 blocked**; requirements stay **462 implemented / 12 missing / 11 blocked**;
both remain zero verified.

This is Linux/stdio qualification with owned local Codex storage. Other
transports/platforms/backends, full lifecycle, real external services, A11,
full compatibility, publication and deployment remain incomplete. The user's
restriction keeps security/permission-related tests and workflows unrun.
