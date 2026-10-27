# Ordinary realtime media and MCP event envelopes

V475 qualifies additional ordinary notifications against stock
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, binary
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Every app-server frame comes from that executable. The local realtime and
HTTP/SSE MCP servers implement backend dependencies, never replacement Codex
servers. Fixed YOLO is launch setup. No security, credential, authentication,
authorization, permission or approval behavior is tested. The retained
real-binary cases, process-owner cleanup and existing protections stay intact.

## Behavior and independent oracles

The realtime file retains all three start/stop, transcript and service-error
cases and adds one item/audio case. Actual start response, native started
notices and backend session readiness precede an explicit local release.
The backend sends a literal `conversation.item.added` and a valid nondefault
16 kHz stereo PCM `response.output_audio.delta`. Codex emits the complete
`thread/realtime/itemAdded` and `thread/realtime/outputAudio/delta` envelopes.
Independent expectations require the exact nested item, base64 bytes, four
signed samples `[0, 1000, -1000, 32767]`, two channels, two samples per channel
and output item ID. All eight selected original native frames equal consumed
events in order, with bounded emission times, generation and positive unique
sequences. Start ACK/readiness, release, media notices and requested stop have
explicit causal intervals; no silence-based readiness or longer timeout is
introduced.

After stop, native `thread/read` is a persistence barrier. Two complete timeline
entries must match exactly two physical `realtime_item` rollout rows, including
IDs, timestamps and ordinals. The backend item and audio observations do not
become invented history items. Repeated timeline reads and original responses
must agree; saved rollout bytes stay exact through shutdown. The peer journal
requires one WebSocket, one release request, one session update, precisely the
three backend messages, no inference request, no errors and bounded frame
counts. Nonsecret inputs remain frozen. Owned native/peer owners, Ports, PIDs,
socket and server/handler threads must all close before temporary files go away.

The MCP case makes no turn or model request. It materializes an empty native
paginated thread and opens `mcpServer/event/stream/start` through Codex's own
Apps MCP HTTP/SSE registration. A merely renamed configured stdio server cannot
produce this path: the pinned processor selects the host-owned Apps runtime.
The peer supplies that runtime at the local `chatgpt_base_url` route
`/api/codex/ps/mcp`. Fixed synthetic account data is positive startup setup only;
it is never read, frozen, asserted or captured. No backend header, credential
value, authentication mode or namespace-authority behavior is checked.

The case observes the real pending subscription before explicit activation.
Codex's original active notice must precede the correlated start response.
The caller's subscription ID is deliberately different from the observed
internal MCP request ID. A second released nested Unicode event must match
the independent full original envelope, including the internal metadata ID.
Exactly two native stream notices and nine unique correlated RPC pairs are
required. Complete start/stop ACKs, native emission bounds, generation,
sequence order and original incoming bytes remain checked.

Stop must produce actual peer EOF and a finished handler, with exactly one
stream. A native read/loaded-query barrier plus final drain establishes idle
driver state and unchanged empty-thread/history bytes. Config, model catalog,
peer script and inert workspace input stay exact; the synthetic account file
is excluded from observation. Native/peer owner, PID and Port cleanup plus
listener/server-thread closure are checked. Capture remains bounded at 128
frames, 8 KiB outgoing, 64 KiB incoming and 2 MiB total. RPC/observation bounds
remain five seconds and the whole case sixty seconds.

The unchanged creation-snapshot case also supplies a narrowly indexed
`runtimeWorkspaceRoots` owner: its independently prescribed complete 32-field
`thread/started` snapshot requires `[row.cwd]` for the local environment and
exact original incoming equality. No neighboring setting gains evidence.

## Exact source and schema binding

The V2 backend parser at `protocol_v2.rs:57–60,96–124` preserves the literal item
and audio fields. `bespoke_event_handling.rs:568–577,593–604` emits the native
notices. The history observer at `core/src/realtime_history.rs:202–222` has no
item/audio history effect; session persistence appends only completed history
items. Existing started/transcript/completed forwarding is also retained.

`request_processors/mcp_event_stream.rs:55–60` selects the Apps event path.
Its forwarding loop at `183–282` sends the original event body through a
connection-specific native notification and awaits the active send before
resolving readiness. Stop at `152–158` removes, aborts and awaits its task.
The MCP resource client's stream cancellation/drop and transport forwarding
complete that path. The observed peer EOF provides runtime cancellation
evidence, rather than treating a stop ACK as proof of cleanup.

`v2/environment.rs:14–31` maps thread environment selection workspace roots
without inventing another schema. The thread snapshot uses those selections.

Only these **31** physical `ServerNotification.json` owners gain scoped
implemented evidence:

| Indices | Exact owner and behavior |
| --- | --- |
| 2474 | `/definitions/ThreadEnvironment/properties/runtimeWorkspaceRoots` |
| 2971–2974 | `/oneOf/46`, stream envelope/method/literal/params reference |
| 3083, 3086 | `/oneOf/71`, realtime started envelope/params reference |
| 3087–3090 | `/oneOf/72`, itemAdded envelope/method/literal/params reference |
| 3091, 3094 | `/oneOf/73`, item-started envelope/params reference |
| 3095–3098 | `/oneOf/74`, item transcript envelope/method/literal/params reference |
| 3099, 3102 | `/oneOf/75`, item-completed envelope/params reference |
| 3103–3106 | `/oneOf/76`, flat transcript delta envelope/method/literal/params reference |
| 3107–3110 | `/oneOf/77`, flat transcript done envelope/method/literal/params reference |
| 3111–3114 | `/oneOf/78`, output audio envelope/method/literal/params reference |

