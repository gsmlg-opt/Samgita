# Native feature-stage values

Two zero-model-call cases qualify the five stage alternatives actually emitted
by stock `rust-v0.163.0`, under the same immutable
[source/executable pin](design.md). This fills a concrete result-evidence gap:
the older mixed suite checked an allowlist without requiring each prescribed
stage. That suite is unchanged and unrun under the current testing restriction.

| Functional representative | Stage | Source index | Default enabled |
| --- | --- | ---: | --- |
| `login_shell_package_path` | beta | 13 | false |
| `cwd_relative_turn_diffs` | underDevelopment | 17 | false |
| `view_image` | stable | 5 | true |
| `transcript_v2` | deprecated | 2 | false |
| `undo` | removed | 3 | false |

The exact five maps, beta text/empty announcement and other null metadata are
literal expectations from the immutable FEATURES declaration. No expected
stage, enabled default or page index comes from the response under test. Two
opposite harmless `view_image`/`cwd_relative_turn_diffs` settings distinguish
effective enabled from the fixed default. No feature tool or shell is invoked.

The pinned [catalog processor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/catalog_processor.rs#L346-L456)
maps every FEATURES entry without filtering stages, so these five alternatives
have real native emitters. The
[feature declaration](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/features/src/lib.rs#L1017-L1135)
provides the selected indices and metadata. The source-only v162 review
independently counts 175 entries and checks all five literal oracles.

Each case checks omitted/null full-list maps, exactly one selected item at each
source-index page and the empty terminal page. Exact complete request envelopes
and response IDs are captured within a 64-frame/4096-byte bound. The complete
matrix repeats with a different native PID after the old one disappears;
executable hashes, config bytes and the sixteen-request capture count match.
No thread is loaded, no model call occurs and no uncertain operation remains.
Only functional catalog metadata is asserted; security/permission feature
behavior, capability denial and executing the represented tools remain untested.

The [final six-file block](resume-personality-values-qualification.md#final-integrated-checks)
passes **16/0 twice**, compile/format, root strict Credo and the 229-file source
guard on v165. Earlier v164 style failure is preserved and corrected without
changing assertions or runtime config bytes. The author v161 source map and
independent v162 review retain original rows/nodes and archive-byte provenance.

Exactly ten direct `ExperimentalFeatureListResponse` owners, indices 3940–3949,
become implemented: all five stage branches and their enum leaves. No request
alias, sibling result, feature execution or broad requirement gains evidence.
Together with resume's three owners, contracts become **4,579 implemented /
1,983 missing / 59 blocked**; requirements remain **462 implemented / 12 missing /
11 blocked**, zero verified in both. Broader hosted checks, other transports,
platforms/backends, real external success, A11, full compatibility, publication
and deployment remain incomplete. No prohibited tests are run.
