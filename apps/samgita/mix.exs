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
      deps: deps()
    ]
  end

  def application do
    [mod: {Samgita.Application, []}, extra_applications: [:logger, :runtime_tools]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:samgita_protocol, path: "../samgita_protocol"},
      {:ecto_sql, "~> 3.14"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_pubsub, "~> 2.3"},
      {:oban, "~> 2.24"},
      {:jason, "~> 1.4"}
    ]
  end
end
