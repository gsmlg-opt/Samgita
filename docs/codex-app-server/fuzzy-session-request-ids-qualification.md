# Existing native fuzzy-session request IDs

V454 binds two independently supported string-ID fields at `main`
`d1eb4fbeded32580769341d41fb27748a1e23df9`. It changes no code, test, fixture
or runtime. Existing ordinary `native_fuzzy_notification_envelope_test.exs`
already generates each string ID before dispatch, captures original outgoing
and incoming bytes, matches the complete sent request/encoded bytes and exact
native response ID, and requires only id/result response keys. The seven RPC IDs
per owned profile remain distinct.

The two commands have separate positive oracles in one causal journey:

- sessionStart registers the supplied session ID and root in a genuinely new
  native scanner. Its ACK and initial scanner-idle notice alone are insufficient.
  A later query, which supplies no new root, returns three versus two exact
  golden matches from the two independently populated roots. This establishes
  the original root/session association.
- sessionUpdate sends the first nonempty `abe` query to that registered scanner.
  Exact independent paths, roots, scores 84/72/71 and character indices prove
  query application. The second root omits the first match and returns exactly
  the remaining two. Expected values come from pinned official golden data.

Only these `schema:ClientRequest.json#` fields gain scoped implemented evidence:

| Index | Pointer | Parent method | Parent node SHA256 |
| --- | --- | --- | --- |
| 1139 | `/oneOf/169/properties/id` | fuzzyFileSearch/sessionStart | `f6d914af07fbf72d33bd9fd1eeda028f5f553bd6cc81a4086b27b31d3c0ef1eb` |
| 1149 | `/oneOf/170/properties/id` | fuzzyFileSearch/sessionUpdate | `3c72b00ae80d41ef53e1a0fb09e4293da6de373227b95ba0f51d8b72e7428d06` |

Each field node SHA256 is
`f1fb3724bb7835add8ed79ef8a7e1acaf3c9c5761502e6ae54c85d0c7f6c82e7`.
Both physical fields, their separate parent hashes and method identities are
recomputed in the full canonical export. Equal ID hashes confer no sibling or
shared-type credit. Eleven RPC/declaration/dispatch/scanner/matcher/outgoing/
transport/oracle files match the official Codex `rust-v0.163.0` source archive
at `83086188ae0614bd882818ff1aa23f3194962012`. Actual start creates/inserts the
scanner before ACK; update looks it up and changes its query; real matcher
snapshots produce the notifications. Typed outgoing responses preserve the
original request ID. This is not a fake-server result.

The unchanged test SHA256 is
`7fcbee46a982832126b9d4a6dae546a925017ef9c754b181c4ebe986cebbf64f`.
All 417 V450 source hashes/nine successful logs remain exact; both reviewed
**58/0** ordinary command lists enable this file. All 825 V453 static source
hashes/four successful logs also remain exact. Those static hashes include the
current Python owner helper; they are separate from the narrower functional-run
source map. No new test/native run occurs. Existing 128-frame, 4 KiB outgoing/
64 KiB incoming, 1 MiB total, five-second RPC/notice and 30-second case bounds,
frozen inputs/config and checked native/owner/Port cleanup remain unchanged.
Inventory consistency and diff whitespace are checked after the binding.

Reports `/tmp/samgita-v454-candidate.md` and
`/tmp/samgita-v454-start-addendum.md`, SHA256 respectively
`2f955a0ec50f4121ef2bd55aff9e11d7bc9eaec4583854513d56716e1b302296`
and `030920bbcd084693b07344f25d7ff04cc559646015aef9d6abca34551b0d2c88`;
binder `/tmp/samgita-v454-bind.py`; source/node binding SHA256
`616247e6e173378d2564690092f0fd1a3ec0ce48eeb6c9f17a7b343a7e87f47b`;
evidence SHA256
`6a38e463763df268d70e1e46b663d7b83a2e395a68d525f40782b12a048e1604`.
[V450](filesystem-typed-id-qualification.md) and
[the static checkpoint](repair-qualification.md#permitted-static-checkpoint-after-v453)
record the exact reused command/result/source guards.

Contracts: **5,274 implemented / 1,267 missing / 80 blocked**; requirements
remain **462 implemented / 12 missing / 11 blocked**, zero verified in both.
Scanner-idle completion or a late empty snapshot cannot prove causal clear or
stop; stop171 remains unqualified. No int64/reused/concurrent ID, reconnect,
exactly-once effect, whole lifecycle, alias, other OS/transport or full-goal
claim follows. Fixed YOLO is setup only. Security/permission tests and audits,
broad suites and hosted workflows remain unrun. A11, unavailable producers,
external/platform and release gates remain incomplete. No publication/deployment.
Rollback reverts only these two bindings and documentation. Continue existing
ordinary process input/output evidence.
