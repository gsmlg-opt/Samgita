# Legacy file-output notification has no stock emitter

The four physical `item/fileChange/outputDelta` envelope owners remain
incomplete and are **blocked** for native-success qualification at official
Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`. Retained schema/codec support is
not a real notification trigger. No scripted peer, manufactured history,
modified upstream executable or mock frame supplies acceptance evidence.

The decisive upstream [wire declaration][declaration] states:

> Deprecated legacy notification for `apply_patch` textual output.
>
> The server no longer emits this notification.

The complete official source inventory confirms the distinction. All **5,259**
Rust files in the local reference match the immutable source archive, SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`,
with no extra local Rust files. A complete search for `FileChangeOutputDelta`
or `fileChange/outputDelta` finds exactly six locations:

| Official source | Line | Role |
| --- | --- | --- |
| `app-server-protocol/src/protocol/common.rs` | 2010 | Retained wire variant declaration |
| `app-server-protocol/src/protocol/v2/item.rs` | 1524 | Deprecated payload type above |
| `app-server-test-client/src/lib.rs` | 102 | Notification-name inventory |
| `app-server/src/notification_media.rs` | 96 | Existing-variant media classification |
| `tui/src/app/app_server_event_targets.rs` | 119 | Client-side notification consumer |
| `tui/src/chatwidget/protocol.rs` | 171 | Client-side notification consumer |

There is no stock producer constructor among these references. The current
[event mapping][mapping] converts `EventMsg::PatchApplyUpdated` to
`ServerNotification::FileChangePatchUpdated`, whose wire name is
`item/fileChange/patchUpdated`. It does not produce the deprecated textual
notification. Existing actual-native file-change tests qualify the current
event and their own effects; they cannot confer evidence on the legacy name.

Only the following physical `ServerNotification.json` owners change from
missing to blocked. Each canonical node matches both generated and vendored
stable/experimental schemas. Requirement-level states are unchanged; no native
test or transport coverage is added.

| Index | Exact pointer |
| --- | --- |
| 2947 | `/oneOf/40` |
| 2948 | `/oneOf/40/properties/method` |
| 2949 | `/oneOf/40/properties/method/enum/0` |
| 2950 | `/oneOf/40/properties/params` |

The exhaustive source hashes, six exact symbol locations, six decisive complete
source hashes, schema-export hashes and four canonical hashes are recorded in
`/tmp/samgita-v476-file-output-boundary/source.json`, SHA256
`9e0f789ff4a2b5380082d0663c0dd7e9ca959a5c34d08b81db3e6619c4422221`.
This is ordinary source evidence, with no native process, backend, security,
credential, permission or approval test. The source-only finding neither
qualifies a different transport/backend nor removes any acceptance gate.

The driver continues to preserve the retained wire payload for consumers that
receive it. The completion contract must still treat native-success acceptance
as unavailable at this pin. A supported upstream producer in a separately
qualified reference, or an explicit accepted scope decision for this proven
legacy boundary, is the minimum prerequisite for changing that conclusion.
No local workaround or implicit scope exclusion is introduced. Other reachable
ordinary behavior continues independently; full compatibility remains open.

[declaration]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/item.rs#L1517-L1524
[mapping]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/event_mapping.rs#L422-L428
