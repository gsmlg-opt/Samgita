# Ordinary installed-app snapshots and populated catalog arrays

This unit follows `cef1bf3` on `main`, retaining official Codex `rust-v0.163.0`,
commit `83086188ae0614bd882818ff1aa23f3194962012` and binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Every app-server response and notification comes from that executable. An owned
loopback dependency supplies inert MCP discovery and directory metadata, never
native app-server messages or installed snapshots. No model, tool, thread or
turn execution is requested.

Fixed YOLO, synthetic identity and required backend DTOs are launch scaffolding.
The test asserts no credential, authentication, authorization, approval, policy,
sandbox, header or TLS outcome. Native callable/enabled/access fields stay outside
semantic projections and owner credit. Existing prohibited tests are preserved
and unrun. No broad suite, audit or hosted workflow runs.

## Native refresh and cache behavior

Exactly five actual `app/installed` requests use omitted,true,false,true,false
`forceRefresh`. A fresh committed snapshot is empty. The first true refresh
discovers three tool descriptors for two connectors: duplicate alpha becomes one
installed identity, its padded Unicode runtime name is trimmed, and beta's
absent name becomes present null. An atomic backend-only generation change
does not touch native cache. The false read retains the first snapshot without
discovery; the second true refresh publishes changed alpha and new gamma while
removing beta; the final false read preserves that second snapshot.

Two separate native `app/list` calls then merge runtime metadata with a populated
directory. Independent literal ID/name/description/logo projections include
canonical alpha/gamma descriptions and a directory-only delta. The second call
uses the committed caches without another tools/list or directory GET. Actual
`app/list/updated` frames are captured and validated separately: the first call
emits one or two updates, including the final populated projection; the second
emits one final update. Runtime-first interim arrays are bounded to owned IDs.
Identity sorting excludes access-derived presentation order. No notification is
manufactured from a response.

The final dependency inventory is exactly three MCP initialize/initialized
lifecycles, four original tools/list request/replies with generations1/2/2/2,
and one directory GET. Literal tools and descriptive native results provide
independent oracles in addition to request journals and response-sent barriers.
Those barriers establish emission; the native response projections establish
snapshot consumption. There is no tools/call route.

Exactly eleven outgoing native envelopes and ten correlated responses are
required. Integer3318 and string"3318" remain distinct. The experimental
ClientRequest document selects the unique app/installed member85, keeps its
original physical ID `$ref` and root definitions, and validates all five actual
captured IDs. Original sent/received bytes, strict identity matching and normal
Wire validation remain enabled.

## Failure diagnosis and supported corrections

The first run failed because the draft expected only method/params notification
keys. Pinned `outgoing_message.rs:904-908` always wraps native notifications with
emittedAtMs; `common.rs:2080-2094` defines it. The test now requires the exact
three-key envelope and a positive integer timestamp while retaining full original
bytes and data assertions. It does not discard the field or add an envelope-owner
promotion.

The next run reached final inventory and exposed a second draft assumption.
A diagnostic run preserved both count/method assertions and printed the actual
methods: remoteControl/status/changed plus two app/list/updated. Pinned
`app-server/src/lib.rs:1239-1251` sends the separate startup notification when
initialization completes. The corrected inventory requires exactly one startup
method, retains two or three application updates and rejects all other methods.
The startup status/policy payload is not asserted or given acceptance credit.
No timeout, capture bound, metadata oracle or process cleanup is weakened.

| Original evidence | SHA256 |
| --- | --- |
| First envelope failure, seed501432 | `82ce80210597b1fe41940ea1cf52e162d03b12a6bc104becd134f661434ad250` |
| Second inventory failure, seed501432 | `f21582c178f3a113a732a2098803e4e9c3f88762a2f3915f693972b0cdf97923` |
| Diagnostic original-method list | `a29b927c39fceac87c9b9729a96afd4c6cdc77920b572c44f28c70bed0151465` |
| Corrected focused seed501432 | `ad4911ab3a501c59ec0a680fd68d2e0ac26e87776c80a29f1b4d7084990716e5` |
| Corrected focused seed987654 | `ac8c6a6462d22ba2a8cd14e868343269469009a978bdf467813efc5f7d2f4513` |
| Final adopted source review | `06b98d7b1c149633ca1a539230c9ef425ceac4fcd0508117691940c5d1568306` |
| Helper | `56fe3f169dbefd4f323c99aae07fe92b7ec4ce53d0b39934c95e94d11667f97f` |
| Corrected formatted native test | `1edf3c6c543e1c4ddbdfb19bf5ad336c33aa0705d690401c94d4102375795f93` |

