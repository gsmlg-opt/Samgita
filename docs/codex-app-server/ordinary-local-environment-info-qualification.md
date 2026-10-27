# Ordinary local environment cwd metadata

V519/V520 continue after `d022cba` with stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The two new ordinary cases call the real local `environment/info` producer with
experimental API enabled. The unchanged assistant-only model fixture is an
observable zero-inference sink, not an environment or app-server substitute.
No Samgita application, database or external executor is required.

## Positive PathUri lifecycle

The launch cwd is an owned directory named `cwd V519 #%.測試`, separate from
HOME, CODEX_HOME and the fixture/config files. Its expected URI suffix is the
independently authored literal
`/cwd%20V519%20%23%25.%E6%B8%AC%E8%A9%A6`. The generated root is encoded from
the owned input path with Elixir's standard URI function, never from a reply or
the native PathUri codec.

| Stage | Required result |
| --- | --- |
| Initial query and repeat | Exact authored cwd URI and stable contextual shell metadata |
| Live directory rename | Same directory inode, native PID and driver instance; exact new `/renamed%20V519%20%23%25.%E6%B8%AC%E8%A9%A6` suffix |
| Repeat after rename | Exact metadata equality and matching `/proc/<pid>/cwd` |
| Confirmed shutdown and distinct cold native | Exact renamed URI and stable shell metadata on both cold queries |
| Side-effect controls | Six info queries, fourteen original correlated RPCs, empty loaded-thread lists and zero model requests |

Sentinels, config, catalog, schema, provider/helper files and the separate model
workspace remain unchanged. The complete outgoing inventory contains only
initialize/initialized, diagnostics, loaded-list and local environment-info.
No thread, turn, tool, command or executor-registration request is sent.

