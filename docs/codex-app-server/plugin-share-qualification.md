# Native plugin share qualification

Eight cases passed twice against the actual pinned binary using isolated,
synthetic HTTPS backend and object-store fixtures. This establishes the selected
local native behavior below; real-service and complete compatibility gates remain
open.

Target: immutable Codex rust-v0.163.0, source
83086188ae0614bd882818ff1aa23f3194962012, binary SHA256
399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215.
Installed and validated on main at
598cced78d4552134d464f2331228ce12f62fc46 in
/home/gao/Workspace/gsmlg-opt/Samgita. Existing work, including the unrelated
samgita-codex-repair-followup.txt, was preserved. No Git mutation was performed
by this contributor.

## Owned implementation

- apps/samgita_codex_driver/test/native_plugin_share_profile.exs.
- scripts/codex/isolated_plugin_share_fixture.py.
- docs/codex-app-server/plugin-share-qualification.md.

Parent review approved installation and exclusive native validation.
The contributor does not own shared fixtures, runtime, configuration, manifest,
CI, ledger, Agent Notes or Git. The existing remote fixture is imported unchanged
for atomic JSON writes, owned CA generation, fixed regular-file bundle creation,
and synthetic auth/config generation. Its server and controller are not started.

Agent Note recall with project=samgita returned no results for two targeted
queries and an empty bounded list. No shared note was written. The nonempty-ID
validation limit below is a candidate for the coordinating agent's coherent
qualification review, not a standalone progress note.

## Pinned source contracts

Rust paths below are relative to the pinned codex-rs tree.

- app-server/src/request_processors/plugins.rs:1267–1480 handles the five share
  methods. All load fresh config and require features.plugins. Save,
  updateTargets and checkout additionally require plugin_sharing; list and
  delete intentionally do not. Auth is checked by core-plugins after feature
  and applicable input validation, not by a synthetic app-server implementation.
- plugins.rs:1276–1304 rejects invalid client remote IDs, save access-policy
  changes with an existing remote ID, LISTED creation and client-supplied
  workspace principals. plugins.rs:313–326 validates workspace target rejection.
  Client targets allow user/group reader/editor; response principals additionally
  permit owner and the injected workspace reader.
- core-plugins/src/remote/share.rs:143–209 archives a local plugin, obtains an
  upload URL, requires its ETag, PUTs the archive, then finalizes create/update.
  The returned plugin ID must be nonempty. Successful save records a best-effort
  local path mapping; no stronger durability/atomicity claim is made on a mapping
  write failure.
- share.rs:408–491 uses authenticated POST
  /backend-api/public/plugins/workspace/upload-url with filename, mime_type,
  size_bytes and optional plugin_id. The object-store PUT separately carries
  application/gzip and x-ms-blob-type: BlockBlob, accepts 200/201 and does not
  attach backend auth. Finalize is authenticated POST
  /backend-api/public/plugins/workspace or /{remote_plugin_id}, with file_id and
  the ETag from the upload-URL response. The blob response ETag is not used.
  The fixture deliberately returns different URL/blob ETags to expose that fact.
- share.rs:304–368 PUTs targets to /backend-api/ps/plugins/{id}/shares.
  UNLISTED injects the authenticated account's workspace reader target unless
  already present; PRIVATE and LISTED do not inject it. Creation supports only
  PRIVATE/UNLISTED at the app-server boundary; updateTargets also supports LISTED.
- share.rs:211–256,368–406 lists created workspace plugins with limit=200,
  follows page tokens, and joins installed WORKSPACE metadata and local mappings.
  Nonempty created results require share_principals. This profile qualifies one
  page only; pagination remains unqualified.
- core-plugins/src/remote.rs:697–764,1801–1838,1870–1905 defines selected catalog
  and share metadata. WORKSPACE requires discoverability; PRIVATE/UNLISTED map
  to workspace-shared-with-me, LISTED to workspace. Plugin source is the tagged
  object {"type":"remote"}, not a string. Installed metadata supplies local
  version, installed and enabled independently of a saved local path mapping.
- share/checkout.rs:38–160 fetches actual detail with download URLs, checks share
  eligibility, downloads into an editable owned HOME path when absent, writes a
  codex-curated personal marketplace entry and records the mapping. Existing
  mapped paths are reused rather than overwritten. The profile proves normal
  success/reuse only; cleanup failures, path collisions and malformed marketplace
  recovery remain unqualified.
- share/checkout.rs:174–213,375–455 uses HOME/plugins/{name} by default and
  serializes personal source paths as ./plugins/{name}, relative to HOME.
- share.rs:281–301 accepts only backend DELETE 204, then removes the mapping
  best-effort. It does not remove the source directory or personal marketplace.
  The profile asserts original source preservation, not remote revocation semantics.
- share/local_paths.rs:10–151 stores
  CODEX_HOME/.tmp/plugin-share-local-paths-v1.json with
  localPluginPathsByRemotePluginId, atomic writes and remove-on-empty behavior.
- plugins.rs:2435–2479 maps backend 404/auth-required/input errors to -32600;
  other HTTP failures, decode errors, missing ETag and malformed response metadata
  map to -32603. HTTP errors remain errors rather than successful empty lists.
