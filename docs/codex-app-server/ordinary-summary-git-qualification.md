# Ordinary summaries, Git facts and exact context bindings

This unit follows `50c9f5d` on the existing `main`. It continues the full
compatibility goal against stock Codex `rust-v0.163.0`, commit
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215` and source
archive SHA256 `e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Fixed YOLO configuration is fixture setup. No security, credential,
authentication, authorization, permission, approval or sandbox behavior is tested.
Prohibited checks, audits, broad mixed suites and hosted workflows remain
unrun/incomplete; their retained gates and tests are unchanged.

## Real summary and Git behavior

The new independently bounded native case creates three owned scratch Git
repositories: a committed named branch with an inert origin, a detached HEAD
without an origin, and an unborn repository with an inert origin. Git itself
provides independent branch, commit and remote facts. The standard-library
helper creates files/configuration and runs local Git; it is neither an
app-server nor a model emulator. No remote Git operation or model turn occurs.

The stock executable creates three persisted paginated histories. The driver
reads each legacy summary by conversation ID, absolute rollout path and
relative rollout path, then reads each again in a fresh native process without
loading a thread. The original native JSONL requests and replies retain typed
IDs and validate against their exact pinned schemas. All 30 requests have one
strictly correlated reply; loaded-thread inventories, rollout byte snapshots,
input files and native process identity are checked independently.

A clean diff is empty. After independently authored tracked/untracked Unicode
file changes, real `gitDiffToRemote` output contains both exact changes and the
original commit SHA. A repeated read returns the same diff. No remote fetch or
execution retry is inferred from the method name. Closing both native processes
and the scratch helper requires the existing confirmed cleanup contract.

The first focused run passed the data assertions but failed the unchanged
configuration immutability assertion: ordinary native startup added the three
owned workspace entries. Fixture initialization now supplies those entries
before snapshots are taken. Assertions, deadlines, buffer limits and cleanup
are unchanged. The failed evidence remains at
`/tmp/samgita-ordinary-summary-git-focused-20261028/501432.log`; it is not a pass.
The corrected summary case passes both seeds in
`/tmp/samgita-ordinary-summary-git-v2-focused-20261028`.

## Exact physical contracts

Twenty new summary/Git owners plus nine retained-context owners gain scoped
`implemented` evidence. No owner becomes globally `verified`; identical hashes,
other union branches and neighboring operations receive no transferred credit.

| Owners | Physical selection | Actual evidence and limits |
| --- | --- | --- |
| 3219–3223 | supplemental ClientRequest summary wrapper, typed ID, method/literal and params reference | Original genuine summary inputs by three forms, native replies and persisted histories; supplemental source-derived schema, not official JSON-export coverage. |
| 3224–3228 | supplemental ClientRequest Git diff wrapper and members | Original genuine clean/dirty/repeated inputs with actual local Git/file effects. |
| 3243–3251 | supplemental ConversationGitInfo branch/origin/SHA parents and string/null branches | Named/detached/unborn repositories prescribe all selected values independently. |
| 3256 | supplemental ConversationSummary gitInfo object reference | Original native summary Git object with exact repository facts; no null-timestamp promotion. |
| 153 | ClientRequest EnvironmentSkillsParams.required | Actual positive required skill projection, strict successful registration ID/order and independent executor/catalog/provider-input effects. Registration bootstrap remains opaque; no complete original registration-byte, omission, empty-list or required:null claim. |
| 4112 | standalone usage output estimatedUsageUsdMicros | Both original correlated thread replies contain the independently prescribed 2500000; USD-null remains unqualified. |
| 4128 | standalone usage output threadUsage null branch | Warm/cold profile replies contain an explicitly present null and distinct independently prescribed scalar/daily data. |
| 4488–4489 | standalone nullable usage request object/null branches | Original typed thread-reference and explicit-null profile requests use this physical schema's own definitions; quota-null is a different operation. |
| 2432 | notification Thread.extra nullable parent | Original creation snapshots contain explicit null; nonnull owner2433 remains missing. |
| 2626 | notification item appContext object reference | Original item/started and item/completed context with retained complete context, MCP/provider and cold-persistence oracles; no response-alias credit. |
| 2983 | stable quota notification wrapper | Original finite-provider429 notification, retained quota-data/order/failed-turn/no-replay oracle; no new policy outcome. |
| 2991 | stable app/list/updated wrapper | Original installed-app notification after retained params/data shape checks and before descriptive projection. Reachable aggregate definitions equal the previously checked standalone shape; no eligibility or permission outcome is asserted. |

Each owner keeps its ID, exact pointer and canonical node SHA in the manifest.
The tests pin full schema-file hashes and independently authored node bytes.
ClientRequest uses its experimental root; the last three stable notification
bindings use their stable root, while Thread.extra uses the source-declared
experimental root. That property is absent from the archived JSON exporter;
no whole-root/archive JSON equality is claimed.

Pinned source production paths include `request_processors/thread_summary.rs`,
`thread_processor.rs`, `git_processor.rs`, `apps_processor/installed.rs`,
`account_processor.rs`, `environment_processor.rs`, environment selection,
MCP item construction and notification mapping. Source/archive bindings are
retained in the source-only handoffs under
`/tmp/samgita-ordinary-summary-git-20261028-*`,
`/tmp/samgita-ordinary-data-context-bindings-20261028-*`,
`/tmp/samgita-ordinary-required-skills-binding-20261028-*` and
`/tmp/samgita-ordinary-notification-bindings-20261028-*`.
Runtime evidence comes from the actual repository tests, not these drafts.

## Functional verification

