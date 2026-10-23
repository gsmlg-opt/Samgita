defmodule SamgitaCodexDriver.EnvironmentProfilesTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  import TurnFixture, except: [setup: 1]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @builtins [":read-only", ":workspace", ":danger-full-access"]

  setup context, do: TurnFixture.setup(context)

  test "local environment exposes stable shell and cwd metadata with ready status", context do
    pid = start(context)

    assert call(pid, "environment/status", %{"environmentId" => "local"}) == %{
             "status" => "ready"
           }

    info = call(pid, "environment/info", %{"environmentId" => "local"})
    assert %{"shell" => %{"name" => name, "path" => path}, "cwd" => cwd} = info
    assert name in ["zsh", "bash", "sh", "fish", "dash", "nu"]
    assert is_binary(path) and path != ""
    assert cwd == "file://" <> context.fixture.workspace
    assert call(pid, "environment/info", %{"environmentId" => "local"}) == info

    assert call(pid, "environment/status", %{"environmentId" => "local"}) == %{
             "status" => "ready"
           }

    assert ModelFixture.requests(context.fixture) == []
  end

  test "unknown environments distinguish status metadata from info request errors", context do
    pid = start(context)

    for id <- ["missing", "", "LOCAL"] do
      message = "unknown environment id `#{id}`"

      assert call(pid, "environment/status", %{"environmentId" => id}) == %{
               "status" => "unknown",
               "error" => message
             }

      assert upstream_error(pid, "environment/info", %{"environmentId" => id}) == %{
               "code" => -32_600,
               "message" => message
             }
    end

    assert Session.status(pid).phase == :ready
    assert ModelFixture.requests(context.fixture) == []
  end

  test "invalid registrations remain absent and experimental negotiation fences environment RPCs",
       context do
    pid = start(context)

    # Every successful add starts a WebSocket connection in this pinned version.
    # These rejected registrations cannot start an executor or contact a destination.
    for {id, url, detail} <- [
          {"", "ws://127.0.0.1:1", "environment id cannot be empty"},
          {"local", "ws://127.0.0.1:1",
           "environment id `local` is reserved for EnvironmentManager"},
          {"empty-url", " ", "remote environment requires an exec-server url"},
          {"disabled-url", "none", "remote environment cannot use disabled exec-server url"}
        ] do
      assert upstream_error(pid, "environment/add", %{
               "environmentId" => id,
               "execServerUrl" => url
             }) == %{"code" => -32_600, "message" => "exec-server protocol error: " <> detail}

      if id != "local" do
        assert call(pid, "environment/status", %{"environmentId" => id})["status"] == "unknown"
      end
    end

    # A request ID is synthetic metadata, not a credential. Its insecure remote
    # destination must be rejected before registration or connection startup.
    assert upstream_error(pid, "environment/add", %{
             "environmentId" => "insecure",
             "execServerUrl" => "ws://executor.invalid",
             "websocketRequestId" => "synthetic-request"
           }) == %{
             "code" => -32_600,
             "message" =>
               "exec-server protocol error: exec-server WebSocket headers require wss:// or a loopback destination"
           }

    assert call(pid, "environment/status", %{"environmentId" => "insecure"})["status"] ==
             "unknown"

    assert call(pid, "environment/status", %{"environmentId" => "local"}) == %{
             "status" => "ready"
           }

    assert :ok = Session.close(pid)
    stable = start(context, experimental: false)

    for {method, params} <- [
          {"environment/add", %{"environmentId" => "blocked", "execServerUrl" => "none"}},
          {"environment/info", %{"environmentId" => "local"}},
          {"environment/status", %{"environmentId" => "local"}}
        ] do
      assert upstream_error(stable, method, params, validation: :wire) == %{
               "code" => -32_600,
               "message" => "#{method} requires experimentalApi capability"
             }
    end

    # Permission profile discovery is a stable method.
    assert Enum.map(call(stable, "permissionProfile/list", %{})["data"], & &1["id"]) == @builtins
    assert ModelFixture.requests(context.fixture) == []
  end

  test "profile catalog preserves descriptions, stable order and exact pagination boundaries",
       context do
    append_config(context, """

    [permissions.dev]
    description = "Synthetic development metadata."
    [permissions.dev.filesystem]
    ":workspace_roots" = "write"
    [permissions.audit]
    description = "Synthetic audit metadata."
    [permissions.audit.filesystem]
    ":workspace_roots" = "read"
    """)

    pid = start(context)
    full = call(pid, "permissionProfile/list", %{})

    expected =
      Enum.map(@builtins, &profile(&1)) ++
        [
          profile("audit", "Synthetic audit metadata."),
          profile("dev", "Synthetic development metadata.")
        ]

    assert full == %{"data" => expected, "nextCursor" => nil}

    assert call(pid, "permissionProfile/list", %{"cursor" => nil, "limit" => nil, "cwd" => nil}) ==
             full

    assert call(pid, "permissionProfile/list", %{"limit" => 0}) == %{
             "data" => [hd(expected)],
             "nextCursor" => "1"
           }

    first = call(pid, "permissionProfile/list", %{"limit" => 3})
    assert first == %{"data" => Enum.take(expected, 3), "nextCursor" => "3"}

    assert call(pid, "permissionProfile/list", %{"limit" => 3, "cursor" => first["nextCursor"]}) ==
             %{"data" => Enum.drop(expected, 3), "nextCursor" => nil}

    assert call(pid, "permissionProfile/list", %{"cursor" => "5"}) == %{
             "data" => [],
             "nextCursor" => nil
           }

    for {cursor, message} <- [
          {"invalid", "invalid cursor: invalid"},
          {"-1", "invalid cursor: -1"},
          {"6", "cursor 6 exceeds total permission profiles 5"}
        ] do
      assert upstream_error(pid, "permissionProfile/list", %{"cursor" => cursor}) == %{
               "code" => -32_600,
               "message" => message
             }
    end

    assert ModelFixture.requests(context.fixture) == []
  end

  test "requested cwd selects trusted project profiles without selecting a default profile",
       context do
    workspace = context.fixture.workspace
    outside = Path.join(context.root, "outside")
    File.mkdir_p!(outside)
    File.mkdir_p!(Path.join(workspace, ".git"))
    File.mkdir_p!(Path.join(workspace, ".codex"))

    File.write!(Path.join(workspace, ".codex/config.toml"), """
    [permissions.project]
    description = "Synthetic project metadata."
    [permissions.project.filesystem]
    ":workspace_roots" = "read"
    """)

    append_config(context, "\n[projects.#{JSON.encode!(workspace)}]\ntrust_level = \"trusted\"\n")
    original = File.read!(Path.join(context.fixture.codex_home, "config.toml"))
    pid = start(context)

    for params <- [%{}, %{"cwd" => nil}, %{"cwd" => outside}] do
      assert call(pid, "permissionProfile/list", params)["data"] ==
               Enum.map(@builtins, &profile(&1))
    end

    assert call(pid, "permissionProfile/list", %{"cwd" => workspace}) == %{
             "data" =>
               Enum.map(@builtins, &profile(&1)) ++
                 [profile("project", "Synthetic project metadata.")],
             "nextCursor" => nil
           }

    assert File.read!(Path.join(context.fixture.codex_home, "config.toml")) == original
    assert ModelFixture.requests(context.fixture) == []
  end

  test "cwd-dependent compilation changes allowed metadata while retaining profile presence",
       context do
    append_config(context, """

    [permissions.scoped.workspace_roots]
    "private/*.env" = true
    [permissions.scoped.filesystem]
    ":workspace_roots" = "write"
    """)

    unsafe_cwd = Path.join(context.fixture.workspace, "[workspace]")
    File.mkdir_p!(unsafe_cwd)
    pid = start(context)

    # This is the pinned upstream catalog compilation case. Metadata alone does
    # not demonstrate that any filesystem or process sandbox has been enforced.
    for {cwd, allowed} <- [{unsafe_cwd, false}, {context.fixture.workspace, true}] do
      catalog = call(pid, "permissionProfile/list", %{"cwd" => cwd})
      assert Enum.map(catalog["data"], & &1["id"]) == @builtins ++ ["scoped"]

      assert Enum.find(catalog["data"], &(&1["id"] == "scoped")) == %{
               "id" => "scoped",
               "description" => nil,
               "allowed" => allowed
             }

      assert catalog["nextCursor"] == nil
    end

    assert ModelFixture.requests(context.fixture) == []
  end

  defp append_config(context, text),
    do: File.write!(Path.join(context.fixture.codex_home, "config.toml"), text, [:append])

  defp profile(id, description \\ nil),
    do: %{"id" => id, "description" => description, "allowed" => true}
end
