defmodule SamgitaProtocolCodex.SchemaTest do
  use ExUnit.Case, async: true
  alias SamgitaProtocolCodex.{Failure, Schema}

  test "all message directions expose the exact full release surface" do
    assert length(Schema.methods(:client_request, experimental: true)) == 172
    assert length(Schema.methods(:server_request, experimental: true)) == 11
    assert length(Schema.methods(:server_notification, experimental: true)) == 85
    assert Schema.methods(:client_notification) == ["initialized"]
    assert "server/diagnostics" not in Schema.methods(:client_request)

    assert {:error, %Failure{code: :unsupported_method}} =
             Schema.validate_request("future/method", %{})

    assert {:error, %Failure{code: :experimental_api_required}} =
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

    assert {:error, %Failure{code: :schema_violation}} =
             Schema.validate_request("turn/start", %{
               "threadId" => "thread",
               "input" => [%{"type" => "image"}]
             })

    assert {:error, %Failure{}} =
             Schema.validate_request("turn/start", %{"thread_id" => "thread", "input" => []})
  end

  test "experimental field gates follow source presence semantics rather than key presence" do
    assert :ok = Schema.validate_request("thread/start", %{"experimentalRawEvents" => false})

    assert {:error, %Failure{code: :schema_violation}} =
             Schema.validate_request("thread/start", %{"experimentalRawEvents" => nil})

    assert {:error, %Failure{code: :experimental_api_required}} =
             Schema.validate_request("thread/start", %{"experimentalRawEvents" => true})

    assert :ok =
             Schema.validate_request("thread/start", %{
               "dynamicTools" => nil,
               "mockExperimentalField" => nil
             })

    assert {:error, %Failure{code: :experimental_api_required}} =
             Schema.validate_request("thread/start", %{"dynamicTools" => []})

    assert {:error, %Failure{code: :experimental_api_required}} =
             Schema.validate_request("thread/start", %{"mockExperimentalField" => ""})

    assert :ok =
             Schema.validate_request("thread/start", %{"experimentalRawEvents" => true},
               experimental: true
             )

    assert {:error, %Failure{code: :experimental_api_required}} =
             Schema.validate_request("thread/start", %{"config" => %{}, "dynamicTools" => []})

    assert :ok = Schema.validate_request("thread/list", %{"parentThreadId" => nil})

    assert {:error, %Failure{code: :experimental_api_required}} =
             Schema.validate_request("thread/list", %{"projectId" => nil})

    assert :ok =
             Schema.validate_request("thread/resume", %{"threadId" => "missing", "path" => ""})

    granular = %{
      "granular" => %{"sandbox_approval" => false, "rules" => false, "mcp_elicitations" => false}
    }

    assert {:error, %Failure{code: :experimental_api_required}} =
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

    assert {:error, %Failure{code: :experimental_api_required}} =
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

    assert {:error, %Failure{code: :schema_violation}} =
             Schema.validate_result(
               :server_response,
               "thread/start",
               put_in(responses["thread/start"]["result"], ["runtimeWorkspaceRoots"], [42])
             )

    assert {:error, %Failure{code: :schema_violation}} =
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

    assert {:error, %Failure{code: :schema_violation}} =
             Schema.validate_notification(:server_notification, "thread/started", %{
               "thread" =>
                 put_in(thread, ["environments", Access.at(0), "runtimeWorkspaceRoots"], [42])
             })

    assert {:error, %Failure{code: :experimental_api_required}} =
             Schema.validate_notification(:server_notification, "thread/settings/updated", %{})

    assert length(Schema.methods(:server_notification)) == 61

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

    assert {:error, %Failure{code: :experimental_api_required}} =
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

    assert {:error, %Failure{code: :schema_violation}} =
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

    assert {:error, %Failure{code: :schema_violation}} =
             Schema.validate_request(
               "item/commandExecution/requestApproval",
               Map.put(params, "availableDecisions", [42]),
               direction: :server_request
             )
  end

  test "omitted params and explicit null obey separate upstream schemas" do
    assert :ok = Schema.validate_request("account/logout", nil, params_present: false)
    assert :ok = Schema.validate_request("account/logout", nil)
    assert {:error, %Failure{}} = Schema.validate_request("thread/start", nil)

    assert {:error, %Failure{}} =
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

    assert {:error, %Failure{}} =
             Schema.validate_result(:client_response, "item/tool/call", %{
               "contentItems" => [],
               "success" => "yes"
             })

    assert {:error, %Failure{}} = Schema.validate_result(:server_response, "thread/start", %{})
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
      assert {:error, %Failure{}} = Schema.validate(schema, value)
    end

    assert :ok = Schema.validate(%{"allOf" => [%{"type" => "integer"}, %{"minimum" => 3}]}, 3)

    assert {:error, _} =
             Schema.validate(%{"oneOf" => [%{"type" => "number"}, %{"type" => "integer"}]}, 1)

    assert :ok = Schema.validate(%{"anyOf" => [%{"type" => "string"}, %{"type" => "null"}]}, nil)

    assert {:error, %Failure{code: :unsupported_schema_keyword}} =
             Schema.validate(%{"not" => %{"type" => "string"}}, 1)

    assert {:error, %Failure{code: :unsupported_schema_format}} =
             Schema.validate(%{"format" => "unimplemented"}, "x")

    assert {:error, %Failure{code: :unsupported_schema_reference}} =
             Schema.validate(%{"$ref" => "https://invalid.example/schema"}, nil)
  end
end
