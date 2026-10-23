# Fake Agent listener recovery investigation

The aggregate reliability concern remains **unresolved**. A populated-database
repeat failed at immediate same-port restart after both the previous listener
supervisor and fake Agent had exited. Subsequent successful repeats do not
establish the original cause or prove a repair. No runtime helper, teardown rule,
port allocation, timeout, retry or database protection was changed.

At baseline `a696aef0ae2445f03bd17fcf273475c71ae13cea`, the original log
`/tmp/samgita-codex-followup-final-platform.log` records:

- Seed `437312`: 203 core tests and 125 web tests passed.
- Seed `987654`: 203 core tests passed; one of 125 web tests failed.
- `FakeAgentLifecycleTest` observed listener `DOWN(:normal)` and fake Agent
  `DOWN(:shutdown)`, then the restarted Bandit listener could not bind port
  `37891` (`:eaddrinuse`). The original log did not capture the kernel socket
  state or its owning process at failure time.

`FakeAgent.terminate/2` already synchronously calls `Supervisor.stop/1` on the
whole Thousand Island server. Its supervision tree contains the actual
TCP-owning listener, acceptor supervisors and a shutdown listener.
`deps/thousand_island/lib/thousand_island/server.ex:60-78` defines this tree;
`shutdown_listener.ex:39-40` stops the socket-owning child before connection
draining. The TCP listener's terminate callback emits telemetry and relies on
port ownership cleanup (`listener.ex:117-122`). The library's public
`ThousandIsland.stop/2` delegates to the same supervisor stop mechanism
(`thousand_island.ex:365-375`). Replacing one stop call with the other would not
establish a different resource barrier.

The explicit diagnostic hypothesis was that the TCP port resource could remain
alive after the fake Agent and complete listener tree exited. A disposable local
probe reproduced the test's suspended-listener shutdown sequence, monitored the
actual listening Erlang port, and checked that port's liveness after both process
`DOWN` messages but before immediate same-port restart. Across 3,000 cycles with
two online schedulers, no old port survived the process tree and all restarts
passed. The probe made no database changes or external requests. This did not
reproduce the original failure or establish that another process took the port.
Port `37891` falls within this host's ephemeral range (`32768-60999`), but that is
only a competing hypothesis, without failure-time ownership evidence.

The retained test diagnostic records original BEAM socket/owner identity. If
same-port restart fails, it reports the failed port's current allowlisted kernel
TCP/TCP6 local/remote endpoints, state and inode; matching BEAM sockets/owners;
and port-filtered `ss -tanp` output when available. Kernel and `ss` collection run
only on failure, before cleanup. It does not retry, sleep, change the selected
port or relax the restart assertion. The original suspended-listener trace and
both process shutdown assertions remain intact. `FakeAgent` itself is unchanged.

Commands ran in the existing verified Devenv environment with:

```sh
PGHOST=/tmp/samgita-p3-pg/socket POSTGRES_PORT=55443 POSTGRES_USER=gao \
SAMGITA_TEST_DATABASE=samgita_redesign_recovery_repair_test MIX_ENV=test
```

No reset, fixture deletion from PostgreSQL, guard bypass or historical-state
mutation was used. The populated database was reused throughout.

| Evidence | Actual result |
| --- | --- |
| Scoped lifecycle file, seed `987654`; `/tmp/samgita-fake-listener-initial.log` | 2 tests, 0 failures. |
| Original instrumented immediate-rebind probe; `/tmp/samgita-fake-listener-probe.log` | 1,000 restarts passed; original socket port monitors were checked after restart. Shutdown during acceptor startup also produced task-exit diagnostics; these do not establish the original bind failure's cause. |
| Web suite, seeds `437312`, `987654`; `/tmp/samgita-fake-listener-web-baseline.log` | 125 tests, 0 failures, 2 excluded at each seed. |
| `mix test --seed 437312 && mix test --seed 987654`; `/tmp/samgita-fake-listener-aggregate-diagnostic.log` | Each seed passed 203 core tests (1 excluded) and 125 web tests (2 excluded). This run exercised the diagnostic branch's normal path before the final extraction that keeps kernel/`ss` reads failure-only. |
| Port-resource-order probe; `/tmp/samgita-fake-listener-port-order.log` | 3,000 immediate restarts passed; no `SOCKET_OUTLIVED_TREE` observation before restart. |
| Final diagnostic source, populated aggregate seeds `437312`, `987654`; `/tmp/samgita-codex-followup-final-platform-2.log` | Each passed 203 core cases (1 excluded) and 125 web cases (2 excluded). Explicit platform scenarios passed 32 core + 5 web; recovery/lifecycle/restart passed 4 core + 3 web at each of `366499`, `888788`, on the same database. No runtime listener fix is established. |

The standalone probes were diagnostic scripts in `/tmp`, not added product
behavior or acceptance substitutes. They and all validation commands completed.
The coordinator's final-source repeat above passed without a runtime change.
On a future failure, compare the original socket identifier with the captured
current owner/inode/state before choosing a resource-close barrier, investigating
another listener/client, or classifying a kernel state. Until that evidence
establishes a cause and a corresponding regression passes, this concern must not
be marked fixed.

