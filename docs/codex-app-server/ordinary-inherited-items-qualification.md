# Ordinary inherited selective-item reads

V518 continues after `b9ce38e` using stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Two sequential, explicitly owned native processes use the unchanged local
assistant-only model fixture. The peer supplies model output; every app-server
request, reply, item and history result comes from the pinned real executable.
No Samgita application, database, external service or existing task is used.

## Native behavior

Six authored Unicode user messages and client IDs identify four original
parent turns, one child turn and one later parent turn. Independently authored
provider item IDs and assistant text define expected payloads. Original native
item notifications supply only native identities and independently bounded
timestamps; full history never defines its own initial oracle.

| Stage | Required result |
| --- | --- |
| Paginated fork before parent turn four | Child retains turns one through three; turn four is absent |
| Select inherited items through child | Reversed and duplicate selectors mixed with an absent ID return exact entries in original durable order |
| Explicit branch divergence | Child-local and parent-local work stays in its own history; provider inputs contain the prescribed branch prefix |
| Parent revert before turn three | Parent retains only turns one and two and uses a replacement rollout path; child still returns original turn-three entries |
| Source preservation | Original child-referenced parent rollout and child rollout remain byte-exact across parent revert |
| Distinct cold process | Its first content RPC is inherited `thread/items/read`, before full history or resume; loaded-thread list stays empty through direct reads |
| Explicit child resume | Complete/selective history remains exact; provider request count stays six and other retained rollouts remain unchanged |

Resume may append normal child session metadata. Its original rollout must
remain an exact byte prefix. This is separate from the byte-exact cold-read
and parent-revert controls. Nothing writes manufactured rollout history,
replays an execution, or treats a read as implicit resume.

The pinned [request processor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L3622-L3669)
routes selected IDs and turn identity to the durable store in ascending item
order. `thread-store/src/local/thread_history/segment_paging.rs:285–333`
traverses retained lineage segments; `local/paginated_fork.rs:108–154` and
`local/revert_thread.rs:105–153` explain the retained source boundary and
replacement parent path. Twenty-six cited source files and six additional
V1/feature-dispatch files were independently compared in full with the
immutable official source archive. Those source checks establish provenance,
not native execution by themselves.

## Verification and limits

The owning actual-native case passes **1/0**, seed `501432`, in 3.5 seconds;
strict Credo passes across 598 files. From the independent driver directory
in the verified Devenv environment, using the pinned binary and fixed yolo:

```sh
mix test test/native_inherited_items_read_lifecycle_test.exs --warnings-as-errors --seed 501432
```

| Artifact | SHA256 |
| --- | --- |
| Formatted test module | `889d682b8e246e5f839a9d85f12f3049cd83d259aecaf2dcc79ddae9022f57d1` |
| Source evidence `/tmp/samgita-v518-source-evidence.json` | `219cedf1340a3b9bad4363504bf246e757dd3ad06a6b412a40a04d1a8227385d` |
| Source review `/tmp/samgita-v518-independent-source-review.json` | `177f447c00d68a0f27f6cb4ed4569504ab5215936623a7d084ec3bc1f0192127` |
| Corrected draft review `/tmp/samgita-v518-independent-draft-review.json` | `76ad504e1044c59b067d6f5a48d250a92d4fce494f8127deb3fce00ffe13515b` |
| Integrated review `/tmp/samgita-v518-integrated-review.json` | `5a3b2c4abf4d438655497a97be8f494e4d8988cc80f795eb1095c267de8c6d48` |
| Focus log `/tmp/samgita-v518-focus-501432.log` | `4314c0bbca66179916f14dad0fd0ce99e8786f13f784c078be1ce8fc7184a620` |
| Credo log `/tmp/samgita-v518-credo.log` | `578f8c14261b17337650e8530a8d7780f95229ba55a9cac88448e0e4a2eb105d` |

Pre-integration review corrected one final prefix read to use the existing
bounded snapshot function. The prefix oracle and 2 MiB bound are unchanged;
integration then changes formatting only. The first compile/native run and
strict static check pass without a runtime repair or relaxed assertion.

