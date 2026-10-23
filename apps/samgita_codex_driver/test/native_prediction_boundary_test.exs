defmodule SamgitaCodexDriver.NativePredictionBoundaryTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  alias SamgitaProtocolCodex.Error

  import TurnFixture,
    only: [call: 3, start: 1, start: 2, thread: 2, upstream_error: 3, upstream_error: 4]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @method "thread/prediction/request"
  @params %{"threadId" => "synthetic-unknown-thread", "sourceTurnId" => "synthetic-turn"}
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

  setup {TurnFixture, :setup}

  setup ctx do
    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             @binary_sha

    :ok
  end

  test "the advertised experimental operation returns the exact native unimplemented error",
       ctx do
    pid = start(ctx)
    id = thread(ctx, pid)
    before = call(pid, "thread/read", %{"threadId" => id})

    for params <- [@params, %{"threadId" => id, "sourceTurnId" => "synthetic-turn"}] do
      assert upstream_error(pid, @method, params) == %{
               "code" => -32_601,
               "message" => "thread/prediction/request is not implemented yet"
             }
    end

    assert call(pid, "thread/read", %{"threadId" => id}) == before
    assert_no_prediction_work(ctx, pid)
  end

  test "stable negotiation rejects the experimental operation at both local and native boundaries",
       ctx do
    pid = start(ctx, experimental: false)

    assert {:error, %Error{code: :experimental_api_required}} =
             Session.request(pid, @method, @params)

    assert upstream_error(pid, @method, @params, validation: :wire) == %{
             "code" => -32_600,
             "message" => "thread/prediction/request requires experimentalApi capability"
           }

    assert_no_prediction_work(ctx, pid)
  end

  test "invalid parameters cannot reach even the unimplemented native dispatcher", ctx do
    pid = start(ctx)

    for field <- ~w(threadId sourceTurnId), value <- [:missing, nil, 17] do
      params =
        if value == :missing, do: Map.delete(@params, field), else: Map.put(@params, field, value)

      assert {:error, %Error{code: :schema_violation}} = Session.request(pid, @method, params)
      error = upstream_error(pid, @method, params, validation: :wire)
      assert error["code"] == -32_600
      assert String.starts_with?(error["message"], "Invalid request: ")

      assert error["message"] =~
               if(value == :missing, do: "missing field", else: "expected a string")
    end

    assert_no_prediction_work(ctx, pid)
  end

  defp assert_no_prediction_work(ctx, pid) do
    assert ModelFixture.requests(ctx.fixture) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, interactions: 0} = Session.status(pid)
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.kind == :server_request))

    refute Enum.any?(events, fn event ->
             event.wire["method"] in [
               "thread/prediction/updated",
               "turn/started",
               "turn/completed",
               "item/started"
             ]
           end)
  end
end

defmodule SamgitaCodexDriver.RetainedPredictionContractTest do
  use ExUnit.Case, async: true

  alias SamgitaProtocolCodex.{Error, Schema, Wire}

  @method "thread/prediction/updated"
  @identity %{"threadId" => "synthetic-thread", "sourceTurnId" => "synthetic-turn"}

  test "synthetic retained prediction variants round trip without native-emission evidence" do
    for result <- [
          %{"type" => "completed", "text" => "Synthetic λ🙂\n"},
          %{"type" => "completed", "text" => nil},
          %{"type" => "completed"},
          %{"type" => "failed"}
        ] do
      params = Map.put(@identity, "result", result)

      assert :ok =
               Schema.validate_notification(:server_notification, @method, params,
                 experimental: true
               )

      wire = %{"method" => @method, "params" => params}
      assert {:ok, encoded} = Wire.encode(wire)
      assert {:ok, ^wire} = Wire.decode(encoded)
    end
  end

  test "retained prediction contracts reject invalid identity and result shapes" do
    valid = Map.put(@identity, "result", %{"type" => "completed", "text" => "synthetic"})

    for field <- ~w(threadId sourceTurnId result), value <- [:missing, nil, 17] do
      params =
        if value == :missing, do: Map.delete(valid, field), else: Map.put(valid, field, value)

      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_notification(:server_notification, @method, params,
                 experimental: true
               )
    end

    for result <- [%{}, %{"type" => "unknown"}, %{"type" => "completed", "text" => false}] do
      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_notification(
                 :server_notification,
                 @method,
                 Map.put(@identity, "result", result),
                 experimental: true
               )
    end
  end
end
