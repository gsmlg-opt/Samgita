defmodule SamgitaCodexDriver.StdioOwnerLifecycleTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Transport.Stdio.Owner
  alias SamgitaProtocolCodex.Error

  @helper_sha "34f63e30a21b040084a473c3c5ce9e175a43dce6691021ab3126d0d53dbce39f"
  @barrier Path.join(__DIR__, "support/stdio_output_barrier.py")
  @barrier_sha "695ca5525beab0a6d585e05cf148361b0a30a8235214d647d3744a91d5527621"
  @line "owned finite output-drain marker\n"

  setup do
    assert {:unix, :linux} = :os.type()
    python = System.find_executable("python3")
    assert is_binary(python), "BLOCKED_ENV: Python 3 required"
    helper = Path.join(:code.priv_dir(:samgita_codex_driver), "stdio_owner.py")
    assert digest(helper) === @helper_sha
    assert digest(@barrier) === @barrier_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-stdio-owner-" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      )

    File.mkdir!(root)
    complete = :atomics.new(1, [])

    on_exit(fn ->
      if :atomics.get(complete, 1) === 1, do: File.rm_rf!(root)
    end)

    %{root: root, python: python, helper: helper, complete: complete}
  end

  for exit_mode <- ~w(natural close), scenario <- ~w(held released) do
    test "#{exit_mode} child with #{scenario} output preserves actual cleanup outcome", ctx do
      run_case(ctx, unquote(exit_mode), unquote(scenario))
    end
  end

  defp run_case(ctx, exit_mode, scenario) do
    journal = Path.join(ctx.root, "phases.json")

    opts = [
      :binary,
      :exit_status,
      :use_stdio,
      :hide,
      {:cd, ctx.root},
      {:args,
       [
         @barrier,
         "--helper",
         ctx.helper,
         "--scenario",
         scenario,
         "--journal",
         journal,
         "--exit-mode",
         exit_mode
       ]},
      {:env, [{~c"PYTHONDONTWRITEBYTECODE", ~c"1"}]}
    ]

    assert {:ok, owner, port} = Owner.open(ctx.python, opts)
    monitor = Process.monitor(owner.pid)

    on_exit(fn ->
      if Process.alive?(owner.pid), do: Owner.close(owner)
      assert Port.info(port) === nil
    end)

    expected_status = if scenario === "held", do: 85, else: child_status(exit_mode)

    if exit_mode === "natural" do
      {status, bytes} = collect_exit(port, <<>>, now() + 5_000)
      assert status === expected_status
      assert bytes === if(scenario === "held", do: <<>>, else: @line)
    else
      await_ready(journal, now() + 3_000)
      assert Process.alive?(owner.pid)
      assert :atomics.get(owner.completion, 1) === 0
      assert :atomics.get(owner.completion, 2) === -1
      assert_close(owner, scenario)
    end

    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1_000
    assert Port.info(port) === nil
    assert :atomics.get(owner.completion, 2) === expected_status
    assert :atomics.get(owner.completion, 1) === if(scenario === "held", do: 2, else: 1)
    assert_close(owner, scenario)
    assert_phases(journal, exit_mode, scenario, expected_status)
    assert digest(ctx.helper) === @helper_sha
    assert digest(@barrier) === @barrier_sha
    :atomics.put(ctx.complete, 1, 1)
  end

  defp assert_close(owner, "released"), do: assert(:ok = Owner.close(owner))

  defp assert_close(owner, "held") do
    failure = assert_raise Error, fn -> Owner.close(owner) end
    assert failure.code === :owned_process_shutdown_unconfirmed

    assert Exception.message(failure) ===
             "Codex request failed: owned_process_shutdown_unconfirmed"

    assert failure.details === %{"cleanup_stage" => "output_drain", "exit_status" => 85}
  end

  defp assert_phases(journal, exit_mode, scenario, expected_status) do
    events = phases(journal)

    common = ~w(worker_started output_barrier_entered group_cleanup_started
                group_cleanup_finished descendants_reaped output_join_started)

    tail =
      if scenario === "held",
        do: ~w(output_join_finished helper_returned),
        else: ~w(output_release_requested output_barrier_released output_reader_finished
             output_join_finished ack_write_started ack_write_finished helper_returned)

    assert Enum.map(events, & &1["event"]) === common ++ tail
    started = one(events, "worker_started")

    assert Map.drop(started, ["pid"]) === %{
             "event" => "worker_started",
             "scenario" => scenario,
             "exitMode" => exit_mode,
             "helperSha256" => @helper_sha
           }

    child = one(events, "group_cleanup_started")
    assert child["childWaitable"] === (exit_mode === "natural")

    assert one(events, "group_cleanup_finished") === %{
             "event" => "group_cleanup_finished",
             "childPid" => child["childPid"],
             "returnCode" => if(exit_mode === "natural", do: 0, else: -15),
             "independentlyReaped" => true
           }

    assert one(events, "descendants_reaped") === %{
             "event" => "descendants_reaped",
             "result" => true
           }

    assert one(events, "output_join_started") === %{
             "event" => "output_join_started",
             "timeoutSeconds" => 1.0
           }

    assert one(events, "output_join_finished") === %{
             "event" => "output_join_finished",
             "readerAlive" => scenario === "held"
           }

    assert one(events, "helper_returned") === %{
             "event" => "helper_returned",
             "returnCode" => expected_status
           }

    for pid <- [started["pid"], child["childPid"]] do
      assert is_integer(pid) and pid > 0
      refute File.exists?("/proc/#{pid}")
    end
  end

  defp collect_exit(port, bytes, deadline) do
    remaining = deadline - now()
    assert remaining > 0 and byte_size(bytes) <= 1_024, "Owned helper output/exit bound"

    receive do
      {^port, {:data, chunk}} -> collect_exit(port, bytes <> chunk, deadline)
      {^port, {:exit_status, status}} -> {status, bytes}
    after
      remaining -> flunk("Owned helper exit deadline")
    end
  end

  defp await_ready(journal, deadline) do
    ready = Path.rootname(journal) <> ".child-ready"

    if File.read(ready) === {:ok, "ready"} and
         Enum.any?(phases(journal), &(&1["event"] === "output_barrier_entered")) do
      :ok
    else
      assert now() < deadline, "Owned child readiness deadline"

      receive do
      after
        10 -> await_ready(journal, deadline)
      end
    end
  end

  defp phases(journal) do
    if File.exists?(journal) do
      assert File.stat!(journal).size <= 16_384
      events = journal |> File.read!() |> JSON.decode!() |> Map.fetch!("events")
      assert length(events) <= 24
      events
    else
      []
    end
  end

  defp one(events, event) do
    assert [row] = Enum.filter(events, &(&1["event"] === event))
    row
  end

  defp child_status("natural"), do: 0
  defp child_status("close"), do: 143
  defp now, do: System.monotonic_time(:millisecond)
  defp digest(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
end
