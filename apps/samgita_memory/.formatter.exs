[
  import_deps: [:ecto, :ecto_sql],
  subdirectories: ["priv/*/migrations"],
  plugins: [],
  inputs: ["*.{ex,exs}", "{config,lib,test}/**/*.{ex,exs}", "priv/*/seeds.exs"]
]
