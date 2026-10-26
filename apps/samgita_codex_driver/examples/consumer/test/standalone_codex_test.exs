defmodule StandaloneCodexTest do
  use ExUnit.Case, async: false

  test "outside-umbrella consumer controls the immutable actual Codex without database or Web" do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: CODEX_BINARY must select the immutable pinned upstream executable"

    root =
      Path.join(
        System.tmp_dir!(),
        "standalone-codex-consumer-#{System.unique_integer([:positive])}"
      )

    dirs = for name <- ~w(home codex workspace), do: Path.join(root, name)
    Enum.each(dirs, &File.mkdir_p!/1)
    on_exit(fn -> File.rm_rf!(root) end)
    [home, codex, workspace] = dirs

    File.write!(Path.join(codex, "config.toml"), """
    approval_policy = "never"
    sandbox_mode = "danger-full-access"
    """)

    assert :ok =
             SamgitaProtocolCodex.Schema.validate_request(
               "thread/start",
               %{
                 "dynamicTools" => [
                   %{
                     "namespace" => "owned_catalog",
                     "name" => "synthetic_lookup",
                     "description" => "Standalone legacy declaration",
                     "inputSchema" => %{"type" => "object"},
                     "exposeToContext" => false,
                     "deferLoading" => nil
                   }
                 ]
               },
               experimental: true
             )

    assert :ok =
             SamgitaProtocolCodex.Schema.validate_request(
               "thread/resume",
               %{
                 "threadId" => "owned-source",
                 "history" => [
                   %{
                     "type" => "compaction_summary",
                     "encrypted_content" => "SYNTHETIC_OPAQUE_CHECKPOINT"
                   }
                 ]
               },
               experimental: true
             )

    unit_modes =
      for name <- ~w(plan default code pair_programming execute custom),
          payload <- [nil, %{}],
          do: %{name => payload}

    for mode <- ~w(code pair_programming execute custom) ++ unit_modes do
      assert :ok =
               SamgitaProtocolCodex.Schema.validate_request(
                 "thread/settings/update",
                 %{
                   "threadId" => "owned-thread",
                   "collaborationMode" => %{
                     "mode" => mode,
                     "settings" => %{"model" => "mock-model"}
                   }
                 },
                 experimental: true
               )
    end

    for value <- [
          "none",
          %{"none" => nil},
          %{"explicitRequestOnly" => nil},
          %{"proactive" => nil},
          %{"none" => %{}},
          %{"explicitRequestOnly" => %{}},
          %{"proactive" => %{}}
        ] do
      assert :ok =
               SamgitaProtocolCodex.Schema.validate_request(
                 "thread/start",
                 %{"multiAgentMode" => value},
                 experimental: true
               )
    end

    {:ok, pid} = StandaloneCodex.start(binary, home, codex, workspace)
    on_exit(fn -> if Process.alive?(pid), do: StandaloneCodex.close(pid) end)

    assert {:ok, %{outcome: :sent_unconfirmed}} =
             StandaloneCodex.notify(pid, %{
               "method" => "initialized",
               "params" => nil,
               "future" => %{"preserved" => [true, "é🙂"]}
             })

    assert %{phase: :ready, pending: 0, interactions: 0} =
             SamgitaCodexDriver.Session.status(pid)

    assert {:ok, %{"result" => %{"data" => [], "nextCursor" => nil}}} =
             StandaloneCodex.list_threads(pid)

    assert SamgitaCodexDriver.Session.status(pid).phase == :ready
    assert :code.which(Samgita.Repo) == :non_existing
    assert :code.which(Phoenix.Endpoint) == :non_existing
    assert :code.which(Ecto.Repo) == :non_existing

    refute Enum.any?(Application.started_applications(), fn {app, _, _} ->
             app in [:samgita, :samgita_web, :ecto, :phoenix]
           end)

    assert :ok = StandaloneCodex.close(pid)
  end
end
