# Ordinary remote plugin installation, removal and null search paths

This unit follows pushed checkpoint `62c2f20` and retains official Codex
`rust-v0.163.0`, commit `83086188ae0614bd882818ff1aa23f3194962012`, binary
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
All app-server messages and local plugin effects come from that real binary.
Only its metadata/bundle dependencies are owned fixtures. Fixed YOLO, synthetic
identity, required backend DTOs and HTTPS setup are scaffolding; no security,
permission, authentication, authorization, approval, policy, header or TLS
outcome is tested. No broad suite, audit or hosted workflow is selected.

## Actual install and uninstall effects

The native client sends one install with explicit `marketplacePath:null`, a
nonnull `remoteMarketplaceName` and a remote plugin identity. The owned tar
contains only a literal manifest, Unicode marker and inert skill. The fixture
never writes or removes the native plugin cache. Before accepting the backend
install POST it independently verifies all three actual materialized files.
The test checks those bytes again, persisted remote identity and backend state.

One installed refresh returns the owned plugin. Native `skills/list` must then
expose its exact namespaced name, description, plugin ID and absolute cache
path within at most eight read-only observations. No explicit plugin TOML entry
is created, so disk materialization alone cannot satisfy this positive
installed-snapshot publication oracle. Those observations never retry installation.

Only after positive publication, one actual remote-ID uninstall resolves the
target through a second detail GET with empty raw/parsed query. The backend
uninstall POST must see the exact installed bytes still present. Native success
then returns `{}`, removes the whole canonical cache root and identity file,
and removes the owned skill. Exactly this business-action sequence is required:

`detail → scope → bundle → install → refresh → detail → uninstall → refresh`.

The second refresh returns an empty page. Its response-sent barrier proves
delivery of that response. Root/skill absence can follow native direct removal
and cache clear before asynchronous empty-snapshot publication; that publication
is deliberately **not** claimed. No extra reconcile/installed operation or
invented completion event is used.

Pinned `remote_mutations.rs:85-214` materializes before backend installation;
`217-315` awaits backend removal/local deletion before returning uninstall.
`remote.rs:1655-1798` establishes the remote detail/POST/removal path, and
`store.rs:343-345` removes the full canonical root. Native marketplace spelling
is ignored after remote-branch selection; canonical USER scope supplies identity.
This proves source selection, not name-specific routing or validation.

The existing capture/private-reduction shape, per-call5s, helper50s, test60s,
socket3s, startup5s and observation/owner deadlines remain unchanged. Each
mutation occurs exactly once. HTTP<=24, journal<=64, bundle/response<=128KiB,
capture<=64 frames/1MiB and positive skill probes<=8 remain bounded. Empty
model journals, workspaces, rollout and loaded-thread inventory, idle/no-uncertain
Session state and original-byte/typed-ID correlation are required. Explicit
native/helper close and owner/Port/PID completion checks retain the prior cleanup.
No thread, turn, tool, MCP, hook or model execution is requested.

## Present null on actual remote search results

The existing seven-search limit/pagination journey is unchanged. Every real
row already uses `Map.fetch!` and an independent literal nil expectation for
`marketplacePath`. The added response-schema hash/input snapshot and validation
select only its exact null node under `definitions.PluginSearchResult`.
All original metadata/page/limit/cursor, counts, wire bytes and cleanup checks
remain. The helper and all RPC/backend requests are unchanged.

Pinned native `plugins/search.rs:117-121,262-273` supplies `None` for remote
results and serializes the present null. The experimental JSON is an existing
pinned-binary generated artifact, SHA256
`d98f7926f5bf62c228f8c39e83214e2140e80ea7a1db3c221eb1babe26ff8fed`;
it equals the cached generated copy and provenance manifest. It has no standalone
JSON archive member or stable-schema file. Archived Rust type, producer and
TypeScript contract match exactly; this record does not invent an archive JSON
match or a new schema-generation run.