Corrected focused checks pass **1/0 twice**, at501432 and987654; strict Credo
passes619 source files. Original failed logs remain under the first three
`/tmp/samgita-ordinary-installed-apps-*-20261028` evidence directories.

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-ordinary-installed-apps-focused-20261028.py
python3 -B /tmp/samgita-ordinary-installed-apps-source-binding-20261028.py
```

The source binding JSON, SHA256
`84e25b2a678f32afbfcf510deb348206fb921d50820a0757375d315ff89f1a78`,
compares19 complete upstream sources/schemas against the immutable source archive
and binds seven exact physical nodes. The experimental ClientRequest JSON matches
the existing pinned-generated copy and provenance, not a new generation run or
an invented archive member. Archive SHA256 remains
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.

## Bounds, ownership and limited credit

Existing bounds remain helper50s, case60s, operation/observation5s, socket3s,
HTTP64, journal64 events/1MiB, MCP input8KiB, response128KiB and capture64
frames/1MiB. Session buffers remain128 events/1MiB. Inputs, configuration,
helpers and schemas retain exact byte snapshots; workspace, model journal,
loaded threads, uncertain operations and rollouts remain empty. Native and
helper close require the original owned-process completion, Port/PID absence
and fallback cleanup before final root removal.

Only physical owners1529/3317/3318/3322/3323/3324/3329 change missing→implemented.
The five existing app/installed, app/list and app/list/updated requirements gain
supplemental evidence with unchanged states. No alias, neighboring field,
computed policy outcome, complete method or other deployment profile inherits
credit. Contracts: **5,642 implemented /843 missing /136 blocked**; requirements
**462 implemented /12 missing /11 blocked**, zero globally verified.

## Final combined-source functional qualification

```sh
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py \
  --output /tmp/samgita-ordinary-installed-apps-final-20261028
python3 -B /tmp/samgita-ordinary-installed-apps-final-binding-20261028.py
```

All **14 reviewed functional steps pass** against identical before/after/live
source. The runner adds only this single native test argument and count153;
removing that argument reproduces every prior command exactly.

| Check | Actual result |
| --- | --- |
| WebSocket overflow/replay selection | Three cases at455834,501432,987654; each16 tests,0 failures,13 excluded |
| Independent driver,88 selected files | **153/0 twice**, seed501432/987654;261.0/261.8s ExUnit time |
| Outside-umbrella native consumer | **1/0**, seed481203; no Repo/Phoenix/platform configuration |
| Static/build | Driver/root compile and format, inventory consistency, strict Credo619 files, Dialyzer and assets pass |
| Source binding | **1,722** hashes identical; **1,718** other prior sources unchanged |

Final fingerprint:
`0666b112c56185772446af67dd46d8c2051bc825484c9aed713fb2953b363f67`.
The binding limits manifest changes to these seven physical promotions and five
already-implemented requirement supplements, preserving every other state.

| Final artifact | SHA256 |
| --- | --- |
| Binding JSON | `3dd28ea4a72bea78c0c86697fb61ae2c59be98d817d614578d5188278a27920e` |
| results.json | `38debaf799a743be24cec3695b6aef52614193be5ea19860294badbcf87d1cf2` |
| source.json | `ec507e14d0574b3032543febe2b4c9a0179a7623ca2f22f0af60972499a1ccfd` |

Full compatibility, prohibited/broad/hosted gates, A11, unavailable emitters,
external services/other OS success, the native timestamp cursor defect, release,
publication and deployment remain incomplete. No database recovery rerun or
production migration occurs. Rollback removes this helper/test/selection and
reverts only the seven promotions/five supplemental requirements and this unit's
documentation; there is no platform or persisted-data change.
