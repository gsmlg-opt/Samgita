# Deprecated native multi-Agent mode values

At immutable `rust-v0.163.0`, the `thread/start` and `turn/start`
`multiAgentMode` fields are accepted but explicitly ignored. This unit qualifies
that native no-op contract; it does **not** establish active delegation.
Source remains `83086188ae0614bd882818ff1aa23f3194962012`; executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

## Source evidence and actual behavior

The pinned [thread declaration](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/thread.rs#L110-L113)
and [turn declaration](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/turn.rs#L287-L290)
document deprecated/ignored behavior. Thread creation binds the value to
`_multi_agent_mode`; the turn processor's explicit settings construction omits
it. The native start response and public settings conversion return fixed
`explicitRequestOnly`. The v166 evidence archive-byte-matches six relevant Rust
files; the v168 independent source-only review checks their complete plumbing.
No upstream process or message is replaced with a fake to manufacture evidence.

Two functional matrices each cover omission, null, `explicitRequestOnly`,
`proactive` and the published custom object. The deserializer-only `none` alias
is outside these published alternatives and receives no evidence here.
Thread-start cases use five independent native threads and one explicit turn
each; turn-start cases use five turns on one thread. Every captured native
request checks its entire ID/method/params envelope and exact response ID.

Distinct summary-only updates provide applied public snapshots before/after the
turn without supplying a mode. Effective model/provider/effort/personality/mode
stay fixed. Actual model input retains prescribed developer instructions and
one user marker; the custom hint never enters it. Stock native assistant items,
exact completed history and five-call journals corroborate each case. These
assistant-only fixtures do not spawn delegates or test execution authority.

Capture stays bounded to 32 frames/4096 bytes; exact totals are ten/six.
Functional completion uses the fixed deadlines and local collector, preserving
existing helpers and their cleanup. Final native executable hash, owned process
disappearance, config bytes, empty workspace and ready/uncertainty state match.
No security, permission, credential, authorization or approval tests run.

## Integrated checks and limits

The final seven-file functional block is the six files in
[resume qualification](resume-personality-values-qualification.md#final-integrated-checks)
plus `test/native_multi_agent_mode_values_test.exs`, from the driver directory,
with `--warnings-as-errors --seed 501432` and then `--seed 987654`.
Both runs pass **18/0**, in 32.055/31.870 command seconds. Compile/format, root
strict Credo and the 230-file source guard pass. No failed native run or timeout
increase occurs. Before the first run, a config literal uses an equivalent sigil
to meet the already known lint rule; all runtime bytes and assertions stay fixed.

Exact commands/logs/source are in
`/tmp/samgita-v169-multi-agent-mode-checks/functional/`; results/source SHA256:
`fb845af87a58457ec951d2cdc27216aee1589186672b8b3014623f59305798ba` /
`91e34b117bcd755daa2af5ab318445b080f67b7613aef45b4fd7d4efae57dd1c`.

Only six direct owners, indices **6334–6336 and 6525–6527**, become implemented.
No shared enum, alias, active-delegation scenario or broad requirement inherits
evidence. Contracts become **4,585 implemented / 1,977 missing / 59 blocked**;
requirements remain **462 implemented / 12 missing / 11 blocked**; both have
zero verified. Other transports/platforms/backends, external success, full
compatibility, A11 and broad/hosted gates remain incomplete. No release,
publication, production migration or deployment occurs.
