# Genuine sources from the official standalone app-server

This unit follows `a0b55660d8b0f8ef4409cdfa6eda3caa9ee1eb3f` on existing
`main`. It declares a separate **linux-x86_64-musl/standalone-stdio** profile
for official Codex `rust-v0.163.0`. The existing combined executable and its
behavior evidence remain unchanged. Only ordinary functional checks run, with
fixed YOLO launch settings. Security, credential, authentication, authorization,
approval, sandbox and permission tests, audits, broad mixed suites and hosted
workflows remain unrun and incomplete.

## Independently pinned official executable

The official release contains the separate
[app-server archive](https://github.com/openai/codex/releases/download/rust-v0.163.0/codex-app-server-x86_64-unknown-linux-musl.tar.gz),
asset ID `645226350`. This resolves artifact discovery for this profile; it does
not add a source selector to the combined `codex app-server` entry.

| Reference | Verified value |
| --- | --- |
| Source commit | `83086188ae0614bd882818ff1aa23f3194962012` |
| Annotated tag object | `129b8ec7ee6f4511557a4856279f529025c25af4` |
| Source archive SHA256 | `e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567` |
| Standalone archive bytes / SHA256 | 87,120,300 / `bd587a5419f9b6fa488e4950b065c9127f7db0989388210a3785294b460cdf09` |
| Sole regular executable bytes / SHA256 | 228,736,728 / `528c11baca43b3be05112c0be1fb1c4a3d5c53f1b6d628f5bf42ebd7803e7a9e` |
| Retained combined executable SHA256 | `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215` |

Actual `--version` returns `codex-app-server 0.163.0`. Actual `--help` exposes
top-level `--listen` and `--session-source`; there is no `app-server` subcommand
in this executable. Initial metadata commands retained a missing disposable
CODEX_HOME/PATH-alias warning. Creating that owned empty directory and repeating
the metadata commands produced identical stdout and empty stderr. Original
records remain in the ignored `tmp/codex/0.163.0/standalone/` cache.

`scripts/codex/fetch_standalone_pin.py` installs only this additional reference
in that cache; it never starts a service or changes the primary pin. Existing
unexpected bytes fail without replacement. `--check` validates cached archive
and executable bytes without downloading or executing either. No adverse-path
security tests are claimed.

```sh
python3 -B scripts/codex/fetch_standalone_pin.py
python3 -B scripts/codex/fetch_standalone_pin.py --check
```

The release-discovery report is
`/tmp/samgita-app-server-release-assets-20261028.md`, SHA256
`34bb5adedce4e21fa572a05d4b53ee67b53381b5517ab96cc1b9c92702359ab1`.
The source/trigger plan is
`/tmp/samgita-standalone-source-selector-20261028-plan.md`, SHA256
`ba7797d22e112a862c328c74083b835b7591166046a156d96048eea32a15cba9`.

## Native production, persistence and cold discovery

The [standalone main](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/main.rs#L47)
passes its selector to the manager. The
[core parser](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/protocol/src/protocol.rs#L3062)
normalizes the source; the
[public conversion](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/thread_data.rs#L43)
names core Mcp `appServer`. This is app-server JSONL protocol, not an MCP endpoint.
The bounded plan archive-matches the complete causal source files; it does not
infer production from an enum or a synthetic stored-source label.

One native case starts four distinct standalone producers sequentially. Each
performs one real thread/start and turn/start against the existing loopback
**model** fixture. The immutable native app-server generates the protocol
responses, item IDs, history and source metadata itself.

| CLI selector | Native canonical source | Public source |
| --- | --- | --- |
| `appserver` | `mcp` | `appServer` |
| `unknown` | `unknown` | `unknown` |
| `AtLaS` | `{"custom":"atlas"}` | `{"custom":"atlas"}` |
| `vscode` | `vscode` | `vscode` |

Each producer must reach a public completed-item persistence barrier and a
newline-complete native canonical record containing its task_complete. Native
thread/read, thread/turns/list and thread/items/list must agree on original
source, path, content, turn and item IDs. Each process is reaped before the next
starts. No stored metadata, SQLite row or app-server response is injected.

Two distinct cold readers start after all producers close. Before any history
hydration they each issue both thread/list and thread/search for this matrix:

| sourceKinds | Exact selected histories |
| --- | --- |
| `["appServer"]` | appServer |
| `["unknown"]` | unknown |
| `["vscode"]` | vscode control |
| `["appServer","unknown"]` | appServer, unknown |
| `["appServer","unknown","vscode"]` | appServer, unknown, vscode |
| omitted | custom, vscode |

All 24 discovery requests require unique exact positive/exclusion sets, source
values, original prompt snippets and terminal nextCursor=null. This deliberately
avoids the independently documented timestamp-pagination defect. Native database
discovery presents threadSource=null; canonical and thread/read attribution
remain separately checked. Only stable content/source projections are compared
across readers; original full replies and independent read-state receipts stay
in the bounded captures.

Both readers then read all four original histories without resume or another
model call. Canonical bytes, fixture inputs and the empty workspace stay exact.
The ledger requires exactly four model calls, six distinct native process IDs,
four thread/start and four turn/start requests. Every request has exactly one
original correlated reply. Captures retain the existing per-process limits:
1,024 frames, 262,144 bytes/frame and 8,388,608 total bytes. Request, turn and
persistence deadlines remain 5s, 20s and 5s, with at most 200 persistence probes.
Existing owned-process ACK, helper exit, native reaping and provider shutdown
remain required; no timeout or buffer is increased to obtain a pass.

## Exact scope and focused evidence

Only these six physical owners gain scoped **implemented** evidence:

| Owner | Schema and pointer |
| --- | --- |
| 6076 | `v2/ThreadSearchParams.json#/definitions/ThreadSourceKind/enum/3` |
| 6082 | `v2/ThreadSearchParams.json#/definitions/ThreadSourceKind/enum/9` |
| 6101 | `v2/ThreadSearchResponse.json#/definitions/SessionSource/oneOf/0/enum/3` |
| 6102 | `v2/ThreadSearchResponse.json#/definitions/SessionSource/oneOf/0/enum/4` |
| 6103 | `v2/ThreadSearchResponse.json#/definitions/SessionSource/oneOf/1` |
| 6104 | `v2/ThreadSearchResponse.json#/definitions/SessionSource/oneOf/1/properties/custom` |

The test binds each exact original node hash and root file SHA256. Equal-hash
aliases, list/request roots, notification owners and complete methods receive
no transferred credit. Requirements remain 462 implemented /12 missing /11
blocked. Contracts become **5,742 implemented /743 missing /136 blocked**;
globally verified remains **zero**.

The first focused attempt passes format, compile and native 1/0 at both seeds
501432 and 987654, then fails strict Credo with six complexity/nesting findings.
Its original evidence is `/tmp/samgita-standalone-source-focused-20261029`:
results SHA256 `90dd0c4251d6dbf21013dc7da87c8c2573cab1ad1dc07564667c62599c7c389e`,
source SHA256 `37ed023f9a056bd803b8bb65b86886c872ecf9d1dd574cc3465d21a404567ee3`.
Helper extraction preserves the assertions and bounds; no lint rule is disabled.

The repaired focused run passes all five checks, native **1/0 twice** in 5.461s
and 5.411s, and strict Credo. All 1,762 guarded source hashes remain identical.
Evidence: `/tmp/samgita-standalone-source-focused-repaired-20261029`;
results SHA256 `a406794f64031af909b59a34c3920b04c1373338d05ab16548f57a3ce9947ac9`,
source SHA256 `e0efde9f76b112140556f18c7416d5a143937f9ec2787dde952f2361344d4091`.
This focused run precedes manifest and ordinary-runner integration.

## Final combined-source functional qualification

All **17 reviewed functional steps pass** against **1,762 identical guarded
source hashes**. The runner retains every main 165-case argv/assertion and its
320s bound. The separate extension block adds this single case, becoming 14
cases with its existing 120s bound. It verifies both immutable executable hashes
and sets CODEX_APP_SERVER_BINARY separately. The existing manual conformance
workflow receives the new reference prerequisite; it is not dispatched under
the current verification restriction.

| Check | Actual result |
| --- | --- |
| Neutral overflow/replay | Three selected cases, zero failures, 13 excluded at each of 455834, 501432 and 987654 |
| Main native block | 165/0 at both seeds; 288.965s and 285.566s |
| Separate native extension block | 14/0 at both seeds; 27.159s and 26.657s |
| Owned cleanup phases | 4/0, existing ACK/exit/deadline requirements retained |
| Outside-umbrella consumer | 1/0 against actual combined Codex without Repo/Phoenix |
| Other checks | Driver format/compile, inventory, umbrella compile/format, strict Credo, Dialyzer and assets build pass |

```sh
MIX_ENV=test ERL_FLAGS='+S 2:2' devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-standalone-source-combined-20261029
```

Results JSON SHA256:
`7f565016bc0207fbca4d61536bb3302dd43c2f5e33aa3a22a0525a2b54e1cbdd`;
source JSON SHA256:
`bec468feda0617d3fa24e4aa008587781360029c73b8330d71eca6e4152d6ef1`.
Reviewed source fingerprint:
`6e2672979306a555257ec0828174128a45c3fae869da259884a38704e68d81b5`.
Exact argv, bounds, individual results and log hashes remain in that evidence
directory. No prohibited test, broad suite, audit or hosted workflow runs. This
functional selection does not replace full compatibility or release acceptance.

## Production and remaining acceptance

Production code, configuration, locks, migrations, database safeguards and shared
cleanup behavior are unchanged. The preceding local production assembly remains
evidence for those inputs; no new assembly, artifact startup or publication is
claimed. Earlier [combined-artifact findings](app-server-source-artifact-limit.md)
and [search prerequisites](thread-source-prerequisites.md) remain historical
evidence for the combined executable, with this separate profile now qualified
for the six owners above.

Next ordinary work can qualify original native thread/started source notifications
through this newly available executable; search replies cannot substitute for
those notifications. Compact/Other producers, A11's pre-emission boundary,
source-proven absent legacy emitters, the historical intermittent cleanup cause,
external/backend/other-OS success, prohibited/broad/hosted checks, full compatibility
and release remain incomplete. No historical data, host configuration, live
services, sibling repositories or credentials change. Nothing is tagged,
published, released or deployed.
