# Native turn inputs and parameters

The initial checkpoint adds 23 actual-binary scenarios at Samgita `73258c5`, bringing
the independent driver's suite to 125 tests. The follow-up below adds standalone
tool-output/settings (`50abfe3`) and controlled MCP-startup (`9791d54`) evidence.
These changes affect
tests and documentation; the native schema, driver and platform runtime are
unchanged. Full compatibility remains incomplete. The method and field contracts
stay `missing` until all their
required behavior and deployment profiles have evidence.

The immutable reference remains Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux musl executable SHA-256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Every scenario drives that real app-server through the reusable Session's stdio
transport. The Responses backend is the existing deterministic loopback model
fixture. It captures what Codex sends to a model; it does not perform inference,
recognize media or emulate the app-server.

## Input behavior established

| Native input | Actual behavior checked | Limits |
| --- | --- | --- |
| `text` | UTF-8 text `é🙂x`, byte ranges, omitted/null/explicit placeholders, client message ID and both user-item lifecycle events; close the owned process, start another, then resume/read the persisted thread without another model request | Stable and experimental negotiation; no invented range/overlap rejection rule |
| `image` with `url` | Omitted/null detail defaults, `auto`/`high`, original-detail normalization, explicit low-detail omission, mixed-case HTTP(S) rejection before model dispatch; follow-up below adds real resizing and data-URI preparation | Synthetic PNG inputs; no GiB limit or visual-understanding claim |
| `image` with `fileId` | Opaque reference and its detail reach the captured provider request; original reference remains in both item events | No upload, provider-side file lookup or access authorization was exercised |
| `localImage` | Local file and original path, detail defaults and capability-dependent `original`, low-detail omission, missing/corrupt-file fallback | Synthetic disposable PNG files; no remote filesystem or other-OS qualification |
| `audio` | Inline `audio/x-wav` canonicalizes to `audio/wav`; an HTTP URI produces the pinned preprocessing placeholder; original input remains in both item events | Synthetic audio-capable model metadata; arbitrary bytes establish construction rather than valid decoded audio |
| `localAudio` | `wav`, case-insensitive `MP3`, `m4a`, `webm`, `ogg` MIME/data-URI construction and path framing; missing and unsupported files produce defined text | No speech recognition or live provider acceptance |
| `skill` | Explicit discovered path injects a unique body once despite duplicate selection; disabled/unmatched explicit paths block fallback by name | The positive prompt contains no skill name, so its text cannot satisfy the assertion through plain-name selection; no dependencies/tools are installed |
| `mention` | Unknown synthetic `app://` and `plugin://` identities remain intact in both item events and add no model content; the follow-up qualifies exact `mcp://` startup selection | Enabled app/plugin routing and additional MCP exposure/permission profiles remain unqualified |

The wire spelling is `text_elements` with nested `byteRange`. Byte offsets refer
to UTF-8 bytes. Omitted text elements normalize to an empty array in upstream
events. Omitted/null placeholders normalize to null. The driver sends the
original request unchanged; the assertions distinguish upstream output
normalization from client-side data loss. Invalid element containers, negative
or nonnumeric offsets and nonstring placeholders are rejected by the actual
server without a model request. These tests do not assert semantic validation
of offsets that have valid Rust types.

Image detail has an observable difference between schema and execution. The
schema accepts `low`, but the pinned inline/local image preparation path emits
`image content omitted because detail 'low' is not supported; use 'high', 'original', or 'auto'`.
Opaque file references bypass this inline preparation and preserve their detail.
`original` is retained for a model advertising `supports_image_detail_original`;
otherwise it normalizes to `high`. A corrupt local image uses deferred preparation
and produces `image content omitted because it could not be processed`.

Likewise, default fallback model metadata advertises text/image input only.
Audio-capable metadata exercises actual audio forwarding; a separate test checks
that a model lacking audio support receives the unsupported-audio placeholder.
Neither that fallback nor a scripted assistant answer proves audio understanding.

