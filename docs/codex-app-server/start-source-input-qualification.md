# Native start-source unit inputs

Default validation accepts the pinned native decoder's four `sessionStartSource`
objects on `thread/start`: `{"startup":null}`, `{"startup":{}}`,
`{"clear":null}` and `{"clear":{}}`. Caller maps and bytes remain unchanged.
Actual first-turn provider metadata distinguishes `new` from `cleared`; prior
threads and public cold histories remain intact. Base:
`295fb4e0d7db61d87f13727936ed494e40720ae5`.

## Reproduction, source and correction

The dedicated protocol regression initially reports **5 tests /2 failures**;
the default-validation native case reports **1/1**, rejected locally before
dispatch. A temporary exact copy changes only the request helper to
`validation: :wire`: actual native accepts all four forms, completes four turns
and retains unloaded cold history (**1/0**, 3.0s). The retained default-validation
case then passes **1/0**, 3.1s; structural coverage passes **5/0**. Logs:
`/tmp/samgita-v361-{protocol-red,native-red,native-wire-diagnostic,protocol-green,native-green}.log`.
The diagnostic bypass is absent from final code and tests.

The target remains Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
source archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Ten complete relevant sources byte-match their archive members. Existing serde
1.0.228 source/license/origin and native lock bindings are checked again; no new
crate-download verification is claimed.

`thread.rs:47–53,120–121` declares an ordinary camelCase Startup/Clear unit enum
and nullable input. `common.rs:225–289` buffers the nested request through pinned
serde. Its enum decoder accepts exactly one known map key and its unit decoder
accepts null or an empty map. Both untouched official schema profiles describe
strings only, while both actual transitive request graphs reach this definition
from `thread/start` alone.

An eighth source-derived input descriptor preserves the complete original string
schema as a union branch and adds two disjoint required-key object branches.
Additional keys and non-unit payloads remain invalid. Canonical strings, outer
null/omission, enclosing constraints and existing input supplements remain valid.
Source hashes, exact declarations, stable/full field shapes and singleton graphs
guard generation. Only one new provenance entry is added; all seven earlier
descriptors, every prior pin and all **770 official JSON exports** keep their bytes.
Output schemas and transport/session behavior stay unchanged.

## Native behavior and retained records

The new native case captures eight successful actual sends, four thread starts
and four explicit turns, checking exact original bytes/maps and response IDs.
The assistant-only loopback model supplies fixed text; stock Codex supplies every
app-server response, native identity, initialization value and history item.

Each non-ephemeral Legacy thread gets a distinct native ID/path and genuine
creation notice. Start and the applied summary-setting barrier leave the provider
journal unchanged. Each explicit turn produces one request containing the exact
marker, instructions, native thread/turn association and independently prescribed
`history_initialization`: `new` for Startup, `cleared` for Clear. Live assistant
items and public saved user/assistant turns contain the fixed expected text.

All earlier histories are checked before every start and after every turn,
including both Clear forms. Clear creates another thread; it neither erases prior
records nor submits work. A checked distinct owned process begins unloaded and
reads all four exact histories without loading threads, inference or replay.
Provider journal, configuration/catalog bytes, capture list and empty workspace
remain unchanged. Original eight-frame/4KiB, 256-event and finite deadline bounds
and existing owned PID/Port cleanup barriers remain asserted.

Native qualification negotiates experimental API for its existing diagnostics/
legacy-history setup. Both validation profiles have structural evidence; native
stable-profile execution, source-specific SessionStart hooks and full Startup/
Clear semantics are not inferred. Hook setup crosses the prohibited verification
boundary and remains unqualified.

## Final permitted checks

All eleven final commands pass; no selected test is excluded:

| Check | Result |
| --- | --- |
| Eleven reviewed protocol modules | **52/0**, seeds `501432` and `987654` |
| Twenty-two ordinary driver modules | **124/0 twice**, 174.062/177.968s |
| Driver composition per seed | 95 actual-binary cases and 29 scripted fault cases |
| Outside-umbrella native consumer | **1/0** |
| Scoped format and package compile | Pass, warnings as errors |
| Root strict Credo | Pass on **525** sources |
| Nine Python ASTs / inventory consistency | Pass |
| Before/after executable source guard | **347** stable files; **340** other prior sources unchanged |

The consumer adds local validation of the four forms under both options; its
native journey remains initialization/listing. Runner, source check and evidence
binding: `/tmp/samgita-v361-{run,source,bind}.py`. Exact command arrays, per-command
logs and source hashes: `/tmp/samgita-v361-functional-checks/final/`.
Independent source review SHA256:
`f82ae773a819eb3cf0f89591294a6dc49631004a954bff15a69e3705914389ca`.

Supplemental requirement evidence changes no state or physical schema owner.
The ledger remains **5,038 implemented /1,517 missing /66 blocked** contracts
and **462 implemented /12 missing /11 blocked** requirements, **zero verified**.
Strict completeness exits **1**. Security/credential/authentication/authorization/
permission/approval tests, audits, mixed broad suites and hosted workflows remain
unrun/incomplete under the user's restriction. A11, producerless legacy paths,
external/OS/platform/final aggregate and complete compatibility gates stay open.

Rollback removes the new descriptor/registration/provenance entry, generator
derivation and related tests/evidence together. No database migration, historical
record rewrite, redispatch or task acceptance occurs. No tag, publication,
deployment or live-credential change occurs. Continue with the source-selected
`thread/search.sortKey` object-input discrepancy and independent native ordering.
