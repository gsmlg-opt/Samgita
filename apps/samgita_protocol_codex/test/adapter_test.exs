defmodule SamgitaProtocolCodexTest do
  use ExUnit.Case, async: true

  alias SamgitaProtocolCodex, as: Codex

  test "Codex initialization stays outside native negotiation" do
    info = %{"name" => "samgita_test", "version" => "0.1.0"}

    assert {:ok, wire} = Codex.initialize_request("init-1", info)

    assert wire == %{
             "id" => "init-1",
             "method" => "initialize",
             "params" => %{"clientInfo" => info}
           }

    refute Map.has_key?(wire, "jsonrpc")
    assert Codex.initialized() == %{"method" => "initialized"}

    result = %{
      "userAgent" => "codex/0.163.0",
      "platformFamily" => "unix",
      "platformOs" => "linux",
      "codexHome" => "/tmp/codex"
    }

    assert {:ok, ^result} =
             Codex.decode_initialize_response(%{"id" => "init-1", "result" => result}, "init-1")

    assert_error(
      Codex.decode_initialize_response(%{"id" => "other", "result" => result}, "init-1"),
      "correlation_mismatch"
    )

    assert_error(Codex.initialize_request("init", %{"name" => "x"}), "invalid_params")

    assert_error(
      Codex.encode_request(
        request("connection/initialize", %{"versions" => ["1.0"], "capabilities" => []})
      ),
      "unsupported_method"
    )
  end

  test "all six supported methods translate only the documented subset" do
    cases = [
      {"thread/start", %{}, %{}},
      {"thread/read", %{"thread_id" => "thr-1"}, %{"threadId" => "thr-1"}},
      {"thread/resume", %{"thread_id" => "thr-1"}, %{"threadId" => "thr-1"}},
      {"turn/start", %{"thread_id" => "thr-1", "input" => input()},
       %{"threadId" => "thr-1", "input" => input()}},
      {"turn/steer", %{"thread_id" => "thr-1", "turn_id" => "turn-1", "input" => input()},
       %{"threadId" => "thr-1", "expectedTurnId" => "turn-1", "input" => input()}},
      {"turn/interrupt", %{"thread_id" => "thr-1", "turn_id" => "turn-1"},
       %{"threadId" => "thr-1", "turnId" => "turn-1"}}
    ]

    for {method, params, upstream} <- cases do
      neutral = request(method, params)
      assert {:ok, wire} = Codex.encode_request(neutral)
      assert wire == %{"id" => neutral["id"], "method" => method, "params" => upstream}
      refute Map.has_key?(wire, "command_id")
      refute Map.has_key?(wire, "project_ref")
    end
  end

  test "unsupported fields are rejected rather than silently discarded" do
    for params <- [%{"title" => "name"}, %{"metadata" => %{"key" => "value"}}] do
      assert_error(
        Codex.encode_request(request("thread/start", params)),
        "unsupported_capability"
      )
    end

    for method <- ["request/cancel", "stream/resume", "approval/request", "project/event.receive"] do
      assert_error(Codex.encode_request(request(method, %{})), "unsupported_method")
    end

    refute "stream/resume" in Codex.supported_methods()
    refute "approval/request" in Codex.supported_methods()
  end

  test "native malformed input and mutation without command identity fail" do
    assert_error(Codex.initialize_request("init", %URI{}), "invalid_params")
    assert_error(Codex.decode_initialize_response(%URI{}, "init"), "invalid_response")
    assert_error(Codex.encode_request(nil), "invalid_message")

    assert_error(
      Codex.encode_request(request("turn/start", %{"thread_id" => "thr", "input" => []})),
      "invalid_params"
    )

    assert_error(
      Codex.encode_request(
        request("turn/start", %{
          "thread_id" => "thr",
          "input" => [%{"type" => "image", "url" => "secret"}]
        })
      ),
      "invalid_params"
    )

    assert_error(
      Codex.encode_request(Map.delete(request("thread/start", %{}), "command_id")),
      "invalid_message"
    )
  end

  test "malformed local struct inputs return typed errors" do
    assert_error(
      Codex.decode_initialize_response(%{"id" => "init", "result" => %URI{}}, "init"),
      "invalid_response"
    )

    wire = %{"method" => "turn/started", "params" => %{}}
    assert_error(Codex.decode_message(wire, %URI{}), "invalid_message")

    context = %{"correlation_id" => "corr", "thread_id" => "thr", "turn_id" => "turn"}
    assert_error(Codex.decode_message(%{wire | "params" => %URI{}}, context), "invalid_params")
  end

  test "thread replies preserve native identity/context and map the remote thread" do
    for method <- ["thread/start", "thread/read", "thread/resume"] do
      params = if method == "thread/start", do: %{}, else: %{"thread_id" => "thr-1"}
      original = request(method, params)
      thread = %{"id" => "thr-1", "preview" => "text", "status" => %{"type" => "idle"}}

      assert {:ok, response} =
               Codex.decode_message(
                 %{"id" => "req-1", "result" => %{"thread" => thread}},
                 original
               )

      assert response["result"] == %{"thread_id" => "thr-1", "thread" => thread}
      assert response["id"] == original["id"]
      assert response["correlation_id"] == original["correlation_id"]
      assert response["project_ref"] == original["project_ref"]
      assert response["command_id"] == original["command_id"]
    end
  end

  test "turn acknowledgements do not manufacture durable acceptance or cancellation completion" do
    original = request("turn/start", %{"thread_id" => "thr-1", "input" => input()})

    wire = %{
      "id" => "req-1",
      "result" => %{
        "turn" => %{"id" => "turn-1", "status" => "inProgress", "items" => [], "error" => nil}
      }
    }

    assert {:ok, response} = Codex.decode_message(wire, original)

    assert response["result"] == %{
             "thread_id" => "thr-1",
             "turn_id" => "turn-1",
             "status" => "running"
           }

    steer =
      request("turn/steer", %{"thread_id" => "thr-1", "turn_id" => "turn-1", "input" => input()})

    assert {:ok, response} =
             Codex.decode_message(%{"id" => "req-1", "result" => %{"turnId" => "turn-1"}}, steer)

    assert response["result"]["status"] == "running"

    interrupt = request("turn/interrupt", %{"thread_id" => "thr-1", "turn_id" => "turn-1"})
    assert {:ok, response} = Codex.decode_message(%{"id" => "req-1", "result" => %{}}, interrupt)
    assert response["result"]["status"] == "requested"
  end

  test "responses require the exact pending request and valid result shape" do
    original = request("thread/read", %{"thread_id" => "thr-1"})

    assert_error(
      Codex.decode_message(%{"id" => 1, "result" => %{}}, original),
      "correlation_mismatch"
    )

    assert_error(
      Codex.decode_message(%{"id" => "req-1", "result" => %{}}, original),
      "invalid_response"
    )

    assert_error(
      Codex.decode_message(%{"id" => "req-1", "result" => %{}, "error" => %{}}, original),
      "invalid_response"
    )

    assert_error(
      Codex.decode_message(
        %{"id" => "req-1", "result" => %{"thread" => %{"id" => "another"}}},
        original
      ),
      "correlation_mismatch"
    )

    assert_error(
      Codex.decode_message(%{"id" => "req-1", "result" => %{}}, %{}),
      "invalid_message"
    )
  end

  test "upstream errors are typed and never echo arbitrary messages or data" do
    original = request("thread/read", %{"thread_id" => "thr-1"})

    wire = %{
      "id" => "req-1",
      "error" => %{
        "code" => -32001,
        "message" => "secret-key",
        "data" => %{"token" => "secret-key"}
      }
    }

    assert {:ok, response} = Codex.decode_message(wire, original)
    assert response["error"]["code"] == "upstream_error"
    assert response["error"]["retryable"] == true
    refute inspect(response) =~ "secret-key"
  end

  test "stream deltas map IDs without inventing upstream replay/cursors" do
    wire = %{
      "method" => "item/agentMessage/delta",
      "params" => %{
        "threadId" => "thr-1",
        "turnId" => "turn-1",
        "itemId" => "item-1",
        "delta" => "hello"
      }
    }

    context = %{"correlation_id" => "corr-1", "thread_id" => "thr-1", "turn_id" => "turn-1"}
    assert {:ok, message} = Codex.decode_message(wire, context)
    assert message["method"] == "item/delta"

    assert message["params"] == %{
             "thread_id" => "thr-1",
             "turn_id" => "turn-1",
             "item_id" => "item-1",
             "delta" => "hello"
           }

    refute Map.has_key?(message, "stream_id")
    refute Map.has_key?(message, "cursor")

    assert {:ok, message} =
             Codex.decode_message(
               wire,
               Map.merge(context, %{"stream_id" => "local-stream", "cursor" => 3})
             )

    assert message["stream_id"] == "local-stream"
    assert message["cursor"] == 3

    assert_error(
      Codex.decode_message(wire, %{context | "thread_id" => "other"}),
      "correlation_mismatch"
    )

    assert_error(Codex.decode_message(wire, Map.put(context, "cursor", 1)), "invalid_message")
    assert_error(Codex.decode_message(%{wire | "params" => %{}}, context), "invalid_params")
  end

  test "turn lifecycle preserves completion, failure and interruption semantics" do
    context = %{"correlation_id" => "corr", "thread_id" => "thr", "turn_id" => "turn"}

    for {upstream, neutral} <- [
          {"completed", "completed"},
          {"failed", "failed"},
          {"interrupted", "interrupted"}
        ] do
      wire = %{
        "method" => "turn/completed",
        "params" => %{
          "threadId" => "thr",
          "turn" => %{"id" => "turn", "status" => upstream, "items" => [], "error" => nil}
        }
      }

      assert {:ok, message} = Codex.decode_message(wire, context)
      assert message["params"]["status"] == neutral
    end

    wire = %{
      "method" => "turn/started",
      "params" => %{
        "threadId" => "thr",
        "turn" => %{"id" => "turn", "status" => "inProgress", "items" => [], "error" => nil}
      }
    }

    assert {:ok, message} = Codex.decode_message(wire, context)
    assert message["method"] == "turn/started"

    assert_error(
      Codex.decode_message(
        %{
          "id" => "approval",
          "method" => "item/commandExecution/requestApproval",
          "params" => %{}
        },
        context
      ),
      "unsupported_method"
    )
  end

  defp input, do: [%{"type" => "text", "text" => "inspect"}]

  defp request(method, params) do
    %{
      "schema_version" => "1.0",
      "type" => "request",
      "id" => "req-1",
      "method" => method,
      "params" => params,
      "correlation_id" => "corr-1",
      "command_id" => "command-1",
      "project_ref" => "project-1"
    }
  end

  defp assert_error({:error, error}, code), do: assert(error.code == code)
end