## Turn parameters established

Six scenarios inspect real events and captured provider requests:

- `additionalContext` preserves untrusted text under the user role and application
  context under the developer role, without adding it to the original user item.
- Disabled experimental negotiation rejects `additionalContext` and
  `responsesapiClientMetadata` at the actual server before a turn/model request.
  Those negative calls deliberately use native wire-only validation to reach
  upstream rather than counting local schema rejection as server evidence.
- `responsesapiClientMetadata`, `turnTrigger`, `parentTurnId` and `rootTurnId`
  produce the JSON string under body `client_metadata["x-codex-turn-metadata"]`.
  Caller-supplied reserved keys cannot override authoritative thread/turn/causal
  IDs. A subsequent ordinary turn gets its own root ID.
- `serviceTierForTurn` overrides only one request. Sticky `serviceTier` survives
  omission and null per-turn override; null sticky tier clears it. `default`
  produces no provider service-tier field. This tests request construction, not
  actual backend allocation or billing.
- `outputSchema` becomes that turn's `text.format` JSON-schema configuration and
  is absent on the next plain turn. The backend's fixed text answer is not schema
  adherence evidence.
- `toolOutput` with nonempty `input`, and an empty tool name, fail explicitly
  before model dispatch. A following valid turn succeeds. Standalone output
  success and selected remaining variants are qualified below.

## Standalone tool output and settings follow-up

`tool_output_test.exs` adds ten scenarios, five under each experimental negotiation
profile. A fresh idle thread accepts `toolOutput` without a preceding tool call,
registered tool or pending approval. String and structured UTF-8 text, empty
string/array, omitted/null/value/empty namespace and omitted/false/true retention
all reach the actual server. Both native item events retain the generated item
ID, thread/turn association, name, namespace and output. They are
`functionCallOutput` items, rather than user messages. Provider requests preserve
these outputs and omit `call_id` and internal retention flags.

Read history preserves the native item before and after a confirmed owned-process
close, new process and explicit resume. Both ordinary and retained outputs are
stored. The synthetic rollout records `metadata.client_authored` for retained
outputs; that annotation does **not** prove survival through compaction. No actual
tool runs in these assistant-only cases. Omitted/null `toolOutput` with empty
`input` still requests ordinary inference. Malformed shapes fail actual native
deserialization; aggregate text over 1,048,576 Unicode characters returns native
`-32602` with `input_too_large`, maximum and actual character counts. Structured
HTTP(S) image references return `-32600` before model execution. Structured image
preparation is qualified below. The subsequent active-steering and compaction
sections add selected audio/encrypted-content and retention evidence; other
profiles remain incomplete.

`turn_overrides_test.exs` adds four scenarios. Successive requests demonstrate
sticky model, effort and summary settings; public null preserves those settings,
and `summary: "none"` omits the provider summary parameter. A collaboration mode's
model/effort override conflicting ordinary fields. Its null developer instructions
select the upstream preset; explicit and empty instructions preserve their exact
values in settings and model context. Each instruction profile uses a fresh thread:
old developer messages remain conversation history and cannot be treated as a
new settings leak. Disabled experimental negotiation rejects `environments`,
`runtimeWorkspaceRoots` and `permissions` before turn/model execution. An unknown
environment and conflicting permissions/sandbox fail explicitly; a later valid
turn succeeds. These are request/settings outcomes, not evidence of model reasoning
quality, remote environments or sandbox enforcement during command execution.

## Active-turn steering and structured output

Seven actual-binary cases in `native_turn_steering_test.exs` hold a turn at a real
`item/tool/call` and release it only through an explicit synthetic tool reply.
Accepted `turn/steer` text, untrusted/application context and metadata enter the
next captured provider request and the existing turn. Reserved causal IDs cannot
be spoofed. Started/completed item identity, one turn lifecycle and persisted
history survive confirmed process shutdown and cold resume.

