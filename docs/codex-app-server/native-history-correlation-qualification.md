# Native retained history and correlation continuation

Status: 103 precise physical owners implemented; **full compatibility incomplete**.
Target: Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

| Native behavior | Exact owners | Independent oracle |
| --- | ---: | --- |
| Retained opaque media and non-null image detail | 11 | Prescribed file-ID image, tiny WAV URL and synthetic ciphertext survive provider forwarding, live completion and first cold selective read. Existing low/high detail assertions qualify only their non-null detail arm. No remote file authorization, media inference or decryption claim. |
| Persisted completed collaboration waits | 20 | Actual spawned child IDs come from correlated native results; fixed child completion messages and null prompt/model/effort prescribe the exact canonical item. Warm/first cold selectors preserve the eleven-request provider journal. |
| Paginated user-shell actions and failure | 19 | Fixed cat/ls/grep/false commands in an owned private namespace prescribe read/list/search classification, output and exit code. Files remain unchanged, provider calls stay zero, and first cold selective reads retain exact entries. |
| Request-ID properties for 53 named successful methods | 53 | The explicit unique string ID is pinned in the returned response before method-specific state, file, provider or history assertions. Exact calls/oracles are indexed; ACK-only/error-only/mock paths and integer-ID branches are excluded. |

The shell oracle reads passwd UID 0 because the unchanged fixture uses
`--map-root-user`. Host-user `SHELL`/UID do not prescribe the native shell.
This correction occurred in source review before runtime. Fixed `false` gives a
deterministic failure without locale-dependent missing-file stderr. Original
legacy shell-history tests and owned-process cleanup remain intact.

## Preserved first failure and repair

The first complete fourteen-file run at seed 501432 had **94 tests / 1 failure**.
The new opaque-media branch configured the model twice. `configure_model/2`
prepends `model_catalog_json`, so Codex correctly rejected the duplicate TOML key
at thread/start before starting a turn. The repair supplies this branch's audio
modality tag to the existing first setup call and removes the second call.
Existing branches retain their prior model settings; no shared helper, deadline,
assertion, retry or native validation changes.

First-failure report:
`/tmp/samgita-native-history-v35-first-failure-20261025.json`, SHA256
`70d78ea5b37c0324b5471f4078be14acf6233ce9935404449a358b20c864e8b0`.
The original source snapshot, runner and failed log remain preserved.

## Terminal scoped evidence

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-native-history-correlation-v35-r1-20261025.py
python3 -B /tmp/samgita-bind-native-history-v35-20261025.py
python3 -B /tmp/samgita-bind-native-correlation53-v35-20261025.py
python3 -B scripts/codex/inventory.py --check
python3 -B -m unittest discover -s scripts/codex -p 'test_*.py'
git diff --check
```

Both complete fourteen-file runs pass **94 tests / 0 failures**, seeds
501432/987654, zero exclusions. Namespace/sandbox prerequisites, warning-free
compilation, driver format and strict root Credo (442 files) pass. Both
**1,495-file source** and immutable executable guards match. Exact file membership,
commands, exits and logs are in
`/tmp/samgita-native-history-correlation-v35-r1-20261025/`.

The parent checks original rows/canonical nodes/hashes, 34 history source
excerpts, 212 ID call/helper/oracle excerpts, 13 unchanged ID dependency preimages,
new literal assertions and both native results. Only the selected 50 history
and 53 ID rows change; the full manifest equals the generated expected JSON.
The exact source-only candidate inventories remain separately labelled as
proposals until bound to these fresh results; historical v27 is not inherited.

Terminal reports:

- `/tmp/samgita-v35-native-history50-owner-terminal-20261025.json`, SHA256
  `44f519f6e5eb127773bc43214ca471bd87ca867d073599a5766dad97d6c25424`.
- `/tmp/samgita-v35-native-correlation53-owner-terminal-20261025.json`, SHA256
  `aed5439dac5814ac179686a47663e62c1ecee97aa932b739d992cb1ee688c038`.

Their adjacent indexes retain exact pointers, test hashes, calls and limits.
Inventory consistency and 37 tooling regressions pass. Contracts become
**4,337 implemented / 2,284 missing**, zero verified; requirements stay
**462 implemented / 12 missing / 11 blocked**, zero verified.

## Unavailable output variants remain incomplete

The two ThreadItemsReadResponse null arms for image detail and savedPath cannot
be emitted by the pinned `skip_serializing_if = Option::is_none` serializers:
[detail](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/protocol/src/models.rs#L2206-L2231),
[savedPath/public item](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/ext/items/src/image_generation.rs#L21-L43).
The exact anchors/hashes and all 148 audited owners are in
`/tmp/samgita-thread-items-read-v33-20261025.json`, SHA256
`db160a9baf8c1d07b0a759e6ff4d22442a1082af0954d37abe75a393141dc752`.
Omission is not null evidence. Five inProgress history leaves still need an
actual completed-record producer; live started items do not qualify canonical
history. The [queue-start audit](queue-lifecycle-qualification.md#pinned-queue-start-response-reachability)
separately records its 57 unreachable success-result owners without promotions.

Complete default-driver/profile, populated-platform, independent-consumer and
final-pushed hosted qualification remains mandatory. Retained aggregate/cursor/
listener failures, A11, legacy emitters and external/backend/OS success remain
incomplete. No tag, package publication, production migration or deployment.
