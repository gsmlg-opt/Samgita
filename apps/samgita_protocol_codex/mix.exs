defmodule SamgitaProtocolCodex.MixProject do
  use Mix.Project

  def project do
    [
      app: :samgita_protocol_codex,
      version: "0.1.1",
      description:
        "Pinned Codex app-server schemas and lossless native wire validation for Elixir clients.",
      package: [
        licenses: ["AGPL-3.0-only"],
        links: %{"GitHub" => "https://github.com/gsmlg-opt/Samgita"},
        files: ~w(lib priv config mix.exs README.md LICENSE .formatter.exs)
      ],
      elixir: "~> 1.18",
      build_path: "_build",
      deps_path: "deps",
      lockfile: "mix.lock",
      config_path: "config/config.exs",
      deps: [{:samgita_protocol, "~> 0.1.1", path: "../samgita_protocol"}]
    ]
  end

  def application, do: []
end
