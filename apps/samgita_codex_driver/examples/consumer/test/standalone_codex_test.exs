defmodule StandaloneCodexTest do
  use ExUnit.Case, async: false

  test "outside-umbrella consumer controls the immutable actual Codex without database or Web" do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: CODEX_BINARY must select the immutable pinned upstream executable"

    root =
      Path.join(
        System.tmp_dir!(),
        "standalone-codex-consumer-#{System.unique_integer([:positive])}"
      )

    dirs = for name <- ~w(home codex workspace), do: Path.join(root, name)
    Enum.each(dirs, &File.mkdir_p!/1)
    on_exit(fn -> File.rm_rf!(root) end)
    [home, codex, workspace] = dirs
    {:ok, pid} = StandaloneCodex.start(binary, home, codex, workspace)
    on_exit(fn -> if Process.alive?(pid), do: StandaloneCodex.close(pid) end)

    assert {:ok, %{"result" => %{"data" => [], "nextCursor" => nil}}} =
             StandaloneCodex.list_threads(pid)

    assert SamgitaCodexDriver.Session.status(pid).phase == :ready
    assert :code.which(Samgita.Repo) == :non_existing
    assert :code.which(Phoenix.Endpoint) == :non_existing
    assert :code.which(Ecto.Repo) == :non_existing

    refute Enum.any?(Application.started_applications(), fn {app, _, _} ->
             app in [:samgita, :samgita_web, :ecto, :phoenix]
           end)

    assert :ok = StandaloneCodex.close(pid)
  end
end
