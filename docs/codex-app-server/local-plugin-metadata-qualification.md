# Native installed local marketplace and plugin metadata

Two additive cases in `native_plugin_lifecycle_profile.exs` exercise actual
stock `plugin/installed` warm and after owned cold restart. Source is
`83086188ae0614bd882818ff1aa23f3194962012`, release `rust-v0.163.0`, Linux musl
binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The fixture enables local plugins with remote plugin/sharing disabled and uses
only owned source files, no credentials, threads or model calls. Existing
process-owner shutdown/reaping and all earlier lifecycle assertions remain.

The first case adds a prescribed Unicode marketplace displayName, verifies the
complete empty uninstalled response, installs the ordinary local fixture and
compares the entire installed response to an independent expected map. That
map includes exact marketplace name/path/interface and complete plugin summary,
including every expected null. It repeats the same oracle after a distinct
native PID starts, with immutable marketplace bytes and no loaded threads.

The second case supplies a complete rich local plugin interface. It independently
specifies all 19 output fields, including normalized defaultPrompt whitespace,
Unicode descriptions, category, informational capabilities, invalid-domain URLs,
brand color, absolute owned asset paths, null URL/dark alternatives and empty
screenshotUrls. The three assets are prescribed PNG bytes; all remain regular
files with exact source bytes before install, warm reads and cold restart. Both
complete installed response and plugin/read summary match the independent maps.
The response is never copied to construct its own expected metadata.

This is metadata projection. Informational capabilities do not grant execution
authority; no plugin tool, remote URL, image decoder/rendering, authentication,
policy enforcement or model reasoning is exercised.

## Exact physical owner scope

All 21 owners belong only to `schema:v2/PluginInstalledResponse.json#`.
They become scoped implemented, never fully verified. The corresponding
vendored experimental JSON nodes were independently traversed and hashed using
the inventory's canonical encoding; equal sibling hashes transfer no evidence.

| Definition prefix | Exact suffixes |
| --- | --- |
| `/definitions/MarketplaceInterface/properties/` | `displayName` |
| `/definitions/PluginMarketplaceEntry/properties/` | `interface`, `interface/anyOf/0`, `name`, `path`, `path/allOf/0` |
| `/definitions/PluginInterface/properties/` | `brandColor`, `capabilities`, `category`, `composerIcon`, `composerIcon/anyOf/0`, `defaultPrompt`, `developerName`, `logo`, `logo/anyOf/0`, `longDescription`, `privacyPolicyUrl`, `screenshots`, `shortDescription`, `termsOfServiceUrl`, `websiteUrl` |

Whole interfaces/summaries, Git/remote alternatives, URL-backed assets,
omission/default branches, sibling read/list aliases, nonlocal backends and
other OS profiles gain no qualification from this index.

## Executed evidence

The complete owning plugin profile is **10/0** within each **14/0** combined
scoped run at seeds501432 and987654. Command:
`devenv shell --no-tui -- python3 -B
/tmp/samgita-native-sleep-queue-plugin-v2-20261024.py`. Compile, format, root
strict Credo and executable-source guard pass. The combined `results.json`
SHA256 is
`afbde503a2f8efdb71d2a668ad3c34ecfeeea21068f01c89cb026bd85c5bc4fc`;
source snapshot SHA256 is
`3753eeb92184af2fabf7392b8e251586ff2e265e2eafc5b28d87f48f4cc42149`.
Both logs and complete source snapshots remain in its `/tmp` result directory.
No native failure occurred in these two new cases. Existing CI already runs
the complete owning profile explicitly; final-source hosted/aggregate checks
remain required. A11, missing emitters and full compatibility remain incomplete.
No publication, release, production migration or deployment follows.