## Bounded follow-up diagnosis: default schedulers and collision control

This follow-up also **did not reproduce or repair the historical failure**.
Source inspection began at `55630e1a797e96cfaab9c818a8d57ff09c88bf99` on `main`;
the coordinating agent advanced HEAD to
`f85f6628c5b021028f10051e339fafd0413a6479` during diagnosis. The lifecycle test,
FakeAgent helper, protocol WebSocket server and root lockfile had no committed
changes between those revisions. The existing uncommitted test diagnostics were
preserved. No runtime or test edits were made by this follow-up.

The bounded recovery assignment used `astra_gate=SOL_IMPASSE`, diagnosis mode,
received `sol_repair_rounds=0` and cumulative `astra_repair_rounds=0`. These
experiments consumed no implementation repair rounds. Documentation was appended
under a subsequent documentation-only authorization.

Source inspection confirms that this lifecycle test opens no client connection
and starts its replacement only after both process shutdown assertions. Its own
client traffic therefore supplies no evidence for a TIME_WAIT explanation.
`FakeAgent.terminate/2` and the Thousand Island supervisor sequence already await
the old process tree; `ThousandIsland.Listener.terminate/2` does not explicitly
close or acknowledge closure of the listening socket. This distinction is a
diagnostic question, not evidence that process shutdown actually preceded socket
closure in the failed run. Neither delayed resource cleanup nor a competing
socket was observed in that run. The live ephemeral range remained `32768–60999`
and `/proc/sys/net/ipv4/ip_local_reserved_ports` was empty.

Both commands below used `mix run --no-start` and explicitly started only Bandit;
they did not start the Samgita platform or Repo, query/reset a database, or contact
external services. Their outputs were captured in the diagnostic tool transcript,
not saved as separate `/tmp` log files. The excerpts below omit only the Devenv
welcome banner. Both commands completed with exit status `0`.

### Default-scheduler probe: non-reproduction

The earlier `/tmp/samgita_fake_listener_probe.exs` forced two online schedulers
and called `Port.info/1` before rebind. Those queries could alter cleanup timing;
that possibility was not established as the reason earlier probes passed.
The following exact command transformed that existing disposable script in memory
to run 1,000 cycles with the default scheduler settings and no socket queries
between process `DOWN` and restart. It retained a passive port monitor and a
pre-restart mailbox snapshot. The latter still adds instrumentation; this is not
an identical execution of the original uninstrumented failing test.

The prerequisite script's SHA-256 at execution and documentation time was
`fed323f2c3802cebd7e3ff2babeaa4f8fb2d2b2a90657ab6ec9f5bdf59b51cca`.
It is a disposable `/tmp` prerequisite, not a tracked regression artifact.

```sh
python3 - <<'PY' | devenv shell --no-tui -- env MIX_ENV=test mix run --no-start -e 'Application.ensure_all_started(:bandit); Code.eval_string(IO.read(:stdio, :eof))'
from pathlib import Path
source = Path('/tmp/samgita_fake_listener_probe.exs').read_text()
source = source.replace(':erlang.system_flag(:schedulers_online, 2)', 'IO.inspect({:erlang.system_info(:schedulers), :erlang.system_info(:schedulers_online)}, label: "SCHEDULERS")')
source = source.replace('1..3_000', '1..1_000')
start = source.index('    for {sock, _} <- socket_refs, Port.info(sock) != nil do')
end = source.index('    case FakeAgent.start_link', start)
source = source[:start] + source[end:]
source = source.replace('    case FakeAgent.start_link', '    monitor_before_restart = Process.info(self(), :messages)\n    case FakeAgent.start_link')
source = source.replace('IO.inspect({iteration, port, error,', 'IO.inspect(monitor_before_restart, label: "PASSIVE_PRE_RESTART_MAILBOX")\n        IO.inspect({iteration, port, error,')
source = source.replace('3000 immediate rebinds passed; checked socket liveness before each rebind', '1000 immediate rebinds passed; no socket queries between process DOWN and restart; default schedulers; passive monitor mailbox retained')
print(source)
PY
```

Captured output:

```text
SCHEDULERS: {16, 16}
1000 immediate rebinds passed; no socket queries between process DOWN and restart; default schedulers; passive monitor mailbox retained
```

This is another non-reproduction. No failure-time socket ownership evidence was
obtained, and no socket/process `DOWN` ordering conclusion follows from it.

### Injected competing listener: diagnostic control only

This command deliberately waits for the original owner, fake Agent, listener and
listening socket to exit, then binds a separately owned socket to the same port.
It verifies that this injected collision produces the original error signature
and that releasing the competing socket permits the same port to restart. The
extra socket-`DOWN` wait and deliberate competing bind belong only to this control;
neither was added to the lifecycle test or runtime helper.

