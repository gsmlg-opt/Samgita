# Native Admin skill discovery

The stock `rust-v0.163.0` binary discovers one inert Admin skill from its actual
system root. This is scoped enabled discovery evidence, not skill execution,
policy enforcement or complete compatibility. Source remains
`83086188ae0614bd882818ff1aa23f3194962012`; binary SHA256 is
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Upstream `ext/skills/src/host_roots.rs:118` classifies that root as Admin.

The explicitly owned fixture creates fresh user, mount and network namespaces,
makes propagation recursively private, then binds only its owned synthetic
`etc` tree onto existing `/etc` inside that namespace. It requires read-only,
nodev, nosuid and noexec, exact source/target device+inode and file-byte equality,
loopback only with no default route, zero capability sets and no_new_privs
before starting services or native. Parent `/etc` and namespace identities are
checked unchanged. No host system path is created or written, no elevated
fallback or host security-policy change is used.

Only system configuration disables bundled System skills; user and CLI config
provide no override. The test compares the sole complete skills/list metadata
map, source bytes/hash, absent System cache and immutable configuration after
reload and owned cold restart. There is no thread, inference, skill execution,
authentication or inherited credential. Both native PIDs and the namespace
controller are confirmed reaped. Unavailable namespace/mount prerequisites fail
the required profile explicitly.

## Initial failures and cause

The first scoped runner stopped at strict Credo in a concurrently added sleep
helper, before Admin runtime. Extracting transcript and cleanup helpers retained
all assertions. Admin v2/v3 then failed startup with the original 10-second bound.
Safe startup diagnostics record exception type and frame basename/line/function,
without exception arguments or payload values. The retained roots are
`/tmp/samgita-admin-skills-MHNgcXXn0MtB` and
`/tmp/samgita-admin-skills-EDToTQ_mfPc-`.

The mount proof incorrectly compared mountinfo's filesystem device with
`stat.st_dev`, which is a subvolume device on this Btrfs host. The repaired proof
compares filesystem devices within mountinfo using the unique deepest covering
source mount, while retaining exact source/target stat device+inode equality for
the directory and both files. Ambiguous covering mounts fail closed. No mount,
capability, ownership, byte, deadline or cleanup check was removed.

## Executed evidence

`devenv shell --no-tui -- python3 -B
/tmp/samgita-native-admin-skills-v4-20261024.py` passes compile, format, root
strict Credo and **1/0** at each seed `501432` and `987654`, with a matching full
executable-source guard. The subsequent combined scoped runner
`/tmp/samgita-native-sleep-queue-plugin-v2-20261024.py` passes **14/0** at both
seeds, including this same case, all ten plugin cases, both queue cases and
sleep/steer. Its compile/format/strict Credo and source guard also pass.

Combined `results.json` SHA256:
`afbde503a2f8efdb71d2a668ad3c34ecfeeea21068f01c89cb026bd85c5bc4fc`;
source snapshot:
`3753eeb92184af2fabf7392b8e251586ff2e265e2eafc5b28d87f48f4cc42149`.
Logs and synthetic roots remain under `/tmp`; hosted and final-source aggregate
qualification are separate gates. CI explicitly runs this profile.

Exactly one independently hashed physical owner becomes scoped implemented:
`schema:v2/SkillsListResponse.json#/definitions/SkillScope/enum/3`, literal
`admin`, subtree SHA256
`d22a3bd3ccf802db8efbb8f15404a3fb74f53fdfca7f6c2e99a71c62bc06820e`.
No sibling response/alias, skill execution, other platform or fully verified
status is inferred. A11, legacy emitters, external profiles and the full goal
remain incomplete; no release, publication or deployment follows.
