defmodule SamgitaProtocolCodex.SchemaTest do
  use ExUnit.Case, async: true
  alias SamgitaProtocolCodex.{Error, Schema}

  test "experimental gates match exact untagged branches before same-type alternatives" do
    path = %{
      "type" => "object",
      "properties" => %{"path" => %{"type" => "string"}},
      "required" => ["path"]
    }

    id = %{
      "type" => "object",
      "properties" => %{"id" => %{"type" => "string"}},
      "required" => ["id"]
    }

    full = %{"anyOf" => [path, id]}

    for stable <- [full, %{"anyOf" => [id, path]}],
        value <- [%{"path" => "file"}, %{"id" => "thread"}, %{"path" => "file", "id" => "thread"}] do
      assert :ok = Schema.Gates.check(full, stable, value, full, stable)
    end
  end

  test "source-derived legacy contracts retain required, optional and nullable fields" do
    for params <- [
          %{},
          %{"includeToken" => nil},
          %{"includeToken" => false, "refreshToken" => true}
        ] do
      assert :ok = Schema.validate_request("getAuthStatus", params)
    end

    for {method, params, opts} <- [
          {"getAuthStatus", %{"includeToken" => "false"}, []},
          {"getAuthStatus", nil, []},
          {"getAuthStatus", nil, [params_present: false]},
          {"gitDiffToRemote", %{}, []},
          {"gitDiffToRemote", %{"cwd" => nil}, []},
          {"getConversationSummary", %{}, []},
          {"getConversationSummary", %{"rolloutPath" => nil}, []}
        ] do
      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_request(method, params, opts)
    end

    assert :ok = Schema.validate_request("gitDiffToRemote", %{"cwd" => "/tmp"})

    for params <- [
          %{"rolloutPath" => "/tmp/rollout.jsonl"},
          %{"conversationId" => "00000000-0000-0000-0000-000000000001"},
          %{
            "rolloutPath" => "/tmp/rollout.jsonl",
            "conversationId" => "00000000-0000-0000-0000-000000000001"
          }
        ] do
      assert :ok = Schema.validate_request("getConversationSummary", params)
    end

    assert :ok = Schema.validate_result(:server_response, "getAuthStatus", %{})

    assert :ok =
             Schema.validate_result(:server_response, "getAuthStatus", %{
               "authMethod" => nil,
               "authToken" => nil,
               "requiresOpenaiAuth" => false
             })

    assert {:error, %Error{code: :schema_violation}} =
             Schema.validate_result(:server_response, "getAuthStatus", %{
               "authMethod" => "invented"
             })

    assert :ok =
             Schema.validate_result(:server_response, "gitDiffToRemote", %{
               "sha" => "fixture",
               "diff" => ""
             })

    assert {:error, %Error{code: :schema_violation}} =
             Schema.validate_result(:server_response, "gitDiffToRemote", %{"sha" => "fixture"})
  end

  test "source-derived internal notifications use full official payload contracts" do
    assert :ok =
             Schema.validate_notification(:server_notification, "rawResponse/completed", %{
               "responseId" => "response",
               "threadId" => "thread",
               "turnId" => "turn",
               "usage" => nil
             })

    assert :ok =
             Schema.validate_notification(:server_notification, "rawResponseItem/completed", %{
               "threadId" => "thread",
               "turnId" => "turn",
               "item" => %{"type" => "message", "role" => "assistant", "content" => []}
             })

    for method <- ["rawResponse/completed", "rawResponseItem/completed"] do
      assert method in Schema.methods(:server_notification)

      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_notification(:server_notification, method, %{})
    end
  end

  test "all message directions expose the exact full release surface" do
    assert length(Schema.methods(:client_request, experimental: true)) == 175
    assert length(Schema.methods(:server_request, experimental: true)) == 11
    assert length(Schema.methods(:server_notification, experimental: true)) == 87
    assert Schema.methods(:client_notification) == ["initialized"]
    assert "server/diagnostics" not in Schema.methods(:client_request)

    assert {:error, %Error{code: :unsupported_method}} =
             Schema.validate_request("future/method", %{})

    assert {:error, %Error{code: :experimental_api_required}} =
             Schema.validate_request("server/diagnostics", %{})
  end

  test "thread and multimodal turn params retain their full native surface" do
    assert :ok =
             Schema.validate_request("thread/start", %{
               "cwd" => "/tmp",
               "model" => nil,
               "approvalPolicy" => "never",
               "futureExtension" => [1, nil]
             })

    input = [
      %{"type" => "text", "text" => "hello", "text_elements" => []},
      %{"type" => "image", "url" => "https://invalid.example/test.png", "detail" => "high"},
      %{"type" => "localImage", "path" => "/tmp/fixture.png"},
      %{"type" => "audio", "url" => "data:audio/wav;base64,Zg=="},
      %{"type" => "localAudio", "path" => "/tmp/fixture.wav"},
      %{"type" => "skill", "name" => "fixture", "path" => "/tmp/skill"},
      %{"type" => "mention", "name" => "fixture", "path" => "/tmp/resource"}
    ]

    assert :ok =
             Schema.validate_request("turn/start", %{"threadId" => "thread", "input" => input})

    assert {:error, %Error{code: :schema_violation}} =
             Schema.validate_request("turn/start", %{
               "threadId" => "thread",
               "input" => [%{"type" => "image"}]
             })

    assert {:error, %Error{}} =
             Schema.validate_request("turn/start", %{"thread_id" => "thread", "input" => []})
  end

  test "experimental field gates follow source presence semantics rather than key presence" do
    assert :ok = Schema.validate_request("thread/start", %{"experimentalRawEvents" => false})

    assert {:error, %Error{code: :schema_violation}} =
             Schema.validate_request("thread/start", %{"experimentalRawEvents" => nil})

    assert {:error, %Error{code: :experimental_api_required}} =
             Schema.validate_request("thread/start", %{"experimentalRawEvents" => true})

    assert :ok =
             Schema.validate_request("thread/start", %{
               "dynamicTools" => nil,
               "mockExperimentalField" => nil
             })

    assert {:error, %Error{code: :experimental_api_required}} =
             Schema.validate_request("thread/start", %{"dynamicTools" => []})

    assert {:error, %Error{code: :experimental_api_required}} =
             Schema.validate_request("thread/start", %{"mockExperimentalField" => ""})

    assert :ok =
             Schema.validate_request("thread/start", %{"experimentalRawEvents" => true},
               experimental: true
             )

    assert {:error, %Error{code: :experimental_api_required}} =
             Schema.validate_request("thread/start", %{"config" => %{}, "dynamicTools" => []})

    assert :ok = Schema.validate_request("thread/list", %{"parentThreadId" => nil})

    assert {:error, %Error{code: :experimental_api_required}} =
             Schema.validate_request("thread/list", %{"projectId" => nil})

    assert :ok =
             Schema.validate_request("thread/resume", %{"threadId" => "missing", "path" => ""})

    granular = %{
      "granular" => %{"sandbox_approval" => false, "rules" => false, "mcp_elicitations" => false}
    }

    assert {:error, %Error{code: :experimental_api_required}} =
             Schema.validate_request("thread/start", %{"approvalPolicy" => granular})

    assert :ok =
             Schema.validate_request("thread/start", %{"approvalPolicy" => granular},
               experimental: true
             )

    tokens = %{
      "type" => "chatgptAuthTokens",
      "accessToken" => "synthetic",
      "chatgptAccountId" => "synthetic"
    }

    assert {:error, %Error{code: :experimental_api_required}} =
             Schema.validate_request("account/login/start", tokens)

    assert :ok = Schema.validate_request("account/login/start", tokens, experimental: true)

    result =
      Path.expand("fixtures/native/contracts.json", __DIR__)
      |> File.read!()
      |> JSON.decode!()
      |> Map.fetch!("messages")
      |> Enum.find(&(&1["id"] == "server_response:thread/start"))
      |> Map.fetch!("value")

    assert :ok =
             Schema.validate_result(
               :server_response,
               "thread/start",
               Map.put(result, "runtimeWorkspaceRoots", [])
             )

    assert :ok =
             Schema.validate_result(
               :server_response,
               "thread/start",
               Map.put(result, "runtimeWorkspaceRoots", ["/tmp"])
             )
  end

  test "stable server responses validate full output without client-input experimental gates" do
    responses =
      Path.expand("fixtures/native/stable-server-responses.json", __DIR__)
      |> File.read!()
      |> JSON.decode!()

    for {method, response} <- responses do
      assert :ok = Schema.validate_result(:server_response, method, response["result"])
    end

    assert {:error, %Error{code: :schema_violation}} =
             Schema.validate_result(
               :server_response,
               "thread/start",
               put_in(responses["thread/start"]["result"], ["runtimeWorkspaceRoots"], [42])
             )

    assert {:error, %Error{code: :schema_violation}} =
             Schema.validate_result(
               :server_response,
               "thread/list",
               Map.put(responses["thread/list"]["result"], "readStates", [])
             )
  end

  test "server notifications gate method variants without recursively gating output fields" do
    thread =
      Path.expand("fixtures/native/stable-server-responses.json", __DIR__)
      |> File.read!()
      |> JSON.decode!()
      |> get_in(["thread/start", "result", "thread"])

    assert :ok =
             Schema.validate_notification(:server_notification, "thread/started", %{
               "thread" => thread
             })

    assert {:error, %Error{code: :schema_violation}} =
             Schema.validate_notification(:server_notification, "thread/started", %{
               "thread" =>
                 put_in(thread, ["environments", Access.at(0), "runtimeWorkspaceRoots"], [42])
             })

    assert {:error, %Error{code: :experimental_api_required}} =
             Schema.validate_notification(:server_notification, "thread/settings/updated", %{})

    assert length(Schema.methods(:server_notification)) == 63

    for method <- ["thread/settings/updated", "process/outputDelta", "thread/realtime/started"] do
      refute method in Schema.methods(:server_notification)
      assert method in Schema.methods(:server_notification, experimental: true)
    end

    # These methods have experimental-looking documentation/names, but no runtime
    # enum annotation. Do not infer gates from comments, payload fields or names.
    assert "item/plan/delta" in Schema.methods(:server_notification)
    assert "remoteControl/status/changed" in Schema.methods(:server_notification)

    settings =
      Path.expand("fixtures/native/contracts.json", __DIR__)
      |> File.read!()
      |> JSON.decode!()
      |> Map.fetch!("messages")
      |> Enum.find(&(&1["id"] == "server_notification:thread/settings/updated"))
      |> get_in(["value", "params"])

    assert {:error, %Error{code: :experimental_api_required}} =
             Schema.validate_notification(
               :server_notification,
               "thread/settings/updated",
               settings
             )

    assert :ok =
             Schema.validate_notification(
               :server_notification,
               "thread/settings/updated",
               settings,
               experimental: true
             )

    assert {:error, %Error{code: :schema_violation}} =
             Schema.validate_notification(:server_notification, "thread/settings/updated", %{},
               experimental: true
             )
  end

  test "server requests preserve output fields without applying client-input field gates" do
    assert Schema.methods(:server_request) == Schema.methods(:server_request, experimental: true)
    assert "currentTime/read" in Schema.methods(:server_request)

    assert :ok =
             Schema.validate_request("currentTime/read", %{"threadId" => "t"},
               direction: :server_request
             )

    params = %{
      "threadId" => "t",
      "turnId" => "u",
      "itemId" => "i",
      "startedAtMs" => 0,
      "availableDecisions" => ["decline"]
    }

    assert :ok =
             Schema.validate_request("item/commandExecution/requestApproval", params,
               direction: :server_request
             )

    assert {:error, %Error{code: :schema_violation}} =
             Schema.validate_request(
               "item/commandExecution/requestApproval",
               Map.put(params, "availableDecisions", [42]),
               direction: :server_request
             )
  end

  test "omitted params and explicit null obey separate upstream schemas" do
    assert :ok = Schema.validate_request("account/logout", nil, params_present: false)
    assert :ok = Schema.validate_request("account/logout", nil)
    assert {:error, %Error{}} = Schema.validate_request("thread/start", nil)

    assert {:error, %Error{}} =
             Schema.validate_request("thread/start", nil, params_present: false)

    assert :ok =
             Schema.validate_notification(:client_notification, "initialized", nil,
               params_present: false
             )
  end

  test "server requests and their full results are independently schema validated" do
    params = %{
      "threadId" => "t",
      "turnId" => "u",
      "callId" => "c",
      "tool" => "tool",
      "arguments" => %{"structured" => [1, nil]}
    }

    assert :ok = Schema.validate_request("item/tool/call", params, direction: :server_request)

    assert :ok =
             Schema.validate_result(:client_response, "item/tool/call", %{
               "contentItems" => [%{"type" => "inputText", "text" => "result"}],
               "success" => true
             })

    assert {:error, %Error{}} =
             Schema.validate_result(:client_response, "item/tool/call", %{
               "contentItems" => [],
               "success" => "yes"
             })

    assert {:error, %Error{}} = Schema.validate_result(:server_response, "thread/start", %{})
  end

  test "draft-07 refs, unions, defaults, additional properties and numeric constraints" do
    schema = %{
      "definitions" => %{"a/b~c" => %{"type" => "integer", "minimum" => 2, "format" => "uint16"}},
      "type" => "object",
      "properties" => %{
        "value" => %{"$ref" => "#/definitions/a~1b~0c"},
        "defaulted" => %{"type" => "string", "default" => "x"}
      },
      "required" => ["value"],
      "additionalProperties" => false
    }

    assert :ok = Schema.validate(schema, %{"value" => 2})

    for value <- [
          %{"value" => 1},
          %{"value" => 65_536},
          %{"value" => nil},
          %{"value" => 2, "extra" => true},
          %{}
        ] do
      assert {:error, %Error{}} = Schema.validate(schema, value)
    end

    assert :ok = Schema.validate(%{"allOf" => [%{"type" => "integer"}, %{"minimum" => 3}]}, 3)

    assert {:error, _} =
             Schema.validate(%{"oneOf" => [%{"type" => "number"}, %{"type" => "integer"}]}, 1)

    assert :ok = Schema.validate(%{"anyOf" => [%{"type" => "string"}, %{"type" => "null"}]}, nil)

    assert {:error, %Error{code: :unsupported_schema_keyword}} =
             Schema.validate(%{"not" => %{"type" => "string"}}, 1)

    assert {:error, %Error{code: :unsupported_schema_format}} =
             Schema.validate(%{"format" => "unimplemented"}, "x")

    assert {:error, %Error{code: :unsupported_schema_reference}} =
             Schema.validate(%{"$ref" => "https://invalid.example/schema"}, nil)
  end
end
