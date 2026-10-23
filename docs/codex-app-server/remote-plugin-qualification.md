# Authenticated native remote-plugin qualification

This bounded profile targets the actual Codex `rust-v0.163.0` app-server through
the independent driver Session. The source pin is
`83086188ae0614bd882818ff1aa23f3194962012`; Linux musl binary SHA-256 is
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

The eight explicit native cases pass at seeds `501432` and `987654` after the
fixture repairs below. This establishes only the declared isolated profile;
real remote-provider compatibility and full acceptance remain unverified.

## Isolation and ownership

`test/native_remote_plugin_profile.exs` is explicitly selected, outside default
test discovery. Its helper verifies the immutable binary before and inside a
private user/network namespace. Only loopback exists and no default route is
present. The fixture owns its temporary HOME, CODEX_HOME, workspace, cache,
synthetic account tokens, HTTP metadata peer, HTTPS bundle peer and certificate
authority. It does not read real accounts or execute model turns, hooks or MCP
tools. Each app-server response comes from the pinned native binary; only its
metadata and bundle dependencies are synthetic.

The backend accepts only startup metadata, the exact remote skill endpoint and
the installed snapshot endpoint. Other HTTP routes and model/mutation POSTs
fail and are journaled. Exact synthetic bearer/account-header equality is
recorded as booleans, never raw tokens. Bundles use HTTPS, receive no backend
credentials, and require normal TLS verification against the owned CA through
`CODEX_CA_CERTIFICATE` or `SSL_CERT_FILE`. There is no HTTP-bundle debug bypass
and no insecure TLS setting. Static valid model metadata avoids discovery.

The first run exposed a startup race: `remote_plugin=false` hides remote catalog
entries but does not disable authenticated background materialization or the
featured-catalog warmup. A background pass consumed the initial bundle change
before the explicit reconcile request, and the unapproved featured route was
correctly rejected. All eight tests failed in 20.7s at seed 501432. The repair
starts each native process with `plugins=false`, then atomically enables that
feature in its owned config before the first explicit plugin request, after
initialization. Native per-request config loading sees the new feature setting.
No sleep, debug hook or assertion relaxation is used; cold restarts use the same
gate while preserving cache, authentication and CA state. This profile therefore
qualifies explicit reconciliation, excluding normal enabled-at-startup background
sync and readiness.

The first repair validation also failed 8/8 in 19.8s because a substring guard
matched both `plugins` and `recommended_plugins`. The fixture stopped before
forwarding plugin calls. Exact line matching and a newline-anchored replacement
correct this harness defect; error messages now expose the driver error code.

Only initialize/initialized, thread/loaded/list, plugin/skill/read and
plugin/reconcile are admitted to native stdin. No threads or turns are created.
MCP declarations are disabled and use a nonexistent executable; app/hook flags
are disabled and hook commands are nonexistent. Capability flags describe bundle
declarations, not activation or authorization. Fixed regular-file archive entries
are generated only under owned cache paths; no traversal, link or hostile-path
archive is introduced. Invalid plugin names contain no path separators.

The Stdio guardian owns the complete namespace process group. Cleanup closes
the native process, joins the output bridge, closes both HTTP peers and joins
their bounded request threads. Tests also await recorded process disappearance.

## Executed cases

| Case | Required assertions |
| --- | --- |
| Matching skill detail | Exact authenticated route returns Unicode contents and explicit null unchanged; no bundle download. |
| Skill identity/decode errors | Mismatched plugin ID, mismatched skill name and malformed JSON are RPC errors, with no fabricated contents. |
| Skill HTTP/auth errors | HTTP404 is invalid request; 401/429/503 are internal errors. Missing/API-key auth rejects before HTTP. |
| Materialize/repeat/cold restart | Valid HTTPS bundle materializes, all four declaration flags appear, repeat is a no-op, and a complete native restart preserves cache without another download. |
| Revision/enable/removal | Changed version reports old/new declaration union; disabled/re-enabled same version avoids downloads; removal reports active-version declarations and deletes only owned cache; next pass is a no-op. |
| Per-plugin failures with partial success | Missing version, HTTP bundle URL and invalid gzip populate both sorted failure arrays while a valid sibling installs. SSL_CERT_FILE trust fallback still verifies TLS. |
| Whole-snapshot errors | HTTP401/429/503, decode and invalid identity fail the RPC and preserve the cached prior bundle without further downloads. |
| Failed update and recovery | A bundle503 populates both failure arrays and preserves the old version; a later valid bundle updates and reports unioned declarations; repeat is a no-op. |

These distinguish successful RPC results, RPC failure and per-plugin failure
arrays. Reconcile success with failures does not claim that every plugin
materialized; capability flags do not prove runtime readiness.

## Pinned source contracts

Paths below are relative to the pinned `codex-rs/` checkout:

- `app-server/src/request_processors/plugins.rs:1225-1274,2434-2474` validates
  skill selectors and maps authentication, HTTP404 and other errors.
