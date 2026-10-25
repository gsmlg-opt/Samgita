# Retained native client envelope and history owners

This evidence-only index adds93 precise implemented contracts, zero verified,
from the unchanged executable source of the
[terminal v21 matrix](repair-qualification.md#terminal-frozen-v21-local-matrix).
Stock Codex is `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The native driver passes700/0 twice; all49 isolated profiles pass280/0 twice,
seeds501432/987654. Both manifest-inclusive source guards match1,490 files.
No source/test/runtime behavior changes in this unit.

## Concrete operation owners

Eighty-four selected physical nodes belong to `ClientRequest.json` operation
envelopes, their exact `method` property/literal, or their `params` reference.
Only still-missing nodes are selected. Request-ID types and referenced payload
fields receive no inherited evidence. Positive calls have independent native
state, effect, history or provider-input oracles; generic forwarding is not the
oracle. All these existing cases use explicitly owned Linux stdio sessions.

| Owning test | Selected operations | Added owners and independent oracles |
| --- | --- | --- |
| `native_thread_future_settings_test.exs` | `thread/settings/update` | 4; applied-settings barrier, active turn retains A and next provider request captures B |
| `method_families_test.exs`, `native_thread_event_lifecycle_test.exs`, `native_organization_lifecycle_test.exs` | `thread/unarchive` | 4; restored listing/state and preserved native identity/history |
| `native_thread_list_fields_test.exs` | `thread/list` | 4; independently prescribed selected/excluded thread identities and fields; known created-at cursor defects remain unqualified |
| `native_history_cursor_semantics_test.exs` | `thread/read`, `thread/items/list`, `thread/turns/list` | 12; independently recorded turns/items, exact view and ordered pagination oracles |
| `native_turn_steering_test.exs` | `turn/steer` | 4; exact continued provider input and original turn association |
| `native_approval_lifetime_test.exs` | `turn/interrupt` | 4; original turn interruption and stale interaction rejection |
| `native_projects_test.exs` | `project/create`, `project/update`, `project/move`, `project/delete`, `project/list`, `project/read`, `project/import` | 22; known names/roots/metadata, notifications, independent SQLite/cold persistence; read/import add only their still-missing envelope |
| `native_organization_lifecycle_test.exs` | `threadSection/create`, `threadSection/update`, `threadSection/delete`, `threadSection/list`, `thread/section/move`, `thread/readState/update` | 21; known section/thread identities, ordering and persistent state; readState adds only its envelope |
| `native_thread_event_lifecycle_test.exs` | `turn/start` | 4; actual native turn/item events and durable outcomes |
| `filesystem_lifecycle_test.exs` | `fs/createDirectory`, `fs/getMetadata`, `fs/readDirectory`, `fs/watch`, `fs/unwatch` | 5; independently owned filesystem state and bounded local watcher observations; only envelopes were missing |

No method gains a whole-family or full transport qualification. In particular,
watch/unwatch observations do not promise arbitrary OS watcher semantics,
unarchive does not prove every lifecycle branch, and positive reference use does
not prove every referenced optional/default/null field.

## Typed supplied history

Nine other exact `ClientRequest.json` owners use the existing
`native_default_gates_profile.exs:511` supplied-history test over the real
native Unix WebSocket. Its `thread/resume.history` is a typed user
`ResponseItem::message` with one `ContentItem::input_text`, containing the
independently prescribed Unicode marker `Owned supplied history λ`.

The complete independent oracles are at541–698: exact outgoing params;
new durable thread identity rather than the supplied source ID/path; exact
JSONL response item; a single explicit next turn containing the marker once;
unchanged source history; cold retention and zero automatic execution.
The selected owners are:

- `ResponseItem/oneOf/1` and its `content`, `role`, `type` and `type/enum/0`.
- `ContentItem/oneOf/0` and its `text`, `type` and `type/enum/0`.

These paths are under `schema:ClientRequest.json#/definitions/`. Optional
message members are absent. No opaque inject route, encrypted content, reasoning,
agent-message input, media input, alternate transport or buffer boundary gains
evidence from this case. Its configured defaults are not boundary tests.

## Exact provenance and checks

Each manifest row retains its own ID, pointer and schema subtree hash. Three
source-only audits are bound to the matching passing frozen runtime hashes:

| Local audit artifact | SHA256 |
| --- | --- |
| `/tmp/samgita-client-request-positive-envelope-audit-20261025.json` | `b081553a505a14dbfebdf5b3666aa5b9e903dc4f92fef53fc571828602553a49` |
| `/tmp/samgita-additional-client-request-positive-owners-audit-20261025.json` | `44ad4a1a8d2301eb96298482c07b258d43449567da7f0be894eee9b2bc36553e` |
| `/tmp/samgita-client-history-content-owner-audit-20261025.json` | `0bbe090cd14e7c90b67c4fd96c4fa74d222ad3848b4a672f39726b9f4372ca9d` |

The bounded generator checks every available preimage and runtime-source hash,
93 unique missing IDs, exact pointer/hash and the expected full resulting JSON.
Complete-object patch hunks include owner identity and are sorted in physical
file order. The initial unsorted patch is rejected without changing the file;
the sorted patch is checked against the generated complete expected manifest.
An initial verification script used the nonexistent `requirements` key; the
corrected check compares every non-`schema_contracts` section unchanged. Neither
tooling correction changes a coverage criterion or native assertion.

Resulting ledger:485 requirements,462 implemented/12 missing/11 blocked;
6621 contracts,3492 implemented/3129 missing; zero verified. `inventory.py --check`
and all37 inventory regressions pass; `--require-verified` still exits1. The retained
populated GitHub-page failures, mandatory completeness failure, A11,
source-unreachable production emissions and external/OS success remain open.
No publication, release, deployment or production migration occurs.
