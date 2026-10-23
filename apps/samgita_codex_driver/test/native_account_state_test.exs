defmodule SamgitaCodexDriver.NativeAccountStateTest do
  use ExUnit.Case, async: false

  import Bitwise
  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @missing_login "67e55044-10b1-426f-9247-bb680e5fe0c8"

  setup tags do
    context = TurnFixture.setup(tags)
    TurnFixture.configure_model(context, %{})
    config = Path.join(context.fixture.codex_home, "config.toml")
    body = File.read!(config)

    body =
      if tags[:custom_provider],
        do: body,
        else: String.replace(body, "requires_openai_auth = false", "requires_openai_auth = true")

    policy =
      if tags[:forced_login],
        do: "forced_login_method = #{JSON.encode!(tags[:forced_login])}\n",
        else: ""

    # Disable the unrelated plugin startup sync. Every configured HTTP destination
    # remains the owned loopback fixture; these account-only cases start no turns.
    File.write!(
      config,
      policy <>
        "cli_auth_credentials_store = 'file'\n" <>
        body <>
        "\n[features]\nplugins = false\nrecommended_plugins = false\n"
    )

    Map.put(context, :auth_path, Path.join(context.fixture.codex_home, "auth.json"))
  end

  test "unauthenticated reads and repeated logout retain explicit absence", context do
    pid = TurnFixture.start(context)

    for params <- [%{}, %{"refreshToken" => false}, %{"refreshToken" => true}] do
      assert account(pid, params) == empty_account(true)
    end

    for params <- [%{}, %{"includeToken" => true, "refreshToken" => false}] do
      assert call(pid, "getAuthStatus", params) == auth_status(nil, nil, true)
    end

    for params <- [nil, :omitted] do
      assert call(pid, "account/logout", params) == %{}
      assert updated(pid) == %{"authMode" => nil, "planType" => nil}
      refute File.exists?(context.auth_path)
      assert account(pid) == empty_account(true)
    end

    assert_idle(context, pid)
  end

  test "API key persists privately across restart and logout removes it without remote revocation",
       context do
    key = "sk-synthetic-account-persistence-canary"
    pid = TurnFixture.start(context)
    notifications = login_api(pid, key)
    assert updated_payload(notifications) == %{"authMode" => "apikey", "planType" => nil}
    assert account(pid) == api_account()
    assert_redacted([notifications, account(pid), Session.status(pid)], key)

    stored = context.auth_path |> File.read!() |> JSON.decode!()
    assert stored["auth_mode"] == "apikey"
    assert stored["OPENAI_API_KEY"] == key
    assert stored["tokens"] == nil
    assert band(File.stat!(context.auth_path).mode, 0o777) == 0o600
    assert :ok = Session.close(pid)

    restarted = TurnFixture.start(context)
    assert account(restarted) == api_account()
    assert call(restarted, "getAuthStatus", %{}) == auth_status("apikey", nil, true)
    assert call(restarted, "account/logout", nil) == %{}
    assert updated(restarted) == %{"authMode" => nil, "planType" => nil}
    refute File.exists?(context.auth_path)
    assert account(restarted) == empty_account(true)
    assert :ok = Session.close(restarted)
    cold = TurnFixture.start(context)
    assert account(cold) == empty_account(true)
    assert_idle(context, cold)
  end

  test "legacy auth status exports only an explicitly requested token and replacement is durable",
       context do
    pid = TurnFixture.start(context)
    first = "sk-synthetic-first-account-canary"
    second = "sk-synthetic-second-account-canary"
    login_api(pid, first)

    for params <- [%{}, %{"includeToken" => false}, %{"includeToken" => nil}] do
      assert call(pid, "getAuthStatus", params) == auth_status("apikey", nil, true)
    end

    # Native legacy getAuthStatus deliberately supports token export. This is an
    # opt-in sensitive native response, unlike the redacted v2 account/read API.
    assert call(pid, "getAuthStatus", %{"includeToken" => true, "refreshToken" => true}) ==
             auth_status("apikey", first, true)

    login_api(pid, second)

    assert call(pid, "getAuthStatus", %{"includeToken" => true}) ==
             auth_status("apikey", second, true)

    assert_redacted([account(pid), call(pid, "getAuthStatus", %{})], second)
    persisted = File.read!(context.auth_path)
    refute persisted =~ first
    assert JSON.decode!(persisted)["OPENAI_API_KEY"] == second
    assert_idle(context, pid)
  end

  test "missing and malformed cancellation IDs leave existing local credentials unchanged",
       context do
    pid = TurnFixture.start(context)
    key = "sk-synthetic-cancellation-canary"
    login_api(pid, key)
    persisted = File.read!(context.auth_path)

    for _ <- 1..2 do
      assert call(pid, "account/login/cancel", %{"loginId" => @missing_login}) == %{
               "status" => "notFound"
             }
    end

    assert upstream_error(pid, "account/login/cancel", %{"loginId" => "not-a-uuid"}) == %{
             "code" => -32_600,
             "message" => "invalid login id: not-a-uuid"
           }

    assert File.read!(context.auth_path) == persisted
    assert account(pid) == api_account()
    assert_idle(context, pid)
  end

  @tag forced_login: "api"
  test "API-only policy rejects every ChatGPT login kind before starting external authentication",
       context do
    pid = TurnFixture.start(context)

    for params <- [
          %{"type" => "chatgpt"},
          %{"type" => "chatgptDeviceCode"},
          %{
            "type" => "chatgptAuthTokens",
            "accessToken" => "synthetic-not-a-jwt",
            "chatgptAccountId" => "synthetic-account"
          }
        ] do
      expected =
        if params["type"] == "chatgptAuthTokens",
          do: "External ChatGPT auth is disabled. Use API key login instead.",
          else: "ChatGPT login is disabled. Use API key login instead."

      assert upstream_error(pid, "account/login/start", params) == %{
               "code" => -32_600,
               "message" => expected
             }
    end

    refute File.exists?(context.auth_path)
    assert account(pid) == empty_account(true)
    assert_idle(context, pid)
  end

  @tag forced_login: "chatgpt"
  test "ChatGPT-only policy rejects API keys without storing them", context do
    pid = TurnFixture.start(context)
    key = "sk-synthetic-disallowed-key-canary"

    error = upstream_error(pid, "account/login/start", %{"type" => "apiKey", "apiKey" => key})

    assert error == %{
             "code" => -32_600,
             "message" => "API key login is disabled. Use ChatGPT login instead."
           }

    assert_redacted(error, key)
    refute File.exists?(context.auth_path)
    assert account(pid) == empty_account(true)
    assert_idle(context, pid)
  end

  test "malformed external token fails local parsing without replacing persisted API credentials",
       context do
    pid = TurnFixture.start(context)
    key = "sk-synthetic-preserved-key-canary"
    login_api(pid, key)
    persisted = File.read!(context.auth_path)
    token = "synthetic-invalid-token-canary"

    error =
      upstream_error(pid, "account/login/start", %{
        "type" => "chatgptAuthTokens",
        "accessToken" => token,
        "chatgptAccountId" => "synthetic-account",
        "chatgptPlanType" => "pro"
      })

    assert error["code"] == -32_603
    assert String.starts_with?(error["message"], "failed to set external auth:")
    assert_redacted(error, token)
    assert File.read!(context.auth_path) == persisted
    assert account(pid) == api_account()

    assert call(pid, "getAuthStatus", %{"includeToken" => true}) ==
             auth_status("apikey", key, true)

    assert_idle(context, pid)
  end

  @tag custom_provider: true
  test "provider without an auth requirement suppresses account and legacy token exports",
       context do
    pid = TurnFixture.start(context)
    key = "sk-synthetic-custom-provider-canary"
    notifications = login_api(pid, key)
    assert updated_payload(notifications) == %{"authMode" => "apikey", "planType" => nil}
    assert account(pid) == empty_account(false)

    for params <- [%{}, %{"includeToken" => true, "refreshToken" => true}] do
      assert call(pid, "getAuthStatus", params) == auth_status(nil, nil, false)
    end

    assert JSON.decode!(File.read!(context.auth_path))["OPENAI_API_KEY"] == key
    assert_idle(context, pid)
  end

  defp account(pid, params \\ %{}), do: call(pid, "account/read", params)

  defp empty_account(required),
    do: %{"account" => nil, "requiresOpenaiAuth" => required, "workspaceRouting" => nil}

  defp api_account,
    do: %{
      "account" => %{"type" => "apiKey"},
      "requiresOpenaiAuth" => true,
      "workspaceRouting" => nil
    }

  defp auth_status(method, token, required),
    do: %{"authMethod" => method, "authToken" => token, "requiresOpenaiAuth" => required}

  defp login_api(pid, key) do
    result = call(pid, "account/login/start", %{"type" => "apiKey", "apiKey" => key})
    assert result == %{"type" => "apiKey"}
    events = until_updated(pid)

    assert TurnFixture.notification(events, "account/login/completed") == %{
             "loginId" => nil,
             "success" => true,
             "error" => nil,
             "onboardingEntrypoint" => nil
           }

    assert_redacted([result, events], key)
    events
  end

  defp updated(pid), do: pid |> until_updated() |> updated_payload()
  defp updated_payload(events), do: TurnFixture.notification(events, "account/updated")

  defp until_updated(pid),
    do: collect(pid, [], System.monotonic_time(:millisecond) + 5_000)

  defp collect(pid, acc, deadline) do
    assert {:ok, events} = Session.drain(pid)
    acc = acc ++ events

    if updated_payload(acc) do
      acc
    else
      assert System.monotonic_time(:millisecond) < deadline,
             "native account notification deadline"

      assert Session.status(pid).phase == :ready

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("unexpected account event gap")
      after
        10 -> :ok
      end

      collect(pid, acc, deadline)
    end
  end

  defp call(pid, method, params) do
    id = "account-request-#{System.unique_integer([:positive])}"
    request = %{"id" => id, "method" => method}
    request = if params == :omitted, do: request, else: Map.put(request, "params", params)

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, request)

    result
  end

  defp upstream_error(pid, method, params) do
    id = "account-error-#{System.unique_integer([:positive])}"

    assert {:error, %Error{code: :upstream_error, wire: %{"id" => ^id, "error" => error}}} =
             Session.request_native(pid, %{"id" => id, "method" => method, "params" => params})

    error
  end

  defp assert_redacted(value, canary), do: refute(inspect(value, limit: :infinity) =~ canary)

  defp assert_idle(context, pid) do
    assert ModelFixture.requests(context.fixture) == []
    assert {:ok, %{"result" => %{"data" => []}}} = Session.request(pid, "thread/loaded/list", %{})
    assert Session.status(pid).phase == :ready
  end
end
