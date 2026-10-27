# Retained, non-emitting file-change output notification

The later [V457 field binding](retained-notification-producer-limitations.md)
also marks its four physical field contracts blocked, preserving the historical
synthetic evidence below. The earlier counts/status wording records that stage.

`item/fileChange/outputDelta` remains an advertised wire contract in immutable
Codex `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, but
its defining source explicitly says the server no longer emits it. The required
actual-native enabled-success evidence is blocked, not complete. Retaining the
codec and handler does not make a synthetic message a native event.

## Immutable upstream evidence

The [type declaration and deprecation comment](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/item.rs#L1517-L1529)
state: “Deprecated legacy notification for `apply_patch` textual output” and
“The server no longer emits this notification.” Its required `threadId`,
`turnId`, `itemId` and `delta` fields remain strings. The immutable
[wire declaration](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/common.rs#L2010)
retains `FileChangeOutputDelta` under that method name. The original generated
stable/experimental schemas carry the same description and remain unchanged.

A complete pinned Rust source search for
`FileChangeOutputDeltaNotification|FileChangeOutputDelta` finds only five
locations: those two declarations, `app-server/src/notification_media.rs:96`
(media classification), and TUI consumers in `tui/src/app/app_server_event_targets.rs:119`
and `tui/src/chatwidget/protocol.rs:171`. There is no constructor or production
producer. The local search log is `/tmp/samgita-retained-output-source-search.log`.
The explicit upstream comment is positive evidence of non-emission; absence in
one test run alone would not establish that source contract.

This is distinct from `item/fileChange/patchUpdated`, final file-change items
and `turn/diff/updated`, which have production paths and still require their
own actual-native assertions. Existing patch disk effects do not qualify any
unasserted notice. It is also distinct from the four source-blocked
[legacy approval entries](legacy-approval-qualification.md) and the separately
recorded non-emitting MCP progress notification.

## Retained contract tests

`apps/samgita_codex_driver/test/retained_output_notification_contract_test.exs`
contains two explicitly synthetic tests, requiring no executable or platform:

- Validate every required string field, preserve empty/Unicode/control text
  through the codec, and reject missing/null/wrong-type fields.
- Deliver the complete notification through a scripted Session under both
  stable and experimental negotiation, preserve future envelope data, keep it
  separate from server requests and an unrelated pending RPC, then settle only
  the correctly correlated response.

These tests qualify only local schema/codec/handler behavior. Their evidence
must remain labeled synthetic. They cannot close native-emission acceptance;
the notification entry remains `blocked` and its four field contracts remain
`missing` with the limited contract evidence attached. No schema is removed,
no pin is changed, no event is fabricated by a native fixture, and no upstream
repository is modified.

## Verification

Source/spec and code review passed before installation. Review moved cleanup
registration immediately after Session startup, before waiting for a transport
message. No production source changed. All commands below ran serially under
`devenv shell --no-tui --`, with `MIX_ENV=test`:

```sh
# From apps/samgita_codex_driver
mix compile --warnings-as-errors
mix format test/retained_output_notification_contract_test.exs
mix format --check-formatted test/retained_output_notification_contract_test.exs
mix test test/retained_output_notification_contract_test.exs --seed 501432
mix test test/retained_output_notification_contract_test.exs --seed 987654
# From the repository root
mix compile --warnings-as-errors
mix credo --strict --files-included apps/samgita_codex_driver/test/retained_output_notification_contract_test.exs
```

Both runs passed **2 tests / 0 failures**, each in **0.2s**. Compilation,
formatting and scoped strict Credo passed (**322 source files loaded, 69 checks,
no issues**). The command exited zero; its log is
`/tmp/samgita-retained-output-validation.log`. No repair round, Codex process,
network listener, account or native-emission test was involved. These successful
synthetic checks remain separate from the blocked native requirement.

## Remaining acceptance prerequisite

The immutable target cannot supply the documented removed production emitter.
Credentials or a different fixture do not repair that prerequisite. An explicit
target/evidence-policy decision is needed to reconcile advertised retained wire
contracts with mandatory enabled native emission. Until then, retain this
requirement and the complete-evidence failure. Do not count another version,
modified upstream or scripted messages as complete acceptance for this pin.
External/platform profiles, A11, publication and deployment remain separate
incomplete gates.
