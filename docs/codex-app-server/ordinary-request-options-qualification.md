# Ordinary request-option validation repair

This continuation starts from `dd2561e39f63071a0689ff8d6ed2bd6ee7b92c8e`
on `main`. The compatibility target remains official Codex `rust-v0.163.0`,
source `83086188ae0614bd882818ff1aa23f3194962012`. It repairs a local driver
failure, without changing upstream, protocol schemas, platform persistence or
the full compatibility requirements.

## Reproduction, cause and behavior

The ordinary public call below accepts a list that is not a keyword list:

```elixir
Session.request(pid, "thread/list", %{}, [{:effect}])
```

Previously `submit/5` checked only `is_list/1`, then called `Keyword.get/2`
before the later dispatch guard checked `Keyword.keyword?/1`. The malformed
one-element tuple raises `CaseClauseError`, terminating the Session. Direct and
native initialization and native ordinary requests reach the same defect.
The pre-fix regression run exits 2 with **3 tests /3 failures**, each showing
that exact exception in `Keyword.get/3` and `Session.validate_effect/2`.
No upstream process is involved in this reproduction.

Initialization, native requests and request submission now validate the option
container before reading any keyword, allocating a request ID or dispatching.
Direct initialization also checks before changing phase/capability state.
Invalid containers return `{:error, %Error{code: :invalid_options}}` on the
same live Session. A non-list initialization option now receives this option
error rather than the unrelated initialization-state error.

Three new explicitly scripted cases cover malformed tuples, an atom list,
string-key tuples and a map. They require no outgoing request, unchanged
connection generation/state, later explicit initialization and reuse of the
rejected native initialization ID. The ready-state case holds an ordinary
`thread/list`, submits invalid direct/native calls, then settles the original
read exactly once and uses the rejected native read ID successfully. No gap,
uncertainty, reconnect, automatic retry or manufactured native result is used.

The production diff is restricted to request-option validation. Notification
and server-interaction handling, transport ownership, process cleanup, database
guards, historical records and both patched Plug.Crypto locks are unchanged.
The bounded read-only transport review established no further actionable
framing/lifecycle defect; it is not runtime acceptance.

## Focused qualification

Run from the repository root with `MIX_ENV=test ERL_FLAGS='+S 2:2'` through
`devenv shell --no-tui --`, changing to `apps/samgita_codex_driver` for Mix:

```sh
mix test test/ordinary_request_options_test.exs --warnings-as-errors --seed 501432
mix test test/ordinary_request_options_test.exs --warnings-as-errors --seed 987654
mix format --check-formatted lib/samgita_codex_driver/session.ex test/ordinary_request_options_test.exs
```

After the repair, **3/0** passes at each seed. Logs are retained as
`/tmp/samgita-ordinary-options-red-20261029.log`,
`/tmp/samgita-ordinary-options-green-20261029.log` and
`/tmp/samgita-ordinary-options-focused-987654-20261029.log`. The red log is
preserved; no failure wrapper turns it into a passing check.

The first scoped strict Credo invocation exits 4 on a new single-clause `with`.
An equivalent `case` fixes that readability issue without changing validation
or weakening an assertion. Its original log remains
`/tmp/samgita-ordinary-options-credo-20261029.log`. Final scoped strict Credo
passes with no issues across the two changed Elixir files; log SHA256 is
`908838e9a3aca26e2ea6c69452f2a4e83c447d84169fc5b75476316693128e24`.
The final combined run below covers the corrected branch.

The reviewed ordinary selection adds this one file to its independent
extensions, **23 to 26 cases**, retaining the original 120-second bound. The
main 166-case argv and 320-second bounds, WebSocket seeds and cleanup selection
remain unchanged. No prohibited test is added or enabled. The extension count
means 23 retained native cases plus 3 new scripted cases, not 26 native cases.

## Final combined-source functional qualification

From the repository root:

```sh
MIX_ENV=test ERL_FLAGS='+S 2:2' devenv shell --no-tui -- \
  python3 -B scripts/codex/check_ordinary.py \
  --output /tmp/samgita-ordinary-options-combined-20261029
python3 -B /tmp/samgita-ordinary-options-final-binding-20261029.py
python3 -B scripts/codex/inventory.py --check --require-verified
```

All 17 reviewed functional steps pass against **1,763 identical before/after
guarded hashes**, fingerprint
`3786e66b12cd1f24ed6d87fbffb4ed867dda75aa4f7b0f2cdb91f6ce3e61cca9`:

| Check | Final result |
| --- | --- |
| Existing main selection, seeds 501432/987654 |166/0 each; 264.566s/277.083s, original 320s bounds|
| Extensions, same seeds |26/0 each; 37.129s/37.037s, original 120s bounds; 23 native plus 3 scripted|
| Selected WebSocket overflow/replay, seeds 455834/501432/987654 |Each reports 16 tests, 0 failures, 13 excluded|
| Retained stdio-owner cleanup |4/0|
| Actual-binary outside consumer |1/0, isolated from umbrella dependencies|
| Driver/root compile and format, inventory consistency, strict Credo, Dialyzer, assets |All exit 0|

