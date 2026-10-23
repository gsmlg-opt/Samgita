defmodule SamgitaCodexDriver.NativeAppCatalogProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag :isolated_app_catalog
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_app_catalog_fixture.py", __DIR__)

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert System.find_executable("unshare"), "BLOCKED_ENV: unshare required"
    assert System.find_executable("ip"), "BLOCKED_ENV: ip required"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-isolated-app-catalog-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      binary: binary,
      root: root,
      scenario: tags[:scenario] || "catalog",
      journal: Path.join(root, "isolated-app-catalog-journal.json")
    }
  end

  test "native catalog merges directory pages with discovered accessibility and paginates cached state",
       ctx do
    pid = start(ctx)
    expected = catalog(["beta", "alpha", "gamma"], ["beta"])
    assert list(pid) == %{"data" => expected, "nextCursor" => nil}
    assert final_update(pid, expected)["data"] == expected
    assert Enum.map(directory(ctx), & &1["token"]) == [nil, "page 2"]
    assert tools_count(ctx) == 1

    assert list(pid, %{"limit" => 1}) == %{"data" => [hd(expected)], "nextCursor" => "1"}
    assert final_update(pid, expected)["data"] == expected
    discard(pid)

    assert list(pid, %{"limit" => 1, "cursor" => "1"}) == %{
             "data" => [Enum.at(expected, 1)],
             "nextCursor" => "2"
           }

    assert list(pid, %{"cursor" => "3"}) == %{"data" => [], "nextCursor" => nil}
    assert list(pid, %{"limit" => 0}) == %{"data" => [hd(expected)], "nextCursor" => "1"}
    assert final_update(pid, expected)["data"] == expected

    for {cursor, message} <- [
          {"bad", "invalid cursor: bad"},
          {"-1", "invalid cursor: -1"},
          {"4", "cursor 4 exceeds total apps 3"}
        ] do
      assert upstream_error(pid, "app/list", %{"cursor" => cursor}) == %{
               "code" => -32_600,
               "message" => message
             }
    end

    assert length(directory(ctx)) == 2
    assert tools_count(ctx) == 1
    assert_profile(ctx, pid)
    close(ctx, pid)
  end

  test "directory completion cannot publish an inaccessible interim catalog while tools are held",
       ctx do
    pid = start(ctx)
    state(ctx, %{"hold_tools" => true})
    request = Task.async(fn -> list(pid) end)
    await_event(ctx, "tools_waiting")
    await_event(ctx, "directory_sent", &(&1["token"] == "page 2"))
    assert Task.yield(request, 0) == nil
    assert_no_updates(pid, System.monotonic_time(:millisecond) + 150)
    File.write!(Path.join(ctx.root, "release-tools"), "release")
    expected = catalog(["beta", "alpha", "gamma"], ["beta"])
    assert Task.await(request, 10_000) == %{"data" => expected, "nextCursor" => nil}
    assert final_update(pid, expected)["data"] == expected
    assert_profile(ctx, pid)
    close(ctx, pid)
  end

  test "explicit refresh publishes current facts while directory rate limits preserve the prior cache",
       ctx do
    pid = start(ctx)
    assert list(pid)["data"] == catalog(["beta", "alpha", "gamma"], ["beta"])
    discard(pid)
    state(ctx, %{"directory_ids" => ["beta", "delta"], "tool_ids" => ["delta"]})
    expected = catalog(["delta", "beta"], ["delta"])
    assert list(pid, %{"forceRefetch" => true}) == %{"data" => expected, "nextCursor" => nil}
    assert final_update(pid, expected)["data"] == expected
    discard(pid)
    state(ctx, %{"directory_status" => 429})
    error = upstream_error(pid, "app/list", %{"forceRefetch" => true})
    assert error["code"] == -32_603
    assert error["message"] =~ "failed to list apps"
    assert Enum.any?(directory(ctx), &(&1["status"] == 429))
    assert list(pid) == %{"data" => expected, "nextCursor" => nil}
    assert final_update(pid, expected)["data"] == expected
    assert_profile(ctx, pid)
    close(ctx, pid)
  end

  @tag scenario: "installed"
  test "installed snapshots separate presence enabled state and callability without directory access",
       ctx do
    pid = start(ctx)
    assert installed(pid, false) == %{"apps" => []}
    assert tools_count(ctx) == 0
    expected = installed_apps()
    assert installed(pid, true) == %{"apps" => expected}
    assert installed(pid, false) == %{"apps" => expected}
    assert tools_count(ctx) == 1
    assert directory(ctx) == []
    assert_profile(ctx, pid)
    close(ctx, pid)

    cold = start(ctx)
    assert installed(cold, false) == %{"apps" => expected}
    assert tools_count(ctx) == 0
    assert directory(ctx) == []
    state(ctx, %{"tool_ids" => ["beta"]})
    assert installed(cold, true) == %{"apps" => [installed_app("beta", true, true)]}
    state(ctx, %{"tool_ids" => []})
    assert installed(cold, true) == %{"apps" => []}
    assert installed(cold, false) == %{"apps" => []}
    assert tools_count(ctx) == 2
    assert directory(ctx) == []
    assert_profile(ctx, cold)
    close(ctx, cold)
  end

  @tag scenario: "installed"
  test "a rejected tools refresh reports a native failure and retains the committed installed snapshot",
       ctx do
    pid = start(ctx)
    committed = installed(pid, true)
    state(ctx, %{"fail_tools" => true, "tool_ids" => ["beta"]})
    error = upstream_error(pid, "app/installed", %{"forceRefresh" => true})
    assert error["code"] == -32_603
    assert error["message"] =~ "failed to refresh installed connector runtime state"
    assert installed(pid, false) == committed
    assert tools_count(ctx) == 2
    assert directory(ctx) == []
    state(ctx, %{"fail_tools" => false})
    assert installed(pid, true) == %{"apps" => [installed_app("beta", true, true)]}
    assert_profile(ctx, pid)
    close(ctx, pid)
  end

  test "invalid and unknown thread references reject both methods without backend discovery",
       ctx do
    pid = start(ctx)

    for method <- ["app/list", "app/installed"] do
      for id <- ["invalid-thread", "67e55044-10b1-426f-9247-bb680e5fe0c8"] do
        error = upstream_error(pid, method, %{"threadId" => id})
        assert error["code"] == -32_600
        assert error["message"] =~ "thread"
      end
    end

    assert directory(ctx) == []
    assert tools_count(ctx) == 0
    assert_profile(ctx, pid)
    close(ctx, pid)
  end

  @tag scenario: "disabled"
  test "disabled app capability returns empty catalog and installed state without discovery",
       ctx do
    assert_disabled(ctx)
  end

  @tag scenario: "api_key"
  test "API key auth cannot enable hosted app discovery", ctx do
    assert_disabled(ctx)
  end

  defp assert_disabled(ctx) do
    pid = start(ctx)

    for refresh <- [false, true] do
      assert list(pid, %{"forceRefetch" => refresh}) == %{"data" => [], "nextCursor" => nil}
      assert installed(pid, refresh) == %{"apps" => []}
    end

    assert directory(ctx) == []
    assert tools_count(ctx) == 0
    assert_no_updates(pid, System.monotonic_time(:millisecond) + 50)
    assert_profile(ctx, pid)
    close(ctx, pid)
  end

  defp start(ctx) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: System.find_executable("python3"),
             args: [
               @script,
               "--codex",
               ctx.binary,
               "--root",
               ctx.root,
               "--scenario",
               ctx.scenario
             ],
             env: %{"CODEX_HOME" => Path.join(ctx.root, "codex")}
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_isolated_app_catalog", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp list(pid, params \\ %{}), do: call(pid, "app/list", params)
  defp installed(pid, refresh), do: call(pid, "app/installed", %{"forceRefresh" => refresh})

  defp installed_apps do
    [
      installed_app("alpha", true, true),
      installed_app("blocked", true, false),
      installed_app("disabled", false, false)
    ]
  end

  defp installed_app(id, enabled, callable),
    do: %{
      "id" => id,
      "runtimeName" => "#{String.capitalize(id)} Runtime",
      "enabled" => enabled,
      "callable" => callable
    }

  defp catalog(ids, accessible) do
    Enum.map(ids, fn id ->
      %{
        "id" => id,
        "name" => "#{String.capitalize(id)} Directory",
        "description" => "Directory #{id}",
        "logoUrl" => nil,
        "logoUrlDark" => nil,
        "iconAssets" => nil,
        "iconDarkAssets" => nil,
        "distributionChannel" => nil,
        "branding" => nil,
        "appMetadata" => nil,
        "labels" => nil,
        "installUrl" => "https://chatgpt.com/apps/#{id}-directory/#{id}",
        "isAccessible" => id in accessible,
        "isEnabled" => id != "disabled",
        "pluginDisplayNames" => []
      }
    end)
  end

  defp state(ctx, changes) do
    path = Path.join(ctx.root, "catalog-state.json")
    current = path |> File.read!() |> JSON.decode!()
    pending = path <> ".pending"
    File.write!(pending, JSON.encode!(Map.merge(current, changes)))
    File.rename!(pending, path)
  end

  defp final_update(pid, expected),
    do: final_update(pid, expected, System.monotonic_time(:millisecond) + 5_000)

  defp final_update(pid, expected, deadline) do
    assert {:ok, events} = Session.drain(pid)

    found =
      Enum.find(
        events,
        &(&1.wire["method"] == "app/list/updated" and &1.wire["params"]["data"] == expected)
      )

    if found do
      found.wire["params"]
    else
      assert System.monotonic_time(:millisecond) < deadline,
             "native final app-list update deadline"

      pause(pid)
      final_update(pid, expected, deadline)
    end
  end

  defp assert_no_updates(pid, deadline) do
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.wire["method"] == "app/list/updated"))

    if System.monotonic_time(:millisecond) < deadline do
      pause(pid)
      assert_no_updates(pid, deadline)
    end
  end

  defp await_event(ctx, name, predicate \\ fn _ -> true end),
    do: await_event(ctx, name, predicate, System.monotonic_time(:millisecond) + 5_000)

  defp await_event(ctx, name, predicate, deadline) do
    if Enum.any?(events(ctx), &(&1["event"] == name and predicate.(&1))) do
      :ok
    else
      assert System.monotonic_time(:millisecond) < deadline, "owned catalog barrier #{name}"

      receive do
      after
        10 -> :ok
      end

      await_event(ctx, name, predicate, deadline)
    end
  end

  defp pause(pid) do
    assert Session.status(pid).phase == :ready

    receive do
      {:codex_driver, ^pid, :events_available} -> :ok
      {:codex_driver, ^pid, {:gap, _}} -> flunk("unexpected app catalog event gap")
    after
      10 -> :ok
    end
  end

  defp discard(pid), do: assert({:ok, _events} = Session.drain(pid))

  defp assert_profile(ctx, pid) do
    data = journal(ctx)
    assert data["namespace"]["parent"] != data["namespace"]["child"]
    assert data["namespace"]["interfaces"] == ["lo"]
    refute data["namespace"]["default_route"]

    refute Enum.any?(
             events(ctx),
             &(&1["event"] in ["unexpected_http", "fixture_error", "forbidden_mcp"])
           )

    for event <- events(ctx), event["event"] in ["directory", "mcp"] do
      if event["event"] == "directory" do
        assert event["bearer_verified"]
        assert event["account_verified"]
      else
        assert event["bearer_absent"]
        assert event["account_absent"]
      end

      assert event["sku_verified"]
    end

    assert call(pid, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert Session.status(pid).phase == :ready

    auth = ctx.root |> Path.join("codex/auth.json") |> File.read!() |> JSON.decode!()
    secrets = Map.values(auth["tokens"] || %{}) ++ [auth["OPENAI_API_KEY"]]

    for path <- [ctx.journal, Path.join(ctx.root, "native-stderr.log")],
        secret <- secrets,
        is_binary(secret) and secret != "" do
      refute File.read!(path) =~ secret
    end
  end

  defp close(ctx, pid) do
    started = Enum.find(events(ctx), &(&1["event"] == "native_started"))
    assert :ok = Session.close(pid)

    for key <- ["pid", "controller_pid", "namespace_owner_pid"] do
      refute File.exists?("/proc/#{Map.fetch!(started, key)}"),
             "owned catalog process must be reaped"
    end

    assert Enum.any?(events(ctx), &(&1["event"] == "native_closed"))

    refute Enum.any?(
             events(ctx),
             &(&1["event"] in ["unexpected_http", "fixture_error", "forbidden_mcp"])
           )
  end

  defp journal(ctx), do: ctx.journal |> File.read!() |> JSON.decode!()
  defp events(ctx), do: journal(ctx)["events"]
  defp directory(ctx), do: Enum.filter(events(ctx), &(&1["event"] == "directory"))
  defp tools_count(ctx), do: Enum.count(events(ctx), &(&1["event"] == "tools_list"))

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params)
    result
  end

  defp upstream_error(pid, method, params) do
    assert {:error, %Error{code: :upstream_error, wire: %{"error" => error}}} =
             Session.request(pid, method, params)

    error
  end
end
