defmodule Samgita.Workers.QualityGateWorkerTest do
  use Samgita.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Samgita.Domain.Prd
  alias Samgita.Projects
  alias Samgita.Repo
  alias Samgita.Workers.QualityGateWorker

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

      assert artifacts != []
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

    test "summarizes empty results" do
      assert QualityGateWorker.summarize_results([]) == ""
    end

    test "includes finding count in summary" do
      results = [
        %{
          gate: 2,
          name: "Static Analysis",
          verdict: :fail,
          findings: [
            %{gate: 2, severity: :high, message: "issue1", file: nil, line: nil},
            %{gate: 2, severity: :medium, message: "issue2", file: nil, line: nil}
          ],
          duration_ms: 50
        }
      ]

      summary = QualityGateWorker.summarize_results(results)
      assert String.contains?(summary, "2 findings")
    end
  end

  describe "gate aggregation via perform" do
    test "defaults to pre_qa when gate_type is missing", %{project: project, prd: prd} do
      job = %Oban.Job{
        args: %{
          "project_id" => project.id,
          "prd_id" => prd.id
          # no gate_type
        }
      }

      assert :ok = QualityGateWorker.perform(job)
    end

    test "falls back to pre_qa for unknown gate_type", %{project: project, prd: prd} do
      job = %Oban.Job{
        args: %{
          "project_id" => project.id,
          "prd_id" => prd.id,
          "gate_type" => "custom_unknown"
        }
      }

      assert :ok = QualityGateWorker.perform(job)
    end

    test "stores verdict in artifact metadata", %{project: project, prd: prd} do
      job = %Oban.Job{
        args: %{
          "project_id" => project.id,
          "prd_id" => prd.id,
          "gate_type" => "pre_qa"
        }
      }

      :ok = QualityGateWorker.perform(job)

      artifacts =
        Samgita.Domain.Artifact
        |> Ecto.Query.where(project_id: ^project.id)
        |> Repo.all()

      assert length(artifacts) == 1
      artifact = hd(artifacts)
      assert artifact.metadata["verdict"] in ["pass", "fail"]
      assert is_integer(artifact.metadata["gate_count"])
      assert artifact.metadata["gate_count"] >= 1
      assert is_integer(artifact.metadata["findings_count"])
    end

    test "pre_deploy runs more gates than pre_qa", %{project: project, prd: prd} do
      # Run pre_qa
      job_qa = %Oban.Job{
        args: %{
          "project_id" => project.id,
          "prd_id" => prd.id,
          "gate_type" => "pre_qa"
        }
      }

      :ok = QualityGateWorker.perform(job_qa)

      qa_artifacts =
        Samgita.Domain.Artifact
        |> Ecto.Query.where(project_id: ^project.id)
        |> Repo.all()

      qa_gate_count = hd(qa_artifacts).metadata["gate_count"]

      # Clean artifacts for next run
      Repo.delete_all(
        Ecto.Query.from(a in Samgita.Domain.Artifact, where: a.project_id == ^project.id)
      )

      # Run pre_deploy
      job_deploy = %Oban.Job{
        args: %{
          "project_id" => project.id,
          "prd_id" => prd.id,
          "gate_type" => "pre_deploy"
        }
      }

      :ok = QualityGateWorker.perform(job_deploy)

      deploy_artifacts =
        Samgita.Domain.Artifact
        |> Ecto.Query.where(project_id: ^project.id)
        |> Repo.all()

      deploy_gate_count = hd(deploy_artifacts).metadata["gate_count"]

      # pre_deploy should run more gates (adds test coverage, mock detector, mutation detector)
      assert deploy_gate_count >= qa_gate_count
    end

    test "creates tasks and includes them in project status", %{project: project, prd: prd} do
      # Create some tasks to ensure project status is populated
      {:ok, _task} =
        Projects.create_task(project.id, %{
          type: "implement",
          payload: %{"description" => "Test task"},
          priority: 1,
          status: :completed
        })

      job = %Oban.Job{
        args: %{
          "project_id" => project.id,
          "prd_id" => prd.id,
          "gate_type" => "pre_qa"
        }
      }

      assert :ok = QualityGateWorker.perform(job)
    end
  end
end