Wrong active-turn IDs, empty input and oversized Unicode input fail without
merging rejected content, context or metadata. Idle steering cannot start a turn
or inference; empty/absent/null expected IDs and disabled experimental fields
retain actual upstream errors. Fresh-thread `thread/read(includeTurns: true)`
returns the pinned `list_turns is not supported yet` before the first turn. The
test therefore establishes no provider/start event, completes one valid turn,
then proves the history contains exactly that turn rather than assuming an
unsupported history operation succeeds.

Standalone `turn/start.toolOutput` also steers the pending turn. String and
structured text/image/audio/encrypted outputs retain item identity and opaque
encrypted content in native history and the next provider request. The audio
input is preserved under an audio-capable model; otherwise the pinned omission
placeholder is asserted. These are request preparation and lifecycle checks,
not actual media understanding or ciphertext interpretation. Both local runs
passed **7 tests**, seeds `455834` and `987654`.

## Compaction and retained outputs

Four actual-binary tests in `compaction_test.exs` exercise explicit
`thread/compact/start`. The empty RPC result acknowledges the request; correlated
`contextCompaction` item and turn events establish completion separately.
Invalid and unknown thread IDs fail before any turn or provider request.

A custom loopback Responses provider advertises remote compaction `v2`. Its
fixture returns an opaque synthetic compaction item only when the real Codex
request includes `compaction_trigger`, irrespective of request count. With
`retain_client_tool_outputs` enabled, a marked named output survives compaction,
confirmed owned-process close, fresh process/resume and a new turn unchanged;
an unmarked output is absent. With the feature disabled, even the marked output
is absent. The synthetic checkpoint survives cold resume in the next provider
request; internal retention flags never enter the provider payload.

The separate local-compaction route uses the configured summary prompt over
ordinary Responses input, emits the same correlated item lifecycle and puts its
summary into the next request without leaking the compaction prompt as ordinary
conversation input. These selected Linux/stdio checks passed **4 tests**, seed
`501432`. Two Python regressions cover actual HTTP fixture routing and its
existing one-argument item override contract. The backend supplies deterministic
data; it proves no summary quality or decryption.

Three further actual-binary cases in `compaction_retention_test.exs` qualify the
64,000-estimated-token shared retention budget from pinned
`core/src/compact_remote_v2.rs:87,606–702`. Each first proves complete, untruncated
outputs reached the actual compaction request. The model catalog permits a large
context and 1 MB per output so ingestion clipping cannot masquerade as retention.
The newest output survives whole; a middle output exceeding the remaining budget
stops the traversal, so an older output that would fit cannot backfill it. An
oversized newest output instead drops whole and prevents older backfill. A cold
process resume and next ordinary provider request prove the resulting history,
opaque checkpoint and absence of internal retention metadata.

The third case deliberately supplies an assistant item instead of a checkpoint.
The RPC acknowledges `{}` before the native asynchronous error and failed turn;
there is no completed compaction item or installed checkpoint. Ordinary turns
in the same process and after cold resume retain pre-failure history. This is
ordinary-turn recovery, not a successful compaction retry. All three passed at
seeds `501432` and `987654`. Log:
`/tmp/samgita-compaction-retention-validation.log`. An initial root-development
formatter command failed in cached dependency type checking before tests ran;
the independent package's test environment compiled and formatted successfully.

Automatic/background compaction, fork/prediction variants, interruption,
successful compaction retry and other transports/backends remain unqualified.

## Controlled MCP mention follow-up

`mcp_mention_test.exs` uses the same gated local stdio MCP service and synthetic
Direct-tool model profile in two fresh homes. Both wait for an initialize marker.
With ordinary text and no mention, a turn completes while initialization remains
held; the first provider tool catalog lacks `mcp__fixture`. Adding only a structured
mention with an unrelated display label and exact `mcp://fixture` path keeps model
requests empty beyond the configured 50 ms optional-startup grace. Releasing the
gate lets the first model request include its `confirm` tool. The real server
delivers startup status, original user mention and MCP item lifecycle, routes one
form elicitation for explicit synthetic acceptance, and returns its correlated
tool output. Local peer journals establish the actual call and elicitation reply.

