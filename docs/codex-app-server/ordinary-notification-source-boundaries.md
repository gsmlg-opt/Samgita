# Ordinary notification producer boundaries

This source-only continuation follows
`f7345589c242d176d054cb59c489f6fc46855655` on `main`. Target is official
Codex `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`.
It records why six exact physical owners still lack native notification
evidence. No mock, history record, successful API response or equal-hash alias
is substituted for a notification. No implementation, native launch, security,
credential, authentication, authorization, approval, sandbox or permission test
is performed. Fixed YOLO setup stays unchanged.

## Ordinary child creation and public ThreadStarted are separate

The actual ordinary model `spawn_agent` path creates a genuine
`SessionSource::SubAgent(ThreadSpawn)` containing descriptive nickname/path.
That source does not reach `ServerNotification::ThreadStarted` on the traced
ordinary path:

1. `core/src/tools/handlers/multi_agents_v2/spawn.rs:125–162` invokes the real
   spawn implementation. `core/src/thread_spawn.rs:99–112` builds ThreadSpawn
   source; `core/src/agent/control.rs:593–619` supplies native nickname/path.
   `core/src/agent/control/spawn.rs:760–788,835–844` passes that source into
   actual child startup.
2. [Thread finalization](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/thread_manager.rs#L2451)
   consumes the first SessionConfigured event before exposing the CodexThread.
   The event is returned separately in NewThread, not left in the listener queue.
3. `core/src/agent/control/spawn.rs:970–973` broadcasts only the child UUID.
   [App-server's receiver](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/lib.rs#L1298)
   attaches listeners for initialized connections. The attachment at
   `request_processors/thread_processor.rs:3770–3839` registers/drains events;
   it does not construct ThreadStarted.
4. `request_processors/thread_lifecycle.rs:143–205,233–389` delegates drained
   events to bespoke conversion. The production match in
   `app-server/src/bespoke_event_handling.rs:140–1275` has no matching
   ThreadStarted translation. Deprecated child activity events at977–997 and
   the fallback branch do not manufacture it.

The three explicit production emitters are public start, public fork and
detached review. Their bodies and ordinary source assignment were inspected,
rather than relying on a negative text search:

- Public start at `thread_processor.rs:1484,1510–1526,1572–1588,1652–1664`
  uses startup options without `session_source`; ThreadManager falls back to
  the app-server manager's ordinary source.
- Public fork at `thread_processor.rs:5387–5401,5476–5500,5594–5635,5689–5710`
  also omits child source. Its inherited-options/prediction route copies settings
  into `StartThreadOptions::new(config)` without copying session_source
  (`core/src/thread_manager.rs:1485–1510`). Changing lineage/history does not
  preserve the original child's source in the new notification.
- [Detached review](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/turn_processor.rs#L1473)
  emits ThreadStarted after AgentRunner startup, but
  `ext/agent/src/lib.rs:47–78` likewise does not set Review source.
- Inline review supplies Review source to a direct Session
  (`core/src/tasks/review.rs:125–141`, `core/src/codex_delegate.rs:96–129`),
  whose bridge drops SessionConfigured at343–367. It does not create the
  managed child notification above.

The projection helper at `request_processors/thread_summary.rs:220–222` wraps
an already supplied Thread; settings overlay does not rewrite its source.
Other read/history/AgentSpawn values remain separate physical owners. This
is a bounded absence finding for these stock routes, not a universal claim
about every alternate embedding or an authorization to modify upstream.

## Project hook provenance lacks an established fixture input

`hooks/src/engine/discovery.rs:825–841` maps
`ConfigLayerSource::Project` to `HookSource::Project`. This conditional
provenance mapping exists. It does not prove a project layer entered discovery
or that a matching HookStarted/HookCompleted frame was delivered.

The reviewed ordinary generators `scripts/codex/tool_hook_fixture.py:237–304`
and `plugin_hook_fixture.py:233–311` write the isolated user config plus the
already covered CLI/plugin inputs. The SessionFlags case creates an empty
workspace and fixes CODEX_HOME to its separate user-config directory. It does
not establish a project `.codex/config.toml` input. The existing plugin-hook
qualification explicitly leaves Project provenance outside its scope.

No new admission/trust setup was investigated, designed or performed. Keep
this candidate at its fixture prerequisite boundary. It is not an upstream
impossibility finding. A future permitted scenario must independently establish
that input and observe actual native notifications with the exact source value.

## Adjacent remote-disable response prerequisite

A separate bounded review leaves remote-disable response owners5031–5034
unchanged. `app-server/src/request_processors/remote_control_processor.rs:63–82`
calls either disable path. In
`app-server-transport/src/transport/remote_control/mod.rs:355–398,818–849,957–969`,
sequential disable constructs status `disabled` and `environment_id:None`.
`app-server-protocol/src/protocol/v2/remote_control.rs:185–200` copies that pair.
This does not produce the response's `connecting`/`connected`/`errored` owners
5031–5033 or a nonnull environmentId for5034. Concurrent writers were not
established as a producer and are not claimed impossible.

The processor obtains a handle before either path; a fresh successful scenario
needs an admitted handle. Review stops at that prerequisite, without examining
or adding admission/policy behavior. The only actual remote-control profile is
mixed/restricted and remains unrun. Similarly named ordinary remote lifecycle
fixtures concern plugins; they provide no remote-control evidence. Historical
disabled/null observations cannot be relabeled as a new ordinary acceptance.
These four records receive no manifest modification or runtime credit here.
The three complete files also match the pinned archive:

| Source under `codex-rs/` | SHA256 |
| --- | --- |
|`app-server/src/request_processors/remote_control_processor.rs`|`34a891caca1c163d253ba8cfafaed490e5ee63467c956e075e07443eaae459d0`|
|`app-server-transport/src/transport/remote_control/mod.rs`|`07146b098b5bd854d43673f343a237c3ec185d78f1e92409a173600a61cdd359`|
|`app-server-protocol/src/protocol/v2/remote_control.rs`|`26a76375d0b9286de8740ff6550801cf85c22563e6d68b8734f86f5ba17f372f`|

## Exact unchanged owners

All six physical nodes belong to stable `ServerNotification.json`. Canonical
JSON uses sorted keys, two-space indentation, UTF-8 and a trailing newline.
States, tests, implementation modules and transport coverage remain unchanged;
only append-only source evidence/limitations are added.

| Owner | Pointer under `/definitions` | Canonical SHA256 |
| --- | --- | --- |
|2259|`/HookSource/enum/2`|`7f51421cffd8e5eea782ff7bad1d60b0e4c269cd77a182907cd4eefe4e72a11c`|
|2404|`/SubAgentSource/oneOf/0/enum/0`|`049325e91469f33f035f3153f87a3a89d93e41f292dd00fc5df091496a7ad2c2`|
|2409|`/SubAgentSource/oneOf/1/properties/thread_spawn/properties/agent_nickname`|`67f0689e1c8ccd3216aeecbb51d53b4c1317267308d341e1b8af082aae3310af`|
|2410|`/SubAgentSource/oneOf/1/properties/thread_spawn/properties/agent_path`|`bf16a21a4a406f1e2fc39c43c21f4f48ce3ad57ed144ddab1d867050c3972d47`|
|2411|`/SubAgentSource/oneOf/1/properties/thread_spawn/properties/agent_path/anyOf/0`|`1bef6f9728beaba3998133575a18426e06da265fee27e0614fc8f5fd05ab1a19`|
|2412|`/SubAgentSource/oneOf/1/properties/thread_spawn/properties/agent_path/anyOf/1`|`b7c373d0981a5441c9dd775ad89a68ba691af04e4da70eaeaacaaf54549837fb`|

Source reports:

- `/tmp/samgita-spawn-threadstarted-source-closure-20261029-report.md`, SHA256
  `2906befb29276850da35e117579264aa2efe3ada8250cb76240e4f4c38420d6f`.
- `/tmp/samgita-hook-project-source-boundary-20261029-report.md`, SHA256
  `01075c36a4b5839a04d30e199d37f0d19859b98726a418c8e2b33ef796e51a5d`.

The source binding verifies all nineteen complete causal files against archive
SHA256 `e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
It also checks the six physical-node hashes, unchanged requirement/contract
states, append-only evidence, and every other guarded hash against the preceding
successful17-step snapshot.

## Metadata-only qualification

```sh
python3 -B /tmp/samgita-notification-boundaries-binding-20261029.py
```

The binding passes, including fresh `scripts/codex/inventory.py --check`.
It permits only evidence/limitations additions to these six exact rows, preserves
all states/tests/modules/coverage and all485 requirements, and checks all1,761
other guarded hashes against the successful existing-call snapshot. The runner
changes only its fingerprint literal; its normalized content, commands,166/21
case counts and original bounds remain exact. Every prior17-step result,
command, count, deadline and original log hash is rebound. There is no fresh
runtime test or new binary/platform success assertion.

Reviewed fingerprint is
`f5085fb834b6c82365616cc109bd09d4558356a39a893da2ef9db3456817239a`.
Evidence `/tmp/samgita-notification-boundaries-binding-with-remote-20261029/binding.json`
has SHA256 `b368adbd434179a5ad6126f07d15e0d11eb3dfb9a2f513dde93b71bec08f4eea`.
The final binding includes the three adjacent remote-disable source files;
the earlier sixteen-file binding remains a valid narrower record.
The fresh inventory log SHA256 is
`0d98cdb3e17fb613b9e32450810e8b60557a2d449b6818a3d240a0663cb0aa19`.
Prior functional `results.json`/`source.json` hashes remain
`dc0fe4f442ecd2031b452adebe506489cf1fe684eb41bc3a50db2fcd2d0e03c3`/
`d6c49b729b57dca19be1cd914ec9f590efe62de9a0beb7d1b7c00478e429b9fa`.

Future native qualification of the child leaves requires an actual matching
stock emitter or a separately accepted target/evidence-contract change. The
hook leaf requires an independently established permitted project-layer input.
Neither prerequisite was silently supplied by a fixture, and neither branch is
counted as complete. Continue only independently supported ordinary work.

No fresh runtime, native notification, field implementation, assembly,
publication or deployment credit is added. Counts remain **5,756 implemented
/729 missing /136 blocked contracts**,462 implemented/12 missing/11 blocked
requirements and zero globally verified. Prohibited/broad/hosted checks, A11,
unavailable source routes, external/platform success and full/release gates
remain incomplete. Rollback restores these six metadata supplements and the
corresponding reviewed fingerprint; no runtime/data migration occurs.
