# Native resume personality values

Two cases distinguish warm subscribed rejoin from cold native resume on the
immutable `rust-v0.163.0` [pin](design.md), source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Only a loopback synthetic model dependency is used; all resume responses,
settings notifications and stored history come from stock Codex.

## Effective settings and inherited instructions

The owned configuration selects pragmatic; every original thread explicitly
starts with none. A synthetic model template has a Personality section. The
first actual model request must contain the independently prescribed stripped
base, making later accidental regeneration observable.

- Warm subscribed rejoin receives omitted, null, same-none and different-friendly
  resume maps. It preserves the live none setting and original completed history.
  Summary-only updates provide distinct public settings snapshots without sending
  personality. Each explicit follow-up turn retains the original stripped base;
  history has exactly five unique completed IDs and five provider requests.
- Four separately persisted cold parents each resume after confirmed native PID
  replacement and an initially empty loaded-thread list. Omitted/null values use
  configured pragmatic; explicit friendly/none wins. Independent summary-only
  snapshots observe those values. Each explicit follow-up preserves the original
  stripped base, including under pragmatic/friendly metadata. Exactly eight
  provider requests and both completed IDs per parent survive.

Resume and settings snapshots themselves cannot dispatch model work. Bounded
capture preserves exact missing/null/present maps; retained request helpers check
response correlation. Local functional completion collection keeps fixed
deadlines and event-gap checks without invoking the retained approval assertion.
Full reads observe completed stored history and are not claimed to flush it.
Owned config bytes, uncertainty, ready state and cleanup remain checked.

The pinned [warm rejoin](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L4499-L4635),
[typed cold overrides](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L3905-L3924),
[configuration precedence](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/config/mod.rs#L4188-L4191)
and [inherited-base construction](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/session/mod.rs#L798-L832)
support these distinct oracles. The v159 source map binds seven upstream files
to the immutable archive. The v163 source-only review approves the final source.

## Final integrated checks

The final six reviewed functional files pass **16/0 twice**, seeds 501432/987654,
in 27.700/28.137 command seconds. Compile/format, root strict Credo on 458 files
and the 229-file source guard pass. Exact commands, cwd, logs and hashes are in
`/tmp/samgita-v165-resume-stage-final-checks/`; results/source SHA256:
`e8790f7f4c71c890155c06f27a3e410bf31753c3a51758b86ebfb88c264821ef` /
`ea7f313ffbc87141d1be12c83e196269371d328411b72035c3a66239546aa9de`.

```sh
mix test test/native_turn_personality_test.exs test/native_turn_plugin_list_test.exs test/native_project_sort_matrix_test.exs test/native_thread_section_values_test.exs test/native_resume_personality_values_test.exs test/native_feature_stage_values_test.exs --warnings-as-errors --seed 501432
mix test test/native_turn_personality_test.exs test/native_turn_plugin_list_test.exs test/native_project_sort_matrix_test.exs test/native_thread_section_values_test.exs test/native_resume_personality_values_test.exs test/native_feature_stage_values_test.exs --warnings-as-errors --seed 987654
```

The first v164 block also passed 16/0 twice but failed strict Credo on one new
config string's quote style. Its logs remain intact. Replacing that literal with
an equivalent sigil preserves config bytes; the complete final block reruns.
No production source, helper, assertion or deadline changes.

Exactly three direct `ThreadResumeParams.personality` owners, indices 6008–6010,
gain implemented evidence. Together with the separate
[feature stages](feature-stage-values-qualification.md), contracts become
**4,579 implemented / 1,983 missing / 59 blocked**; requirements remain
**462 implemented / 12 missing / 11 blocked**, zero verified in both. No alias,
response sibling, full lifecycle, other transport/platform/backend or real model
style inherits acceptance. Security/permission tests and related hosted workflows
remain unrun; A11, full compatibility, release and deployment remain incomplete.
