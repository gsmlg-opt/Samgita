# Native MCP titled single-select forms

Two new cases use stock Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux musl SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
`native_mcp_titled_enum_test.exs` exercises negotiated MCP `2025-06-18` and
`2026-07-28` through the actual app-server. Synthetic local model and MCP peers
are dependencies; they never supply app-server messages. No external service,
paid task or live credential is used.

Each peer requests a typed string field with an exact title, description,
ordered `oneOf` constants/display titles and a nonselected default. The caller
explicitly selects `green-id-λ`, whose display title is `Green display λ` and
whose default is `blue-id`. Before replying, the test compares the entire
native schema/request, its real thread/turn/server identity and generation-bound
handle; it requires a live timer, one provider call, no outcome, no uncertainty,
no marker and no completed turn. No automatic responder is installed.

After explicit acceptance, assertions join the actual native resolution to the
exact MCP peer response, one selected-constant journal marker, correct protocol
handshake, two provider calls and the exact model-visible function output.
One MCP start/completion pair and persisted history retain native identity and
arguments. The completed turn is separate from the local write result. Duplicate
replies fail as stale; no policy rule, workspace write or further inference is
permitted. The marker is a local dependency effect, not an external exactly-once
guarantee or Samgita task acceptance.

The first draft failed both new cases before inference because the shared base
model fixture creates its request-observation file only on the first request.
The new fixture now exclusively creates an empty journal before serving. It
cannot overwrite an existing journal or erase a later request. The negative
zero-request check remains, as do the schema/effect/history assertions and all
deadlines. Failure log:
`/tmp/samgita-mcp-titled-adoption-v1-20261024/native-501432.log` (**4/2**,
including two passing existing scalar Form cases).

From the independent driver package in the verified Devenv with the immutable
`CODEX_BINARY`:

```sh
mix test test/native_mcp_titled_enum_test.exs test/native_mcp_form_fields_test.exs --seed 501432
mix test test/native_mcp_titled_enum_test.exs test/native_mcp_form_fields_test.exs --seed 987654
```

Both passed **4 tests / zero failures**, 4.1/4.1 seconds. Python fixture AST,
changed-file formatting, warnings-as-errors compile, whole-driver format check
and root strict Credo passed. Exact commands, exits and logs:
`/tmp/samgita-mcp-titled-adoption-v2-20261024/`.

## Pin ownership and limits

`app-server-protocol/src/protocol/v2/mcp.rs:607-610,640-685,773-780` defines
the single-select union, titled branch and const/title options. Lines 856-864
deserialize core Form schema into typed app-server schema. Native elicitation
conversion is in `codex-mcp/src/elicitation.rs:642-653`; nonempty schema avoids
empty-confirmation autoaccept at 725-738. Version-specific reply encoding and
content/metadata preservation are in
`rmcp-client/src/elicitation_client_service.rs:202-245,419-458`.

Eight exact missing request contracts gain scoped `implemented` evidence: two
const-option properties, the titled single-select union branch and its five
direct properties. Broader form/primitive/enum owners, untested siblings,
null/empty variants and whole methods are not promoted. The response content is
generic JSON; this does not prove validation of arbitrary answers against a
requested schema. Untitled/legacy/multiselect forms, interruption/loss races,
real MCP/providers, other transports/OS and A11 remain incomplete.

The inherited ordinary launcher disables unrelated startup plugins and preserves
owned cleanup. This suite does not itself run inside a private network namespace;
namespace prerequisite checks and dedicated isolated profiles are separate.
Final-source complete package/platform/hosted checks remain required, with no
full-compatibility, publication or deployment claim.