The gate has an eight-second monotonic deadline; driver collection is bounded and
owned shutdown is asserted. The synthetic tool is read-only. A mention selects a
startup dependency: it does not grant permission, make other ready tools disappear,
or prove external MCP authentication. Deferred-tool discovery, app/plugin mentions,
permission rejection, reconnect and other transport profiles remain separate gaps.

## Image preparation and Unicode boundary follow-up

Eight additional actual-binary tests in `image_preparation_test.exs` exercise
inline image URLs, local PNG paths and structured `toolOutput.input_image`.
`ImageFixture` creates valid synthetic PNGs using zlib and CRC32 without an image
library dependency. Its checker validates complete fixture PNG chunk lengths,
CRCs, IDAT inflation, row lengths and every expected constant RGB/RGBA pixel
across filters 0–4, not only header dimensions. A ninth bounded checker test
rejects malformed CRCs, truncated/trailing data, duplicate IEND and valid-CRC
incorrect pixels. Both item lifecycle events retain the original native input;
each submission must append exactly one provider request, whose prepared content
is inspected separately from earlier captures.

| Input/profile | Captured provider outcome on all three input paths |
| --- | --- |
| Small `64×32` PNG, high | Original PNG bytes and dimensions preserved |
| `2048×2048`, high | Resized to `1600×1600` to meet the 2,500-patch budget, despite satisfying the dimension limit |
| `2048×2048`, supported original | Original bytes preserved at `2048×2048` |
| `3201×3201`, supported original | Resized to `3200×3200` for the 10,000-patch budget |
| `6401×100`, supported original | Resized to `6000×94` for the original-detail dimension limit |
| `2048×2048`, unsupported original | Original-budget pixels remain `2048×2048`, then model normalization changes the wire detail to high |

Structured omitted/null detail uses high preparation limits but retains an absent
provider detail field. This differs from user-image detail defaulting. Uppercase
data-URI components and an incorrect declared MIME normalize from actual PNG
bytes. Missing base64 framing, invalid base64, corrupt image bytes and low detail
produce the exact ordered upstream text placeholders while a following valid
image and surrounding text survive. Those URI cases cover inline and structured
output; the earlier tests cover corrupt/missing local files.

The text boundary test submits exactly 1,048,576 Unicode scalars, constructed
from combining characters so scalar, grapheme and byte counts differ. Both user
text and standalone tool output reach the provider unchanged at the limit. One
additional scalar returns the exact native `-32602` error and counts, before a
turn-start event or model request; the Session stays ready with no pending or
uncertain operation.

These tests establish request preparation, not model vision or tool execution.
The upstream 1 GiB direct/inline/tool-image sanity guard, image-count/memory limits,
`unified_image_budget`, resize notices, Responses Lite, other image formats,
orientation/color metadata and real visual inference remain unqualified. The
driver's 8 MiB message limit and model fixture's 4 MiB HTTP limit do not prove the
upstream image-byte boundary. The queued local-file metadata guard is separately
qualified below without reading a huge file.

## Image boundaries and queued local snapshots

Four cases in `image_limits_test.exs` extend actual Linux/stdio coverage:

- An unloaded persisted thread retains an ordinary queued submission. Queue add
  and update each reject a local image of **1 GiB + 1 byte** with the exact native
  `-32600` error, leaving that submission unchanged, starting no turn and issuing
  no additional provider request. The owned file is sparse; GNU `stat` checks
  its allocated blocks remain below 1 MiB before and after the RPCs.
- Across inline, local and structured tool output, `high` preserves exact
  `1600 x 1600` patch and `2048 x 32` dimension boundaries; `original` preserves
  `3200 x 3200` and `6000 x 32`. One pixel over each boundary resizes to the
  expected dimensions. Unchanged images retain exact bytes. Compressed fixture
  files remain below 100,000 bytes; provider/frame limits are unchanged.
