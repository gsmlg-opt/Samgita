defmodule SamgitaCodexDriver.AuthInteractionsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/auth_interaction_fixture.py", __DIR__)

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    root =
      Path.join(System.tmp_dir!(), "samgita-codex-auth-#{System.unique_integer([:positive])}")

    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, tags[:scenario] || "refresh")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn ->
      ModelFixture.close(fixture)
      File.rm_rf!(root)
    end)

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: binary,
             args: ["app-server", "--listen", "stdio://"],
             cwd: fixture.workspace,
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "RUST_LOG" => "off"
             }
           ]}
      )

    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)

    assert {:ok, %{"result" => _}} =
             Session.initialize(
               pid,
               %{"name" => "codex_desktop", "version" => "0.1.0"},
               %{
                 "experimentalApi" => true,
                 "requestAttestation" => tags[:scenario] == "attestation"
               }
             )

    %{pid: pid, fixture: fixture}
  end

  defp token(email) do
    payload = %{
      "email" => email,
      "https://api.openai.com/auth" => %{
        "chatgpt_account_id" => "synthetic-account",
        "chatgpt_user_id" => "synthetic-user",
        "chatgpt_plan_type" => "pro"
      }
    }

    Enum.map_join([%{"alg" => "none", "typ" => "JWT"}, payload], ".", fn value ->
      value |> JSON.encode!() |> Base.url_encode64(padding: false)
    end) <> ".c3ludGhldGlj"
  end

  defp login(pid, email) do
    assert {:ok, %{"result" => %{"type" => "chatgptAuthTokens"}}} =
             Session.request(
               pid,
               "account/login/start",
               Map.put(credentials(email), "type", "chatgptAuthTokens")
             )
  end

  defp credentials(email),
    do: %{
      "accessToken" => token(email),
      "chatgptAccountId" => "synthetic-account",
      "chatgptPlanType" => "pro"
    }

  defp journey(context, respond) do
    params = %{
      "model" => "mock-model",
      "modelProvider" => "fixture",
      "cwd" => context.fixture.workspace,
      "ephemeral" => true,
      "sandbox" => "read-only",
      "approvalPolicy" => "never"
    }

    task = Task.async(fn -> Session.request(context.pid, "thread/start", params) end)
    {response, events} = service_until(context.pid, respond, fn _ -> Task.yield(task, 0) end)
    assert {:ok, %{"result" => %{"thread" => %{"id" => thread}}}} = response

    assert {:ok, %{"result" => %{"turn" => %{"id" => turn}}}} =
             Session.request(
               context.pid,
               "turn/start",
               %{
                 "threadId" => thread,
                 "input" => [%{"type" => "text", "text" => "Synthetic auth interaction only"}]
               }
             )

    {completed, later} =
      service_until(context.pid, respond, fn accumulated ->
        case Enum.find(accumulated, &(get_in(&1, [:wire, "method"]) == "turn/completed")) do
          nil -> nil
          event -> {:ok, event}
        end
      end)

    assert completed.wire["params"]["threadId"] == thread
    assert completed.wire["params"]["turn"]["id"] == turn
    {completed, events ++ later}
  end

  defp service_until(pid, respond, done, events \\ [], deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 15_000
    assert System.monotonic_time(:millisecond) < deadline, "auth interaction deadline"
    assert Session.status(pid).phase == :ready
    assert {:ok, incoming} = Session.drain(pid)
    Enum.each(Enum.filter(incoming, &(&1.kind == :server_request)), respond)
    events = events ++ incoming

    case done.(events) do
      {:ok, response} ->
        {response, events}

      nil ->
        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
        after
          10 -> :ok
        end

        service_until(pid, respond, done, events, deadline)
    end
  end

  test "synthetic 401 requests refreshed tokens and retries only after explicit response",
       context do
    login(context.pid, "old@synthetic.invalid")

    {completed, events} =
      journey(context, fn event ->
        assert event.wire["method"] == "account/chatgptAuthTokens/refresh"

        assert event.wire["params"] == %{
                 "reason" => "unauthorized",
                 "previousAccountId" => "synthetic-account"
               }

        assert [%{"generation" => "old@synthetic.invalid", "status" => 401}] =
                 ModelFixture.requests(context.fixture)

        assert :ok =
                 Session.respond(
                   context.pid,
                   event.handle,
                   {:ok, credentials("new@synthetic.invalid")}
                 )
      end)

    assert completed.wire["params"]["turn"]["status"] == "completed"

    assert [
             %{"generation" => "old@synthetic.invalid", "status" => 401},
             %{"generation" => "new@synthetic.invalid", "status" => 200}
           ] = ModelFixture.requests(context.fixture)

    [interaction] = Enum.filter(events, &(&1.kind == :server_request))

    assert {:error, %Error{code: :stale_interaction}} =
             Session.respond(
               context.pid,
               interaction.handle,
               {:ok, credentials("new@synthetic.invalid")}
             )

    assert {:ok, %{"result" => %{"account" => %{"email" => "new@synthetic.invalid"}}}} =
             Session.request(context.pid, "account/read", %{"refreshToken" => false})
  end

  test "refused refresh fails the turn without another model request", context do
    login(context.pid, "old@synthetic.invalid")

    {completed, _events} =
      journey(context, fn event ->
        assert event.wire["method"] == "account/chatgptAuthTokens/refresh"

        assert :ok =
                 Session.respond(
                   context.pid,
                   event.handle,
                   {:error, %{"code" => -32_001, "message" => "Synthetic refresh denied"}}
                 )
      end)

    assert completed.wire["params"]["turn"]["status"] == "failed"
    assert [%{"status" => 401}] = ModelFixture.requests(context.fixture)
  end

  @tag scenario: "attestation"
  test "explicit synthetic attestation reaches the actual Responses WebSocket handshake",
       context do
    login(context.pid, "new@synthetic.invalid")

    {completed, events} =
      journey(context, fn event ->
        assert event.wire["method"] == "attestation/generate"
        assert event.wire["params"] == %{}

        assert :ok =
                 Session.respond(
                   context.pid,
                   event.handle,
                   {:ok, %{"token" => "v1.synthetic-test"}}
                 )
      end)

    assert completed.wire["params"]["turn"]["status"] == "completed"
    assert Enum.any?(events, &(&1.kind == :server_request))

    [handshake] =
      Enum.filter(ModelFixture.requests(context.fixture), &(&1["transport"] == "handshake"))

    assert JSON.decode!(handshake["attestation"]) == %{
             "v" => 1,
             "s" => 0,
             "t" => "v1.synthetic-test"
           }

    assert Enum.any?(ModelFixture.requests(context.fixture), &(&1["transport"] == "websocket"))
  end
end