The pinned [dispatcher and processor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/environment_processor.rs#L53-L78)
select the named local environment and call `force_info()`. Its local branch
in `exec-server/src/environment.rs:1019–1024` calls `EnvironmentInfo::local()`
for each request; `exec-server-protocol/src/protocol.rs:245–268` obtains the
process current directory and converts it to PathUri. The local environment
is installed through the ordinary startup/default-provider path, without an
executor fixture or environment registration. Eleven complete producer and
provenance files equal the immutable official archive.

Shell metadata reads the actual passwd/default-shell context. Assertions check
its shape and stability; they neither invent a private PATH shell nor qualify
shell schema owners. The older mixed `environment_profiles_test.exs` already
contains local metadata coverage and is not executed under the current
restriction. This is a stronger ordinary encoding/rename case, not the first
local method test.

## V519 scoped evidence

The owning actual-native case passes **1/0**, seed `501432`, in 1.6 seconds,
from the independent driver directory in the verified Devenv environment with
the pinned executable and fixed yolo:

```sh
mix test test/native_local_environment_info_test.exs --warnings-as-errors --seed 501432
```

| Artifact | SHA256 |
| --- | --- |
| Formatted test module | `93c6d43e7148a1fbc4d7a20b7bfa429c5ae846f10a399b8f4579417b36a191df` |
| Source report `/tmp/samgita-v519-next-gap.md` | `672906200aaebc2312660611ea6e605a83649669c76581a88d533012831f9511` |
| Source evidence `/tmp/samgita-v519-next-gap-evidence.json` | `d99f0e42017826c0b976edfb31e82a0482b1bef452ff326f6281becbba26e769` |
| Draft review `/tmp/samgita-v519-independent-review.json` | `5273353f2aa7a4708de786214f9b1e318f3bdaee89c40dc86d2a24d3d195cff0` |
| Focus log `/tmp/samgita-v519-focus-501432.log` | `da68d7d636c595ff7faa4a8049c77ece95ef3432c21e85b1a4b5fda7f0200398` |

Original encoded request/reply bodies and full maps retain exact authored
unique-string correlation. Bounds are 60 seconds per case and 5 seconds per
RPC; 32 outbound/128 inbound frames, 4/64 KiB per body and 1 MiB aggregate;
128 events/256 KiB and 1 MiB per retained file. Both native and provider
guardians require confirmed death/completion and closed Ports. No sleep,
automatic retry, private-state mutation or relaxed bound is used.

Only physical owner **3908**,
`v2/EnvironmentInfoResponse.json#/properties/cwd/anyOf/0`, gains scoped
implemented evidence. Its canonical node hash is
`815f1f5d28890061ed18b2319f46edf96e316cdcd4d96db2180bac4e0a96a755`.
V519 gives no credit to its null sibling, aggregate aliases, other PathUri
schemas, shell fields, remote executors, other OS/transports or complete-method
acceptance. V520 below separately exercises the actual null response.

## Explicit null after an owned cwd is unlinked

V520 uses a separate, newly created **empty** launch directory. HOME,
CODEX_HOME, model fixtures and sentinels remain in sibling directories.
It never removes a repository directory, task history or other user data.

| Stage | Actual native requirement |
| --- | --- |
| Before unlink | Independently authored positive encoded URI; held inode matches the empty directory |
| Remove that empty directory | Same native/driver and held inode; two successful replies contain explicit `cwd: null` |
| Recreate the same pathname | New directory inode differs from the original held inode; two more replies still contain explicit null |
| Confirm shutdown, start distinct native in new inode | Two replies return the positive authored URI again |

Every response must contain exactly `cwd` and contextual `shell`; `Map.fetch!`
and full-map comparisons distinguish explicit null from omission or a JSON-RPC
error. Native `/proc/<pid>/cwd` stat follows the held directory inode through
unlink and recreation. The reply is decisive; no guessed deleted-link spelling
or synthetic executor response is used. Seven metadata queries occur inside
fifteen exactly correlated original RPCs. Loaded-thread lists and model request
counts stay empty; all non-cwd fixture bytes remain unchanged.

The actual local producer uses `std::env::current_dir().ok()` and forwards
`None`; the response is a serialized `Option<PathUri>` without skip attributes.
The checked-in Rust 1.95.0 toolchain reference and immutable std source explain
the `getcwd` error path. Linux [getcwd(3)](https://man7.org/linux/man-pages/man3/getcwd.3.html)
documents `ENOENT` for an unlinked working directory. These sources explain an
ordinary filesystem lifecycle, without a permission-denial test. They do not
prove the executable's compiler inputs; the pinned real response establishes
the behavior. Twelve whole Codex sources equal the immutable source archive.

The owning case passes **1/0**, seed `501432`, in 1.6 seconds with the same
pinned binary, isolated driver and fixed yolo setup:

```sh
mix test test/native_local_environment_missing_cwd_test.exs --warnings-as-errors --seed 501432
```

| Artifact | SHA256 |
| --- | --- |
| Formatted V520 module | `cae59bce365d828888e22166d5ef2d0eb5c6a392c1978237163a186da57dfa48` |
| Source report `/tmp/samgita-v520-next-gap.md` | `716a13c2e929e972476f6fd286bb5db5798e7cc804623a53296ab9c4d595bf5b` |
| Source evidence `/tmp/samgita-v520-next-gap-evidence.json` | `1d1c8e15112a703f09242f509322dc29007b6f36df0196c55ab60fba6b5d753f` |
| Draft review `/tmp/samgita-v520-independent-review.json` | `0d560a4866cbb9c1856d5fc7a065cb6749b96f45eadfb23efdcbd00915278d8e` |
| V519 integrated review `/tmp/samgita-v519-integrated-review.json` | `7937c2fb06a44b8d58813a8d64f9a6c8477163cd2e3f2e939dbf364b9c88241d` |
| V520 integrated review `/tmp/samgita-v520-integrated-review.json` | `9cfa50bd478df1e3a4965215bfc3f713a6777ace48dbfb46000f27f470b46be0` |
| Focus log `/tmp/samgita-v520-focus-501432.log` | `da68d7d636c595ff7faa4a8049c77ece95ef3432c21e85b1a4b5fda7f0200398` |

V520 retains the same per-case/RPC/capture/event/file limits and confirmed
native/provider ownership cleanup. It promotes only physical owner **3909**,
`v2/EnvironmentInfoResponse.json#/properties/cwd/anyOf/1`, node hash
`b7c373d0981a5441c9dd775ad89a68ba691af04e4da70eaeaacaaf54549837fb`,
to scoped implemented. The four null and three positive responses qualify no
other alias, omitted-field behavior, shell schema or remote/platform profile.
Both first compile/native runs pass without a runtime repair, changed oracle
or relaxed bound. Strict Credo then passes across 600 files; log
`/tmp/samgita-v519-v520-credo.log`, SHA256
`bcf8e6540f0083a8330588f14223eb00bab6b23f32f0bd3ef38dc2355931e4d4`.
Final combined-source results follow below.

Rollback removes only the new tests, selector additions and their exact
manifest evidence. No production runtime, dependency, migration, historical
record or external service changes. Security, credential, authentication,
authorization, approval and permission tests/audits, broad suites and hosted
workflows remain unrun and incomplete. A11, unavailable emitter/external/OS
profiles, full compatibility and release gates stay incomplete. Nothing is
published or deployed.

## Final combined-source functional qualification

All **14 reviewed steps** pass on the final V519/V520 source:

| Check | Actual result |
| --- | --- |
| Explicit 68-file ordinary native selection, seeds `501432`/`987654` | **129/0 each**, 223.325/222.622 seconds command time |
| Selected neutral WebSocket overflow/replay, seeds `455834`/`501432`/`987654` | **3/0 each**, 13 mixed-file cases excluded |
| Outside-umbrella actual-native consumer | **1/0**, without Repo/Phoenix/umbrella |
| Driver/root compile and format | Pass with warnings as errors |
| Inventory consistency, strict Credo, Dialyzer, assets | Pass |

All **1,687** guarded source hashes and the command plan match before, after
and at final binding. Reviewed fingerprint:
`c73312083a489a82c534e28dc4cde12a6c3484cd938fa1471025be9869fc3451`.
All **1,683** other previous guarded sources remain exact. Compared with
`d022cba`, only physical owners3908/3909 change from missing to scoped
implemented; all485 requirements and all6,619 other contracts stay identical.
The binding rechecks every result/log hash and case count, twelve complete
immutable Codex files, the schema/node hashes, binary/archive pins, two Rust
source snapshots, the Linux manual snapshot and independent reviews.

The first binding attempt incorrectly hashed compact JSON, which differs from
the inventory's canonical indented JSON with a final newline. Using the
existing `inventory.encode` fixes only the temporary evidence-binding script.
The corrected proof passes; no repository source, schema, manifest assertion
or test changes were needed, and all guarded hashes remain exact.

| Artifact | SHA256 |
| --- | --- |
| `/tmp/samgita-ordinary-v519-v520-qualified/results.json` | `b8a57e0e171a74b19fcbf1e8139f717bc163c2658d337be9f0cfb4594a605cfb` |
| `/tmp/samgita-ordinary-v519-v520-qualified/source.json` | `7579e92ea4b8e2899be10b59aeeb40d90fa601f2d38c7fd41d3bc40e21098c0c` |
| `/tmp/samgita-v519-v520-final-binding.json` | `c8c47af254fcc95075734bb6bfbb829d2f2473f475d2f5ee6c8aaf0b83b9c5ec` |

Reproduce from the root after reviewing the named selection:

```sh
python3 -B scripts/codex/check_ordinary.py --list
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output <new-evidence-directory>
```

Contracts: **5,493 implemented / 998 missing / 130 blocked**. Requirements:
**462 implemented / 12 missing / 11 blocked**. **Zero verified** entries.
Prohibited/broad/hosted checks, A11, unavailable emitters/external/OS success,
full compatibility and release gates retain their incomplete status. Automatic
CI is suppressed on delivery. No publication or deployment is claimed.

Next is narrow evidence indexing of completed/started realtime notification
thread identities using the unchanged original-frame lifecycle case. Its
distinct producers and existing oracles have been source-reviewed; the two
physical owners remain missing until their exact evidence binding is complete.