- Empty/truncated PNGs and complete valid-CRC zero-dimension headers become
  processing placeholders on all three paths, preserving surrounding text and
  the valid image. Both native item lifecycle events retain original payloads
  and a common item ID, separately from provider-side normalization.

The sparse profile is deliberately confined to queue RPCs. Pinned
`protocol/src/local_media.rs:59-79` checks metadata before a bounded read;
`ext/queue/src/service.rs:519-526` invokes it. Direct local-image conversion at
`protocol/src/models.rs:2136-2158` calls `std::fs::read` before preparation.
Submitting the sparse file through direct `turn/start` would therefore be unsafe
and was never attempted. Inline/tool inputs above the image guard, direct-local
overflow, and exact-limit accepted reads remain **unqualified**; their source
and schema declarations are not enabled-success evidence.

Initial setup used asynchronous `thread/unsubscribe`, whose acknowledgment did
not establish completed unload. Replacing that assumption with confirmed owned
process shutdown and a cold app-server, followed by `thread/loaded/list`,
establishes the unloaded queue precondition before creating the sparse file.
The four cases passed at seeds `501432` and `987654`, with independent compile
and scoped format. Log: `/tmp/samgita-image-limits-validation.log`. No timeout,
resource limit or assertion was relaxed to obtain these results.

## Controlled compaction interruption and retries

`compaction_control_test.exs` adds two actual pinned-binary cases, using a new
loopback Responses provider rather than an app-server replacement. The minimal
`ModelFixture.write_response` extension runs after atomic request-journal
replacement and preserves existing `item(index)` subclasses. Its regression
first failed with the old handler, then passed with the extension.

The held-compaction case waits for a provider notice proving that the original
request is recorded and blocked. It obtains the real compaction turn/item IDs,
interrupts that turn and requires an `interrupted` terminal before explicitly
releasing late checkpoint output. Subsequent ordinary and cold-resumed requests
retain original usable history and contain no cancelled checkpoint. Exactly one
terminal result is retained; no second compaction is sent. This uses observed
barriers, without sleeping or extending upstream deadlines.

The retry case follows pinned upstream
`core/tests/suite/compact_remote.rs:1183-1287`: request retries zero, stream
retries two, then HTTP 500, provisional checkpoint without `response.completed`,
and finally a completed checkpoint. Exactly three compact requests carry
identical original input; only the final checkpoint enters subsequent ordinary
and cold-resumed history. This is Codex's documented internal compaction retry,
not driver replay of an ambiguous mutation. The driver never resends the RPC.
Production references are `core/src/compact_remote_v2.rs:324-374,454-476` and
task abortion in `core/src/tasks/mod.rs:930-994`, relative to the immutable pin.

The initial experiment failed because a derived fixture passed its new control
scenario into the existing assistant selector, unintentionally faulting the
first ordinary request. A direct regression reproduced that error. Separating
the control scenario from the assistant scenario fixed it; exact request counts
and all history assertions remain. Logs retain both attempts.

The two new cases passed at seed `501432`. Running
`mix test test/compaction_test.exs test/compaction_control_test.exs` passed
**six cases** at each of seeds `513498` and `987654`; independent compile and
format passed. All **17 Python regressions** passed, including journal-before-
response and legacy subclass preservation. Logs:
`/tmp/samgita-compaction-control-{initial,repair-1,regressions,python-red,python-green,python-repair-1,python-all}.log`.
These selected Linux/stdio cases do not complete all compaction fields,
transports, concurrent-steering combinations or external backend profiles.

## Harness, verification and source

`test/support/turn_fixture.ex` shares setup for the original three suites and the
tool-output/settings follow-up. It creates
an exclusive directory with a random 128-bit suffix, uses disposable home/config
and workspace paths, initializes an explicitly started Session, and fails on an
unexpected server interaction. Collection has a monotonic 20-second deadline.
Fixture/session shutdown is asserted; cleanup errors cannot be converted to a
passing test. The synthetic catalog includes an instruction template required by
the pinned `ModelsResponse` reader. There is no Samgita Repo, Phoenix or global
platform configuration dependency.

