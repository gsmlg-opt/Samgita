# Retained native request correlation and notification envelopes

Status: 112 selected physical owners implemented; **full compatibility incomplete**.
This indexes unchanged direct native assertions and adds no executable behavior
or new runtime claim. Target: Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

| Exact operations | Physical owners | Independent native oracle |
| --- | ---: | --- |
| environment/add, info, status | 15 | Existing helper supplies a unique string JSON-RPC ID and pins its returned ID; owned executor registration, selected CWD and reconnect status are asserted. This ID differs from the separately checked WebSocket X-Request-ID. |
| Seven remoteControl enable/disable/status/pairing/client operations | 35 | Explicit response-ID pins plus held enrollment, actual owned WebSocket, fixed pairing/claim maps and client revoke effects. Backend/account peers use synthetic credentials. |
| fs/getMetadata and fs/readDirectory | 2 | Only the missing id properties: explicit correlated envelopes retain independently set modification times and known Unicode directory entries/rename effects. Previously bound roots are excluded. |
| Twenty notification methods | 60 | Exact method/literal/params-root fields bind nonempty native output, prescribed identity/content/effects, lifecycle ordering and pinned production emitters. No whole branches or payload descendants inherit evidence. |

The notification cases cover thread start/read-state/attachment/queue/project
changes, project changes, token usage, thread environment connect/disconnect,
goal updates, reasoning/plan output, checklist updates, file patch/diff,
account quota and app catalog notices. Their
fourteen evidence groups retain exact assertions/helpers and native producer
source ranges. Provider/MCP/backend fixtures supply deterministic input; they
do not construct app-server frames. Some cases relay native stdio over an owned
isolated UDS connection. This does not establish an external native endpoint or
real account/backend success.

Only observed successful string-ID envelopes qualify the request owners. Numeric
IDs, error/timeout/uncertain outcomes, missing IDs and unobserved nullable/parameter
children remain separate. The notification params reference does not qualify its
children, other enum branches, aliases or declaration-only emitters. The deferred
60 TurnFixture correlation owners and all previously bound roots are excluded.

## Retained runtime binding and parent validation

Frozen v27 source `0aba494a89eb02bd651ea1792d755c6cee6c452c` passes the complete
default driver **718/0 twice** and all 49 isolated profiles **292/0 twice**, seeds
501432/987654, zero exclusions. Exact test membership follows saved explicit
profile commands or unchanged default test discovery, not fabricated per-test
traces from aggregate dots. This is retained v27 evidence, not a new current-source
full suite result. The combined-source/final-pushed matrix remains required.

The parent verifies every original row, canonical schema node and inventory
hash; all 869 client and 882 notification dependency preimages match current
source and the frozen snapshot. It independently checks **153 source excerpts**,
all four exact command/log/summary bindings and the immutable executable hash.
Only these 112 rows change, with no requirement or verified-state promotions.

Source audits:

- `/tmp/samgita-client-envelope-explicit-correlation-v31-20261025.json`, SHA256
  `76cee7357e00194ca883080ee93b27e25c0dcb34e945048d6bc80ce0719ecc89`.
- `/tmp/samgita-server-notification-retained-envelopes-v31-complete-20261025.json`,
  SHA256 `c42e69433597ca6006052be25f0628b937462d43066058705562e1adc6fcd103`.
- `/tmp/samgita-v31-retained112-envelope-terminal-20261025.json`, SHA256
  `5b4e7a7e1bf0271a2a4e8651325aca83e640e8724428890bb68b0ecb74e8b3cf`;
  the adjacent bound index records every selected method, physical pointer,
  original row/node, exact test/hash, oracle and retained runtime source.

```sh
python3 -B /tmp/samgita-bind-v31-retained112-envelopes-20261025.py
python3 -B scripts/codex/inventory.py --check
python3 -B -m unittest discover -s scripts/codex -p 'test_*.py'
git diff --check
```

Inventory consistency and 37 tooling regressions pass. The ledger becomes
**4,125 implemented / 2,496 missing contracts**, zero verified. Requirements
remain **462 implemented / 12 missing / 11 blocked**, zero verified. Continue the
explicit TurnFixture correlation unit and remaining actual-native behavior,
then complete final-source local/hosted qualification. Retained aggregate/cursor/
listener failures, A11, unreachable emitters and external/backend/OS success
remain incomplete. No tag, publication or deployment occurs.
