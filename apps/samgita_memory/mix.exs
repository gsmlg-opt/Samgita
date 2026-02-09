defmodule SamgitaMemory.MixProject do
  use Mix.Project

  def project do
    [
      app: :samgita_memory,
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
      mod: {SamgitaMemory.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:pgvector, "~> 0.3"},
      {:oban, "~> 2.18"},
      {:jason, "~> 1.2"},
      {:telemetry, "~> 1.0"}
    ]
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
