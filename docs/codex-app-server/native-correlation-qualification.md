# Native request correlation continuation

Status: 60 precise physical owners implemented; **full compatibility incomplete**.
Target: Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

`TurnFixture.call/3` now supplies a VM-unique string request ID and asserts that
the native response returns that same ID before returning its unchanged result.
The owning tests retain their independent content, persistence and side-effect
assertions. No retry, duplicate request, timeout increase or weakened assertion
is introduced.

The selected operations are `server/diagnostics`, `thread/metadata/update`,
`thread/attachment/add`, `thread/attachment/list`, `thread/attachmentOwner/list`,
`thread/attachment/remove`, `thread/memoryMode/set`, `rollout/compress`,
`thread/revert`, `thread/items/read`, `hooks/list` and `turn/settings/update`.
For each operation, only the ClientRequest branch root, ID, method, method
literal and params-root owner gains evidence. Nested parameter fields, numeric
or error IDs, alias owners and other helper consumers do not inherit evidence.

## Reproduction and scoped checks

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-native-correlation-v29-r1-20261025.py
python3 -B /tmp/samgita-bind-v29-correlation60-owners-20261025.py
python3 -B scripts/codex/inventory.py --check
python3 -B -m unittest discover -s scripts/codex -p 'test_*.py'
git diff --check
```

The first runner referenced an absent preflight fixture and failed before any
Mix/native command. Its failure is preserved in
`/tmp/samgita-native-correlation-v29-runner-first-failure-20261025.json`.
The corrected runner checks the actual owned stdio launcher and Python fixture
syntax; no product or test behavior was changed to address that runner error.

The complete eight-file block passes **54 tests / 0 failures** at each seed
501432 and 987654, with zero exclusions. The exact file list and commands are in
`/tmp/samgita-native-correlation-v29-r1-20261025/results.json`. Namespace and
sandbox preconditions, warning-free driver compilation, driver format and strict
root Credo pass. Both **1,495-file source** and immutable executable guards match.

The binding checks every original row, canonical schema node/hash, selected
native test, helper preimage, command and terminal result. Only 60 manifest rows
change, and the complete manifest equals its generated expected JSON.
Terminal report:
`/tmp/samgita-v29-correlation60-owner-terminal-20261025.json`, SHA256
`6416278cf4a92d737c10d6229ae99d2c517dd9cd781150805b9f640f1f36dbd2`.
The adjacent bound index records each exact pointer, test/hash and effect oracle.

Inventory consistency and 37 tooling regressions pass. Contracts become
**4,185 implemented / 2,436 missing**, zero verified; requirements remain
**462 implemented / 12 missing / 11 blocked**, zero verified. This is scoped
native evidence: the shared helper still requires the complete final driver and
profile matrix. Remaining behavior, final-source local/hosted checks, A11,
unreachable legacy emitters, external/backend/OS success and retained failures
remain incomplete. No tag, publication or deployment occurs.
