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
