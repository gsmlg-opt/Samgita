defmodule SamgitaProtocolCodex.ProjectOutputCompatibilityTest do
  use ExUnit.Case, async: true

  alias SamgitaProtocolCodex.{Error, Schema}

  @methods ~w(project/list project/read project/create project/update project/import)
  @project %{
    "id" => "project",
    "name" => "Example",
    "metadata" => %{"color" => "blue"},
    "roots" => [%{"path" => "/workspace/example"}],
    "createdAt" => 1,
    "updatedAt" => 2,
    "recencyAt" => nil
  }

  test "current Project results need no position in every schema mode" do
    for method <- @methods,
        opts <- [[], [schema_mode: :strict], [schema_mode: :compatible]] do
      assert :ok =
               Schema.validate_result(:server_response, method, result(method, @project), opts)
    end
  end

  test "a former position field follows the same unknown-field policy as other output additions" do
    for method <- @methods,
        opts <- [[], [schema_mode: :strict], [schema_mode: :compatible]],
        position <- [3, nil, "3", 1.5, %{"opaque" => [false]}] do
      project = Map.put(@project, "position", position)
      result = result(method, project)
      original = JSON.encode!(result)
      assert :ok = Schema.validate_result(:server_response, method, result, opts)
      assert JSON.encode!(result) == original
    end
  end

  test "Project results retain current required fields and typed output constraints" do
    invalid_projects =
      Enum.map(~w(id name metadata roots createdAt updatedAt), &Map.delete(@project, &1)) ++
        [
          Map.put(@project, "metadata", %{"color" => 1}),
          Map.put(@project, "roots", [%{}]),
          Map.put(@project, "recencyAt", "recent"),
          Map.put(@project, "createdAt", "1")
        ]

    for method <- @methods,
        project <- invalid_projects,
        opts <- [[], [schema_mode: :strict], [schema_mode: :compatible]] do
      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_result(:server_response, method, result(method, project), opts)
    end

    assert {:error, %Error{code: :schema_violation}} =
             Schema.validate_result(:server_response, "project/list", %{"data" => false},
               schema_mode: :compatible
             )

    assert {:error, %Error{code: :schema_violation}} =
             Schema.validate_result(:server_response, "thread/list", %{"data" => false},
               schema_mode: :compatible
             )
  end

  defp result("project/list", project), do: %{"data" => [project], "nextCursor" => nil}
  defp result(_method, project), do: %{"project" => project}
end
