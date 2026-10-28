# Ordinary app-list context and remote skill reads

Both cases use stock Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux-musl binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The app-server is real; only its owned directory/MCP discovery or skill-content
HTTP dependencies are fixtures. No real account/service, paid task or other
repository is used. This unit follows pushed share/save checkpoint `f4cb68b`.

## Loaded-thread context on app/list

A real `thread/start` creates one loaded thread without starting a turn. Its
returned ID must appear in `thread/loaded/list` and original `thread/started`
bytes. The case sends `app/list` first with that exact string as `threadId`,
then with explicit JSON null on the same method. Thread/global feature and
config settings stay the same. Native responses and genuine updates retain
literal Alpha/Beta/Gamma id/name order. Exactly two directory GETs across both
calls prove the observed cache reuse; MCP discovery methods remain bounded,
with no model/tool request or workspace change.

The pinned [processor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/apps_processor.rs#L55)
looks up a supplied loaded thread and uses its config snapshot's cwd. The
[loaded-thread lookup](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/apps_processor.rs#L333)
is genuinely exercised; this same-config success does not qualify precedence
between different snapshots/configs, missing IDs or feature/access outcomes.

Only physical owner **3328**, `AppsListParams.threadId`, gains new implemented
evidence. Whole mixed `AppInfo` arrays, owners3329/3317, remain missing: only
id/name scalars are selected. Raw correspondence preserves other fields as
opaque data without semantically validating policy/default fields. The case
reuses the unchanged reviewed ordinary catalog fixture, with no new dependency.

## Direct plugin/skill/read content

Two explicit native requests use fixed ordinary marketplace/plugin/skill
identifiers. Each causes a real direct GET at
`/backend-api/ps/plugins/plugins~Plugin_owned_skill/skills/notes`. The dependency
first returns independently literal Unicode skill text, then explicit null.
Exact native results must be `contents: <literal>` and `contents: null`.
The journal independently binds route/query/order, complete response JSON and
byte size. Exactly two fetches establish the native read/projection; the helper
never emits an app-server frame or interprets the document as instructions.

The [native handler](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/plugins.rs#L1225)
reloads the owned config and calls the [remote reader](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core-plugins/src/remote.rs#L1399).
It requires matching identifiers and projects `skill_md_contents`; it does not
need a bundle, installation, reconciliation, TLS listener, model turn or skill
execution. The dedicated helper imports only reviewed inert configure/close
setup, replaces every HTTP handler and exposes one synchronous loopback listener.

Only missing physical root77 owners **1483–1487** gain implemented credit.
Standalone ordinary fields/results already implemented receive no new state
credit. No aliases, unobserved values or complete method claim follow.

## Common evidence and verification limits

Original native outgoing/incoming bytes, JSON/Wire decoding and Session results
must agree, with integer `-1` distinct from string `"-1"`. Exact inventories
require eight correlated exchanges for app context and six for skill reads.
Native/helper owner completion, closed Ports and absent owned PIDs preserve the
earlier cleanup repair, including failure callbacks. Frozen inputs, empty model
journals/workspaces and no turn/item execution remain required.

Both launches use fixed YOLO `approval_policy="never"` and
`sandbox_mode="danger-full-access"`. Skill reads initialize with plugins disabled
in owned TOML and explicitly enable them before the calls; this does not qualify
enabled-at-startup/default behavior. No security, permission, authentication,
authorization, approval, TLS or header tests run. Existing mixed profiles are
never invoked. Each case stays60seconds, RPCs/sockets5seconds, owner-close1second.
App capture is512frames/2MiB; skill capture128frames/1MiB; individual messages
128KiB. Dependency counts, bodies and journals remain explicitly bounded.

Eight complete production/type files match the official source archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
All six physical node hashes match; official skill root42 equals generated
experimental root77 selected by method, without assuming equal array indices.
Source binding `/tmp/samgita-app-context-skill-read-source-binding-20261028.json`
has SHA256 `2bcafd541f629d00ead82cc27518d2ba935660d50b40961bc7be72a9266b6583`.

## Focused qualification

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-ordinary-app-context-skill-read-focused-20261028.py
```

Both new cases pass **2/0 at seeds501432 and987654**, on the first run at each
seed. Formatting, full strict Credo across614sources and independent complete
formatted-source review pass. No runtime repair, timeout increase, retry,
removed assertion or process-owner change is needed.

| Artifact | SHA256 |
| --- | --- |
| App-context test | `8cbda2d229e6350d88545c3ee9368fd89d5e4ce00ebfb8f24e7437d64f33a88a` |
| Skill-read test | `42523a9ea23245b1baab0bc20c91f0e5de8d902d25c57c4b029b21492ea8422d` |
| Skill dependency | `53d0a0812d44198b11edefe8faf4524e24a50136c3942e1d0ca05e7e51acb2d2` |
| Formatted-source review | `afcc884d3c33c5f2bb3a532cb7abf4ffbb5e800a58dd38d35231e053cfb97af0` |
| Focused seed501432 log | `07e414deb3a095f33f500448274ec620e1ab5d7dcc6b8ff32527e98077a9b0e4` |
| Focused seed987654 log | `d1a9193c23ec2a05f51322b8040055d64ab5398b99f7632dd3dce8adf9e63274` |

The ledger now contains **5,614 implemented / 871 missing / 136 blocked**
contracts and **462 implemented / 12 missing / 11 blocked** requirements,
zero globally verified. Final combined-source functional qualification is
recorded below. Required prohibited/broad/hosted gates, A11, unavailable native emitters,
real external/OS success, complete compatibility and release remain incomplete.
No package is published, tagged, released or deployed.

Rollback removes the two new tests, skill dependency and selector arguments,
restores six physical rows/four supplemental annotations and the prior reviewed
fingerprint. It requires no platform migration, record deletion, remote change
or replay. The existing catalog helper and all earlier assertions stay exact.

## Final combined-source functional qualification

All **14 reviewed functional steps** pass on the frozen integrated source:

```sh
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py \
  --output /tmp/samgita-ordinary-app-context-skill-read-final-20261028
python3 -B /tmp/samgita-app-context-skill-read-final-binding-20261028.py
```

The **83 files / 147 actual-native cases** pass at seeds501432 and987654,
in257.7/260.0seconds. Three selected WebSocket overflow/replay cases pass at
455834,501432,987654; thirteen other mixed-file cases remain excluded. The
outside-umbrella consumer passes **1/0**, seed76234, with real pinned Codex.
Driver/root warnings-as-errors compile and formatting, inventory consistency,
strict Credo across614sources, Dialyzer and assets all pass. No prohibited test,
audit, broad suite or hosted workflow runs; database recovery is not rerun.

All **1,712** guarded sources match before/after and final binding. Three
test/helper files are added. Only the manifest and selector change among prior
sources; **1,707** other hashes are identical. Every prior command stays exact
after removing the two new file arguments. Independent source review and final
binding confirm only six physical state changes and four supplemental unchanged
requirements. No assertion, deadline, cleanup behavior or old fixture changes.

| Final artifact | SHA256 |
| --- | --- |
| Evidence directory `results.json` | `31510e7872c72e40d08814eee8da543fe000fe8d4d4e2d0ed3faebd57447c364` |
| Evidence directory `source.json` | `d3ce808cd9d11f47a5aa25fca995f5ee681712c3e47326e7f481b3f76ec4e74b` |
| Final binding JSON | `168c7f6312426d3d7b54fed5c23d6bab4f3f3139aaaa0d9c74ac96637ea48348` |
| Manifest/selector raw diff | `d5a6f360f779379c3c3e406b197774e06b395de0fb42c1c6d68c592ae7b1d3fd` |
| Final integration review | `2760b674c8a42284571dadf587e6dc91cc5b658992cb62bb5834a4fe99a817bf` |
| Reviewed source fingerprint | `fdde4fcf262dd05f0dfb82feb10d3b3e0f635bc4ae3595607696f8e3cfc0c5c0` |

The complete goal stays active. Next ordinary candidates are environment
required-skills object/null replacement with actual discovery/inference and
feedback tags/thread context through the pin's own loopback proxy test setup.
Their source investigations and drafts remain unrun outside the repository;
no runtime, compatibility or permission claim follows from those candidates.
Full compatibility, prohibited/broad/hosted gates, A11, unavailable emitters/
external/OS success, publication, release and deployment remain incomplete.
