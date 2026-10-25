# Native diagnostic process identity

This binds one previously missing direct field, physical contract **5071**:
`ServerDiagnosticsResponse#/definitions/ServerDiagnosticsProcess/properties/id`.
It uses existing meaningful assertions in the completed functional matrix;
no new test or runtime behavior is introduced.

The immutable target is Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The pinned
[diagnostics handler](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/diagnostics.rs#L5)
returns the actual diagnostics snapshot's process ID. The
[Linux snapshot](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/diagnostics/src/lib.rs#L142)
uses std::process::id(), preserving the schema's required u32. Four complete
production files match the immutable archive, the experimental export matches
pinned provenance and the exact node digest matches inventory; source evidence
is in `/tmp/samgita-v241-functional-owner-candidate/`.

The actual
[`native_id/2` assertions](../../apps/samgita_codex_driver/test/native_timeline_position_values_test.exs)
read this exact response field, require an integer and independently hash
`/proc/<returned-id>/exe` against the immutable executable. The cold process must
have a different native ID; checked shutdown requires the corresponding process
to disappear. Thus a merely well-typed arbitrary number or the fixture/driver
PID cannot pass. Existing command/process and fork/resume cases corroborate the
same effect, but this row is bound directly to the timeline test's own assertions.

The [timeline qualification](timeline-position-values-qualification.md) records
the completed twenty-three-file matrix: **38/0 at both seeds 501432 and 987654**,
warning-free compile, scoped format, strict Credo, outside consumer **1/0**,
Python syntax and **248 unchanged source files**. Test SHA256
`c190c2c2046d511d642a34f50081b2df4157673e9d06dbcd4f9a0d802108697d`
matches that final guard and the current source. This documentation-only binding
does not invalidate or rerun those tests. Exact logs/source are in
`/tmp/samgita-v239-functional-checks/functional/`; the adjacent
`manifest-binding-diagnostics.json` records the original/current row.

Only field 5071 gains scoped implemented evidence. No memory footprint, gauges,
diagnostics container, whole method/response, other OS/remote process or alias
inherits the result. Inventory consistency passes; all 485 requirement records
and schema identities/hashes are preserved. Contracts become **4,703 implemented /
1,859 missing / 59 blocked**; requirements stay **462 implemented / 12 missing /
11 blocked**, zero verified in both. Prohibited checks, broader/hosted matrices,
full compatibility, A11 and external/platform acceptance remain incomplete.
No release, publication, production migration or deployment occurs.
