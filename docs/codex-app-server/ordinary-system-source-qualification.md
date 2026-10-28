# Inert System configuration source metadata

This unit follows `3c018d6b9fa8e4dda2b1d22fd702815061050486` on existing
`main`. The immutable target remains Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
The profile is explicitly owned Linux x86_64 musl stdio, experimental API
enabled and fixed YOLO setup. No security, permission, credential,
authentication, authorization, approval or sandbox behavior is tested.
Audits, broad mixed suites and hosted workflows remain unrun; their gates stay
incomplete. No production code, dependency, migration or cleanup helper changes.

## Native behavior and environment prerequisite

The three existing ordinary desktop-configuration cases already call
`config/read(includeLayers:true)`. Before selecting their User layer, a new tap
extracts only layer names and requires exactly one native System name:
`{"type":"system","file":"/etc/codex/config.toml"}`. Existing User selection,
desktop write/version/override assertions, RPCs, startup arguments, processes,
timeouts and teardown remain unchanged. No extra native operation is added.

Before any fixture or native process starts, `File.lstat` must return exactly
`{:error,:enoent}` for the default system path. A present path, symlink or any
other result fails explicitly as a missing environment prerequisite. No test
creates, reads, renames, mounts over or overrides a host system configuration.
The successful local profile meets this prerequisite.

The stock loader attempts that absent path and materializes an empty required
System layer. The new assertion reads only its source name/path through the
real Session result. It does not inspect System contents, effective policies,
managed requirements, layer precedence/version/disabled reason or credentials.
The existing owning file has no original-wire capture ledger, so this unit
claims native response-source evidence only, not raw-frame preservation proof.

## Exact production source and physical contracts

The CLI supplies `LoaderOverrides::default()`. The required loader helper
returns an empty TOML table for NotFound and always pushes the System source.
Its stack iterator keeps empty layers; the app-server excludes only packaged
defaults from requested layers and preserves System/file on conversion.

| Immutable source relative to codex-rs | Causal anchor |
| --- | --- |
| `cli/src/main.rs` | 1281–1289: default loader overrides |
| `config/src/loader/mod.rs` | 80,272–288,555–618,785–801: default Unix path, required empty layer and unconditional System push |
| `config/src/state.rs` | 302–324,618–629: stored layer vector and unfiltered iteration |
| `app-server/src/config_manager_service.rs` | 119–176: includeLayers response, packaged-default filtering |
| `app-server/src/config_layer.rs` | 20,57–64: unchanged System/file conversion |
| `app-server-protocol/src/protocol/v2/config.rs` | 33–57: System/file wire representation |

All six complete files match the immutable source archive in
`/tmp/samgita-ordinary-system-source-20261028-handoff.md`, SHA256
`63b447f98dae27086b1843d77748dbed76f52619d424a1e8a0cf18b235110aa0`.
The whole pinned `v2/ConfigReadResponse.json` SHA256 is
`4ec77e1a3eed746037149799c3b6bb8fe7b4b593e5930fc9f410e6282de9df50`.
Exactly five physical owners gain scoped implemented evidence:

| Owner | Pointer suffix under `/definitions/ConfigLayerSource` | Canonical node SHA256 |
| --- | --- | --- |
| 3591 | `/oneOf/2` | `70e5f8094529342c49c1599bac5d51776d8c0828f91e96983cee716bf14bdf7d` |
| 3592 | `/oneOf/2/properties/file` | `fe2f4b1a6a231e6274b65ec8c75271560b1396630bddc5b898b6c48ea91fdf7e` |
| 3593 | `/oneOf/2/properties/file/allOf/0` | `85b73ba1a78c40839a9e48b1e72023c66bba5c7f1922229b01a93922acea475d` |
| 3594 | `/oneOf/2/properties/type` | `5610749d649bc10c2ae21b13fdd17982083ed8256a51dcdf83ac647b631cab1c` |
| 3595 | `/oneOf/2/properties/type/enum/0` | `cf5fba424df88453fd1c04605897f3372415874ef6eb4d48b3e8bf745f291178` |

IDs, pointers, schema hashes and the native pin stay unchanged. No alias,
other source variant, whole layer, policy or globally verified credit follows.
Requirements remain **462 implemented /12 missing /11 blocked**; contracts
become **5,735 implemented /750 missing /136 blocked**, zero globally verified
in either ledger.

## Focused functional qualification

The complete owning file passes **3/0 at seeds501432 and987654** on its first
run,2.606s each including command startup, followed by strict Credo. Scoped
format and compile pass. All1,760 guarded source hashes remain identical.

