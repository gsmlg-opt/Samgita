# Native app catalog and installed snapshots

The explicit `native_app_catalog_profile.exs` profile runs immutable Codex
`rust-v0.163.0` as the real app-server with an owned synthetic directory and
discovery-only Streamable HTTP MCP backend. The native executable produces every
app-server response and notification. This is neither a mocked Codex server nor
live ChatGPT/app acceptance.

Source commit is `83086188ae0614bd882818ff1aa23f3194962012`; executable SHA256 is
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Run from `apps/samgita_codex_driver` in the verified Elixir environment:

```sh
MIX_ENV=test CODEX_BINARY=/absolute/path/to/pinned/codex \
  mix test test/native_app_catalog_profile.exs --seed 501432
```

The filename avoids default test discovery because this profile requires Linux,
`unshare`, `ip` and private user/network namespace permission. Missing isolation
fails; there is no skip, elevated permission or host-network fallback. The
namespace must differ from the caller, have only loopback interfaces/routes and
no default route. Disposable auth/config/home/tmp/workspace and an allowlisted
native environment prevent inherited credentials and exporters. The fixture
reuses configuration and synthetic-auth helpers from `isolated_apps_fixture.py`
without editing that metadata-only profile.

The native bridge permits only handshake, `app/list`, `app/installed` and
loaded-thread discovery. HTTP permits paginated directory metadata, narrow
startup account metadata, MCP initialization, ping and `tools/list`; tool calls,
resource execution, models and other routes fail. No turn or execution is
authorized. The MCP fixture uses JSON responses over stateless Streamable HTTP;
the optional unsolicited SSE stream returns 405. This qualifies this discovery
profile, not MCP event-stream compatibility.

Eight cases cover catalog merge/order/pagination and cached HTTP counts;
observable directory-complete/tools-held notification gating; explicit refresh
and directory HTTP 429 errors with retained cache; installed identity, enabled
and callable policy; duplicate/missing/synthetic connector filtering; persisted
snapshot reads after native-process restart; refresh changes, empty snapshots
and failed-refresh retention; unknown/invalid threads; and disabled/API-key-only
behavior. No loaded thread or callable execution is allowed. The gated case
waits on actual backend observations, then holds the discovery response while
requiring absence of an inaccessible-only interim update.

Directory requests carry synthetic ChatGPT auth. The pinned release withholds
that auth from the loopback MCP origin because it is outside its trusted
ChatGPT-origin allowlist; this discovery-only synthetic peer is anonymous, and
the tests require bearer/account headers to be absent. This does not qualify
production hosted-MCP authentication or OAuth. Header checks enter the journal
only as booleans. Tests check secret-canary absence, unexpected routes and
confirmed owned native/controller/namespace-owner reaping. Catalog presence or
`callable: true` is native discovery
metadata; neither grants Samgita authorization nor Task acceptance.

Pinned source references, relative to `codex-rs/`:

| Contract | Source |
| --- | --- |
| Asynchronous directory/discovery merge, refresh, notification gating | `app-server/src/request_processors/apps_processor.rs:168-325` |
| Invalid thread/config boundary and pagination | `app-server/src/request_processors/apps_processor.rs:331-436` |
| Installed snapshot, force-refresh runtime, failure retention and policy | `app-server/src/request_processors/apps_processor/installed.rs:35-195` |
| Discovery-only upstream fixture and native installed examples | `app-server/tests/suite/v2/app_installed.rs:55-103,455-675` |
| Catalog paging and update examples | `app-server/tests/suite/v2/app_list.rs:690-913,915-1066,1169-1445` |
| Directory pagination and cache | `connectors/src/lib.rs:167-223,265-291` |
| Installed identity/filter/callability projection | `connectors/src/runtime_projection.rs:43-118` |
| Native hosted MCP endpoint/header configuration | `codex-mcp/src/mcp/mod.rs:607-663` |
| ChatGPT credential origin restriction | `codex-mcp/src/mcp/mod.rs:361-391,410-425` |

Validation on 2026-10-24 used the current `main` source plus these three files
and the coordinator's `Schema.Output` helper extraction. Final HEAD at reporting
is `a8852e9feff8d8a2f3524b10f1f79b46d2347add`; that helper was still uncommitted.
Commands ran serially in `devenv shell --no-tui --` from the driver directory:

```sh
mix format test/native_app_catalog_profile.exs
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test CODEX_BINARY="$PWD/../../tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl" \
  mix test test/native_app_catalog_profile.exs --seed 501432
MIX_ENV=test CODEX_BINARY="$PWD/../../tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl" \
  mix test test/native_app_catalog_profile.exs --seed 987654
mix format --check-formatted
```

Warnings-as-errors compile and format passed. Both final native runs passed
**8 tests, 0 failures**, with no skips. Python AST parsing and `git diff --check`
also passed. Logs are `/tmp/samgita-native-app-catalog-501432-repair1.log` and
`/tmp/samgita-native-app-catalog-987654.log`.
The coordinator independently reran these eight cases with the new fuzzy-search
and native history regressions: **23 tests passed** at both seeds, with root
strict Credo and both independent format/compile checks passing. Log:
`/tmp/samgita-codex-followup-final-integration-3.log`.

The initial seed 501432 run passed compile but failed 5 of 8 cases because the
fixture required ChatGPT bearer/account headers on its untrusted loopback MCP
origin. A native diagnostic and the pinned origin policy confirmed deliberate
credential withholding; the fixture now requires their absence while retaining
the strict directory-auth and catalog/discovery assertions. The initial log is
`/tmp/samgita-native-app-catalog-501432-initial.log`; its diagnostic journal is
`/tmp/samgita-native-app-catalog-initial-diagnostic.json`. This was one repair
round. All owned native/controller/namespace processes were confirmed reaped,
and the diagnostic's synthetic credential directory was removed.

This establishes these scoped native discovery behaviors. Full field,
thread-context, account/backend-change, event-stream, transport/OS and live
service profiles remain unqualified. A11 remains a separate platform blocker;
no package publication or deployment is claimed.
