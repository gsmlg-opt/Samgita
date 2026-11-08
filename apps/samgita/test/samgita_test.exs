defmodule SamgitaTest do
  use Samgita.DataCase, async: true

  test "health checks only the authoritative database" do
    assert Samgita.health_checks() == %{samgita_repo: :ok}
  end

  test "the foundation supervises Repo, PubSub, durable maintenance and Codex host connections" do
    children = Supervisor.which_children(Samgita.Supervisor)

    assert Enum.sort(Enum.map(children, &elem(&1, 0))) ==
             Enum.sort([
               Samgita.Repo,
               Phoenix.PubSub.Supervisor,
               Styx,
               Samgita.CodexHosts.Runtime
             ])

    assert Application.fetch_env!(:samgita, :ecto_repos) == [Samgita.Repo]
    assert Styx.config().testing == :manual
  end
end
