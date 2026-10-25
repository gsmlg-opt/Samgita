# Retained native command, search and import request owners

Status: **52 selected physical contracts implemented; full compatibility incomplete**.
This is an evidence index over unchanged native assertions, not new executable
behavior or a fresh whole-current-source matrix. The passing frozen source is
`2ed69924c8e82adcbfb41740f28789832c86bf02` (v24). All 23 package commands pass:
default driver **715/0 twice**, all 49 isolated profiles **283/0 twice**, at
seeds 501432 and 987654, with no exclusions in either native suite.

The immutable native target is `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The command profile checks binary presence; pin assurance comes from the
runner's exact CODEX_BINARY, passing pin-checking preflight, retained terminal
hash and independently rehashed executable. The background profile also checks
the hash. No per-request executable attestation or fabricated wire transcript
is claimed by these aggregate logs.

## Physical selection and oracles

Each method contributes exactly four previously missing `ClientRequest.json`
owners: its oneOf request object, method field, method enum leaf and params
field. Referenced parameter types, siblings and responses inherit no evidence.
The thirteen request indices are 41–43, 57, 58, 151–154 and 160–163.
None has a nullable params union branch; readHistories directly exercises its
null params node. No absent/null alternative is inferred from another method.

| Native method | Independent observable effect in the named retained case |
| --- | --- |
| command/exec | Owned child observes exact cwd/env override/deletion, stderr, exit 7, marker and confirmed OS disappearance |
| command/exec/write | NUL/0xff writes and EOF produce prescribed stream bytes; original exec stays pending until EOF |
| command/exec/terminate | Explicit ACK precedes separate exec outcome and observed child disappearance |
| command/exec/resize | Owned PTY reads 24×80 then 45×132 through TIOCGWINSZ, with prescribed echo and cleanup |
| thread/backgroundTerminals/clean | Two native sessions exist before ACK; bounded observation then requires empty list and both owned PIDs gone |
| thread/backgroundTerminals/list | Exact command/cwd/item and independently captured native session IDs, ordering, cursors and state changes |
| thread/backgroundTerminals/terminate | Wrong-thread false preserves state; targeted termination removes only its session and OS child |
| thread/search | Independently prescribed escaped Unicode snippets, filters, pagination, archive and cold read, exactly three explicit provider calls |
| thread/searchOccurrences | Exact UTF16 ranges and original user item/turn identity survive pages and cold continuation, exactly one provider call |
| externalAgentConfig/detect | Owned source files produce prescribed types/cwds under distinct home/repository/source selectors; no writes or inference |
| externalAgentConfig/import | Correlated progress/completion and actual owned AGENTS.md import, protected target/source preservation, no-op repeat and restart history |
| externalAgentConfig/import/recordHistory | Prescribed success/failure/provider/title records persist with distinct UUIDs and ordered cold retrieval, without importing files |
| externalAgentConfig/import/readHistories | Explicit null params reads the independent records exactly; no source/target files or inference |

The four owning files are `native_command_lifecycle_profile.exs`,
`native_background_terminal_profile.exs`, `thread_search_timeline_test.exs` and
`native_import_lifecycle_test.exs`. Commands/background use native WebSocket
frames over a private Unix socket; Stdio owns those servers but is not their
request transport. Search/import use owned stdio sessions. All resources are
isolated and synthetic; no arbitrary service or process is controlled.

## Review, binding and limits

Parent preflight rechecks 59 unique audited source paths, 104 excerpt occurrences,
all 52 complete original owner rows and canonical nodes, and 42 additional
independent-review dependency preimages. The prior 50+140+10 disjoint promotions
explain the historical manifest hash differences. Every selected executable
dependency/test hash still matches frozen v24. Ignored pinned Rust files are
source evidence outside that matrix's 1,495-file guard; the executable pin is
separately verified. Aggregate zero-failure/no-exclusion logs plus explicit file
inclusion bind named cases; disposed markers/transcripts are not recreated.

Retained local artifacts:

- `/tmp/samgita-command-background-request-owner-audit-20261025.json`, SHA256
  `d9f1686987af5b9617406b1ca305e6ef30d47f2de97a2af0da9557c2f8771c20`.
- `/tmp/samgita-command-background-review-v24-20261025.json`, SHA256
  `da941373d1f40c3cc618118fe78a2c3a45cc7be838287c6f1303766353f66c30`.
- `/tmp/samgita-retained-config-file-request-owners-v26-20261025.json`, SHA256
  `7fbf2b659c9db757385398e4fb3305feeaed5660e3484a1262e5c4e382570012`.
- `/tmp/samgita-v26-retained52-owner-terminal-20261025.json`, SHA256
  `fcb1791c698b8f39e9700bba18aed3ca659580d9691cb83e4ba8e62b93f84f83`.
- `/tmp/samgita-v26-retained52-owner-bound-20261025-index.json` maps each physical
  pointer to the exact named test, source hash, transport and scope.

The full expected manifest matches exactly, changing only those 52 rows.
Inventory consistency and all 37 tooling regressions pass.
Contracts become **3,843 implemented / 2,778 missing**, requirements remain
**462 implemented / 12 missing / 11 blocked**, zero verified in both sets.
This indexing adds no code, fixture, timeout, cleanup or authority change.
No equal-hash aliases, whole parameter surfaces, other OS/backend success,
A11 or full-compatibility gate is closed. Final combined-source/hosted checks,
source-unreachable emitters and retained aggregate failures remain required.
