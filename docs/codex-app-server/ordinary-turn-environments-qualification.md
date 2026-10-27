# Ordinary local turn environments

V516 adds one actual-native case after `73f9421`, using stock
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, executable
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The unchanged local assistant peer supplies only model output. No remote
executor, external credential, tool execution or scripted app-server is used.

## Seven-turn lifecycle

Three authored directories define every expected selection before dispatch.
Each turn completes through the real native process and makes exactly one
model request. Complete original RPC JSON bodies and correlated replies are
retained independently of the provider-input and durable-history oracles.

| Turn | Input | Expected native behavior |
| --- | --- | --- |
| Replace | Local B with roots B,A,B; conflicting top-level workspace root | Selection becomes B with ordered, deduplicated roots B,A; explicit selection owns the roots |
| Omitted | No `environments` field | B selection remains |
| Null | `environments: null` | B selection remains |
| Empty | `environments: []` | Selection becomes empty; cwd retains B and model context records local environment removal |
| Sticky empty | Field omitted | Empty selection remains; no duplicate removal context |
| Restore | Local A, nested roots omitted; conflicting top-level B | Selection becomes A with roots A |
| Nested null | Original workspace, nested roots null; conflicting top-level A | Selection becomes workspace with workspace as its root |

Each provider request must contain exactly the authored user-marker history,
prior assistant answers and expected accumulated cwd/root/removal context.
Thread/turn metadata must name the current native identities. A summary-only
settings update supplies an observable matching snapshot barrier without
rewriting the target environment or starting another model request.

Loaded `thread/read` combines persisted history with live configuration; its
environment array is a **live selection snapshot**, not evidence that the array
is stored in the rollout. Separate disk assertions verify every per-turn
cwd/model/turn ID, user/context history and the unchanged complete earlier byte
prefix. No cold restoration of environment arrays is claimed. Final repeated
reads, model journal, source files and empty workspaces remain exact before
and after confirmed owned-process shutdown.

## Pinned ownership and bounds

The [request resolver](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors.rs#L643-L694)
defaults nested missing/null roots to the selected cwd and deduplicates roots.
`request_processors/turn_processor.rs:739–771` gives explicit selections their
own root vector. `core/src/session/session.rs:435–437` replaces selections for
every present array, including empty; omitted/null does not update them.
Context producers emit the ordinary cwd/root and unavailable-environment
changes. Selection runtime types and durable turn context are separate.

Fourteen complete producer files equal the immutable official archive. Five
helper/provider hashes remain unchanged. The source evidence and independent
review bind the exact physical schema node, all seven authored oracles,
history distinction, bounds and cleanup:

| Artifact | SHA256 |
| --- | --- |
| `/tmp/samgita-v516-source-evidence.json` | `2ac018185e157ca9fb58846457dd977b4ec5f8c4c0873990141f310d1d905600` |
| `/tmp/samgita-v516-independent-review.json` | `6972fa200e90ba4b05d9aa752f00207710a960d66f1966bfc4245a7ea9b6fb14` |
| Formatted module | `2771bfd44b8890008a338b46874a9e60727e16fa1f4792597b8fd03ff1a568bb` |
| `/tmp/samgita-v516-focus-501432.log` | `2489b834adb762a10b836cbe67c10a95bbafa50a443c8b1907b44cf3ffb80797` |

Bounds are 60 seconds per case, 20 seconds per turn and 5 seconds per RPC or
snapshot barrier; 32 request/reply records per direction, 4/64 KiB per body and
1 MiB combined; 256 events/1 MiB per stage; 1 MiB rollout, 2,048 rows and
256 KiB per row. Exactly 27 native RPC pairs and seven provider requests are
required. Overflow/gaps fail explicitly. No sleep, retry, private-state mutation,
manufactured history or relaxed cleanup is used.

## Scoped qualification and limits

The exact owning file passes **1/0**, seed `501432`, in 2.4 seconds, in the
verified Devenv environment with the pinned binary and fixed yolo setup:

```sh
mix test test/native_turn_environments_lifecycle_test.exs --warnings-as-errors --seed 501432
```

Only owner **6522**, `v2/TurnStartParams.json#/properties/environments`, gains
scoped implemented evidence. Nested/shared aliases, complete referenced
payloads, remote executors, other transports and cold selection persistence
receive no inferred credit. Zero entries become verified. Final combined-source
functional results follow below.

Rollback removes this new test and its supplemental evidence/selector entry.
No production runtime, database, historical data or external service changes.
Security, credential, authentication, authorization, approval and permission
tests/audits, broad suites and hosted workflows remain unrun and incomplete.
A11, unreachable emitters, external/OS success, full compatibility and release
stay incomplete. Nothing is published or deployed.

## Final combined-source functional qualification

All **14 reviewed steps** pass on the combined V515/V516 executable source:

| Check | Actual result |
| --- | --- |
| Explicit 64-file ordinary native selection, seeds `501432`/`987654` | **125/0 each**, 214.705/216.709 seconds command time |
| Selected neutral WebSocket overflow/replay cases, seeds `455834`/`501432`/`987654` | **3/0 each**, 13 other mixed-file cases excluded |
| Outside-umbrella actual-native consumer | **1/0**, without Repo/Phoenix/umbrella |
| Driver/root compilation and format | Pass with warnings as errors |
| Inventory consistency, strict Credo, Dialyzer, assets | Pass |

The runner's command plan and all **1,683** guarded source hashes are identical
before, after and at final binding. Reviewed fingerprint:
`958ff3ca71304d64ced9f33172ed4b0208ffe8483c20a53ac5a177e8bcd11fdb`.
The final binding rechecks all 24 complete immutable producer files, the binary
and archive pins, five helper/provider files, both precise schema nodes and
every log hash/expected count. It also confirms that the two progress records
are the only manifest changes; all requirements and other contracts remain
identical. Plugin helper reconstruction and the initial static failure are
preserved in the independent review.

| Artifact | SHA256 |
| --- | --- |
| `/tmp/samgita-ordinary-v515-v516-qualified/results.json` | `70917e95500f79f7c1510388d0125889e1ef89710096c7fcfcb9bcc3ba5e508d` |
| `/tmp/samgita-ordinary-v515-v516-qualified/source.json` | `51263e4bfa52197d6461a67d9be86a7e429663d9d0259e51c7d9fc83ccb13ad2` |
| `/tmp/samgita-v515-v516-final-review.json` | `befd13c789dd57118a316020eca555660d73df732517b9eb8265a6276fd4a82d` |
| `/tmp/samgita-v515-v516-final-binding.json` | `226aec13d1fc7460962902e43875772512905ca445744e52d3069b6d7c053297` |

Reproduce from the root, first reviewing the selection:

```sh
python3 -B scripts/codex/check_ordinary.py --list
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output <new-evidence-directory>
```

Ledger: **5,491 implemented / 1,000 missing / 130 blocked** contracts;
**462 implemented / 12 missing / 11 blocked** requirements; **zero verified**.
These ordinary checks do not replace prohibited tests, audits, broad suites,
hosted workflows, full compatibility or release gates. Current A11,
source-unreachable emitters and unavailable external/OS success remain open.
No publication, release or deployment follows from these results.

Next ordinary work is the source-reviewed local plugin-search cursor/limit
differential. Its scratch draft and independent review are not integrated or
executed, and earn no field promotion. Remote-limit success remains missing;
local directory behavior cannot qualify it. Continue that logical unit with
parent-owned focused and final-source checks.
