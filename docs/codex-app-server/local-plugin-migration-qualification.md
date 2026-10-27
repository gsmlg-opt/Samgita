# Native selective local-plugin migration

The ordinary `native_local_plugin_migration_test.exs` uses two owned stock Codex
processes and isolated home/config/workspace roots. A directory marketplace
contains two metadata/skill-only plugins, both enabled in the external source.
Native detection returns the exact marketplace and sorted plugin names. The
import request preserves that actual item except for selecting A alone in
`details.plugins[].pluginNames`. Original framed requests/responses, native
progress/completion and persisted import history are compared with independent
literal expectations. No synthetic peer produces the migration results.

Only A becomes enabled in the Codex configuration and gets version `2.4.1`
manifest/skill cache bytes; B has no configuration/cache entry and remains
detectable. A distinct cold native process reads the same history/config/cache
and again detects B alone. Source files and workspace remain unchanged. Runtime
plugins stay disabled; no plugin, hook, MCP, model, thread or turn is executed.

Target: `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`,
Linux executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Thirteen complete source files match the official source archive. Producers:

| Pinned source under `codex-rs/` | Behavior |
| --- | --- |
| `external-agent-migration/src/source_cla.rs:175-244` | Skips configured plugin IDs and groups remaining names by marketplace |
| `external-agent-migration/src/plugins.rs:128-238` | Consumes selected names and installs each selected plugin |
| `external-agent-migration/src/service.rs:262-311` | Actual succeeded plugin IDs become import results |
| `core-plugins/src/marketplace_add.rs:134-156` | Directory marketplace branch; no Git/network import |
| `core-plugins/src/manager.rs:2256-2329` | Materializes selected plugin cache and enabled configuration |
| `core-plugins/src/store.rs:112-119,295-342` | Versioned installed-plugin paths and copied source content |
| `external-agent-migration/src/service_tests/plugins/marketplaces.rs:407-479` | Matching upstream local import fixture |

Plugin names select installation in this pin. This differs from the scope-wide
hook/MCP import behavior in the [previous profile](local-config-migration-qualification.md).
Neither profile proves runtime execution of its imported content or native
idempotency after an ambiguous disconnect.

Only four exact `ClientRequest.json` definition owners gain scoped implemented
evidence: `ExternalAgentConfigMigrationItemType/enum/3`,
`MigrationDetails/properties/plugins`,
`PluginsMigration/properties/marketplaceName` and `/properties/pluginNames`.
Their node hashes match both the vendored and generated experimental export.
Other fields/schemas/transports gain no credit. Source/node binding
`/tmp/samgita-v466-binding/source.json`, SHA256
`e0fbf0a923dcd64cc455f78d387e14b0b026b6962a28bed486ca3756051680f4`.

Original capture is bounded at 96 frames/64 KiB per frame/1 MiB aggregate;
Session events at 32/128 KiB, files at 16 KiB and parsed TOML output at 32 KiB.
Exactly 11 native RPCs run across warm/cold processes, with five-second
request/observation deadlines and a 60-second case. Checked fallback cleanup
waits for owner completion, closed Port and known native PID disappearance;
the once-only ownership counter gates scratch removal. Production process
ownership/shutdown code remains unchanged.

The focused command from the driver package passes **1/0** at seed `501432`:

```sh
mix test test/native_local_plugin_migration_test.exs --warnings-as-errors --seed 501432
```

Test SHA256
`182e7e971046afd0a2238c1bbcb4956a9308f95acadfbdb290c985c93bdab253`;
original focused log `/tmp/samgita-v466-owning-501432.log`, SHA256
`ad4911ab3a501c59ec0a680fd68d2e0ac26e87776c80a29f1b4d7084990716e5`.
Independent source review found no concrete functional defect; runtime evidence
is recorded separately. The reviewed ordinary runner now selects 41 driver
files/63 cases. All **14 combined-source steps pass**: **63/0** at both seeds
501432/987654; **3/0** WebSocket overflow/replay cases at each of seeds
455834/501432/987654, with the other 13 mixed-file cases excluded; outside
consumer **1/0** (seed 798259); inventory consistency; and retained
compile/format/Credo/Dialyzer/assets checks. All **1,659** fingerprinted sources
stay byte-identical. Assets build retains the existing Bun version warning
(configured 1.3.13, installed 1.1.42); it exits 0. No unrelated dependency
change, broad suite, database recovery test, audit or hosted workflow runs.

Evidence `/tmp/samgita-ordinary-v466/` contains original per-command logs and
source snapshots. Results SHA256
`db3254a79c20d45438fb164aa378100cb86c4398562b5dc0f43b8f1c8bde8252`;
source guard SHA256
`dcabaca4405e671517f02269e3b77166c53f619244725c2da440882965616ba1`;
command-plan digest
`2a4a7f4d708ede89762474f96ab85b2709a43ef21090e3a01a6a7ee9726226c5`.

Counts: **5,299 implemented / 1,214 missing / 108 blocked** contracts;
**462 implemented / 12 missing / 11 blocked** requirements, zero verified.
Fixed YOLO is owned-launch setup only. Prohibited security/permission checks,
A11, unavailable upstream producers, external/backend/OS profiles and complete
compatibility/release gates remain incomplete. No publication or deployment.
Continue ordinary selected local memory migration only after confirming that
the fixture cannot start background inference; consolidation execution receives
no credit from file ingestion.
