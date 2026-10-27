# Existing native process spawn/stdin request IDs

V455 binds two omitted string-ID witnesses at `main`
`dbfb25bff596f81c75816ab23a74839807697085`. It changes no code, test, fixture
or runtime. Existing ordinary `native_process_notification_envelope_test.exs`
independently generates nonempty string IDs before each request, captures actual
outgoing and incoming bytes, checks full sent maps/encoded bytes, matches the
native response ID and requires only id/result response keys.

Two cold uncapped/cap0 profiles perform two real process/spawn and six real
process/writeStdin exchanges. The owned child journals its actual PID, exact
prescribed binary stdin and EOF, writes independently specified binary stdout/
stderr and exits 7. After two writes a diagnostics barrier finds the child alive
without output; explicit stdin close supplies EOF. Complete output/exit events,
uncapped reconstructed bytes and cap0 empty deltas with independent nonempty
child writes establish the actual outcomes. Post-exit diagnostics keeps the
original native process usable. Empty ACKs alone cannot satisfy those oracles.

Only these `schema:ClientRequest.json#` fields gain scoped implemented evidence:

| Index | Pointer | Parent method |
| --- | --- | --- |
| 1064 | `/oneOf/155/properties/id` | process/spawn |
| 1069 | `/oneOf/156/properties/id` | process/writeStdin |

Both node hashes are
`f1fb3724bb7835add8ed79ef8a7e1acaf3c9c5761502e6ae54c85d0c7f6c82e7`.
Their separate parent hashes/method identities are recomputed in the complete
canonical export. Eight RPC/declaration/process/dispatch/outgoing/transport
files match the official archive at Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`. Actual spawn sends its response
after creating the child; stdin control performs real writes/close and settles
its control result. Both paths retain the original connection-scoped typed ID.
No equal-hash sibling or shared RequestId alternatives inherit this evidence.

The unchanged owning test SHA256 is
`1193017a1cdb61feb234f017580dd52b4b9bb41b442971fb89880a8cbef98ee1`.
Both V450 reviewed **58/0** ordinary command lists enable it; all 417 functional
source hashes/nine successful logs and 825 static source hashes/four successful
logs remain exact. No new native/test run occurs. The original 96-frame,
8192-byte outgoing/65536-byte incoming, 262144-byte aggregate, 64-event Session,
five-second stages and 30-second case bounds remain. Checked disappearance of
all actual child/native PIDs, owner DOWN/completion and closed Port remain.
Inventory consistency and diff whitespace are checked after this binding.

Report `/tmp/samgita-v455-candidate.md`, SHA256
`d4dc39e232cbed065b8c13da5781ae6b4dda0a68282f7a29f1959a0e1da50c3b`;
binder `/tmp/samgita-v455-bind.py`; source/node binding SHA256
`529817158e7a0b31771b43fa9da1a79ae887fde2a6539c864c3485663d442531`;
evidence SHA256
`67ce67647ca6460477e87cc38c985c20c80c489ef6ec2de5ecde530be1c8beab`.
[V450](filesystem-typed-id-qualification.md) and the
[static checkpoint](repair-qualification.md#permitted-static-checkpoint-after-v453)
record the reused exact command/result/source guards.

Contracts: **5,276 implemented / 1,265 missing / 80 blocked**; requirements
remain **462 implemented / 12 missing / 11 blocked**, zero verified in both.
Neither reviewed test calls command write/terminate/resize or process kill/
resizePty, so those ID fields stay unqualified. No integer/reused/late/concurrent
ID, disconnect/replay/cancellation/signal/PTY/other OS/transports/full-goal claim.
Fixed YOLO stays setup only; security/permission tests/audits, broad suites and
hosted workflows remain unrun. A11, unavailable producers, external/platform and
release gates remain incomplete. No publication or deployment. Rollback reverts
only these two evidence bindings and documentation. Continue original command
request-byte evidence on the existing output/exit journey.
