# Isolated native app metadata profile

`apps/samgita_codex_driver/test/native_apps_profile.exs` exercises `app/read`
against the immutable Codex `rust-v0.163.0` app-server. Its backend is an owned
synthetic HTTP fixture, not ChatGPT, a real installed app or another Agent.
Source commit is `83086188ae0614bd882818ff1aa23f3194962012`; executable SHA256 is
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

Run explicitly from `apps/samgita_codex_driver`, in the verified Elixir environment:

```sh
MIX_ENV=test CODEX_BINARY=/absolute/path/to/pinned/codex \
  mix test test/native_apps_profile.exs --seed 501432
```

The file intentionally avoids default `*_test.exs` discovery. Linux, `unshare`,
`ip`, permission to create private user/network namespaces and the pinned native
executable are required. Missing isolation is a failing prerequisite; there is
no skip, privilege escalation or host-network fallback.

The fixture verifies a distinct network namespace containing only loopback and
no default/nonloopback route. Native configuration, home, temporary directory,
auth file and cwd are disposable. The native environment contains no inherited
credentials, proxy settings or exporters. A synthetic local model catalog avoids
catalog discovery. The input bridge allows only initialization, `app/read` and
loaded-thread discovery. It rejects turns, execution and MCP methods. The backend
serves `/backend-api/ps/apps/batch` and narrowly specified startup account metadata;
every other request is recorded as a failure. Both model requests and MCP HTTP
requests therefore fail the profile, rather than receiving fabricated results.

The batch endpoint validates synthetic Bearer, account and product-SKU headers.
Only header-verification booleans enter the journal. Native JSONL crosses the
bridge unchanged; the fixture never writes a successful RPC response itself.
Shutdown waits for the owned native process, HTTP server and output reader, and
the tests require native/controller/namespace-owner PIDs to be reaped before
deleting fixture files.

Seven cases require these observable native behaviors:

- Preserve first-requested identity order while deduplicating requests and
  separating missing apps. Reordered, duplicate and unsolicited backend records
  cannot change that order or escape the requested projection. Cached records
  return in the next caller's order without another HTTP request.
- Promote metadata-only cache entries when tools are first requested. Later
  metadata-only reads hide tool summaries while preserving the richer cache.
- Preserve explicit backend failures, including HTTP 429, as native RPC errors.
  An unsuccessful mixed cached/uncached read retains earlier fresh cache records;
  restoring the backend permits later requests.
- Enforce the 100-ID bound before deduplication, handle empty input without HTTP,
  reject an unknown thread before HTTP, and accept exactly 100 input identities.
- Keep disabled-app and API-key-only profiles distinct from enabled success:
  both return deduplicated missing IDs without a backend request.
- Preserve the configured product SKU separately from its default.

Output assertions cover exact public metadata and tool-summary values. Internal
backend action/model/icon-asset fields remain outside that public projection.
No loaded thread, turn, tool execution or project/task transition is allowed.
Metadata availability never grants an Agent authority or establishes Samgita
work acceptance.

Pinned source references, relative to `codex-rs/`:

| Contract | Source |
| --- | --- |
| Raw count, deduplication, feature/auth gate and response projection | `app-server/src/request_processors/apps_processor/read.rs:18-82` |
| Thread identity/config error boundary | `app-server/src/request_processors/apps_processor.rs:331-370` |
| Metadata-only request, cache scope, requested-ID filtering and output order | `chatgpt/src/connectors.rs:133-214` |
| Backend metadata projection | `chatgpt/src/connectors.rs:229-259` |
| Native order/cache example | `app-server/tests/suite/v2/app_read.rs:199-310` |
| Metadata-to-tools promotion | `app-server/tests/suite/v2/app_read.rs:318-395` |
| Failed fetch retains cache | `app-server/tests/suite/v2/app_read.rs:470-526` |
| Native input limit and synthetic backend/auth precedent | `app-server/tests/suite/v2/app_read.rs:616-637,780-810,858-927` |

Scoped warnings-as-errors compilation and formatting passed in Devenv. All
**7 tests passed** at each seed `501432` and `987654`, against working-tree source
based on `a696aef` plus these three profile files. The first run log is
`/tmp/samgita-native-apps-501432-initial.log`; the second is
`/tmp/samgita-native-apps-987654.log`. Python AST parsing also passed. These are
selected native app-server behaviors with a synthetic backend, not complete
app-family or live service conformance. `app/list`, `app/list/updated`, `app/installed`, MCP
discovery/search/execution, account/backend-change races, full field/transport/OS
coverage and live app/backend acceptance remain separate unqualified work.
This profile publishes no package, changes no external permissions and deploys
no service. A11 remains a separate platform confidentiality blocker.
