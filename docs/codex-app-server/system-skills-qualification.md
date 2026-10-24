# Native bundled skills and shared cache

One bounded case passes at seeds `501432` and `987654` against stock
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, Linux musl
binary SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Two explicitly owned native processes use the same fresh private CODEX_HOME.
Only native Codex creates its `skills/.system` files. The fixture never writes,
invokes or substitutes System skills, and serves no inference response.

Enabled process A (`-c skills.bundled.enabled=true`) lists actual System skills
with stable `skills/list` and `experimentalApi:false`. The test checks the
canonical owned paths, exact review-agent description, enabled/system/pluginId
metadata and immutable `review-agent/SKILL.md` SHA256
`07079efd0dc76f05fade424e5dfb048dce1de2df7626e1a4f56292a4f3f92228`, independently
matched to the pinned embedded source asset. Every cache file, including marker
and sidecars, is hashed and sized under explicit bounds.

A stays alive while disabled process B starts with only its bundle override
changed. B's forced list has no System rows and no errors; the entire shared
cache map and bytes remain identical. A's next forceReload returns the exact
original sorted metadata and hashes. Loaded threads, pending requests,
interactions, uncertainty and thread/turn/item notifications remain empty.
Any HTTP access fails the reject-only peer oracle. Config/catalog bytes remain
unchanged and auth.json remains absent. Both native processes and their guarded
controller/namespace owner must be confirmed reaped.

This follows the pinned real upstream
[`skills_list.rs:135`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/tests/suite/v2/skills_list.rs#L135)
two-process shared-cache recipe, with additional independent byte oracles.
[`skills/src/lib.rs:55`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/skills/src/lib.rs#L55)
embeds/materializes the cache;
[`host_service.rs:217`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/ext/skills/src/host_service.rs#L217)
controls installation/discovery without deleting another process's cache.
Host `/etc/codex` configuration is only checked for absence, never modified.
Both native children run inside loopback-only namespaces with no default route,
no inherited credentials and the retained owned-process guardians.

## Verification and evidence boundary

The first runner stopped at strict Credo on nested cleanup assertions, before
native execution. Extracting the identical process-reaping assertion into a
helper fixes style without changing its deadline/oracle. Both runner directories
remain: `/tmp/samgita-native-system-skills-20261024/` and the passing
`/tmp/samgita-native-system-skills-v2-20261024/`.

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-native-system-skills-v2-20261024.py
```

Python AST, warning-free driver compile, scoped format and root strict Credo
(419 files) pass. Each seed passes **1/0**, no exclusions, 1.4s (runner
1.927/1.937s); executable-source guard matches. A required explicit hosted step
is added. Final combined-source local/hosted checks remain separate gates.

| File | SHA256 |
| --- | --- |
| `native_system_skills_profile.exs` | d4ec2c1c409e9097bf2946be19d312077dd28d8fc7f887cfbaec7884d631224f |
| `isolated_system_skills_fixture.py` | f764c0d5e64ad745012b75e582cdc778af74313c26566de454c09255876d57f7 |

Exactly one physical owner gains scoped implemented evidence:
`schema:v2/SkillsListResponse.json#/definitions/SkillScope/enum/2`, pinned subtree
SHA256 `cf5fba424df88453fd1c04605897f3372415874ef6eb4d48b3e8bf745f291178`.
Assertions76–124 cover enabled/disabled/reload/cache behavior;155–177 check the
actual System metadata. No sibling/alias or whole-method promotion follows.
Admin scope needs a separately isolated supported System configuration route;
omitted optional metadata does not prove explicit-null production. Skill
execution, live services, other OS, A11 and complete compatibility remain
incomplete. No release, publication, production migration or deployment.

Regenerated totals: **485 requirements: 0 verified / 462 implemented / 12 missing /
11 blocked; 6,621 contracts: 0 verified / 3,034 implemented / 3,587 missing**.
