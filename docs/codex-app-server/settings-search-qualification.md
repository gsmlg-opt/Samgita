# Native settings and search continuation

Status: 49 selected physical owners implemented; **full compatibility incomplete**.
Target: Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

Two new idle-thread cases supply explicit reviewer, approval, personality,
multi-Agent, summary and sandbox values. Applied snapshots must equal prescribed
values; explicit sandbox changes clear the previously established named-profile
provenance. Existing helpers require zero provider requests and interactions.
These are saved-setting/serialization checks, not automatic-review routing,
delegation, network access or OS sandbox enforcement. The existing detailed
summary test separately asserts the exact subsequent provider reasoning setting.
Three active-turn reviewer owners still need a controlled approval-routing
oracle and remain missing.

A third case compares omitted, individually null and jointly null search sort
fields against an independent order derived from native raw timestamps, before
and after owned-process restart. Exact metadata assertions preserve known input,
pinned version, explicit nulls and the local runtime environment. Search leaves
saved history bytes and provider counts unchanged. The two positive sort-key
literals and three exact reference nodes also bind their existing semantic
assertions. Known created_at continuation defects remain incomplete; first-page
or full-page success does not qualify that continuation. An exec filter that
only excludes known vscode histories is excluded from this owner index.

## Failed oracle and correction

The first five-file run at seed 501432 had **35 tests / 2 failures**. The unrun
proposal assumed warm `environments == []`. Native search instead enriches a
loaded direct thread with the prescribed local environment, CWD and workspace
roots. The correction asserts that exact independently known record, and null
after a cold restart; it removes no assertion and changes no deadline.

The immutable native path is
[search construction/enrichment](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L2851-L2878),
[loaded settings](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors.rs#L620-L633)
and [loaded-thread selection](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_enrichment.rs#L38-L65).
Direct-thread `canAcceptDirectInput` stays null in this projection; the special
sub-Agent enrichment branch is not exercised. Other nulls are specific to these
controlled nonfork, non-Git, direct histories; they are not universal defaults.

First failure:
`/tmp/samgita-native-settings-search-v32-first-failure-20261025.json`, SHA256
`d4893bfa05bc703408deb60b0a94a4f1605cd145afede69c1b8293f20bcbeb7e`.
The original runner, source snapshot and complete failed log remain preserved.

## Scoped terminal evidence

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-native-settings-search-v32-r1-20261025.py
python3 -B /tmp/samgita-bind-settings-search-v32-20261025.py
python3 -B scripts/codex/inventory.py --check
python3 -B -m unittest discover -s scripts/codex -p 'test_*.py'
git diff --check
```

All six owning files pass **41 tests / 0 failures** at each seed 501432/987654,
zero exclusions: future and active settings, search projections, search/timeline,
local history controls and thread source. Namespace/sandbox prerequisites,
warning-free compilation, driver formatting and strict root Credo pass; both
1,495-file source and executable guards match. Exact commands and logs are under
`/tmp/samgita-native-settings-search-v32-r1-20261025/`.

The binding checks every original row and canonical node/hash, 30 original
source excerpts and unchanged dependency preimages, plus new exact assertions
and both terminal native results. Only 49 rows change; the full manifest matches
the generated expected JSON. Terminal report:
`/tmp/samgita-v32-settings-search-owner-terminal-20261025.json`, SHA256
`380007b5993df20572e798eeeffc043103917fe01865ef1c3548f759fd4ab542`.
The adjacent owner index records exact pointers, test hashes and limits.

Inventory consistency and 37 tooling regressions pass. Contracts become
**4,234 implemented / 2,387 missing**, zero verified; requirements remain
**462 implemented / 12 missing / 11 blocked**, zero verified. Continue remaining
native behavior and complete final-source local/hosted qualification. Shared-helper
regression, retained aggregate/cursor/listener failures, A11, unreachable emitters
and external/backend/OS success remain incomplete. No publication or deployment.
