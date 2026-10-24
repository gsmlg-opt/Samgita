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
not establish successful nonempty history import; that contract stays missing.

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
