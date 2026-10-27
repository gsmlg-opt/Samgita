# Native turn-start settings

## Initial thread plugin-list output

V472 freshly executes the existing five-case local-plugin selection file and
binds only canonical output owner **6362**,
`schema:v2/ThreadStartResponse.json#/properties/disabledPluginIds`. The direct
initial native reply must contain exactly `[]` before settings or turns run.
`thread_processor.rs:1636–1638` returns the configuration snapshot's saved list;
`v2/thread.rs:193–195` declares the response vector. The exact canonical node is
`f27565f754f924a35a552321462b8f9c8160cffc642e58704fd250f8292d6364`
in independently checked stable and experimental exports. Both complete
producer/type files match the official immutable archive. Binding
`/tmp/samgita-v472-plugin-start-binding/source.json`, SHA256
`bcc1f2a52cf51ead756e47ee30cf9f614c7c855204f69a54df7ba5d3c6b7a6d7`.

The sole test change adds fixed process-level `approval_policy="never"` and
`sandbox_mode="danger-full-access"` CLI settings, matching its existing thread
setup. The local-plugin startup helper remains intact; the ordinary helper's
permanent `plugins=false` override would suppress the feature being exercised.
No permission/security/approval/credential behavior is tested. The file retains
native plugin installation, causal settings notices, omitted/null/empty/nonempty
turn overrides, exact outgoing turn requests, actual provider-observed plugin
hints, second-turn retention, explicit resume output, immutable inputs and
checked owned cleanup. It uses a local deterministic provider, not synthetic
app-server responses. No helper, assertion, bound or timeout changes.

Focused **5/0**, seed `501432`, 7.1 ExUnit seconds:

```sh
mix test test/native_turn_plugin_list_test.exs --warnings-as-errors --seed 501432
```

Test SHA256 `ff48547ba5ed11771da040d98415550da665b97d6285a486e03119c4dcdbfdc1`;
log `/tmp/samgita-v472-plugin-overrides-501432.log`, SHA256
`b43707cd7fdb40a4fa2395dc03c6dcaa74b7638cfaf487651019830a3f1cfd32`.
The ordinary runner now selects 44 files/73 cases. Final combined source passes
**73/0** at each seed `501432`/`987654` (119.307/119.210 seconds), three selected
WebSocket cases at each of three seeds, and the outside consumer **1/0**. All
**14** reviewed checks pass, including inventory, format, warning-free compile,
strict Credo, forced Dialyzer and assets. Assets retains the unrelated Bun version
warning with exit zero. All **1,660** guarded source hashes remain identical.

Final commands/logs `/tmp/samgita-ordinary-v472/`; results/source SHA256
`50a30479d227d8650a9f3594cfe88e46d25b9deae55b0fac7c95ff35e646f934` /
`4290f4878ca496585fd683334d52e1d000c2aa7e9b9e732b5f2d7381c3107d47`;
plan SHA256 `80517c8d942bef6b21d9e89d0358bd3d51e8cda4f189930f0656defff3c68330`;
reviewed fingerprint
`d8327ededacdfa42acc35d7a0116768a85ea7d8d74981a5988985e096f81f6cc`.

This is a decoded correlated reply oracle, **not original incoming-byte proof**.
No `ThreadStartParams` input field, nonempty startup output, missing/default
decoding, alias or complete method/schema is newly qualified. Earlier turn-input
owners below remain unchanged. Contracts: **5,310 implemented / 1,199 missing /
112 blocked**; requirements remain **462 implemented / 12 missing / 11 blocked**,
zero verified. Prohibited/broad/hosted, A11, unavailable native producers,
external/OS/backend/full-goal and release gates remain incomplete. No publication
or deployment. Earlier records retain their original scope and results.
Continue original-frame and causal-order qualification of ordinary settings,
hook and skill change notifications; retain excluded mixed-file profiles.

## Earlier turn-input scope

This unit qualifies selected `turn/start` personality and plugin-list behavior
against stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The driver uses actual native stdio; an owned loopback Responses fixture supplies
deterministic model output. It does not generate app-server responses or notices.

