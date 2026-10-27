# Ordinary plugin read exchange

V515 extends the five existing ordinary turn-plugin cases after `73f9421`.
The target remains stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The unchanged local peer supplies model output only. Codex owns plugin
installation, reading, skill discovery, settings and provider-input construction.

## Behavior and evidence boundary

Each case sends `plugin/read` with its own explicit string ID and captures the
complete original outgoing JSON body and correlated incoming JSON body.
The returned native wire must equal the decoded original response exactly.
Codec round trips preserve that complete response. The pinned request schema
and JSON-RPC response envelope schema are checked; the latter does not qualify
every field of `PluginReadResponse`.

An independently authored ordinary projection specifies plugin identity, local
source path, installation/enabled state, marketplace, description, versions,
interface, keywords, skill metadata and absent optional ordinary components.
Expected values come from the authored source files and pinned conversion code,
never from copying the returned result. Authentication, installation-policy,
availability, sharing and other permission semantics have no expected-value
assertions and receive no qualification credit.

Original installed/enabled checks, the exact installed skill-file bytes, both
real turns, settings notifications, provider-input effects, immutable source
files and confirmed owned-process cleanup all remain required. The new capture
must stay identical after both turns and shutdown. There is no scripted
app-server, response rewriting, retry, sleep, lengthened wait or production
runtime change.

The separate exchange ledger allows exactly two records: an outgoing body up
to 4 KiB and an incoming body up to 64 KiB, with 68 KiB total. Overflow fails
explicitly. Existing four-request turn capture and eight-record settings
capture retain their original bounds. The new explicit RPC deadline is 5 seconds,
stricter than the former generic helper's 30-second Session default; the five
cases retain their 60-second case deadline. No existing wait is lengthened.

## Immutable source

Ten complete producer/conversion files equal the immutable official source
archive. The native [read processor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/plugins.rs#L1112-L1179)
constructs the detail and copies original skill paths. Local sources retain
their original path through `core-plugins/src/loader.rs:1751–1760`; only Git/Npm
sources are install-materialized. Skill namespace/metadata conversion explains
the independently authored name, description and path.

Three referenced schemas match the archive completely. The binary-generated
experimental `ClientRequest` root has 172 branches versus the archive's 105;
only its exact `plugin/read` branch and referenced RequestId definition are
claimed equal to the corresponding archive nodes. No whole-root equivalence is
invented. Source artifact `/tmp/samgita-v515-source-evidence.json`, SHA256
`91128c92db94ef6b3a73731aa86c31ded33f0611fdeddf0a7ff3bc296b60c223`.

The bounded retained-code review finds all 75 original assertion source lines
unchanged and ordered, and 23 retained complete helper definitions equal to
the baseline. Capture branching adds only the separate read exchange and still
passes every event to the unchanged settings recorder. Review artifact
`/tmp/samgita-v515-parent-review-support.json`, SHA256
`b8fb4ea8909cb6613f5a5e3f3a497fd8d5f89b82e83320ff809758264ec456ff`.

## Scoped qualification

The formatted owning file passes **5/0**, seed `501432`, in 7.1 seconds:

```sh
mix test test/native_turn_plugin_list_test.exs --warnings-as-errors --seed 501432
```

The command runs from the independent driver directory in the verified Devenv
environment with the pinned `CODEX_BINARY` and fixed yolo launch configuration.
Log `/tmp/samgita-v515-focus-501432.log`, SHA256
`81e1d67effbdb16296b86e360d97b5e0b6133777827b3962f1bd1b11a6b30ca3`.
Initially formatted module SHA256
`51ec08f3263921f624499fa5d67f29895be0f39b164924e4a8cfc2991237ab73`.

The first strict-Credo run reports two nested-depth findings in the new capture
helpers. Extracting the read-send helper and moving a pure ID calculation
outside the inner branch corrects them without changing assertions, bounds or
deadlines. Both owning modules then pass **6/0** at seed `501432` in 9.4 seconds,
and strict Credo passes across 596 files. Original failed log
`/tmp/samgita-v515-v516-credo.log`, SHA256
`dc4c97a2816d037a7586c7270ade61d965ab9d73a7334b37c2123052f7184a55`;
successful log `/tmp/samgita-v515-v516-focused-static.log`, SHA256
`58624123a322341fad45f17744acd7a8e5c30cf6f40afef99972cafecdaa4ab5`.
Final module SHA256
`3365150cd5f17beefd30f48933a47a7a7ee9feb5acb6009d60717b8c2f517260`.
The [final combined-source functional checks](ordinary-turn-environments-qualification.md#final-combined-source-functional-qualification)
pass all fourteen reviewed steps, including both 125-case native seeds.

The [combined source review](ordinary-turn-environments-qualification.md#final-combined-source-functional-qualification)
independently reconstructs the initially passing module by reversing exactly
the two helper refactorings. All 24 complete producer files, five support
hashes and both canonical schema nodes are bound; only two manifest progress
records change, with all 485 requirements and 6,619 other contracts unchanged.
Review `/tmp/samgita-v515-v516-final-review.json`, SHA256
`befd13c789dd57118a316020eca555660d73df732517b9eb8265a6276fd4a82d`.

Only physical request-ID owner **1479**,
`ClientRequest.json#/oneOf/76/properties/id`, gains scoped implemented
evidence. This exercises a string ID, not every RequestId variant,
all result fields, aliases, other transports or a whole-method qualification.
No entry becomes verified from this case.

Rollback restores this test module and removes its supplemental evidence;
it changes no application runtime, platform database, historical record or
existing process-cleanup behavior. No security, credential, authentication,
authorization, approval or permission test/audit, broad suite or hosted workflow
runs. Those gates, A11, source-unreachable paths, external/OS success, complete
compatibility and release remain incomplete. Nothing is published or deployed.
