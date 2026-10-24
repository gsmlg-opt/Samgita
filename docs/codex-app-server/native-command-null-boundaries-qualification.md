# Native command limits and explicit-null state

Seven new actual-native cases extend command execution, skills configuration,
persisted image inputs and metadata-only thread reads. The complete owning block
passes **31/0 at both seeds 501432 and 987654**, including the two separate
[image quota cases](native-image-quota-qualification.md). No case is excluded.
These are scoped implemented contracts, not full compatibility or deployment
acceptance. The target remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

## Observable command boundaries

The explicitly owned Python commands run in the existing private user/network
namespace, with loopback-only routes and borrowed native Unix-socket clients.
No shell text, unapproved command, model request or external network is used.
Existing ownership, stdin, PTY, duplicate-ID, timeout and reconnect cases remain.

- Buffered output without `disableOutputCap` returns exactly 1 MiB per stream;
  explicit `true` returns all 1 MiB + 13 stdout bytes and 1 MiB + 29 stderr bytes.
  Exact lengths and independently prescribed content digests are required.
- A zero streamed byte cap emits one empty `capReached:true` notification for
  each nonempty stream. The command remains active until explicit owner EOF.
- A three-byte cap splits multibyte UTF-8. Exact base64-decoded prefixes remain
  lossless binary; invalid UTF-8 is not repaired or silently converted to text.
- Explicit `timeoutMs:null` with `disableTimeout:true` survives the native
  ten-second default. The child reports its monotonic elapsed time of at least
  10,100 ms and remains pending until explicit EOF, then exits zero and is reaped.

Only the new ten-second boundary scenario has its own 15-second request and
12-second observation budget. No existing deadline is increased. Every final
streamed result has empty stdout/stderr, no duplicate deltas and no uncertain
operation. Native source anchors are
`request_processors/command_exec_processor.rs:141-202`,
`command_exec.rs:592-628`, `utils/pty/src/lib.rs:25` and
`core/src/exec.rs:63,185-186` under the immutable source root.

Fifteen precise `CommandExecParams` properties/reference alternatives gain
implemented owners from the complete directly exercised command profile. This
includes retained environment, cwd, supplied process-ID, terminal and explicit
timeout assertions. The selected `dangerFullAccess` request is accepted, but the
configured default is the same: this does not prove override precedence or native
sandbox enforcement. Negative-only permission profiles, unasserted nulls, whole
shared unions and other OS/transport environments remain unqualified.

## Explicit null is distinct from absence and normalization

`skills/config/write` receives an actual `path:null` plus a whitespace-padded name.
Native configuration trims the selector, writes exactly one name override,
preserves unrelated skills and source bytes, and makes repeated disable
byte-idempotent. A distinct cold process observes that override; explicit-null
enable restores the original config bytes. There are zero model requests,
threads, interactions or uncertain operations. This qualifies only
`SkillsConfigWriteParams.path.anyOf/1`; omitted optional metadata cannot qualify
its null alternatives. Source: `protocol/v2/plugin.rs:934-942`,
`request_processors/catalog_processor.rs:681-723` and
`core/src/config/edit.rs:499-588`.

A new persisted-input tuple sends explicit null details for both inline and local
images. Actual started/completed user items and warm/cold `thread/items/read`
retain those null keys, while the independently prescribed provider request
normalizes both to `high`. Existing auto/low/high/original tuples remain unchanged.
Exactly one fixed model request, unchanged owned media/skills, no server request
and a distinct unloaded cold native process are asserted. Only the two physically
owned `ThreadItemsReadResponse.UserInput` null-detail alternatives are indexed.
Source: `protocol/v2/turn.rs:450-461,489-524` and
`protocol/src/models.rs:948,2130-2138`.

The read-state case creates an empty ephemeral thread through public `thread/start`
and reads it with `includeTurns:false`. `Map.fetch!` requires an explicitly present
outer `readState:null`, a pathless ephemeral thread and no turns. A separately
materialized durable thread returns a real receipt with inner `firstUnread:null`,
proving the receipt store remains healthy. Unsupported includeTurns and receipt
updates return exact native errors; another read still has the outer null and the
durable control's receipt/history bytes remain unchanged. No store is disabled,
cleared, corrupted or edited and no task is lost. This is one exact
`ThreadReadResponse.readState.anyOf/1` owner, not ephemeral cold persistence.
Source: `thread_processor.rs:2934-2956,3130-3152,6603`,
`request_processors/thread_read_state.rs:16-64` and
`protocol/v2/thread.rs:1718-1722`.

## Reproducible checks and evidence

From the repository root, the retained runner invokes standalone driver commands
under `devenv shell --no-tui --`, `MIX_ENV=test`, and the exact `CODEX_BINARY`:

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-native-command-null-image-boundaries-v2-20261024.py
```

Its source lists all five owning test paths, full commands, final source hashes
including new files, strict Credo, compile/format checks and both native seeds.
All five commands exit zero. Each native repeat runs 31 tests with zero failures
and no exclusions, in 38.1s / 38.6s. The terminal source guard matches. Full logs
and JSON results are retained in
`/tmp/samgita-native-command-null-image-boundaries-v2-20261024/`.
The first attempt in the adjacent non-v2 directory retains **31/2**: both image
cases failed before quota handling because of the new provider fixture's HTTP/
compression prerequisites. Its failure and bounded correction are recorded in
the separate image qualification; no command/null case failed.

Final test SHA256 values:

| File | SHA256 |
| --- | --- |
| native_command_lifecycle_profile.exs | c061161f7dcf837b0d5895f55933f84d0dc21ea9a4e347f8b192465280c39ada |
| native_skills_lifecycle_test.exs | 9b8c8c1fe3eb2ee87ff31b3233cac0797f549c1faf056833289bde8b5f65776f |
| native_persisted_user_inputs_test.exs | 7f5e87ef91a8050f42dec161269d769f46c383ffe188d5349df5a2ad0c61db07 |
| native_read_state_fields_test.exs | 89271e9c125521b025f99c1f33e024cc903dab7e35d6905c963840f56e8363e4 |

Nineteen precise owners are indexed as implemented; none is promoted to verified.
No evidence transfers by equal schema hashes or to uncalled response owners.
Final combined/hosted checks remain required for the new source. A11, unreachable
legacy emitters, external accounts, unavailable OS profiles and the retained
unrelated aggregate failure remain incomplete. No release or deployment occurs.
