# Native MCP catalog pagination and explicit recovery

The dedicated `native_mcp_catalog_profile.exs` drives stock Codex
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, executable
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
A bounded owned stdio MCP peer supplies synthetic catalogs, not Codex responses.
Both negotiated MCP versions (`2025-06-18` and `2026-07-28`) run through actual
loaded native threads. No model, tool, resource execution or real account is used.

The independently handwritten native result requires rich server icons, tool
title/input/output schemas and annotations, resource title/MIME/size/icons/meta,
and template title/MIME/annotations. Each value remains attached to its original
identity. Two tool/resource/template pages use exact opaque cursors; only order
within each method is constrained because native resource/template collection
runs concurrently. Native server-list `nextCursor:null` is separate from the
peer's resource pagination.

The four explicit status queries have distinct observations:

| Query | Native result and peer activity |
| --- | --- |
| Full, good peer | Exact complete two-page catalog |
| `toolsAndAuthOnly` | Same tools/auth metadata, empty resource/template arrays; no additional resource/template I/O |
| Full, resource page two returns a fixed protocol error | Entire resource collection discarded, templates/tools intact, `runtimeStatus:connected`, `toolsError:null` |
| Full, peer explicitly restored | Original full catalog on the same native instance/generation and loaded MCP manager |

The peer journal requires one negotiation, two tool requests, six resource and
six template requests per version, with exact request/reply IDs and cursor
presence after each phase. There is exactly one second-page resource error.
No automatic retry, reconnect, config reload, new turn or work acceptance occurs.
`connected` does not establish catalog completeness, Agent health or execution
acceptance. The pinned native DTO has no resource-error field; the driver does
not invent one or present the failed first page as a complete result.

## Upstream projection boundaries

These are actual pinned native transformations, not driver losses:

- A regular tool loses exactly five reserved top-level connector metadata keys.
  Nested `connector_id`, an unrelated future key and resource metadata remain
  ordinary data. Such metadata grants no permission; the tool is never called.
- Typed SDK icons and annotations omit the deliberately unknown members. Native
  templates omit SDK icons/meta because their DTO has no such fields.
- Resource size `5_000_000_000` survives exactly. The peer sends the exact Python
  integer `18_446_744_073_709_551_615`; native omits only its unrepresentable i64
  size while retaining the resource's URI/name/title. No floating-point oracle,
  clamping, rounding or whole-resource deletion is used.
- SDK metadata/output schemas require objects and its icons/annotations have
  typed shapes. The broader JSON schema alone does not prove arbitrary scalar,
  null, malformed or unknown-member success. Those domains stay unqualified.

Immutable source references:

- [Native DTOs and conversions](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/protocol/src/mcp.rs#L229-L533).
- [Whole-collection resource failure](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/codex-mcp/src/connection_manager/resources.rs#L38-L128).
- [Ordinary tool metadata filtering](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/codex-mcp/src/rmcp_client.rs#L845-L875).
- [Native status selection and projection](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/mcp_processor.rs#L371-L547).
- [Pinned SDK resource shapes](https://github.com/modelcontextprotocol/rust-sdk/blob/4048ac40e958fb1a7d614617a2ae8d26666ee2fa/crates/rmcp/src/model/resource.rs#L5-L118), selected by Codex's `rmcp 3.5.1` lock.

## Verification and limits

The standalone temporary candidate passes its complete one-case file at both
`501432` and `987654`, both MCP versions in each run, with formatting and matching
source/build guards. Every observed owned process is gone. The journal and
independent result assertions pass on the first runtime attempt. Frame/journal/
control bounds and existing cleanup/deadlines are retained.

Candidate handoff:
`/tmp/samgita-v54-mcp-catalog-candidate/handoff-result-native-r1.json`, SHA256
`37c576e7692fc1807644c790265d20822b090aae4ea365428762be39cee10a0c`.
Exact physical-owner proposal:
`/tmp/samgita-v54-mcp-catalog-candidate/owner-proposal.json`, SHA256
`4cd2380bb345e31bad702ac39b451df1a3c8a959dd1abdd38659a74655d0e0a4`.
Candidate passes alone grant no owner promotion or final-source acceptance.

The subsequent integrated six-file block (direct/origin/target/Apps/catalog/
defaults) passes **37/0 twice**, seeds `501432` and `987654`, with zero exclusions.
All eleven commands pass: root/driver warning-free compile and format, strict
Credo (448 source files), namespace/sandbox prerequisites, both complete native
runs, 38 tooling regressions and inventory consistency. The 1,507-file source
and immutable executable guards match before explicit manifest binding.

Exact commands/logs: `/tmp/samgita-native-continuation-v58-20261025/`.
Terminal report `/tmp/samgita-native-continuation-v58-terminal-20261025.json`,
SHA256 `58108203bdffacfc5e6e8ef57238ab6b6857cfa0217ad9c789354e8c3e60d042`.
Thirteen precise physical `ListMcpServerStatusResponse` properties and the exact
`authStatus:unsupported` enum gain scoped implemented evidence. Seven other
audited auth/runtime/null owners stay unchanged. Contracts become **4,463
implemented / 2,099 missing / 59 blocked**; requirements stay **462 implemented /
12 missing / 11 blocked**, zero verified. No aliases or complete JSON value
domains inherit qualification. Complete final-source matrices remain required.

The required hosted workflow explicitly runs this new profile. Real external
MCP/OAuth/account/OS/backend behavior, unobserved runtime/auth variants, A11,
full final-source qualification and complete compatibility remain incomplete.
No remote service, credential, repository or deployment is changed.
