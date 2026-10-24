# Native missing, null and empty-value differentials

Three additional cases extend `native_default_gates_profile.exs` using its
recording UDS transport, explicitly owned real Codex process and private network
namespace. Target: `rust-v0.163.0`, immutable source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The recording transport retains exact sent JSON; it does not normalize values.
The existing 90-second profile and bounded await/event deadlines remain.

## Differentials and effects

Cold `thread/resume.path` is tested with omitted, null and empty-string input,
each with absent and false experimental negotiation. All six resumes select
the original ID/name/path and legacy empty history in a fresh owned native
process. Nonempty actual rollout paths are rejected locally without send and
natively with the exact experimental error. Rejections do not load a thread or
append history. The journal preserves missing/null/empty input distinctly.

The draft's unchanged-rollout expectation failed at seed `501432`: native
appended `thread_settings_applied`. The
[cold-resume branch](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/session/mod.rs#L1671-L1727)
unconditionally checkpoints effective settings on every cold resume, even when
no turn follows. SessionConfigured can precede this write. The final test waits
for a complete newline-delimited row, stops/reaps the exact owned writer, then
checks durable bytes. Original metadata and every prior byte remain prefixes;
after N resumes the suffix has exactly N settings records with independently
prescribed complete payloads and valid UTC timestamps. No arbitrary append,
rewritten timestamp, extra model/tool/turn record or missing history is accepted.
The original failure remains in
`/tmp/samgita-native-semantic-gaps-v2-20261024/native-501432.log`.

For `thread/start.environments`, omitted and null inputs select exactly the
local environment with the owned cwd and sole runtime workspace root. Enabled
`[]` selects no environments on start and loaded read; disabled `[]` fails both
local and native experimental gates. No turn or model request occurs. The
[optional vector contract](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/thread.rs#L136-L144)
keeps absence/default selection distinct from an explicit empty list.

For `thread/list.sectionId`, omission returns two prescribed owned threads,
explicit null returns only the unsectioned one, and the concrete section ID
returns only its member. Each thread first receives one fixed assistant-only
turn so empty-preview filtering cannot mask selection. Exact IDs, sections,
nonempty previews and final cursor are checked. Queries repeat after actual
native restart without resume/loading; original rollouts and exactly two
provider requests remain unchanged. The
[double-option contract](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/thread.rs#L1438-L1447)
and state filtering preserve null versus omission. This is separate from the
known ordinary reverse-timestamp cursor defect.

## Qualification and limits

The complete profile passes **8/0** twice in its first source-corrected run.
After strengthening preservation of all prior checkpoint bytes, the complete
owning block passes **12/0** at both seeds `501432` and `987654`, including
[four file-effect cases](file-change-effects-qualification.md). Compile/tests
with warnings as errors, formatting, strict Credo and immutable before/after
source hashes pass. Artifacts and exact commands are in
`/tmp/samgita-native-effects-semantics-v1-20261024/`. The earlier formatting
and nesting failures are retained in the v1/v2 semantic and file-effect logs;
they were repaired without suppressions or deadline changes.

Only the precise `ThreadResumeParams.path` contract gains a new scoped
implemented owner; environments and sectionId receive supplemental semantic
evidence. Broad missing/null/default and experimental lifecycle rules remain
missing, with no fully verified promotion or external/OS compatibility claim.
The final source still requires complete local and hosted qualification.

## Fork path normalization and optional resume history

Two further native cases extend the same profile to ten cases. A parent is
created and named with experimental negotiation enabled, then the owned native
process is stopped and reaped. New absent/false connections confirm the parent
is cold. Omitted, null and empty fork paths create distinct children with the
same prescribed name, ancestry, legacy history and effective settings. Exact
outbound key presence, child metadata/checkpoint, unchanged parent response and
every parent byte are asserted. A nonempty actual path is rejected locally
without send and natively with the exact experimental error; no child, provider
request, turn or parent mutation follows that rejection.

Cold resume tests omitted/null history under absent, false and true negotiation.
They retain the same ID/name/path and exact original rollout prefix, appending
only the independently expected settings checkpoint. Empty history is an active
experimental value: absent/false rejects at both local and native gates; true
reaches exact native `history must not be empty` (-32600). Those failures leave
loaded IDs, rollout files and provider requests unchanged. Empty rejection does
not establish successful nonempty history import; that contract stayed missing
at this checkpoint. The subsequent import case is qualified below.

Pinned source anchors are `v2/thread.rs:354-374,548-584`,
`serde_helpers.rs:23-40`, `message_processor.rs:965-983`, and
`request_processors/thread_processor.rs:3927-3951,4507-4521,4789-4802`, all beneath
the immutable `codex-rs/app-server-protocol/src/protocol` or `app-server/src`
tree as appropriate. Cold resume clears configured reasoning effort when the
durable metadata lacks it (`thread_processor.rs:4166-4197`); fork uses the new
conversation configuration (`:5396-5410`, `core/src/session/mod.rs:855-897`).
`ThreadSettingsSnapshot.reasoning_effort` skips None on serialization
(`protocol/src/protocol.rs:2350-2351`), while nested collaboration settings keep
null (`protocol/src/config_types.rs:779-784`). Both values come from the same
session mode (`core/src/session/session.rs:317-337`). Thus resume requires a
missing top-level effort and nested null; fork requires low at both positions.
Complete checkpoint equality remains, with only its separately validated UTC
timestamp removed. No observed settings are stripped to obtain equality.

The combined four-file owning block passes **52/0** at both fixed seeds, with
warnings-as-errors compilation, formatting, strict root Credo and an unchanged
executable-source guard. It also includes the separate
[Session diagnostic boundary](session-confidentiality-qualification.md).
Exact commands/results are retained in
`/tmp/samgita-native-default-confidentiality-v3-20261025/`. Results SHA256 is
`99a560426c434ab9e8ba3498d029ffe18abed485e76bd5663f25e2946c8fa693`;
source-snapshot SHA256 is
`933c57a4fed15b029ca5454c23e70a03dfcc546cc75b53c320879a219aa03ec9`.

Initial v1 **51/4** and v2 **52/2** failures are retained. The default-profile
failures came from explicitly requesting gated history mode during disabled
setup, expecting configured low on cold resume, and omitting the fork's
top-level effort checkpoint. Source-backed oracle repairs preserve the original
gates, no-work assertions, full persistence equality, cleanup and deadlines.
The final conditional expected-key fix followed bounded recovery after two
Sol repair rounds. Original log hashes are
`f16f7fe5af04f99c041e84b755c3d63bfba515fbd9c40a992193754a85f2db20`
(v1) and `4eb585f60d3bc8d31627634f66ec8fa91f9db69af84eb5bfdae0022a92f97144`
(v2). No production, fixture or schema change occurs. No manifest count or broad
lifecycle status changes; full-source local/hosted qualification remains required.

## Successful supplied-history import

One further actual-native case uses the official successful-history reference
`app-server/tests/suite/v2/thread_resume.rs:6163-6249` at the same immutable pin.
It creates and names a populated legacy source S, completes fixed turn910, then
stops/reaps the owned native process. S is cold before import. Its full projected
history, identity/name and every rollout byte must remain unchanged throughout.

The import request supplies S's ID, an explicitly nonexistent owned path and one
exact user Message, `Owned supplied history λ`. With experimental negotiation
disabled, nonempty history rejects locally without a send and natively with the
exact gate error, without work or storage changes. Enabled history takes
precedence over ID/path, creating independent T with a new ID/path, idle state,
paginated storage, no inherited name/project/ancestry and independently expected
effective settings. Exactly three flushed records are required: metadata ordinal0,
the complete imported ResponseItem ordinal1 with a nonempty native-generated ID,
and the complete settings checkpoint ordinal2. Only a separately validated UTC
timestamp is omitted from equality. Import itself makes no provider request.

Supplying replacement history to loaded T rejects with the exact native error,
preserving its files, loaded IDs and no-work controls. Only an explicit turn911
executes. Its actual local provider input contains the imported text exactly
once, contains the explicit turn once and excludes S's turn910 marker. Native
request metadata requires `history_initialization: supplied_history`. A second
owned cold restart preserves the complete imported prefix and exact native item
ID, T's explicit completed turn and all of S. Exactly two provider requests exist,
with no automatic resume/turn. The cold paginated UI history has one explicit
turn; the raw ResponseItem is proved durably outside that UI projection.

The first combined run reached **54 tests / 1 failure**: the expected imported
wrapper omitted `ordinal:1`. Pinned `rollout/src/ordinal.rs:23-50` and
`recorder.rs:1908-1930,1988-2012` establish metadata0/item1/checkpoint2. The repair
adds those exact expected ordinals, retaining full equality. Source audit also
corrected the later cold preview oracle: immediate resume derives preview from
raw supplied history (`thread_processor.rs:5033-5042`), while durable metadata
ignores raw ResponseItems and seeds preview from the first canonical user item
(`thread-store/src/thread_metadata_sync.rs:298-307,341-367`). Thus immediate
preview is exactly imported text; cold preview is exactly
`synthetic:defaults:911`. No history, provider-input, identity, cleanup, no-work
assertion or deadline is removed. The failure and first repair are retained in
`/tmp/samgita-native-history-stdio-v1-20261025/` and
`/tmp/samgita-native-supplied-history-repair1-20261025.md`. Failed results/source
SHA256 are `6a2ac62921fb75f6cbdd7621893655ae5e803d68e6d9a8a18091b995bf607269` /
`7b14c4ec2f4d8fb049b2377cfbf042b7985d9cc4862ac90efde4fa6ab9811b85`.

The complete five-file owning block, including the independent
[stdio startup regression](stdio-startup-confidentiality-qualification.md), passes
**54/0** at seeds501432/987654, 32.1/32.2 seconds. Warning-free compile/tests,
formatting, root strict Credo and unchanged executable-source snapshots pass.
Exact commands/logs remain in `/tmp/samgita-native-history-stdio-v2-20261025/`;
results SHA256 `3b6627ff784a70877295af7ec2bf081612ec54baa3e5fdf368ade711216db0e5`,
source SHA256 `e57074a14793dd6a009c2918d931d4751c6f3541eb692f74ffae01a97c8f498f`.

Exactly `ThreadResumeParams.history` gains a scoped implemented physical owner.
Other ResponseItem variants, multi-item histories, transport/OS combinations and
the broad default/lifecycle rules remain unqualified; no full or verified
promotion follows. Final-source complete local/hosted checks, A11 and the full
goal remain incomplete.

## Session start source and actual request provenance

One further native case covers omitted, null, `startup` and `clear` on a single
connection initialized with `experimentalApi:false`. This field is stable,
optional/nullable, with no schema default. Pinned
`app-server-protocol/src/protocol/v2/thread.rs:45-53,117-121` and
`app-server/src/request_processors/thread_processor.rs:1500-1523` map omitted/
null/startup to New, clear to Cleared. Neither branch selects or deletes another
thread. `history/src/initialization.rs:14-32` supplies runtime request provenance;
`core/src/responses_metadata.rs:330-366` and `core/src/client.rs:1071-1086` carry
it into the actual Responses HTTP body.

The test preserves full outbound maps and independently checks missing versus
present `sessionStartSource`. Four distinct idle paginated roots have prescribed
settings, unique owned IDs/paths and no ancestry. No start may invoke inference,
turn/item execution or an interaction. Exactly four subsequent explicit fixed
turns920..923 complete with native-correlated IDs and fixed assistant content.
Their actual provider metadata must be `new/new/new/cleared`; each request must
contain its own user marker once and none of the other markers. Full earlier
thread projections and every rollout byte remain unchanged through the clear
case and at the final check. No automatic resume occurs. Materialization is
checked after each explicit turn/read; a fresh root need not have a rollout
file before its first turn.

The complete five-file owning block passes **55/0 twice**, seeds501432/987654,
42.1/55.1 seconds, with warning-free compile/tests, formatting, root strict Credo
(429 source files) and a matching executable-source guard. The exact command is
the five-file block in [stdio qualification](stdio-startup-confidentiality-qualification.md#executed-qualification),
rerun after adding this case. Logs/commands are retained in
`/tmp/samgita-native-start-source-v1-20261025/`; results SHA256
`f5587a5332291a3f85e3a0d21a92b79f10ea74d57a0d1486bb03ae6001d9c744`,
source SHA256 `2a4821daaa144251469fd983df9cdf8d8b2dfbcea4d569203a6469449ef193e0`.
No repair, guard/deadline or shared-fixture change was needed.

Exactly the `ThreadStartParams.sessionStartSource` physical owner gains scoped
implemented evidence. This is runtime request provenance, not a persisted source
field guarantee after cold resume. Hooks remain disabled in this profile, so
Startup/Clear hook execution and side effects remain unqualified. No alias,
general default/lifecycle or fully verified promotion follows. Full final-source
local/hosted checks, A11, other profiles and the overall goal remain incomplete.
