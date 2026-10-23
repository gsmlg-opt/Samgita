# Client capacity and response deadline qualification

Seven new deterministic client-boundary tests passed at seeds `501432` and
`987654`: **7/0 each, 1.6s each**. Baseline `38e47451` retains the existing native
driver; this unit changes only tests and evidence. It never starts a fake or real
Codex process. ScriptedTransport stimulates actual Session public APIs, and is
explicitly fault-injection evidence, not native server emission.

The review found no required functional changes before installation. All seven
cases passed on the first run: Sol repair rounds **0**, Astra **0**. No production
deadline, capacity, replay rule, assertion or cleanup mechanism changed.

## Exact boundaries

Test path: `apps/samgita_codex_driver/test/session_capacity_deadline_test.exs`.

| Case/anchor | Required effect |
| --- | --- |
| Sent mutation response deadline, line 7 | Observe transport send before the real 30ms request timer settles as uncertain; retain the exact late envelope without settling uncertainty; explicit reconnect initializes a new generation without resend; invalid reconciliation and ID reuse fail; only explicit valid evidence clears the hold. |
| Pending quota, line 48 | With one held read, reject another request without dispatch; settle the exact held ID, then admit the previously rejected ID to prove rejection consumed no request identity. |
| Uncertainty quota, line 65 | Reserve capacity for the pending mutation, permit reads, preserve the same restriction after explicit local abandonment, then admit a separately chosen new mutation only after explicit reconciliation. |
| Connection ID quota, line 89 | Count initialization against the quota, reject at the exact boundary without dispatch, and reset only on explicit reconnect/reinitialization. No request is replayed. |
| Interaction quota, line 110 | A second approval produces an explicit gap/disconnect; invalidate the retained handle and send no automatic response. |
| Outcome quota, line 129 | Preserve the exact response digest as sent-unconfirmed, then uncertain after saturation; admit no second approval; acknowledging local outcome storage does not reconnect. |
| Critical byte overflow, line 156 | Set the event-byte limit to exactly one byte less than the encoded approval. Expose an explicit gap, invalidate interactions and retain the pending sent mutation as uncertain; no response to the dropped request is sent. |

Each input followed by a Session call uses same-sender message ordering as the
observation barrier. There is no sleep/retry-until-green synchronization. The
deadline test deliberately sends no racing reply before timeout. Every asynchronous
request settles; owned Session cleanup is registered immediately, preserving the
existing owner-death handling.

The late response deliberately has an incomplete ThreadStartResponse because a
request absent from `pending` is retained as an opaque late envelope. That checks
lossless late-message delivery, not typed ThreadStartResponse validation. These
cases also do not qualify response/deadline races, timer-cancellation races, every
transport's write backpressure or any upstream exactly-once/idempotency promise.

## Commands and evidence

From the repository, with Elixir 1.18.5 / OTP 27.3.4.17:

```sh
devenv shell --no-tui -- env MIX_ENV=test PYTHONDONTWRITEBYTECODE=1 \
  python3 /tmp/samgita-quota-unit-check.py
```

The owned runner executes from the independent driver directory:
`mix format test/session_capacity_deadline_test.exs`,
`mix compile --warnings-as-errors`, both focused `mix test` seeds, and changed-file
`mix format --check-formatted`. At root it runs positional strict Credo on the
single changed test: **one file, 69 checks, no issues**. All commands exited zero.
Captured log: `/tmp/samgita-session-capacity-deadline-initial.log`.
Test SHA-256: `950cdc4204b3e37fe0f059a7a3918b2b00baeadd5ed15af158d4a9c208872553`.

The two lifecycle entries gain selected `implemented` evidence; no schema field
or native message entry is promoted by these scripted cases. Full compatibility,
native backend/platform success, A11, external acceptance, publication and
deployment remain incomplete. Aggregate checks must include this new test on
the final delivered source; previous package repeats predate its installation.
