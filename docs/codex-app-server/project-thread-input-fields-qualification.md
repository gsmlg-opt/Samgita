# Native Project and thread input field evidence

This unit indexes **47 exact physical contracts**, previously missing, from
retained real-binary tests. The source is Codex `rust-v0.163.0`, commit
`83086188ae0614bd882818ff1aa23f3194962012`; the Linux executable SHA256 is
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
These are scoped **implemented** records, with no verified or whole-method
promotion. Identical schema hashes and sibling aliases receive no inferred
evidence. Native Codex Projects here are isolated fixture state, distinct from
Samgita Projects and their authorization model.

## Project contracts

The retained `native_projects_test.exs` and `native_project_profiles_test.exs`
provide 25 selected contracts:

| Owning schema | Properties | Observable behavior and limits |
| --- | --- | --- |
| ProjectCreateParams | idempotencyKey, metadata, name, roots | Known nonempty map/root and trimmed name; changed-payload key replay retains original; invalid values preserve state; cold read retains the created object |
| ProjectImportParams | idempotencyKey, threads | Known existing thread membership, atomic rejection and changed-payload key replay without reassignment; cold membership reads |
| ProjectListParams | cursor, limit, sortKey | Single-item pages, continuation with exact complete IDs, position versus recency ordering |
| ProjectMoveParams | beforeProjectId, projectId | Known project moves before the selected neighbor with matching update notification |
| ProjectReadParams | projectId | Cold read of the selected created object and its independently expected values |
| ProjectUpdateParams | metadata, name, projectId, roots | Omitted/null preservation and explicit rename/clear of initially nonempty values; identity, createdAt, recencyAt and membership retained |
| ProjectDeleteParams | projectId | Classification and membership removed; read rejected; retained two-turn history and owned sentinel survive cold restart |
| ProjectCreateResponse, ProjectImportResponse, ProjectReadResponse, ProjectUpdateResponse | project | Outer object joined to the known operation and assertions; nested fields do not inherit qualification |
| ProjectListResponse | data, nextCursor | Nonempty pages, actual continuation and all three expected unique IDs |
| ProjectChangedNotification | changeType, projectId | Exact buffered created/updated/deleted notification maps joined to affected IDs |

Pagination proves eventual falsy termination, not explicit terminal-null
presence. Update has no second-project isolation control and does not preserve
every timestamp. Move has no cold-restart persistence assertion. Notification
checks do not prescribe response-versus-notification wire order. The prior
import metadata cases use only omitted/null/empty maps; its nonempty input
contract remains withheld from this unit.

Pinned source: `app-server-protocol/src/protocol/v2/project.rs:49-182` and
`app-server/src/request_processors/projects.rs:69-287`. Their definitions and
routing identify the owning schemas; source forwarding is not runtime proof.

## Thread contracts

The retained resume/fork settings, response-metadata and read-state tests
provide 22 selected input properties:

| Owning schema | Properties | Observable behavior and limits |
| --- | --- | --- |
| ThreadResumeParams | model, modelProvider, cwd, approvalPolicy, approvalsReviewer, config, serviceTier, permissions | Cold typed overrides differ from defaults; loaded-subscriber precedence; exact effective metadata and named read-only profile |
| ThreadForkParams | model, modelProvider, cwd, approvalPolicy, approvalsReviewer, config, serviceTier, permissions, path, runtimeWorkspaceRoots, experimentalPredictionMode | Typed cold child settings, path-selected parent with deliberately invalid ID, selected inherited prediction metadata and ephemeral precondition; original parent/history retained |
| ThreadReadStateUpdateParams | expectedRevision, operation, threadId | Fresh read/unread updates, exact optimistic conflict and matching notifications across native restart |

Configuration coverage selects `model_reasoning_effort`; it does not qualify
arbitrary settings. Reviewer selection canonicalizes `guardian_subagent` to
`auto_review`, without proving reviewer execution/routing. Resume permissions
cover omission and a named profile, without explicit-null success or OS
enforcement. Service-tier default/null/flex metadata does not prove billing or
live tier availability. The read-state case selects one thread; it does not
prove every cross-target authorization or nonexistent-ID case.

Two input owners are deliberately withheld: the old resume roots input equals
the persisted fallback, and the old start policy equals the configured
`on-request` default. Their response assertions cannot distinguish honoring an
input from dropping it. New discriminating regressions are qualified separately.

Pinned source: `app-server-protocol/src/protocol/v2/thread.rs:62-107,354-412,544-613,2079-2083`,
`app-server/src/request_processors/thread_processor.rs:1694-1705,4060-4107,5094-5524`
and `app-server/src/request_processors/thread_read_state.rs:156-178`.

## Validation

At Samgita `c3dda0c2b89edfe821c63bc4808fd3e307ecbccf`, the complete default
driver ran with `CODEX_BINARY` set to the hashed native executable:

```sh
cd apps/samgita_codex_driver
mix test --seed 501432
mix test --seed 987654
```

Both passed **588 tests / zero failures**, in 521.3/520.3s. All 30 explicit
profiles passed **205/0** at each seed. The independent-package runner completed
23 checks with an executable/configuration/workflow hash guard. Full commands,
hashes, exits and logs are in
`/tmp/samgita-repair-final-packages-v8-20261024/`.
The selected hosted job and isolated profiles at that same revision passed;
the required completeness gate failed, as recorded in
[repair qualification](repair-qualification.md).

The manifest attaches precise test paths/ranges only to the nominated owners.
This evidence does not clear A11, external credentials/backends, other OS
success, full transport coverage or upstream-unreachable emitters. No release,
publication, deployment or production migration occurred.