## Focused evidence and narrow ownership

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-ordinary-remote-install-focused-20261028.py
devenv shell --no-tui -- python3 -B /tmp/samgita-ordinary-remote-lifecycle-null-focused-20261028.py
devenv shell --no-tui -- python3 -B /tmp/samgita-ordinary-remote-lifecycle-final-focused-20261028.py
python3 -B /tmp/samgita-ordinary-remote-lifecycle-source-binding-20261028.py
```

The lifecycle passes **1/0 twice** on its first runs. After the field-specific
search addition the combined cases pass **2/0** at501432 and987654,2.7/2.6s,
also on first runs. No functional repair, assertion removal or deadline increase
is needed. Strict Credo separately rejects the manifest JSON string's escaped
quotes. An equivalent `~s` sigil preserves its exact bytes; the final focused
cases pass **2/0 twice**,2.6s each, and strict Credo passes618 source files.
The original lint failure stays at
`/tmp/samgita-ordinary-remote-lifecycle-credo-20261028.log`, SHA256
`d2d0bd81d8d498a13f28216578286925113800ebe3ad769a519eb9b5253d842b`.
Sixteen whole source/schema files match their immutable archive members. All
four physical node hashes match; generated search JSON provenance is separate.

| Evidence | SHA256 |
| --- | --- |
| Source/node binding JSON | `50b88775c337baac5a787966ff3e836b4fd1efab5f0684e53c7d93ea1128bd86` |
| Focused combined seed501432 log | `127a5a3f1195def4976d81cf97b5466840710f8cc16e87faf50d5c022ce345d6` |
| Focused combined seed987654 log | `dea8590309d46f4e1c49136c97a78c7e92d2db89d12c0c275dfa6e2d74372c46` |
| Initial formatted lifecycle test | `5cd34474805a2597e852fcd472b98bab1b434a74abb4749d4d4e46ed304b2f7d` |
| Final lifecycle test with equivalent sigil | `2e85aafc98edb505ff125bcfb23a065bfd8fc9d7e14f3527d889b0af2c273a08` |
| Lifecycle helper | `ce45f8a557ef130fdb4dd7761810a6e6e13e6d235c9e8a98d827fba65d4dae7c` |
| Modified search test | `bb43efbdc8a9d94cf56136b452951e22cca8a43df281168e5378aa1609f711bc` |
| Final focused seed501432 log | `f931d3acd9ce4779c9668b29ec257847b60e655e4a56a8b35efee660673e239a` |
| Final focused seed987654 log | `dea8590309d46f4e1c49136c97a78c7e92d2db89d12c0c275dfa6e2d74372c46` |
| Final focused strict Credo log | `011f341fc3eff22f8cff04b37ad9ecf43e66f02f6a63039b210e161cb1173dfc` |
| Independent final source review | `2b9d7215356f4df5e6672d03a235218a46ee59d4161a7fa4980f8d1a13714da0` |

After the first full matrix, staged whitespace checking found one additional
blank line at the helper's EOF. That check returned2 but the coordinating
command sequence incorrectly continued into a local commit. Nothing was pushed.
The blank line is removed and only the expected helper hash in the test and
selection fingerprint change. The complete fourteen-step selection is rerun
before amending/pushing that local commit. Original passed matrix/binding
`54aeb07e28c5b4b5505783233d72cba600b226ac36fd5c67143cc4ab55dc0ebb`
remains prior evidence, not acceptance of the changed final bytes. Staged
whitespace checking now gates dependent Git steps by its exit code.

Only install owners4511/4513 and search-null4797 change missing→implemented.
Already-implemented uninstall4904 and six client/server install/search/uninstall
requirements gain supplements with unchanged states. Contracts are **5,635
implemented /850 missing /136 blocked**; requirements **462 implemented /
12 missing /11 blocked**, zero globally verified. No aliases, policy, complete
method, external backend, transport or OS owner inherits credit.

## Final combined-source functional qualification

Whitespace-clean source requalification passes all fourteen steps. The binding
also verifies unchanged prior commands and the exact limited manifest delta.

```sh
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py \
  --output /tmp/samgita-ordinary-remote-lifecycle-final-clean-20261028
python3 -B /tmp/samgita-ordinary-remote-lifecycle-final-clean-binding-20261028.py
```

All **14 reviewed functional steps pass** on final combined source:

| Check | Actual result |
| --- | --- |
| Selected WebSocket overflow/replay | Three cases pass at455834,501432,987654; each16 tests,0 failures,13 excluded |
| Independent driver,87 selected files | **152/0** at501432 and987654;258.2/258.8s ExUnit time |
| Outside-umbrella real-native consumer | **1/0**, seed518102; no Repo/platform configuration |
| Compile and format | Driver/root warnings-as-errors compilation and formatting pass |
| Inventory/static/assets | Inventory consistency, strict Credo618 files, Dialyzer and assets build pass |
| Combined-source binding | **1,720** before/after/live hashes identical; **1,715** prior hashes unchanged |

Only three physical state promotions, one physical supplement and six method
supplements exist. Removing the single new test-file argument reproduces every
prior command exactly. No prior source or command is silently removed. Final
selection fingerprint:
`17e36ec5c4edee2bf0952f9ea7ff4ca20cfbce24ef5424f2e8c33d9a58a63eab`.

| Final evidence | SHA256 |
| --- | --- |
| Final binding JSON | `bf0515b24c439c087ce1031b66c1c03915b2e472043c7010759b92c624c24ba5` |
| `results.json` | `ecd4b9aa5cba8d5814f5e221bed87b3e9d1932de899584536c5158fb8407f75a` |
| `source.json` | `47b6eff166c7ba5f0755d41c9388be6fb9bff94713ca660da7a8bc662aa19d97` |
| Final whitespace-clean helper | `4b16350a181fa2bd002cd4d90380e6797dd7d8ed3e36f2fb36570db32a2b37ca` |
| Final test with updated helper pin | `9912d41f188a6555ba104e76ac7ce5919d7ed611aa937adc32845b0a0d772e85` |
| EOF-only cleanup AST/source binding | `4b03c3f71352e87626e291a9a30715279357c2beca37ba3216e2be1129dc5343` |

No prohibited/broad/hosted check runs.
Full compatibility, A11, the native timestamp cursor defect, unavailable
emitters/external services/other OS success, prohibited/broad/hosted checks and
release remain incomplete. No database recovery rerun, production migration,
publication, tag or deployment occurs. Rollback removes the new helper/test and
selector argument, reverts only the response-schema search-test addition and
these three state promotions/four-schema/six-requirement supplements; no platform,
history, credential, remote or data change is required.
