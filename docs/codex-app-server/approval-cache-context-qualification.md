# Native command context and multi-file approval caches

The immutable stock Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
passes two additional approval cases. Together with the seventeen retained
projection/persistence cases, **19 tests / zero failures** pass at both seeds
`501432` and `987654` in 20.4 seconds per test run. These are selected real-native
behaviors, with synthetic model responses; complete compatibility remains open.

## Independent effects and association

`native_command_cache_context_test.exs` runs four prescribed safe printf turns.
The first argv/cwd A prompts and receives explicit `acceptForSession`; the
identical second command in A executes without a new callback. The same argv in
cwd B requires a new approval and is explicitly declined. After confirmed owned
native process shutdown, a distinct process cold-resumes the persisted thread;
A prompts again and is declined. Exact argv, cwd, stdout, exit/status, provider
counts 2/4/6/8, turn IDs, unchanged canary files and absence of persistent rules
distinguish ephemeral authority from durable history. Old handles remain stale.
Cold resume itself makes no model request. No native request is automatically
replied to or retried.

`native_multifile_approval_test.exs` first accepts file A for the session. One
later patch updates A and adds fresh B: a single new native callback must
correlate by thread/turn/item ID to the native item containing **both** exact
prescribed changes. File approval params have no invented path/diff fields.
Explicit decline preserves A's original bytes and B's absence. A later A-only
update succeeds without a callback, showing that the mixed decline did not
evict A's existing authority. The test independently checks real bytes, complete
directory listings, provider continuations/counts and persisted file items.

Both tests use private disposable HOME/CODEX_HOME/TMPDIR, ordinary launch
overrides, no inherited credentials and the existing native process guardian.
Shutdown requires Session DOWN, a closed port and completed owned cleanup before
final file/provider teardown. The retained 15-second event deadlines reject gaps
and unexpected callbacks. This local stdio profile does not claim network
namespace isolation or real provider authentication.

## Corrections established from pinned source

Failed drafts are retained as evidence, rather than hidden by retries:

- Combined runner v4 ran 19 cases with one failure: it incorrectly expected
  `["printf"]` as the execpolicy amendment suggestion. The pin evaluates the
  configured private shell independently from the inner command. The exact
  suggestion is `[owned_private_shell_path]`; the test keeps its fixed private
  shell and complete argv assertions. Only session acceptance/decline are sent;
  no amendment is accepted. Source: `core/src/unified_exec/process_manager.rs`
  1494-1531; `core/src/exec_policy/executable_identity.rs` 20-92;
  `core/src/exec_policy.rs` 426-436, 916-934, 958-1019. Unix configured-shell
  discovery uses passwd `pw_shell`, not `$SHELL`
  (`shell-command/src/shell_detect.rs` 61-64).
- Runner v5 ran 19 cases with one failure: ordinary declined pre-launch command
  items are live notifications but are absent from durable command history.
  The final test asserts each declined live item, nil output/exit, unchanged
  files and every persisted turn ID/status, and explicitly requires an empty
  command list in declined history turns. Successful history remains exact.
  Source: `core/src/tools/approvals.rs` 403-425;
  `core/src/tools/orchestrator.rs` 204-224;
  `core/src/unified_exec/process_manager.rs` 530-539, 588-595;
  `core/src/tools/handlers/unified_exec/exec_command.rs` 459-464;
  `app-server/src/bespoke_event_handling.rs` 1453-1498, 2021-2024, 2071-2086;
  `app-server-protocol/src/protocol/thread_history_projection.rs` 78-98.
  Switching history mode would not create a durable core item.
- The initial standalone multi-file run failed its one case because its draft
  expected raw patch hunk `@@\n`. The exact native update diff starts with
  `@@ -1 +1 @@\n`, derived through `TextDiff::from_lines(...).unified_diff()`
  with context radius one (`apply-patch/src/file_update.rs` 172-207;
  `app-server-protocol/src/protocol/item_builders.rs` 370-376). The final oracle
  checks the complete native diff against an independent constant; no wire
  normalization or weaker comparison was introduced. Its standalone rerun and
  the final combined runs pass.

Cache ownership follows `core/src/tools/approvals.rs` 220-258, 638-687, 725-764;
`core/src/tools/runtimes/unified_exec.rs` 93-101;
`core/src/tools/sandboxing.rs` 65-117. All keys must be cached, only session
acceptance inserts them, and command cwd participates in identity. A fresh
SessionServices owns a fresh store (`core/src/state/service.rs` 70;
`core/src/session/session.rs` 1744). These source claims explain the observed
effects; they do not substitute for other runtime profiles.

## Commands, artifacts and limits

In verified Devenv, `MIX_ENV=test`, `CODEX_BINARY` set to the hash-checked pin,
from `apps/samgita_codex_driver`:

```sh
mix compile --warnings-as-errors
mix format --check-formatted
mix test test/native_filesystem_projections_test.exs test/native_persisted_media_test.exs test/native_initialization_metadata_test.exs test/native_config_safety_projections_test.exs test/native_persisted_user_inputs_test.exs test/native_persisted_execution_items_test.exs test/native_command_cache_context_test.exs test/native_multifile_approval_test.exs --warnings-as-errors --seed 501432
# Repeat the identical test command with --seed 987654.
```

Root `mix credo --strict`, in-memory Python fixture parsing and exact test/support
source guards also pass. Runner and terminal artifacts:
`/tmp/samgita-native-followup-projections-v6-20261024.py` and its same-named
directory; v4/v5 retain the failed expectations above. This is no new runtime
repair, timeout increase, skipped assertion or approval-policy relaxation.

Five existing requirement entries receive supplemental citations only. No
schema contract or state is promoted: `lifecycle:approval-decisions` stays
missing, all 485 full requirements remain unverified. The older lifetime/loss
records describe their own checkpoint scopes; this record adds these precise
cache dimensions without qualifying every environment/key/decision variant,
pending cold callback restoration, all transports/OS/services, legacy emitters
or A11. Final combined-source and hosted qualification remain separate required
gates. Nothing is released, published or deployed by these tests.
