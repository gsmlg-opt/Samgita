# Native local plugin and marketplace lifecycle

This bounded profile drives the pinned Codex `rust-v0.163.0` executable through
the independent driver Session. Source commit is
`83086188ae0614bd882818ff1aa23f3194962012`; Linux musl binary SHA-256 is
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

`test/native_plugin_lifecycle_profile.exs` intentionally stays outside default
test discovery. Its private network prerequisite belongs to the explicit
isolated Linux qualification job, alongside the existing namespace profiles.

The fixture uses explicitly owned temporary HOME, CODEX_HOME, repository,
plugin/skill bundles and a local Git repository. It checks the binary before
entering and again inside a private user/network namespace. Only loopback
exists, with no default route. No listener, model turn, backend, synthetic
app-server or external credential is supplied. Static model metadata prevents
model discovery; all model/backend URLs point to an unavailable port inside the
private namespace. Native Codex produces every app-server response.
The Stdio process-group guardian owns the namespace, native executable and
native Git descendants. Cleanup is registered immediately after Session start;
tests also check that recorded native/namespace-owner process IDs disappear.
Fixture Git commits have synthetic identity and use no system/global Git config.

| Case | Qualified behavior |
| --- | --- |
| Installed catalog | Uninstalled plugins are omitted unless explicitly suggested; duplicate suggestions collapse. Installation persists across a complete native process restart. |
| Uninstall | Installed/runtime skill catalogs drop the plugin, source files remain, and cold state remains uninstalled. |
| Unauthenticated reconcile | Returns empty change/failure arrays and preserves local installed state/configuration. This is a skipped remote reconciliation pass, not runtime readiness. |
| Remote skill read boundary | Invalid remote identity and empty skill name reject before backend access; a valid selector requires backend authentication. No skill contents success is claimed. |
| Local marketplace registration | Add/duplicate identity, conflicting source rejection, cold discovery, removal and source preservation. |
| Marketplace validation | Empty source, local sparse/ref arguments, unknown and invalid removal selectors reject without configuration writes. |
| Local discovery search | Normalized name/keyword matching, personal/global/workspace selection, first-page-only local entries and empty search. Discovery returns `enabled: false` even for an enabled installed plugin. |
| Explicit local-Git upgrade | Initial materialization, no-op, a changed source revision, exact snapshot contents, unknown/non-Git errors, removal and source preservation. Automatic plugin startup work is disabled for this case, following upstream's upgrade profile. |

Pinned references below are relative to `codex-rs/`:

- `app-server-protocol/src/protocol/v2/plugin.rs:69-145,151-245,268-280`
  defines marketplace, installed, reconcile and remote skill-read fields.
- `app-server/src/request_processors/plugins.rs:822-953` filters installed and
  explicitly suggested local plugins; `1225-1274` validates and fetches remote
  skill detail; `2010-2042` uninstalls local plugins and refreshes caches.
- `app-server/src/request_processors/plugins/reconcile.rs:19-26` makes
  unauthenticated/disabled reconciliation an empty response. Authenticated bundle
  changes, removal hints and failed materialization semantics are documented by
  the response type but are not exercised by this local-only profile.
- `app-server/src/request_processors/plugins/search.rs:35-39,128-136,287-327`
  specifies empty search, local first-page behavior, discovery enablement and
  local marketplace scope filtering.
- `app-server/src/request_processors/marketplace_processor.rs:49-153` maps
  management operations and reload/cache invalidation.
- `core-plugins/src/marketplace_add.rs:96-155` distinguishes local registration,
  duplicate identity and source collisions. Local paths are referenced directly.
- `core-plugins/src/marketplace_remove.rs:56-128` validates names/configuration
  layers, removes owned installed snapshots, and rejects unknown names.
- `app-server/tests/suite/v2/marketplace_upgrade.rs:142,424,459` provides upstream
  references for explicit local-Git upgrade, no-op and non-Git errors.

## Reproduction and validation

The initial eight-case run failed during initialization because the helper
incorrectly observed network interfaces through host-mounted `/sys/class/net`.
The private namespace was real, but that mount was not its interface inventory.
The first repair uses `ip -j link` and `ip -j route` inside the namespace and
retains exact loopback-only/no-default-route assertions. Native lazy config
loading then rejected an empty model catalog. The second repair supplies valid
static metadata and unavailable private-loopback backend URLs, without starting
a listener or turn. Both native runs then passed **8/0** at `501432` and
`987654`, in **16.9s / 18.3s**. No semantic assertion or deadline was relaxed.

Strict Credo next rejected deeply nested cleanup. A bounded helper extraction
preserved close-before-wait order, proof parsing, native/namespace-owner PID
order, predicates and deadlines. The final formatted source passed **8/0**
again at `501432` and `987654`, **18.0s / 17.3s**. Root test-environment
warnings-as-errors compilation, scoped format and strict Credo passed:
**317 files, 69 checks, no issues**. Python AST and whitespace checks passed;
all owned fixture processes were reaped.

Run from the independent driver directory with the pinned absolute
`CODEX_BINARY`: `mix test test/native_plugin_lifecycle_profile.exs --include
real_codex --seed 501432`, repeated with `987654`, inside
`devenv shell --no-tui -- env MIX_ENV=test`. Root strict checks use the same
test environment. Logs are `/tmp/samgita-plugin-lifecycle-{initial,repair1,repair2,final}.log`
and `/tmp/samgita-import-plugin-final-validation.log`. The required hosted
namespace job explicitly selects this profile; default discovery excludes it.

Fourteen method/response entries and 36 directly asserted fields/branches gain
scoped `implemented` evidence. The reconcile fields cover only empty arrays;
local search cursor behavior does not prove remote pagination. Remote skill-read
and local ref/sparse rejection evidence is attached without promoting their
missing success paths. No entry is marked `verified`.

This is local native behavior evidence, not full plugin compatibility. Remote
installed bundles, authenticated reconciliation/materialization/capability
changes, remote `plugin/skill/read` contents, remote search pagination and share,
MCP/app/hook-enabled runtime effects, managed policy layers, Git network/auth
transports, other operating systems and external account profiles remain
incomplete. Fake/local fixtures do not establish real Sigma/Synapsis/Codex service
integration, publication, deployed behavior or production readiness. A11 and
other qualification gates remain governed by the main qualification record.