```sh
devenv shell --no-tui -- env MIX_ENV=test mix run --no-start -e 'Application.ensure_all_started(:bandit); Code.eval_string(IO.read(:stdio, :eof))' <<'ELIXIR'
alias SamgitaWeb.FakeAgent
Logger.configure(level: :critical)
Process.flag(:trap_exit, true)
parent = self()
path = Path.join(System.tmp_dir!(), "samgita-astra-collision-#{System.unique_integer([:positive])}/journal.json")
{owner, owner_ref} = spawn_monitor(fn ->
  {:ok, fake} = FakeAgent.start_link(journal: path, token: "probe-only")
  send(parent, {:owned, fake})
  receive do :shutdown -> exit(:shutdown) end
end)
fake = receive do {:owned, pid} -> pid after 5_000 -> raise "owner startup" end
listener = :sys.get_state(fake).listener
{_, socket_owner, _, _} = Enum.find(Supervisor.which_children(listener), &(elem(&1, 0) == :listener))
[{_, original_socket}] = :sys.get_state(socket_owner).listener_sockets
port = URI.parse(FakeAgent.url(fake)).port
socket_ref = :erlang.monitor(:port, original_socket)
fake_ref = Process.monitor(fake)
listener_ref = Process.monitor(listener)
true = :erlang.suspend_process(listener)
:erlang.trace(fake, true, [:send])
send(owner, :shutdown)
receive do {:trace, ^fake, :send, {:system, _, {:terminate, _}}, ^listener} -> :ok after 5_000 -> raise "shutdown request" end
true = :erlang.resume_process(listener)
receive do {:DOWN, ^listener_ref, :process, ^listener, :normal} -> :ok after 5_000 -> raise "listener down" end
receive do {:DOWN, ^fake_ref, :process, ^fake, :shutdown} -> :ok after 5_000 -> raise "fake down" end
receive do {:DOWN, ^socket_ref, :port, ^original_socket, _} -> :ok after 5_000 -> raise "socket down" end
receive do {:DOWN, ^owner_ref, :process, ^owner, :shutdown} -> :ok after 5_000 -> raise "owner down" end
{:ok, rival} = :gen_tcp.listen(port, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])
try do
  failure = FakeAgent.start_link(journal: path, token: "probe-only", port: port)
  true = match?({:error, _}, failure)
  true = String.contains?(inspect(failure), ":eaddrinuse")
  IO.inspect(%{port: port, original_socket: original_socket, original_socket_alive: Port.info(original_socket), rival_socket: rival, rival_owner: Port.info(rival, :connected), result: failure}, label: "INJECTED_FOREIGN_BINDER_RED")
  IO.inspect(System.cmd("ss", ["-tanp", "sport", "=", ":#{port}"]), label: "COLLISION_KERNEL_OWNER")
after
  :ok = :gen_tcp.close(rival)
end
{:ok, restarted} = FakeAgent.start_link(journal: path, token: "probe-only", port: port)
^port = URI.parse(FakeAgent.url(restarted)).port
:ok = GenServer.stop(restarted)
IO.puts("CONTROL_GREEN: same port rebind succeeds after competing socket closes; original tree and socket were DOWN before injected failure; not historical-cause evidence")
ELIXIR
```

Captured output:

```text
INJECTED_FOREIGN_BINDER_RED: %{
  port: 43069,
  result: {:error,
   {{:badmatch,
     {:error, {:shutdown, {:failed_to_start_child, :listener, :eaddrinuse}}}},
    [
      {SamgitaWeb.FakeAgent, :init, 1,
       [file: ~c"test/support/fake_agent.ex", line: 32]},
      {:gen_server, :init_it, 2, [file: ~c"gen_server.erl", line: 2229]},
      {:gen_server, :init_it, 6, [file: ~c"gen_server.erl", line: 2184]},
      {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 329]}
    ]}},
  original_socket: #Port<0.12>,
  original_socket_alive: nil,
  rival_socket: #Port<0.13>,
  rival_owner: {:connected, #PID<0.95.0>}
}
COLLISION_KERNEL_OWNER: {"State  Recv-Q Send-Q Local Address:Port  Peer Address:PortProcess\nLISTEN 0      5          127.0.0.1:43069      0.0.0.0:*    users:((\"beam.smp\",pid=1500440,fd=18))\n",
 0}
CONTROL_GREEN: same port rebind succeeds after competing socket closes; original tree and socket were DOWN before injected failure; not historical-cause evidence
```

The control demonstrates an `:eaddrinuse` path even when the original socket is
already gone. The successful restart after releasing the competitor also showed
no persistent failed-startup listener preventing rebind in this control. It does
not show that a competing socket existed in the historical failure, establish a
production defect, or validate any runtime repair. The `RED`/`GREEN` labels name
the injected control states, not a repair regression cycle.

All owned diagnostic commands completed. The second BEAM's OS PID `1500440`
was confirmed absent afterward; the exclusive build/native diagnostic slot was
returned to the coordinating agent. No scoped or aggregate test suite was rerun
by this follow-up. The remaining prerequisite for a justified repair is actual
failure-time evidence distinguishing the old socket/resource from a new owner,
followed by a corresponding regression and verified fix. The historical concern
remains unresolved.
