defmodule SamgitaTest do
  use Samgita.DataCase, async: true

  test "health checks only the authoritative database" do
    assert Samgita.health_checks() == %{samgita_repo: :ok}
  end

  test "the foundation supervises only Repo, PubSub and durable maintenance" do
    children = Supervisor.which_children(Samgita.Supervisor)

    assert Enum.sort(Enum.map(children, &elem(&1, 0))) ==
             Enum.sort([Samgita.Repo, Phoenix.PubSub.Supervisor, Oban])

    assert Application.fetch_env!(:samgita, :ecto_repos) == [Samgita.Repo]
    assert Oban.config().testing == :manual
  end
end
