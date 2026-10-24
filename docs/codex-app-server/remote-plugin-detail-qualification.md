# Native remote-plugin schedule metadata

Status: scoped implementation evidence. Five actual-native cases pass against
immutable `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`,
official Linux musl executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
No real marketplace/account, scheduled execution or full compatibility is
qualified by this metadata profile.

## Public native producer and bounded backend

`plugin/read` uses the stock remote-plugin detail implementation. The new peer
returns synthetic backend data; only the actual binary produces app-server
responses. It composes the existing file-auth, private namespace, stdio bridge
and confirmed process guardian. It replaces the backend with a metadata-only
HTTP listener inside a private loopback-only namespace, and proves no IPv4 or
IPv6 default route. Shared lifecycle code is unchanged.

Only the exact detail GET and installed GET are admitted, plus three fixed
startup metadata routes. The detail query is empty. The installed query is
exactly `scope=GLOBAL`; the other reconcile operation's limit/download options
are not part of this method. Bearer, account and product headers must match
synthetic fixed credentials; journals contain verification booleans. Startup
plugin refresh is disabled and individual explicit requests enable the feature
through the established fixture boundary. No model, download, mutation,
scheduler, tool or shell route is available. Every case asserts no loaded
threads, forbidden HTTP request or fixture error.

The five cases independently prescribe:

- All four hourly/daily/weekdays/weekly tags and exact summary fields, repeated
  on the warm connection and through a separately started cold native process.
- Missing/null backend metadata as an explicitly present `scheduledTasks:null`,
  while an empty array remains empty. A later absent result cannot reuse prior
  populated data.
- Hourly u32 boundaries, omitted/null/empty days, opaque time strings and weekly
  empty/ordered/duplicate days. The native serde type preserves these values;
  this profile imposes no clock interpretation or Samgita schedule policy.
- A malformed member rejecting the entire detail, without a subsequent
  installed lookup or partial data. Each invalid interval, required field,
  string/array type, weekday and tag has its own native diagnostic. Corrected
  data succeeds on the same connection.
- HTTP404/401/429/503 remaining errors, followed by successful recovery.
  No-auth and API-key modes have exact distinct authentication errors and make
  no detail GET. Authentication errors cannot become an empty success.

Every owned native/controller/namespace PID must be reaped, and native-close
journal counts must equal starts. Roots are deliberately retained and printed
for deterministic body/initialization/teardown evidence; they contain only
synthetic local data. No platform database or task history is changed.

Pinned source anchors:

- [Protocol metadata types](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/plugin.rs#L772): summary fields, schedule tags, u32 and weekdays.
- [Remote release decode](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core-plugins/src/remote.rs#L626): snake_case `scheduled_tasks` containing the shared camelCase schedule type; remote detail and installed reads at line1354.
- [Native request processor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/plugins.rs#L2297): remote detail forwarding and error classification at line2434.
- [Official native producer test](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/tests/suite/v2/plugin_read.rs#L336): synthetic authenticated remote schedule metadata; local plugin metadata is always null and cannot qualify these alternatives.

## Checks, retained first failure and limits

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-native-plugin-detail-v2-20261024.py
```

Full commands, source snapshot and terminal results are retained in the matching
directory. Driver compile, scoped format and root strict Credo pass; the latter
checks **413 files**. Native seeds `501432` and `987654` each report **5/0**,
no exclusions, 15.7/15.8 seconds. The final source guard matches. The first runner
at `/tmp/samgita-native-plugin-detail-20261024/` stopped at strict Credo exit8
before any native scenario: nested cleanup checks exceeded the depth rule.
Extracting those same checks into a helper fixes it; no deadline, PID assertion,
message/error oracle or production code changes.

| File | Final SHA256 |
| --- | --- |
| `native_remote_plugin_detail_profile.exs` | b767222e77c443d7a165c39d8e124aaf2362f8e8a765cdb166d45695d1c91b6b |
| `isolated_plugin_detail_fixture.py` | c90ff9ac7bf53322a80a1a1c1da13200aa1a66026525c860ffd6f6477b777882 |

Only positively asserted canonical schedule/task/weekday owners under the
actual `PluginReadResponse` gain scoped implemented evidence: **30 owners**,
one collection field, eighteen schedule branch/field/tag nodes, four task
summary fields and seven weekday values, each with its own canonical hash and
direct assertion/call references. No whole
PluginDetail, equal-hash transfer, other endpoint, scheduler execution or fully
verified promotion is inferred. Hosted execution and complete final-source
checks remain separate requirements. A11, upstream-unreachable paths, real
account/backend and other OS profiles remain incomplete. There is no release,
publication, production migration or deployment.