```sh
MIX_ENV=test ERL_FLAGS='+S 2:2' devenv shell --no-tui -- python3 -B /tmp/samgita-ordinary-system-source-focused-20261028.py
```

Results JSON SHA256:
`fdb630e389db44170812d21bab3447868371b32f2d29e870153c6396e97be75f`;
source JSON SHA256:
`af8f393949698f031052614e44f07827e265e7e192719605f220636594e2ffb7`.
These focused results precede manifest/runner integration.

## Final combined-source functional qualification

All reviewed command selections, main 165/extension 12 counts, prior assertions
and 320s/120s bounds remain unchanged. All **17 reviewed functional steps pass**
against **1,760 identical guarded sources**:

| Check | Actual result |
| --- | --- |
| Selected neutral overflow/replay | 16/0, 13 excluded at each of 455834, 501432 and 987654 |
| Main native block | 165/0 at 501432 and 987654; 285.715s and 302.520s |
| Separate native extension block | 12/0 at both seeds; 20.597s and 20.496s |
| Owned cleanup phases | 4/0, original ACK/exit/deadline requirements intact |
| Outside-umbrella consumer | 1/0 against actual pinned Codex, without Repo/Phoenix |
| Other checks | Driver format/compile, inventory, umbrella compile/format, strict Credo, Dialyzer and assets build pass |

```sh
MIX_ENV=test ERL_FLAGS='+S 2:2' devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-system-source-combined-20261028
```

Results JSON SHA256:
`877d7eb1e41b7d11f4adc97d4cd51195254111be08338a26c117aaaf2faa88bd`;
source JSON SHA256:
`e827bb54a757988c399b2ba946f5fca79c53fd4a7a86ff45cae34a720f9c39a2`.
The frozen source fingerprint is
`f10ca127a17bf67d0be1f87a1705444fb705ee4d18a5e0486953c7d03f1ef101`.
Exact argv, individual results and log hashes remain in the evidence directory.
No prohibited test, audit, broad mixed suite or hosted workflow runs. The
preceding production artifact is retained only for unchanged production inputs;
this test-only change does not imply a new publication or deployment.

## Retained production assembly

All 2,304 inputs from the preceding plain-copy assembly were compared with the
current checkout. Exactly seven differ: this unit's test, the reviewed runner,
the compatibility manifest and four qualification/ledger documents. The other
2,297 match. Production source, dependency locks, configuration and assets inputs
remain unchanged; the new document adds no production build input. This retains
the preceding assembly evidence rather than claiming a fresh build of this head.

The retained archive is
`/tmp/samgita-ordinary-record-cache-local-assembly-20261028/source/_build/prod/samgita-0.1.0.tar.gz`,
20,083,133 bytes, SHA256
`ed79ae51eac66b50e46e560395da4deb554dec4d7409d18fe531330d4b00a190`.
Its [five successful build steps](ordinary-record-cache-qualification.md#local-production-assembly)
do not start a service or satisfy the incomplete publication/release gates.

## Remaining work

The bounded82-owner input/config review leaves77 other owners incomplete:
60 direct runtime-policy/requirements/exposure fields,12 external or managed
input/policy prerequisites and5 Mdm source shapes with no construction found in
the inspected stock loader. This is not a global impossibility proof, a scope
waiver or a passing gate. Other response-source, missing-trigger and alternate
artifact prerequisites remain in the preceding unit's source review.

A further four-schema review leaves all eleven selected owners incomplete.
In particular, the successful legacy summary route always constructs
[nonnull timestamps](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L6450-L6490);
the apparent nullable constructor is
[test-only](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_summary.rs#L8).
Neither a supplied history nor a unit-test constructor supplies real native
positive evidence. The archive-matched report is
`/tmp/samgita-four-schema-remaining-20261028-report.md`, SHA256
`d14c086d132bf20ac7c414988a5e06b12538c22bb755bdd9b554db7f77edfa56`.
The [four remaining search-source prerequisites](thread-source-prerequisites.md)
also remain unchanged. This bounded review does not prove global unreachability.

Continue remaining permitted ordinary evidence work where a genuine producer
and deterministic observation can be established. The next source-supported
candidate is a separate ordinary `account/rateLimits/read(params:null)` exchange,
including its additional reset-detail GET; it remains unrun. Existing numeric
read assertions and their optimized request must remain intact.
A11's pre-emission boundary,
source-proven absent legacy emitters, unresolved native triggers and historical
intermittent cleanup cause, external/backend/OS success, prohibited/broad/hosted
checks, full compatibility and release acceptance remain incomplete. Existing
dependency/replay/database/cleanup safeguards and historical data stay intact.
No system file, live service or sibling repository is changed. Nothing is
tagged, published, released, started as a service or deployed.
