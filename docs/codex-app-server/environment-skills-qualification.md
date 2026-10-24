# Native executor required-skills gate

This is selected actual-binary evidence for `EnvironmentAddParams.skills` and
`EnvironmentSkillsParams.required`, not complete environment or provider
qualification. The target remains `rust-v0.163.0`, official source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Both the app-server and exec-server are the original immutable executable.

## Observable behavior

`native_environment_skills_profile.exs` explicitly registers `skills-available`
requiring `owned:review`, and `skills-missing` requiring `owned:absent`, against
one owned authenticated executor. Separate ordinary threads select the exact
environment/cwd and an owned capability root mapped to that environment. The
real filesystem contains only an inert plugin namespace manifest and an inert
`review/SKILL.md`; no skill catalog or executor response is injected.

Registration itself does not validate skill availability. Each explicit turn
causes bounded native filesystem discovery. The available skill permits exactly
one assistant-only request to an owned synthetic Responses provider and a native
completed turn with the independently prescribed message. The missing skill
produces the exact native error:

```text
Fatal error: Required skill "owned:absent" from environment "skills-missing" is unavailable
```

The test requires `willRetry:false`, `codexErrorInfo:other`, exact thread/turn
association, failed completion with the same error, no assistant item, and no
second provider request. Completion, rather than a quiet timeout, is the
pre-inference rejection barrier. Loaded-thread identity, exact registration and
turn counts, no pending interactions/uncertainty and all owned resource shutdowns
are asserted. The fake provider supplies fixed model data only; it does not
implement Codex, perform a skill action or establish live backend success.

## Containment and supported configuration

`isolated_environment_skills_fixture.py` retains the shared fixture hashes,
private user/network namespaces, loopback-only routes, bounded native framing,
connections, journal, stderr, deadlines and process reaping. Original upgrade
bytes require the exact synthetic bearer; missing/wrong credentials return401,
and valid credentials reach the real101 upgrade. Raw credentials never enter
the journal. App-server input is restricted to the exact scenario commands.

Only exact owned metadata, walk and read paths are admitted before original
frames reach the executor. The walk retains native depth6/directories2000/
entries20000. Writes, process/HTTP RPCs, arbitrary ancestors, symlinks and unknown
methods fail closed. Both manifests/config/catalog and skill-file bytes are
hashed and checked unchanged. The namespace manifest includes `mcpServers:{}`
so an unrelated `.mcp.json` lookup is unnecessary.

Two supported configuration boundaries are necessary:

- Global plugins and recommended plugins remain disabled. Only the owned plugin
  ID is enabled by policy. `thread/start.config` explicitly enables plugins for
  that thread, so genuine namespaced skill discovery is admitted without
  app-server startup featured-plugin HTTP warmup.
- The same request enables `features.cwd_relative_turn_diffs`. This supported
  display setting avoids unrelated Git-root ancestor searches. Project document
  reads are disabled and project root markers empty. An owned `.git` sentinel
  alone cannot confine pipelined ancestor probes.

These settings do not alter production defaults or relax the shared firewall.
The fixture rejects unexpected HTTP and RPC traffic and does not synthesize
NotFound or successful discovery responses.

## Immutable source and preserved initial failures

Source paths below are within the immutable official `codex-rs/`:

- `app-server/src/request_processors/environment_processor.rs:22-49` stores
  requirements; `core/src/environment_selection.rs:1221-1246` associates them
  with selected environments.
- `ext/skills/src/required.rs:15-57` matches exact enabled skill/environment
  names. `core/src/session/turn.rs:535-546` validates the discovered catalog
  before inference. `ext/skills/src/loader/environment.rs:113-199` and
  `loader/discovery.rs:55-90` perform actual bounded remote filesystem discovery.
- `app-server/src/bespoke_event_handling.rs:1034-1057,1510-1542,1614-1640`
  preserves the native Fatal error and failed completion; these are not invented
  RPC errors or fake Agent responses.