Run from the independent driver directory in the repository's Elixir/OTP
environment with `CODEX_BINARY` set to the pinned absolute executable:

```sh
mix compile --warnings-as-errors
mix format --check-formatted
mix test
```

The initial local outcome was **125 tests, zero failures**. Its 23 scenarios comprise
10 in `turn_input_test.exs`, seven in `turn_attachment_test.exs` and six in
`turn_parameters_test.exs`. Spec and quality review corrected weak plain-name
skill evidence, scratch-directory collisions and unchecked cleanup results
before the final suite. See [qualification](qualification.md) for final local and
hosted status; this checkpoint does not clear existing aggregate/security gates.

The follow-up's final independent compile, formatting and full suite passed
**140 tests, zero failures**, seed `12198`, with all 15 additional scenarios.
Root strict Credo and a fresh outside-umbrella actual-binary consumer passed.
Inventory consistency and 12 regressions passed; strict completeness still fails
on the missing requirements. Final hosted evidence belongs in the qualification
record, with security and external acceptance gates retained.

Pinned source references below are relative to `codex-rs/`:

| Contract | Reference |
| --- | --- |
| UserInput, byte spans and turn fields | `app-server-protocol/src/protocol/v2/turn.rs:115-279,358-484` |
| Upstream text/client-ID example | `app-server/tests/suite/v2/turn_start.rs:932-1005` |
| HTTP image rejection | `app-server/src/request_processors/turn_processor.rs:25-40`; `app-server/src/image_url.rs:1-8` |
| Image preparation and model normalization | `core/src/image_preparation.rs:32-37,390-414`; `core/src/client_common.rs:108-116`; `core/src/session/mod.rs:3574` |
| Image dimension/patch budgets and byte sanity guard | `utils/image/src/lib.rs:26-31,70-83,284-351` |
| User/tool-output scalar limits | `app-server/src/request_processors/turn_processor.rs:505-520,554-575` |
| Local media and audio MIME | `protocol/src/models.rs:1932-1952,2124-2180`; `protocol/src/local_media.rs:82-98`; `utils/audio/src/lib.rs:208-211` |
| Unsupported model media | `core/src/context_manager/normalize.rs:335-432` |
| Structured skill selection | `skills/src/selection.rs:44-112`; `skills/src/selection_tests.rs:168-225` |
| Additional context, metadata and tiers | `app-server/tests/suite/v2/turn_start.rs:735-862,1100-1185`; `core/src/responses_metadata.rs:68-110` |
| Output schema and tool-input rejection | `app-server/tests/suite/v2/output_schema.rs:21-234`; `app-server/src/request_processors/turn_processor.rs:544-552,660-675` |
| Standalone tool output, history and retention | `app-server/src/request_processors/turn_processor.rs:544-620`; `core/src/hook_runtime.rs:744-765`; `app-server-protocol/src/protocol/thread_history.rs:635-647`; `core/tests/suite/turn_input_submission.rs:1587-1700` |
| Settings precedence and preset normalization | `app-server/tests/suite/v2/turn_start.rs:2408-2585`; `app-server/src/request_processors/turn_processor.rs:406-420,814-935`; `core/src/client.rs:935-946` |
| Exact MCP mention startup selection | `core/src/session/turn.rs:997-1044`; `core/src/session/mcp.rs:404-415`; `codex-mcp/src/runtime.rs:415-460`; `codex-mcp/src/connection_manager/tool_catalog.rs:294-350` |

These are selected Linux/stdio results. The full transport/backend/OS matrix,
enabled external services, remaining field variants, item types and differential
profiles remain incomplete. No credentials, paid calls, real installations,
external repositories, publication or deployment were involved.
