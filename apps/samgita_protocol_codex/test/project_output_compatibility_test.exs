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

  test "compatible results accept Project with or without its former position field" do
    for method <- @methods,
        project <- [@project, Map.put(@project, "position", 3)] do
      result = result(method, project)

      assert :ok =
               Schema.validate_result(:server_response, method, result, schema_mode: :compatible)
    end
  end

  test "strict and default results retain the snapshot requirement for position" do
    for method <- @methods, opts <- [[], [schema_mode: :strict]] do
      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_result(:server_response, method, result(method, @project), opts)

      assert :ok =
               Schema.validate_result(
                 :server_response,
                 method,
                 result(method, Map.put(@project, "position", 3)),
                 opts
               )
    end
  end

  test "compatible Project results still validate remaining fields and any supplied position" do
    invalid_projects =
      Enum.map(~w(id name metadata roots createdAt updatedAt), &Map.delete(@project, &1)) ++
        [
          Map.put(@project, "position", nil),
          Map.put(@project, "position", "3"),
          Map.put(@project, "position", 1.5),
          Map.put(@project, "metadata", %{"color" => 1}),
          Map.put(@project, "roots", [%{}]),
          Map.put(@project, "recencyAt", "recent"),
          Map.put(@project, "createdAt", "1")
        ]

    for method <- @methods, project <- invalid_projects do
      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_result(:server_response, method, result(method, project),
                 schema_mode: :compatible
               )
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