- app-server-protocol/src/protocol/v2/plugin.rs:281–454 defines actual wire names,
  nullable result fields, target/principal roles and discoverability values.
  Save transforms null/absent share_url into the empty string; its nullable
  canPublishToWorkspace remains null.
- app-server/tests/suite/v2/plugin_share.rs:51–192,195–291,533–615,616–771,
  934–1116,1172–1276 and core-plugins/src/remote/share/tests.rs provide matching
  upstream source examples. Those upstream tests were read, not run here.

Important identity limit: save only checks that the returned plugin_id is
nonempty. remote.rs:2302–2329 decodes detail without comparing requested and
returned IDs; build_remote_plugin_detail also supplies no equality check. The
profile does not invent a mismatch rejection guarantee. Identity negatives are
invalid client IDs, empty save IDs and invalid catalog names/missing required
share metadata. Nonempty backend-ID mismatch behavior remains unqualified.

## Eight verified native cases

1. Create a PRIVATE share from two regular owned files. Assert the native save
   identity/URL/capability response, local mapping, nonempty list provenance,
   owner/user-reader/group-editor metadata, native source tag and full selected
   share context. Inspect actual upload bytes, exact archive membership, length,
   content, endpoint, request fields and ETag origin.
2. Save with nullable backend URL/capability fields and list nullable version,
   creator and URL fields plus empty principals. Assert the native empty-string
   save URL and explicit nullable/empty results. This is separate null/empty-only
   evidence, not positive evidence for populated variants.
3. UNLISTED creation and target updates across PRIVATE/UNLISTED/LISTED preserve
   all reader/editor/owner roles and user/group/workspace principal types. Assert
   the exact automatically injected workspace reader and an empty PRIVATE target
   update. Client workspace targets reject before any backend request.
4. Edit only the owned marker, save with remotePluginId as an update, and assert
   actual second upload bytes plus omission of create-only policy fields. Cold
   native restart retains the same local mapping and list identity; a synthetic
   installed row independently provides installed/enabled/localVersion.
5. Checkout a regular fixed HTTPS bundle. Assert every checkout response field,
   downloaded files, mapping and exact personal marketplace entry. Edit its
   marker, close/reap and restart; repeat checkout preserves local content and
   performs no second download, while list reports the retained path.
6. Save then delete; assert actual DELETE 204, mapping removal, empty list and
   original local source preservation, including across cold restart.
7. Backend list 401/404/429/503 and malformed JSON remain exact errors; null
   share principals/discoverability and invalid plugin names reject. Missing
   upload ETag prevents PUT; upload 503 and empty finalize identity remain
   errors. Invalid client IDs, LISTED creation and existing-ID access-policy
   changes reject before backend requests. No hostile filesystem fixture is used.
8. plugins disabled blocks all five methods. With plugins enabled and sharing
   disabled, save/updateTargets/checkout reject while list/delete work. Missing
   auth and API-key auth reject all five without backend requests. These are
   initialized owned process profiles, not live service authentication proofs.

## Network and process boundary

The controller verifies the pinned binary digest before startup and creates a
fresh Linux user/network namespace. It brings up only lo, checks a different
network namespace inode, exactly one loopback interface, and no default route in
IPv4 or IPv6. Namespace proof is journaled and asserted by the native profile.
There is no inherited native proxy environment or route to an external service.

The only backend routes are the seven exact share/installed/detail endpoints
above plus three synthetic startup metadata GET routes. Object storage uses a
separate TLS listener at exact /upload/owned and /bundles/owned.tar.gz paths.
Unrecognized paths/methods are rejected and journaled; tests require no forbidden
HTTP or fixture handler errors. No model, hook, MCP, execution, install,
reconcile or other app-server request is allowlisted.

An owned one-day CA signs the 127.0.0.1 server certificate. The actual native
client trusts it using CODEX_CA_CERTIFICATE or SSL_CERT_FILE; verification is
never disabled. Backend requests must match synthetic bearer/account values.
Every object-store request must lack Authorization and chatgpt-account-id, use
TLS 1.2/1.3, and uploads must have the exact MIME/blob headers. Token values are
never copied to the journal. No real service, credential or upstream write occurs.

The owned local tree contains only .codex-plugin/plugin.json and marker.txt;
bundle downloads use the shared helper with capabilities=[] and the same two
regular files. Upload tar inspection admits only those files and normal
directories, never absolute/parent paths, links, special files or executable
declarations. The fixture never extracts an uploaded archive onto disk.

Every start rewrites features.plugins=false before spawning Codex, preserving the
previous remote profile's fail-safe against startup materialization. Immediately
before the first forwarded plugin request, the owned config is atomically
rewritten to the requested plugins/sharing gate values. Actual request-time
config reload enforces the selected gate. Enabled-at-startup behavior and its
background work remain explicitly untested. The bridge forwards native stdout
unchanged and never synthesizes JSON-RPC responses.

