defmodule SamgitaCodexDriver.NativeLaunchFixture do
  @moduledoc false
  import ExUnit.Assertions

  @ordinary_overrides [
    "-c",
    "features.plugins=false",
    "-c",
    "features.recommended_plugins=false"
  ]
  @local_enabled "\n[features]\nplugins = true\nremote_plugin = false\n"
  @local_startup "\n[features]\nplugins = false\nremote_plugin = false\nrecommended_plugins = false\n"

  # Root CLI overrides leave fixture TOML and its existing [features] appenders
  # intact. This helper belongs only to explicitly owned native test launches.
  def ordinary_args(args), do: @ordinary_overrides ++ args

  # The callback must finish native initialization before returning. Only the
  # three owned local-plugin fixtures use this exact config fragment. Do not
  # generalize this into a TOML rewriter or apply CLI false overrides here: they
  # would remain effective after the file is restored and disable plugin tests.
  def local_plugins_after_initialize(config_path, initialize) do
    original = File.read!(config_path)

    assert length(:binary.matches(original, @local_enabled)) == 1,
           "Expected one owned local-plugin feature fragment"

    startup = String.replace(original, @local_enabled, @local_startup, global: false)
    replace!(config_path, startup)

    try do
      initialize.()
    after
      current = File.read!(config_path)
      replace!(config_path, original)

      assert current == startup,
             "Local-plugin initialization unexpectedly changed owned config"
    end
  end

  defp replace!(path, contents) do
    temporary = path <> ".plugin-startup-#{System.unique_integer([:positive])}"

    try do
      File.write!(temporary, contents, [:exclusive])
      File.rename!(temporary, path)
    after
      File.rm(temporary)
    end
  end
end
