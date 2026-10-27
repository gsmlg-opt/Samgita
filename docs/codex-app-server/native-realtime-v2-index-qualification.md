# Existing native V2 realtime literal evidence

V478 indexes one previously missing experimental owner, **5933**:
`v2/ThreadRealtimeStartParams.json#/definitions/RealtimeConversationVersion/enum/1`,
the exact literal `"v2"`. It reuses unchanged actual-native
[V477 qualification](ordinary-startup-sdp-envelopes-qualification.md); no code,
fixture, scenario, test count or command selection changes, and no native
process or test is run again for this metadata correction.

The existing ordinary realtime case sends explicit `version: "v2"`, checks the
captured original request against `ClientRequest`, requires the actual original
started notification's `version: "v2"`, and independently requires the local
backend's exact path, prompt, `session.type: "realtime"` and
`output_modalities: ["text"]`. One backend request, zero inference, exact
timeline facts and checked owned shutdown remain required. The V1 case's
distinct `quicksilver` session is an additional control; it does not confer
another enum or whole-method credit here.

The pinned [request mapper][mapper] retains the caller's version. The
[core selector][selector] selects the explicit version; its [adapter selection][adapter]
chooses `RealtimeV2` and specifically restricts successful text output to that
version. The [V2 backend builder][builder] constructs the asserted session
type/modalities, and the [producer][producer] reports the selected version.
Thus the evidence includes actual native effects rather than generic JSON
forwarding alone.

An initial source-binding helper incorrectly assumed this parameter type had
a stable export and stopped with `FileNotFoundError` before any manifest write.
The pinned [method declaration][declaration] marks realtime start experimental.
The corrected binding requires matching generated/vendored experimental
schemas and explicitly requires both stable copies to be absent. The retained
manifest experimental flag stays true. No test assertion or export is weakened.

Six complete producer/projection sources match the
[official full-source binding](legacy-file-output-boundary.md). The exact
canonical node SHA256 is
`28450cb417f1e37e9e324652b742b41f536ffbef7849505e3f60cc7dcd9f8daa`.
`/tmp/samgita-v478-native-v2-index/source.json`, SHA256
`977b72f5b91862538414b736f417a813d6e4b5bd39139a136158d455e2f5cdff`,
binds source/schema/test/fixture hashes, assertion lines and the retained
V477 results/source reports. Every original log hash still matches.

V477's **81 ordinary real-binary cases at both seeds**, outside consumer,
three selected WebSocket cases at three seeds and all fourteen reviewed checks
remain the runtime evidence. All 1,668 guarded hashes match that report before
this metadata update. Afterwards, only the manifest's guarded hash differs;
the other **1,667** normalized guarded hashes stay exact. The runner's physical
fingerprint literal also changes, but the existing source guard deliberately
normalizes that self-reference before hashing. An initial comparison expected
that literal to change its guarded hash and stopped; the corrected comparison
checks the exact raw single-field change as well as the unchanged command plan.
Current fingerprint is
`61e6c6fd38ffb5f342d2d702608169a9ed3c9a22c1ed5b9e274608bf6b3bcce0`.
`python3 -B scripts/codex/inventory.py --check` passes. Its original log is
`/tmp/samgita-v478-native-v2-index/inventory-consistency.log`, SHA256
`1d50ff76ba4def00caaf3ad9b97757a25601fcd70d3a3778ff3d9e08c48e52af`.
The final exact source comparison, single canonical-row change, unchanged
command plan and raw fingerprint-only runner change pass in
`source-check.json`, SHA256
`dc6bac4876113826e4fef0e924abe02c0309f2ef0ee1d3377e0d3c358639a800`.
This is not a new fourteen-step runtime result.

Only 5933 gains scoped implemented evidence for explicit V2 with the ordinary
local realtime WebSocket dependency over the **stdio app-server transport**.
Other version/default/null handling, V2 WebRTC, initial-item/handoff behavior,
other app-server transports, live media/providers, OS/platform or requirements
gain no credit. No security, credential, authentication, authorization,
permission, approval test/audit or broad/hosted workflow runs.

Counts are **5,373 implemented / 1,132 missing / 116 blocked** contracts,
unchanged **462 implemented / 12 missing / 11 blocked** requirements and zero
verified. Full compatibility remains active. A11, unavailable emitters,
external/platform/OS success, prohibited/hosted and release gates stay open.
No publication, tag, deployment, production migration or sibling-service change.
The next concrete audit follows the persisted WebSearch `action:null` owner
5483 and the MAv2 private analytics/public-item boundary, including import/raw
history paths before making any producer-impossibility claim.

[mapper]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/turn_processor.rs#L1254-L1303
[selector]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/realtime_conversation.rs#L1397-L1401
[adapter]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/realtime_conversation.rs#L1597-L1608
[builder]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/codex-api/src/endpoint/realtime_websocket/methods_v2.rs#L75-L89
[producer]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/realtime_conversation.rs#L1755-L1762
[declaration]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/common.rs#L1080-L1085
