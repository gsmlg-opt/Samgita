# Actual native client-request capture

Four native cases add scoped evidence for **21 exact physical contracts** in
`ClientRequest.json`: method, selected method enum and params for `thread/start`,
`thread/resume`, `project/import`, `project/read` and `thread/readState/update`,
plus the two complete read/unread operation maps and their discriminators.
No whole-request, request-ID variant, other schema owner or verified promotion
is inferred. Referenced params qualify only the explicit combinations exercised.

The immutable target is Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Pinned `protocol/common.rs:552-562,785-800,864-867` binds those exact requests.
All selected node hashes were independently recomputed from the physical
experimental `ClientRequest.json` file before indexing.

`NativeClientRequestCaptureTest.CaptureStdio` is a test-local wrapper around
the real owned Stdio transport. After a successful send it retains the exact
encoded/decoded synthetic request, bounded to 64 selected messages of at most
4096 bytes each; overflow fails. It leaves upstream output untouched, captures
no initialization/credentials and changes no production logging or transport.
Every result/error ID must match the captured submitted request, and the whole
outgoing envelope must equal the supplied params with no implicit additions.

Independent oracles distinguish merely sending bytes from honoring the request:

| Request | Native effects |
| --- | --- |
| thread/start | Explicit never policy differs from configured on-request; selected roots and cwd appear in durable creation metadata |
| thread/resume | Cold roots B replace persisted A; original creation metadata stays A, a new settings snapshot is B, and another native process restores B without override |
| project/import and project/read | Distinct projects retain known metadata/member histories; changed-payload key replay cannot reassign the control member; cold reads select the right object |
| thread/readState/update | Read/unread variants change independently queried revision/state, survive process restart and reject a stale revision without overwriting the winner |

No model request, turn, tool or command is initiated. History bytes and names
remain intact where applicable; no uncertain/pending interaction remains.
Cleanup delegates to the retained owned-process barrier, including failures.
These native Codex Projects are fixture state, separate from Samgita Projects.

With `CODEX_BINARY` set to the pinned executable, from the driver directory:

```sh
mix test test/native_client_request_capture_test.exs test/native_config_option_projections_test.exs --seed 501432
mix test test/native_client_request_capture_test.exs test/native_config_option_projections_test.exs --seed 987654
```

Both passed **8/0**, 12.8s each. Compile with warnings-as-errors, package format,
root strict Credo and the focused source-hash guard passed. Commands, exits,
test hashes and complete logs are retained in
`/tmp/samgita-native-capture-projections-v2-20261024/`. The first draft also
passed both native seeds, but strict Credo found a numeric-format and a nested
helper issue; both were corrected and all focused checks rerun. Its original
results remain in the v1 directory. No assertion, deadline or gate was relaxed.

The complete final-source matrix is tracked separately in
[repair qualification](repair-qualification.md). A11, real external/OS success,
unreachable emitters and full compatibility remain incomplete. No publication,
deployment or production migration occurred.
