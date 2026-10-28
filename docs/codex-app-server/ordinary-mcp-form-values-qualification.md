# Ordinary MCP form values and the explicit-null boundary

V541/V542 target stock Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux-musl executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The app-server is real; only the local Responses backend and stdio MCP peer
are fixtures. No Samgita platform, database, external account or paid task is
required. All owned launches use the existing fixed YOLO configuration.

## Values consumed by the real native path

The new standalone case deliberately answers with an empty string, integer zero,
floating zero, `false`, an empty selection and Unicode enum IDs. The requested
schema supplies nonempty/nonzero defaults, so substituting defaults or applying
truthiness coercion fails the assertions. Single-select, multi-select, legacy
titled enums, string, integer/number and boolean branches are checked separately.

Complete original native request and response frames agree with the delivered
values. The independent MCP peer checks exact primitive types, then computes a
summary from the answer it actually received. The test checks that independently
expected summary in the next native provider request, together with the echoed
answer, tool-call identity, native item completion and final assistant item.
This establishes consumption beyond local schema validation or generic JSON
forwarding. The consumer sends exactly one answer.

A second form is interrupted while unanswered. Actual native completion and
request-resolution events must both arrive; their relative order is unrestricted.
The peer receives `action:cancel`; the retired handle sends nothing, and the
first response digest/outcome remains intact. Exactly three provider requests,
two forms, eleven selected original frames and an empty workspace are required.
Existing bounds remain: 60-second case, 20-second observable waits, 5-second RPCs,
32 captured frames / 1 MiB and 64 KiB per frame. Confirmed native, MCP peer and
provider ownership/Port/PID shutdown precedes temporary-directory removal.

Only physical owners **1844–1846 and 1864–1867** gain scoped implemented evidence.
No alias, arbitrary constraint enforcement, modern MCP version, permission flow,
external service or alternate transport inherits that evidence. The earlier
[ordinary form lifecycle](ordinary-mcp-form-lifecycle-qualification.md) stays
byte-for-byte unchanged.

## Upstream explicit-null output boundary

Physical owner **1882** declares `{"type":"null"}` under the ordinary string
schema's `format` property. It remains an unmet compatibility requirement and
moves missing→blocked with source evidence; no native success is claimed.

The complete production path at the immutable source is:

1. The ordinary MCP Form is converted to the core Form. The native event mapper
   calls the typed `try_into()` before constructing its sole outgoing native
   elicitation request; conversion failure sends no request.
2. [The typed conversion](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/mcp.rs#L859-L870)
   parses `requested_schema` into `McpElicitationSchema`.
   [The string definition](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/mcp.rs#L506-L545)
   uses `Option<McpElicitationStringFormat>` with
   `skip_serializing_if = "Option::is_none"`. Its closed enum contains only
   email, URI, date and date-time strings. Null becomes `None` and is omitted;
   no `Some(null)` value exists.
3. Typed `ServerRequestPayload` → `ServerRequest` → `OutgoingMessage::Request`
   reaches the shared
   [serializer](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-transport/src/transport/mod.rs#L269-L282).
   Both stdio and WebSocket writers use it. No ordinary raw-JSON request route
   restores the field.

The ordinary Form is the sole reference to this typed schema. OpenAI aliases use
arbitrary JSON and cannot qualify this physical owner. The selected null node,
whole string definition and ordinary Form equal the official archived schema;
complete schema roots differ and are not asserted equal. The source inventory
also accounts for the two internal empty-property Form constructors and the
core destructuring match; none introduces another native serializer.

This conclusion uses source inspection and byte comparison, not a mock emitter
or a forbidden test. A native null-input-to-omission experiment would prove
normalization only. Closure requires a supported upstream producer and an
authorized pin update, or an explicit target/evidence-contract decision. The
goal is not silently narrowed.

## Focused evidence and independent source review

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-v541-focused.py
python3 -B /tmp/samgita-v541-v542-source-review.py
```

The recipe runs
`mix test test/native_ordinary_mcp_form_values_test.exs --warnings-as-errors --seed <seed>`
from the independent driver. Both seeds **501432 and 987654 pass 1/0**, with no
retry or assertion/deadline change. Strict Credo across **609 sources** passes.
Parent source review independently verifies **26 unique complete official files**,
exact selected schema nodes and the immutable archive. Final combined-source
qualification is recorded in the [ordinary server-request batch](ordinary-server-request-envelopes-qualification.md#final-combined-source-functional-qualification):
all14 reviewed steps pass, including143 real-native cases at both fixed seeds,
the three-seed WebSocket selection, isolated consumer and static/build checks.
These focused checks alone do not replace that combined evidence.

| Artifact | SHA256 |
| --- | --- |
| `/tmp/samgita-v541-source-evidence.json` | `76f7398766a87d327a1c520ff8446f612ff4b390394b49977074c4b30bb1b7f5` |
| `/tmp/samgita-v542-source-evidence.json` | `30bcd605e894420beca9c6faaf5feb1cdbf261e8d4830ea63a044c59c3278282` |
| `/tmp/samgita-v541-v542-parent-source-binding.json` | `76da3e373396ba5d546bc84c4944958ce24c757ac4ee11178a60bad3495c619a` |
| Formatted test | `9263267c833b393a7bf5423ffe22b0b984519cea09bbd56051296932d67a935e` |
| Local dependency helper | `fcff9d2186dcdb574f250e994403fb64658e259231bf52c6e7ed93b5c09806ea` |
| `/tmp/samgita-v541-focused-501432.log` | `9fc974a5a05b536ee61cd93e6c00d7a6e868f1b55653a8d769aa61f21b4b8dd1` |
| `/tmp/samgita-v541-focused-987654.log` | `f3c2403249c8c6820e0a8cc0815490a8194917fa03d919ac8ebda7b939df892d` |

## Rollback and limits

Rollback removes this case/helper, restores exactly these eight manifest rows
and the reviewed selection/fingerprint. No database migration, production
resource, historical record or process-owner implementation changes. Contracts
are **5,586 implemented / 904 missing / 131 blocked**; requirements remain
**462 implemented / 12 missing / 11 blocked**, zero globally verified.

Security, credential, authentication, authorization, approval and permission
tests/audits remain prohibited and unrun. Broad suites and automatic hosted
workflows that include them remain unrun. A11, other unavailable emitters,
external/OS profiles, complete compatibility, release and deployment remain
incomplete. No package publication or real provider integration follows from
these functional results.
