# Explicit plugin selection

The three cases in `apps/samgita_codex_driver/test/plugin_selection_test.exs`
drive the immutable Codex `rust-v0.163.0` executable through the independent
stdio Session. Source is `83086188ae0614bd882818ff1aa23f3194962012`; Linux musl
binary SHA-256 is
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Only an owned local marketplace, installed synthetic skill and loopback
Responses fixture are used. The fixture supplies model responses; Codex itself
performs discovery, installation, selection, injection and history persistence.

| Profile | Observed behavior |
| --- | --- |
| Duplicate structured mentions | Native user-item start/completion preserve both original mentions and their identity. A single developer capability hint is injected; no unselected skill, MCP or app capability is invented. |
| Linked mention identity | An `@` link selects the exact installed plugin despite a different display label. A `$` link and an unknown structured path do not inject it. |
| Settings and explicit skill | `thread/settings/update` disables fresh plugin/skill injection while retaining earlier history. Reenabling injects again. The explicitly selected runtime skill body precedes the plugin hint. Cold resume retains the thread without another model request. |

The installed skill is obtained from the actual `skills/list` runtime catalog.
The first run used the source-package path returned by `plugin/read` and failed
one of three cases: it did not select the namespaced installed skill. Selecting
the catalog's installed path repaired the fixture while retaining exact content
counts and order assertions. Strict Credo's nested-helper finding was repaired
by extraction, with no assertion removal or rule exclusion.

Pinned references, relative to `codex-rs/`:

- `core/src/plugins/mentions.rs:63`: explicit path matching and deduplication;
  `mentions_tests.rs:80-155`: structured/link/dollar profiles.
- `skills/src/mentions.rs:38-105`: path classification and linked mentions.
- `core/src/session/turn.rs:236-242,503,1017`: selection and turn injection.
- `core/src/plugins/render.rs:23-44`: developer capability hint.
- `core-plugins/src/discoverable.rs:107,174-177`: disabled plugin filtering.
- `core/tests/suite/skills_extension.rs:917`: skill/hint ordering reference.

The corrected file passed **3 tests**, seed `501432`. Together with the six
filesystem cases it passed **9 tests** at each seed `513498` and `987654`.
After the helper extraction, the combined profile/plugin/filesystem/environment
run passed **22 tests**, seed `501432`, and strict Credo passed 286 files.
Logs: `/tmp/samgita-plugin-selection-{initial,repair-1}.log`,
`/tmp/samgita-fs-lifecycle-regressions.log` and
`/tmp/samgita-operation-profiles-static-check.log`.

The selected `plugin/list`, `plugin/install`, `plugin/read` and
`thread/settings/update` request/response entries have implementation evidence;
they are not fully verified. Other plugin operations, remote marketplaces,
app/auth/MCP-enabled injection, field variants and other transport/OS profiles
remain incomplete. No fixture is a real external integration, publication or
production-readiness claim. Final-source aggregate/hosted results belong in
[qualification](qualification.md).
