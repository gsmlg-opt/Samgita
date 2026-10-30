defmodule SamgitaCodexDriver.MixProject do
  use Mix.Project

  def project do
    [
      app: :samgita_codex_driver,
      version: "0.1.0",
      description:
        "Explicitly owned Codex app-server sessions, transports, tool interactions and truthful recovery.",
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
      elixirc_paths: if(Mix.env() == :test, do: ["lib", "test/support"], else: ["lib"]),
      deps: [
        {:samgita_protocol_codex, "~> 0.1.0", path: "../samgita_protocol_codex"},
        {:mint_web_socket, "~> 1.0"}
      ]
    ]
  end

  def application, do: [extra_applications: [:crypto, :ssl]]
end
