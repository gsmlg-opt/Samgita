# Native child provenance in archived search

Exactly **6113, 6114, 6117, 6118 and 6119** gain implemented-only evidence:
ThreadSearchResponse's nested `agent_nickname`, `agent_path`, descriptive
`agent_role`, `depth` and `parent_thread_id`. The immutable target remains Codex
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, binary
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

One ordinary MAv2 root uses genuine native `spawn_agent` and `wait_agent` tools
to complete one child. The loopback fixture supplies only Responses items;
Codex creates the child, parent/child messages, notifications, stored history and
source metadata. A custom descriptive type includes the required description
and a singleton nickname candidate. The independent expected source is:

```json
{"subAgent":{"thread_spawn":{"agent_nickname":"OwnedSearchChild","agent_path":"/root/search_child","agent_role":"source_fixture","depth":1,"parent_thread_id":"<actual independently created root ID>"}}}
```

The label is Codex provenance, not a Samgita project membership role or permission
grant. Fixed yolo settings configure only owned qualification processes. There
are no security or permission scenarios.

A separate relation-list query resolves the generated child identity, source,
parent and empty preview. Saved native history independently resolves the child
turn. Exactly two ordered completion events must identify child then root,
both completed without error and both bound to the original root turn. The
provider journal must contain exactly three root requests and one child request;
literal message/tool outputs and completed answers are checked. No imported or
fabricated history is used.

## Pinned search preconditions

The initial active search fails for a source-backed reason. Native global
active discovery requires a nonempty preview. This MAv2 child receives an
`agent_message`; that path and its assistant completion do not create a user
preview. Parent-child relation listing deliberately includes empty previews.
The test now requires the active child search to be empty before any archive.
No retry, longer wait, extra user turn or manufactured preview can satisfy it.

The test explicitly archives the completed owned child through `thread/archive`.
This native lifecycle operation moves its rollout to `archived_sessions` and
updates native state. The independently derived archive path must match the
native path, the old path must disappear, and complete rollout bytes and saved
turns must remain identical. Archived discovery includes empty-preview threads,
so `archived:true` plus `sourceKinds:[subAgentThreadSpawn]` returns the actual
child content and all five prescribed nested source values.

Global stored search leaves outer `parentThreadId` explicitly null; its nested
source still contains the actual parent ID. Relation listing supplies the
independent non-null outer parent assertion. No outer-parent contract is promoted.
Default interactive content search separately returns only the known root.

After confirmed native shutdown, a distinct process's first content operation
is the archived source-filtered search. Empty loaded lists, full original root
and child turns, unchanged rollout/config/catalog/provider/fixture-journal bytes,
exactly four provider requests, empty workspace and no uncertain operations
remain required. The collector retains 256 events/1 MiB/20 seconds; requests use
5 seconds. Existing cleanup is preserved. This is orderly process-restart
evidence, not power-loss, production recovery or a broader active-search profile.

The pinned [source construction](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/agent/control.rs#L570),
[role loader](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/agent-roles/src/loader.rs#L100),
[preview extraction](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/state/src/extract.rs#L133),
[active predicate](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/state/src/runtime/threads.rs#L1436)
and [native archival](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/thread-store/src/local/archive_thread.rs#L72)
establish the real production paths. Global list parent-map defaults explain
the outer null without erasing source provenance. All **21 complete source
files**, five exact nodes and the response export match immutable provenance.

## Evidence and limits

Base commit: 7091e3a. Three draft runs fail **1/1** each: the initial oracle
incorrectly expects only the root completion; repair 1 then exposes a missing
required role description and falls back to a built-in nickname; repair 2
reaches the active empty-preview exclusion. The first correction requires both
independently identified completions. The second declares a valid custom type
with a singleton nickname. Bounded recovery then diagnoses the actual native
search precondition and requires active exclusion plus legitimate archived
success. It also source-corrects the separate global outer-parent oracle before
execution. No production code, test bound or retained assertion is weakened.

The final owning test passes **1/0** at both seeds 501432/987654, with warning-free
compile, scoped format and fixture AST checks. Logs:
`/tmp/samgita-v290-subagent-search-astra1-501432.log` and
`/tmp/samgita-v290-subagent-search-astra1-987654.log`.
Final test/fixture SHA256:
`ea3c6188ccd57357c94c387cbc5f886b3de1efb974356087d37f6d530a9fb0f6` /
`7ef1d60b7085696f92e83aa970da8e2dd08636d4a7c7f4414ce29e007ffe9bfb`.
Source/node evidence:
`/tmp/samgita-v290-subagent-search-archived-final/source-evidence.json`, SHA256
`817267c4e64e56850afc09607883f5ef9b76a86e7909d595141c1d96fdaa7f40`.
Adjacent manifest-binding.json binds only the original/current five owners and
final executable bytes. Earlier failed-source artifacts remain separate.

After the web and canonical dynamic-tool units, contracts become **4,793
implemented / 1,769 missing / 59 blocked**; requirements remain **462 implemented /
12 missing / 11 blocked**, zero verified. Final combined functional results are
recorded in [qualification](qualification.md). No alias, enclosing union,
nullable alternative, other backend/OS/transport or whole-method promotion
occurs. Active empty-preview success remains unavailable in this pin. Security/
permission tests and broad/hosted checks stay unrun. A11, source-unreachable
paths, external/platform acceptance, full compatibility and release remain
incomplete. No publication or deployment.

The final [31-file functional checkpoint](streamed-web-search-qualification.md#integrated-functional-checkpoint)
passes **57/0** at both fixed seeds, compile/format, strict Credo, outside
consumer **1/0**, eight fixture ASTs and the 261-source guard. It tests the final
archived-only profile alongside all retained selected functional files; active
empty-preview success and other unqualified profiles are not inferred.
