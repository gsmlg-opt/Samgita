# Scripted Session cleanup and hosted partition repair

Status: scoped repair passed; **full compatibility remains incomplete**.
Baseline: `9b5298290c5b8724a2ddc9158786d80aec85e80d`.

The frozen v36 second full-driver run failed in
`SessionToolRetirementTest` after its assertions: `on_exit` called
`GenServer.stop/3` on an already terminated Session. The preceding complete
driver run passed 728/0. Running the owning file alone at seed 987654 passed
5/0; that pass does not erase the complete-suite failure.

The fixture combined two independent cleanup owners: Session monitors its test
owner, while a later ExUnit callback checked `Process.alive?` and then stopped
the same process. Owner death can terminate Session between those calls. A
deterministic diagnostic suspends an unlinked Session, checks liveness in
`on_exit`, resumes its queued owner-DOWN handling, observes its normal DOWN,
and calls the old stop. It reproduces the exact `GenServer.stop/3` `noproc`
failure without sleeps or retries. Unlinking isolates the monitored-owner path;
the original fixture also had a direct link to the exiting test process.

The four affected scripted/owned-resource test fixtures now use ExUnit's
supervisor, temporary Session children and unique child IDs. They pass the test
owner explicitly; otherwise `Session.start_link/1` would select the supervisor
as owner. ExUnit coordinates child termination, replacing the racy callback.
A regression creates three supervised Sessions with separate explicit owners,
observes normal owner/Session termination and exactly one transport close each,
and rejects reopen. All prior interaction, uncertainty, confidentiality and
resource-termination assertions remain. Production Session code and the
previous native Stdio cleanup repair are unchanged.

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-scripted-cleanup-v37-20261025.py
```

The deterministic old-pattern diagnostic retains exit **2** and its exact
failure log; it is not a passing acceptance test. The complete four-file block
passes **44/0 at seeds 987654 and 501432**, zero exclusions. Driver warning-free
compile/format and all **38** Python tooling regressions pass. Exact commands,
exits, source preimages and log hashes are retained under
`/tmp/samgita-scripted-cleanup-v37-20261025/`.

The exact baseline's hosted selected-conformance job separately reached its
unchanged eight-minute deadline in driver partition 1 of 2 after reporting
370/0. The timeout is a failure, and subsequent partition/platform/consumer
steps did not run. The workflow now splits the complete sorted Mix test-file
set into four required sequential partitions. Each retains the eight-minute
deadline and seed 501432; the job retains its thirty-minute deadline. No file
or tag filter, retry, skip or failure-masking option is added. A tooling
regression checks the four distinct indices, full-suite commands and required
deadlines. Actual hosted success on the changed source still requires a new run.

This repair does not close A11, unavailable upstream emitters, external/OS
success profiles, the retained populated GitHub assertion or complete-evidence
gates. Complete final-source local and pushed hosted qualification remains
required. No release, publication, production migration or deployment occurs.
