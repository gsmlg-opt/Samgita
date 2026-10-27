# Native thread revert: original notice and retained history

V441 strengthens the three ordinary thread-revert profiles on `main`
`7e809d2723c54e6d299e09f519172cf24f0a1955`. The successful case uses genuine
pinned Codex to run two synthetic text turns, revert before the second, read
the retained first turn through actual cursors/full history, and reconnect and
resume that retained history. The known workspace sentinel remains unchanged;
exactly two local model-provider requests occur. The provider supplies model
data only, never app-server notices or a replacement history implementation.

The test-local Stdio wrapper now captures selected original thread/reverted
JSONL before Session decoding, forwarding all messages unchanged. Its ledger
fails explicitly beyond 128 selected records, 64 KiB per frame or 1 MiB total.
Exactly one original and projected notice must equal the complete independently
prescribed envelope: method, the already known genuine thread ID and native
emittedAtMs bounded by host observations around the successful request. Known
notification kind and original initialized generation, direct original JSON/Wire
decoding and canonical experimental ServerNotification validation are required.

The original invalid-target request still produces its exact native error,
unchanged history and no notice; now its raw selected capture must also stay
empty. Both retained ephemeral/legacy history-mode rejection profiles likewise
leave the selected ledger empty without inference. The successful capture
remains exact through cursor/readback, explicit reconnect/reinitialize/resume,
no-replayed-notice assertions and final owned cleanup. Reconnect increments
generation normally; the original event keeps its original generation. No
extra turn or management request is added, and no mutation is automatically
resent. Original 10-second notice and 60-second module deadlines remain.

The shared cleanup registration specifically matches transport Stdio. For the
test-local wrapper, only this profile registers the equivalent saved-connection
on_exit calling unchanged `StdioSessionFixture.close/2`; explicit final close
remains. The wrapper delegates close to the same Stdio implementation. No
shared cleanup helper, production lifecycle implementation or policy behavior
changes. Fixed YOLO launches remain.

## Native provenance and exact owners

Stock `thread_processor.rs:606–629` sends the typed notice only after a genuine
successful revert response. Native store revert creates an immutable replacement
rollout referencing the retained prefix and switches the current path with CAS;
the old rollout remains intact. Public protocol declarations and outgoing-message
code provide the exact thread/reverted spelling and native emission time. Five
whole native producer/store files match the immutable archive. The test proves
its public retained-prefix/read/reconnect behavior, not every internal CAS race.

Pin: Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Only four physical canonical ServerNotification owners gain scoped implemented
evidence:

| Owner | Canonical pointer | Node SHA256 |
| --- | --- | --- |
| 3119 | `/oneOf/8` | `0f385115e14bf23abb08c887519932f0fe153ef5ea63bf01e007637527d8c011` |
| 3120 | `/oneOf/8/properties/method` | `11a1dfa02f070ad4e973b0ea86b8e69271c9dceee32dda65a60ea80ca1cc42a3` |
| 3121 | `/oneOf/8/properties/method/enum/0` | `3e5d99d16e5a7de89c5d43c3d9b195e3c22877294d104781bd9149120b5b1754` |
| 3122 | `/oneOf/8/properties/params` | `4a86501cf0051b0637242f38455f6dfe67c0c0bc1fad086e20213ebd1b76deb0` |

Source/node binding `/tmp/samgita-v441-binding/source.json`, SHA256
`788725b670db70af2f2d9b9ac2965b65fa6a04556be545e309774e0fc4dae3b1`.
Already implemented request/result fields, aliases and standalone params gain
no duplicate evidence. Legacy history has only its native rejection here; no
mocked legacy success or approval producer is substituted.

## Actual permitted checks and limits

All nine commands in
`/tmp/samgita-v441-functional-checks/final/results.json` pass: focused **3/0**,
the reviewed 32-file ordinary block **54/0** at both `501432` and `987654`, Python
dependency syntax, scoped format, warning-free driver compile, root strict
Credo, inventory consistency and the reviewed outside-umbrella consumer **1/0**
(generated seed 778337). The latter uses the actual pinned executable without
Samgita Repo, Phoenix or umbrella startup. No external model service or paid
operation runs.

Exact command/log ledger SHA256:
`b2d1c1500931505470484d87e245affeae9a8df4e85615e247cdb8d2850b3cf2`.
All 414 source hashes remain stable; 413 prior paths stay exact and only the
selected profile changes. Source guard SHA256
`cb369990f65c55d53d9d5b8c1d3f423e17684892f9eb4cca44c97e26ac28129f`.
Final test SHA256
`2a5abfa40a0fcdd1e904943916f1d00e2c66f8bbf9cffcf1ee824d64cc127248`.
Binder `/tmp/samgita-v441-bind.py`; evidence JSON SHA256
`7697ecc8316e588b9ce46d2f61887b0994421b22e8cf80f18ef46c2f99971744`.

Contracts: **5,246 implemented / 1,309 missing / 66 blocked**; requirements
remain **462 implemented / 12 missing / 11 blocked**, zero verified in both
ledgers. Active-turn/concurrent revert, internal CAS conflicts, fork/compression
branches, real providers/services and other OS/transports remain unqualified.
Security/permission tests and audits, broad suites and hosted workflows remain
unrun under the user's restriction. A11, upstream-unreachable legacy, external/
platform/full-goal and release gates remain incomplete. No publication or
deployment. Rollback reverts this test-local capture and its four evidence
bindings without changing runtime or historical records. Continue the next
bounded ordinary native lifecycle from the remaining manifest gaps.
