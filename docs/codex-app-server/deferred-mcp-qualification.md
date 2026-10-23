# Deferred MCP discovery qualification

This unit targets the immutable Codex `rust-v0.163.0` executable, commit
`83086188ae0614bd882818ff1aa23f3194962012`, with the existing native driver.
It adds only an owned synthetic Responses provider, an owned stdio MCP peer,
and focused qualification tests. No production implementation changes are made.

Current status: all eight actual-binary cases pass with seeds `501432` and
`987654`. Compilation with warnings as errors, formatting and Python static
validation pass. This qualifies the selected Linux stdio/local synthetic
behaviors below; external services and other profiles remain unqualified.

## Source contract

Paths below are relative to the pinned upstream `codex-rs/` directory:

- `core/tests/suite/search_tool.rs:554–595,745–831`: three provider responses
  search, invoke a namespaced tool, then finish. Search results enter history as
  `tool_search_output`; later provider `tools` arrays do not reinject the namespace.
- `core/tests/suite/search_tool.rs:1271–1404`: enabled local MCP tools are
  searchable namespace children; disabled tools stay absent.
- `core/tests/suite/search_tool.rs:1408–1562`: a search-surfaced local MCP
  execution error is associated with its original call and returned to the model.
- `core/tests/common/responses.rs:1001–1012`: provider search-call envelope uses
  `tool_search_call`, `execution: "client"`, a call ID and JSON arguments.
- `core/src/tools/spec_plan.rs:265–273,392–420`: model search capability controls
  MCP exposure and whether a search handler is advertised. Historical
  `tool_search` feature switches are removed in this pin; they are not used here.
- `core/src/tools/handlers/tool_search.rs:231–244,275–282,343–358`: empty query
  and zero limit reject before discovery; successful search coalesces matching
  loadable tools into namespace results.
- `core/src/tools/context.rs:241–257,361–367`: successful and aborted search
  output history retain the search call identity and client execution marker.
- `core/src/tools/parallel.rs:338–346`: search handler failures become completed
  client search-output items with an empty tool list.
- `protocol/src/models.rs:2414–2440` and `core/src/tools/context.rs:183–213`:
  non-null structured MCP content takes precedence in the model output payload;
  the runtime adds a wall-time header without changing the structured value.
- `core/src/tools/handlers/mcp.rs:215–246`: discovered invocation passes the
  originating call and cancellation token into the normal MCP runtime.
- `app-server-protocol/src/protocol/thread_history.rs:831–860`: MCP completion
  derives item status from native success and retains either result or error.

The existing `mcp_mention_test.exs` explicitly disables `supports_search_tool`.
Its direct exposure proof does not establish the deferred discovery path.

## Verified behavior checks

`apps/samgita_codex_driver/test/deferred_mcp_test.exs` contains eight cases:

1. Search-capable native turn advertises search and hides the direct MCP namespace
   across all three provider requests. Search history carries the namespaced
   deferred schema; the backend call, item lifecycle and model-visible result
   retain their respective thread, turn, item and provider call identities.
2. An MCP `isError` result produces a failed native item while retaining structured
   result data and model-visible structured content. Native item results retain
   the original text content separately.
3. An MCP JSON-RPC error produces a failed item and model-visible error tied to
   the discovered call, without falling through to unsupported-call handling.
4. A tool present in `enabled_tools` and `disabled_tools` stays undiscoverable.
5. An empty search query produces no executable MCP discovery result or call.
6. A zero search limit produces no executable MCP discovery result or call.
7. A model without search capability receives the enabled direct namespace,
   with the disabled tool still excluded.
8. Interrupting a held discovered invocation produces an interrupted native turn
   without a third model request or duplicate backend invocation.

`scripts/codex/deferred_mcp_fixture.py` subclasses the existing model fixture
without modifying it. Its stdio MCP mode is launched and owned by disposable
Codex. Only loopback provider traffic, synthetic text, temporary configuration
and request journals are used. The held tool leaves stdin available for
cancellation and terminates when its owning session closes the stream.

## Verification record

Prepared at repository baseline `a696aef0ae2445f03bd17fcf273475c71ae13cea`.
Runtime qualification started at `55630e1a797e96cfaab9c818a8d57ff09c88bf99`.
Python AST parsing and pure response-construction assertions passed on
2026-10-24. The check allocated the fixture without its constructor and created
no socket, subprocess, thread or listener. It checked search/call/final response
shapes, the tool catalog, error modes and structured result identities.
Whitespace checks on both new source files produced no diagnostics.

The following command completed with exit `0` on 2026-10-24:

```sh
devenv shell --no-tui -- bash -c 'cd apps/samgita_codex_driver &&
  MIX_ENV=test mix format test/deferred_mcp_test.exs &&
  MIX_ENV=test mix compile --warnings-as-errors &&
  MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl mix test test/deferred_mcp_test.exs --include real_codex --seed 501432 &&
  MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl mix test test/deferred_mcp_test.exs --include real_codex --seed 987654 &&
  MIX_ENV=test mix format --check-formatted test/deferred_mcp_test.exs'
```

- Seed `501432`: **8 tests, 0 failures**, 5.6 seconds.
- Seed `987654`: **8 tests, 0 failures**, 5.6 seconds.
- Compile with warnings as errors and changed-file formatting checks passed.
- Independently refreshed binary SHA-256:
  `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
- Final command log: `/tmp/samgita-codex-deferred-mcp-final.log`.
- The coordinator independently reran compilation, formatting and all eight
  tests at both seeds against the integrated tree based on `55630e1`; both
  passed. Log: `/tmp/samgita-codex-deferred-mcp-parent.log`.
- All owned commands exited. A targeted process inspection found no surviving
  deferred MCP fixture or pinned Codex app-server process. The build/native slot
  was explicitly released to the coordinator.

The initial seed `501432` run had **8 tests, 2 failures**, recorded in
`/tmp/samgita-codex-deferred-mcp-initial.log`. Both failures expected the MCP text
content in model history, while the observed value was the structured MCP result
preceded by the native wall-time header. The exact pinned source confirms this
precedence. One fixture-expectation repair changed those two assertions to parse
and compare the structured JSON and added a separate native-item text-content
assertion. No production code, pinned schema, driver helper or shared fixture was
changed. One repair round completed successfully; no failed repair rounds remain.

## Limits

Verified cases are Linux stdio with local synthetic provider and MCP transports.
They do not establish live
hosted Apps, OAuth, real provider authorization, MCP HTTP transports, modern
protocol negotiation, concurrent searches, catalog refresh, search ranking across
large catalogs, reconnect/replay, cold history recovery, every invalid argument,
or every cancellation race. No paid or production calls, real credentials,
external service tasks or deployment are authorized. Full compatibility, external
platform profiles and A11 remain separately incomplete.
