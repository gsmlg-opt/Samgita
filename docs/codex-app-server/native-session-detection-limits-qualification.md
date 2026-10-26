# Native session discovery age and count limits

The success-only import profile now distinguishes actual session discovery
limits using owned foreign-format files. It uses real pinned Codex
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`,
Linux x86_64 musl/stdio. The immutable binary SHA256 is
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`;
source archive SHA256 is
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.

## Independent input and effect oracles

Three valid inert Claude-format JSONLs contain identical recent explicit
conversation timestamps and bytes. Only their foreign-input file mtimes differ:
captured current time minus one hour, two hours and three days. Each mtime and
source byte snapshot is independently asserted before detection and through
both native shutdowns. No native rollout, SQLite or ledger data is modified.

All four native detection queries happen before import:

| Maximum age in days | Maximum sessions | Exact native source order |
| --- | --- | --- |
| 1 | 4 | Newest, middle |
| 7 | 4 | Newest, middle, oldest |
| 7 | 1 | Newest |
| 7 | 2 | Newest, middle |

The first pair discriminates modification age while holding count constant;
the latter pair discriminates count while holding age constant. Assertions
compare complete session maps and exact source identities/order, home-level
description/cwd, empty connectors and companion detail arrays. Equal recent
message timestamps prevent conversation age from accidentally satisfying the
modification-age oracle. No sleeps or clock/deadline changes are needed.

The exact single-source native selection then enters the retained complete
[import journey](native-session-import-success-qualification.md): ordered
receipt/progress/completion, durable success/history, one real Legacy thread,
full raw/public messages and source conversation chronology, explicit repeat
after known completion, and distinct cold native reads. Only the newest source
is imported. Two operation histories survive with unchanged native bytes;
model requests stay zero. The original Claude and two Cursor cases retain
their assertions, bounds and owned process cleanup.

## Exact ownership and source

Only these standalone physical nodes become scoped **implemented**:

| Owner | `v2/ExternalAgentConfigDetectParams.json` pointer | Node SHA256 |
| --- | --- | --- |
| 3954 | `/properties/maxSessionAgeDays` | `52d3d7461c58b37eaeacde4089db52849d3596c16901c452a5264c73f84260c3` |
| 3955 | `/properties/maxSessions` | `96a9657f088eaa85a578648c497c00ff60306af42262c02a546418b23aac9627` |

The actual `ClientRequest.externalAgentConfig/detect` parameter graph resolves
both fields and independently matches those nodes. No twin, hash or reference
propagation occurs. Twenty-nine whole files match their exact immutable archive
members, including processor parameter conversion, Claude source discovery,
the mtime filter and bounded newest-source heap, record parsing, import ledger,
importer and durable/native public history.

This covers the listed positive nonnull/nonzero values. Zero, null, omitted
defaults, tied mtimes, parse-drop variants, other sources and complete import
family qualification remain separate work. Synthetic Claude-format input does
not establish a real Claude producer or provider integration.

## Final functional checks

Baseline: `7e03742c4615d6b8f0183e4fbcf5841b5386cab0`.
Elixir 1.18.5/OTP 27.3.4.17, `MIX_ENV=test`, `ERL_FLAGS='+S 2:2'`, exact
`CODEX_BINARY` and independent driver paths. The owning module initially passes
**4/0**. Final affected four-file checks pass **8/0 twice**, seeds `501432` and
`987654`, in 30.060s and 30.286s. Scoped format, warnings-as-errors compile,
strict Credo on 508 sources, outside actual-binary consumer **1/0** and retained
relay/inline Exec AST checks pass. The 310-source guard stays stable; all 309
unrelated sources and production protocol/driver/process cleanup are unchanged.
No functional failure, skipped assertion or deadline increase occurs.

Commands/logs: `/tmp/samgita-v343-run.py` and
`/tmp/samgita-v343-functional-checks/final/`. Source/final bindings:
`/tmp/samgita-v343-source.py` and `/tmp/samgita-v343-bind.py`.

| Artifact | SHA256 |
| --- | --- |
| Functional results | `3259e1e6aa103bb685f1c29aaab08b0a92c1c5dcfe47ae355a7860d7d30f4007` |
| Source guard | `74e429044c975f9a60654fd51375af951ba0963c64654301d669aa538d94b52b` |
| Whole source/schema comparisons | `d4c2d6ce3c1892668ee89eef971c602832d8b6dea120a2546497e82dcb91a54a` |

Inventory consistency passes; strict completeness exits **1**. Contracts become
**5,002 implemented / 1,553 missing / 66 blocked**; requirements remain
**462 implemented / 12 missing / 11 blocked**, zero verified. Ordinary setup is
fixed YOLO. Prohibited security/credential/authentication/authorization/
permission/approval tests and audits, mixed/broad suites and hosted workflows
remain unrun. A11, unreachable legacy and unavailable external/platform/OS
success, full compatibility and release remain incomplete. No package
publication, deployment or production migration occurs.
