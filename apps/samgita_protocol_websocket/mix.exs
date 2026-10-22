defmodule SamgitaProtocolWebSocket.MixProject do
  use Mix.Project

  def project do
    [
      app: :samgita_protocol_websocket,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps_path: "deps",
      build_path: "_build",
      lockfile: "mix.lock",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: [
        {:samgita_protocol, path: "../samgita_protocol"},
        {:bandit, "~> 1.12"},
        {:plug, "~> 1.19"},
        {:websock_adapter, "~> 0.6"},
        {:mint_web_socket, "~> 1.0"}
      ]
    ]
  end

  def application, do: [extra_applications: [:logger, :ssl]]
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
