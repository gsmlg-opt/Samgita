# Native displaced configuration writes

Three actual-binary cases in `native_config_override_metadata_test.exs` use
Codex `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`,
Linux musl SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The fixture supplies inert desktop CLI overrides and edits only its owned
temporary user configuration. No thread, model request, tool or live credential
is used. Process guardians and confirmed close remain required.

| Case | Required native behavior |
| --- | --- |
| Displaced single write and restart | Requested `light` persists in user TOML while CLI `dark` remains effective. The response is `okOverridden` with exact message, effective value and session-layer metadata. Restart without the desktop overrides exposes persisted `light`, unchanged bytes and user-layer version. |
| Equal value and deletion | Equal user/CLI `dark` returns `ok` and explicit null metadata. Deletion removes the user key, changes its version and reports CLI `dark` as the effective override. |
| Batch ordering | An unrelated first edit is skipped; the first displaced edit in request order determines metadata. Reversing the displaced edits changes the known effective value from boolean true to string `dark`, while both requested file edits persist. Exact effective and persisted maps differ as expected. |

The session-layer version oracle hashes an independently specified canonical
JSON string containing every owned CLI override. It is not derived from the
response. `app-server/src/config_manager_service.rs:410-439` persists edits
before constructing status; lines 788-852 define exact messages/equality/null
handling, and 855-868 choose the first displaced edit. Config layer metadata
and canonical hashing are defined in `config/src/state.rs:202-207` and
`config/src/fingerprint.rs:54-67`. Inert desktop keys are accepted by
`config/src/config_toml.rs:547-549` and its strict-config tests.

Five exact `ConfigWriteResponse` contracts gain scoped implemented evidence:
the three `OverriddenMetadata` properties, `WriteStatus`'s `okOverridden`
variant and the owning `overriddenMetadata` property. No shared layer alias,
unobserved union, whole method or verified requirement is promoted. Managed,
enterprise/project layers, credential-provider overrides, concurrent writers,
execution enforcement and other deployment profiles remain unqualified.

From the independent driver package with the verified Devenv and pinned binary:

```sh
mix test test/native_config_override_metadata_test.exs --seed 501432
mix test test/native_config_override_metadata_test.exs --seed 987654
```

Both passed **3 tests / zero failures**, 2.0/2.1s. Changed-file formatting and
warnings-as-errors compile passed. Exact commands/exits and logs are in
`/tmp/samgita-config-override-adoption-v3-20261024/`. The initial v1 adoption
failed formatting because the new file had not been applied; no test ran. The
v2 draft ran three cases and failed all three on its separate empty loaded-list
check, which omitted native `nextCursor: null`. The final test compares the
entire exact empty response, additionally requires zero uncertainty and
execution events, and retains every config/metadata/persistence assertion.
No runtime behavior, deadline, assertion or gate is weakened.

This default-suite addition still requires final-source package/platform/hosted
checks. Full compatibility, A11, external/OS success, publication and deployment
remain incomplete.
