defmodule SamgitaCodexDriver.MixProject do
  use Mix.Project

  def project do
    [
      app: :samgita_codex_driver,
      version: "0.1.0",
      elixir: "~> 1.18",
      build_path: "_build",
      deps_path: "deps",
      lockfile: "mix.lock",
      config_path: "config/config.exs",
      elixirc_paths: if(Mix.env() == :test, do: ["lib", "test/support"], else: ["lib"]),
      deps: [
        {:samgita_protocol_codex, path: "../samgita_protocol_codex"},
        {:mint_web_socket, "~> 1.0"}
      ]
    ]
  end

  def application, do: [extra_applications: [:crypto, :ssl]]
end
