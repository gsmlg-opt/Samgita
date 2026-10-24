# Native goals and explicit user provenance

Five cases in `apps/samgita_codex_driver/test/native_goal_test.exs` drive the
immutable real Codex `rust-v0.163.0` executable through stdio. Native goals belong
to Codex threads. They do not create Samgita goals, start work automatically in
these cases or satisfy Task review/acceptance.

The selected profiles establish:

- All three stable goal RPCs return the exact native disabled-feature error
  when `features.goals` is false. Their use does not require experimental API
  negotiation; that is a separate gate.
- A paused goal trims its objective, retains timestamps/thread identity and
  zero usage, emits its exact update notification and survives get/update.
  Omitted budgets preserve a prior value; explicit null clears it when no maximum
  exists, or resets it to the configured maximum. Inactive status updates and
  repeated clear operations do not start a turn or model request.
- Objective limits count Unicode scalars: 4,000 mixed lambda/emoji scalars
  succeed; 4,001 fail. Empty objectives and nonpositive/over-maximum budgets fail
  without changing the existing goal. Ephemeral and unknown threads reject all
  three operations with distinct native errors.
- Explicit `origin: "user"` edits and clear are retained as user instructions,
  including cold writes before the thread runtime is loaded. Automatic, missing
  and null origins cannot acquire user provenance. After a confirmed process
  close/resume, one explicitly started synthetic turn sees both approved edits
  in order and the clear instruction; it never sees the automatic objectives as
  user instructions.

The initial five-case run had two fixture failures: setup had discarded the
disabled tag before writing configuration, and the budget maximum was put at
the TOML root instead of `[goals]`. Fixing these fixtures retained every original
disabled/budget assertion. No runtime change, timeout increase or skipped check
was used. Five cases passed seed `501432`; the coordinator's goal/MCP combination
passed **9 tests**, seed `987654`.

Pinned source references, relative to `codex-rs/` at
`83086188ae0614bd882818ff1aa23f3194962012`:

- `app-server-protocol/src/protocol/common.rs:615-629`: stable goal RPCs.
- `app-server/src/request_processors/thread_goal_processor.rs:139,169-196,259,281`:
  feature checks, loaded/cold budget configuration and mutation dispatch.
- `ext/goal/src/api.rs:158-176,243`: omitted/null/default budget semantics.
- `protocol/src/protocol.rs:4205-4218` and `ext/goal/src/tool.rs:425-445`:
  scalar objective length and positive/maximum budgets.
- `core/src/config/mod.rs:4504-4512` and its `config_tests.rs:400-413`:
  `[goals].max_goal_token_budget` configuration.
- `app-server/src/request_processors/thread_goal_user_context.rs` and upstream
  `guardian_goal_tests.rs`: explicit user provenance and durable instruction order.

Logs: `/tmp/samgita-native-goal-{initial,repair-1}.log` and
`/tmp/samgita-native-timeline-protocol-goal-mcp-green.log`. All homes, threads,
objectives and credentials are synthetic. The provenance cases use the real
app-server plus a loopback model fixture; no inference/provider account is used.

The later [automatic budget profile](goal-budget-qualification.md) and
[provenance/quota/stock-tool profile](goal-control-qualification.md) add selected
active continuation, computed stops and cold retention evidence. Active
crash/accounting reconciliation, remaining concurrency/field variants and other
deployment profiles remain unqualified. The three methods and their two
notifications have selected implementation evidence; none is fully verified.
