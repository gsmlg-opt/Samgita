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

    for method <- ["thread/settings/update", "turn/start", "turn/settings/update"],
        summary <- ~w(auto concise detailed none),
        payload <- [nil, %{}] do
      params = %{"threadId" => "owned-thread", "summary" => %{summary => payload}}

      params =
        case method do
          "turn/start" -> Map.put(params, "input", [])
          "turn/settings/update" -> Map.put(params, "turnId", "owned-turn")
          "thread/settings/update" -> params
        end

      assert :ok =
               SamgitaProtocolCodex.Schema.validate_request(method, params, experimental: true)
    end

    for method <- ["thread/start", "thread/resume", "thread/settings/update", "turn/start"],
        personality <- ~w(none friendly pragmatic),
        payload <- [nil, %{}] do
      params = %{"personality" => %{personality => payload}}

      params =
        case method do
          "thread/start" -> params
          "turn/start" -> Map.merge(params, %{"threadId" => "owned-thread", "input" => []})
          _ -> Map.put(params, "threadId", "owned-thread")
        end

      assert :ok =
               SamgitaProtocolCodex.Schema.validate_request(method, params, experimental: true)
    end

    for mode <- ~w(legacy paginated), payload <- [nil, %{}] do
      assert :ok =
               SamgitaProtocolCodex.Schema.validate_request(
                 "thread/start",
                 %{"historyMode" => %{mode => payload}},
                 experimental: true
               )
    end

    for source <- ~w(startup clear), payload <- [nil, %{}], opts <- [[], [experimental: true]] do
      assert :ok =
               SamgitaProtocolCodex.Schema.validate_request(
                 "thread/start",
                 %{"sessionStartSource" => %{source => payload}},
                 opts
               )
    end

    for key <- ~w(created_at updated_at recency_at), payload <- [nil, %{}] do
      assert :ok =
               SamgitaProtocolCodex.Schema.validate_request(
                 "thread/search",
                 %{"searchTerm" => "Owned consumer query", "sortKey" => %{key => payload}},
                 experimental: true
               )
    end

    for key <- ~w(created_at updated_at recency_at section_position),
        payload <- [nil, %{}],
        opts <- [[], [experimental: true]] do
      assert :ok =
               SamgitaProtocolCodex.Schema.validate_request(
                 "thread/list",
                 %{"sortKey" => %{key => payload}},
                 opts
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
