# Collaboration mode input aliases

Default validation now accepts pinned native `ModeKind::Default` input aliases
`code`, `pair_programming`, `execute` and `custom` on `turn/start` and
`thread/settings/update`. Original caller values remain intact; Codex alone
canonicalizes, applies and persists `default`. Base:
`c29c0966c32da09ebb23e1b30b7ff6e8ee3db8fd`.

## Source and reproduction

The immutable target remains Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Archive SHA256:
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.

`protocol/src/config_types.rs:671–685` declares the four serde aliases on
`Default`. Actual typed request decoding reaches this enum through
`CollaborationMode` in the two request parameter types. Traversing request
parameter reference graphs, rather than unrelated definitions, confirms exactly
those two methods. The official enum export includes only `plan` and `default`.
Twelve complete inspected source files match their pinned archive members.

Before the repair, the dedicated protocol module reports **4/3 failures**. The
full owning native module reports **7/4 failures**: canonical Default and both
existing Plan cases pass; each alias fails local default validation at the idle
settings update. The real native process has already initialized and applied a
Plan snapshot, but the rejected alias has not reached its request decoder.
After the repair, the full modules report **4/0** and **7/0**. No location filter,
excluded test or validation bypass is used.

One initial implementation attempt fails compilation: a map access on the right
of a guard's `in` is not a compile-time list. Evaluating the descriptor's method
list in its own module attribute resolves that error without changing the
accepted methods. The failed compile log and original red logs remain recorded
at `/tmp/samgita-v352-{protocol,native}-{before,after}.log`; the corrected
dedicated protocol result is `/tmp/samgita-v352-protocol-final.log`.

## Implementation and actual-native oracle

The third labeled input descriptor derives only the four source-declared aliases
from complete pinned `config_types.rs`. Generation checks its digest, alias
target, three official schema hashes and exact request graph. Inventory
generation copies the complete source before derivation; offline consistency and
compile-time resource checks include the new descriptor. All **770 official JSON
exports**, previous pinned artifacts and the other two input descriptors retain
their hashes. Vendored Rust tests are not compiled or executed.

`Schema.Input` augments only the ModeKind input enum for the two methods.
Required/nullable settings, invalid-value rejection and experimental negotiation
remain intact. It does not rewrite outgoing values, install driver presets or
broaden output enums. Wire round trips separately preserve original alias maps.

Five new native cases use canonical Default and each alias with the unchanged
Responses-only `plan_item_events_fixture.py`. This fixture emits one literal
assistant message, not app-server settings, items or persisted records. The real
binary must:

- Apply Plan, then the alias/Default, then Plan again through
  `thread/settings/update`. Each step waits for its actual
  `thread/settings/updated` snapshot with complete canonical mode/settings,
  model/provider and cwd. An RPC ACK only queues the update. Buffer/deadline
  bounds and zero provider calls are checked while waiting.
- Receive the alias in the explicit subsequent `turn/start`, persist a genuine
  canonical Default turn context and produce the exact ordinary `agentMessage`
  containing `<proposed_plan>`, its Unicode body and `</proposed_plan>` literally.
  Its ID and final-answer phase are checked positively. Existing Plan controls
  parse the same producer text into Plan items.
- Complete the correct turn, preserve the exact user marker and owned developer
  instruction marker in actual provider input, and make exactly one inference.
  No Plan items/deltas may substitute for the ordinary assistant result.
- Preserve live item/timestamp correlation through warm full/selective history,
  duplicate/absent selections and the first cold selective content read on a
  different verified native PID. Retained rollout/config/model-catalog/provider
  script/request bytes stay exact, no inference occurs after replacement, and
  existing owner-scoped cleanup plus explicit native-process exit checks pass.

Native coverage uses explicit developer instructions and nil reasoning effort.
It does not establish built-in alias instruction defaults, every optional output
field, independent outgoing-byte capture, cold resumed inference or complete
collaboration/delegation behavior. The outside consumer validates all four aliases
locally; its actual-native journey remains initialization/list. Real alias
execution evidence belongs to the dedicated native cases.

## Final permitted checks

All eleven final commands pass at seeds `501432` and `987654`:

| Check | Final result |
| --- | --- |
| Six reviewed protocol modules | **25/0 twice**, no exclusions |
| Twelve reviewed ordinary driver modules | **61/0 twice**, no exclusions; 74.806/75.323s |
| Driver composition | 32 actual-binary cases and 29 scripted Session fault cases per seed |
| Outside-umbrella consumer | **1/0**, local supplement checks and actual native initialization/list |
| Package compile/scoped format | Pass with warnings as errors |
| Root strict Credo | Pass on **514 sources** |
| Python AST/inventory consistency | Seven files parse; inventory passes |
| Before/after executable-source guard | **325** stable files; **316** other previous sources unchanged |

Exact environments and command arrays: `/tmp/samgita-v352-run.py`; artifacts:
`/tmp/samgita-v352-functional-checks/`. Source/reproduction binding:
`/tmp/samgita-v352-source.py`; manifest binding: `-bind.py --verify`.
The source-only review report is `/tmp/samgita-v352-input-alias-review.md`, SHA256
`1b19d3fa5195e9debf0192427b6c859c0dca7a970141a899c52ffe30d11c95ac`.
The separate strict completeness command exits **1**, not a passing result.

| Artifact | SHA256 |
| --- | --- |
| Source and reproduction evidence | `b2251db50255a4b50e1a89264efff4c209f17c534390aa170440181333b7affb` |
| Final `final/results.json` | `cd4175fcdd256210fc0dfbffda5cfcec7d94c5751f95c50ba56e1c76fba4d02d` |
| Final `final/source.json` | `985819bc31743a146d2365c833cec7705960b022db0233e843b7779eb36d69af` |

## Migration, rollback and remaining gates

There is no database migration or history rewrite. Session, cleanup, providers,
previous input tests and uncertain-operation handling remain unchanged. Rollback
restores local rejection of the aliases; preserve existing histories/journals
and never redispatch possibly executed operations during rollback.

Six requirement records receive supplemental evidence only. No state or physical
schema owner is promoted: contracts remain **5,018 implemented /1,537 missing /66
blocked**, requirements **462 implemented /12 missing /11 blocked**, **zero
verified**. Omitted aliases do not create invented official physical enum owners.
Broad defaults/negotiation remain missing. Next inspect the separately deferred
source-supported `MultiAgentMode` input `none`, whose deprecated request fields
are documented no-ops; do not infer active delegation behavior from acceptance.

Ordinary owned launches use fixed YOLO settings. Security/credential/authentication/
authorization/permission/approval tests, audits, mixed broad suites and hosted
workflows remain unrun and their gates incomplete. A11, producerless legacy
paths, external/OS/platform profiles, final aggregate qualification and full
compatibility remain incomplete. No tag, publication or deployment occurs.
