defmodule Samgita.Agent.ResultParserTest do
  use ExUnit.Case, async: true

  alias Samgita.Agent.ResultParser

  describe "classify/1" do
    test "classifies successful binary result" do
      assert {:success, "hello world"} = ResultParser.classify({:ok, "hello world"})
    end

    test "classifies empty string as failure" do
      assert {:failure, :empty_response} = ResultParser.classify({:ok, ""})
    end

    test "classifies nil result as failure" do
      assert {:failure, :nil_response} = ResultParser.classify({:ok, nil})
    end

    test "classifies error tuple with atom reason" do
      assert {:failure, :rate_limit} = ResultParser.classify({:error, :rate_limit})
    end

    test "classifies error tuple with string reason" do
      assert {:failure, "connection refused"} =
               ResultParser.classify({:error, "connection refused"})
    end

    test "classifies unexpected format" do
      assert {:failure, :unexpected_format} = ResultParser.classify(:something_else)
      assert {:failure, :unexpected_format} = ResultParser.classify(42)
      assert {:failure, :unexpected_format} = ResultParser.classify(nil)
    end
  end

  describe "success?/1" do
    test "true for success tuples" do
      assert ResultParser.success?({:success, "result"}) == true
    end

    test "false for failure tuples" do
      assert ResultParser.success?({:failure, :rate_limit}) == false
    end
  end

  describe "error_category/1" do
    test "extracts category from failure" do
      assert ResultParser.error_category({:failure, :rate_limit}) == :rate_limit
      assert ResultParser.error_category({:failure, "some error"}) == "some error"
    end

    test "returns nil for success" do
      assert ResultParser.error_category({:success, "ok"}) == nil
    end
  end
end
