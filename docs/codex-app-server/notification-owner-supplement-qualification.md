# Selected native notification owners

This source-attribution index connects fourteen previously missing physical
`ServerNotification.json` owners to independently prescribed native assertions.
It adds no runtime behavior and promotes no fully verified state. The pin remains
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, Linux
executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Each exact node/hash is checked against the owning experimental schema with the
inventory's canonical encoding; equal hashes do not transfer evidence.

## Eleven explicit-null rate-limit owners

The physical prefix is
`schema:ServerNotification.json#/definitions/RateLimitSnapshot/properties/`.

| Suffix | Narrow native oracle |
| --- | --- |
| `credits/anyOf/1` | Present null in the empty/malformed snapshot |
| `individualLimit` | Present null |
| `individualLimit/anyOf/1` | Null alternative |
| `normalModelSlug` | Present null |
| `planType` | Present null |
| `planType/anyOf/1` | Null alternative |
| `primary/anyOf/1` | Present null in empty/credits-only snapshots |
| `rateLimitReachedType` | Present null |
| `rateLimitReachedType/anyOf/1` | Null alternative |
| `secondary/anyOf/1` | Present null in empty/credits-only snapshots |
| `spendControlReached` | Present null |

`native_rate_limits_test.exs:13-24` prescribes the complete empty snapshot,
including every key explicitly set to nil. Cases152-185 supply selected sparse,
malformed or absent HTTP headers. The native notification assertion227-233
requires a nonempty result and strict equality of each entire actual envelope to
`%{"rateLimits" => expected}`. It rejects missing keys and invented nonnull data;
it does not merely access a potentially absent map key or copy another response.
`rate_limits_fixture.py` sends provider headers/data, never app-server notices.

Pinned `codex-api/src/rate_limits.rs:57-101` constructs this header snapshot;
`app-server-protocol/src/protocol/v2/account.rs:650-696` converts its optional
fields. `app-server/src/bespoke_event_handling.rs:1587-1612` emits the actual
account notice. Positive account metadata is not reachable through that header
parser. These nulls do not prove clearing/merging, entitlement, enforcement or a
separate WebSocket producer. All positive branches remain unqualified.

## Three synchronous hook-output literals

The physical prefix is
`schema:ServerNotification.json#/definitions/HookOutputEntryKind/enum/`.

| Suffix | Exact literal and independently expected native text |
| --- | --- |
| `1` | `stop`: `Owned synthetic hook stopped input` |
| `2` | `feedback`: `Owned synthetic hook denied input` |
| `4` | `error`: `hook exited with code 7` |

The original six scenarios in `native_hook_lifecycle_profile.exs` require four
correlated actual lifecycle notices for each trusted execution case and compare
the complete completed entries with fixed `expected_entries` constants. The
fixture supplies exit2/stderr, exit7 or `continue:false/stopReason`; it never
constructs hook notices. Native turn outcome, provider count and owned process
sentinels independently distinguish blocking, failing and stopping effects.

Pinned `hooks/src/events/user_prompt_submit.rs:184-190,228-248` produces those
three kinds; `app-server-protocol/src/protocol/v2/hook.rs:77-96` converts them;
`app-server/src/bespoke_event_handling.rs:1147-1165` emits the native lifecycle.
Async/builtin hooks, other handlers/sources, managed/project/plugin hooks and
broader failure/lifecycle behavior are not qualified by these literals.

## Provenance and verification limits

The read-only audit is `/tmp/samgita-contract-owner-next-audit-20261025.md`.
It recomputed the official source archive/binary hashes, matched all fourteen
exact physical nodes, and byte-compared the five cited production files to the
hash-matching source tar. The original owning tests/fixtures matched hosted
`589e02ffd96f7372b2d654835e8c0df0c183511b` when that audit ran. Subsequent additive
hook cases have their own execution evidence; this index does not retroactively
qualify them or alter historical hosted counts.

Existing two-seed native evidence is **6/0** per suite:
`/tmp/samgita-rate-limits-{501432,987654}-20261024.log` and
`/tmp/samgita-hook-lifecycle-{501432,987654}-20261024.log`. Their guarded scoped
runners also passed compile/format/strict Credo and namespace checks. The audit
itself ran no executable or database test. Full final-source matrices and hosted
checks remain required. Only the selected literal/null scope gains implemented
evidence; no alias, unchecked variant or whole lifecycle gains status. A11,
source-unreachable emitters and unavailable external/OS acceptance remain
incomplete. No publication or deployment occurs.

After the additive warning/context hook cases, the parent reran both owning
suites inside the full21-file native block: **127/0 at each fixed seed**, with
warning-free compile, format, strict Credo and unchanged source guard. Logs are
`/tmp/samgita-native-repair-continuation-v6-20261025/`; the exact hashes remain
in [repair qualification](repair-qualification.md#scoped-continuation-after-636b2ad).
This supplies current combined native evidence while preserving the historical
source-only attribution and all null/literal scope limits above.
