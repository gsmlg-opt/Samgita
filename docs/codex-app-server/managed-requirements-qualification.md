# Native managed requirements, write boundaries and recovery

Thirteen focused cases pass against stock Codex `rust-v0.163.0` at seeds
`501432` and `987654`, **13/0** each, 19.6 seconds each. The source pin is
`83086188ae0614bd882818ff1aa23f3194962012`; the Linux musl executable SHA256 is
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
All protocol responses come from that immutable executable. The fixture supplies
local policy files, with no model provider, app-server emulator or execution turn.

## Behavior demonstrated

- `native_managed_requirements_test.exs:81-191` checks exact restrictive approval,
  reviewer, sandbox, browser/remote-control/login/feedback settings, empty web
  search normalization to `disabled`, and legacy managed-layer narrowing without
  losing other settings. A managed-field edit rejects the entire batch with
  exact `configRequirementReadonly` data; the preceding writable edit has no
  effect. Malformed policy returns the native parse error while the session stays
  ready; repairing the owned file restores the exact prior response.
- `native_managed_provider_requirements_test.exs:96-212` checks the synthetic
  managed provider, `ephemeral` credential-store mode and closed-loopback URL as
  effective overlays, without persisting them into user config or inventing user
  origins. Both ancestor and descendant provider edits reject. Batches also reject
  managed no-op values atomically. Unmanaged provider metadata remains writable
  and survives confirmed native shutdown and cold restart beside the overlay.
- `native_managed_feature_requirements_test.exs:113-239` checks selected typed
  browser/computer/in-app-browser/application metadata, exact deny/turn values,
  normalized ASCII domains, explicit source reload and cold restart. Invalid
  lifetime and wildcard-domain policy reads fail without damaging user config;
  repairing policy recovers the prior response. This proves reported policy
  metadata, rather than actual browser/computer/network enforcement.

Every case asserts no loaded thread, turn start or server interaction, and zero
pending requests. Explicit close verifies both the native process and namespace
owner are gone; the existing guardian also owns failure cleanup.

## Fixture boundary

`scripts/codex/managed_requirements_fixture.py` verifies the executable hash and
creates child-only user, mount and network namespaces. It proves mapped root,
loopback only, no IPv4/IPv6 default route, private `/etc` tmpfs and a read-only
bind of the synthetic `system` directory at `/etc/codex`. Only child mounts are
changed. HOME, CODEX_HOME, TMPDIR and the exec environment are explicitly scoped;
there are no real credentials or external network services.

The fixture creates `workspace/.git/HEAD`, the stock loader's project boundary.
The helper checks its exact proof path. A separate native positive-control case
at `native_managed_requirements_test.exs:194-252` creates an owned ancestor Git
marker and conflicting `.codex/config.toml`. Both disposable roots have explicit
trust in the owned user config. Workspace reads return the user value/origin
without the ancestor layer, while an explicit ancestor read returns its project
value/origin. Repeating the workspace read returns the original complete result.
Thus an ignored untrusted layer cannot provide a vacuous pass. This is a tested
project-discovery boundary, not total host-filesystem isolation or a fully
initialized Git repository.

Immutable source references, relative to `codex-rs/` at the pin above:

- `app-server/src/request_processors/config_processor.rs:446-578,645-714`
  constructs the native requirements response and typed metadata.
- `app-server/src/config_manager_service.rs:119-175` loads explicit cwd and
  constructs config origins/layers; `:231-285` rejects managed write paths.
- `config/src/project_root_markers.rs:5,45-49` supplies the default `.git` marker.
- `config/src/loader/mod.rs:1067-1116,1304-1315,1538-1562,1688-1706` resolves
  trust, the nearest marker and bounded project layers. `git-utils/src/trust.rs:81-130`
  independently recognizes the owned `.git/HEAD` directory without running Git.

## Commands, failures and evidence scope

From the independent driver in verified Devenv, with `MIX_ENV=test` and the
hash-checked CODEX_BINARY:

```sh
mix compile --warnings-as-errors
mix test test/native_managed_requirements_test.exs test/native_managed_provider_requirements_test.exs test/native_managed_feature_requirements_test.exs --seed 501432
mix test test/native_managed_requirements_test.exs test/native_managed_provider_requirements_test.exs test/native_managed_feature_requirements_test.exs --seed 987654
```

Python AST, namespace prerequisite, scoped formatting and root `mix credo
--strict` also pass. Exact commands, exits and complete logs are retained under
`/tmp/samgita-native-managed-qualification-20261024/attempt-02/`. The initial
12-case version passed both seeds but strict Credo rejected an escaped string
literal. Its complete results remain under `attempt-01/`. A sigil preserves the
same bytes; no deadline, assertion or check was relaxed. The thirteenth case is
the added ancestor positive control.

Only **43 directly demonstrated contracts** gain scoped `implemented` evidence:
13 restrictive settings, four provider/store/URL contracts and 26 selected typed
metadata fields/values. Exact IDs and hashes remain in the manifest. The audited
candidate list and before/after hashes are retained in
`/tmp/samgita-managed-contracts-qualified-20261024.json`.
No whole union, all policy choices, real login, model effect, complete method,
full lifecycle, external/OS profile or fully verified promotion is inferred.
The broad goal, final-source aggregate/hosted checks and A11 remain incomplete.
No tag, publication, production migration or deployment occurs.
