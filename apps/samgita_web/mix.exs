defmodule SamgitaWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :samgita_web,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      test_coverage: [
        summary: [threshold: 70],
        ignore_modules: [
          SamgitaWeb.CoreComponents,
          SamgitaWeb.Layouts,
          SamgitaWeb.PageHTML,
          SamgitaWeb.Gettext
        ]
      ]
    ]
  end

  def application do
    [
      mod: {SamgitaWeb.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:samgita, in_umbrella: true},
      {:phoenix, "~> 1.8.3"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:phoenix_ecto, "~> 4.5"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:bun, "~> 1.6", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:bandit, "~> 1.5"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "bun.install --if-missing"],
      "assets.build": ["tailwind samgita_web", "bun samgita_web"],
      "assets.deploy": [
        "tailwind samgita_web --minify",
        "bun samgita_web --minify",
        "phx.digest"
      ]
    ]
  end
end
