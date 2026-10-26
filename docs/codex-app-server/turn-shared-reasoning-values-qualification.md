# Shared turn reasoning input values

Two independent real pinned-native profiles qualify canonical ClientRequest
concise-summary356 and nested Settings.reasoning_effort null602. This is ordinary
selected-setting/provider behavior with fixed yolo; no policy matrix or new
permission behavior is tested.

## Actual three-turn behavior

apps/samgita_codex_driver/test/native_turn_shared_reasoning_values_test.exs uses
the unchanged original assistant-only model_fixture.py. Each profile owns a
private provider/home/workspace/native. Its synthetic catalog supports low/high,
default low and reasoning summary; unrelated surfaces and effort override stay
disabled. No ConfigurationUpdate producer or tool is involved.

The concise profile completes baseline low/auto, explicitly submits summary:
concise and observes low/concise, then sends a followup omitting summary/effort/
collaborationMode and still observes low/concise. The targeted real applied
thread/settings/updated snapshot and full provider reasoning map must agree;
an ACK or assistant answer alone is insufficient.

The null profile starts ordinary default collaboration mode with selected high
and fixed non-null instructions. Its next submitted mode changes only nested
reasoning_effort to a present null. Full encoded client wire must preserve that
key/null. Actual native selected effort and nested mode expose null, while the
provider's complete effective reasoning map resolves to low/auto from model
default. An omitted followup stays low/auto. This distinction does not imply
that the different top-level effort:null field clears a selected value.

A bounded delegating capture checks complete actual request id/method/params
and native response ID for thread/start and all three turn/start operations.
Every provider request has its actual native thread/turn metadata and current
marker once. Each turn requires one literal completed assistant and exactly one
completed turn selected by thread, turn and item type. No callback/tool input is
allowed. Requests remain **0 → 1 → 2 → 3**; reads/close add none.

After native close/reap, the test reads six genuine native-written user/assistant
maps. Full independent oracles fix actual distinct IDs, turn metadata, content/
classification/order and bounded user creation times. Each provider request's
entire selected ordinary-history prefix equals those maps with exactly the
documented custom-provider transformations: passthrough removed, non-prefixed
fixture-message IDs omitted outbound, msg_ IDs retained. Repeated assistant
text remains an ordered list, not an invalid globally unique-text assertion.
No raw/history injection, sidecar or app-server emulator supplies the result.

Provider, fixed config and catalog bytes remain exact through native shutdown;
workspace stays empty. Public owner/guardian/provider completion/Port cleanup
precedes root removal.

## Source and exact owners

Only ClientRequest pointers /definitions/ReasoningSummary/oneOf/0/enum/1 and
/definitions/Settings/properties/reasoning_effort/anyOf/1 gain implementation
evidence. No sibling enum/null/reference or enclosing-method owner is promoted.

Pin: rust-v0.163.0, source83086188ae0614bd882818ff1aa23f3194962012, binary SHA256
399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215.
Seventeen complete official files match the immutable archive; both exact
physical nodes independently match their canonical hashes.

v2/turn.rs:263–285 exposes summary/collaborationMode for this and subsequent
turns. protocol/config_types.rs:63–71,705–724,778–784 defines concise and the
selected optional effort. The actual turn processor forwards these values;
core/session/step_settings.rs:259–268 replaces a submitted whole mode and updates
summary. Its63–88 distinguishes selected effort from model default.
core/client.rs:934–952 resolves the effective request reasoning. Applied native
settings precede turn creation and emit the changed snapshot. Ordinary provider
responses contain assistant text only; they never manufacture setting notices.

## Final permitted checks

Owning module:2/0, seed501432,2.9seconds,
log /tmp/samgita-v319-turn-reasoning-501432.log. Commands/environment:
/tmp/samgita-v319-run.py; artifacts:
/tmp/samgita-v319-functional-checks/functional/.
The reviewed **49-file matrix passes99/0 twice**, seeds501432/987654, in
**175.565/177.313 seconds**. Scoped format, warnings-as-errors compile, strict
Credo on499 sources, outside actual-binary consumer1/0,27 fixture ASTs and the
**297-source** guard pass. All prior296 sources match baseline
4b8188a8052ee8f95ac70ccf598eaeb2723d58dd byte-for-byte; only the focused test is
added. No native failure or repair is observed.

| Evidence | SHA256 |
| --- | --- |
| Results | a4c1422836ebd511efa97eab5cb0d8d0d52c3755f66ac1704f002f35c7d140ae |
| Source guard | abd4a8b5e988d33f4ec6b37112f87b71e3b1785058597789ed26d6226b602834 |
| Seventeen pinned files and two nodes | 744e128bedd97dc904a7d4e763e743f45ea2d71adc7497fb02133cbe4503af1d |
| Resulting manifest | 3540edf8bec04fc80974114e6ebca86239b51cfa41f4d4000d9179365458534b |

Session256event/8MiB defaults,256event/1MiB local collector,32captures/4KiB,
4MiB files/2048rows/262KiB row and20s turn/60s case deadlines remain unchanged.
Final binding preserves schema identities/planned tests, every other contract
and all requirements. Inventory passes; strict completeness exits1.
Contracts become **4,958 implemented / 1,597 missing / 66 blocked**; requirements
stay **462 implemented / 12 missing / 11 blocked**, zero verified.

Other summary/null positions, plan modes, cold persistence/restoration,
unsupported models, external reasoning/services, OS/transports, A11 and full
compatibility remain unqualified. Prohibited security/auth/permission/approval
tests and broad/hosted workflows stay unrun. Release gates remain incomplete;
no publication or deployment occurs.