Every successful outgoing request and original incoming response is captured
as encoded JSON and complete maps with exact unique-string correlation. Item
notifications must match original incoming frames. Bounds remain 100 seconds
per case, 20 seconds per turn and 5 seconds per RPC; 128 outbound/768 inbound
frames, 4/128 KiB per body and 4 MiB aggregate capture; 256 events/1 MiB and
2 MiB per retained file. Confirmed guardian death, completion flag, closed Port
and absent owned native PID are required before cold replacement and teardown.

Only existing implemented request/response `thread/items/read` entries and
physical schema owners **5281/5282/5283/5679** gain supplemental evidence.
There are zero state/count promotions. The sixteen missing selective-response
owners remain unchanged. Inspected analytics or start-only producer paths
establish neither global emitter unreachability nor an upstream blocker.
Complete referenced item types, aliases, arbitrary request IDs, other
transports, external/OS profiles and full compatibility receive no credit.

Rollback removes only this test, selector addition and supplemental metadata.
No production runtime, dependency, migration, historical data or service changes.
Security, credential, authentication, authorization, approval and permission
tests/audits, broad suites and hosted workflows remain unrun and incomplete.
A11, unavailable emitters/external/OS success, full compatibility and release
gates stay incomplete. No publication or deployment is claimed.

## Final combined-source functional qualification

All **14 reviewed steps** pass on the final V518 source:

| Check | Actual result |
| --- | --- |
| Explicit 66-file ordinary native selection, seeds `501432`/`987654` | **127/0 each**, 221.564/222.569 seconds command time |
| Selected neutral WebSocket overflow/replay cases, seeds `455834`/`501432`/`987654` | **3/0 each**, 13 mixed-file cases excluded |
| Outside-umbrella actual-native consumer | **1/0**, without Repo/Phoenix/umbrella |
| Driver/root compile and format | Pass with warnings as errors |
| Inventory consistency, strict Credo, Dialyzer, assets | Pass |

All **1,685** guarded source hashes and the exact command plan match before,
after and at final binding. Reviewed fingerprint:
`ebe4b4242da13ff22f00f53b5fab3da0ea6518a6000c68df7bc4fdad10e44566`.
The final binding rechecks every result/log hash and expected case count, all
32 immutable source files, binary/archive pins, and the exact six manifest
changes. Compared with `b9ce38e`, only evidence/test/limitation metadata changes
in two requirements and four existing schema owners. Every state and all other
nodes remain unchanged. All **1,682** other previous guarded sources stay exact.

| Artifact | SHA256 |
| --- | --- |
| `/tmp/samgita-ordinary-v518-qualified/results.json` | `9fdb00abf38a539db1bc7b62d4c77cdeebdebeb74f7215d067ec29d3257c9e80` |
| `/tmp/samgita-ordinary-v518-qualified/source.json` | `a9e35416249d60f58956090a4a43f61a9447c5dbee4a9f0286c97bbcd83b1ac9` |
| `/tmp/samgita-v518-final-binding.json` | `dc4cf2d561ec9ca475a0c95837aadc3200e1f531a81aeb14f6b2b174ee7fd18a` |

Reproduce from the root after reviewing the named selection:

```sh
python3 -B scripts/codex/check_ordinary.py --list
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output <new-evidence-directory>
```

Counts remain **5,491 implemented / 1,000 missing / 130 blocked** contracts
and **462 implemented / 12 missing / 11 blocked** requirements; **zero verified**.
Prohibited/broad/hosted checks, A11, unavailable emitters/external/OS success,
full compatibility and release remain incomplete. Automatic CI is suppressed
on delivery; nothing is published or deployed.

Next is the reviewed ordinary local `environment/info.cwd` PathUri case with
an independently authored encoded path, live directory rename and cold repeat.
Its scratch draft is not integrated, compiled or executed and earns no state
promotion. The null branch and other aliases remain missing.