Twenty complete producer/protocol files match the official source archive,
SHA256 `e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Every canonical subtree independently matches both generated and vendored
stable/experimental exports. Binding
`/tmp/samgita-v475-event-binding/source.json`, SHA256
`e988ca902fa4e3e88cdcdc1bb6fbd280c411373c034650d00b0611090bff813b`.
Eighteen nodes index retained realtime evidence; eight cover the new media
envelopes, four the new MCP stream envelopes and one the unchanged roots field.
No unlisted nested alias/default/variant, complete method/schema, SDP/sideband
path, remote backend or deployment profile gains credit.

## Failures and focused checks

The first format invocation omitted `MIX_ENV=test` and tried to load retained
dev dependency BEAMs under Devenv's OTP 27. It failed during
`Telemetry.Metrics.ConsoleReporter` type checking with `beam_lib` invalid-atom
data. Read-only inspection shows the dev telemetry BEAM compiler version
`9.0.6.1`, while the existing test BEAM uses `8.6.1.6`; the host is OTP 28.
The established `MIX_ENV=test` environment formats both changed files
successfully. No dependency source, cache deletion, assertion or guard changes
are made to fix this unrelated dev build state. Original failure output remains
in the session record.

The first MCP focused run fails **1/1** before peer startup. The test's Python
peer omitted the explicit absolute `CODEX_HOME` required by the shared Stdio
transport's normal environment setup. Adding only the owned `root/codex`
environment entry produces final **1/0**, 1.6 seconds. Every oracle and deadline
is retained. Initial log `/tmp/samgita-v475-mcp-event-501432.log`; corrected log
`/tmp/samgita-v475-mcp-event-final-501432.log`.

Focused commands from the independent driver directory, using Devenv's
Elixir 1.18.5/OTP 27, `MIX_ENV=test`, `ERL_FLAGS='+S 2:2'` and the pinned binary:

```sh
mix test test/native_realtime_start_stop_test.exs --warnings-as-errors --seed 501432
mix test test/native_mcp_event_envelope_test.exs --warnings-as-errors --seed 501432
```

Realtime **4/0**, 5.7 seconds; final MCP **1/0**, 1.6 seconds. Both Python
fixtures parse with the standard AST reader. Focused realtime/initial MCP/final
MCP log SHA256 values are respectively
`3c9a2b00fb1a474152793fab0113f5a670691eb1a8b647578834134a8b892b14`,
`79468b1a79af2600df051e30560d0a224e601d5d45d6e901f810c336a9977ad2`
and `da68d7d636c595ff7faa4a8049c77ece95ef3432c21e85b1a4b5fda7f0200398`.
Final realtime/MCP test hashes are
`6be5c99834e40f751ac31d20079a40b9be507a2a16d6eb70280dc9accf8b4670`
and `3e8644201c46a1d5240c367eaa6c6e191e81bb03ced44eb1611385d6abe98f8a`.
The source-only cross-review finds no actionable realtime defect; it grants
no playback/device/live-service/SDP or additional runtime credit. The parent's
baseline diff retains all three original cases and their assertions.

## Final reviewed functional matrix

Execution base is `e738dfbb236563fef7161784d02fd30ba069e188` plus the scoped
changes bound below. The exact 48-file/78-case command selection is printed
by `scripts/codex/check_ordinary.py --list`; its guard includes the test helpers,
fixtures, schemas, configuration, locks and generated assets. Final command:

```sh
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-v475
```

All **14** reviewed steps pass. Ordinary actual-binary cases are **78/0** at
seeds `501432`/`987654`, 129.177/130.079 command seconds. The three selected
WebSocket overflow/replay cases pass at `455834`, `501432` and `987654`, with
thirteen mixed-file cases excluded. The isolated outside-umbrella actual-binary
consumer passes **1/0**. Warning-free driver/umbrella compile, selected/root
format, inventory consistency, strict Credo on 585 source files, forced
Dialyzer and assets pass using Devenv Elixir 1.18.5/OTP 27 and Bun 1.3.13.
All **1,665** guarded source hashes remain identical before/after. No assertion,
deadline, required gate or source-guard exclusion is weakened.

Original commands/logs are in `/tmp/samgita-ordinary-v475/`. Results/source
SHA256 values are
`b9c88ef94c47d67fd7283d36e017e687232c3a1c6761b9303878ebc3220386fb` /
`2e3672f7c342c349d6b47fbd4492ae7da4cc9772f9cdfc4588957af62962de5a`;
command-plan SHA256
`0130ffee3bafa50d8c979d5ab8b5c2e285f7f8602cf3ad6c725c4904c5397566`;
reviewed fingerprint
`e75ae85789c8877df02796e5c4ef1c9b510f14f25f0f0deedee102a59d09c3f5`.

Counts after the exact mapping are **5,360 implemented / 1,149 missing /
112 blocked** contracts and **462 implemented / 12 missing / 11 blocked**
requirements, with zero verified in both. Prohibited tests/audits and broad/
hosted checks stay unrun. A11, unavailable legacy emitters, real external and
other OS/backend success, full compatibility, publication and release stay
incomplete. No production migration, service deployment or live credentials.
Continue with the genuine ordinary `write_stdin` terminal-interaction producer
and source-bound legacy file-output non-emission evidence. Neither is counted
as qualified by this unit.