- `app-server/src/message_processor.rs:542-560` and
  `core-plugins/src/manager.rs:2824-2947` gate startup work on plugins_enabled;
  remote_plugin alone does not suppress bundle synchronization or featured-cache
  warming. `app-server/src/request_processors/plugins.rs:539-546` and
  `app-server/src/config_manager.rs:191-225` reload the owned config for explicit
  plugin requests without repeating those startup tasks.
- `core-plugins/src/remote.rs:113,395-453,598-602,1399-1435,2250-2280`
  defines pagination limit 200, typed remote errors, optional skill contents,
  exact response identity checks and installed snapshot download URL requests.
- `app-server/src/request_processors/plugins/reconcile.rs:19-46` distinguishes
  unauthenticated skips from authenticated overall synchronization errors.
- `core-plugins/src/remote/remote_installed_plugin_sync.rs:131-346,398-455`
  validates all cache identities before mutation, persists matching identity,
  classifies per-plugin validation/download/install failures, unions old/new
  capabilities and reports removal capabilities before deleting stale cache.
- `core-plugins/src/manager.rs:1682-1770` serializes reconciliation and detects
  cached enablement changes without downloading the same version.
- `core-plugins/src/remote/plugin_capabilities.rs:17-70` discovers declaration
  hints independently of runtime policy and activation.
- `core-plugins/src/store.rs:110-158,190-235,347-350` defines owned version cache
  paths and the base-directory `.codex-remote-plugin-install.json` identity.
- `core-plugins/src/remote_bundle.rs:229-243,303-370` requires HTTPS for the
  immutable release binary and fetches bundles without backend auth headers.
- `http-client/src/custom_ca.rs:11,61-62,167-189,395-407` selects an additional
  trust root from CODEX_CA_CERTIFICATE, falling back to SSL_CERT_FILE.
- `app-server/tests/suite/v2/plugin_read.rs:965-1025` and
  `app-server/tests/suite/v2/plugin_reconcile.rs:42-207,269-342` are upstream
  behavior references. Their debug-only HTTP bundle allowance is not used.

## Scope and remaining evidence

At baseline `dd6ec5b6422fdd52243e94af1c4ed95a2b023902`, the second fixture repair
passed all eight cases at seeds `501432` and `987654` in 26.6s and 26.3s. Root
warnings-as-errors compilation and scoped formatting passed, but strict Credo
reported the empty-bundle assertion's `length(list) == 0`. A bounded cleanup
changes only that assertion to `list == []`; deadlines, routes, first
materialization, cache, restart, TLS, authorization and error assertions remain
unchanged.

The final native rerun used, from the repository root:

```sh
devenv shell --no-tui -- env MIX_ENV=test \
  CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl \
  sh -c 'cd apps/samgita_codex_driver && mix test test/native_remote_plugin_profile.exs --include real_codex --seed 501432 && mix test test/native_remote_plugin_profile.exs --include real_codex --seed 987654'

devenv shell --no-tui -- env MIX_ENV=test \
  PGHOST=/tmp/samgita-p3-pg/socket POSTGRES_PORT=55443 POSTGRES_USER=gao \
  SAMGITA_TEST_DATABASE=samgita_redesign_recovery_repair_test \
  sh -c 'mix compile --warnings-as-errors && mix format --check-formatted apps/samgita_codex_driver/test/native_remote_plugin_profile.exs && mix credo --strict'
```

The final native runs passed **8/0 in 26.8s** and **8/0 in 27.3s**, respectively.
Root compilation and scoped formatting passed. Strict Credo examined 319 files
and no longer reported a remote-plugin warning, but exited 8 for a separately
installed test: `native_thread_event_lifecycle_test.exs:300`, `assert_stream/1`
cyclomatic complexity 10 (maximum 9). That unrelated path was left with its
owner; this checkpoint does not claim a passing aggregate lint gate.
Scoped `devenv shell --no-tui -- env MIX_ENV=test mix credo
apps/samgita_codex_driver/test/native_remote_plugin_profile.exs --strict` passed
69 checks on its one source file with no issues. An earlier `--files-included`
invocation still selected all 319 files and reproduced the unrelated failure;
it is not counted as a scoped pass.

Python AST parsing and scoped whitespace checks passed. Per-test cleanup
assertions passed, and a subsequent process inspection found no owned fixture
process or generated fixture directory. The preserved source draft directory is
not a runtime fixture. Logs are `/tmp/samgita-remote-plugin-repair2.log`,
`/tmp/samgita-remote-plugin-final.log` and
`/tmp/samgita-remote-plugin-astra-validation.log`; initial failures remain in
`/tmp/samgita-remote-plugin-initial.log` and
`/tmp/samgita-remote-plugin-repair1.log`.

This profile does not qualify remote sharing/search pagination, workspace policy,
real account/token issuance, certificate rotation, runtime MCP/app/hook effects,
model execution, arbitrary archive security, non-Linux platforms or real external
service behavior. No full-compatibility, published-package, deployment, release
readiness or production claim follows. A11 remains separately incomplete.
