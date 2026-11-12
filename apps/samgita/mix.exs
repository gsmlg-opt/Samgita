defmodule Samgita.MixProject do
  use Mix.Project

  def project do
    [
      app: :samgita,
      version: "0.4.1",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
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
      {:samgita_protocol_websocket, path: "../samgita_protocol_websocket"},
      {:samgita_codex_driver, path: "../samgita_codex_driver"},
      {:ecto_sql, "~> 3.14"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_pubsub, "~> 2.3"},
      {:styx, "~> 0.1.1"},
      {:jason, "~> 1.4"},
      {:tzdata, "~> 1.1"},
      {:http_fetch, "~> 1.0.0-rc.5"}
    ]
  end
end
