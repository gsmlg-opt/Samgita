defmodule SamgitaProtocol.ThreadListingTest do
  use ExUnit.Case, async: true
  alias SamgitaProtocol.{Capabilities, Error, Schema}
  alias SamgitaProtocol.Schema.Document

  test "listing is an optional read-only capability independent of existing session hosts" do
    assert Schema.capability("thread/list") == "sessions.list.v1"
    refute Schema.mutating?("thread/list")
    refute "thread/list" in Capabilities.methods(["sessions.v1"])
    assert Capabilities.methods(["sessions.list.v1"]) == ["thread/list"]

    assert {:ok, ["sessions.v1"]} =
             Capabilities.negotiate(
               ["sessions.v1"],
               ["sessions.v1", "sessions.list.v1"]
             )

    request = %{
      "schema_version" => "1.0",
      "type" => "request",
      "id" => "list-1",
      "correlation_id" => "list-1",
      "method" => "thread/list",
      "params" => %{}
    }

    assert {:ok, ^request} = Schema.validate(request)
  end

  test "list parameters accept bounded-page requests and reject malformed fields" do
    assert :ok = Schema.validate_params("thread/list", %{})

    assert :ok =
             Schema.validate_params("thread/list", %{
               "cursor" => "opaque-page",
               "limit" => 1000,
               "metadata" => %{"repository" => "/workspace/example"}
             })

    for params <- [
          %{"limit" => 0},
          %{"limit" => -1},
          %{"limit" => 1.5},
          %{"cursor" => 3},
          %{"metadata" => []},
          %{"unexpected" => true}
        ] do
      assert {:error, %Error{code: "invalid_params"}} =
               Schema.validate_params("thread/list", params)
    end
  end

  test "results contain strictly typed summaries and an explicit nullable cursor" do
    assert :ok =
             Schema.validate_result("thread/list", %{"threads" => [], "next_cursor" => nil})

    assert :ok =
             Schema.validate_result("thread/list", %{
               "threads" => [
                 %{
                   "thread_id" => "thread-1",
                   "title" => "Existing session",
                   "updated_at" => "2026-11-18T00:00:00Z",
                   "status" => "running"
                 }
               ],
               "next_cursor" => "opaque-next-page"
             })

    for summary <- [
          %{},
          %{"thread_id" => ""},
          %{"thread_id" => 1},
          %{"thread_id" => "thread-1", "title" => 1},
          %{"thread_id" => "thread-1", "updated_at" => "yesterday"},
          %{"thread_id" => "thread-1", "status" => false},
          %{"thread_id" => "thread-1", "metadata" => %{}}
        ] do
      assert {:error, %Error{code: "invalid_response"}} =
               Schema.validate_result("thread/list", %{
                 "threads" => [summary],
                 "next_cursor" => nil
               })
    end

    for result <- [
          %{"threads" => []},
          %{"threads" => [], "next_cursor" => 1},
          %{"threads" => %{}, "next_cursor" => nil},
          %{"threads" => List.duplicate(%{"thread_id" => "thread-1"}, 101), "next_cursor" => nil}
        ] do
      assert {:error, %Error{code: "invalid_response"}} =
               Schema.validate_result("thread/list", result)
    end
  end

  test "JSON schema projects the same summary and pagination types" do
    definition = Document.build()["$defs"]["result.thread.list"]
    assert definition["required"] == ["next_cursor", "threads"]
    assert definition["properties"]["threads"]["maxItems"] == 100
    summary = definition["properties"]["threads"]["items"]
    assert summary["required"] == ["thread_id"]
    assert summary["additionalProperties"] == false
    assert summary["properties"]["updated_at"]["format"] == "date-time"
  end
end
