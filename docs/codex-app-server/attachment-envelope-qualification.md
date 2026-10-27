# Native attachment changes and durable membership

V442 adds one ordinary-only native attachment lifecycle case on `main`
`3138b6f8ddf5074b226dfea3d11b2998b8bb6db5`. One genuine durable thread is
materialized by one finite local model turn. Pinned Codex, rather than the
model fixture, implements attachment storage, mutation responses and notices.
The test creates an attachment, repeats the add with different content, removes
it twice, recreates it, then reads the retained replacement from a distinct
cold native process on the same isolated synthetic home.

Independent literals prescribe type, identity key, original and replacement
JSON content. Native-generated UUIDv7 and Unix-second creation time are checked
once and retained exactly. Duplicate add must return the original ID, time and
content; duplicate remove leaves membership empty. Two repeated native list and
owner-list pairs after each stage require exact records and membership. The
cold process stays unloaded before and after its reads. Exactly one provider
request is frozen through both processes; no additional inference occurs.

A test-local Stdio wrapper retains original inbound and outbound JSONL before
Session decoding. The three complete native attachment notices must be exactly
`created(A), deleted(A), created(B)`, with known method and independent params,
the original initialized generation and native `emittedAtMs` bracketed in host
milliseconds. Their correlated native mutation responses precede the notices.
Complete original JSON/Wire decoding and canonical experimental schema validation
agree. Exactly 30 warm and nine cold outgoing method frames include one response
per RPC, unique request IDs and the initialized notification. Cold attachment
notices remain empty through the finite read barriers.

The fixed bounds are 128 captured frames, 64 KiB inbound/8 KiB outbound per
frame, 2 MiB total, 128 buffered events and 5-second RPC/positive-notice
deadlines, with a 60-second module deadline. Overflow fails explicitly.
Config/catalog/script bytes and the empty workspace remain unchanged. Both
native processes retain fixed YOLO launches and the existing confirmed
owner/Port/PID cleanup; the local provider's owner and Port are also checked.
No production, shared fixture, cleanup helper or existing mixed test changes.

Existing `Owner.await_exit` deliberately discards ordinary stdout while
confirming shutdown. This test preserves that behavior. Exact duplicate-notice
absence covers the finite observed pre-close RPC/Session barriers; it does not
claim capture of shutdown-tail bytes or absence of arbitrarily delayed output.
The observed prefix is frozen and checked again after cleanup.

## Native source and exact contract

Pin: `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`,
binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The selected executable and running diagnostics-identified executable match.
Six complete native source files match the immutable source archive:
message dispatch, attachment request processor, local store, state runtime,
attachment protocol declarations and outgoing-message timestamp wrapper.
Native state commits before returning; only Created/Removed emit notices,
and those responses are queued before their corresponding notices.

Only `schema_contracts[2819]`, exact ID
`schema:ServerNotification.json#/oneOf/11`, gains scoped implemented evidence.
Its canonical node SHA256 is
`1f31c7967b8a2de4aa0387663993a96739ec2cbe3215072234541ff40e92f9fc`.
The full canonical export matches the pinned generated export; no sibling,
account field, alias or already implemented payload gains duplicate credit.
Source/node binding `/tmp/samgita-v442-binding/source.json`, SHA256
`1737836c0d65a25022de34a12ef2b646d0541d2bd61496021fb67bebaadd7da7`.

## Actual permitted verification and limits

All nine commands in `/tmp/samgita-v442-functional-checks/final/results.json`
pass: focused **1/0**, reviewed 33-file ordinary block **55/0** at both
`501432` and `987654`, dependency Python syntax, scoped format, warning-free
driver compile, root strict Credo, inventory consistency and reviewed
outside-umbrella consumer **1/0** (generated seed `340865`). The consumer uses
actual pinned Codex without Samgita Repo, Phoenix or platform startup.

Results SHA256:
`3ed961fb1f9ccfc02847ab25e378f4939265cefc7196dda736cef0f40d0c82c4`.
All 415 source hashes remain stable, with all 414 prior paths unchanged and
only this new test added. Guard SHA256
`f30cd59ace8042e03a870b6abbbf484f15f97b65793a8bc2987dbb75955af95a`.
Test SHA256
`109055e590414462de9a8edd7edb51685ffcbd3510ae28be632499b8808e9761`.
Binder `/tmp/samgita-v442-bind.py`; evidence JSON SHA256
`5adbb6fa712a03aeffffce460e6ac85153c76e48813194a61eae8da95de29ab2`.

Contracts: **5,247 implemented / 1,308 missing / 66 blocked**. Requirements
remain **462 implemented / 12 missing / 11 blocked**, zero verified in both
ledgers. Multi-client/concurrent writers, fork-copy, pagination, other native
stores/OS/transports and real providers/platforms remain unqualified. No mock
substitutes for a native attachment or legacy producer. Security/permission
tests and audits, broad suites and hosted workflows remain unrun under the
user's restriction. A11, upstream-unreachable legacy, external/platform/full-goal
and release gates remain incomplete. No publication or deployment. Rollback
reverts this new test and one evidence binding without changing runtime or
historical data. Continue the next bounded ordinary behavior from the ledger.
