defmodule Samgita.Agent.TypesTest do
  use ExUnit.Case, async: true

  alias Samgita.Agent.Types

  test "defines 37 agent types" do
    assert length(Types.all()) == 37
  end

  test "all IDs are unique" do
    ids = Types.all_ids()
    assert length(ids) == length(Enum.uniq(ids))
  end

  test "engineering swarm has 8 agents" do
    assert length(Types.engineering()) == 8
  end

  test "operations swarm has 8 agents" do
    assert length(Types.operations()) == 8
  end

  test "business swarm has 8 agents" do
    assert length(Types.business()) == 8
  end

  test "data swarm has 3 agents" do
    assert length(Types.data()) == 3
  end

  test "product swarm has 3 agents" do
    assert length(Types.product()) == 3
  end

  test "growth swarm has 4 agents" do
    assert length(Types.growth()) == 4
  end

  test "review swarm has 3 agents" do
    assert length(Types.review()) == 3
  end

  test "get/1 returns agent type by id" do
    assert {"eng-backend", "Backend Engineer", _} = Types.get("eng-backend")
  end

  test "get/1 returns nil for unknown type" do
    assert nil == Types.get("unknown")
  end

  test "valid?/1 validates known types" do
    assert Types.valid?("eng-backend")
    refute Types.valid?("unknown")
  end

  test "model_for_type/1 returns appropriate model" do
    assert Types.model_for_type("prod-pm") == "opus"
    assert Types.model_for_type("eng-qa") == "haiku"
    assert Types.model_for_type("eng-backend") == "sonnet"
  end
end
