# Native ordinary quota literals

This continuation follows `af58e40076de4a41e014442e45a69d60a6701f1f` on
`main`. It targets official Codex `rust-v0.163.0`, source commit
`83086188ae0614bd882818ff1aa23f3194962012`, combined executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
YOLO is fixed launch configuration. No security, credentials, authentication,
authorization, approval, sandbox or permission behavior is tested. Mixed broad,
audit and hosted gates remain unrun; full compatibility remains incomplete.

## Dependency data and original native output

The ordinary provider fixture gains one finite optional `--reached-type` input.
Its omitted default remains `rate_limit_reached`; the original case, original
fixture argv, exact generic error message and all bounds remain. Four separately
tagged cases use separate roots, providers, captures and actual Codex processes.
The fixture supplies only one local Responses429, never app-server envelopes.
No real account, workspace credit state or entitlement is required or selected.

Each case sends one ordinary text turn to the actual binary. The provider emits
the selected `x-codex-rate-limit-reached-type` header, fixed quota windows and
`{"error":{"type":"usage_limit_reached"}}`. Native code parses that dependency
data, emits `account/rateLimits/updated`, then emits the error and failed turn
in that exact order. The native success reply to `turn/start` is distinct from
its eventual failed execution. Neither result represents Samgita Task acceptance.

The oracle requires exactly one provider POST, prescribed model/input and
thread/turn metadata, a native quota value matching the selected literal and
an original `usageLimitExceeded` error with no retry. New literal-specific
message text is opaque nonempty data, preserved exactly between original raw
error and completed-turn maps; the retained base case still requires its exact
generic text. All three original notifications preserve native timestamps and
complete payloads through capture and codec. No scripted peer supplies them.

The outgoing method sequence is prescribed: initialize/initialized,
server/diagnostics, loaded/list, thread/start, turn/start and loaded/list.
All six request IDs have exactly one matching original reply; there is one
turn/start. Session ends ready with no pending interaction, uncertainty or gap.
Checked native/helper/provider shutdown, completion acknowledgement, closed
Ports and absent owned PIDs precede disposable-root removal. No provider or
protocol mutation occurs during shutdown. Existing cleanup code is unchanged.

## Exact physical ownership

Only these four `ServerNotification.json` physical owners become implemented.
The test hashes the owning stable root, compares its entire reached-type
definition and selected index to the experimental export, and binds the exact
canonical literal bytes with their independent pinned hashes. Canonical JSON
includes the trailing newline. Equal definitions alone do not qualify aliases.

| Owner | Pointer suffix | Literal | Canonical SHA256 |
| --- | --- | --- | --- |
|2352|`/RateLimitReachedType/enum/1`|`workspace_owner_credits_depleted`|`418e3888e855c21751ee536b69d28e353cd84d2b119bb80010d5fa02466999ac`|
|2353|`/RateLimitReachedType/enum/2`|`workspace_member_credits_depleted`|`76c10aa6691ddd9ebcc1c61d727f07d6cb268d3918a41fbfa29788dc29cb9a75`|
|2354|`/RateLimitReachedType/enum/3`|`workspace_owner_usage_limit_reached`|`153f564270c13fadf038316276b57cdb213ebf8b47f783fe540db8647bc71c33`|
|2355|`/RateLimitReachedType/enum/4`|`workspace_member_usage_limit_reached`|`dbb97eef870378cb1707637f30d2610ef0d208c7a410054c8305805abf9c6467`|

Each full pointer starts with `/definitions`. Stable root SHA256 is
`8e719512bc26bb3871fcf7b378b79abf912d82787609c0ad418b71f179d0883f`;
experimental root is
`c626079776d401d358a8791b74cfe6c978d18aabbb78477ce7bd710a79779bc1`.
Fixture SHA256 becomes
`f64f18603635d448e9981e1a20d8793c1f1a75820bedac30666fb8c8e2465b5f`.
The separately reviewed draft SHA256 was
`99f9aaf3226feab02a09c0fff67bd4bb3fc43c8250d1791586154ced53286ca8`;
formatting and stable-root assertions are included in final qualification.

Immutable producer route:

- `codex-api/src/rate_limits.rs:188–193` parses the header as dependency data;
  `protocol/src/protocol.rs:2490–2510` defines the five exact strings.
