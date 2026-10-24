# Native MCP form variants and explicit decisions

Sixteen new tests run the stock Codex `rust-v0.163.0` app-server, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Only its loopback model provider and stdio MCP dependencies are synthetic.
The fixtures never construct app-server requests or notifications. All cases
exercise both MCP `2025-06-18` and `2026-07-28`, asserting the corresponding
native initialize or server/discover exchange.

## Typed selections and string formats

Two enum-sibling cases add untitled single, legacy enumNames, untitled multi
and titled multi selections. Exact known native schemas and peer receipts
distinguish raw values from display labels and from defaults, including
explicit multi-selection order. Thirty-two exact canonical schema properties
and branch nodes gain scoped implemented evidence. Native pending ownership,
timer, no pre-reply effect, explicit reply, single marker, provider continuation,
history identity, resolution and stale-reply rejection remain asserted.

Two string-format cases preserve a known nonempty `$schema` and distinct
uri/date/date-time literals; selected strings differ from defaults. An explicit
`Map.has_key?` check proves omitted format on the plain string. The nonnull
format union branch is exercised by those three native enum-string values.
The null branch remains missing: omission does not prove null.
Five exact physical contracts gain evidence, without dialect fetching,
URI navigation, date/time conversion or arbitrary-schema enforcement claims.

The pinned Codex Cargo.lock uses RMCP 3.5.1 at
`4048ac40e958fb1a7d614617a2ae8d26666ee2fa`. Its immutable
[elicitation schema source](https://github.com/modelcontextprotocol/rust-sdk/blob/4048ac40e958fb1a7d614617a2ae8d26666ee2fa/crates/rmcp/src/model/elicitation_schema.rs)
preserves `$schema` (1130-1218), distinguishes string formats (71-125), and
has an actual legacy enumNames regression (1907-1926). Source SHA256 is
`3921e0ebbad32b0df6fe4c788f35914e786ce4356a79c471825d20f72a8e37cf`.
This source basis supplements the actual native tests; it is not their substitute.

## Arbitrary OpenAI form extensions

Twelve cases cross two MCP versions, two production producers and three
explicit decisions:

| MCP producer | Native app-server mode | Required advertised extension |
| --- | --- | --- |
| openai/form | openai/form | `openai/form: {}` |
| openai/elicitation/create, mode=form | openaiForm | `openai/elicitation: {form: {}}` |

Pinned `rmcp-client/src/elicitation_client_service.rs:270-286` and
`app-server-protocol/src/protocol/v2/mcp.rs:810-835` define these paths. The
test explicitly enables both extensions at initialization and verifies their
forwarding in each native MCP negotiation. It does not use trusted-host user
verification or invent a legacy approval emitter.

Whole native envelopes preserve independently known nested arbitrary JSON,
image-picker metadata, Unicode, message and request metadata. A bounded 150ms
held-state observation requires the original live handle/timer and no decisions,
effects or continuation. Only the explicit accept response writes its known
marker; decline and cancel have no marker and omit content in the native MCP
reply. Each case asserts one peer decision, two provider requests, exact
provider continuation, completed native items/history, one observed resolution,
timer cancellation, no uncertainty/gap and rejected duplicate handles.
Twelve exact canonical branch/property/enum contracts gain evidence. No
unobserved schema, actual UI rendering, external MCP, trusted verification,
reconnect, other transport/OS or live-service profile is qualified.

## Validation

From `apps/samgita_codex_driver`, with the pinned `CODEX_BINARY`:

```sh
mix test test/native_mcp_enum_siblings_test.exs test/native_mcp_titled_enum_test.exs test/native_mcp_form_fields_test.exs --seed 501432
mix test test/native_mcp_enum_siblings_test.exs test/native_mcp_titled_enum_test.exs test/native_mcp_form_fields_test.exs --seed 987654
mix test test/native_mcp_openai_forms_test.exs test/native_mcp_string_formats_test.exs --seed 501432
mix test test/native_mcp_openai_forms_test.exs test/native_mcp_string_formats_test.exs --seed 987654
```

Enum and retained scalar/titled cases passed **6/0**, 13.0/17.8s; the new
OpenAI/string cases passed **14/0**, 17.7/19.5s. Driver warning-free compile,
format and root strict Credo passed. Exact commands/source hashes/logs and
successful end-of-run guards:
`/tmp/samgita-native-new-fields-adoption-v1-20261024/` and
`/tmp/samgita-native-mcp-new-forms-adoption-v1-20261024/`.

All 49 new schema records remain scoped implemented, with zero verified or
whole-method promotions. Legal answer transport does not prove arbitrary
constraint enforcement. Complete package, populated-platform and hosted checks
must cover final combined code. A11, missing native emitters and external/OS
profiles remain incomplete. No release, publication or deployment occurs.
