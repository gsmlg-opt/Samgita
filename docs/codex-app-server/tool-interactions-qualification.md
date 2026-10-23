# Native user input and dynamic tools

This bounded profile targets Codex `rust-v0.163.0`, source commit
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The actual executable produces every app-server request, response and notification.
Only its model peer is synthetic. No schema forwarding or synthetic app-server
emission counts as native behavior evidence.

User input and dynamic tool calls are distinct interactions. User input replies
contain an answer map, with string arrays for each question. Selecting an option,
providing Unicode/freeform Other text, multiple answers and an empty map all use
that same representation. There is no separate user-input denial enum. An
explicit client RPC error becomes an empty answer map upstream. Plan mode emits
`isBlocking: true`; enabled Default mode emits false. Both still await a response
in this pin, and neither emits an automatic-resolution deadline. Synchronous
questions require nonempty options and normalize `isOther` to true. A freeform-only
question is rejected before a server request, rather than emitted with missing
options. The synthetic secret flag is accepted by the upstream parser even
though the model-facing tool schema does not advertise that argument; the test
uses no real secret. The async user-input tool is a different agent-message flow
outside this profile.

Dynamic tools carry an optional namespace, a tool name, arbitrary JSON arguments
and a native call ID. Replies contain `success` plus `inputText`, inline
`inputImage` and inline `inputAudio` content items. Structured JSON is carried as
text; there is no arbitrary structured-object content variant. Native item
status distinguishes successful and failed tools even when the turn completes
successfully. A single text item becomes a plain string in the follow-up model
request; empty and multimodal content remain arrays. The success flag is internal
metadata and is not a separate model-output field. Remote HTTP image URLs and
non-data audio URLs produce explicit failed native tool results without fetching
the URL. Core cancellation has an error string, but this pin's v2 dynamic item
schema does not expose that field.

`Session.respond/3` reports transport send, not native response acceptance. User
input emits `serverRequest/resolved` before normal turn completion; this is
resolution evidence, not approval or Task acceptance. Ordinary dynamic replies
emit no corresponding resolution notification. Their outcomes remain
`sent_unconfirmed`, including after a completed item or turn. Disconnect turns
unconfirmed sends into uncertainty; reconnect never resends them automatically.

The actual-native regression reproduced a pending dynamic handle remaining active
after an interrupted native turn. The repair records thread, turn and call
identity and retires only unanswered current-generation dynamic interactions on
matching terminal dynamic items or terminal turns. It cancels their timers,
rejects late responses with `stale_interaction` and sends no response. It does not
create an outcome, fabricate a resolution notification, modify sent outcomes or
confer work acceptance. Other request families retain their native resolution
rules. Separate unit cases cover mismatched thread/turn/item/type/status,
reconnect generations, user-input isolation and preservation of unconfirmed
outcomes.

The profile covers eight native cases:

1. Plan-mode multiple questions/options, `isOther` normalization, a synthetic
   secret flag, exact Unicode/freeform/multiple answers, and resolution ordering.
2. Enabled Default nonblocking mode, explicit empty answers, disabled-feature
   rejection and missing-options rejection before app-server interaction.
3. Invalid local reply rejection without consuming the handle, followed by an
   explicit client error and the native empty-answer fallback.
4. Explicit namespace, nested JSON arguments, exact started/completed correlation,
   JSON text/image/audio replies and native model-content conversion.
5. Explicit failure, empty success and RPC-error fallback, with distinct tool
   results and preserved unconfirmed response outcomes.
6. Native remote image/audio rejection and an owned HTTP sentinel proving neither
   rejected URL was fetched.
7. Interrupted held dynamic/user-input requests, terminal evidence, stale response
   rejection, no fabricated acknowledgement and no extra inference.
8. Borrowed UDS reconnect and explicit thread resume, replay of the original
   native request ID/body with a fresh driver handle, rejection of old handles,
   one explicit response and survival of the shared native server after closure.

The helper enters a private user/network namespace, verifies only loopback and no
default route, and hash-checks the executable. The test independently checks its
namespace evidence. All home/config/tmp/workspace/model data is disposable;
environment inheritance is allowlisted. Provider/account URLs point at the owned
synthetic peer; the fixture requests no commands or external tools. The remote
URL sentinel is another owned loopback listener inside that namespace. Missing
isolation prerequisites fail explicitly without a host-network fallback. Cleanup
checks native/controller/namespace-owner process reaping. Borrowed client closure
does not terminate the service's native process.

Pinned sources relative to `codex-rs/`:

