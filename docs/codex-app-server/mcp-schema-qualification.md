# Native MCP Form fields and URL decisions

Eight cases use stock Codex `rust-v0.163.0` with a local stdio MCP peer and
loopback model provider. Two Form cases and six URL cases cover both MCP
`2025-06-18` and `2026-07-28`. The source pin remains
`83086188ae0614bd882818ff1aa23f3194962012`, Linux musl binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Every app-server request, item and response originates in that executable.
Synthetic model/MCP dependencies cannot establish external authentication.

## Typed Form and metadata

`native_mcp_form_fields_test.exs:45-145,167-205` asserts the complete native
request map: active thread/turn, server, message, request metadata and scalar
schema. Boolean, integer, number and email fields retain the selected titles,
descriptions, defaults and bounds. The actual pending interaction requires an
explicit reply, with exact content and response metadata observed at the MCP
peer and in the next provider request. Native start/completed MCP items preserve
their associations. Duplicate handles cannot cause a second effect or inference.

The first draft sent floating-point integer-schema bounds/defaults. Both cases
failed before any app-server request with native MCP error `-32602`,
`data did not match any variant of untagged enum ElicitRequestParamsWire`.
The pinned RMCP IntegerSchema requires `Option<i64>`; the fixture now sends
legal integers `1/9/3`. Exact native schema equality remains required. This
proves valid integer round trips through the public numeric representation,
not acceptance of floating-point values in an integer MCP schema.

Reviewable RMCP dependency evidence is
[IntegerSchema at the exact locked revision](https://github.com/modelcontextprotocol/rust-sdk/blob/4048ac40e958fb1a7d614617a2ae8d26666ee2fa/crates/rmcp/src/model/elicitation_schema.rs#L363-L386).
Codex pins this revision in `Cargo.lock:13123-13126`. Public schema conversion
and integer serialization are in
`app-server-protocol/src/protocol/v2/mcp.rs:445-602,803-812,855-867`.
The actual runtime forwards response metadata via
`rmcp-client/src/elicitation_client_service.rs:205-245,419-460`.
An unused public conversion omitting metadata is not this execution route.

## URL decisions

`native_mcp_url_elicitation_test.exs:37-158` covers explicit accept, decline and
cancel in both protocol versions. Each actual request retains its exact URL,
elicitationId, metadata and thread/turn identity. A trap on the owned loopback
provider records GET/POST/HEAD; all tests require zero visits before the reply,
after the reply and after confirmed native shutdown. No command or web-search
item is produced. One peer decision marker and exactly two model requests
remain the only observed continuation. Acceptance records a decision; it does
not prove a login, opened browser or completed authentication.

The initial accept expectation omitted content. Native core explicitly changes
accepted null/absent content into `{}` and discards content for decline/cancel:
`core/src/session/handlers.rs:134-156`. Tests retain submitted `content:null`
and now assert the exact resulting maps, including `{}` for accept. Both MCP
encoders preserve that core decision. No assertion or timeout was removed.
The URL projection is in `protocol/v2/mcp.rs:831-842,883-899` and
`codex-mcp/src/elicitation.rs:655-669`; native association/dispatch is in
`app-server/src/bespoke_event_handling.rs:875-945,1728-1780`.

## Execution and ledger boundary

In verified Devenv with the pinned CODEX_BINARY, the final five-module command
passed **25/0** at seeds `501432` and `987654`, 36.5/38.2s of ExUnit time
(37.06/38.78s command wall time). The modules are
`native_persisted_tool_items_test.exs`, `native_provider_errors_test.exs`,
`native_mcp_form_fields_test.exs`, `native_thread_future_settings_test.exs` and
`native_mcp_url_elicitation_test.exs`. Separate Form repeats also passed **2/0**
at both seeds. The earlier **13/2** invalid-integer run and **12/2** accept-content
expectation run remain in `/tmp/samgita-native-followup-units-20261024/`, along
with exact commands, complete logs, exits and measured times. No native runtime
or dependency source needed a patch for either fixture mistake.

Only **31 Form/shared contracts** and **six URL leaf contracts** gain scoped
implemented evidence. TurnId covers an active nonnull turn; other null contexts,
schema unions, scalar formats, malformed-answer validation and real service
profiles remain unqualified. No aggregate variant or fully verified promotion
is made. Process cleanup uses the existing guardian barriers. A11, complete
field/lifecycle/deployment coverage and final combined/hosted checks remain
separate required gates. No credentials or sibling services were changed.
