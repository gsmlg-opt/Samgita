# Existing native question text and MCP result metadata

This evidence-binding unit starts from
`2522b7928f05aebca7dea9dd0a62fd8b66d88b9d` on the existing `main`. It
changes only documentation and two exact manifest records. No test, fixture,
production code, schema, lock or configuration changes, and no new runtime
execution, are attached to this unit.

Target: official Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Nine complete producer/conversion sources match their immutable archive members;
both physical schema nodes independently match their canonical hashes.

## Question text: owner 3155

`schema:ServerRequest.json#/definitions/ToolRequestUserInputQuestion/properties/question`
is a required nonnull string. The unchanged
[ordinary input-wait test:171](../../apps/samgita_codex_driver/test/native_search_input_wait_test.exs)
receives the actual native server request and independently requires the literal
`Choose fixture input`, its prescribed question ID/header/options and the real
thread/turn/call identity. The provider supplies only a model function item;
Codex's [native emitter:829–862][question] creates the app-server request.

The actual opaque-handle reply retains its original outgoing bytes and native
request ID. Matching resolution, completed turn and exactly one provider tool
output with the original call ID and prescribed answer establish causal use.
This is an ordinary choice question; no permission or approval behavior is
exercised. The [input-wait qualification](search-user-input-wait-qualification.md)
retains the owning scenario and original run history.

## Direct MCP result metadata: owner 4403

`schema:v2/McpServerToolCallResponse.json#/properties/_meta` belongs to the
native app-server result. The unchanged
[ordinary MCP test:192](../../apps/samgita_codex_driver/test/native_mcp_request_metadata_test.exs)
independently requires the complete result map with top-level
`_meta: {"fixture":{"preserved":true}}`. This is distinct from both request
metadata and the content block's separate metadata.

Eight genuine local MCP `tools/call` operations across warm/cold native
processes retain independently checked backend params, startup negotiation,
request IDs and progress tokens. The native [processor:679–697][mcp-call] uses
the real MCP runtime; the exact [response conversion:216–226,252–259][mcp-meta]
copies `result.meta` into the top-level field. The peer answers MCP only; it
does not manufacture app-server responses. No inference, remote backend,
authentication or permission profile is needed. Existing
[request-metadata qualification](mcp-request-metadata-qualification.md) retains
the scenario; its request-field evidence does not itself qualify this result.

## Execution continuity and byte-evidence limit

Both exact owning modules appear in the previously executed V384 final2 driver
commands at seeds **501432/987654**, each **154/0**, with no exclusions. Their
current hashes match the original before/after guard and the current **389**
source guard. Those old results are reused with exact source identity; no new
154-case, aggregate or outside-consumer run is claimed.

The modules retain original outgoing bytes and independently assert complete
decoded incoming request/response values. They **do not retain original incoming
JSON frame bytes**. Re-encoding the decoded maps does not add that evidence.
This binding qualifies the named decoded string/object values and their native
causal paths, without claiming original inbound encoding coverage. The MCP
result's omitted/null/empty alternatives and other question strings/profiles
remain unqualified by these assertions. No alias or surrounding family inherits
acceptance.

Inventory consistency passes. Only **3155/4403** gain scoped implemented
evidence: contracts become **5,083 implemented /1,472 missing /66 blocked**;
requirements remain **462 implemented /12 missing /11 blocked**, with zero
verified in both. Full completeness remains failed. The preceding final four-case
block, strict checks and outside-consumer evidence retain their original source
identities. No additional behavioral test is run for this documentation unit.

Binding program: `/tmp/samgita-v392-bind.py`; complete source/node, original
command/log hashes and guard evidence: `/tmp/samgita-v392-binding/evidence.json`.
Bounded source review: `/tmp/samgita-v392-next-ordinary-owner.md`. Original runs:
`/tmp/samgita-v384-functional-checks/final2/`; current guard:
`/tmp/samgita-v390-functional-checks/final/source.json`.

Prohibited security/permission tests, audits, mixed broad suites and hosted
workflows remain unrun. A11, unavailable producers, external/backend/OS/platform
success, full compatibility and release gates remain incomplete. No publication
or deployment occurs. Rollback removes only these two evidence mappings and
this record; execution behavior and historical data remain unchanged.

[question]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/bespoke_event_handling.rs#L829-L862
[mcp-call]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/mcp_processor.rs#L679-L697
[mcp-meta]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/mcp.rs#L252-L259
