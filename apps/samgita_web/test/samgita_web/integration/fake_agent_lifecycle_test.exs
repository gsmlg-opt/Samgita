defmodule SamgitaWeb.FakeAgentLifecycleTest do
  use ExUnit.Case, async: false
  alias SamgitaWeb.FakeAgent

  test "owner shutdown waits for the listener before the same port can restart" do
    parent = self()
    root = Path.join(System.tmp_dir!(), "samgita-fake-lifecycle-#{Ecto.UUID.generate()}")
    path = Path.join(root, "journal.json")
    File.mkdir!(root)

    {owner, owner_monitor} =
      spawn_monitor(fn ->
        parent_monitor = Process.monitor(parent)
        {:ok, fake} = FakeAgent.start_link(journal: path, token: "lifecycle-only")
        send(parent, {:owned_fake, self(), fake})

        receive do
          :shutdown -> exit(:shutdown)
          {:DOWN, ^parent_monitor, :process, ^parent, _reason} -> exit(:shutdown)
        end
      end)

    fake =
      receive do
        {:owned_fake, ^owner, fake} -> fake
        {:DOWN, ^owner_monitor, :process, ^owner, reason} -> flunk(inspect(reason))
      after
        5_000 -> flunk("fake Agent startup timed out")
      end

    port = fake |> FakeAgent.url() |> URI.parse() |> Map.fetch!(:port)
    listener = :sys.get_state(fake).listener
    fake_monitor = Process.monitor(fake)
    listener_monitor = Process.monitor(listener)
    assert :erlang.suspend_process(listener)

    try do
      :erlang.trace(fake, true, [:send])
      send(owner, :shutdown)

      receive do
        {:trace, ^fake, :send, {:system, _from, {:terminate, _reason}}, ^listener} ->
          :ok

        {:DOWN, ^fake_monitor, :process, ^fake, reason} ->
          flunk("fake Agent exited before awaiting its listener: #{inspect(reason)}")
      after
        5_000 -> flunk("fake Agent did not request synchronous listener shutdown")
      end

      assert :erlang.resume_process(listener)
      assert_receive {:DOWN, ^listener_monitor, :process, ^listener, :normal}, 5_000
      assert_receive {:DOWN, ^fake_monitor, :process, ^fake, :shutdown}, 5_000

      restarted =
        start_supervised!({FakeAgent, journal: path, token: "lifecycle-only", port: port})

      assert URI.parse(FakeAgent.url(restarted)).port == port
      assert :ok = stop_supervised(FakeAgent)
    after
      cleanup_fake = Process.monitor(fake)
      cleanup_listener = Process.monitor(listener)
      if Process.alive?(owner), do: Process.exit(owner, :shutdown)
      if Process.alive?(listener), do: assert(:erlang.resume_process(listener))
      assert_receive {:DOWN, ^cleanup_fake, :process, ^fake, _reason}, 5_000
      assert_receive {:DOWN, ^cleanup_listener, :process, ^listener, _reason}, 5_000
      File.rm_rf!(root)
    end
  end

  test "explicit simulated cessation persists without duplicating the execution start" do
    root = Path.join(System.tmp_dir!(), "samgita-fake-cessation-#{Ecto.UUID.generate()}")
    path = Path.join(root, "journal.json")
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    fake = start_supervised!({FakeAgent, journal: path, token: "cessation-only"})
    operation = Ecto.UUID.generate()
    assert {:error, :not_started} = FakeAgent.stop_once(fake, operation)
    assert :started = FakeAgent.start_once(fake, operation)
    assert {:ok, evidence} = FakeAgent.stop_once(fake, operation)
    assert {:ok, ^evidence} = FakeAgent.stop_once(fake, operation)
    assert evidence["operation_id"] == operation
    assert evidence["state"] == "stopped"
    assert evidence["evidence_ref"] == "fake-agent-journal:#{path}##{operation}"

    assert %{"stops" => %{^operation => ^evidence}, "starts" => [^operation]} =
             path |> File.read!() |> Jason.decode!()

    assert :ok = stop_supervised(FakeAgent)
    restarted = start_supervised!({FakeAgent, journal: path, token: "cessation-only"})
    assert {:ok, ^evidence} = FakeAgent.stop_once(restarted, operation)
    assert :already_started = FakeAgent.start_once(restarted, operation)
    assert FakeAgent.snapshot(restarted)["starts"] == [operation]
    assert FakeAgent.snapshot(restarted)["stops"] == %{operation => evidence}
  end
end
