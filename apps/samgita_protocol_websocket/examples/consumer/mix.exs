defmodule IndependentTransportConsumer.MixProject do
  use Mix.Project

  def project do
    [
      app: :independent_transport_consumer,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: [{:samgita_protocol_websocket, path: "../.."}]
    ]
  end

  def application, do: [extra_applications: [:logger]]
end