The combined owning block passes **7/0** at seeds501432 and987654, with original
request counts, bounds and cleanup retained. Its evidence is
`/tmp/samgita-ordinary-summary-bindings-focused-20261028`; command times are
14.181/17.325 seconds and original log SHA256 values are
`ac74d04c46d90ca19acecf456e0a6a6fb9d95faa12d123b640596eba07d5c45e` and
`e6e2b8d0c17f24c47eb4f0370d2e00fada73e5ca23533177244db5376a0ee5ff`.
These checks precede final manifest/runner integration and do not themselves
establish a final combined-source pass.

The first frozen combination in
`/tmp/samgita-ordinary-summary-bindings-final-20261028` passes both164-case
repeats, both6-case extension repeats, the outside consumer and other preceding
steps, then stops at strict Credo with four new quoted-JSON readability findings
(15/17 commands executed). Dialyzer and assets are unrun in that failed gate.
The four constants now use readable heredocs with the same canonical JSON
bytes/hashes. No assertion, deadline, request inventory or static rule changes.
The failed gate and its original logs remain retained; subsequent results must
identify the corrected source separately.

The reviewed runner preserves all164 original cases and their320-second
bounds. The new summary case joins only the separately bounded extension group,
now six cases. The corrected frozen combination passes **all17 reviewed
functional steps**, with **1,749 identical guarded source files**, fingerprint
`a18ba235a9d942fd4f844dd9140dae1121692fa90e124453da57dad0e19596dc`.

```sh
MIX_ENV=test ERL_FLAGS='+S 2:2' devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-summary-bindings-v2-final-20261028
```

| Final check | Actual result |
| --- | --- |
| Selected overflow/replay, seeds455834/501432/987654 | 3/0 per seed (16 discovered/13 excluded), unchanged cases |
| Stdio cleanup phases | 4/0, original cleanup ACK/deadline contract |
| Preserved ordinary group, seeds501432/987654 | 164/0 each, 287.467/284.452 seconds command time |
| Separate extension group, both seeds | 6/0 each, 11.024/10.723 seconds |
| Outside-umbrella consumer | 1/0 against the immutable executable |
| Inventory, driver/root compile, format, strict Credo, Dialyzer, assets | All pass |

The results JSON SHA256 is
`42ea93cf77df980d410c74e3e854cf91ac42e5bf634c9ac1f1f569034bb5a8e6`;
source-guard JSON is
`3963ef0046862582d115fe1418848143f1e7500556b78572923c722a373b03a7`;
command-plan hash is
`d8429dedbbaf982f9796d49327709cb9ab0e466cd487cbe3237e5f8db017429c`.
Both original main-group logs remain retained, SHA256
`ddfff11989dc443469ee29b21b859e9ae7231389107287cd1c33de70e91f3abe` and
`b0b95a2133dc6006e79ce4d66900345798cc25b077031b1b8cff603e629a8c98`.
No successful repeat establishes the unknown earlier intermittent cleanup cause.
The full compatibility/security/hosted/release matrix stays separate.

A fresh plain source copy in
`/tmp/samgita-ordinary-summary-local-assembly-20261028` passes production
dependency resolution and compile. The first frozen web install fails because
the task runner incorrectly selects an old cached Bun1.1.42 executable; no
lockfile is changed and no assets/assembly step runs in that failed attempt.
This is a task-runner setup error, not an application/dependency defect.

The continuation at
`/tmp/samgita-ordinary-summary-local-assembly-v2-20261028` first verifies every
one of2,290 copied input files is unchanged, then uses the verified repository
environment's Bun1.3.13 and Tailwind4.3.1. Production compile with
warnings-as-errors, frozen web install, minified assets and `mix release
--overwrite` **all pass**. Root's1,749 guarded source files remain identical.
The copy is not a Git worktree; no service, database or assembled release starts.

The local tarball is
`/tmp/samgita-ordinary-summary-local-assembly-20261028/source/_build/prod/samgita-0.1.0.tar.gz`,
20,079,881 bytes, SHA256
`3421e4a0a22665fe12c0b9279f9ee89ba4fb658ea98a4dfc3bd5f64c0e6b36ea`.
Continuation results JSON SHA256 is
`e7eb5779d28ebb7cc7464e6c46725caeb0dcb41b094b7e7aeb3167c98da9886a`;
source guard is
`82379162e582851be582ec0468b180ef08cc407684755df2945bf75b41cffa70`.
This is local assembly evidence only. There is no publication workflow in the
current repository; CD is disabled. Nothing is tagged, published, released,
started or deployed, and full acceptance gates remain incomplete.

## Remaining work

The ledger is **462 implemented /12 missing /11 blocked requirements** and
**5,726 implemented /759 missing /136 blocked field/variant contracts**, with
zero globally verified. This count is evidence indexing, not a compatibility
percentage or completion claim.

The next installed-thread owner3319 needs its own ordinary `app/installed`
context. Creating the thread introduces another genuine Eager MCP connection
and uncached discovery; the current fixture already consumes its strict
three-initialize/four-tools-list inventory. A successful thread/start reply
alone is not an optional MCP readiness barrier. The source-only prerequisite
report is `/tmp/samgita-ordinary-installed-context-20261028-prerequisite.md`.
No count/bound is relaxed, no failed runtime is substituted and no app/list
alias is promoted. This is fixture work remaining, not an upstream defect.

Ordinary in-flight native WebSocket disconnect/reconciliation and remaining
producer gaps continue under source review. A11's pre-emission prerequisite,
legacy paths without upstream production emitters, real external/backend/OS
success profiles and the original intermittent stdio-cleanup cause remain
unresolved. Existing Plug.Crypto2.2.1 locks, deterministic overflow/replay fix,
populated-database guards and shutdown fixes are retained. Database recovery
and prohibited tests are not rerun here. No release, publication, deployment,
production migration or sibling-service change is claimed.
