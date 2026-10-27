# Observed native creation metadata index

V425 starts from `main` `0759db07f3b5feb3157aeb9236f9749224d6ee11`.
This is an evidence-index correction with no executable change or new runtime
run. Seven still-missing physical owners already have independent positive
evidence in the current reviewed complete creation-snapshot test:

| Owners | Observed selected value | Remaining limits |
| --- | --- | --- |
|2422/2423|agentNickname/agentRole keys present as null|No nonnull names/roles; role is descriptive source metadata|
|2430|One complete local environment object with prescribed cwd/root|No null/empty/multiple/remote/default or connection-health claim|
|2434/2438/2456|extra/gitInfo/section exact null alternatives|Whole nullable wrappers and populated references stay missing|
|2457|sectionEnteredAt key present as null|No integer timestamp, default or omission behavior|

These are selected-value implemented bindings, never complete nullable-union
or full compatibility claims. Input-admission/permission-adjacent metadata is
excluded. No role metadata grants Project authorization.

## Existing independent actual-native observation

`native_creation_snapshot_notification_test.exs` starts two distinct ordinary
threads before any inference, with prescribed project/cwd/history/Daybreak
inputs. Its complete32-key oracle at382–420 literally expects the null values
and exact environment selection:

```elixir
"environments" => [
  %{"environmentId" => "local", "cwd" => row.cwd, "runtimeWorkspaceRoots" => [row.cwd]}
]
```

The cwd comes from the independent request specification. Native identity/path/
time are separately constrained; no metadata expectation comes from a response
copy. Full map equality rejects absent/extra keys, wrong nulls and wrong array
elements. Original pre-Session thread/started bytes at424–438 must match both
complete independent snapshots in order. Zero model requests during creation
is checked, then the same snapshots remain exact after two real later turns.

Pinned `thread_processor.rs:1570–1587,1652–1674` builds and publicly emits the
real snapshot. Its builder6581–6633 takes actual environment selections and
ordinary session-source metadata while setting extra/section/time/git_info to
None. `protocol.rs:3091–3107` supplies nickname/role only for spawned subagents;
these ordinary vscode threads have neither. Native `v2/thread_data.rs:204–297`
serializes Option values explicitly. `v2/environment.rs:10–31` defines exactly
environmentId/cwd/runtimeWorkspaceRoots; there is no credential, permission or
connection-health field in this referenced object.

Five complete source files match official `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`; seven canonical nodes match their
generated exports. Executable SHA256 remains
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
`/tmp/samgita-v425-source/evidence.json` SHA256:
`4a22bf3ddcf01cd513efdd695c2297a63bda1469578d168065306a0f51beba06`.

## Reused passing source and exact index limits

The [V421 final reviewed matrix](native-assistant-phases-qualification.md)
contains this exact owner and passes **43/0** at501432/987654. Its source guard
contains408 paths, all matching the current0759db0 bytes. Owner SHA256 remains
`fda45de162e822f3a56da0c56c04ecf90951704775a07378d6ae539f342ef323`.
V425 binds that source-equivalent result; it does not claim a separate execution.
Exact commands/logs/membership/hashes remain in
`/tmp/samgita-v421-functional-checks/final/{results,source}.json`.

The original case still has one native/provider pair, two project/create,
two thread/start and two later assistant requests; zero requests at snapshots.
Its 60s case/20s await,256 events/1MiB,32 methods and raw fewer-than32 frames/
4KiB each/128KiB total bounds stay intact. Configuration, provider, snapshots,
workspace, native identity and owner/Port/PID cleanup remain checked.
No new request, fixture, process, timeout, cap, dependency or runtime is added.

Binder `/tmp/samgita-v425-bind.py` verifies all408 source hashes, current exact
owner membership in both successful matrix commands, source artifacts and only
the seven physical row changes. `/tmp/samgita-v425-binding/evidence.json` SHA256:
`396d58d7e93f3dc0615f2c77aeb6551c7ef7ad870f42cc10033095d01c78d0a5`.
The consistency check preserves every other entry/variant, including extra/
gitInfo/section populated references and nullable wrappers. No alias/history,
subagent, remote environment or unobserved default behavior is inferred.

Contracts: **5,177 implemented /1,378 missing /66 blocked**. Requirements stay
**462 implemented /12 missing /11 blocked**, zero verified. Prohibited security/
permission tests, audits and broad/hosted workflows remain unrun; pushes suppress
CI. A11, unreachable producers, external/platform success and full-goal/release
gates stay incomplete. No publication or deployment. Rollback removes these
seven bindings and this index record, preserving all runtime/history. Continue
the separate actual-native TurnError inner-null case under its accepted bounds.
