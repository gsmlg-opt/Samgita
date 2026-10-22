defmodule StandaloneConsumer.MixProject do
  use Mix.Project

  def project,
    do: [
      app: :standalone_consumer,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: [{:samgita_protocol, path: "../.."}]
    ]

  def application, do: []
end
