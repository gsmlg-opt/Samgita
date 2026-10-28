# Remaining thread-search source prerequisites

This is source evidence for official Codex `rust-v0.163.0`, commit
`83086188ae0614bd882818ff1aa23f3194962012`. It adds no runtime acceptance.
The four physical `ThreadSearchParams` owners below remain **missing**. An empty
result for an absent source does not prove positive selection or production.
No manifest state, executable, test, permission behavior or deployment changes.

| Physical owner | Exact pointer under `v2/ThreadSearchParams.json#` | Literal |
| --- | --- | --- |
| 6076 | `/definitions/ThreadSourceKind/enum/3` | `appServer` |
| 6079 | `/definitions/ThreadSourceKind/enum/6` | `subAgentCompact` |
| 6081 | `/definitions/ThreadSourceKind/enum/8` | `subAgentOther` |
| 6082 | `/definitions/ThreadSourceKind/enum/9` | `unknown` |

The complete experimental JSON SHA256 is
`5c3bbb9d37d7d83f3f7747423427ff9c8b0f1154ac8cd7c832995a763dfa8e61`.
It is a pinned generated export; no standalone JSON/TypeScript archive member
exists for that filename. The archived Rust request/type declaration and the
earlier [experimental-generation evidence](ordinary-generic-subagent-search-qualification.md)
provide its source basis. No new schema generation is claimed here.

## Native source and executable boundary

The actual search processor loads stored content and source metadata, then
applies a post-filter. All four kinds use a broad store scan before the exact
core-source match (`app-server/src/filters.rs:17-30,51-80`,
`request_processors/thread_processor.rs:2765-2870`). Their prerequisites differ:

- **appServer** requires `CoreSessionSource::Mcp`. The supplied multicall
  `codex app-server` entry passes `SessionSource::VSCode` unconditionally
  ([CLI source](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/cli/src/main.rs#L1281)).
  Changing the initialize client name cannot create an Mcp-origin history.
  The separate app-server main exposes `--session-source`, and its parser maps
  `mcp`/`appserver` to Mcp (`app-server/src/main.rs:47-55,126`,
  `protocol/src/protocol.rs:3063-3077`). A matching immutable official executable
  exposing that selector has not been established for the current profile.
- **subAgentCompact** requires an actual `SubAgentSource::Compact`. Ordinary
  compaction runs within its existing Session; a compaction item or summary is
  not a Compact-origin child (`core/src/tasks/compact.rs:29-96`,
  `core/src/compact.rs:117-177`). The bounded non-test core constructor search
  found a metadata match arm and no producer. This is incomplete producer
  discovery, not global proof that no constructor exists.
- **subAgentOther** requires `SubAgentSource::Other`. Custom child roles and
  the generic subAgent filter do not change that variant. A production
  constructor exists in a path excluded from the user's current verification
  scope. Synthetic upstream store/list fixtures do not supply an ordinary
  permitted producer. Other possible producers have not been exhaustively
  excluded; this owner remains missing.
- **unknown** requires core Unknown before public conversion. Internal-to-Unknown
  presentation does not satisfy that filter (`thread_data.rs:54`, `filters.rs:80`).
  Malformed stored-source fallback (`thread-store/src/local/read_thread.rs:538-541`)
  would require injected metadata. It cannot replace genuine production. The
  separate app-server source selector provides a source route, subject to the
  same executable prerequisite as appServer.

The existing `native_thread_source_kind_unit_input_test.exs` creates a real
VSCode thread and explicitly requires empty results for the absent source
kinds. Its helper documents that limit. Existing actual Cli, VSCode, Exec,
Review, ThreadSpawn and generic-subAgent success supplies no positive evidence
for these four owners.

## Required next proof

First establish a permitted genuine producer in the pinned executable profile.
For appServer/unknown, obtain and verify the official selector-bearing executable
and its immutable provenance. Compact/Other need a permitted source-grounded
producer before a native test is designed.

Then create a real matching history and a same-content unrelated-source control.
Require singleton positive selection and exclusion with original correlated
request/reply bytes, repeat in a distinct cold reader, and preserve the histories,
provider-call counts, inputs and owned-process cleanup. A terminal single page
keeps this separate from the known timestamp/backwardsCursor defect. No model
source label, direct store edit, scripted app-server frame or unverified alternate
executable can satisfy this proof. No tests in excluded profiles are proposed.

## Immutable evidence and limits

Source archive SHA256:
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Complete local files below match their unique archive members byte-for-byte.
Paths are relative to `codex-rs/` at the pinned commit.

| Source | SHA256 |
| --- | --- |
| `app-server/src/filters.rs` | `a55c6f5896073df242fd4e06d0831496291ebf42501b0ac2e07a72158a99f0fc` |
| `app-server/src/request_processors/thread_processor.rs` | `f98fdad7df37ad720e63b75488ffab99ae88f7de4578b280ab957a09f0a98153` |
| `app-server/src/main.rs` | `6c027c0307379f7426f25812e4422d5740ac6a128a28a51bcf79267516457ced` |
| `cli/src/main.rs` | `54437cf29a22e2f4606c816bde8fe4b00a38929ff281a02f5eb497f1c05e1bb0` |
| `app-server-protocol/src/protocol/v2/thread.rs` | `8c10510bb88990aa0f0105e7a85c0bb7859db7232be29f84a6c66693600ef502` |
| `app-server-protocol/src/protocol/v2/thread_data.rs` | `293359f14a1a11da8d54acce7bc69b5756c1d30b5a59e8768f5ce6b4e02edeb1` |
| `protocol/src/protocol.rs` | `8a586a54d3ce19e3eaa5410e08c6724b7554f9a70126b3eb309180e54da98655` |
| `core/src/tasks/compact.rs` | `6291a21cb965e45a580b21f54e7f2a6f43da40b14f533cadb9f782d5c29015d4` |
| `core/src/compact.rs` | `28363b56f58b999358b3f2fbf9953a1633818c0a74f5a71a3d7f3d813144355a` |
| `thread-store/src/local/read_thread.rs` | `7f44115d6332636272133b184d55a835598d182ad054201c00239d626e135f32` |

Exact scalar node hashes in owner order6076/6079/6081/6082:

```text
622214a100066aceb1d1ab827c78dee8aaf32f7cd66e8c02400287fe6cb589c3
d85a2934393a355694655213a832fb9ac656cbc45e0c07bee9498246d5b131b0
8c84b24aaff54b79cff49fb22b4fb5b9c289d6a9a6991f9c3b2795f80e6aaaa7
53331ee8a3d89d5e956086b9c9ffaa709efef795a17c43bbc9666bb622947f8e
```

The source-only review is retained at
`/tmp/samgita-ordinary-thread-search-next.md`, SHA256
`148f79979d749855eaaf0a9493d4045a467d7ab6fb34ac00825db33bda273daa`.
Only source/text/archive reads and hashes underpin these findings. No runtime,
security/permission test, audit, external-service acceptance or global
unreachability proof follows. These owners and full compatibility stay incomplete.
