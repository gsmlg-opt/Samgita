# Advertised prediction contract without an upstream implementation

The immutable target advertises `thread/prediction/request` and
`thread/prediction/updated`, but its production dispatcher explicitly returns
method-not-found for the request. Its source contains no prediction-notification
producer. Enabled success and native notification emission therefore remain
blocked. A schema, synthetic contract test or another upstream version cannot
qualify those paths for this pin.

Target: `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The source was obtained from the hash-verified archive recorded by
`scripts/codex/fetch_pin.py`. No upstream files are changed.

## Exact source boundary

The [request declaration](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/common.rs#L609-L614)
retains the experimental operation, `threadId` serialization scope and empty
response type. The [notification declaration](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/common.rs#L1964-L1965)
retains the experimental notification. The
[types](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/thread_prediction.rs#L11-L35)
define two required string request identifiers, an empty result object and
`completed {text: Option<String>}` / `failed` notification variants.

The [production request arm](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/message_processor.rs#L1450-L1453)
unconditionally returns `method_not_found("thread/prediction/request is not
implemented yet")`. It neither loads a thread nor schedules prediction work.
This is positive evidence that the enabled dispatcher is unimplemented, rather
than an inference from one unsuccessful test.

An exhaustive Rust source search for
`ThreadPredictionUpdatedNotification|ThreadPredictionUpdated|ThreadPredictionRequest`
finds only the type/wire declarations, the unimplemented dispatcher arm, media
classification and TUI consumer matches. The notification has no constructor or
production send path in this source tree. Its retained schema is not removed.

## Separate evidence layers

`apps/samgita_codex_driver/test/native_prediction_boundary_test.exs` contains:

- Actual pinned process cases for the exact enabled method-not-found response,
  stable capability rejection, and local/native malformed-parameter rejection.
  A real registered thread and unknown identifiers both encounter the explicit
  unimplemented arm. Metadata remains unchanged, no provider request is made,
  no turn/interaction is started and no mutation is retried.
- Explicitly synthetic codec cases for all retained completed-text, null-text,
  omitted-text and failed notification variants. Required identities, invalid
  shapes and unsupported variants are checked. These cases do not establish
  native notification emission or enabled prediction success.

The native cases reuse the existing owned `TurnFixture`: fresh HOME/CODEX_HOME,
temporary workspace, disabled tools/hooks/remote control and a deterministic
loopback Responses peer that must receive zero requests. The fixture closes and
reaps its owned native process before removing scratch files. They require no
Samgita database, Phoenix runtime, external account or model request.

## Executed qualification and status

All validation ran serially through `devenv shell --no-tui --`, with
`MIX_ENV=test` and the exact hash-checked executable above. From the driver:

```sh
mix format test/native_prediction_boundary_test.exs
mix compile --warnings-as-errors
mix test test/native_prediction_boundary_test.exs --seed 501432
mix test test/native_prediction_boundary_test.exs --seed 987654
mix test test/native_configuration_notice_test.exs test/native_account_control_profile.exs test/native_prediction_boundary_test.exs --seed 501432
mix format --check-formatted test/native_prediction_boundary_test.exs
```

At that historical checkpoint, the prediction file passed **5/0** at both seeds (2.4/2.3s): three actual-native
cases and two explicitly synthetic codec cases. The coordinating-owner combined
repeat passed **21/0**, 29.6s. Root warnings-as-errors compile and positional
`mix credo apps/samgita_codex_driver/test/native_prediction_boundary_test.exs --strict`
passed (one file, 69 checks). Runner:
`/tmp/samgita-prediction-validation-20261024.py`; per-command logs:
`/tmp/samgita-prediction-*.log`. All owned cleanup assertions passed.

The initial five-case run had two synthetic failures because validation omitted
the explicit experimental opt-in. One test-only repair supplies that capability
to the retained notification validator, preserving all payload assertions and
deadlines. All three native cases passed initially and finally. No production
code, upstream implementation or enabled-success assumption was changed.

The complete Rust search output is retained locally at
`/tmp/samgita-prediction-source-search.log` (eleven matches). Source SHA256:

```text
96d57b0cb554802211460637993c2e57e27440b1052ca5f12ac79e1bbaf54449  app-server/src/message_processor.rs
7570c5e7ff7b56efd954aace8d3f444599352cb75e5037728dc66bdc7e44d9e8  app-server-protocol/src/protocol/v2/thread_prediction.rs
ee03e7b76763ac658f4af3d36c0c1a26c00dff6ee9256d474dd85fa740143cc3  app-server-protocol/src/protocol/common.rs
```

The request, response and notification entries are **blocked**. Twelve related
schema contracts retain `missing` success requirements with exact native-negative
or synthetic-only labels; no field is promoted. This evidence supplements the
separate source-blocked legacy approvals, MCP progress and file-change output
contracts. Reconcile this advertised-but-unimplemented
surface only through an explicit target/evidence-policy decision. Do not modify
the pin, invent a server emitter or silently waive required success behavior.

## Durable-state precondition repair

The frozen default-driver run at `6dcd341` ended **539 tests / one failure**,
seed `501432`, 507.5s. Its sole failure compared two pre-materialization
`thread/read` responses across a second boundary. Only `createdAt`, `updatedAt`
and `recencyAt` differed. The exact pinned
[read fallback](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L3021-L3033)
uses the loaded snapshot when no stored thread exists;
[snapshot construction](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L6581-L6613)
assigns the current second to all three fields. Equality within one second had
hidden this invalid test precondition. This is not evidence of prediction work
or a driver mutation.

The test now explicitly persists an empty thread with `thread/name/set` before
taking its baseline. Both legacy and paginated histories must retain the entire
response, including all timestamps, and the exact history-file bytes after each
unknown-thread and registered-thread prediction error. Zero turns, provider
requests, pending calls, uncertain operations and interactions remain asserted.
No timestamp is filtered, no clock is rewritten, and no sleep, deadline or
runtime behavior changes. The pinned unimplemented arm and all three blocked
entries remain unchanged.

The repaired file has six cases: four actual-native and two synthetic codec
cases. Together with the five disabled managed-network cases, it passes **11/0**
at each of `501432` and `987654`, 12.5/12.4s ExUnit time, with warnings-as-errors
compilation, formatting, required namespace preflight and strict Credo. Logs and
commands: `/tmp/samgita-native-prediction-network-20261024-attempt02/`.
The preceding attempt also passed both native repeats but failed two new network
test string-style checks; sigils preserve the exact TOML bytes and strict Credo
then passes. The original failed full run remains in
`/tmp/samgita-repair-final-packages-v6-20261024/`. That runner aborted after its
first default-driver seed; remaining final checks were not run by that attempt.
These scoped results require a new combined-source and hosted matrix.
