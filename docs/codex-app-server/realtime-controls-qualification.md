# Native V1/V3 realtime controls

Three new cases extend the eight retained SDP/control cases against stock
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, Linux musl
binary SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The full **11/0** profile passes both fixed seeds with strict checks. Every
app-server request result and notification comes from that executable; the owned
dependency peer supplies fixed audio/transcript data only. No real media engine,
account, audio device or external network is involved.

The new behavior is independently prescribed on both sides:

- V1 ingress checks one audio frame, assistant `output_text`, developer
  `input_text`, assistant transcript delta/done and nonnull output sample count.
- V3 startup checks ordered user/assistant initial items and explicit
  `delegationAckFiller: false` in the actual dependency `session.update` as
  `ack_filler: false`, followed by audio ingress and native transcript return.
- V3 UTF-8 input sends exactly 1,000 bytes across the native 500-byte boundary.
  The three exact context frames have byte lengths 499/500/1; their independent
  expected chunks concatenate losslessly, without inferred role/channel keys.
  Native assistant transcript output includes the non-ASCII value.

Each append waits for the peer's observed-frame barrier before the next request;
RPC acknowledgement alone establishes no ordering across audio/text channels.
The dependency sends output only after validating all prescribed native frames.
Exact started/closed identities and empty results, no SDP/error/turn/tool work,
no uncertainty, bounded journals and confirmed owned-process cleanup remain
required. The original eight cases, one-append gate, allowlist and deadlines
remain. Failed fixture journals now retain their owned evidence after process
reaping and identify the assertion line; error events include diagnostic context
without changing the rejection assertion.

## Retained failure and source-backed fixture repair

The first runner `/tmp/samgita-native-realtime-controls-20261024/` passed
compile/format/strict Credo, then failed **three of eleven** at seed501432.
Diagnostic repeats located the fixture's exact `session.update` comparison:
native sent `instructions: "Synthetic SDP prompt"`; all three new cases
expected `"Owned realtime controls prompt"`. Handshake headers/routes passed.
Three preserved journals are in `/tmp/samgita-realtime-sdp-` directories ending
`FE2MaVh6Cz2nxfdvxzQbfw`, `OmUY-TSlixUOLjZdXTrwew` and
`EJiI8p_XSL5cAi3rYszTrA`.

Immutable [`realtime_prompt.rs:9`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/realtime_prompt.rs#L9)
returns a nonblank configuration prompt before considering a request prompt;
its retained upstream unit test explicitly requires that precedence. The
fixture now supplies an empty configuration override **only for the three new
request-prompt cases**, with an exact test prerequisite. The original eight
retain their configuration prompt. No fallback comparison, changed deadline or
driver/runtime repair is claimed. Source for the V3 startup and UTF-8 mappings
is [`methods_frameless_bidi.rs:52`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/codex-api/src/endpoint/realtime_websocket/methods_frameless_bidi.rs#L52)
and its chunking at line109.

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-native-realtime-controls-v2-20261024.py
```

The final runner records Python AST, warning-free compile, format, root strict
Credo (416 files), **11/0** at seeds501432/987654, no exclusions, 15.9/15.7s
(runner 16.368/16.166s), and a matching executable-source guard.

| File | Final SHA256 |
| --- | --- |
| `native_realtime_sdp_profile.exs` | f5aa4c7db19b256279c6349949eb85d7a65a11362e80e9d83e4a5e20351010af |
| `isolated_realtime_sdp_fixture.py` | e314d478263a09aff652246dde9fc7fa4561d2299ec203766e4b0d9266a6ea5e |

Exactly one physical owner gains scoped implemented evidence:
`schema:v2/ThreadRealtimeStartParams.json#/properties/delegationAckFiller`,
subtree SHA256 `39de3cca8efa66a41d560ebd64d533b52c7d92b7228e93f04c868c3daa2d1bdb`.
Request construction at test141–147 and exact frame/barrier assertions100–124,
with independent fixture305–323, establish the supplied false value. They do
not establish true/null alternatives or actual backend filler/handoff effects.
No sibling aliases, enum or whole-method entries inherit this evidence.

Regenerated totals: **485 requirements: 0 verified / 462 implemented / 12 missing /
11 blocked; 6,621 contracts: 0 verified / 3,021 implemented / 3,600 missing**.
Real provider/media, ICE/DTLS/SRTP, device/browser, other OS, reconnect/handoff,
A11 and full compatibility remain incomplete. Existing hosted CI explicitly
runs this profile; complete final-source local/hosted checks remain required.
No release, publication, production migration or deployment occurs.
