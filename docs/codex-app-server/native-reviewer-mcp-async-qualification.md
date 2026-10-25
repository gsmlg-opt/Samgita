# Native reviewer, MCP presentation and async messages

Status: 46 exact contracts implemented; **full compatibility incomplete**.
Target: Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

| Behavior | Physical owners | Independent oracle |
| --- | ---: | --- |
| Current-turn reviewer and saved defaults | 7 | Both opposite reviewer changes while a dynamic tool is pending; omission/null preserve the active change, while an explicit-null future turn keeps its saved thread default. Human approval is explicitly declined; Guardian returns a fixed high-risk denial with exact rationale. Both command items remain declined with null output/exit. Five parent provider requests and exactly one Guardian request are required. |
| MCP UI and correlated protocol errors | 17 | Fixed inline/fullscreen descriptors, nested/flat/template URI precedence and fallback, unsupported display mode, and one peer JSON-RPC error `-32001`. Exact live, warm and first-cold selective items, pinned error/cause text and provider content items must match. One MCP effect, two provider requests and no resource fetch are required. |
| Async questions and notice | 8 | Fixed titles and populated/omitted/null options, whitespace trimming, async delivery, five exact validation errors and accepted continuation. Live plus warm selective items and order are checked. No client interaction is created; no cold-persistence claim is made. |
| Server-request method/params owners | 14 | Six named native command/file/MCP/permission/dynamic/current-time scenarios contain exact method/params assertions and independently prescribed effects/errors. Only selected original physical leaves are bound; opaque IDs and other variants are excluded. |

The backend fixtures prescribe model outputs and MCP responses. The immutable
Codex executable produces the app-server messages, routes reviewers and tools,
validates input, serializes items and persists history. These tests do not
authenticate a real provider, perform inference, or establish unavailable
external/backend/OS success. The full Guardian assessment is checked because a
Guardian failure can also result in denial; denial alone is insufficient proof.

The MCP error oracle pins the actual dependency chain: rmcp 3.5.1 commit
`4048ac40e958fb1a7d614617a2ae8d26666ee2fa` and anyhow 1.0.103. The inspected
anyhow crate matches its locked checksum. The real-native tests confirm the
entire literal message and two-item provider payload, rather than accepting a
prefix or normalizing the error. Existing owned-process cleanup is preserved.

## Preserved failures and repairs

The first complete eight-file run reports **40 tests / 3 failures**. All three
new async cases requested selective history using the existing fixture's
explicit `legacy` history mode. A separate real-native diagnostic returns
`-32601`, `thread/items/read is not supported yet`. The new cases now explicitly
select `paginated`; every existing case keeps its legacy default. All live and
history assertions remain. First-failure report:
`/tmp/samgita-native-interactions-v37-first-failure-20261025.json`, SHA256
`f7c2c3bf584c5f7675b01c40c111510dd6cdd7fd4ddbc277d2a653529717db43`.

The first repair passes both full native runs **40/0**, then strict Credo fails
on one numeric literal and one test-helper complexity check. The final repair
uses `32_001` and extracts the repeated item-index predicate without changing
selection or ordering assertions. No rule, assertion, timeout or retry is
weakened. Both failed attempts and source snapshots remain under
`/tmp/samgita-native-interactions-v37{,-r1}-20261025/`.

## Terminal scoped checks and binding

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-native-interactions-v37-r2-20261025.py
python3 -B /tmp/samgita-bind-native-interactions-v37-20261025.py
python3 -B scripts/codex/inventory.py --check
```

Both complete eight-file runs pass **40/0**, seeds 501432/987654, zero exclusions.
Namespace/sandbox prerequisites, warning-free compile, format, strict Credo
(442 files), all 38 tooling regressions and inventory consistency pass. The
**1,495-file source guard and binary guard match**. Exact files, commands,
exits and log hashes remain under
`/tmp/samgita-native-interactions-v37-r2-20261025/`.

Binding checks original rows, canonical nodes/hashes, exact six named server
test bodies, source/oracle excerpts and dependency preimages. The two reviewed
dependency changes add async scenarios and their explicitly selected history
mode; old native dynamic-tool scenarios retain their defaults. The full manifest
equals the generated expected JSON, with exactly 46 selected rows changed and
all requirements/other sections unchanged. Terminal report:
`/tmp/samgita-v37-native-interactions-owner-terminal-20261025.json`, SHA256
`141a816fe50dbd18eb7b390ccb6bfe36ea5c817ee11acd163657b0abbec842a3`.

Contracts become **4,383 implemented / 2,238 missing**, zero verified.
Requirements stay **462 implemented / 12 missing / 11 blocked**, zero verified.
This is scoped implementation evidence. Complete default-driver/profile,
platform/recovery/consumer and final-pushed hosted checks remain required. A11,
upstream-unreachable outputs, external/OS success, retained aggregate/cursor/
listener failures and the full goal remain incomplete. No release, publication,
production migration or deployment.
