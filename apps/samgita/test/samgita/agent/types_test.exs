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
    # Planning tier (Opus)
    assert Types.model_for_type("prod-pm") == "opus"
    assert Types.model_for_type("eng-infra") == "opus"

    # Fast tier (Haiku) — eng-qa + all review-*
    assert Types.model_for_type("eng-qa") == "haiku"
    assert Types.model_for_type("review-code") == "haiku"
    assert Types.model_for_type("review-business") == "haiku"
    assert Types.model_for_type("review-security") == "haiku"

    # Development tier (Sonnet) — everything else
    assert Types.model_for_type("eng-backend") == "sonnet"
    assert Types.model_for_type("ops-monitor") == "sonnet"
    assert Types.model_for_type("ops-sre") == "sonnet"
    assert Types.model_for_type("biz-marketing") == "sonnet"
    assert Types.model_for_type("data-ml") == "sonnet"
    assert Types.model_for_type("growth-hacker") == "sonnet"
  end

  test "model_for_type/1 returns a valid model string for all 37 agent types" do
    valid_models = ["opus", "sonnet", "haiku"]

    Enum.each(Types.all_ids(), fn type_id ->
      model = Types.model_for_type(type_id)
      assert model in valid_models, "#{type_id} returned invalid model: #{inspect(model)}"
    end)
  end

  test "all agent types have non-empty id, name, and description" do
    Enum.each(Types.all(), fn {id, name, desc} ->
      assert String.length(id) > 0, "Empty id found"
      assert String.length(name) > 0, "Empty name for #{id}"
      assert String.length(desc) > 0, "Empty description for #{id}"
    end)
  end

  test "all 7 swarms are represented" do
    all_ids = Types.all_ids()

    # Engineering swarm prefix
    assert Enum.any?(all_ids, &String.starts_with?(&1, "eng-"))
    # Operations swarm prefix
    assert Enum.any?(all_ids, &String.starts_with?(&1, "ops-"))
    # Business swarm prefix
    assert Enum.any?(all_ids, &String.starts_with?(&1, "biz-"))
    # Data swarm prefix
    assert Enum.any?(all_ids, &String.starts_with?(&1, "data-"))
    # Product swarm prefix
    assert Enum.any?(all_ids, &String.starts_with?(&1, "prod-"))
    # Growth swarm prefix
    assert Enum.any?(all_ids, &String.starts_with?(&1, "growth-"))
    # Review swarm prefix
    assert Enum.any?(all_ids, &String.starts_with?(&1, "review-"))
  end

  test "all() is the union of all 7 swarms" do
    swarm_total =
      length(Types.engineering()) +
        length(Types.operations()) +
        length(Types.business()) +
        length(Types.data()) +
        length(Types.product()) +
        length(Types.growth()) +
        length(Types.review())

    assert swarm_total == length(Types.all())
  end

  test "valid?/1 returns true for all 37 known types" do
    Enum.each(Types.all_ids(), fn type_id ->
      assert Types.valid?(type_id), "Expected #{type_id} to be valid"
    end)
  end
end
