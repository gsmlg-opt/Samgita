# Retained compaction notification without a native producer

`thread/compacted` remains advertised by Codex `rust-v0.163.0`, but the pinned
production dispatcher deliberately suppresses it. Native v2 clients receive a
`contextCompaction` item instead. The retained notification is therefore
**blocked**, not verified. Its two field contracts remain missing native-success
evidence. No synthetic app-server message is counted as a native emission.

The immutable source is `83086188ae0614bd882818ff1aa23f3194962012`; the Linux
executable SHA256 is
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
No upstream code or target version is changed.

## Exact upstream evidence

The [wire declaration](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/common.rs#L2029-L2031)
explicitly says: `Deprecated: Use ContextCompaction item type instead.` The
[retained struct](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/thread.rs#L2172-L2175)
contains `threadId` and `turnId`.

The [production event arm](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/bespoke_event_handling.rs#L1016-L1020)
handles `EventMsg::ContextCompacted(..)` without sending a notification:

> Core still fans out this deprecated event for raw-event and rollout compatibility
> consumers;
> v2 clients receive the canonical ContextCompaction item instead.

The complete Rust-tree query, from the pinned `codex-rs/` directory, is:

```sh
rg -n --glob '*.rs' 'ServerNotification::ContextCompacted|ContextCompactedNotification' .
```

It has exactly five references: the struct and wire declarations above,
`app-server/src/notification_media.rs:113` (media classification),
`tui/src/app/app_server_event_targets.rs:140` (consumer routing) and
`tui/src/chatwidget/protocol.rs:398` (consumer ignore arm). None constructs or
sends the notification. This exhaustive search plus the explicit suppression arm
establishes the boundary; a missing message in a timed test alone would not.

Reproducible source hashes:

```text
7ac4d1bf125375c27018d7b0f5741d0bda1673bee147e5b196f61fe01e8280de  app-server/src/bespoke_event_handling.rs
8c10510bb88990aa0f0105e7a85c0bb7859db7232be29f84a6c66693600ef502  app-server-protocol/src/protocol/v2/thread.rs
ee03e7b76763ac658f4af3d36c0c1a26c00dff6ee9256d474dd85fa740143cc3  app-server-protocol/src/protocol/common.rs
```

## Evidence policy and remaining work

Existing actual-binary compaction tests retain canonical item, terminal turn,
history-retention, interruption and cold-resume assertions. They do not establish
this deprecated notification's positive emission. This source-only classification
adds no runtime qualification or decoder-success claim and promotes no field.
The lossless native schema and accessible decoder remain intact.

Do not manufacture an upstream producer, modify the pinned binary, treat a raw
legacy event as this v2 notification, or silently exclude its advertised schema
from the completion contract. Resolving the completion requirement for proven
unreachable entries needs an explicit target/evidence-policy decision. Independent
reachable compatibility work continues while this requirement stays blocked.
