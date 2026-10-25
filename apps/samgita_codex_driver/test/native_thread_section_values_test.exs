defmodule SamgitaCodexDriver.NativeThreadSectionValuesTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaProtocolCodex.Error
  import TurnFixture, only: [call: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @pinned %{
    "id" => "01984de2-8f74-7c91-a3b2-5c5e937cf318",
    "name" => "Pinned",
    "appearance" => nil
  }
  @empty %{"icon" => nil, "color" => nil}
  @populated %{"icon" => "folder", "color" => "purple"}

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio
    @methods ~w(threadSection/create threadSection/update threadSection/list threadSection/delete)

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      wire = JSON.decode!(encoded)

      if wire["method"] in @methods do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 256 and byte_size(encoded) <= 4096 do
        with {:ok, next} <- Stdio.send(state, encoded) do
          Agent.update(state.capture, &(&1 ++ [wire]))
          {:ok, next}
        end
      else
        {:error, Error.new(:test_capture_overflow), state}
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

    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             @binary_sha

    TurnFixture.configure_model(ctx, %{})
    capture = start_supervised!({Agent, fn -> [] end})
    Map.put(ctx, :capture, capture)
  end

  test "create distinguishes absent null empty and populated appearances in native persisted pages",
       ctx do
    pid = start(ctx)

    sections =
      for {label, extra, appearance} <- [
            {"omitted", %{}, nil},
            {"null", %{"appearance" => nil}, nil},
            {"empty", %{"appearance" => %{}}, @empty},
            {"populated", %{"appearance" => @populated}, @populated},
            {"partial", %{"appearance" => %{"icon" => "star"}},
             %{"icon" => "star", "color" => nil}}
          ] do
        params = Map.put(extra, "name", "  Owned section #{label} λ  ")
        response = request(ctx, pid, "threadSection/create", params)
        section = Map.fetch!(response, "section")
        id = Map.fetch!(section, "id")
        assert_uuid(id)

        expected = %{
          "id" => id,
          "name" => "Owned section #{label} λ",
          "appearance" => appearance
        }

        assert response === %{"section" => expected}
        expected
      end

    assert length(Enum.uniq_by(sections, & &1["id"])) == 5
    expected = ordered(sections)
    assert_listing(ctx, pid, expected)

    for limit <- [0, 1, 2], do: assert_pages(ctx, pid, expected, limit)
    assert_functional_state(ctx, pid)
    cold = restart(ctx, pid)
    assert_listing(ctx, cold, expected)
    for limit <- [0, 1, 2], do: assert_pages(ctx, cold, expected, limit)
    assert_functional_state(ctx, cold)
    assert :ok = Session.close(cold)
  end

  test "update omission preserves null clears and objects replace rather than merge appearance",
       ctx do
    pid = start(ctx)
    subject = create(ctx, pid, "Owned mutable section", @populated)
    control = create(ctx, pid, "Owned unchanged section", %{"icon" => "control"})
    id = subject["id"]

    cases = [
      {%{}, @populated},
      {%{"appearance" => %{}}, @empty},
      {%{}, @empty},
      {%{"appearance" => %{"icon" => "star"}}, %{"icon" => "star", "color" => nil}},
      {%{"appearance" => nil}, nil},
      {%{}, nil},
      {%{"appearance" => %{"icon" => nil, "color" => "blue"}},
       %{"icon" => nil, "color" => "blue"}},
      {%{"appearance" => @populated}, @populated},
      {%{"appearance" => %{"icon" => "star", "color" => nil}},
       %{"icon" => "star", "color" => nil}},
      {%{}, %{"icon" => "star", "color" => nil}}
    ]

    final =
      Enum.reduce(Enum.with_index(cases, 1), subject, fn {{extra, appearance}, index}, _prior ->
        params =
          Map.merge(%{"sectionId" => id, "name" => "  Updated section #{index} λ  "}, extra)

        expected = %{
          "id" => id,
          "name" => "Updated section #{index} λ",
          "appearance" => appearance
        }

        assert request(ctx, pid, "threadSection/update", params) === %{"section" => expected}
        assert_list(ctx, pid, ordered([expected, control]), %{})
        expected
      end)

    expected = ordered([final, control])
    assert_pages(ctx, pid, expected, 1)
    assert_functional_state(ctx, pid)
    cold = restart(ctx, pid)
    assert_listing(ctx, cold, expected)
    assert_pages(ctx, cold, expected, 1)
    assert_functional_state(ctx, cold)
    assert :ok = Session.close(cold)
  end

  test "delete removes only its section and native not-found errors do not recreate it", ctx do
    pid = start(ctx)
    first = create(ctx, pid, "Owned deleted section", @populated)
    control = create(ctx, pid, "Owned retained section", nil)
    empty = create(ctx, pid, "Owned empty section", %{})
    assert_pages(ctx, pid, ordered([first, control, empty]), 1)
    deleted = %{"sectionId" => first["id"]}
    assert request(ctx, pid, "threadSection/delete", deleted) == %{}
    expected = ordered([control, empty])
    assert_listing(ctx, pid, expected)

    for {method, params} <- [
          {"threadSection/delete", deleted},
          {"threadSection/update", Map.put(deleted, "name", "Must remain deleted")}
        ] do
      assert request_error(ctx, pid, method, params) == %{
               "code" => -32_602,
               "message" => "thread section not found: #{first["id"]}"
             }

      assert_list(ctx, pid, expected, %{})
    end

    assert request_error(ctx, pid, "threadSection/update", %{
             "sectionId" => control["id"],
             "name" => " \t\n "
           }) == %{"code" => -32_602, "message" => "section name must not be empty"}

    assert_list(ctx, pid, expected, %{})
    assert_functional_state(ctx, pid)
    cold = restart(ctx, pid)
    assert_listing(ctx, cold, expected)

    for section <- [control, empty] do
      assert request(ctx, cold, "threadSection/delete", %{"sectionId" => section["id"]}) == %{}
    end

    assert_listing(ctx, cold, [@pinned])
    assert_pages(ctx, cold, [@pinned], 1)
    final = restart(ctx, cold)
    assert_listing(ctx, final, [@pinned])
    assert_functional_state(ctx, final)
    assert :ok = Session.close(final)
  end

  defp create(ctx, pid, name, appearance) do
    response =
      request(ctx, pid, "threadSection/create", %{"name" => name, "appearance" => appearance})

    section = Map.fetch!(response, "section")
    assert_uuid(Map.fetch!(section, "id"))
    section
  end

  defp ordered(sections), do: Enum.sort_by([@pinned | sections], & &1["id"])

  defp assert_listing(ctx, pid, expected) do
    for params <- [
          %{},
          %{"cursor" => nil},
          %{"limit" => nil},
          %{"cursor" => nil, "limit" => nil}
        ],
        do: assert_list(ctx, pid, expected, params)
  end

  defp assert_list(ctx, pid, expected, params) do
    assert request(ctx, pid, "threadSection/list", params) === %{
             "data" => expected,
             "nextCursor" => nil
           }
  end

  defp assert_pages(ctx, pid, expected, limit) do
    chunks = Enum.chunk_every(expected, max(limit, 1))

    Enum.reduce(Enum.with_index(chunks), nil, fn {chunk, index}, cursor ->
      params = %{"limit" => limit}
      params = if cursor, do: Map.put(params, "cursor", cursor), else: params
      next_cursor = if index == length(chunks) - 1, do: nil, else: List.last(chunk)["id"]

      assert request(ctx, pid, "threadSection/list", params) === %{
               "data" => chunk,
               "nextCursor" => next_cursor
             }

      next_cursor
    end)
  end

  defp request(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    result = call(pid, method, params)
    assert_capture(ctx, method, params, before)
    result
  end

  defp request_error(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-section-error-#{System.unique_integer([:positive, :monotonic])}"

    assert {:error, %Error{code: :upstream_error, wire: %{"id" => ^id, "error" => error}}} =
             Session.request(pid, method, params, id: id)

    assert_capture(ctx, method, params, before)
    error
  end

  defp assert_capture(ctx, method, params, before) do
    sent = Agent.get(ctx.capture, & &1)
    assert length(sent) == before + 1
    assert List.last(sent)["method"] == method
    assert List.last(sent)["params"] === params
  end

  defp assert_uuid(id),
    do: assert(id =~ ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)

  defp assert_functional_state(ctx, pid) do
    assert ModelFixture.requests(ctx.fixture) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
  end

  defp restart(ctx, pid) do
    assert_functional_state(ctx, pid)
    original = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(original)
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{original}")
    cold = start(ctx)
    replacement = call(cold, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(replacement) and replacement != original
    assert_functional_state(ctx, cold)
    cold
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
               %{"name" => "owned_thread_section_values", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end
end
