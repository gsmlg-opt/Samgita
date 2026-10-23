# Native turn inputs and parameters

This checkpoint adds 23 actual-binary scenarios at Samgita `73258c5`, bringing
the independent driver's suite to 125 tests. It changes tests and documentation;
the native schema, driver and platform runtime are unchanged. Full compatibility
remains incomplete. The method and field contracts stay `missing` until all their
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
| `image` with `url` | Omitted/null detail defaults, `auto`/`high`, original-detail normalization, explicit low-detail omission, mixed-case HTTP(S) rejection before model dispatch | One tiny inline PNG; no resize, size-limit or visual-understanding claim |
| `image` with `fileId` | Opaque reference and its detail reach the captured provider request; original reference remains in both item events | No upload, provider-side file lookup or access authorization was exercised |
| `localImage` | Local file and original path, detail defaults and capability-dependent `original`, low-detail omission, missing/corrupt-file fallback | Synthetic disposable PNG files; no remote filesystem or other-OS qualification |
| `audio` | Inline `audio/x-wav` canonicalizes to `audio/wav`; an HTTP URI produces the pinned preprocessing placeholder; original input remains in both item events | Synthetic audio-capable model metadata; arbitrary bytes establish construction rather than valid decoded audio |
| `localAudio` | `wav`, case-insensitive `MP3`, `m4a`, `webm`, `ogg` MIME/data-URI construction and path framing; missing and unsupported files produce defined text | No speech recognition or live provider acceptance |
| `skill` | Explicit discovered path injects a unique body once despite duplicate selection; disabled/unmatched explicit paths block fallback by name | The positive prompt contains no skill name, so its text cannot satisfy the assertion through plain-name selection; no dependencies/tools are installed |
| `mention` | Unknown synthetic `app://` and `plugin://` identities remain intact in both item events and add no model content | Enabled app/plugin/MCP routing and permissions remain unqualified |

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
  before model dispatch. A following valid turn succeeds. Successful tool-output
  continuation and its remaining variants still need evidence.

## Harness, verification and source

`test/support/turn_fixture.ex` shares setup for the three new suites. It creates
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

Final local outcome: **125 tests, zero failures**. The 23 new scenarios comprise
10 in `turn_input_test.exs`, seven in `turn_attachment_test.exs` and six in
`turn_parameters_test.exs`. Spec and quality review corrected weak plain-name
skill evidence, scratch-directory collisions and unchecked cleanup results
before the final suite. See [qualification](qualification.md) for final local and
hosted status; this checkpoint does not clear existing aggregate/security gates.

Pinned source references below are relative to `codex-rs/`:

| Contract | Reference |
| --- | --- |
| UserInput, byte spans and turn fields | `app-server-protocol/src/protocol/v2/turn.rs:115-279,358-484` |
| Upstream text/client-ID example | `app-server/tests/suite/v2/turn_start.rs:932-1005` |
| HTTP image rejection | `app-server/src/request_processors/turn_processor.rs:25-40`; `app-server/src/image_url.rs:1-8` |
| Image preparation and model normalization | `core/src/image_preparation.rs:32-37,390-414`; `core/src/client_common.rs:108-116`; `core/src/session/mod.rs:3574` |
| Local media and audio MIME | `protocol/src/models.rs:1932-1952,2124-2180`; `protocol/src/local_media.rs:82-98`; `utils/audio/src/lib.rs:208-211` |
| Unsupported model media | `core/src/context_manager/normalize.rs:335-432` |
| Structured skill selection | `skills/src/selection.rs:44-112`; `skills/src/selection_tests.rs:168-225` |
| Additional context, metadata and tiers | `app-server/tests/suite/v2/turn_start.rs:735-862,1100-1185`; `core/src/responses_metadata.rs:68-110` |
| Output schema and tool-input rejection | `app-server/tests/suite/v2/output_schema.rs:21-234`; `app-server/src/request_processors/turn_processor.rs:544-552,660-675` |

These are selected Linux/stdio results. The full transport/backend/OS matrix,
enabled external services, remaining field variants, item types and differential
profiles remain incomplete. No credentials, paid calls, real installations,
external repositories, publication or deployment were involved.
