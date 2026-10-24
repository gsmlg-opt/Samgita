# Native file effects, failure persistence and approval reasons

These four tests exercise stock Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux musl binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Only the prescribed model responses are synthetic. Native Codex verifies and
executes patches, requests decisions, produces notifications and stores history.
All files, processes and provider endpoints belong to disposable fixtures.

## Demonstrated effects

- `native_file_move_delete_test.exs` explicitly approves a move, declines a
  delete and later approves the delete. Independently prescribed native item
  maps retain the source path, populated destination, exact diff, delete content
  and completed/declined statuses. File bytes, directory contents and an
  unrelated canary verify effects before and after each decision. Exact direct
  `thread/items/read` maps and history survive confirmed native shutdown and a
  distinct process, without resume, replay or extra model calls.
- A separate test pauses the second delete approval, removes only the fixture's
  exact owned target, then accepts that captured request once. This intentional
  fixture mutation is separate from native effects. Native returns exit 1 and
  a `failed` FileChange with the original delete diff, without sandbox retry or
  target recreation. Live, hot direct, cold direct and complete history reads
  independently assert the failed item; successful move history also remains.
- `native_permission_glob_effects_test.exs` grants a writable parent while
  omitting the requested deny glob from its reply. Native's normalized grant
  still contains the deny. A public sibling changes successfully. The private
  patch encounters the retained sandbox restriction and requests a retry with
  reason `command failed; retry without sandbox?`. The test explicitly declines
  it, checks `declined`, preserves private bytes and verifies both interactions
  resolve and reject stale responses. It never authorizes unsandboxed retry.
- `native_file_approval_reason_test.exs` first updates an owned mode-0600 file
  without approval. After the fixture changes that same file to mode 0444, it
  requires actual read-only access and observes the nonnull native retry reason.
  Explicit decline preserves bytes/mode/canary; native shuts down before the
  fixture restores its own mode. This qualifies failure classification and
  reason propagation, not sandbox security.

All cases retain the 60-second test and 15-second event deadlines, bounded
draining, original item/turn/request identities, stale-handle rejection, empty
uncertainty and explicit owned-process/port/guardian completion checks.

## Source-backed corrections to the first draft

The first combined run failed two of three tests. The move summary used the
destination, while the draft expected the source. The glob draft incorrectly
forbade the private retry callback. Neither failure was a successful result.
Logs remain in `/tmp/samgita-native-move-glob-v1-20261024/` and the diagnostic
wire in `/tmp/samgita-glob-first-failure-wire-20261024.log`.

The immutable [patch path selector](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/apply-patch/src/parser.rs#L93-L109)
uses the move destination for affected-path summaries. The
[summary producer](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/apply-patch/src/lib.rs#L826-L841)
therefore emits `M moved.txt`, then `D moved.txt`. The corrected test checks the
exact summary suffix within intercepted exec output; it does not fix elapsed
timing or change the source-path/destination item assertions.

For the glob case, the runtime merges additional permissions, but
[orchestration](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/orchestrator.rs#L158-L229)
computes unsandboxed eligibility from the environment baseline. A retained
additional deny therefore does not suppress the retry prompt. The exact private
item ID and reason establish which patch failed; the test preserves that
authority boundary by declining. No successful private write or vulnerability
is inferred. Directory-deny preapproval and glob-denial retry remain distinct.

The missing-target delete is a genuine native nonzero result:
[non-force removal](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/apply-patch/src/lib.rs#L501-L551)
fails, and the
[core item emitter](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/events.rs#L599-L622)
persists the failed FileChange. The tests directly verify the resulting store;
source support alone is not counted as execution evidence.

## Unreachable populated grantRoot

The production calls in
[approvals.rs](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/approvals.rs#L738-L759)
both pass `None` for grantRoot. The
[app-server projection](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/bespoke_event_handling.rs#L640-L657)
only copies that value. TUI `/testapproval` constructs a populated value in
[local UI injection](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/tui/src/chatwidget/slash_dispatch.rs#L631-L662),
which is not a production native app-server producer. This positive branch
remains unverified. The [legacy approval evidence](legacy-approval-qualification.md)
also remains blocked; synthetic peers do not replace either missing producer.

## Qualification

The four file tests plus the eight-case
[default-semantics profile](default-semantics-qualification.md) pass **12/0** at
both seeds `501432` and `987654`. Warnings-as-errors compile/tests, Python fixture
parsing, package formatting, strict root Credo and before/after source hashes
pass in `/tmp/samgita-native-effects-semantics-v1-20261024/`;
`results.json` records exact commands. The earlier three-file block also passed
twice before strict Credo exposed nesting in the separate new semantic helper;
the helper was extracted without changing its assertions, then the final block
passed. No assertion, deadline, guard or process-cleanup rule was removed.

Twelve precise missing live/direct-store contracts gain scoped `implemented`
evidence; reason/grantRoot fields gain supplemental evidence and explicit limits.
No row becomes fully verified. Add/create, failed in-progress store snapshots,
all transports/OS profiles, remote effects and complete approval lifecycle
acceptance remain separate requirements. The final combination still needs the
complete local and hosted matrix. A11, publication and deployment are unchanged.
