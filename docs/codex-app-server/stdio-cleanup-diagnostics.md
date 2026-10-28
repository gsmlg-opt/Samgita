# Owned stdio cleanup diagnostics

This change follows `d08fa36` on `main`. It adds failure-stage evidence; it does
not establish the cause of the intermittent native-suite cleanup failures
recorded in [ordinary data qualification](ordinary-data-extensions-qualification.md#combined-source-functional-gate-and-remaining-work).
The existing process-ownership, shutdown and reaping fixes remain in place.

## Behavior

The Python owner still stops its owned process group, waits for its leader,
reaps descendants, and joins its output reader. Only confirmed descendant
reaping **and** a stopped reader permit the existing NUL cleanup acknowledgement.
Termination, descendant and output-join bounds remain one second each; the
Elixir owner retains its five-second shutdown deadline and six-second call
bound. No native request is resent and no failed cleanup becomes success.

Without that acknowledgement, the helper now reports its observed failure
branch through its real exit status:

| Exit status | Helper branch |
| --- | --- |
| 84 | Descendant reaping unconfirmed |
| 85 | Output reader still alive after its existing join |
| 86 | Both conditions unconfirmed |

An acknowledged cleanup retains the actual child's exit status, including a
nonzero status. The exit code alone does not certify cleanup. The Elixir owner
publishes the status before its completion flag, preserving completion slot 1
and adding status slot 2 (`-1` means unobserved). Existing error codes/messages
remain; error details contain only `cleanup_stage` and `exit_status`. Repeated
close calls retain the evidence after Owner termination. An unclassified status
or an unobserved exit remains `unknown`, rather than an inferred root cause.

## Functional reproduction and regression

`test/support/stdio_output_barrier.py` imports the real pinned helper. It runs a
real finite child and gates only the output reader with an explicit barrier.
Original signal, child wait, descendant reaper, output join and ACK functions
execute unchanged. Observers record a bounded allowlisted lifecycle journal;
they do not substitute wait results, exit statuses or ACK bytes.

Four Owner scenarios cover natural exit and explicit close, each with a held
or released reader. Held cases require the real missing ACK, status 85, failed
completion and identical repeated-close diagnostics. Released cases require
the exact finite output/ACK, successful completion and preserved child status
0 or 143. Both child and worker must be reaped, their exact PIDs absent, Owner
down and Port closed. A held-reader intervention demonstrates this branch; it
does not prove that an earlier native run experienced the same condition.

Review moved the fixture's lifecycle assertions after original group cleanup,
so an unexpected lifecycle observation cannot skip cleanup. Assertions remain
intact. Stages 84/86 are source-mapped only: this fixture does not manufacture
an unreaped descendant to claim runtime coverage. Failed-case artifacts remain.

The environment-envelope test now includes the BEAM PID in its scratch name.
Earlier diagnostic attempts collided with retained failure artifacts when
`unique_integer` restarted in a new VM. No retained directory is deleted to
make a repeat pass; all test actions, close order and deadlines remain.

## Qualification and limits

The initial focused review runs seven functional cases (four cleanup scenarios,
the original environment-envelope case, root-input case and provider-429 case)
at seeds 501432 and 987654, followed by strict Credo. Both initial source guards
pass; the fixture cleanup-order correction then requires final-source checking.
The exact final combined command and outcomes are recorded in
[root/rate qualification](ordinary-roots-rate-qualification.md).

The retained original 164-case command and its 320-second bound are unchanged.
The reviewed runner adds a separate four-case cleanup step with a 30-second
bound. A successful repeat cannot erase the earlier unexplained failure.
Security/credential/permission/approval tests, audits and hosted workflows are
unrun under the user's restriction. No full-suite, release or deployment claim
is made. Rollback of these diagnostics changes no database, task, journal,
ownership or retry semantics.