- `codex-api/src/api_bridge.rs:190–205` maps429 usage-limit data and its header
  into the typed snapshot. No claimed Agent capability or project role is used.
- `core/src/session/turn.rs:1797–1802` updates the snapshot before returning
  the error. `core/src/session/mod.rs:5146–5186` emits the token-count event.
- `app-server/src/bespoke_event_handling.rs:1587–1613` emits the quota
  notification. `app-server-protocol/src/protocol/v2/account.rs:701–729` maps
  the five values without replacing their meaning.

This is finite data-preservation evidence, not backend credit/role/policy
enforcement qualification. Nonnull notification `individualLimit` owners2360
and2395–2398 remain missing: ordinary header and WebSocket producers construct
None. A successful read-response mapping is a different producer. The existing
wrapper/reference/base literal owners and all aliases gain no new credit.

## Verification and limits

The first focused source runs5/0 twice at seeds501432/987654 in5.864s/5.912s,
with format and strict Credo passing. Evidence directory is
`/tmp/samgita-quota-literals-focused-20261029`; native log SHA256 values are
`c823478c9fcce39924b7ae5a6810eca0db6a25c17f1bcb91f573bc82b5577eec`
and `ab26b7df657fa4f044d641f25de13c8ee8f02bbd379e9b78cc2b1d12074a52fb`.
These runs precede the additional stable-root binding; final combined results
below must cover that assertion. The source-only review finds no actionable
issue and does not count as runtime acceptance.

The metadata patch generator initially stops before any repository write because
its canonical round-trip omitted `ensure_ascii=False`. Inspecting that diff
identifies only escaped existing Unicode; retaining the repository's canonical
form corrects the generator without rewriting unrelated content.

The reviewed combined selection preserves all original165 main cases and320s
bounds. Its independent extensions grow17 to21 with the original120s bounds.
No prior assertion or timeout is weakened.

## Final combined source functional qualification

```sh
MIX_ENV=test ERL_FLAGS='+S 2:2' devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-quota-literals-combined-20261029
python3 -B /tmp/samgita-quota-literals-binding-20261029.py
```

All **17 reviewed steps pass** against1,762 identical before/after guarded
hashes, including the final stable-root assertions. Main165/0 passes twice in
289.170s/285.905s within the original320s bounds. Extensions21/0 pass twice
in35.075s/34.825s within120s. Three selected WebSocket seeds, four cleanup
cases, independent outside consumer1/0, inventory, driver/root formatting and
compilation, strict Credo, Dialyzer and assets build pass. No prohibited test,
audit, broad mixed suite or hosted workflow runs.

Reviewed fingerprint is
`1d9a8ab13bc6e1e3795f949ce07708fa75c3d4d8d96abd831da22a1be2627d8d`.
`results.json` SHA256 is
`6e386d668c461c056599f6db2ad07a0eb8dcbe76fa57d3d8925c3d9e04f90a3e`;
`source.json` SHA256 is
`61225e612bf56b10c95707d946a89a524cf5aaf12f8438ec7df9b5ad9519318f`.
Binding evidence is
`/tmp/samgita-quota-literals-binding-20261029/binding.json`, SHA256
`a7270ca5084b702046bc1f554bddafa5b3bd012aa2958563e62751ad267ecc16`.
It verifies all1,748 other tracked guarded files against baseline and ten
ignored static outputs against the preceding successful snapshot, all7 complete
causal source files against the immutable archive, every command/log/bound,
the byte-identical original test body, and exactly four changed physical owners.
All485 requirements and6,617 other schema contracts remain exact.

Scoped totals are **5,752 implemented /733 missing /136 blocked
contracts**, unchanged462 implemented/12 missing/11 blocked requirements,
zero globally verified. Only the four named states change. Production code,
schemas, locks, shared cleanup,
database guards and historical records are unchanged. A11, prohibited/broad/
hosted checks, source-bound legacy/nullable branches, external/OS acceptance,
complete compatibility and release remain incomplete. No publication or
deployment is performed.

Next: implement and qualify the source-supported ordinary existingCall input
owners653–656, with prescribed callId routing, inert sideband control lifecycle
and warm/cold history. The separately prepared draft is not yet native evidence;
it cannot claim real client-negotiated media or external service success.

Rollback restores this test/fixture extension, the four evidence records and
the reviewed runner count/fingerprint. There is no runtime or data migration.
