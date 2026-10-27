# Native sleep, compaction and command output

This continuation covers ordinary native runtime values with explicitly owned
Codex `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, binary
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Fixed yolo settings apply to the owned profiles. No old permission/isolation
profile is invoked, no app-server frames or history are manufactured, and no
external backend or paid inference is used. Runtime and shared helpers remain
unchanged.

| Native scenario | Direct physical owners | Boundary |
| --- | --- | --- |
| One real clock.sleep call | ServerNotification **2535–2539** | Sleep variant, requested duration, stable ID and exact type/literal |
| Local thread compaction | ThreadItemsReadResponse **5524–5526** | Persisted contextCompaction ID and exact type/literal; live copies are separate |
| One command with two output streams | ServerNotification **2102–2105** | Stdout/stderr branches and each branch's exact literal |

## Real sleep

`native_sleep_item_events_test.exs` enables `sleep_tool` in `always_on` mode,
with current-time reminders disabled and the system clock selected. The model
fixture requests exactly one `clock.sleep` with `duration_ms:1`. Stock Codex
registers the function and performs its actual wait; the second provider
request receives its real function result. Complete native tool schema,
literal arguments, `fc_`/`fco_` identities and exact output shape are checked.
The reported elapsed time must be at least 1 ms and remain within the
host-observed turn interval, allowing only the output's decimal rounding at
the upper bound. A no-op return cannot satisfy the lower bound.

The actual producer is
[sleep.rs:102–152](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/sleep.rs#L102).
It creates `Sleep{id,duration_ms}`, emits a start, waits, emits completion and
returns the completed/interrupted result text. This profile exercises normal
completion only. Registration is
[spec_plan.rs:1397–1412](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/spec_plan.rs#L1397);
[extension forwarding](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/item.rs#L1002)
retains the exact item.

The test requires complete prescribed start/completion maps, actual identities,
paired order and bounded native timestamps. Warm full/selective reads and
first-cold selective/full history preserve the exact item and timestamps after
confirmed native replacement. Rollout/config/catalog/provider bytes and exactly
two inference requests remain unchanged; workspace/uncertainty checks and
existing 5-second request, 20-second turn and 256-event/1-MiB bounds remain.

The initial owning test passes **1/0** at seeds 501432/987654. Parent review
strengthens its elapsed lower bound from zero to the requested 1 ms; both
owning runs pass again. Logs are `/tmp/samgita-v295-sleep-{501432,987654}.log`
and `/tmp/samgita-v295-sleep-parent-{501432,987654}.log`. No deadline or existing
assertion is weakened.

## Local compaction

`native_compaction_item_selection_test.exs` reuses the existing Responses-only
model fixture. After one completed seed turn, it requests
`thread/compact/start` with a configured literal compact prompt. The second
provider request independently identifies the new compaction turn and contains
the original user input, prior assistant answer and explicit compact prompt.

Pinned
[compact.rs:271–273](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/compact.rs#L271)
creates and starts the item;
[429–430](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/compact.rs#L429)
completes the same item. Its UUID-v7 comes from
[protocol/items.rs:509–520](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/protocol/src/items.rs#L509).
The independent oracle validates UUID version/variant and its embedded
millisecond timestamp against the observed compaction interval, then requires
the literal `contextCompaction` type, same ID and complete ordered native
start/completion maps. The compaction and seed turns must both complete.

Warm selective reads and the first content read after native replacement must
return the exact completed item/timestamps. Duplicate/absent IDs and wrong-turn
queries have explicit outcomes. Full warm/cold history retains both completed
turns and the original literal seed user/assistant contents; original
rollout/config/catalog/provider bytes and the two-request inference budget
remain intact. Parent review adds the explicit seed-content assertions.
This is local compaction only. Deprecated `thread/compacted` owners3889/3890
remain blocked; no live notification, alias or whole-variant evidence transfers
to these three directly queried response fields.

## Native command streams

V401 adds [original incoming-frame evidence](command-output-ingress-qualification.md)
to this owning test. Runs below describe the earlier source; the current
24-case matrix passes twice with all original byte/order/result assertions retained.

`native_command_output_stream_values_test.exs` needs no provider. One owned
Python `-I -c` process writes prescribed stdout/stderr bytes containing Unicode,
NUL and invalid UTF-8, then exits 7. The request uses a literal process ID and
request ID, enables streaming and supplies bounded timeout/output capacity.
Each native delta must retain the current generation, ordered unique sequence,
exact stream label, canonical base64, process ID and false cap flag.
Reconstruction is exact per pipe; relative stdout/stderr ordering is deliberately
unconstrained. The correlated final result is exactly exit 7 with empty captured
stdout/stderr. No inference or thread execution entry point is called.

Pinned
[command_exec.rs:480–500](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/command_exec.rs#L480)
starts separate readers; [613–621](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/command_exec.rs#L613)
creates typed stream/base64 notifications. The
[worker joins:561–579](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/command_exec.rs#L561)
provide a real response barrier before draining; no sleep or delayed polling
substitutes for completion. Native/child processes must both be reaped.

The first owning run fails because the expected envelope omitted the official
`emittedAtMs` field. The repaired oracle requires its exact presence and an
integer timestamp within the independently observed command interval.
[outgoing_message.rs:894–908](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/outgoing_message.rs#L894)
is the pinned timestamp producer. All byte, order, result and cleanup assertions
remain. The command file then passes **1/0** at both seeds. Logs are
`/tmp/samgita-v295-owning-501432.log` and
`/tmp/samgita-v295-command-repair1-{501432,987654}.log`.

## Combined verification

The three owning files pass **3/0** at both fixed seeds after final review,
logs `/tmp/samgita-v295-owning-final-{501432,987654}.log`. The first aggregate
attempt passes format/compile, then fails strict Credo on the new compaction
test's zero-match `Enum.count` assertion. Replacing it with the equivalent
`refute Enum.any?` retains the check. Its original results/logs remain under
`/tmp/samgita-v295-functional-checks/functional/`; no warning is suppressed.

Eighteen complete producer/conversion files byte-match the immutable archive;
all twelve exact canonical nodes and their exports match pinned provenance.
Final source evidence is
`/tmp/samgita-v295-functional-checks/final-source-evidence.json`, distinct from
the retained initial source capture. Its SHA256 is
`ed2e2f9af8c365ae72f1e48b1e899923bb95a542c54e8550d4e5359a28fb629f`.

The corrected final explicit **37-file** matrix passes **63/0** at seeds
501432/987654, in **105.720/105.545** command seconds. Warning-free compile,
scoped format, strict Credo on 488 sources, the outside actual-binary consumer
**1/0**, twelve provider AST checks and the **271-source** unchanged-byte guard
pass; all eight commands complete. Exact environment/commands/logs are in
`/tmp/samgita-v295-run-final.py` and
`/tmp/samgita-v295-functional-checks/final-functional/`. Results/source SHA256:
`bd58542b3cb49b51f85001e6f686f50a018e805dc1dd05632a3357b6bf4ef5e8` /
`8a07656948f28f1ea9e2ee2b38f5e69aee5da621a46bd1b9f4674723e76c63ff`.
Adjacent final-binding.json checks exactly twelve changed owners, unchanged
requirements/schema identity/planned tests and preserved blocked deprecated
notifications and missing selective null-action owner5483.

Only these twelve owners become implemented: **4,818 implemented / 1,744 missing /
59 blocked** contracts, unchanged **462 implemented / 12 missing / 11 blocked**
requirements, zero verified. No alias, other export or broader profile inherits
evidence. Source retention and generic schema decoding do not establish a real
native entry point. Inventory consistency passes; strict completeness still
exits **1**.

Security/permission tests, audits, broad suites and hosted workflows remain
unrun under the user's restriction. A11, unresolved legacy emission paths,
unavailable external/OS profiles, full compatibility and release remain
incomplete. No publication or deployment.
