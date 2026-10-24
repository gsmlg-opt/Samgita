# Native generated-image result, artifact and cold history

Status: scoped implementation evidence. Four success cases and the two retained
quota regressions pass **6/0** at seeds `501432` and `987654`, with the official
`rust-v0.163.0` executable. The synthetic backend returns a fixed official test
PNG; this is not real image generation, real account authentication or full
provider integration.

The immutable source is `83086188ae0614bd882818ff1aa23f3194962012`; the Linux
musl executable SHA256 is
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The success fixture subclasses the [quota fixture](native-image-quota-qualification.md)
and retains its private network namespace, fixed file-only synthetic account,
explicit synthetic provider bearer, HTTP admission, supported compression-off
configuration and confirmed process guardian. Shared helpers are unchanged.
No app-server response or notification is synthesized.

## Independent result and persistence oracles

Each background result (`opaque` and `transparent`) runs with both legacy and
paginated durable history. The fixed model call always requests transparency.
The actual image item's Boolean must follow the HTTP **response** background:
false for opaque, true for transparent. It cannot merely echo the request.
The image response remains withheld until actual `item/started` is observed,
the one image request is journaled and the independently computed artifact path
is absent. Only explicit fixture control releases HTTP200.

The complete started/completed image maps and user/assistant maps are prescribed
before reading native output. The completed image has the original call ID,
completed status, exact revised prompt/base64, response-derived Boolean, explicit
failure null and exact saved path. Internal image request/generation analytics
IDs are absent. Only the first returned data entry is used. The artifact is a
regular file under `<CODEX_HOME>/generated_images/<thread>/<call>.png`, with
exactly the official 70 bytes and SHA256
`4ff6ab670a58c14270e034e2090d9a432caa263a14e0a25785386b0c12f880b5`.
No symlink, extra generated file or workspace file is permitted.

The second model request must contain exactly the high-detail inline PNG and
the independently computed full native saved-path hint, bounded to1024 bytes.
There is no legacy developer-message hint. The image HTTP request has the exact
fixed body, original turn header and `chatgpt_cca` originator. Exactly two
Responses POSTs and one image POST occur; there is no realtime handshake,
approval, shell/tool execution, retry or extra generation.

Warm native `thread/read` verifies the complete persisted turn, exact image
fields, content, timestamps and duration. Paginated cases additionally compare
the entire prescribed timeline and directly read all backing items. Closing the
borrowed client leaves the native server alive; an explicit owned restart reaps
the old PID. The new client starts unloaded, reads the same complete turn and
paginated history without loading execution, and preserves rollout bytes and
artifact bytes. Request budgets remain unchanged. Explicit close and teardown
prove all owned native/controller/namespace PIDs are gone before successful
disposable roots are removed. No Samgita database or historical task is changed.

The same tiny PNG is used for both backgrounds. The test proves reported native
metadata and saved bytes, not alpha-channel transparency or model quality.
Image edits, code-mode generation, live services, resume/reconnect execution,
other image errors, compression-enabled requests and analytics delivery are not
qualified by this profile.

## First failure and source-supported legacy identity correction

The first run in `/tmp/samgita-native-image-success-20261024/` retains **6/2**:
only legacy warm full-history equality failed. The native response was not
captured by its combined Boolean assertion. Failure roots
`/tmp/samgita-img-ok-W6UG6dNS6Lk9` and `/tmp/samgita-img-ok-obEEid5SLWyn`
retain the complete owned rollouts, HTTP journals and confirmed close evidence.
They contain exactly one user event, one image completion and one assistant
event, with no intervening ID-allocating event.

Pinned legacy history reconstruction assigns sequential `item-1`/`item-2` IDs
to those user/assistant events. Its image completion copies the original call ID
and every image field without consuming that counter. Live notifications retain
their own UUID/fixed model message ID. The original draft incorrectly equated
the two history modes. The correction prescribes only these two legacy message
IDs from source; the fully checked image map is identical. Live maps, paginated
full equality, cold full-turn equality, deadlines and cleanup remain unchanged.
No field is dropped, no actual response supplies an expected value, and no
production driver or upstream implementation is changed.

Exact pinned source anchors:

- [Official image success test](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/tests/suite/v2/imagegen_extension.rs#L42): exact PNG, mismatched request/result background, request headers, saved artifact and follow-on model input.
- [Native image tool](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/ext/image-generation/src/tool.rs#L183): response Boolean, first entry, save-before-completion and model input at line657.
- [Artifact path/hint](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/ext/image-generation/src/artifact.rs#L9): exact path and bounded hint; app-server `extensions.rs:101` supplies CODEX_HOME.
- [Legacy message projection](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/thread_history.rs#L504): sequential user/assistant IDs, image copy at line912 and counter at line1537. Native thread reads select the builder at `thread_processor.rs:3056,3164`.

## Reproducible checks and qualification boundary

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-native-image-success-v2-20261024.py
```

The matching directory retains full commands, source hashes and terminal logs.
Driver compile/scoped format and root strict Credo (**414 files**) pass. Each
native repeat reports **6/0**, no exclusions, 19.2 seconds. The final executable
source guard matches. The original **6/2** result remains separate. Hosted and
complete final-source matrix checks must run again; this profile's added required
workflow step is not a hosted success claim.

| File | Final SHA256 |
| --- | --- |
| `native_imagegen_success_profile.exs` | 634cc89a3aefaecba05e86ce3859eab4ab926b49f06955b0720007ae9b46fb93 |
| `isolated_imagegen_success_fixture.py` | 452859dc08c1949c87a7188d7e3541b5b86d9d08d491cdea431dc95fd2dee42a |

Only actual notification and directly called backing-item owners gain evidence.
Five missing owners become implemented: the saved-path field/non-null branch
for each physical owner and the directly read completed-item failure null.
Nineteen existing image rows receive supplemental success evidence. Every
selection retains its own canonical hash and direct assertions in the manifest.
Positive savedPath does not qualify an explicit null; omitted started savedPath
is not null evidence. No same-hash transfer, uncalled owner, whole union or fully
verified promotion is inferred. A11, source-unreachable legacy paths, real
accounts/backends, other OS profiles, the retained aggregate failure and full
compatibility remain incomplete. No release, publication or deployment occurs.
