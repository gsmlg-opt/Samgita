# Offline native model discovery

This profile targets actual Codex `rust-v0.163.0`, source commit
`83086188ae0614bd882818ff1aa23f3194962012`, Linux musl executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Only the official executable produces app-server messages. A synthetic local
catalog supplies metadata; no model inference or hosted discovery is performed.

`offline_model_discovery_fixture.py` replaces itself with Codex inside an owned
private user/network namespace. It checks a different namespace, the sole
loopback interface and absence of a default route before execution. The
environment is allowlisted; home, config, catalog and temporary files are
disposable. The fixture starts no HTTP server and supplies no credentials.
Missing namespace prerequisites fail explicitly, without a host-network fallback.

Six cases specify:

- Full rich and nullable model projection: reasoning strings, modalities,
  default selection, hidden and non-API filtering, service tiers, specialty,
  access programs, availability and upgrade/timestamp metadata.
- Native filtered-offset pagination, zero/large limits, end cursors and invalid
  cursors; callers still treat cursors as opaque.
- Omitted/null option semantics and stable negotiation, unknown request fields,
  local schema rejection and native malformed-input rejection.
- Invalid empty-file configuration, its initialization warning and startup
  fallback catalog, versus fresh provider-capability configuration errors.
  Filtered-empty and all-hidden catalogs exercise the pinned empty-result
  shortcut before cursor parsing and the hidden-only default.
- Startup static-catalog snapshot versus a cold restart with a replacement file.
- Fresh local provider capability reads across ordinary, Bedrock and Bedrock
  Runtime configuration, invalid configuration and recovery. Capability metadata
  is not successful image generation, search or real Bedrock integration.

Every case requires an empty loaded-thread list and an operational session,
then confirms native and namespace-owner reaping before deleting its files.
No execution is started or retried. No catalog entry grants Samgita Project
permission or confers Task acceptance.

Pinned sources relative to `codex-rs/`:

| Behavior | Source |
| --- | --- |
| Catalog provider checks and list dispatch | `app-server/src/request_processors/catalog_processor.rs:177-217` |
| Hidden filtering, limit/cursor policy and empty shortcut | `app-server/src/request_processors/catalog_processor.rs:280-329` |
| Exact model/result projection | `app-server/src/models.rs:8-75` |
| Sort, account filtering and default selection | `models-manager/src/manager.rs:171-182`; `protocol/src/openai_models.rs:954-985,1025-1044` |
| Fresh provider capability configuration | `app-server/src/request_processors/config_processor.rs:207-217` |
| Capability configuration error code | `app-server/src/request_processors/config_processor.rs:233-244` |
| Empty catalog configuration rejection | `core/src/config/mod.rs:2193-2213` |
| Non-strict startup fallback and warning | `app-server/src/lib.rs:559-580`; `app-server/src/request_processors/initialize_processor.rs:232-251` |
| Model wire representation | `app-server-protocol/src/protocol/v2/model.rs:118-194` |
| Matching upstream scenarios | `app-server/tests/suite/v2/model_list.rs:295-534`; `app-server/tests/suite/v2/model_provider_capabilities_read.rs:15-100` |

Validation used the existing `main` at
`8331b9977d50ffd7615c962c3b2cd79e6eb5e3f2` plus the new owned profile/launcher
on 2026-10-24. The profile verifies the exact executable SHA256 before use.
Commands ran serially through Devenv with `MIX_ENV=test` and the canonical
absolute `CODEX_BINARY`, from `apps/samgita_codex_driver`:

```sh
mix format test/native_model_discovery_profile.exs
mix compile --warnings-as-errors
mix test test/native_model_discovery_profile.exs --seed 501432
mix test test/native_model_discovery_profile.exs --seed 987654
mix format --check-formatted
```

Both final runs passed **6 tests, 0 failures** (15.6s / 15.5s). Compilation and
whole-driver format checks passed; Python AST parsing passed. Log:
`/tmp/samgita-native-model-discovery-repair-3.log`. Every native/namespace-owner
process was reaped before its fixture files were deleted. No database or running
Samgita was required.

The initial six-case run failed one incorrect assertion: it assumed a physically
empty catalog yielded an empty result. The first assertion repair still assumed
the config loader's rejection propagated through `model/list`; actual startup
instead warns and falls back under non-strict configuration. Matching startup
source established that path. The second repair correctly asserted fallback,
but assigned `-32600` to the fresh capability-read error; this processor explicitly
uses `internal_error` (`-32603`). The final correction asserts that exact code,
message, startup warning, fallback data and filtered-empty behavior. Logs retain
each **6 tests / 1 failure** run:
`/tmp/samgita-native-model-discovery-initial.log`,
`/tmp/samgita-native-model-discovery-repair-1.log` and
`/tmp/samgita-native-model-discovery-repair-2.log`. No runtime code, timeout or
assertion coverage was weakened; these were test-oracle corrections against
fixed source and actual wire observations.

The required Ubuntu 22.04 isolated CI job runs this explicit profile. Its six
cases add four method/response entries and 26 directly asserted parameter,
model-projection, list-response and capability fields as scoped `implemented`.
Other field branches and deployment profiles retain their unqualified status;
the complete inventory gate remains separate.

This does not qualify live catalog/auth refresh, Gateway OAuth, managed provider
policy changes, runtime inference, all enum variants, other transports or other
operating systems. The full compatibility manifest, unreachable legacy emitters
and A11 remain incomplete. No publication or deployment follows from this unit.