- `core/src/session/turn.rs:290-318,910-932` independently searches for a Git
  root for display diffs; `file-system/src/find_up.rs:96-119` pipelines probes.
  That producer does not consult `project_root_markers`.
- `app-server/src/message_processor.rs:542-560` starts plugin warmup using
  global config. `core-plugins/src/manager.rs:2824-2947` and
  `remote_legacy.rs:123-159` can request featured plugins independently of
  recommendations. `thread_processor.rs:1337-1356` applies supported per-thread
  config; `core/src/mcp.rs:211` uses it for selected-root admission.

Initial v4 and repair1/repair2 runs failed: effective plugins=false filtered the
namespace skill; global enablement caused refused startup HTTP; independent
display-diff discovery probed ancestors beyond the owned firewall. A substring
replacement also unintentionally matched `recommended_plugins` in a draft.
Exact-line configuration checks corrected that fixture defect. No unexpected
traffic was admitted to obtain a passing run, and no timeout, assertion or cap
was increased. These failures are not classified as harmless flakiness or a
production driver bug. The HTTP failure journal did not capture the requested
path, so its exact route is source-supported rather than directly observed.

The failed logs remain under `/tmp/samgita-native-repair-continuation-v4-20261025/`
and `/tmp/samgita-native-environment-skills-{v4-diagnostic,repair1,repair1-diagnostic,repair1-diagnostic3,repair2}-20261025.log`.
After two failed Sol repair rounds, bounded source diagnosis identified the
two independent producers. Its one subsequent actual-native control passes
**1/0** in `/tmp/samgita-native-environment-skills-astra1-20261025.log`.
Combined verification is recorded separately below; a contributor diagnosis
alone is not acceptance.

The final combined nineteen-file owning block passes **113/0 twice**, seeds
501432/987654 (168.4/171.8 seconds). The dedicated skills-first and timeout-first
controls each pass **1/0**. Warning-free compile/tests, formatting, root strict
Credo on433 files and the before/after executable/config/workflow guard pass.
Exact commands and logs are
`/tmp/samgita-native-repair-continuation-v5-20261025/`; results SHA256
`0bd111e5478afd8ce449be4e6e9814856db7ba0a3c56fe9e094dc570e390ae68`,
source SHA256 `104fc85eb0e8ac2b5dd1c234797116af680b081606ccdd59403f1d6a308e75af`.
This also reruns the earlier positive-time, permissions, notification/process,
executor metadata/request-ID and timeout oracles together. A full package/platform
matrix and final-pushed hosted result are still required.

The two exact physical primary nodes are:

| Owner | Canonical subtree SHA256 |
| --- | --- |
| `schema:v2/EnvironmentAddParams.json#/properties/skills` | `a77713bf9ef162b189e32a79014f55dfb7e254d66ab37af3c14dc7f4c4058b13` |
| `schema:v2/EnvironmentAddParams.json#/definitions/EnvironmentSkillsParams/properties/required` | `194c548147940b450311462180d07417b504c041f27cb7fd8dad668dc3d61776` |

## Reproduction and limits

From the independent driver in verified Devenv, `MIX_ENV=test` and the exact
hash-checked `CODEX_BINARY`:

```sh
mix compile --warnings-as-errors
mix test test/native_environment_skills_profile.exs --warnings-as-errors --seed 501432
mix test test/native_environment_skills_profile.exs --warnings-as-errors --seed 987654
```

The workflow explicitly requires this49th isolated native profile. Local and
hosted execution, complete source matrices and completeness remain separate.
Only the two concrete primary properties can gain scoped implemented evidence;
nullable/empty/default, duplicate/update, deselection, skill invocation, other
roots/environments/transports/OS, real backend success and full lifecycle remain
unqualified. No aliases, wrappers or verified states follow from this journey.
A11 and source-unreachable emitters remain incomplete. No publication,
production credential, deployment or sibling-service change occurs.
