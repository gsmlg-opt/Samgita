# Native marketplace partial failure

An explicit `marketplace/upgrade` can succeed as a JSON-RPC request while some
selected marketplaces fail. The driver now has real-native populated-error and
partial-success evidence for this distinction, including repeated requests and
a process restart. Runtime and protocol schemas are unchanged.
Base: `59c91c99a8339b9b277b091212e4e640d6088d78`.

## Producer, effect and persistence

The immutable target remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`
and source archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Six complete source members freshly match the pinned archive.

`config/src/types.rs:1153–1174` makes source type and source independently
optional. A real `bad` Git configuration with source omitted reaches
`core-plugins/src/marketplace_upgrade.rs:163–232`, which produces the literal
`configured Git marketplace is missing source`. The batch path at87–160 sorts
selected names and continues valid upgrades. The actual app-server handler at
`app-server/src/request_processors/marketplace_processor.rs:69–108` preserves
each native error name/message in `MarketplaceUpgradeErrorInfo`.

The focused test creates a real owned local Git repository named `good`, with
independently authored marketplace/marker bytes and an actual recorded commit.
Plugin startup work is disabled. Before the explicit upgrade, diagnostics and
loaded-list observations leave both installation roots absent. The exact first
response must select `["bad","good"]`, report the one activated `good` root and
contain exactly the `bad` name/literal-message error. Real activated files,
revision and full install metadata must match the source/configuration.

An explicit warm repeat returns the same names/error and no upgraded roots. A
distinct pinned cold native process preserves the installed snapshot before
any upgrade; its explicit repeat has the same no-op/error result. Complete
bounded installed/source trees, including `.git`, and config/catalog/support
inputs remain exact through final close. The recorded provider journal stays
empty; there are no requested turns or plugin installations. This is a local
Git effect through the real app-server, not a scripted app-server response.

All ten selected outgoing requests retain exact caller maps/bytes and unique
correlation IDs: three upgrades, two diagnostics and five loaded-list reads.
Capture remains bounded16 frames/4KiB; source/installed snapshots128 paths/4MiB
each, individual files1MiB. Requests/initialize stay5s and the case60s. Existing
owned native fallback cleanup and explicit PID disappearance remain enforced;
the model peer uses unchanged TurnFixture cleanup. No new model-owner monitor
or Git subprocess deadline beyond the existing case guardian is claimed.

## Checks and remaining gates

Initial actual-native **1/0**, final focused **1/0 at501432 and987654**, driver
compile/format, strict Credo543 and inventory consistency pass. All374 guarded
sources remain stable; all373 prior sources are exact, as are770 official
exports and15 input descriptors. The previous87-schema/141-ordinary-driver
twice, outside consumer and root/static/local assembly checks are retained by
source equivalence and were not rerun for this test-only addition. The V371
rank-cursor profile also remains unchanged.

Commands/logs/source guard: `/tmp/samgita-v372-run.py` and
`/tmp/samgita-v372-functional-checks/final/`. Source investigation and parent
review: `/tmp/samgita-v372-ordinary-gap.md`,
`/tmp/samgita-v372-final-review.md`. The final binding records their hashes and
the exact two physical owners4343/4344: `MarketplaceUpgradeErrorInfo` properties
`marketplaceName` and `message`. Only those owners become scoped implemented.

Contracts: **5,042 implemented /1,513 missing /66 blocked**. Requirements remain
**462 implemented /12 missing /11 blocked**, zero verified. The strict full
compatibility gate still fails. This profile does not qualify arbitrary error
messages, staging/activation rollback, installed-plugin refresh, concurrent
changes, network sources, other backends/transports/OS or complete marketplace
compatibility. Prohibited tests/audits, mixed suites and hosted workflows remain
unrun; A11 and legacy/external/platform gates remain open. No publication, tag or
deployment follows.

Rollback removes the focused test and its exact supplemental evidence only.
Preserve prior runtime, source, tests and historical failure records. Continue
remaining reachable ordinary behavior groups.
