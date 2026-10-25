# Native Apps context, cold history and resume redaction

The complete origin profile passes **3/0 at both seeds501432/987654** after root
integration. Stock `rust-v0.163.0` emits every app-server item and response; owned
local model/Apps MCP dependencies supply prescribed inputs in a private loopback
namespace. Source is `83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
No real account, provider authorization or paid task is used.

## Live provenance and persisted identity

The original case drives two actual model-originated `codex_apps` calls with
prescribed connector/account/resource descriptors. Both live `item/started` and
`item/completed` must retain exact native IDs, thread/turn, tool arguments and all
five non-null `appContext` fields: actionName, appName, connectorId, linkId and
resourceUri. Expected values come from the prescribed fixture, independently of
returned context. Conflicting resource-read hints cannot select another origin;
the original account/resource provenance and negative guards remain unchanged.

Only host-configured `codex_apps` metadata supplies this native presentation
identity. Ordinary MCP connector claims are stripped at the native trust boundary.
This does not grant a Samgita Agent any Project role or execution permission.

The first added case completes the genuine producer, establishes its supported
warm history persistence barrier and closes/reaps the native process. A fresh
owned native uses the same isolated CODEX_HOME and native-written history. Its
first content operation is `thread/items/read` with the original generated
thread/turn and prescribed call IDs. Complete stored items, timestamps and duration
must match independently prescribed semantic payloads and genuine live timing.
Loaded-thread lists remain empty around selection; no resume, full hydration or
new turn primes the result. Exact model/tool/resource journals and request bytes
stay at the producer baseline, with unchanged workspace effects.

The fixture's explicit history/reuse mode restores only its dependency effect
oracle and cumulative owned-process markers. It does not write, restore or invent
native rollout/SQLite items. Reuse rejects a missing successful producer or an
unclosed prior native. Existing default operation allowlists and the original
test remain intact; new history operations require the explicit test profile.

## Exact remote-client response behavior

The second added case opens fresh native clients named exactly
`codex_chatgpt_android_remote` and `codex_chatgpt_ios_remote` in succession. Each
resumes the genuine prior thread with `excludeTurns:true` and an
`initialTurnsPage` requesting `itemsView:full`. Its two persisted MCP items retain
all five context fields while arguments become `[redacted]` and result content
becomes the prescribed redacted text with physical null metadata/structured data.
The successful producer has `error:null`; non-null error redaction is not claimed.

An ordinary selective read by that same remote client then returns the complete
original stored items. This proves the observed redaction is response-local; it
does not alter persisted data, authorize work or make client names a security
boundary. Every restart/resume/read preserves exact model/tool/effect counts.
Both original and replacement native/controller/namespace processes are checked
reaped within existing bounds. No timeout, cleanup assertion or original case is
removed.

## Immutable source and execution evidence

The source audit compares 24 extracted files with the retained official archive:
`/tmp/samgita-v104-next-native-gap/evidence.json`, SHA256
`5390d9f88b6a603da6af90422f7f582d6886d107b18f088dbe67ab308919d5ea`.
Key immutable producers are:

- [Native trusted context](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/mcp_tool_call.rs#L410-L430)
  and [API conversion](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/item.rs#L1037-L1062).
- [Canonical persisted projection](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/thread_history_projection.rs#L78-L85)
  and [whole-item JSON storage](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/thread-store/src/local/thread_history.rs#L433-L460).
- [Exact client-name response redaction](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_resume_redaction.rs#L6-L48)
  and [native resume application](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L4359-L4399).

In verified Devenv, `MIX_ENV=test`, from the independent driver directory:

```sh
mix compile --warnings-as-errors
mix format --check-formatted
mix test test/native_mcp_resource_origin_profile.exs --warnings-as-errors --seed 501432
mix test test/native_mcp_resource_origin_profile.exs --warnings-as-errors --seed 987654
```

Both root runs pass **3/0**, with root strict Credo and the three-file source
guard unchanged. Exact commands/logs are in
`/tmp/samgita-v111-integrated-origin-checks/`; result/source SHA256 are
`4eebae74545ff2af4a00e718928c549ee5e4d889bd62e3e95d71fe2d76ad253d` /
`776205b3fb215ba34fa36ed75ce0d668ee8e1d1986d509bc4b421ed2c2751125`.
The prior independent candidate also passes compile/format/strict Credo and
3/0 twice in `/tmp/samgita-v109-origin-history-checks/`, without a repair round.

Ten precise physical owners gain implemented evidence: the five context fields
in `ServerNotification.json` from live assertions, and the separate five in
`v2/ThreadItemsReadResponse.json` from actual cold selective reads. Resume/sibling
schemas are not promoted by inheritance. Contracts become **4,486 implemented /
2,076 missing / 59 blocked**; requirements remain **462 implemented / 12 missing /
11 blocked**, with zero verified in both ledgers. Optional absence/null, other
transports, external/backend/OS success and full final local/hosted qualification
remain incomplete. These synthetic-dependency native cases do not close A11,
upstream-unreachable emitters or full compatibility, publish a package or deploy.
