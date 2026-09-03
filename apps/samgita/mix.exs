defmodule Samgita.MixProject do
  use Mix.Project

  def project do
    [
      app: :samgita,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [summary: [threshold: 80]]
    ]
  end

  def application do
    [
      mod: {Samgita.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:samgita_provider, in_umbrella: true},
      {:samgita_memory, in_umbrella: true},
      {:bcrypt_elixir, "~> 3.0"},
      {:ecto_sql, "~> 3.14"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_pubsub, "~> 2.3"},
      {:phoenix_ecto, "~> 4.5"},
      {:oban, "~> 2.24"},
      {:horde, "~> 0.9"},
      {:libcluster, "~> 3.4"},
      {:earmark, "~> 1.4"},
      {:swoosh, "~> 1.28"},
      {:finch, "~> 0.23"},
      {:dns_cluster, "~> 0.3"},
      {:gettext, "~> 1.0"},
      {:telemetry_metrics, "~> 1.2"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:mox, "~> 1.3", only: :test}
    ]
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
