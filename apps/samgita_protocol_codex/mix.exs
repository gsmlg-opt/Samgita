defmodule SamgitaProtocolCodex.MixProject do
  use Mix.Project

  def project do
    [
      app: :samgita_protocol_codex,
      version: "0.1.0",
      elixir: "~> 1.18",
      build_path: "_build",
      deps_path: "deps",
      lockfile: "mix.lock",
      config_path: "config/config.exs",
      deps: [{:samgita_protocol, path: "../samgita_protocol"}]
    ]
  end

  def application, do: []
end
