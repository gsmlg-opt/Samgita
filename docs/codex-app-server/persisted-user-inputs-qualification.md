# Persisted typed user inputs

Two cases in `native_persisted_user_inputs_test.exs` use the actual pinned
`rust-v0.163.0` binary with the existing owned loopback model fixture. They
prescribe original input order, media bytes, paths, skill metadata and an unknown
app mention independently of any native response. The provider returns inert
assistant text and never manufactures app-server frames.

The two profiles select image URL/auto detail or opaque fileId/low detail;
local images select high/original detail. Both add inline and local complete
PCM WAV, an owned inert skill and an unresolved mention. Known PNG and WAV bytes
must survive into the one actual captured Responses request, with exact image
reference/detail and audio objects. The selected skill sentinel occurs once;
the unknown app path confers no routing authority and is absent from model text.

Native user-item start/completion must equal the complete expected original
content and supplied client ID. A `thread/read` flush barrier precedes direct
hot `thread/items/read`; expected content never comes from that barrier. Exact
entry content and original timing/identity survive duplicate/missing selectors,
wrong-turn selection and direct reads from a different cold native process.
Cold reads leave the thread unloaded, add no provider request and leave owned
files unchanged. The original process/fixture guardians remain registered.

The pinned source is `app-server-protocol/src/protocol/v2/turn.rs:425-531`,
`protocol/src/items.rs:81-87`, `core/src/session/mod.rs:5260-5277`,
`protocol/src/models.rs:2115-2190` and
`app-server/src/request_processors/thread_processor.rs:2934-2960,3123-3180,3622-3669,6161-6186`.
The canonical stored item preserves typed content; the older reconstructed
UserMessageEvent representation is not this test's expected-content source.

The combined native block passes **17/0** at seeds `501432` and `987654`, with
warnings-as-errors compile/tests, formatting, strict Credo and source guards;
logs are `/tmp/samgita-native-followup-projections-v3-20261024/`.
The earlier v1 block passed fourteen cases twice but emitted compile-time
unreachable-branch warnings from parameterized literals. Prescribed parameter
tuples remove those dead branches while retaining both inputs and all oracles.

Thirty-seven exact physical ThreadItemsReadResponse contracts gain scoped
implemented evidence, covering selected typed input/image reference fields and
four explicit image detail literals. Explicit null detail branches remain
missing. No fileId lookup/upload backend, media understanding, remote retrieval,
real app/skill execution, sibling schema, other transport/OS or full verification
claim follows. A11 remains blocked.
