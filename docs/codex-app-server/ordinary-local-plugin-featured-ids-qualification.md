# Ordinary local plugin featured IDs

V523 continues after `c7a0a62` with stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
It adds one presence/value assertion to the existing ordinary local plugin
filter case, without a new test, scenario, provider, method, call or runtime.

## Missing oracle and actual native result

The existing case retains complete original `plugin/list` request/reply maps
and encoded bodies with unique-string correlation. Its full cold result must
equal the warm result. It independently requires a real nonempty authored
local marketplace with all seven prescribed plugin metadata rows.

That consistency oracle allowed both results to omit `featuredPluginIds` or
carry the same incorrect value. The added
`Map.fetch!(listed, "featuredPluginIds") === []` assertion independently
requires presence, empty-list type and the prescribed local value for both
native processes. A schema default cannot fill this evidence gap: the field
is optional for deserialization. No response transformation or default is used.

The [pinned plugin processor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/plugins.rs#L794-L820)
directly assigns `Vec::new()` when the returned marketplace names match neither
curated remote name. The independently checked fixture name
`owned-local-filter-values` takes this branch. The native response type's
`Vec<String>` uses `serde(default)` without a serialization skip, so the
original reply explicitly includes `[]`. Six complete producer/dispatch/type
files and the standalone response schema equal the official immutable archive.
No remote recommendation response or disabled-plugins shortcut supplies this
field.

## Scoped verification

The owning actual-native case passes **1/0**, seed `501432`, in 1.5 seconds,
from the independent driver directory in the verified Devenv environment with
the pinned executable and fixed yolo:

```sh
mix test test/native_local_plugin_filter_values_test.exs:227 --warnings-as-errors --seed 501432
```

| Artifact | SHA256 |
| --- | --- |
| Modified test module | `3cfe1724279749d290dbd6ea7ec1c6e9bdd7fc85e125160bd64ef5d5755ffb48` |
| Source evidence `/tmp/samgita-v523-next-gap-evidence.json` | `079298439ac044af465f1f6ccd6960aa7da6d254413f8f6781e2a43af9d20453` |
| Independent review `/tmp/samgita-v523-independent-review.json` | `490ac875699e3474e147f0604774565508d0e0e5eb531073d94a0a9049a015bf` |
| Focus log `/tmp/samgita-v523-focus-501432.log` | `c9aa8f9aa75ad44ed7df3e93a9ef9c0c9f8117c0ad2f1e0b604ab18ec88bf87f` |

Removing only this inserted line reconstructs the exact original file SHA256
`f4ae72a4d0d7128afbcc194602ca733df241ff44cdff5bbe4f97ea19d98b8225`.
Every prior assertion, byte-retention and warm/cold equality check remains.
All existing source filters, no-inference controls, method inventories,
deadlines, buffers and confirmed process cleanup are unchanged. The first
compile/native run passes without a repair or relaxed bound.

Only physical owner **4644**,
`v2/PluginListResponse.json#/properties/featuredPluginIds`, gains scoped
implemented evidence. Node SHA256:
`aac2a4e83d2823be6d45475fa797647d1e2a6c55cfa5a4632ae455eeacdd2e88`.
Nonempty string items, remote recommendations/ranking, omission/default
interoperability, aliases, other transports/OS and complete-method acceptance
remain unqualified. Final combined-source results follow.

## Final combined-source functional qualification

All **14 reviewed functional steps pass** on the final source:

```sh
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-v523-qualified
```

The **68-file / 129-case** actual-native selection passes at seeds `501432`
and `987654` in 224.178 and 222.972 seconds. Three selected neutral WebSocket
cases pass at each of `455834`, `501432`, `987654` (13 other cases excluded).
The outside-umbrella actual-native consumer passes **1/0**. Driver/root
formatting, driver/umbrella compile with warnings as errors, inventory
consistency, strict Credo, Dialyzer and assets build all pass.

All **1,687** guarded before/after hashes are identical. Fingerprint:
`2db91a3d1536ee9b9aa0c047d117ac0944d0a3a065554f676527a5890abe9427`.
The final binding verifies every command/result/log hash, the exact one-line
test addition against `c7a0a62`, six complete archive producers, the official
schema and canonical field node. Only this test and the manifest differ from
the preceding V519/V520 source snapshot; **1,685** other guarded sources stay
exact. No failure, timeout, bound increase, skipped selected assertion or
runtime repair occurred.

Final binding `/tmp/samgita-v523-final-binding.json` SHA256:
`17d72107b86c31c1f11a60715b0cdbb99eae0f13447ac11294f5d15532b3c728`.

| Final execution artifact | SHA256 |
| --- | --- |
| `/tmp/samgita-ordinary-v523-qualified/results.json` | `7473ce37e7c5f344494e8f6345a5dababea15d58c2b0a7bf24a5d86916d92240` |
| `/tmp/samgita-ordinary-v523-qualified/source.json` | `6a52fbc1db6de777b4801f6432f0695dcf3b2bcd48789a9bd59f891eeeb88668` |

Only owner4644 gains scoped implemented evidence. Contracts: **5,496
implemented / 995 missing / 130 blocked**; requirements **462 implemented /
12 missing / 11 blocked**; **zero verified**. Continue source-reviewed
realtime transcript-role indexing, then the ordinary workspace-search
discriminator. Neither receives credit from this local plugin-list assertion.

Rollback removes this single assertion and its exact evidence/fingerprint
changes. No production runtime, dependency, schema, migration, historical
record or external service changes. Security, credential, authentication,
authorization, approval and permission tests/audits, broad suites and hosted
workflows remain unrun and incomplete. A11, unavailable emitters/external/OS,
full compatibility and release gates remain incomplete. Nothing is published
or deployed.
