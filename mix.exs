defmodule Samgita.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      apps: [:samgita, :samgita_web],
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [plt_add_apps: [:ex_unit]],
      aliases: aliases(),
      releases: releases(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  defp deps do
    [
      # Dev/Test tools shared across all apps
      {:credo, "~> 1.7.19", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": [
        "ecto.create",
        "ecto.migrate",
        "run apps/samgita/priv/repo/seeds.exs"
      ],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": [
        "tailwind.install --if-missing",
        "bun.install --if-missing",
        "bun packages"
      ],
      "assets.copy": [&copy_static_assets/1],
      "assets.build": ["assets.copy", "tailwind samgita_web", "bun samgita_web"],
      "assets.deploy": [
        "assets.copy",
        "tailwind samgita_web --minify",
        "bun samgita_web --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end

  defp releases do
    [
      samgita: [
        version: "0.1.0",
        applications: [
          samgita: :permanent,
          samgita_web: :permanent
        ],
        include_executables_for: [:unix],
        steps: [:assemble, :tar]
      ]
    ]
  end

  defp copy_static_assets(_) do
    source = Path.join(__DIR__, "apps/samgita_web/assets/static")
    target = Path.join(__DIR__, "apps/samgita_web/priv/static")
    File.mkdir_p!(target)
    File.cp_r!(source, target)
  end
end
