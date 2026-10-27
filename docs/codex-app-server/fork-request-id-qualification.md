# Existing native fork string-ID evidence

V452 corrects one omitted evidence binding at `main`
`93df63c991e4f10b071dbaa133323f566f9522e9`. It changes no executable, test,
fixture or runtime behavior. The unchanged ordinary
`native_fork_git_notification_test.exs` already independently generates a string
ID before thread/fork, retains original outgoing and incoming bytes/maps, checks
the exact correlated response and orders request before response before the
child's native thread/started notification.

Actual persistent child identity, lineage, name, rollout path and Git facts are
checked against the owned parent/Git fixture, with unchanged parent rollout/Git
tree and empty provider journals. That independent readback prevents an unrelated
empty success from satisfying the journey. Full request bytes and id/result
response keys remain asserted. Existing capture limits, native/fixture cleanup
and no-uncertainty controls remain; no second fork or redundant ID scenario runs.

Only index **1554**, `schema:ClientRequest.json#/oneOf/9/properties/id`, gains
scoped implemented evidence. Node SHA256
`f1fb3724bb7835add8ed79ef8a7e1acaf3c9c5761502e6ae54c85d0c7f6c82e7`
and parent method thread/fork are recomputed from the full canonical export.
This is a string-ID profile for this physical reference, not qualification of
the referenced int64 alternatives, whole RequestId, sibling IDs or all fork
variants. Seven production declaration/dispatch/processor/outgoing/transport
files match the official archive at source
`83086188ae0614bd882818ff1aa23f3194962012` (Codex `rust-v0.163.0`). Fork sends
its typed response internally before ThreadStarted; it does not use the generic
Some(payload) response tail. That route preserves the supplied connection/ID.

The test SHA256 remains
`23aee62ad73fe39db69ccc8fe0b77c24172e89788a110e645a4a193a1323a28b`.
Current V450's 417-source guard and nine successful logs remain exact; both
reviewed **58/0** ordinary command lists explicitly enable this unchanged file.
V450's focused **1/0** belongs to the filesystem test. V452 runs no new native
case and does not relabel that focused result as a fork-specific run. Earlier
[V430 fork evidence](fork-git-notification-qualification.md) remains historical.
Inventory consistency and diff whitespace are checked after this binding.

Report `/tmp/samgita-v452-candidate.md`, SHA256
`44646a7c02d2748cc332cad04123279e0b6bfb9cd7f90de1fbb1ad5cb31adc63`;
binder `/tmp/samgita-v452-bind.py`; source/node binding SHA256
`0e29e0fd351606b75f795d150d959cf6dd9b86734c76de16704f4c2c2ca20eca`;
evidence SHA256
`808c630d313ebb81b89905c08a8ead37b3e6e7af7593272561684b2cb0219e45`.
The [filesystem qualification](filesystem-typed-id-qualification.md) records
the reused exact command/result/guard hashes and independent consumer result.

Contracts: **5,271 implemented / 1,270 missing / 80 blocked**; requirements
remain **462 implemented / 12 missing / 11 blocked**, zero verified in both.
No integer/reused ID, concurrent or cross-connection correlation, ambiguous
disconnect/replay, all fork results, other transports/OS or full-goal claim.
Fixed YOLO remains setup only. Security/permission tests/audits, broad suites
and hosted workflows remain unrun. A11, unavailable producers, external/platform
and release gates remain incomplete. No publication or deployment. Rollback
reverts only this one evidence binding and documentation. Continue the existing
local plugin-search correlation evidence.
