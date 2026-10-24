# Native skills per-cwd configuration recovery

`native_skills_cwd_config_test.exs` passes **one test / zero failures** at both
`501432` and `987654` (0.8 seconds each) using stock Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
This adds configuration-failure isolation to earlier malformed SKILL.md coverage;
every skill/configuration profile is not yet qualified.

## Behavior and independent oracles

The test owns six explicitly trusted project directories, each with an inert
`.git/HEAD` and project-local `.codex/config.toml`, plus one inert user skill.
Eight requested cwd entries include healthy and failing duplicates and exceed
the native concurrency bound of five. Every call must preserve complete original
request order and duplicate entries.

After warming the catalogue, only one owned project's Agent limit changes from
one to zero. That cwd must return exactly empty skills and one error, whose path
is the requested cwd and whose message is
`failed to reload config: agents.max_concurrent_threads_per_session must be at least 1`.
Every unaffected entry returns the independently prescribed user skill with no
errors. Ordinary cache reuse and explicit forceReload both preserve the isolated
error. It cannot become a global RPC failure or stale success.

A confirmed owned-process shutdown and distinct native process ID establish a
cold repeat against the same files. The error survives restart. Restoring only
that project configuration to one restores metadata on an ordinary list without
forceReload; the explicit reload control also succeeds. Exact config, HEAD and
SKILL.md bytes remain intact. No model request, loaded thread or server callback
is accepted. Existing guardians confirm owned shutdown. No task is executed.

## Failed draft and pinned-source correction

The initial v1 native run failed **one of one tests** because its project-local
invalid provider did not trigger an error: the native result correctly remained
healthy. This was a fixture assumption error, not a cache defect. The pin removes
project-local `model_provider` and `model_providers`, even for trusted projects
(`config/src/loader/mod.rs` 86-102, 1175-1179, 1763-1767), so repository config
cannot choose credential destinations. The repair preserves that boundary.

The final trigger is valid TOML in the same owned file:

```toml
[agents]
max_concurrent_threads_per_session = 0
```

The valid control uses one. `config/src/config_toml.rs` 758-766 accepts the
integer and the project deny-list retains this setting. `core/src/config/mod.rs`
2813-2824 derives the v2 fallback separately, then 4000-4008 rejects the original
zero limit with the exact error. The correction also adds an inert `.git/HEAD`:
root discovery requires it at `loader/mod.rs` 1538-1559; the previous empty
marker could only use saved exact-cwd fallback trust. No error, order, duplicate,
cache, restart, recovery or file assertion was relaxed.

`app-server/src/request_processors/catalog_processor.rs` 270-278, 515-592
materializes each cwd before consulting its skill cache, emits failed-cwd entries
and restores concurrent outcomes to input order. The concurrency bound is five.
`app-server/src/config_manager.rs` 191-205, 451-494 and `core/src/config/mod.rs`
1538-1598 reload each explicit cwd through local layers. These source facts
explain the observed behavior; they do not qualify watchers/concurrent writers.

## Reproduction and limits

From `apps/samgita_codex_driver` in verified Devenv, with `MIX_ENV=test` and
`CODEX_BINARY` set to the hash-checked pin:

```sh
mix compile --warnings-as-errors
mix format --check-formatted
mix test test/native_skills_cwd_config_test.exs --warnings-as-errors --seed 501432
mix test test/native_skills_cwd_config_test.exs --warnings-as-errors --seed 987654
```

Root strict Credo and exact source guards pass. Runner/artifacts:
`/tmp/samgita-native-skills-cwd-config-v2-20261024.py` and its same-named directory;
v1 retains the failed trigger. Ordinary launch safeguards, ephemeral credential
storage, isolated HOME/CODEX_HOME and disabled unused features remain. No
deadline, runtime implementation, policy or upstream dependency changed.

Six already implemented response owners and the called request/response entries
gain supplemental citations only. No state is newly implemented or verified.
Other config errors, roots, remote/executor authority, watchers, concurrent
writers, other OS/services, A11 and final aggregate/hosted gates remain open.
Nothing is published, released, migrated in production or deployed.