| Contract | Source |
| --- | --- |
| Dynamic-tool and user-input wire variants | `app-server-protocol/src/protocol/v2/item.rs:1663-1810` |
| User-input normalization and mode rejection | `core/src/tools/handlers/request_user_input_spec.rs:93-125` |
| Root-thread/mode handling and blocking semantics | `core/src/tools/handlers/request_user_input.rs:45-151` |
| User-input native resolution and error fallback | `app-server/src/bespoke_event_handling.rs:1642-1718` |
| Dynamic requests without a resolution callback | `app-server/src/bespoke_event_handling.rs:1090-1118` |
| Media validation and RPC-error/turn-transition handling | `app-server/src/dynamic_tools.rs:17-112` |
| Dynamic item lifecycle and cancellation | `core/src/tools/handlers/dynamic.rs:142-180,230-284` |
| Native v2 dynamic item omits core error text | `app-server-protocol/src/protocol/v2/item.rs:360-370,948-963` |
| Single text versus content-array model output | `core/src/tools/context.rs:578-589` |
| Media conversion and internal success metadata | `protocol/src/models.rs:2267-2305,2365-2375` |
| Turn interruption cancels native requests | `app-server/src/bespoke_event_handling.rs:1208-1225` |
| Retained request replay and one-shot response callback | `app-server/src/outgoing_message.rs:452-529,588-602` |
| Explicit resume replays requests after its response | `app-server/src/request_processors/thread_lifecycle.rs:920-970` |

Validation on 2026-10-24 used `main` checkpoint
`1f1dc5ec27f4cfb07efb4502eb1152968b81c98e` plus the five owned files. Commands
ran serially through `devenv shell --no-tui --`, from
`apps/samgita_codex_driver`:

```sh
mix format lib/samgita_codex_driver/session.ex \
  test/session_tool_retirement_test.exs test/native_tool_interactions_profile.exs
MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl \
  mix test test/native_tool_interactions_profile.exs --only retirement_regression --seed 501432
# The native regression failed before the runtime repair: pending interactions 1 instead of 0.
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix test test/session_tool_retirement_test.exs test/session_test.exs
MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl \
  mix test test/native_tool_interactions_profile.exs --seed 501432
MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl \
  mix test test/native_tool_interactions_profile.exs --seed 987654
mix format --check-formatted
MIX_ENV=test mix test --exclude real_codex
unshare --user --map-root-user --net --fork --kill-child=TERM bash -c \
  'ip link set lo up && MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl mix test test/real_session_test.exs --seed 501432'
```

The initial actual-native red case failed at the unanswered-interaction count
after native interruption, before any runtime edit. Initial unit validation
also caught missing required `completedAtMs` in the new scripted item fixtures;
the driver correctly rejected those invalid notifications. The first full native
run passed six cases and identified two incorrect model-output expectations:
single text is a plain string. Those expectations were corrected against the
pinned `function_tool_response` implementation, preserving exact text/content,
item/turn, no-fetch and unconfirmed-outcome assertions. Neither correction
changed runtime behavior, deadlines, isolation or buffering limits. Two bounded
test-correction rounds were used; final validation passes.

Final compile and format checks passed. New and existing Session tests passed
**33 tests, 0 failures**. The full new native profile passed **8 tests, 0 failures**
on both seeds, taking 18.8 seconds each. The nonnative driver run reported
**335 tests, 0 failures, 254 excluded** (81 executed; explicit real-Codex exclusion);
its certificate-negative cases emitted expected TLS rejection notices. The
existing actual-native Session suite passed **7 tests, 0 failures** in the outer
private network namespace. Python AST parsing and `git diff --check` passed.
Each new native case checked owned process reaping; no owned fixture directories
remain. No validation command remains running.

Preserved local evidence:

- `/tmp/samgita-native-tool-interactions-red.log`
- `/tmp/samgita-native-tool-interactions-green1.log`
- `/tmp/samgita-native-tool-interactions-repair1.log`
- `/tmp/samgita-native-tool-interactions-final.log`
- `/tmp/samgita-native-tool-interactions-affected.log`

No Samgita platform, Repo or PostgreSQL was needed. These cases do not establish live
model/provider integration, every dynamic-tool registration/deferred-search
variant, async user input, other platforms or complete app-server compatibility.
A11 remains separately blocked. No publication, deployment or production
migration is performed.

The coordinator additionally passed root warnings-as-errors compile, format and
strict Credo (313 files) after the runtime changes. The profile is a required
explicit CI step. Eleven message/lifecycle entries and 35 directly asserted
field/variant contracts receive this selected `implemented` evidence; none is
fully verified. Platform journal retirement is a separate required integration
check and is not proven by this independent-driver unit.
