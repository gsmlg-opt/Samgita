defmodule SamgitaProtocol.MixProject do
  use Mix.Project

  def project do
    [
      app: :samgita_protocol,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: if(Mix.env() == :test, do: ["lib", "test/support"], else: ["lib"]),
      deps: []
    ]
  end

  def application, do: [extra_applications: [:crypto]]
end
