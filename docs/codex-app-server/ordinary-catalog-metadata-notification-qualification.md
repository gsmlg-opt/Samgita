# Ordinary catalog metadata notifications

V536 uses stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
It adds one ordinary native case and a bounded backend dependency, preserving
production driver/schema/platform behavior and historical data.

## Real emitter and independent projection

Three actual `app/list` calls cover first warm discovery, a cached repeat and the
first content operation in a distinct cold native process. The real Apps processor
waits for directory and threadless empty-MCP discovery, maps domain metadata through
`app_info_to_api` and emits `ServerNotification::AppListUpdated` before the result.
The cached repeat also emits its final native update. Cold persisted directory
cache has no fresh process-local TTL, so discovery refreshes from the dependency.

The fixture supplies two fixed directory pages and an empty MCP catalog. Stock
Codex creates every app-server notification, timestamp, result and cache write.
Four exact directory path/query pairs, an opaque Unicode continuation token and
bounded initialize/tools-list discovery are checked. There is no model response,
tool executor, injected notification or fabricated history/cache.

Literal test maps are independent of fixture constructors. Alpha has complete
Unicode branding, labels, icon maps, logos, version/category metadata and screenshots
with camelCase/snake_case backend aliases. Beta has explicit nulls; Gamma has empty
nested objects/maps/strings. Exact descriptive projections preserve these distinctions,
category duplicates, screenshot ordering and directory sorting into Alpha/Beta/Gamma.
The prompt strings and URLs are opaque display data; nothing fetches or executes them.

Each native notification is checked against both its captured original bytes and
the delivered Session event, then against the literal projection. Results provide
supporting evidence without alias credit. Thirteen outgoing envelopes, eleven
distinct request/reply IDs and three original notifications are accounted for;
warm capture prefixes survive cold execution unchanged. Loaded threads, workspace
and model-request journal stay empty, with no turn/item/server interaction.
Inputs stay exact and native/dependency owner/Port/PID completion is confirmed.

Only **29 physical descriptive owners** gain scoped implemented evidence:
`1987,1988,1990–1998,2000–2002,2007–2009,2011–2013,2018,2019,2021–2024,2026–2028`.
These cover AppBranding, descriptive AppInfo/nullable wrappers, AppMetadata and
AppScreenshot in ServerNotification. Excluded discoverability/install/composer/
review/access/policy fields are neither read nor compared nor schema-validated.
Validation uses selected descriptive leaves and the screenshot reference, with
literal map/null checks for wrappers. `pluginDisplayNames` covers only `[]`.
Separate response schemas, state outcomes and aliases receive no credit.

## Source, setup and bounds

Eleven complete production files and twenty-one excerpts match the immutable
archive. All five relevant definitions, six reference steps and twenty-nine
canonical node hashes agree. The whole experimental ServerNotification root
differs from the archive in exactly five unrelated retained-only properties:
Thread.canAcceptDirectInput, daybreakEnabled, environments, extra, and
ThreadSettings.multiAgentMode. Removing only these yields equal JSON; whole-root
byte/JSON equality is explicitly false. No selected catalog definition differs.

Fixed yolo startup keeps Apps=true and plugins/recommended_plugins=false; there
is no inherited feature conflict. Synthetic identity is inert setup. The new
helper imports only V532's reviewed ordinary configure/journal/cleanup and never
imports the old mixed helper. No credential/header inspection or security,
permission, policy-enforcement or approval outcome is tested.

Bounds: 60-second case, 5-second RPC/socket operations, four directory GETs,
32 MCP discovery POSTs/128 total HTTP operations, 64 KiB discovery inputs and
256 journal entries/1 MiB. Capture allows 128 outgoing/768 incoming frames,
4/128 KiB each and 4 MiB total; events 256/1 MiB and snapshots 2 MiB. One
dependency and two sequential native processes are explicitly owned and stopped.
No retries, deadline increases or relaxed assertions are used.

## Focused evidence

Independent source review found no actionable defect. Formatting preserves the
reviewed AST and Python syntax parses without importing/executing the helper.
The first actual-native run passes **1/0**, seed `501432`, in 1.8 seconds:

```sh
mix test test/native_ordinary_catalog_metadata_notification_test.exs --warnings-as-errors --seed 501432
```

| Artifact | SHA256 |
| --- | --- |
| Formatted test | `c3f97c8dfab278a72b287ea19dc8909273af571c9e5ce76453ecabcdbdf01813` |
| Reviewed helper | `aa2504ad84207f76be387799838158c0b7f40e590e1147ca3a4025420c0d972b` |
| `/tmp/samgita-v536-handoff.md` | `fd76f81baabb9fe1064fe7b704ee74cb7129338a5f0974514e8ec64d2efe6141` |
| `/tmp/samgita-v536-source-evidence.json` | `fbd3b5067a7a6b09a1612253dff0602164dc6696197d081a7afc3b345dfee659` |
| `/tmp/samgita-v536-independent-review.json` | `f3645bac22875c74677bd56c9669d1582dc0427078ca5ba82e2b87a0c648989d` |
| `/tmp/samgita-v536-focused-501432.log` | `1ef0f24766158b926ae43a43640ad98e1e31d6f0b755d96c235220d5df23e86b` |

The [final combined-source selection](ordinary-plugin-template-metadata-qualification.md#final-combined-source-functional-qualification)
passes all **14 reviewed steps**, including **75 files / 138 actual-native cases
twice**, three selected WebSocket seeds, outside consumer **1/0**, static/build
checks and **1,698** unchanged guarded sources. Its binding rechecks this exact
test/helper, all twenty-nine physical promotions and the explicit selected-node
versus whole-root archive comparison. It does not qualify live backend behavior.

## Rollback and remaining gates

Rollback removes the test/helper and restores these twenty-nine rows and the
reviewed selector/fingerprint. It needs no database or production migration.
This case does not qualify live Apps/backend operation, populated plugin names,
other OS/transports or full compatibility. Prohibited security/credential/
authentication/authorization/permission/sandbox/approval tests, audits, broad
suites and hosted workflows remain unrun/incomplete. A11, unavailable emitters,
external/platform/full-goal/release gates remain open; zero global verified
credit, publication or deployment is claimed.
