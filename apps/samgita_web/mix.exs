defmodule SamgitaWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :samgita_web,
      version: "0.3.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      test_coverage: [
        summary: [threshold: 70],
        ignore_modules: [
          SamgitaWeb.Layouts,
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
      {:phoenix_live_reload, "~> 1.7", only: :dev},
      {:phoenix_live_view, "~> 1.2"},
      {:phoenix_ecto, "~> 4.5"},
      {:lazy_html, ">= 0.1.13"},
      # TODO(upstream): duskmoon-dev/duskmoon-bundler#9 - qualify assets on a glibc 2.43+ builder.
      {:duskmoon_bundler, "~> 10.1.2", runtime: Mix.env() in [:dev, :test]},
      {:duskmoon_bundler_runtime, "~> 10.1.2"},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:phoenix_duskmoon, "~> 10.1.0"},
      # TODO(upstream): gsmlg-dev/gaoxy#22 - adopt the published Abyss/Hell RC cohort refresh.
      {:gaoxy_http, "~> 0.15.1"},
      {:websock_adapter, "~> 0.15.1", hex: :gaoxy_websock_adapter, override: true},
      {:telemetry_metrics, "~> 1.2"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.4"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["npm.ci"],
      "assets.copy": [&copy_static_assets/1],
      "assets.build": ["assets.copy", "duskmoon_bundler.build samgita_web --tailwind"],
      "assets.deploy": [
        "assets.copy",
        "duskmoon_bundler.build samgita_web --tailwind",
        "phx.digest"
      ]
    ]
  end

  defp copy_static_assets(_) do
    source = Path.join(__DIR__, "assets/static")
    target = Path.join(__DIR__, "priv/static")
    File.mkdir_p!(target)
    File.cp_r!(source, target)
  end
end