A final explicit `mix format --check-formatted` on Session and the new test
also exits 0 in the same verified environment. Its log is
`/tmp/samgita-ordinary-options-final-format-check-20261029.log`, SHA256
`e922907f5b37fe175acdefc35a03960a7546b6fbdac42bf8013223c1732a4c80`.
The new client-option reproduction log retains 3/3 failures, SHA256
`a09305566f0ce86b4cbc00d234dfdf1cb5caea13fe137fbbb02de031bb11e422`.

The binding verifies all 17 commands, original deadlines, expected counts and
log hashes. All 1,759 unaffected original guarded paths match the preceding
successful functional source; only Session, the two manifest supplements and
runner change among old paths, with one new test. All 6,621 schema contracts
and every entry's state/transport coverage remain exact. The driver README now
documents the keyword-list option contract.

| Artifact | SHA256 |
| --- | --- |
| Final `results.json` |`0da55a33223e9fe82fb0b3e6f02e19272f70f5fde4ea2f4bf83bbe9bbe42db7b`|
| Final `source.json` |`9e7d6cfb6d12d1bbb3e0300b4ba363e891ce96251ad12c8364aae1b22776f92e`|
| `/tmp/samgita-ordinary-options-final-binding-20261029.json` |`8645f941bdd963e13c8aa0cfd09b4be344bcb5dfcd07ca856ec7eacdfb347f45`|

The separate strict completeness command exits **1** because unverified
requirements remain. Its original log is
`/tmp/samgita-ordinary-options-completeness-20261029.log`, SHA256
`8c14de37787f2fa05e8a25dbe96cc1932f9d716f451c257ce98ba73ecbeea0cd`.
This required failure is retained independently of the passing functional run.

A bounded read-only continuation review of remaining ThreadListResponse and
ThreadSearchResponse branches found no established genuine producer plus
available permitted fixture awaiting qualification. Owner5702 still requires
resolution of the pinned created_at precision defect. Owners 6107/6109/6110/
6120/6121 require genuine exact stored source provenance; current compaction
and memory producers do not establish those branches. See
[reverse-pagination evidence](ordinary-reverse-timestamp-qualification.md) and
[output prerequisites](ordinary-output-source-prerequisites.md). This review
adds no runtime or field-state credit and does not imply that a mock can close
the remaining acceptance.

## Local production assembly

```sh
MIX_ENV=test ERL_FLAGS='+S 2:2' devenv shell --no-tui -- \
  python3 -B /tmp/samgita-ordinary-options-local-assembly-20261029.py
```

A plain source copy under `/tmp` builds in a sanitized production environment,
without creating a branch/worktree or starting a database, endpoint or release.
All five serial steps exit 0 with their original bounds: `mix deps.get --only
prod`, `mix compile --warnings-as-errors`, `mix bun packages`, `mix assets.deploy`
and `mix release --overwrite`. Bun 1.3.13 and Tailwind 4.3.1 are independently
recorded. The 2,321-file input manifest includes the new test/document and
excludes the unrelated untracked user prompt. All 1,763 guarded hashes remain
identical through assembly and match the functional run. Documentation edits
after copying do not change executable inputs.

Evidence is under `/tmp/samgita-ordinary-options-local-assembly-20261029`:

| Artifact | SHA256 |
| --- | --- |
| `results.json` |`2d8d828817420ff3018878deda8afa3c5cd50a56e7f470aa38a4e9e672012571`|
| `source.json` |`3d18e45668c38ede46c7a54c44881c340fe7b2bf62fe4937487f5f9b05b1b8f0`|
| `copied.json` |`c60c95dc34796f4fcb53c5344763f5bfdbb9b9f949351eae99290218da0e0cbd`|
| Local `samgita-0.1.0.tar.gz`, 20,073,947 bytes |`9d242d01b8c89af5deca9250630b1c2a9ba6ebaaed1c5a116d4892b62d717d56`|

The tarball is assembled locally only: it is never started, published or
deployed. This is not an enabled publication workflow or a passing full release
gate. The strict completeness failure and prohibited/unavailable checks remain.

## Acceptance boundary and rollback

Only evidence/tests/limitations for the existing
`lifecycle:bidirectional-correlation` and `lifecycle:initialization-order`
records gain this scripted regression. Their states, schemas and transport
coverage stay unchanged; no physical field owner or global verified state is
promoted. Counts remain 462 implemented/12 missing/11 blocked requirements,
5,756 implemented/729 missing/136 blocked contracts and zero globally verified.

No security, credential, authentication, authorization, approval, sandbox or
permission test or audit is run. Ordinary native launches in the retained
selection use fixed YOLO configuration. Broad/hosted checks, A11, missing
genuine producers, the upstream created_at defect, unavailable real service/OS
profiles, full compatibility and release remain incomplete. The pending
target/evidence-rule question is not answered by this client-side repair.

Rollback reverts this scoped production fix, test, two metadata supplements
and reviewed selector/fingerprint. There is no database migration or replay.
No publication, production migration or deployment occurs.
