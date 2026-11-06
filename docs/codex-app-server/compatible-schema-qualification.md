# Compatible inbound schema handling

This change implements the user's approved forward-compatible client policy.
It does not change the immutable Codex 0.163.0 schema inventory or claim full
compatibility with newer releases. The starting main revision is
`493a49aa27c18bbd227d41f837b0d48c11c542cb`.

## Behavior and ownership

`SamgitaCodexDriver.Session` defaults to compatible inbound handling. A known
response that fails the pinned result schema returns an explicitly unvalidated
Error with the original wire, a bounded structured warning and the original
mutation uncertainty. Only that pending request settles; unrelated work stays
connected. Unknown extension results receive the same treatment even when the
caller explicitly used outbound `validation: :wire`.

Known schema-invalid notifications have their own unvalidated event kind and
never drive interaction/lifecycle updates. Unknown notifications retain their
existing event kind with explicit unvalidated metadata in both modes. All raw
payloads remain available to the authorized caller/event consumer. Diagnostic
metadata contains no raw payload snippets, free-form schema paths or upstream
strings; the event byte bound includes warning metadata. Existing resource
overflow/gap behavior is unchanged.

An unvalidated initialization result cannot establish readiness or send
`initialized`. It leaves an open but unusable-for-requests connection in
`initialization_failed`, requiring explicit reconnect. Known invalid server
requests receive `-32602` without an actionable handle; unknown requests still
receive `-32601`. No response is automatically approved. Framing, JSON limits,
typed IDs, correlation, generation handles, dispatch fences, uncertainty and
explicit recovery remain intact.

`schema_mode: :strict` preserves failure/disconnect on known schema violations.
The package config also accepts `SAMGITA_CODEX_SCHEMA_MODE=strict`; the manual
conformance workflow now sets it. Outbound schemas remain strict unless the
caller explicitly selects the existing extension path. That option no longer
bypasses inbound validation or readiness checks. Additional fields that already
validate against the pinned schemas continue to preserve successful raw results.

The platform bridge recognizes only actual upstream error envelopes as native
error settlements; raw unvalidated result errors become uncertain delivery.
The platform's durable journal remains schema-strict. Unvalidated diagnostics
must not be passed off as validated journal/lifecycle evidence. This change does
not introduce a new durable diagnostics schema, alter authorization or close A11.

## Scoped verification

The environment still cannot install Nix/devenv. Official Debian OTP packages
were extracted into a user-owned workspace toolchain, paired with the official
Elixir archive. Tests run on Elixir 1.18.5 / OTP 27 (ERTS 15.2.7), not the project's
OTP 28 deployment profile. Driver dependencies resolve without lockfile changes.

From `apps/samgita_codex_driver`, with that toolchain activated:

```sh
mix test test/compatible_schema_test.exs --warnings-as-errors
SAMGITA_CODEX_SCHEMA_MODE=strict mix test test/compatible_schema_test.exs --warnings-as-errors
mix test test/initialization_test.exs test/query_uncertainty_test.exs \
  test/ordinary_request_options_test.exs test/native_notification_test.exs --warnings-as-errors
SAMGITA_CODEX_SCHEMA_MODE=strict mix test test/initialization_test.exs \
  test/query_uncertainty_test.exs test/ordinary_request_options_test.exs \
  test/native_notification_test.exs --warnings-as-errors
mix compile --warnings-as-errors
```

The four existing regression files pass **51 tests /0 failures** in each mode;
the new suite passes **24 tests /0 failures** in each mode. A final combined run
of all five files with `--seed 501432` passes **75 tests /0 failures** in both
compatible and strict default configurations. The focused new suite checks shape/enum/union drift, added fields, typed
correlation, mutation uncertainty, strict mode, initialization, extension calls,
known/unknown notifications and pure tool requests, lifecycle isolation and
warning resource bounds. These are scripted protocol peers, not actual native
Codex or external-service evidence. No legacy approval/security suite is run.

From `apps/samgita_protocol_codex`, `mix test test/wire_test.exs
--warnings-as-errors` passes **5 tests /0 failures**, including malformed JSON,
duplicate keys, ID/envelope validity and resource limits. Changed Elixir files
pass scoped formatting; driver compilation passes with warnings as errors.
Root formatting initially could not load absent Ecto dependencies; the unchanged
driver formatter successfully formats/checks the small platform bridge change.
The full platform build and PostgreSQL integration tests are not run.

`python3 -B scripts/codex/inventory.py --check` passes. The unchanged full
compatibility gate and existing manifest gaps remain incomplete; no requirement
is promoted by these scripted tests. The historical `check_ordinary.py` source
fingerprint is not rewritten to imply that its previous whole-run evidence
applies to changed source. Full/hosted/native/other-OS qualification remains
separate. Commit publication uses `[skip ci]` under the existing restriction;
no broad workflow or deployment is requested by this change.