## Observable behavior

| Field | Native evidence |
| --- | --- |
| `personality` | Two initial values, `none` and `friendly`, each run nine turns covering omission, explicit null, `pragmatic`, `friendly`, `none` and subsequent omission/null retention. Bounded outgoing capture preserves presence and exact values. An independent summary-only update yields the public settings snapshot after each completed turn; it cannot apply a missing personality value. Exact provider base instructions retain their original thread construction despite metadata changes. Invalid local/native enum variants preserve their distinct errors and produce no turn/provider request. Final history contains exactly the nine correlated completed turns. |
| `disabledPluginIds` | Five cases cover enabled/disabled baselines, omission, null, empty list and a nonempty list. A real local plugin is installed through the native API. Exact request IDs/maps, live settings notices, plugin hints in actual model input and a second omitted-list turn establish effective selection and retention. The public resume result reports the resulting list; input/plugin/config bytes and the two-request provider journal remain unchanged after closure. |

The pinned [turn processor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/turn_processor.rs#L802-L936)
passes the optional overrides through the native settings path. The pinned
[snapshot comparison](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/thread_state.rs#L224-L228)
emits a settings notice only for a change. The plugin test therefore establishes
an enabled baseline through a causal `[P]` then `[]` transition, waiting for each
exact snapshot. An ACK alone or a no-op update is insufficient evidence.

Both files keep bounded capture and fixed completion/snapshot deadlines. The
tests collect functional completion locally because the retained general helper
also contains an approval assertion. Existing helpers and tests remain unchanged.
No security, permission, approval, authorization or credential tests run in this
unit, following the user's current verification restriction.

## Corrections and integrated checks

Original candidate failures are retained: the personality wrapper needed explicit
owned transport cleanup, followed by explicit experimental opt-in for settings
snapshots; the plugin fixture needed lazy-history-aware initialization, an empty
provider journal, its synthetic model catalog and causal non-no-op baselines.
These were fixture/oracle corrections. No production driver, upstream binary,
deadline or existing assertion changed to obtain a pass.

The final integrated block runs from `apps/samgita_codex_driver`:

```sh
mix format --check-formatted test/native_turn_personality_test.exs test/native_turn_plugin_list_test.exs
mix compile --warnings-as-errors
mix test test/native_turn_personality_test.exs test/native_turn_plugin_list_test.exs --warnings-as-errors --seed 501432
mix test test/native_turn_personality_test.exs test/native_turn_plugin_list_test.exs --warnings-as-errors --seed 987654
```

Both native runs pass **7 tests / 0 failures**, in 14.113/14.018 command seconds,
with Elixir 1.18.5/OTP 27. Root `mix credo --strict` passes on 454 source files.
The source guard matches all 225 captured driver/protocol/helper/fixture/lock
files before and after. Commands, cwd, exit codes, logs and source hashes are in
`/tmp/samgita-v151-turn-settings-checks/`; results/source SHA256 are
`947fdfac7746db2bd1d2d058e88aacb6c29814d4c88e8718c7d9a32fa689c30e` /
`462045db03971bca5f9663526e75e27ceebc03f6958ac401d9a3f8c7ffe32671`.
Source-only reviews are retained in v148/v149; the original failed candidates
remain in v143/v144 and the successful bounded plugin recovery in v146.

Exactly four direct physical owners become **implemented**: indices 6518 and
6531–6533, `TurnStartParams.disabledPluginIds` and `personality` plus its two
alternatives. No response, settings, history or alias sibling inherits evidence.
Contracts are **4,541 implemented / 2,021 missing / 59 blocked**; requirements
remain **462 implemented / 12 missing / 11 blocked**; both have zero verified.

This is live-thread Linux/stdio evidence with local synthetic dependencies.
It does not qualify real model style, cold/restart behavior, remote plugin
success, other transports/platforms/backends, full compatibility, publication,
deployed behavior or A11. Broad suites/hosted workflows containing prohibited
tests are unrun on these sources; retained gates are not converted to success.
