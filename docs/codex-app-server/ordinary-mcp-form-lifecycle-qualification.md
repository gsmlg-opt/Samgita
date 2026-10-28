# Ordinary MCP form answer and interruption

V539 uses stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
One new standalone case and one bounded local dependency exercise ordinary
display-label input. The actual pinned app-server emits every protocol frame;
the fixture supplies only a local Responses backend and an owned stdio MCP peer.
No model service, platform task, credential or permission flow is exercised.

## Native data and cancellation flow

An explicitly User-sourced root thread advertises standard-form input under
fixed YOLO. A real MCP tool asks for a nonempty label form. The consumer's exact
Unicode answer and ordinary metadata agree across original response bytes,
independent peer receipt, the next provider tool-result input, native MCP item
completion and final assistant output. The native resolution retires the handle
and preserves the response digest.

A second form receives no consumer answer. Actual `turn/interrupt` causes both
interrupted completion and `serverRequest/resolved`; the independent peer then
receives exactly `action:cancel` and writes its terminal tool result. The test
requires both native events without imposing their relative order. The first
answered outcome remains exact; no result is invented for the unanswered form.
A late local handle produces no bytes. Three provider requests retain exact
thread/turn correlation through shutdown.

The ledger contains **eleven selected original frames**: thread start, two turn
starts, one ordinary form reply and interrupt; two requests, two resolutions and
two turn completions. Each original frame decodes to the delivered value. Native,
MCP peer and provider PIDs/Ports/owners must complete before temporary-root cleanup.
The workspace stays empty. Only physical ordinary Form owner **1922** gains scoped
implemented evidence; existing request/response entries186/309 receive supplemental
behavior evidence. Other elicitation modes, nested aliases and all-profile/global
verification receive none.

## Reproduced failure and supported repair

The first actual run fails **1/1**, seed501432, after21.2seconds at the first
form's unchanged20-second observable deadline. Its original log is preserved.
Source investigation establishes a missing required setup condition: omitted
threadSource stays None through the typed request and StartThreadOptions;
the ordinary standard-form route activates only for a root Some(User).
Advertising the extension alone does not satisfy that condition.

The repair supplies `threadSource:"user"` and requires the native start response
to confirm it. Nine whole official files/sixteen excerpts trace the omission,
forwarding, exact activation predicate and returned source. The helper, fixed
YOLO, deadlines, eleven-frame inventory and all data/cancellation/cleanup oracles
remain unchanged. First-failure journals were removed by registered cleanup,
so no claim about their unobserved contents is made.

A bounded failure-only diagnostic now records ordinary event, provider-tool and
peer evidence before cleanup. Independent review caught that a diagnostic error
could replace the original timeout assertion. A narrow try/after makes the
original assertion unconditional on that failure path; no diagnostic can turn
the deadline green or extend waiting. Original and corrected reviews are retained.

Strict Credo then finds only excessive nesting in the new capture callback.
Extracting its message-recording lambda preserves filtering, order, capacity and
error propagation. No check is disabled. The affected case passes both seeds
again after this test-only refactor; its logs match the preceding successful
repair runs exactly.

## Immutable source, scope and bounds

Sixteen original whole source files/thirty-two excerpts match the archive and
trace ordinary form emission, callback cancellation, listener resolution,
active/runtime-router fallback and actual peer encoding. The retained
experimental Form `/oneOf/1` equals archive `/oneOf/0`, canonically
`50b970d16b1b18f7b45c764d7bc245ba4589b275c73dc62ae60c467ec8b3aa5f`.
Retained and archive roots have five and four variants respectively; whole-root
equality is explicitly false. No device or other branch is inferred from this
cross-index comparison. The observed peer protocol is MCP `2025-06-18`.

The helper overrides both generic config and item dispatch and enters no mixed
scenario/startup self-test. TurnFixture is used only for the model-catalog writer;
thread startup is direct. Capture is32selectedframes/64KiB each/1MiB total,
events256/1MiB, peer journal64rows/1MiB, failure diagnostics3MiB, case60seconds,
observable deadlines20seconds and RPCs5seconds. Journal snapshots replace
atomically. There are no sleep increases, retries or removed assertions.

## Focused native evidence

