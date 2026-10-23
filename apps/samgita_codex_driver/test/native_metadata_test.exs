defmodule SamgitaCodexDriver.NativeMetadataTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error
  import TurnFixture, except: [setup: 1]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @missing "00000000-0000-4000-8000-000000000000"

  setup context do
    TurnFixture.setup(context)
  end

  test "Git patches trim replacements preserve omissions and clear explicit nulls", ctx do
    pid = start(ctx)
    id = thread(ctx, pid, %{"historyMode" => "legacy"})
    original = read(pid, id)

    git = %{
      "sha" => "abc123",
      "branch" => "feature/λ",
      "originUrl" => "git@example.invalid:org/repo.git"
    }

    padded = Map.new(git, fn {key, value} -> {key, "  #{value}\n"} end)
    full = update(pid, id, %{"gitInfo" => padded})
    assert full["gitInfo"] == git
    assert full["id"] == id
    assert full["sessionId"] == original["sessionId"]
    assert full["status"] == %{"type" => "idle"}
    assert read(pid, id)["gitInfo"] == git

    partial = update(pid, id, %{"gitInfo" => %{"branch" => "feature/partial"}})
    expected = %{git | "branch" => "feature/partial"}
    assert partial["gitInfo"] == expected

    assert update(pid, id, %{"gitInfo" => %{"sha" => nil}})["gitInfo"] == %{
             expected
             | "sha" => nil
           }

    cleared =
      update(pid, id, %{"gitInfo" => %{"sha" => nil, "branch" => nil, "originUrl" => nil}})

    assert cleared["gitInfo"] == nil
    assert read(pid, id)["gitInfo"] == nil
    assert :ok = Session.close(pid)
    cold = start(ctx)
    assert read(cold, id)["gitInfo"] == nil

    assert update(cold, id, %{"gitInfo" => %{"branch" => "cold-update"}})["gitInfo"] == %{
             "sha" => nil,
             "branch" => "cold-update",
             "originUrl" => nil
           }

    assert read(cold, id)["gitInfo"]["branch"] == "cold-update"
    assert_clean(ctx, cold)
  end

  test "origin credentials are sanitized in responses rollouts and cold reads without remote access",
       ctx do
    pid = start(ctx)
    id = thread(ctx, pid, %{"historyMode" => "legacy"})

    for {origin, sanitized} <- [
          {"https://synthetic-origin-user:synthetic-origin-secret@example.invalid/org/repo%20name.git",
           "https://example.invalid/org/repo%20name.git"},
          {"ssh://synthetic-origin-user:synthetic-origin-secret@example.invalid/org/repo.git",
           "ssh://example.invalid/org/repo.git"},
          {"synthetic-origin-user@example.invalid:org/repo.git", "example.invalid:org/repo.git"},
          {"git@example.invalid:org/repo.git", "git@example.invalid:org/repo.git"}
        ] do
      response = update(pid, id, %{"gitInfo" => %{"originUrl" => origin}})
      assert response["gitInfo"]["originUrl"] == sanitized
      assert read(pid, id)["gitInfo"]["originUrl"] == sanitized
      assert File.read!(response["path"]) =~ sanitized
      assert_sanitized_files(ctx)
    end

    assert :ok = Session.close(pid)
    cold = start(ctx)
    assert read(cold, id)["gitInfo"]["originUrl"] == "git@example.invalid:org/repo.git"
    assert_sanitized_files(ctx)
    assert_clean(ctx, cold)
  end

  test "omitted null and invalid Git patches preserve prior metadata", ctx do
    pid = start(ctx)
    id = thread(ctx, pid)

    git = %{
      "sha" => "abc123",
      "branch" => "unchanged",
      "originUrl" => "https://example.invalid/repo.git"
    }

    update(pid, id, %{"gitInfo" => git})

    for extra <- [%{}, %{"gitInfo" => nil}] do
      assert update(pid, id, Map.put(extra, "daybreakEnabled", false))["gitInfo"] == git
    end

    for {extra, message} <- [
          {%{}, "thread metadata update must include at least one field"},
          {%{"gitInfo" => nil, "projectId" => nil, "daybreakEnabled" => nil},
           "thread metadata update must include at least one field"},
          {%{"gitInfo" => %{}}, "gitInfo must include at least one field"},
          {%{"gitInfo" => %{"sha" => " \n "}}, "gitInfo.sha must not be empty"},
          {%{"gitInfo" => %{"branch" => " \n "}}, "gitInfo.branch must not be empty"},
          {%{"gitInfo" => %{"originUrl" => " \n "}}, "gitInfo.originUrl must not be empty"},
          {%{
             "gitInfo" => %{
               "branch" => "must-not-persist",
               "originUrl" => "ext::command synthetic-origin-secret"
             }
           }, "gitInfo.originUrl must be a valid Git remote"}
        ] do
      assert upstream_error(pid, "thread/metadata/update", Map.put(extra, "threadId", id)) == %{
               "code" => -32_600,
               "message" => message
             }

      assert read(pid, id)["gitInfo"] == git
      assert project_events(pid) == []
    end

    for extra <- [%{"gitInfo" => %{"sha" => 42}}, %{"daybreakEnabled" => "yes"}] do
      error =
        upstream_error(pid, "thread/metadata/update", Map.put(extra, "threadId", id),
          validation: :wire
        )

      assert error["code"] == -32_600
      assert error["message"] =~ "Invalid request"
      assert read(pid, id)["gitInfo"] == git
    end

    assert_clean(ctx, pid)
  end

  test "project assignments preserve nulls clear empty strings and notify only on membership changes",
       ctx do
    pid = start(ctx)
    id = thread(ctx, pid)
    update(pid, id, %{"gitInfo" => %{"branch" => "persistent-before-turn"}})
    first = project(pid, "First")
    second = project(pid, "Second")
    assert project_events(pid) == []

    assigned = update(pid, id, %{"projectId" => first})
    assert assigned["projectId"] == first
    assert project_events(pid) == [project_change(id, first)]
    assert read(pid, id)["projectId"] == first
    assert update(pid, id, %{"projectId" => first})["projectId"] == first
    assert project_events(pid) == []

    for extra <- [%{}, %{"projectId" => nil}] do
      response = update(pid, id, Map.put(extra, "gitInfo", %{"branch" => "still-assigned"}))
      assert response["projectId"] == first
      assert project_events(pid) == []
    end

    assert :ok = Session.close(pid)
    cold = start(ctx)
    assert read(cold, id)["projectId"] == first
    assert update(cold, id, %{"projectId" => second})["projectId"] == second
    assert project_events(cold) == [project_change(id, second)]
    assert update(cold, id, %{"projectId" => ""})["projectId"] == nil
    assert project_events(cold) == [project_change(id, nil)]
    assert update(cold, id, %{"projectId" => ""})["projectId"] == nil
    assert project_events(cold) == []
    assert read(cold, id)["projectId"] == nil
    assert read(cold, id)["gitInfo"]["branch"] == "still-assigned"
    assert_clean(ctx, cold)
  end

  test "experimental field gates retain stable Git updates under absent and false negotiation",
       ctx do
    for negotiation <- [:absent, false] do
      pid = start_profile(ctx, negotiation)
      id = thread(ctx, pid)

      assert update(pid, id, %{"gitInfo" => %{"branch" => "stable-git"}})["gitInfo"]["branch"] ==
               "stable-git"

      for {field, value} <- [
            {"projectId", ""},
            {"projectId", @missing},
            {"daybreakEnabled", false},
            {"daybreakEnabled", true}
          ] do
        params = %{"threadId" => id, field => value, "gitInfo" => %{"branch" => "blocked"}}

        assert {:error, %Error{code: :experimental_api_required}} =
                 Session.request(pid, "thread/metadata/update", params)

        assert upstream_error(pid, "thread/metadata/update", params, validation: :wire) == %{
                 "code" => -32_600,
                 "message" =>
                   "thread/metadata/update.#{field} requires experimentalApi capability"
               }

        assert read(pid, id)["gitInfo"]["branch"] == "stable-git"
        assert project_events(pid) == []
      end

      assert update(pid, id, %{
               "projectId" => nil,
               "daybreakEnabled" => nil,
               "gitInfo" => %{"branch" => "null-fields"}
             })["gitInfo"]["branch"] == "null-fields"

      assert_clean(ctx, pid)
      assert :ok = Session.close(pid)
    end
  end

  test "Daybreak choice persists true false and null semantics across cold and archived updates",
       ctx do
    pid = start(ctx)
    id = thread(ctx, pid, %{"historyMode" => "legacy"})
    assert update(pid, id, %{"daybreakEnabled" => true})["daybreakEnabled"] == true
    assert read(pid, id)["daybreakEnabled"] == true
    assert update(pid, id, %{"daybreakEnabled" => false})["daybreakEnabled"] == false

    for extra <- [%{}, %{"daybreakEnabled" => nil}] do
      assert update(pid, id, Map.put(extra, "gitInfo", %{"branch" => "daybreak-preserved"}))[
               "daybreakEnabled"
             ] == false
    end

    assert :ok = Session.close(pid)
    cold = start(ctx)
    assert read(cold, id)["daybreakEnabled"] == false
    assert call(cold, "thread/archive", %{"threadId" => id}) == %{}

    archived =
      update(cold, id, %{"daybreakEnabled" => true, "gitInfo" => %{"branch" => "archived-change"}})

    assert archived["daybreakEnabled"] == true
    assert archived["gitInfo"]["branch"] == "archived-change"
    assert read(cold, id)["daybreakEnabled"] == true
    assert :ok = Session.close(cold)
    restarted = start(ctx)
    assert read(restarted, id)["daybreakEnabled"] == true
    assert read(restarted, id)["gitInfo"]["branch"] == "archived-change"
    assert project_events(restarted) == []
    assert_clean(ctx, restarted)
  end

  test "combined invalid patches missing identities and ephemeral updates have no partial effects",
       ctx do
    pid = start(ctx)
    id = thread(ctx, pid)
    update(pid, id, %{"gitInfo" => %{"branch" => "original"}})
    existing = project(pid, "Existing")
    ephemeral = thread(ctx, pid, %{"ephemeral" => true})

    for {params, message} <- [
          {%{"threadId" => id, "projectId" => @missing, "gitInfo" => %{"branch" => "rejected"}},
           "project not found: #{@missing}"},
          {%{"threadId" => id, "projectId" => existing, "gitInfo" => %{}},
           "gitInfo must include at least one field"},
          {%{"threadId" => id, "projectId" => existing, "gitInfo" => %{"branch" => " "}},
           "gitInfo.branch must not be empty"},
          {%{"threadId" => @missing, "gitInfo" => %{"branch" => "absent"}},
           "no rollout found for thread id #{@missing}"},
          {%{"threadId" => ephemeral, "gitInfo" => %{"branch" => "ephemeral"}},
           "ephemeral thread does not support metadata updates: #{ephemeral}"}
        ] do
      assert upstream_error(pid, "thread/metadata/update", params) == %{
               "code" => -32_600,
               "message" => message
             }

      assert read(pid, id)["projectId"] == nil
      assert read(pid, id)["gitInfo"]["branch"] == "original"
      assert project_events(pid) == []
    end

    error =
      upstream_error(pid, "thread/metadata/update", %{
        "threadId" => "invalid",
        "gitInfo" => %{"branch" => "bad"}
      })

    assert error["code"] == -32_600
    assert error["message"] =~ "invalid thread id"
    assert read(pid, id)["gitInfo"]["branch"] == "original"
    assert_clean(ctx, pid)
  end

  defp update(pid, id, fields),
    do: call(pid, "thread/metadata/update", Map.put(fields, "threadId", id))["thread"]

  defp read(pid, id), do: call(pid, "thread/read", %{"threadId" => id})["thread"]

  defp project(pid, name) do
    call(pid, "project/create", %{
      "name" => name,
      "roots" => [],
      "idempotencyKey" => "metadata-#{name}"
    })["project"]["id"]
  end

  defp project_events(pid) do
    assert {:ok, events} = Session.drain(pid)

    for event <- events,
        event.wire["method"] == "thread/project/updated",
        do: event.wire["params"]
  end

  defp project_change(id, project), do: %{"threadId" => id, "projectId" => project}

  defp assert_sanitized_files(ctx) do
    for file <- Path.wildcard(Path.join(ctx.fixture.codex_home, "**/*"), match_dot: true),
        File.regular?(file) do
      bytes = File.read!(file)
      assert :binary.match(bytes, "synthetic-origin-secret") == :nomatch
      assert :binary.match(bytes, "synthetic-origin-user") == :nomatch
    end
  end

  defp assert_clean(ctx, pid) do
    assert ModelFixture.requests(ctx.fixture) == []
    assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid)
  end

  defp start_profile(ctx, negotiation) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: ctx.binary,
             args: ["app-server", "--listen", "stdio://"],
             cwd: ctx.fixture.workspace,
             env: %{
               "HOME" => ctx.fixture.home,
               "CODEX_HOME" => ctx.fixture.codex_home,
               "RUST_LOG" => "off",
               "CODEX_DISABLE_REMOTE_CONTROL" => "1"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)
    params = %{"clientInfo" => %{"name" => "samgita_metadata_profile", "version" => "0.1.0"}}

    params =
      if negotiation == :absent,
        do: params,
        else: Map.put(params, "capabilities", %{"experimentalApi" => negotiation})

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.request_native(pid, %{
               "id" => "initialize-profile",
               "method" => "initialize",
               "params" => params
             })

    pid
  end
end
