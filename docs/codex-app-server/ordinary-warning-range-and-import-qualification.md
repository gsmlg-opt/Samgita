# Native configuration ranges and partial import evidence

V503 uses unchanged official `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012` and binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
These ordinary functional checks change no driver, upstream or platform code.

## Exact Unicode diagnostic from the real configuration loader

`native_config_warning_envelope_test.exs` preserves its original range-absent
otel warning and adds one ordinary scalar type error. The three-line owned
file assigns `model_context_window = "λ🙂"` to an `Option<i64>` field. Its
independently authored oracle is the quote-inclusive UTF8 byte span136..144,
Unicode-scalar start3:24 and inclusive end3:27. The preceding comment also
contains Unicode. Neither oracle reads observed native coordinates or calls
the upstream location helper. Exact file SHA256:
`52fce6ed8c29560175f4e0b8451780a536a9af9cefad211422998003ed725f3b`.

The complete original native `configWarning` requires summary
`Invalid configuration; using defaults.`, exact path, full range and details
`<owned path>:3:24: invalid type: string "λ🙂", expected i64`. Original ingress
bytes, schema, generation, sequence, initialization ordering and bounded
emission clock remain required. Both cases run through two distinct native
processes with repeated exact local-catalog reads,12 captured frames per
process, empty loaded-thread/workspace state, frozen config/catalog/shell
bytes and confirmed owner/Port/native cleanup. No inference or external model
request occurs.

Non-strict fallback intentionally ignores the invalid user file. The new
profile supplies all finite local provider/catalog/startup settings as CLI
overrides, which pinned `app-server/src/config_manager.rs:336–372` reapplies.
It does not override the invalid field or erase/change the file to make
startup succeed. Existing YOLO/plugin launch defaults remain fixed; no policy,
trust or credential error variant is introduced.

`config/src/config_toml.rs:178` declares the scalar;
`core/src/config/mod.rs:1599–1622` maps the typed failure to its original layer.
`config/src/diagnostics.rs:142–169,261–269,315–382` supplies quote-inclusive
range and scalar positions; display53–77 supplies exact details.
`app-server/src/lib.rs:312–338,372–382,535–576` preserves original source
diagnostics through fallback; initialize_processor236–250 emits the warning.
StaticModelsManager reads only the configured owned catalog. Seventeen whole
producer files and four exact canonical nodes are bound in
`/tmp/samgita-v503-config-warning-evidence.json`, SHA256
`3085c4b76db775d7aad4f25eaed1baae86578e7619947443a39f1f03efedf1f7`.
Independent source review found no blocking defect.

The combined focused command with `native_plugin_hook_test.exs` passes **3/0**
at both seeds501432/987654,5.1/4.7s, with strict Credo593 clean. Logs are
`/tmp/samgita-v502-v503-focus-{501432,987654-credo}.log`. The original20s
journey,5s operations,60s case,128-frame/2MiB capture and64KiB frame caps remain.
Final combined-source qualification passes in the
[integrated record](ordinary-mcp-control-ids-qualification.md#final-combined-source-qualification-for-v502v505).

Only physical `ServerNotification.json` owners2418–2421 gain scoped implemented
evidence: TextPosition column/line and TextRange end/start. Exact canonical
hashes remain in the evidence/manifest; no wrapper or alias inherits credit.

## Genuine partial session import, retained functional case

Physical owner2126 is
`ServerNotification.json#/definitions/ExternalAgentConfigImportTypeResult/properties/failures`,
canonical SHA256
`dd7bd4b4730bdc088a51295c9496efb1e6f92ce6122647df5cf9e98fdb58e9f6`.
Earlier evidence covered a mixed profile without actual session import success.
The retained ordinary test
`native_session_import_success_test.exs:310` supplies the stronger independent
journey: genuine detection sees two sanitized sessions, only one owned source
is moved intact to a non-jsonl sibling, and actual native import succeeds for
the other while reporting exact `session_not_detected/session_missing` failure.

Complete progress/progress/completion maps require the independent failure
alongside actual imported-thread success, original import ID/timestamps and
receipt-before-notices order. Combined durable history and real imported
thread records survive confirmed native close and a distinct cold process;
original source bytes remain preserved. No handler-supplied synthetic failure
is substituted for the native validation result. The production import
processor541–557,665–696 owns validation/progress/completion and persistence.
This owning case remains in the reviewed ordinary selection; its actual-native
evidence maps only this exact failure container to scoped implemented. Final
combined-source binding now passes in that integrated record.

Exactly these five physical owners gain implemented evidence. Final integrated
tests, per-node binding and inventory pass. No other import/config field,
full migration compatibility or deployment profile follows. Nothing becomes
verified; prohibited/hosted, A11, unavailable external/OS and full-goal gates
remain incomplete. Rollback removes these test/evidence extensions without
changing persisted platform data; no release, deployment or live credential
change occurs.