The repaired and then refactored case passes **1/0 at seeds501432 and987654**,
1.5seconds in the first repaired run:

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-v539-refactor-focused.py
```

That recipe runs `mix test test/native_ordinary_mcp_form_lifecycle_test.exs --warnings-as-errors --seed <seed>`
from the independent driver. Final combined-source qualification follows below.

| Artifact | SHA256 |
| --- | --- |
| Original source evidence | `97353873d5f66131ce9660bc58a5c41c17b3173b0dab17a7b1db4a96633e922d` |
| Original independent review | `0ff58dd60e0cebd22dcae5130c839069aafc43f31cef30d0fbb61250b3a12035` |
| First native failure | `8c62ffa7873ddca5a283b18f05f52903de3840fb587675fc6bfb94e424dad6b1` |
| `/tmp/samgita-v539-repair1-source-evidence.json` | `f0daccdb56dce21762ba7a86a9108dded88baab9e7d0edd95590478c0bf5f6e1` |
| Diagnostic NEEDS_REVISION review | `73c69c981b685140902eb9a803f32e29097b84a3cb557e643536d72327484e54` |
| Corrected diagnostic review | `d2f5ad104ed19a45069f4528a7fea6795dcae6fa16410bf05de510d6d2f26ca3` |
| Failed strict Credo preflight | `59bb007cf9cb7444a8e15a049fc998384929b37deea94a84fdfbc5cad23e7252` |
| Final formatted test | `a080110cd4be5f81e84253146a31de95e6dd0117f83761b49e26de96b472d3e0` |
| Helper | `2f0eb4e91e42bd1c7d665c559ff4c5d39af61ed6a5d0d30f0bb8e3d3bcc142f3` |
| `/tmp/samgita-v539-refactor-focused-501432.log` | `ad4911ab3a501c59ec0a680fd68d2e0ac26e87776c80a29f1b4d7084990716e5` |
| `/tmp/samgita-v539-refactor-focused-987654.log` | `ac8c6a6462d22ba2a8cd14e868343269469009a978bdf467813efc5f7d2f4513` |

## Final combined-source functional qualification

V539 and V540 pass all **14 reviewed steps** under Devenv Elixir 1.18.5 /
OTP 27.3.4.17:

```sh
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py \
  --output /tmp/samgita-ordinary-v539-v540-final
python3 -B /tmp/samgita-v539-v540-final-bind.py
```

The selection contains **77 files / 140 actual-native cases**, passing at both
501432 and 987654; selected WebSocket overflow/replay cases pass 455834, 501432
and 987654. The outside-umbrella consumer passes **1/0** against the immutable
binary. Driver/root warnings-as-errors compile, formatting, strict Credo across
608 sources, Dialyzer and assets all pass. No broad suite, security/permission
test, audit or hosted workflow runs.

All **1,701** guarded sources match before/after and final binding. Exactly
three test/helper sources are added; only the manifest and reviewed selector
change among the previous sources. All **1,696** other prior hashes and every
previous command remain exact after removing the two added test arguments.
Twenty-eight unique complete official source files match the pinned archive.
Only schema owners 217/1922 move missing→implemented; four requirement entries
gain supplemental evidence without changing state. No globally verified credit.

| Final artifact | SHA256 |
| --- | --- |
| `results.json` in the evidence directory | `859c2745310b44241a19cea66a5730ddde06e4af2cba03be4b7dfc8c044b8607` |
| `source.json` in the evidence directory | `f445f4f911fb64e5e23aa578f056f11cf0a7ebf61be3a749e4f94cacb4a9eb5f` |
| `/tmp/samgita-v539-v540-final-binding.json` | `5e63765a835d85ba1a594302b32071c680529bf59eee144d1e13b9768bfc3006` |
| Reviewed source fingerprint | `ae6fe55db146c5c1fff6b37cd47fdac1b55ccb6620f12762aee76d1b3517b724` |

The original native failure, diagnostic correction and static failure remain
recorded above. The next ordinary form-values draft is still unrun and earns
no credit from this batch. A11, prohibited/hosted checks, unavailable emitters,
external/OS profiles and the complete compatibility/release gates stay open.

## Rollback and limits

Rollback removes this case/helper, restores owner1922 and the two supplemental
entry records, and restores the reviewed selector/fingerprint. Historical data,
platform state, process-owner fixes and previous evidence remain intact. With
V540, counts are **5,579 implemented / 912 missing / 130 blocked** contracts;
requirements **462 implemented / 12 missing / 11 blocked**, zero globally verified.
Other MCP versions/modes, real external services, OS/transports and full
compatibility remain unqualified. Prohibited tests/audits and hosted workflows
remain unrun; A11, unavailable emitters, release/publication/deployment stay open.
