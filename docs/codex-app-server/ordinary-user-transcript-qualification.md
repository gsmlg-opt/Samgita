# Ordinary native User transcript

V529 targets stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The independently reviewed change adds one ordinary realtime case. Its first
real-native run passes in a **24/0** two-file regression block, seed `501432`,
43.9 seconds. Physical root owner **2702** gains scoped implemented evidence;
the final combined-source record below covers both fixed seeds. No production
driver/schema change is made.

## Genuine production path and independent oracle

The v2 backend parser accepts
`conversation.item.input_audio_transcription.delta` and
`conversation.item.input_audio_transcription.completed`. Actual native fanout
enters `Session.send_event_raw`; the canonical history reducer maps these Input
events explicitly to `User`. It creates an empty typed segment, accumulates
both deltas and seals that accumulated text. A revised final transcript remains
in the separate flat done notification. Public protocol conversion maps core
User to public User before the app-server emits typed started/completed events.
The local backend supplies backend messages only; Codex produces every public
notification, item identity, timestamp, rollout record and timeline response.

The case prescribes distinct user/session/text constants. It requires
complete original encoded frames, exact event counts/order and generation,
measured timestamp brackets, JSON/Wire decoding and aggregate schema validation.
The original typed start/completed params are also checked directly against
their standalone schemas. Positive native/peer readiness precedes explicit
transcript release. Canonical rollout records and repeated exact timeline reads
must retain streamed User text rather than the different flat final revision.
Zero model requests, the exact native operation inventory and owned cleanup
remain required. Existing bounds and all earlier Assistant assertions remain.

Only the canonical physical leaf
`ServerNotification.json#/definitions/ThreadRealtimeTranscriptRole/enum/0`
is indexed. Its node SHA256 is
`9a7d469ee31c85617b47990418cdcf535c45728d90c73d4195d16cf3ec1d2b41`.
Its role definition equals corresponding standalone/timeline definitions, but
that equality provides no automatic alias or descendant credit. Existing
Assistant and timeline owner states are unchanged.

Twenty-two whole official source files and 34 excerpts match the immutable
source archive; four generated exports and 29 reference pointers are checked.
The archived aggregate and generated experimental aggregate have different
whole-file hashes; only their exact role definitions are claimed equal. The
independent source review reports no actionable finding and confirms the old
Assistant case body is byte-identical. Source review is not native acceptance.

The formatter preserves the complete Elixir syntax tree. Final test SHA256:
`6d97df2542ede2557d1bcec416692b33fcbfd0b9346c6010ffe7b69a94a7a9ca`.
The Python helper matches the exact reviewed draft and passes AST syntax parsing
without import/execution. All original assertions, limits and deadlines remain.

| Source artifact | SHA256 |
| --- | --- |
| `/tmp/samgita-v529-error-family-handoff.md` | `5f28aaf232d3a095390e34cad1c9f5af973bc454bb5471cddc9afbfdb0800194` |
| `/tmp/samgita-v529-error-family-evidence.json` | `90bdecb340a2d142719cd1abdc3df4d66a91cca4f89349d36c589c8ee56994ad` |
| `/tmp/samgita-v529-independent-review.json` | `16f92ff639d3b0568ecd094bf9428a849312ebb4f636bad8fbc851a76a018598` |
| Reviewed helper draft | `fbd3c18b360f8113292584fbfa6e57e133a5bb6849152e3acf96796c8fcd4f09` |
| Unformatted test draft | `39f24a9c6823b3385f77e8e9ce0150af11c22ec8f502e04f0aa8cc55e9243899` |

## Final combined-source functional qualification

All **14 reviewed functional steps pass** for combined V529/V530 source:

```sh
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-v529-v530-final
```

The **70-file / 133-case** real-native selection passes at `501432` and
`987654` in 229.192 and 229.441 seconds. The outside-umbrella real-native
consumer passes **1/0**. Three selected neutral WebSocket cases pass at each
of `455834`, `501432`, `987654` (13 other cases excluded). Driver/root format,
driver/umbrella warnings-as-errors compile, inventory consistency, strict
Credo, Dialyzer and assets build pass. No native failure, runtime repair,
deadline/buffer increase or weakened assertion occurs in this unit.

All **1,689** guarded before/after hashes remain identical. Fingerprint:
`c2ceb2c6c6edd7245ee6745ce89a1be495e9e1d8f14cad34a9957760beed9520`.
The final binding checks every command/result/log, the exact five changed
guarded paths, six precise metadata rows, canonical node hashes, unchanged
requirements and **1,684** other sources. Thirty-four unique complete official
producers and 55 excerpts cover these units plus the bounded V531 memory-source
distinction. Every executed command and its timeout stays identical to V528;
two new cases run within already selected ordinary files. Formatter AST
equivalence preserves the reviewed User draft, and the capability test and
realtime helper match their exact reviewed bytes. No alias propagation is used.

| Final execution evidence | SHA256 |
| --- | --- |
| `/tmp/samgita-v529-v530-focused-501432.log` | `07583b4a22534dace87290dd264166179b48897149a4553ea30c0627ba113c94` |
| `/tmp/samgita-v529-v530-final-binding.json` | `3a32f5a5bb0a7b1eee43d9b15b7531a5c6c1bcb46ad9582035c9382236899b1d` |
| `/tmp/samgita-ordinary-v529-v530-final/results.json` | `64f05069c0a00993f65ca5516cb06a27d67bc6bc66b7863fc678713439b2173a` |
| `/tmp/samgita-ordinary-v529-v530-final/source.json` | `86085465a837d32835d39f8a467f86280a1c362bb0975c7cc3f52a26ac61e527` |

Exactly User owner2702 and configured-provider request owners830–834 gain
scoped implemented evidence. Contracts: **5,507 implemented / 984 missing /
130 blocked**; requirements: **462 implemented / 12 missing / 11 blocked**;
**zero verified**. Continue the separate ordinary MCP app-context
producer/fixture. Its source-only draft earns no native acceptance or promotion.

## Scope, rollback and remaining gates

Native launches use fixed yolo. No credential, authentication, authorization,
approval, permission or security check/audit is added or run. Existing mixed
profiles are not imported. The helper's explicit new `user-transcript` mode
preserves prior mode selection, backend data, deadlines, caps and cleanup.
Two existing assertion helpers retain their defaults and accept explicit new
expected backend/delta values. No thread/turn execution or public-notification
emulation is introduced.

Rollback restores the helper/test, their one exact manifest row and reviewed
selection/fingerprint. No database or historical record changes. This v2
local-backend case cannot qualify v1/frameless transports, cold restart,
real media/provider services, other OS, A11 or full compatibility. Prohibited
checks and hosted workflows remain unrun/incomplete. Legacy source-unreachable
paths retain their upstream evidence and blocked state; synthetic peers cannot
close them. No publication, release or deployment is claimed.
