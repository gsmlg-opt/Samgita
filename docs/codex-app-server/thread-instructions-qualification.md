# Native top-level thread instruction overrides

Fifteen stock Codex `rust-v0.163.0` cases pass at seeds `501432` and `987654`,
**15/0** each, 32.0 and 31.1 seconds. Source pin:
`83086188ae0614bd882818ff1aa23f3194962012`; executable SHA256:
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
All calls and persisted histories belong to the real native process. The owned
loopback Responses fixture supplies only deterministic assistant text and
captures the actual provider request.

The complete four-row nonempty/empty/null/omitted matrix runs separately for
`thread/start`, cold `thread/resume` and `thread/fork`, using durable named
pre-first-turn histories. Owned config has distinct Unicode/multiline defaults;
parents and explicit overrides have other distinct markers. Nonempty typed
values replace the defaults, explicit empty values suppress the corresponding
fragments, and null/omission select config defaults. Name/set and native history
reads provide the persistence barrier; no rollout or database is seeded.

Each first explicitly requested turn proves exact developer-role content and
counts every selected marker once while excluding the other known markers.
The effective base is the exact first provider input message when nonempty.
This pinned release has no top-level Responses `instructions` field; the test
requires its absence. Resume/fork itself makes no provider request. Forked child
and parent turns retain their own instruction content and separate durable
files; cold reads preserve exact completed-turn identities without loading or
executing them. User config bytes remain unchanged through cleanup.

Two populated-history cases exercise nonempty resume/fork overrides after a
completed turn. The new effective base prefixes the next provider request,
while the recorded original generic developer content remains in history.
The supplied new generic developer marker is not retroactively inserted into
that restored context. A fork leaves its parent's file and next-turn behavior
unchanged. This native distinction is preserved, not normalized by the driver.

Wrong integer/boolean field types reject both through local schema validation
and native wire validation on all three methods. Exact native invalid-request
and string-type errors preserve the complete read response, loaded IDs and
provider count. An explicit later turn still uses the original instructions.
No automatic approval, extra turn, retry or inferred project acceptance occurs.

## Immutable source semantics

References are relative to pinned `codex-rs/`:

- `app-server-protocol/src/protocol/v2/thread.rs:104,106,412,414,615,617`
  defines stable `Option<String>` fields. `thread_processor.rs:1679-1712`
  forwards typed overrides; start/resume/fork call that builder.
- `core/src/config/mod.rs:4112-4128` selects typed overrides ahead of configured
  values, retaining explicit empty strings. `core/src/session/mod.rs:797-832`
  gives configured base priority over persisted history/model defaults.
- `core/src/client.rs:996-1006,1074-1090` prepends a nonempty base as input;
  `core/src/context/base_instructions.rs:26-45` sets exact developer-role text.
- `core/src/session/mod.rs:4433-4459,4863-4899` distinguishes initial generic
  developer context from later context diffs;
  `session/rollout_reconstruction.rs:560-570` restores the completed-turn
  baseline. Generic developer instructions are not a world-state section.
- Loaded hot resume ignores these overrides at
  `app-server/src/request_processors/thread_processor.rs:223-230`. The positive
  replacement tests deliberately use cold resume; they do not claim hot resume
  replacement or rewrite the upstream behavior.

In the independent driver in verified Devenv with the pinned CODEX_BINARY:

```sh
mix test test/native_thread_instructions_test.exs --seed 501432
mix test test/native_thread_instructions_test.exs --seed 987654
```

Compile with warnings as errors, namespace preflight, scoped formatting and root
strict Credo pass. Exact commands and logs:
`/tmp/samgita-native-thread-instructions-qualification-20261024/attempt-01/`.
The existing 60-second case limit, 20-second turn deadline and guardian cleanup
remain unchanged. No rejected assertion or deadline was relaxed.

Only the six exact owning top-level instruction fields gain scoped implemented
evidence. Populated-history coverage is nonempty-only; hot-resume acceptance,
paginated/compacted histories, in-progress turns, other stores/OS/transports and
real provider profiles remain unqualified. No whole method, same-hash lookalike,
broad lifecycle or fully verified promotion is inferred. Final combined-source
and hosted gates, A11 and complete compatibility remain incomplete. No tag,
publication, real credentials, paid task or deployment occurs.
