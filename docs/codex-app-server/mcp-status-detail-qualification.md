# Native MCP status detail and repeatable ordinary checks

`native_mcp_status_detail_test.exs` exercises the immutable Codex
`rust-v0.163.0` threadless `mcpServerStatus/list` producer. Four sequential
requests preserve omitted, explicit `null`, `full`, and repeated `null` parameters
in original outgoing frames. Every native result must contain independently
prescribed, nonempty resource and resource-template metadata. The local stdio MCP
dependency journals a distinct process and initialize/tools/resources/templates
discovery for every request. It supplies MCP data only; the real executable
produces all app-server responses. No thread, model or hosted-service bootstrap
is involved. Other status fields remain outside this functional check.

The source pin is `83086188ae0614bd882818ff1aa23f3194962012`; executable SHA256
is `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The [nullable input](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/mcp.rs#L50)
is an ordinary Option; the
[production default](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/mcp_processor.rs#L394)
maps omitted and null to Full. The test preserves their different wire shapes
and requires the same discovery effects, without claiming different Rust values.
The [threadless collector](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/codex-mcp/src/mcp/mod.rs#L504)
starts an eager connection and cancels it after collecting the snapshot.

Only contract **4216**,
`schema:v2/ListMcpServerStatusParams.json#/properties/detail/anyOf/1`, gains
scoped implemented evidence. Six complete producer/protocol sources match the
official source archive; the canonical null subtree matches the generated and
vendored export. Binding `/tmp/samgita-v464-binding/source.json`, SHA256
`bb0d5bec8370c7591c59097c779c62bfc33ffc3062f1a95c3b4e7bce9ff2e662`.
No sibling null, status or method owner inherits this evidence.

Capture is bounded at 64 frames, 64 KiB each and 512 KiB aggregate. The peer
journal is bounded at 128 rows/128 KiB; RPC and observation deadlines are five
seconds, the case 60 seconds. Checked cleanup waits for the owned driver owner,
closed Port, absent native PID and all journaled MCP PIDs before fixture removal.
Fixed YOLO launch is setup only. No permission or credential behavior is tested.

Initial exact-file command, from `apps/samgita_codex_driver`, passed **1/0**:

```sh
mix test test/native_mcp_status_detail_test.exs --warnings-as-errors --seed 501432
```

Log `/tmp/samgita-v464-owning-501432.log`, SHA256
`ddc7f689e0b2b499894a640ec6ae3e583ad0f50a2afc59bcf12617a5c8b01bc6`.
Final test SHA256 `4d949e554c3e89e950600746b8696ed7d512d6cbb0005e3b55ed5a69b8357a56`;
peer SHA256 `bc363da3756359be7eeb9b03024c3921e92b7545cdbd9cb3ced9dc5b6d6edb50`.
Independent source review found no concrete functional defect.

## Repository-owned verification command

`scripts/codex/check_ordinary.py` replaces the temporary-only command assembly
with an explicit reviewed selection. Inspect it before execution:

```sh
python3 -B scripts/codex/check_ordinary.py --list
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-20261027
```

The output directory must be new. The runner executes three overflow/replay
cases at each of seeds 455834/501432/987654, 39 named driver files at seeds
501432/987654, the outside-umbrella real-binary consumer, inventory consistency,
and the retained compile/format/Credo/Dialyzer/assets static checks. It requires
the exact case counts; the WebSocket selection explicitly excludes the other
13 cases in its mixed file. It runs no database recovery/admission tests, broad
suite, audit or hosted workflow. The pinned executable and compatible installed
Elixir/OTP environment are prerequisites; it provisions neither.

The reviewed source fingerprint includes the runner with only its fingerprint
literal normalized, manifest, schemas, dependencies, test helpers and fixtures.
Source changes require review before updating it. Each serial step retains an
original log, command, exit status and hash; the runner stops on the first failure
or wrong test count, records source identity and command-plan digest, and treats
drift as incomplete qualification. Each child gets an owned process group;
timeout/interruption terminates that group while retaining its waitable leader.
Existing detached native-process cleanup stays under the driver owner.

The combined-source selection completed all **14 steps** with exit 0: **61/0**
driver cases at each fixed seed, **3/0** selected WebSocket cases at each of
three seeds (13 other cases excluded), outside consumer **1/0** (seed 599458),
and all listed static checks. All **1,657** fingerprinted sources stayed exact.
The Elixir 1.18.5/OTP 27 environment was the same verified environment used by
the preceding qualification. The runner's ordinary subprocess timeout and
interruption probes also passed, with both owned parent/child PIDs absent;
these are harness checks, not Codex compatibility evidence. No failure, deadline
increase or removed assertion occurred in this profile.

Evidence directory `/tmp/samgita-ordinary-v464/` contains original logs, commands,
results and source snapshots. `results.json` SHA256:
`d59aa394a537e626744cda93564e4074a1c2ec82ddbb592d5843c9ef5c52548c`;
`source.json`: `689463fda22e5f0e75454d63998e43e691e1d3e6a1772a421b4de52655b71c50`;
command-plan digest:
`d7223f39726cf38527977020cc67cea16c06dac03a154101acd62b638c80ae6b`.
Lifecycle probe `/tmp/samgita-v464-runner-lifecycle.json`, SHA256
`998469467095ec1c3e9c72ad67c41b368434a77523e5f2a747ccbd21c3ccc489`.

Counts are **5,289 implemented / 1,224 missing / 108 blocked** contracts; requirements
remain **462 implemented / 12 missing / 11 blocked**, zero verified in both.
Security/permission tests and audits, broad/hosted workflows, A11, unavailable
upstream producers, real external/OS profiles and full compatibility/release
remain incomplete. No publication, deployment or production migration occurs.
Continue ordinary native HOOKS/MCP configuration detection and import; their
advisory detail lists do not authorize or prove hook/MCP command execution.
