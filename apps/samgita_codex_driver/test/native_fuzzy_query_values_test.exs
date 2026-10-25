defmodule SamgitaCodexDriver.NativeFuzzyQueryValuesTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  import TurnFixture, only: [call: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @body "Owned immutable fuzzy query input λ"

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      wire = JSON.decode!(encoded)

      if wire["method"] == "fuzzyFileSearch" do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 32 and byte_size(encoded) <= 4096 do
        with {:ok, next} <- Stdio.send(state, encoded) do
          Agent.update(state.capture, &(&1 ++ [wire]))
          {:ok, next}
        end
      else
        {:error, SamgitaProtocolCodex.Error.new(:test_capture_overflow), state}
      end
    end

    @impl true
    def handle_info(message, state), do: Stdio.handle_info(message, state)
    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup tags do
    ctx = TurnFixture.setup(tags)
    assert hash(File.read!(ctx.binary)) == @binary_sha
    TurnFixture.configure_model(ctx, %{})
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n"
    )

    capture = start_supervised!({Agent, fn -> [] end})
    Map.merge(ctx, %{capture: capture, config: config, config_bytes: File.read!(config)})
  end

  test "native one-shot ranking and sequential token presence retain the immutable upstream oracle",
       ctx do
    root = ctx.fixture.workspace
    paths = ~w(abc abcde abexy zzz.txt sub/abce)

    for path <- paths do
      absolute = Path.join(root, path)
      File.mkdir_p!(Path.dirname(absolute))
      File.write!(absolute, @body)
    end

    pid = start(ctx)
    expected = %{"files" => ranked(root)}

    for extra <- [
          %{},
          %{"cancellationToken" => nil},
          %{"cancellationToken" => "Owned reusable query token λ"},
          %{"cancellationToken" => "Owned reusable query token λ"}
        ] do
      params = Map.merge(%{"query" => "abe", "roots" => [root]}, extra)
      result = request(ctx, pid, params)
      assert result === expected
      assert length(result["files"]) == 3
    end

    # All calls above finish before reuse. This proves token presence and
    # sequential reuse, never cancellation of a concurrent in-flight search.
    for params <- [
          %{"query" => "", "roots" => [root]},
          %{"query" => "abe", "roots" => []},
          %{"query" => "owned_no_filename_matches_987654", "roots" => [root]}
        ] do
      assert request(ctx, pid, params) === %{"files" => []}
    end

    for path <- paths, do: assert(File.read!(Path.join(root, path)) == @body)
    assert Enum.sort(File.ls!(root)) == ~w(abc abcde abexy sub zzz.txt)
    assert File.ls!(Path.join(root, "sub")) == ["abce"]
    finish(ctx, pid, 7)
  end

  test "native roots preserve file and directory identity with Unicode character highlights",
       ctx do
    first = Path.join(ctx.fixture.workspace, "first")
    second = Path.join(ctx.fixture.workspace, "second")

    for root <- [first, second] do
      File.mkdir!(root)
      File.write!(Path.join(root, "λ_unicode.txt"), @body)
    end

    directory = Path.join(first, "unicode_directory")
    File.mkdir!(directory)
    pid = start(ctx)

    for {roots, expected} <- [
          {[first, second],
           [
             {first, "λ_unicode.txt", "file"},
             {second, "λ_unicode.txt", "file"},
             {first, "unicode_directory", "directory"}
           ]},
          {[first],
           [
             {first, "λ_unicode.txt", "file"},
             {first, "unicode_directory", "directory"}
           ]},
          {[second], [{second, "λ_unicode.txt", "file"}]}
        ] do
      result = request(ctx, pid, %{"query" => "unicode", "roots" => roots})
      files = Map.fetch!(result, "files")
      assert result === %{"files" => files}
      assert length(files) == length(expected)

      triples = Enum.map(files, &{&1["root"], &1["path"], &1["match_type"]})
      assert Enum.sort(triples) == Enum.sort(expected)

      for file <- files do
        assert Enum.sort(Map.keys(file)) ==
                 Enum.sort(~w(root path match_type file_name score indices))

        assert file["file_name"] == Path.basename(file["path"])
        assert is_integer(file["score"]) and file["score"] > 0

        expected_indices =
          case file["path"] do
            "λ_unicode.txt" -> [2, 3, 4, 5, 6, 7, 8]
            "unicode_directory" -> [0, 1, 2, 3, 4, 5, 6]
          end

        assert file["indices"] === expected_indices
        assert file["indices"] == Enum.sort(Enum.uniq(file["indices"]))
        chars = String.codepoints(file["path"])
        assert Enum.map_join(file["indices"], &Enum.at(chars, &1)) == "unicode"
      end
    end

    for root <- [first, second], do: assert(File.read!(Path.join(root, "λ_unicode.txt")) == @body)
    assert Enum.sort(File.ls!(first)) == ["unicode_directory", "λ_unicode.txt"]
    assert File.ls!(second) == ["λ_unicode.txt"]
    assert File.dir?(directory)
    assert File.ls!(directory) == []
    assert Enum.sort(File.ls!(ctx.fixture.workspace)) == ["first", "second"]
    finish(ctx, pid, 3)
  end

  # Exact literals from pinned app-server/tests/suite/fuzzy_file_search.rs,
  # test_fuzzy_file_search_sorts_and_includes_indices. No response supplies an
  # expected score, rank or highlight. The oracle is scoped to Linux paths.
  defp ranked(root) do
    [
      %{
        "root" => root,
        "path" => "abexy",
        "match_type" => "file",
        "file_name" => "abexy",
        "score" => 84,
        "indices" => [0, 1, 2]
      },
      %{
        "root" => root,
        "path" => "sub/abce",
        "match_type" => "file",
        "file_name" => "abce",
        "score" => 72,
        "indices" => [4, 5, 7]
      },
      %{
        "root" => root,
        "path" => "abcde",
        "match_type" => "file",
        "file_name" => "abcde",
        "score" => 71,
        "indices" => [0, 1, 4]
      }
    ]
  end

  defp request(ctx, pid, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-fuzzy-query-#{System.unique_integer([:positive, :monotonic])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request(pid, "fuzzyFileSearch", params, id: id)

    assert [wire] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    assert wire === %{"id" => id, "method" => "fuzzyFileSearch", "params" => params}
    assert ModelFixture.requests(ctx.fixture) == []
    result
  end

  defp finish(ctx, pid, count) do
    assert length(Agent.get(ctx.capture, & &1)) == count
    assert File.read!(ctx.config) == ctx.config_bytes
    assert ModelFixture.requests(ctx.fixture) == []
    assert call(pid, "thread/loaded/list", %{})["data"] == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native)
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{native}")
    assert ModelFixture.requests(ctx.fixture) == []
  end

  defp start(ctx) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {CaptureStdio,
           [
             capture: ctx.capture,
             executable: ctx.binary,
             args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
             cwd: fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "TMPDIR" => ctx.root,
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    %{transport: CaptureStdio, connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_fuzzy_query_values", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
