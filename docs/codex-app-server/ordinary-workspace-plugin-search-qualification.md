# Local workspace plugin-search discrimination

V525 extends the existing ordinary local-source case after `1c50ea8` for
stock `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`.
Only `native_plugin_search_scope_test.exs` changes. Two additional native
queries provide a missing local scope discriminator; no runtime code changes.

## Missing behavior and actual native producer

The earlier filter-values case queried workspace with only a positive
personal catalog. Both global and workspace were empty, so it could not
distinguish an accidental global/workspace swap. The existing source-scope
case independently requires two nonempty global and two nonempty personal
results in the same native process, including complete candidate identities,
content, ranking, source paths and an exact combined result.

Immediately after that positive matrix, the extension queries the same term
and roots with `scope: "workspace"` and requires the entire native result
`{"data": [], "nextCursor": null}`. It repeats after confirmed shutdown and
the independently positive matrix in a distinct cold process. Either ordinary
local scope substituted for workspace would now fail with nonempty data.

The pinned `app-server/src/request_processors/plugins/search.rs:136` skips
local enumeration for Workspace; the separate local scope predicate at
line293 also explicitly returns false. Nonempty local controls rule out the
plugins-disabled and blank-query empty paths. Four complete request/type/
dispatch/processor source files match the immutable official archive.

Only physical owner **4745** is eligible for this narrow local behavior:
`v2/PluginSearchParams.json#/definitions/PluginSearchScope/enum/1`.
Canonical node SHA256:
`29cdac370427a3c5a1e0ade781009bee8e496747497648a3414f42193e6534dc`.
The source archive does not contain a checked-in `PluginSearchParams.json`.
The hash-verified stock binary's documented experimental schema generator was
run in a separate temporary directory; its complete exported file equals the
committed experimental schema byte for byte (SHA256
`9a531ed727cf716302e611d98153f4ed09598b7b27a5629074648c0e57f24e09`).
Reference `/tmp/samgita-v525-generated-schema-reference.json` SHA256:
`3ade9094f90f812dafbe268d7675f8f1508945aad42510475a25d302083bfd31`.
This fixture disables remote catalogs. Enabled remote workspace discovery
and external service integration remain unverified; no empty reply is
presented as successful remote catalog acceptance.

## Preserved checks and focused result

All original candidate, held/restored catalog, warm/cold equality, source-file
snapshot, zero-inference, loaded-thread, session-state and confirmed native
shutdown assertions remain. Every request/reply retains its complete original
encoded body and typed unique-string correlation. Only the two new searches
change declared exchange counts **30 to 32**; the capture cap stays **32**.
No deadline, cap, provider, helper, transport, case count or runtime changes.

The existing case at line181 passes **1/0**, seed `501432`, in 1.8 seconds,
from the independent driver directory with the pinned executable and fixed
yolo, after formatting passes:

```sh
mix test test/native_plugin_search_scope_test.exs:181 --warnings-as-errors --seed 501432
```

| Artifact | SHA256 |
| --- | --- |
| Modified test | `9ca2297ca30286a00890b5056852f91cded92ac0912bb87d7488a5c224d0734d` |
| `/tmp/samgita-v525-next-gap-evidence.json` | `d99770b0914abbfde293fba6d538b5c0e6df7a3e18bb1dc049638631acb81c86` |
| `/tmp/samgita-v525-workspace.patch` | `9e4b16cd74c2037cd608812fb01cb91146bee06fe0a08f1d7a798a21f384eb19` |
| `/tmp/samgita-v525-independent-review.json` | `22bb390244185d9738cba1016293eaba5b44d93202abe8763239058b20c9dc17` |
| `/tmp/samgita-v525-focus-501432.log` | `4c60d0354794b38c6b7cd474a474c468a669e581dc9c29f0dbce506dca38f9dd` |

The original test SHA256 is
`93602b891fcd506b256426212cd9638f500073982a21d3fe8970a3567a221e5c`.
Independent source review reports no findings and exactly reconstructs every
original byte by reversing the three patch hunks. No first-run failure or
repair occurred. Final combined-source results follow. No other enum, default,
activation, alias, transport/OS or whole-method credit follows.

## Final combined-source functional qualification

All **14 reviewed functional steps pass**:

```sh
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-v525-qualified
```

The unchanged **68-file / 129-case** selection passes at `501432` and
`987654` in 223.225 and 222.522 seconds. Three selected neutral WebSocket
cases pass at each of `455834`, `501432`, `987654` (13 other cases excluded).
The independent outside-umbrella actual-native consumer passes **1/0**.
Driver/root formatting, driver/umbrella warnings-as-errors compilation,
inventory consistency, strict Credo, Dialyzer and assets build pass.

All **1,687** before/after guarded hashes are identical. Fingerprint:
`f39705149b2628d3e63c57f34376b62d7aa7328f5b783539efd2f4c229c04bd3`.
The final binding verifies every command/result/log hash, exact scratch patch
and original test bytes, four complete immutable producers, generated native
schema reference, canonical node and independent source review. All **1,685**
other guarded sources remain identical to V523. Only owner4745 changes from
`1c50ea8`; every requirement and other contract stays exact.

Final binding `/tmp/samgita-v525-final-binding.json` SHA256:
`af5797b632b96e7a5890d3ea78317a4d534b251634de0ee4e99d5eabf71543d1`.

| Final execution artifact | SHA256 |
| --- | --- |
| `/tmp/samgita-ordinary-v525-qualified/results.json` | `c1dbf2af10b1bcc32d3f077d26278457db70e7a221d140806d9f9c0eb7d8be58` |
| `/tmp/samgita-ordinary-v525-qualified/source.json` | `e042a5fda4e7b1b5679bcb5663202c76b93312af25226a7085e40ca851b92403` |

Contracts: **5,498 implemented / 993 missing / 130 blocked**; requirements
**462 implemented / 12 missing / 11 blocked**; **zero verified**. Continue
the source-reviewed two-producer generic-subAgent searches; their scratch
patches have no runtime credit yet. Environment connected/disconnected root
owners2847/2851 still need a new ordinary helper: the old helper automatically
executes prohibited authentication checks and must not be run under the
current restriction. Neither source investigation is acceptance.

Rollback removes the two queries, restores declared counts and the associated
evidence/fingerprint metadata. No migration, dependency, production runtime,
historical record or external service changes. Security, credential,
authentication, authorization, approval and permission tests/audits, broad
suites and hosted workflows remain unrun and incomplete. A11, unavailable
emitters/external/OS, full compatibility and release gates remain incomplete.
Nothing is published or deployed.
