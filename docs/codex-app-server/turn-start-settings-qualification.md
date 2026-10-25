# Native turn-start settings

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
