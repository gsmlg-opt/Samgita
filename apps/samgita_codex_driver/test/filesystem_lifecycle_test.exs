defmodule SamgitaCodexDriver.FilesystemLifecycleTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000

  setup tags do
    ctx = TurnFixture.setup(tags)
    pid = TurnFixture.start(ctx)
    Map.put(ctx, :session, pid)
  end

  test "directory watch rejects duplicate IDs and unwatch fences future notifications", ctx do
    pid = ctx.session
    watched = Path.join(ctx.fixture.workspace, "watched-é")
    control = Path.join(ctx.fixture.workspace, "control")
    File.mkdir!(watched)
    File.mkdir!(control)
    child = Path.join(watched, "child.txt")
    control_child = Path.join(control, "control.txt")

    assert rpc(pid, "fs/watch", %{"path" => watched, "watchId" => "owner-watch"}) == %{
             "path" => watched
           }

    assert rpc_error(pid, "fs/watch", %{"path" => control, "watchId" => "owner-watch"}) ==
             %{"code" => -32_600, "message" => "watchId already exists: owner-watch"}

    assert rpc(pid, "fs/watch", %{"path" => control, "watchId" => "control-watch"}) == %{
             "path" => control
           }

    File.write!(child, "before unwatch")
    assert_change(pid, "owner-watch", child)
    assert rpc(pid, "fs/unwatch", %{"watchId" => "owner-watch"}) == %{}
    assert rpc(pid, "fs/unwatch", %{"watchId" => "owner-watch"}) == %{}
    drain(pid)

    File.write!(child, "after unwatch")
    File.write!(control_child, "control mutation")
    events = assert_change(pid, "control-watch", control_child)
    refute_watch(events, "owner-watch")
    assert_watch_quiet(pid, "owner-watch")

    # An explicit new subscription may reuse a released identifier.
    assert rpc(pid, "fs/watch", %{"path" => watched, "watchId" => "owner-watch"}) == %{
             "path" => watched
           }

    File.write!(child, "after explicit rewatch")
    assert_change(pid, "owner-watch", child)
    assert rpc(pid, "fs/unwatch", %{"watchId" => "owner-watch"}) == %{}
    assert rpc(pid, "fs/unwatch", %{"watchId" => "control-watch"}) == %{}
    assert_no_model_requests(ctx)
  end

  test "a missing file watch survives atomic replacements and ends with its connection", ctx do
    pid = ctx.session
    target = Path.join(ctx.fixture.workspace, "missing-HEAD")
    refute File.exists?(target)

    assert rpc(pid, "fs/watch", %{"path" => target, "watchId" => "atomic-watch"}) == %{
             "path" => target
           }

    for contents <- ["first\n", "second replacement\n"] do
      staging = target <> ".staging"
      File.write!(staging, contents)
      File.rename!(staging, target)
      events = assert_change(pid, "atomic-watch", target)
      assert File.read!(target) == contents

      for event <- events, event.wire["method"] == "fs/changed" do
        assert_change_event(event, "atomic-watch", target)
      end
    end

    assert :ok = Session.close(pid)
    resumed = TurnFixture.start(ctx)

    assert rpc(resumed, "fs/watch", %{"path" => target, "watchId" => "atomic-watch"}) == %{
             "path" => target
           }

    File.write!(target, "new connection mutation")
    assert_change(resumed, "atomic-watch", target)
    assert rpc(resumed, "fs/unwatch", %{"watchId" => "atomic-watch"}) == %{}
    assert_no_model_requests(ctx)
  end

  test "byte writes truncate and reject malformed base64 without corrupting file or metadata",
       ctx do
    pid = ctx.session
    file = Path.join(ctx.fixture.workspace, "binary é🙂.bin")
    bytes = <<0, 255, 195, 40, 13, 10, 0, 1>>

    for contents <- [bytes, <<1, 0>>, <<>>] do
      assert rpc(pid, "fs/writeFile", %{
               "path" => file,
               "dataBase64" => Base.encode64(contents)
             }) == %{}

      assert File.read!(file) == contents

      assert rpc(pid, "fs/readFile", %{"path" => file}) == %{
               "dataBase64" => Base.encode64(contents)
             }
    end

    assert rpc_error(pid, "fs/writeFile", %{"path" => file, "dataBase64" => "%%%%"}) == %{
             "code" => -32_600,
             "message" =>
               "fs/writeFile requires valid base64 dataBase64: Invalid symbol 37, offset 0."
           }

    assert File.read!(file) == <<>>
    directory = Path.join(ctx.fixture.workspace, "directory")
    File.mkdir!(directory)
    file_link = Path.join(ctx.fixture.workspace, "binary-link")
    directory_link = Path.join(ctx.fixture.workspace, "directory-link")
    File.ln_s!(file, file_link)
    File.ln_s!(directory, directory_link)

    for {path, kind, symlink} <- [
          {file, :file, false},
          {file_link, :file, true},
          {directory, :directory, false},
          {directory_link, :directory, true}
        ] do
      metadata = rpc(pid, "fs/getMetadata", %{"path" => path})

      assert Map.keys(metadata) |> Enum.sort() ==
               Enum.sort(~w(createdAtMs isDirectory isFile isSymlink modifiedAtMs))

      assert metadata["isDirectory"] == (kind == :directory)
      assert metadata["isFile"] == (kind == :file)
      assert metadata["isSymlink"] == symlink
      assert is_integer(metadata["createdAtMs"]) and metadata["createdAtMs"] >= 0
      assert is_integer(metadata["modifiedAtMs"]) and metadata["modifiedAtMs"] > 0
    end

    assert rpc(pid, "fs/readDirectory", %{"path" => directory}) == %{"entries" => []}
    missing = Path.join(directory, "missing")

    for method <- ["fs/readFile", "fs/getMetadata", "fs/readDirectory"] do
      assert rpc_error(pid, method, %{"path" => missing}) == %{
               "code" => -32_603,
               "message" => "No such file or directory (os error 2)"
             }
    end

    assert_no_model_requests(ctx)
  end

  test "directory and remove optional null/defaults preserve explicit false protections", ctx do
    pid = ctx.session
    refused = Path.join(ctx.fixture.workspace, "no-parent/child")

    assert rpc_error(pid, "fs/createDirectory", %{"path" => refused, "recursive" => false}) ==
             %{"code" => -32_603, "message" => "No such file or directory (os error 2)"}

    refute File.exists?(Path.dirname(refused))

    for {suffix, options} <- [{"omitted", %{}}, {"null", %{"recursive" => nil}}] do
      directory = Path.join(ctx.fixture.workspace, "#{suffix}/nested/leaf")
      assert rpc(pid, "fs/createDirectory", Map.put(options, "path", directory)) == %{}
      assert File.dir?(directory)
      child = Path.join(directory, "keep.txt")
      File.write!(child, "preserved while nonrecursive")

      assert rpc_error(pid, "fs/remove", %{
               "path" => directory,
               "recursive" => false,
               "force" => false
             }) == %{"code" => -32_603, "message" => "Directory not empty (os error 39)"}

      assert File.read!(child) == "preserved while nonrecursive"
      removal = if suffix == "null", do: %{"recursive" => nil, "force" => nil}, else: %{}
      assert rpc(pid, "fs/remove", Map.put(removal, "path", directory)) == %{}
      refute File.exists?(directory)
      assert rpc(pid, "fs/remove", Map.put(removal, "path", directory)) == %{}

      assert rpc_error(pid, "fs/remove", %{"path" => directory, "force" => false}) == %{
               "code" => -32_603,
               "message" => "No such file or directory (os error 2)"
             }
    end

    assert_no_model_requests(ctx)
  end

  test "copy guards leave sources intact and recursive copies preserve owned relative symlinks",
       ctx do
    pid = ctx.session
    source = Path.join(ctx.fixture.workspace, "source")
    nested = Path.join(source, "nested")
    File.mkdir_p!(nested)
    contents = <<255, 0, 1, 10>>
    File.write!(Path.join(nested, "bytes"), contents)
    File.ln_s!("nested", Path.join(source, "nested-link"))
    destination = Path.join(ctx.fixture.workspace, "destination")

    assert rpc_error(pid, "fs/copy", %{
             "sourcePath" => source,
             "destinationPath" => destination
           }) == %{
             "code" => -32_600,
             "message" => "fs/copy requires recursive: true when sourcePath is a directory"
           }

    refute File.exists?(destination)

    for invalid_destination <- [source, Path.join(nested, "copy")] do
      assert rpc_error(pid, "fs/copy", %{
               "sourcePath" => source,
               "destinationPath" => invalid_destination,
               "recursive" => true
             }) == %{
               "code" => -32_600,
               "message" => "fs/copy cannot copy a directory to itself or one of its descendants"
             }
    end

    refute File.exists?(Path.join(nested, "copy"))

    assert rpc(pid, "fs/copy", %{
             "sourcePath" => source,
             "destinationPath" => destination,
             "recursive" => true
           }) == %{}

    assert File.read_link!(Path.join(destination, "nested-link")) == "nested"
    assert File.read!(Path.join(destination, "nested-link/bytes")) == contents

    entries = rpc(pid, "fs/readDirectory", %{"path" => destination})["entries"]

    assert Enum.sort_by(entries, & &1["fileName"]) == [
             %{"fileName" => "nested", "isDirectory" => true, "isFile" => false},
             %{"fileName" => "nested-link", "isDirectory" => true, "isFile" => false}
           ]

    copied_file = Path.join(ctx.fixture.workspace, "copy.bin")

    assert rpc(pid, "fs/copy", %{
             "sourcePath" => Path.join(nested, "bytes"),
             "destinationPath" => copied_file,
             "recursive" => false
           }) == %{}

    assert File.read!(copied_file) == contents
    assert rpc(pid, "fs/remove", %{"path" => Path.join(destination, "nested-link")}) == %{}
    assert File.read!(Path.join(destination, "nested/bytes")) == contents
    assert File.read!(Path.join(nested, "bytes")) == contents
    assert_no_model_requests(ctx)
  end

  test "all filesystem path positions reject relative input at the upstream schema boundary",
       ctx do
    pid = ctx.session
    absolute = Path.join(ctx.fixture.workspace, "absolute.txt")
    File.write!(absolute, "do not mutate")

    variants = [
      {"fs/readFile", %{"path" => "relative.txt"}},
      {"fs/writeFile", %{"path" => "relative.txt", "dataBase64" => ""}},
      {"fs/createDirectory", %{"path" => "relative-dir", "recursive" => nil}},
      {"fs/getMetadata", %{"path" => "relative.txt"}},
      {"fs/readDirectory", %{"path" => "relative-dir"}},
      {"fs/remove", %{"path" => "relative.txt", "recursive" => nil, "force" => nil}},
      {"fs/copy", %{"sourcePath" => "relative.txt", "destinationPath" => absolute}},
      {"fs/copy", %{"sourcePath" => absolute, "destinationPath" => "relative-copy.txt"}},
      {"fs/watch", %{"path" => "relative-path", "watchId" => "relative-watch"}}
    ]

    for {{method, params}, index} <- Enum.with_index(variants) do
      id = if rem(index, 2) == 0, do: 50_000 + index, else: "relative-#{index}"

      assert rpc_error(pid, method, params, id: id, validation: :wire) == %{
               "code" => -32_600,
               "message" => "Invalid request: AbsolutePathBuf deserialized without a base path"
             }
    end

    assert File.read!(absolute) == "do not mutate"
    refute File.exists?(Path.join(ctx.fixture.workspace, "relative.txt"))
    refute File.exists?(Path.join(ctx.fixture.workspace, "relative-dir"))
    assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid)
    assert_no_model_requests(ctx)
  end

  defp rpc(pid, method, params) do
    id = "fs-request-#{System.unique_integer([:positive])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, %{"id" => id, "method" => method, "params" => params})

    result
  end

  defp rpc_error(pid, method, params, opts \\ []) do
    id = Keyword.get(opts, :id, "fs-error-#{System.unique_integer([:positive])}")

    assert {:error, %Error{code: :upstream_error, wire: %{"id" => ^id, "error" => error}}} =
             Session.request_native(
               pid,
               %{"id" => id, "method" => method, "params" => params},
               Keyword.delete(opts, :id)
             )

    error
  end

  defp assert_change(pid, watch_id, path) do
    events = collect_change(pid, watch_id, path, [], System.monotonic_time(:millisecond) + 5_000)

    event =
      Enum.find(events, fn event ->
        event.wire["method"] == "fs/changed" and
          event.wire["params"]["watchId"] == watch_id
      end)

    assert_change_event(event, watch_id, path)

    events
  end

  defp assert_change_event(event, watch_id, path) do
    assert %{
             "method" => "fs/changed",
             "params" => %{"watchId" => ^watch_id, "changedPaths" => [^path]},
             "emittedAtMs" => emitted_at
           } = event.wire

    assert Enum.sort(Map.keys(event.wire)) == ~w(emittedAtMs method params)
    assert is_integer(emitted_at) and emitted_at > 0
  end

  defp collect_change(pid, watch_id, path, acc, deadline) do
    events = acc ++ drain(pid)

    if Enum.any?(events, fn event ->
         event.wire["method"] == "fs/changed" and
           event.wire["params"]["watchId"] == watch_id and
           path in event.wire["params"]["changedPaths"]
       end) do
      events
    else
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {:codex_driver, ^pid, :events_available} ->
          collect_change(pid, watch_id, path, events, deadline)

        {:codex_driver, ^pid, {:gap, _}} ->
          flunk("unexpected filesystem notification gap")
      after
        remaining -> flunk("missing real fs/changed for #{inspect({watch_id, path})}")
      end
    end
  end

  defp assert_watch_quiet(pid, watch_id, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 500
    refute_watch(drain(pid), watch_id)
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:codex_driver, ^pid, :events_available} -> assert_watch_quiet(pid, watch_id, deadline)
      {:codex_driver, ^pid, {:gap, _}} -> flunk("unexpected filesystem notification gap")
    after
      remaining -> refute_watch(drain(pid), watch_id)
    end
  end

  defp refute_watch(events, watch_id) do
    refute Enum.any?(events, fn event ->
             event.wire["method"] == "fs/changed" and
               event.wire["params"]["watchId"] == watch_id
           end)
  end

  defp drain(pid) do
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.kind == :server_request or &1.wire["method"] == "error"))
    events
  end

  defp assert_no_model_requests(ctx), do: assert(ModelFixture.requests(ctx.fixture) == [])
end
