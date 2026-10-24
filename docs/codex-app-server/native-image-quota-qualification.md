# Native image quota failure and BEM backing history

Status: scoped implementation evidence, **not full compatibility**. Two actual
`rust-v0.163.0` cases exercise the image extension's HTTP429 classification,
typed quota failure, real BEM image promotion and persisted backing history.
The backend and account material are synthetic; there is no real image service,
account authorization, generated image, paid task or deployed behavior.

## Native trigger and independent oracles

The immutable source is `83086188ae0614bd882818ff1aa23f3194962012`; the official
Linux musl executable SHA256 is
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The new fixture composes the existing private user/network namespace, realtime
peer and confirmed owned-process lifecycle without changing those helpers.
Only loopback is available and neither IP family has a default route. Native
configuration uses file-only synthetic ChatGPT metadata, a separate explicit
synthetic provider bearer, the owned provider URLs, read-only sandbox and
on-request approval. The explicit provider bearer is also the supported native
realtime credential; synthetic ChatGPT-only auth is not claimed to provide it.

A fixed first Responses SSE result asks the stock image extension to generate
one image. The fixture admits exactly two Responses requests and one image
request. The image HTTP response is withheld until the client observes actual
native `item/started` and `bemItemPromoted` notifications. The latter references
the original thread, turn and backing image ID with `wholeItem` presentation.
Only then does an explicit fixture control release HTTP429. One case contains
the prescribed reset timestamp `1786150800`; the other omits both reset sources
and requires an explicitly present `resetsAt:null`.

Complete native started/completed image maps, original IDs, failed status,
revised prompt, empty result, null transparency and typed
`usageLimitExceeded/limitId:image_gen` are asserted. A fixed assistant result
then completes the ordinary turn successfully: image-tool failure and turn
failure are distinct. There is exactly one BEM promotion across image start and
completion. No approval, command, extra model/image request or saved artifact
occurs. The workspace remains empty.

`thread/read` provides a native persistence barrier. The tests independently
prescribe the full user/image/assistant item sequence and realtime facts, check
the complete timeline, positions, turn timestamps and backing items, and query
`thread/items/read` directly. After closing the borrowed client, the native
server remains alive. An explicit owned restart confirms the old PID is gone;
a distinct client then reads identical unloaded timeline/backing history without
another execution. Explicit close and guardian teardown confirm all owned
native/controller/namespace PIDs are gone before disposable successful roots
are removed. No historical or platform database is touched.

Pinned source corroboration:

- [Official quota test](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/tests/suite/v2/imagegen_extension.rs#L586): real image failure recipe and history; provider setup at line1150.
- [Image tool](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/ext/image-generation/src/tool.rs#L150): start/completion and quota mapping, including optional resets at line261.
- [HTTP error mapping](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/codex-api/src/api_bridge.rs#L187): typed usage-limit error requires the actual backend classification.
- [BEM presentation](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/realtime_history/presentation.rs#L44): image extension promotion on observed lifecycle events; backing identity deduplication is in the adjacent realtime history implementation.

## Retained failed attempt and bounded correction

The first owning run retains **31 tests / 2 failures**, both new image cases,
in `/tmp/samgita-native-command-null-image-boundaries-20261024/`. Its two roots
`/tmp/samgita-imagegen-failure-oCEc1pj2KgPg` and
`/tmp/samgita-imagegen-failure-zUKIsCoDnCXQ` preserve rejected startup GETs,
one admitted Responses POST, zero decoded model requests, a UTF8 byte error and
the native internal-server-error turn. They establish failure before image
quota handling. They do not capture the old Content-Encoding or raw body.

Pinned production source enables zstd for this ChatGPT/OpenAI combination by
default (`features/src/lib.rs:1424`, `core/src/client.rs:1727` and
`http-client/src/request.rs:196`). Compression is a source-supported diagnosis,
not a directly captured old-header claim. The correction uses the same supported
`enable_request_compression=false` setting as the official local ChatGPT test
at `app-server/tests/suite/v2/turn_start.rs:676`. New HTTP admission journals and
asserts absent/identity encoding before decoding bounded JSON. No compressor,
dependency, native patch or provider-identity change is introduced.

The peer now admits only the three source-defined startup GETs:
`/api/codex/accounts/check`, `/api/codex/settings/user` and
`/api/codex/config/bundle`. They return fixed single-account HTTPS `.invalid`
routing metadata, disabled attribution and an empty bundle. The invalid origin
is never an execution destination; the explicit bearer retains the owned
provider path. Analytics is disabled through its supported configuration.
Unexpected routes, request budgets and image failures still fail explicitly.
The original item/promotion deadlines and assertions are unchanged. This is a
new fixture prerequisite correction, not a production driver repair.

## Reproducible verification and limits

The serialized retained runner is:

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-native-command-null-image-boundaries-v2-20261024.py
```

Its results and complete logs are in the matching `/tmp` directory. Driver
compile and scoped format checks pass; root strict Credo reports **412 files,
no issues**. Both seeds `501432` and `987654` run the five complete owning files:
**31/0**, no exclusions, 38.1/38.6 seconds reported by ExUnit. The final guard
checks tracked and new source files. The two quota cases are also a required
explicit isolated hosted profile; adding the step is not evidence that hosted
execution has passed on this new source.

| File | Final SHA256 |
| --- | --- |
| `native_imagegen_failure_profile.exs` | d37d7de4519fa166541077bd234e92195b6a16d6d84a0bf605403af6ae17bb3f |
| `isolated_imagegen_failure_fixture.py` | 0a753f55b0350c698f0ef0b919922c515345ad4a9a45dde565f26c468e89bcda |

Only directly asserted, physically indexed image failure/item owners gain
scoped implemented evidence: **31 owners**, sixteen under ServerNotification
and fifteen under ThreadItemsReadResponse. Each includes its canonical subtree
hash and exact owning assertion/call references in the manifest. These cover
the selected quota failure, image branch/fields and non-null failure reference;
only the notification owner gains its positively emitted started-failure null.
No equal-hash transfer, savedPath null inference,
whole ThreadItem union, uncalled response owner or fully verified promotion is
allowed. Actual read/timeline equality corroborates this lifecycle without
creating duplicate canonical contract owners. Successful image generation,
other image errors, compression and analytics delivery remain outside this
profile. A11, source-unreachable legacy paths, external accounts/OS profiles,
the retained aggregate failure and final-source complete checks remain open.
No release, publication or deployment occurs.
