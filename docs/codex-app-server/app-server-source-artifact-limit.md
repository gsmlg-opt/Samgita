# appServer source producer is unavailable in the selected artifact

Current update: the [separately pinned official standalone app-server](standalone-source-selector-qualification.md)
now supplies genuine source production and cold search evidence for its declared
Linux musl stdio profile. The combined executable limitation below remains valid.
This historical investigation did not establish absence from the entire release.
No owner676 or notification credit is transferred from the new six-owner unit.

Positive producer/discovery acceptance for `ThreadSourceKind.appServer`
(canonical physical owner676) remains incomplete for the selected combined
`codex` executable. Existing explicit input/exclusion evidence is retained.
This source-only finding supplies no successful native MCP execution or
full-compatibility claim.

Reference: `rust-v0.163.0`, source commit
`83086188ae0614bd882818ff1aa23f3194962012`. Eighteen complete source/manifest
files match their unique archive members. Archive SHA256:
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
The previously selected binary SHA256 remains
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`;
no executable is run or substituted for this investigation.

The exact [combined CLI subcommand enum](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/cli/src/main.rs#L145)
contains `mcp` for external-server management and `app-server`, with no
`mcp-server` command/handler. The archive has no `codex-rs/mcp-server/` crate.
`codex-mcp` is a library for external MCP connections/tools. An old comment or
another release's command does not establish an executable path in this pin.

The [combined app-server dispatch](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/cli/src/main.rs#L1288)
passes literal `SessionSource::VSCode`; its `AppServerCommand` has no
session-source argument. `thread/start` inherits that manager source. Its
similarly named `sessionStartSource` chooses only `startup`/`clear` history;
`threadSource` is independent attribution. Neither selects Core Mcp.

A [separate upstream main](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/main.rs#L46)
for Cargo binary `codex-app-server` exposes `--session-source`. Its parser maps
`mcp`/`app-server` aliases to Core Mcp, which public conversion names `appServer`.
That target is a distinct artifact. The flag is not available by renaming the
selected combined binary or passing arbitrary initialization fields.

Native app-server stdio is JSONL app-server protocol; the pinned ClientRequest
has no MCP `tools/list`/`tools/call` methods. There is no established MCP
initialization, inference-result identity or normal exit lifecycle for the
absent combined entry. The local model fixture can answer a real native
request; it cannot supply a missing native producer. Fabricated SessionMeta,
SQLite rows, source labels or a mock Codex server are not acceptance evidence.

Resolution requires a supported genuine producer in the selected artifact or
an explicitly declared, separately pinned executable/deployment profile with
its own behavior evidence. Neither is delivered here. No universal
unreachability claim is made for other Codex artifacts/releases.

Both actual list/search request graphs resolve to
`ClientRequest.json#/definitions/ThreadSourceKind/enum/3`, literal `appServer`.
Its independent node SHA256 is
`622214a100066aceb1d1ab827c78dee8aaf32f7cd66e8c02400287fe6cb589c3`;
export SHA256 remains
`92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352`.
`/tmp/samgita-v337-source.py` verifies the complete files/archive absence and
exact request graphs. The source report is
`/tmp/samgita-v337-candidate-report.md`, SHA256
`48ecffba0a54414907ff903493970517fafa92a3f9acfac42998f1cdc61aaa5c`.

Documentation binding base: `c13a258e7162a20328e640d3d7b38d95ab3cb1e5`.
All308 current and committed guarded sources equal the last reviewed57-file,
111/0-twice functional matrix; this unit reruns none of it. The source evidence
SHA256 is `fe719bbffe2de871526affbb6a247be18883056538de8706901734b10c187264`;
manifest SHA256 is
`fd5cde07b049ed826ea9866a854958731b7790a943b4b472a912189bd28fac2e`.
`/tmp/samgita-v337-bind.py` verifies only owner676's evidence/limitations change;
all states, requirement records and test references remain unchanged. Inventory
passes; strict completeness still exits1. Totals remain462 implemented/12
missing/11 blocked requirements and4,996 implemented/1,559 missing/66 blocked
contracts, zero verified.

No runtime, security/permission test, audit, broad suite, hosted workflow,
publication or deployment is run. No manifest state is promoted. A11, legacy
production evidence, external/OS acceptance and the full goal remain incomplete.
