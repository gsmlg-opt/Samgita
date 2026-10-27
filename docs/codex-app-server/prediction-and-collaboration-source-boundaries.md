# Pinned prediction and collaboration producer boundaries

V505 is source-only evidence for official `rust-v0.163.0`, commit
`83086188ae0614bd882818ff1aa23f3194962012`. All5,259 Rust files match their
immutable archive members; archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
It introduces no fake native message, runtime result or target exclusion.

## Prediction has no stock notification source

Eleven exact physical `ServerNotification.json` owners2659–2665 and2827–2830
remain required and receive scoped **blocked** classification. They
cover Completed/Failed prediction-result branches and the
`thread/prediction/updated` notification wrapper/method/params. The complete
18-reference/seven-file source scan contains declarations, consumers and the
unconditional negative request dispatcher; it finds no prediction result,
notification or ServerNotification constructor.

`app-server/src/message_processor.rs:1450–1453` unconditionally returns
`thread/prediction/request is not implemented yet`. This negative branch alone
would be insufficient proof. The complete scan additionally closes over
protocol common/thread_prediction/mod declarations and client/media consumers,
with no task or successful producer. Generic outgoing helpers require an
already constructed typed notification and do not synthesize prediction data.
Canonical item/history and external session-import paths have no prediction
mapping. A custom producer could represent these retained schemas; stock
pinned Codex has no such source. No mock or altered version qualifies success.

Immutable upstream anchors: [prediction dispatcher](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/message_processor.rs#L1450-L1453),
[retained prediction protocol](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/thread_prediction.rs)
and [outgoing sender](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/outgoing_message.rs).
The complete scan below establishes the absence of a producer across the pin;
the anchors identify its declaration, rejection and outgoing boundaries.

The distinct request properties5723/5724 are sourceTurnId/threadId in
`v2/ThreadPredictionRequestParams.json`; they receive no status/evidence
transfer from this notification proof. Existing negative request evidence and
the blocked requirement remain separate from successful notification behavior.

## Private collaboration analytics is different from public item emission

Exact public enum owners2094–2097, `CollabAgentTool` sendMessage/followupTask/
interruptAgent/listAgents, stay **missing**. The stock V2 operations route their
selected variants through `ToolCallAnalytics`; analytics.rs10–62 explicitly
avoids another public tool item. Real effects are SubAgentActivity or ordinary
tool output. Older public collaboration producers use other enum values.

There are actual notification-shaped constructors in
`analytics/src/client.rs:431–455`, so a blanket no-constructor claim would be
wrong. Their sink is `track_notification`/AnalyticsFact/AnalyticsEventsQueue,
not the app-server outgoing sender. Complete scans record478 relevant symbol
references,38 qualified selected-variant references and62 bare-name matches,
including test and consumer roles.

The immutable [analytics client](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/analytics/src/client.rs#L431-L455)
shows that private sink. Its constructed messages do not prove delivery through
the public app-server connection.

Generic canonical ItemStarted/ItemCompleted conversion can nevertheless carry
these exact variants over the public outgoing route. Retained supplied histories
and selective-history projection also preserve them. This is enough to reject
global impossibility; the evidence does not establish authentic built-in
operation provenance, a stock native-generated public item, or a resumed
supplied item becoming a fresh notification. Constructed rollouts or captured
private analytics cannot stand in for that missing acceptance. Separate
history owners5303–5306 gain no credit by equal hash or shared conversion.

`ThreadResumeParams.history` accepts ResponseItem, not arbitrary TurnItem;
external conversation imports normalize ordinary response/message/turn records.
Neither fills the missing public-operation provenance. These limits preserve
all retained schema/codec/forwarding support and the original compatibility
requirement, rather than silently reducing it.

## Reproducible source evidence and limits

The bounded independent report is
`/tmp/samgita-v505-producer-boundary-review.md`, SHA256
`060dd50a43ec81dff9f04a6d7c8cd25e2dedf4d4192fb21997c88046e0d2de80`.
`/tmp/samgita-v505-source-evidence.json`, SHA256
`f5352b1038f502eafa35c8ae332d3b3a7e229acec017d10ecbc9b265ffa787d4`,
binds21 precise canonical nodes,68 complete reference files and eight
supplementary chain files. Full original reference rows, producer/consumer
roles and whole archive-equal file hashes remain under the same scratch prefix.
No test, native launch, upstream change or security/permission audit ran for
this source proof. Native success and full compatibility remain incomplete;
no verified/publication/deployment claim follows. Final combined-source
consistency and archive/node binding pass in the
[final integrated record](ordinary-mcp-control-ids-qualification.md#final-combined-source-qualification-for-v502v505).
