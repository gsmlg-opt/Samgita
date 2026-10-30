defmodule SamgitaProtocol.MixProject do
  use Mix.Project

  def project do
    [
      app: :samgita_protocol,
      version: "0.1.0",
      description:
        "Transport-independent Agent protocol with versioned schemas and explicit lifecycle semantics.",
      package: [
        licenses: ["AGPL-3.0-only"],
        links: %{"GitHub" => "https://github.com/gsmlg-opt/Samgita"},
        files: ~w(lib priv mix.exs README.md LICENSE .formatter.exs)
      ],
      elixir: "~> 1.18",
      elixirc_paths: if(Mix.env() == :test, do: ["lib", "test/support"], else: ["lib"]),
      deps: []
    ]
  end

  def application, do: [extra_applications: [:crypto]]
end
