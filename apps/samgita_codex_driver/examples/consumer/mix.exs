defmodule SamgitaCodexConsumer.MixProject do
  use Mix.Project

  def project do
    [
      app: :samgita_codex_consumer,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: [{:samgita_codex_driver, path: "../.."}]
    ]
  end

  def application, do: [extra_applications: [:crypto, :ssl]]
end
