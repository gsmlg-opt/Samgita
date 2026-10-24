# Discriminating native input and skill metadata

Seven new cases exercise the unmodified Codex `rust-v0.163.0` executable, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Only owned local configuration, files and synthetic dependencies are used.
These tests qualify selected metadata behavior, without starting model turns.

## Inputs that differ from fallback

`native_thread_input_override_test.exs` first establishes configured
`on-request`, selects explicit `never`, then creates an omitted-policy sibling
that still receives `on-request`. Dropping the explicit policy would fail.
Both root-selection cases persist A, cold-resume with a distinct B or `[]`, and
require those selected roots immediately and after another process restart
with the parameter omitted. The original creation record and journal prefix
remain intact; a new durable effective-settings snapshot records B. No turn,
history item or model request is manufactured to flush the setting.

This discriminates the two [previously withheld input owners](project-thread-input-fields-qualification.md).
Pinned `core/src/session/mod.rs:1716-1725` flushes an effective-settings
checkpoint even without a following turn. The test retains that assertion,
original history identity and content, exact instructions, read-only metadata,
no loaded threads before resume, and zero uncertain operations/model requests.
It does not qualify OS sandbox enforcement or all policy/default variants.

`native_project_import_metadata_test.exs` supplies a nonempty known metadata
map, including Unicode, surrounding whitespace and an empty string. Omitted,
null and empty-map controls remain empty. Changed-metadata/member replay with
the same key retains the original map and membership. Cold project read/list,
thread association and unchanged owned empty histories prove persistence.
The known imported name and nonempty root also have exact immediate response
assertions; their cold persistence is not claimed by this test.

These cases add five selected canonical input properties: start approvalPolicy,
resume runtimeWorkspaceRoots, and import metadata/name/roots. No nested aliases
or whole-method state are promoted.

## Inert skill metadata

Three `native_skill_metadata_test.exs` cases create owned SKILL.md frontmatter,
`agents/openai.yaml` and local asset files. Exact full native list maps prove
normalization, local asset containment, rich dependency declarations, forced
reload, a cold stable-negotiation read, invalid optional-field filtering and
metadata removal. The top-level legacy summary remains distinct from the
interface summary. The owned dependency-command canary remains absent and
model request count remains zero.

Ten exact `SkillsListResponse` properties gain evidence: SkillMetadata's
dependencies/interface/shortDescription, SkillDependencies.tools, and
SkillToolDependency's command/description/transport/type/url/value. Transport,
command and URL strings are declarations only. No installation, invocation,
MCP connectivity, arbitrary network-effect absence or runtime authorization
is inferred. Shared SkillInterface aliases and unobserved nullable branches
remain unqualified.

## Validation

Run from the standalone driver with the pinned `CODEX_BINARY`:

```sh
mix test test/native_skill_metadata_test.exs --seed 501432
mix test test/native_skill_metadata_test.exs --seed 987654
mix test test/native_thread_input_override_test.exs test/native_project_import_metadata_test.exs --seed 501432
mix test test/native_thread_input_override_test.exs test/native_project_import_metadata_test.exs --seed 987654
```

Skills passed **3/0** at both seeds, 2.0/2.0s. Input cases passed **4/0**,
23.2/20.0s. Driver warning-free compile/format and root strict Credo passed.
Commands, source hashes and logs are in
`/tmp/samgita-native-new-fields-adoption-v1-20261024/`; its end-of-run source
guard passed. The manifest records only scoped implemented evidence, with
zero verified promotions. Complete final-source package/platform/hosted checks
remain separate. A11, upstream-unreachable emitters and external/OS success
remain incomplete. No release, deployment or production migration occurs.
