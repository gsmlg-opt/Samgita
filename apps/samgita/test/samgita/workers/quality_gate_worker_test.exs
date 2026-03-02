defmodule Samgita.Workers.QualityGateWorkerTest do
  use Samgita.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Samgita.Workers.QualityGateWorker
  alias Samgita.Projects
  alias Samgita.Domain.Prd
  alias Samgita.Repo

  setup do
    Sandbox.mode(Samgita.Repo, {:shared, self()})

    {:ok, project} =
      Projects.create_project(%{
        name: "Quality Gate Test",
        git_url: "git@github.com:test/qg-#{System.unique_integer([:positive])}.git",
        prd_content: "# Test PRD\n\n## Features\n\n1. User login\n2. Dashboard",
        status: :running
      })

    {:ok, prd} =
      %Prd{}
      |> Prd.changeset(%{
        title: "Test PRD",
        content: "# Test PRD\n\n## Features\n\n1. User login\n2. Dashboard",
        status: :approved,
        project_id: project.id
      })
      |> Repo.insert()

    %{project: project, prd: prd}
  end

  describe "perform/1" do
    test "runs pre_qa gates", %{project: project, prd: prd} do
      job = %Oban.Job{
        args: %{
          "project_id" => project.id,
          "prd_id" => prd.id,
          "gate_type" => "pre_qa"
        }
      }

      assert :ok = QualityGateWorker.perform(job)
    end

    test "runs pre_deploy gates", %{project: project, prd: prd} do
      job = %Oban.Job{
        args: %{
          "project_id" => project.id,
          "prd_id" => prd.id,
          "gate_type" => "pre_deploy"
        }
      }

      assert :ok = QualityGateWorker.perform(job)
    end

    test "returns error for nonexistent project", %{prd: prd} do
      job = %Oban.Job{
        args: %{
          "project_id" => Ecto.UUID.generate(),
          "prd_id" => prd.id,
          "gate_type" => "pre_qa"
        }
      }

      assert {:error, :not_found} = QualityGateWorker.perform(job)
    end

    test "returns error for nonexistent PRD", %{project: project} do
      job = %Oban.Job{
        args: %{
          "project_id" => project.id,
          "prd_id" => Ecto.UUID.generate(),
          "gate_type" => "pre_qa"
        }
      }

      assert {:error, :prd_not_found} = QualityGateWorker.perform(job)
    end

    test "returns error for nil PRD ID", %{project: project} do
      job = %Oban.Job{
        args: %{
          "project_id" => project.id,
          "prd_id" => nil,
          "gate_type" => "pre_qa"
        }
      }

      assert {:error, :no_prd} = QualityGateWorker.perform(job)
    end

    test "stores artifact with gate results", %{project: project, prd: prd} do
      job = %Oban.Job{
        args: %{
          "project_id" => project.id,
          "prd_id" => prd.id,
          "gate_type" => "pre_qa"
        }
      }

      :ok = QualityGateWorker.perform(job)

      # Check artifact was created
      artifacts =
        Samgita.Domain.Artifact
        |> Ecto.Query.where(project_id: ^project.id)
        |> Repo.all()

      assert length(artifacts) >= 1
      artifact = List.first(artifacts)
      assert artifact.type == :doc
      assert String.starts_with?(artifact.path, "quality_gates/pre_qa_")
      assert artifact.metadata["gate_type"] == "pre_qa"
      assert artifact.metadata["verdict"] in ["pass", "fail"]
    end
  end

  describe "summarize_results/1" do
    test "formats gate results into readable summary" do
      results = [
        %{gate: 3, name: "Blind Review", verdict: :pass, findings: [], duration_ms: 100},
        %{
          gate: 4,
          name: "Completion Council",
          verdict: :fail,
          findings: [%{severity: :medium, message: "issue"}],
          duration_ms: 200
        }
      ]

      summary = QualityGateWorker.summarize_results(results)
      assert String.contains?(summary, "Gate 3")
      assert String.contains?(summary, "Blind Review")
      assert String.contains?(summary, "pass")
      assert String.contains?(summary, "Gate 4")
      assert String.contains?(summary, "fail")
    end
  end
end
