# Native local hook and MCP configuration migration

The ordinary `native_local_config_migration_test.exs` uses two owned stock Codex
processes and isolated home/config/workspace roots. Real detection returns two
named MCP declarations and two ordinary hook event names. The original detected
items are compared with independent literal names/details and sent unchanged to
native import. Exact original requests, native progress/completion, persisted
history and independently prescribed TOML/hooks/copied-script destinations are
required. Source files and the workspace stay unchanged; marker-only imported
commands are never called. No thread, turn, model or hosted service is started.

Repeating the original import is an explicit new operation: native generates a
different import ID and history record, emits two successful empty result groups
and completion, and preserves destination bytes. A distinct cold native process
reads those same histories/files and observes no remaining migration items.
This proves repeat behavior and cold persistence; it does not promise native
deduplication after an ambiguous disconnect. Detail names are advisory: the
importer rediscovers the source scope rather than selecting only supplied names.

Target: `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`,
Linux executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Eleven full source files match the official archive. Relevant producers:

| Pinned source under `codex-rs/` | Behavior |
| --- | --- |
| `external-agent-migration/src/detect/mod.rs:129-191` | Named MCP/hook details |
| `external-agent-migration/src/service.rs:328-378` | Imported names become result records |
| `external-agent-migration/src/service.rs:602-679` | MCP config and hook destination persistence |
| `external-agent-migration/src/config_values.rs:44-96` | Only absent MCP names merge; pretty TOML serialization |
| `external-agent-migration/src/hooks_common.rs:13-35` | Existing nonempty hook destination is a no-op |
| `app-server/src/external_agent_migration/processor.rs:197-258` | New import identity, progress, completion and history |
| `app-server/src/external_agent_migration/protocol.rs:67-101` | Public name/detail projection |
| `app-server/src/request_processors/config_processor.rs:219` | Cache invalidation after import; no MCP execution |

Only six exact `ClientRequest.json` definition owners gain scoped implemented
evidence: `ExternalAgentConfigMigrationItemType/enum/4` and `/enum/6`,
`HookMigration/properties/name`, `McpServerMigration/properties/name`, and
`MigrationDetails/properties/hooks` and `/properties/mcpServers`. Their subtree
hashes match the generated/vendored experimental export. Other schemas, fields
and execution behavior gain no credit. Source/node binding
`/tmp/samgita-v465-binding/source.json`, SHA256
`17fb31a87f7616c4d7679af7cf6c16aaa2feef7312b790d9574a3b4bf81ee4ea`.

Original capture is bounded at 96 frames/64 KiB per frame/1 MiB aggregate;
Session events at 32/128 KiB and files at 16 KiB. There are exactly 12 native RPCs
across the warm/cold processes, with five-second RPC/observation deadlines and
a 60-second case. Checked fallback cleanup waits for owner completion, closed
Port and known native PID disappearance; a once-only ownership counter gates
scratch removal. The existing driver shutdown behavior remains unchanged.

The first focused run at seed `501432` was **1/1**: the test incorrectly decoded
pretty TOML array lines as JSON. Native detection/import/progress had already
passed their preceding assertions; later persistence/repeat/cold checks had not.
Pinned `write_toml_file` explicitly calls `toml::to_string_pretty`. The repair
uses Python 3.11+ stdlib `tomllib` on the complete bounded real file and exact
equality for the entire MCP server map, including both command/args values and
rejection of extra entries. It changes no production code, effect assertion or
deadline. The repaired focused run passes **1/0**. Independent source re-review
found no remaining concrete defect and acknowledges the initial parser miss.

| Artifact | SHA256 |
| --- | --- |
| Final test | `dd4835fb7def07e053757a9885a2254d3cc5cdf525245a58fd220ff86b468fb2` |
| Initial failure `/tmp/samgita-v465-owning-501432.log` | `c2d8c1e1df05466df054458e27cd1286211fc470a529f664286544b60ac6d5e5` |
| Repaired `/tmp/samgita-v465-owning-repair1-501432.log` | `36d5a289b3ddb6292c1fdd45c2d197ef97990439ef14993814da29c13f6887ec` |

The focused command, from the driver package, is:

```sh
mix test test/native_local_config_migration_test.exs --warnings-as-errors --seed 501432
```

The [repository ordinary runner](mcp-status-detail-qualification.md) now names
40 files/62 cases and requires renewed source review before updating its
fingerprint. All **14 combined-source steps pass**: **62/0** at each seed
501432/987654, **3/0** WebSocket overflow/replay cases at each seed
455834/501432/987654 (13 other cases excluded), outside consumer **1/0** (seed
814870), and all retained compile/format/Credo/Dialyzer/assets and inventory
checks. All **1,658** fingerprinted sources remain byte-identical. No mixed/broad
suite, database admission/recovery test, audit or hosted workflow runs.

Evidence `/tmp/samgita-ordinary-v465/` contains original per-command logs and
source snapshots. Results SHA256
`e51fcf2a9b679fb7359997d199052c24234a70d8ccd99fbc307f1089333c5b6a`;
source guard SHA256
`982807d2f7d47507aef10faac2fbdb6a22a9f1e2232dbd60364659a49cf428dc`;
command-plan digest
`cae8b91efbc1218df815477000bfef636c82887a14043c0aa71156b6f34bf712`.

Counts: **5,295 implemented / 1,218 missing / 108 blocked** contracts;
**462 implemented / 12 missing / 11 blocked** requirements, zero verified.
YOLO remains fixed owned-launch setup only. Prohibited security/permission
checks, A11, unavailable upstream producers, external/backend/OS profiles and
full-compatibility/release gates stay incomplete. No publication or deployment.
Continue ordinary selective migration of a directory-backed local plugin; hook
and MCP detail lists do not establish plugin-name selection semantics.