Cleanup is registered immediately after Session.start_link and before initialize.
Explicit cold restarts close sessions and wait for the recorded native,
controller and namespace owner PIDs to exit. The controller reaps its native
process, joins output/request threads and closes both owned listeners before
recording native_closed. Both passing runs exercised this cleanup; a final /proc
audit found no remaining process with an owned fixture argument or owned scratch
working directory.

## Validation

The exclusive validation command completed with exit 0. Its log is
/tmp/samgita-native-plugin-share-initial.log. Commands ran through
devenv shell --no-tui --, with MIX_ENV=test and the pinned CODEX_BINARY above.

- From apps/samgita_codex_driver: mix compile --warnings-as-errors;
  mix format test/native_plugin_share_profile.exs;
  mix format --check-formatted test/native_plugin_share_profile.exs: passed.
- From that independent driver: mix test test/native_plugin_share_profile.exs
  --include real_codex --seed 501432: 8 tests, 0 failures, 33.7 seconds.
- Same profile with --seed 987654: 8 tests, 0 failures, 34.3 seconds.
- From repository root: mix compile --warnings-as-errors: passed;
  mix credo --strict --files-included
  apps/samgita_codex_driver/test/native_plugin_share_profile.exs: no issues.
  This invocation examined 321 source files despite the inclusion argument;
  the result is not presented as a one-file scan.
- Python ast.parse of the installed fixture, without importing or starting it:
  passed. Whitespace checks for all three owned additions produced no output
  (git diff --no-index --check returns 1 for these clean additions).
- Post-run binary SHA256 matched the pinned digest. Final /proc ownership audit
  found no owned processes. The command and owned processes finished before the
  exclusive native validation slot was released.

Sol repair rounds: zero for this separate unit; Astra rounds: zero. The preceding
thread-event lifecycle unit retains its separate Sol2 counter. Shared manifest
and ledger integration remains owned by the coordinating agent. Only directly
asserted populated fields are candidates for positive schema promotion;
null/empty-only assertions and error cases remain separately identified.

This unit does not qualify real backend authorization/revocation, real
publication, enabled-at-startup behavior, pagination, cross-platform transports,
hostile archives, every nullable/enum branch, nonempty backend-ID mismatch,
concurrent writers, failure atomicity, A11 or complete Codex compatibility.

## Manifest evidence mapping

The coordinating review checked the installed test/fixture digests above,
every assertion anchor and 23 canonical-definition equalities against the pinned
experimental schemas. All five request/response pairs become implemented with
selected evidence. The table identifies the 118 directly asserted positive
contracts; 112 were previously missing. No entry becomes verified. Test anchors
refer to `native_plugin_share_profile.exs` in this unit.

| Contract group | Positive contracts | Direct assertions |
| --- | ---: | --- |
| Save request fields and non-null discoverability branch | 5 | 45, 51, 157, 227: fixed path, user/group targets, create and existing-ID update |
| Save response | 3 | 54: exact ID, populated URL and true capability |
| Target update request/response | 5 | 165–177: all discovery values, exact returned principals and backend targets |
| Checkout request and complete response | 8 | 258–290: all seven response fields, actual files/mapping, cold reuse |
| Delete request | 1 | 300–309: ID, backend 204, removed mapping, source preserved after restart |
| Nonempty list and populated local-path branch | 4 | 62–65, 247, 291: plugin and exact local source/checkout path |
| Canonical PluginSummary fields | 20 | 66–70, 248–249: ID/name/source/version/policies and installed/local version |
| Remote source tag/variant | 6 | 68: exact remote source object |
| Populated interface and displayName | 6 | 71: nonempty display name; no other interface field |
| Populated share context | 22 | 72–81: exact identity/version/discovery/URL/creator/capability/principals |
| Principal fields and all three roles | 14 | 81, 175, 522: exact names/IDs/types, owner/reader/editor |
| Client target fields and two target roles | 5 | 45, 175–177, 509–511: user/group targets survive native processing |
| Principal-type variants | 6 | 150–175: user/group plus automatically injected workspace response principal |
| Discovery/update variants | 9 | 51, 157, 165–175: create PRIVATE/UNLISTED; update all three |
| Selected policy variants | 4 | 70: AVAILABLE and ON_USE only |

Canonical `PluginSummary`, `PluginSource`, `PluginInterface`, `PluginShareContext`,
`PluginSharePrincipal` and policy/role/type definitions are stored under the
manifest's canonical `PluginInstalledResponse`, `PluginSearchResponse`,
`PluginInstallResponse` and `ClientRequest` schema IDs. They are structurally
identical to the definitions exercised by share responses/requests. This
supports those exact schema contracts; it does not establish execution of
`plugin/installed`, `plugin/search` or `plugin/install` in this unit. A workspace
response principal also does not make client workspace targets valid.

Explicit null URL/capability/creator/version and empty principals/targets/list
assertions remain limited evidence. A field with an independently populated
assertion can remain implemented; a null/empty-only field remains missing.
Negative inputs, missing auth and HTTP 401/404/429/503 are method-error evidence,
never evidence for a populated success field. The profile is explicitly required
in `.github/workflows/codex-conformance.yml`; no hosted success is inferred from
the two local runs.
