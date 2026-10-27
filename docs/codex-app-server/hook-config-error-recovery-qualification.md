# Native hook catalog configuration errors and recovery

V396 starts from `11834a86975ae5fe685d2f46727a73943fba50d6` on `main`.
The new [ordinary test](../../apps/samgita_codex_driver/test/native_hook_config_error_test.exs)
qualifies exactly two `v2/HooksListResponse.json` fields:
**4148**, `/definitions/HookErrorInfo/properties/message`, and **4149**,
`/definitions/HookErrorInfo/properties/path`. Both canonical nodes independently
match SHA256 `bf0b727f7b1c6d07c7312c6c7760fd34302744385611a86804210c77d80b0cc7`.
No alias, surrounding error family or hook execution contract inherits evidence.
Production code, shared fixtures, schemas, configuration and locks are unchanged.

Target: official Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
source archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Ten complete producer/loader/model sources match their immutable archive members.

## Independent error and recovery oracle

After valid native initialization, two baseline calls require complete empty
catalog entries for `[workspace, other-owned-Unicode-cwd, workspace]`, preserving
the requested order and duplicate cwd. Only the exact owned top-level
`model_provider = "fixture"` line changes to a literal nonexistent provider.
All remaining configuration bytes and provider definitions remain intact.

Two calls then require each complete native entry to contain empty hooks and
warnings and exactly one error: `path` equals that entry's **requested cwd**;
`message` equals the independently prescribed literal:

```text
Model provider `samgita-v396-missing-provider-a` not found
```

The correlated JSON-RPC result contains catalog errors; this is not an upstream
JSON-RPC error response.

Restoring exact original bytes must restore the complete baseline twice in the
same native process. A second independently chosen provider name ending `-b`
must produce its own exact message twice, followed by another exact restoration
and two normal results. This detects cached errors and incomplete recovery.
No expected value is copied from an observed response or parser diagnostic.

The live process remains initialized with empty loaded-thread membership,
zero model requests, no thread/turn/item execution events or server interactions,
and no pending, uncertain or gap state. Config replacement is atomic; per-phase
`after` restoration and a separate exit cleanup restore original bytes on
failure. Catalog/provider/journal/source inputs and empty directories remain
exact. Normal/fallback cleanup retains owner completion, closed Port and absent
verified native PID.

Exactly **14** original request/response pairs have unique IDs: initialization,
diagnostics, loaded-list, ten catalog calls, loaded-list. Capture is bounded to
16 frames per direction,4KiB outgoing/64KiB incoming,1MiB total; events256/1MiB,
snapshots1MiB, RPC/initialization5s and case60s. Incoming evidence is original
JSON after Stdio delimiter removal and before Session decoding, with full map
and native-ID equality; no OS-chunk/newline preservation claim follows.

## Upstream producer boundary

The real [catalog loop:613–649][catalog] calls `load_for_cwd` independently for
each input. A load failure directly supplies `cwd` and `err.to_string()` to the
error entry. `config_manager.rs:389–409,447–493` creates a fresh ConfigBuilder;
`config/src/loader/mod.rs:512–631` rereads the current user file. The literal
message is prescribed by the [selected-provider lookup:3929–3951][provider],
also illustrated in immutable `cli/tests/features.rs:72–105` (source read only).
The separate startup fallback at `config_manager.rs:335–352` is not this path.
The fixture uses valid TOML, so parser-derived syntax messages are not assumed.

This is ordinary configuration/discovery behavior. No hook runs or is installed,
activated or granted authority. Security, trust, permissions, credentials and
approval behavior are not exercised. Earlier hook catalog/declaration evidence
has its own scope; it does not substitute for these exact error fields.

## Final-source qualification and limits

Initial focused native **1/0** passes. The final block adds this module to V395's
eight reviewed ordinary modules and passes **9/0** at **501432** and **987654**,
with no exclusions. Scoped format, driver compile with warnings as errors, root
strict Credo557 and offline inventory consistency pass. The unchanged environment
uses Elixir1.18.5/OTP27.3.4.17, test mode, two schedulers, pinned executable and
fixed YOLO ordinary launch setup. No external model/service success is claimed.

Runner/results/log hashes: `/tmp/samgita-v396-run.py` and
`/tmp/samgita-v396-functional-checks/final/`. All **392** guarded sources remain
stable; all **391** prior sources retain their bytes. Initial focused source/log:
`/tmp/samgita-v395-native/hook-errors/`. Final owning test SHA256:
`b105dd72f715d001fb46160ab6c22a8e8fb1d282527bd430eaf22be267e4c602`.
Source/node binding: `/tmp/samgita-v396-source.py` and
`/tmp/samgita-v396-source/evidence.json`, SHA256
`177fa836d313a3e0f26c6dc7cf5b82d66ea50fd2045dc9397a41b644405ce918`.
Final results/guard SHA256 values are respectively
`c725ceb8c10c3d9860b2a950bd242c98b135619811c74f010d7ded2e796a7d19` and
`8c9b881438065bea6578242e19b537cd84089cfa88f73f9bcbbd4fe0d750190a`.
Manifest binding: `/tmp/samgita-v396-bind.py` and
`/tmp/samgita-v396-binding/evidence.json`.

Only **4148/4149** become scoped implemented: contracts become
**5,087 implemented /1,468 missing /66 blocked**; requirements remain
**462 implemented /12 missing /11 blocked**, with **zero verified** in both.
Strict completeness still fails. Other error messages, cold recovery, actual
hook execution, transports, backends and OS profiles remain separate.

Prohibited security/credential/authentication/authorization/permission/approval
tests/audits, mixed broad suites and hosted workflows remain unrun. Existing
checks/gates are preserved. A11, unavailable upstream producers, real external/
platform success, full compatibility and release remain incomplete. No tag,
publication, production migration, service deployment or sibling change occurs.
Rollback removes this test and its two evidence mappings; preserve runtime and
historical data. Continue independently reachable ordinary native gaps.

[catalog]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/catalog_processor.rs#L613-L649
[provider]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/config/mod.rs#L3929-L3951
