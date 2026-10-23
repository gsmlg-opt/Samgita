defmodule SamgitaCodexDriver.Transport.Stdio do
  @moduledoc """
  Explicitly owned Codex process with bounded JSONL framing.

  `:executable`, `:args`, `:cwd` and `:env` configure the child. Only the environment
  names in `:inherit_env` are inherited (by default PATH and locale/temp/platform
  names, never HOME, CODEX_HOME, authentication variables or proxy credentials).
  Supply an isolated CODEX_HOME explicitly when needed. Python 3 is used solely
  to own the child process group and reap it when the session/port disappears.
  Child stderr is continuously discarded, never mixed into protocol output.
  """
  @behaviour SamgitaCodexDriver.Transport
  alias SamgitaCodexDriver.Transport.Stdio.Owner
  alias SamgitaProtocolCodex.Error
  @inherit ~w(PATH LANG LC_ALL LC_CTYPE TMPDIR TEMP TMP SystemRoot WINDIR)
  @default_limit 8_388_608

  @impl true
  def open(opts) do
    with {:ok, executable} <- executable(Keyword.get(opts, :executable)),
         {:ok, python} <- executable(Keyword.get(opts, :python, "python3")),
         {:ok, args} <- arguments(Keyword.get(opts, :args, [])),
         {:ok, environment} <- environment(opts),
         {:ok, cwd} <- directory(Keyword.get(opts, :cwd)),
         limit when is_integer(limit) and limit > 0 <-
           Keyword.get(opts, :max_message_bytes, @default_limit) do
      helper = Path.join(:code.priv_dir(:samgita_codex_driver), "stdio_owner.py")

      port_opts = [
        :binary,
        :exit_status,
        :use_stdio,
        :hide,
        {:args, [helper, executable | args]},
        {:env, environment}
      ]

      port_opts = if cwd, do: [{:cd, cwd} | port_opts], else: port_opts

      with {:ok, owner, port} <- Owner.open(python, port_opts) do
        {:ok, %{port: port, owner: owner, buffer: <<>>, max_message_bytes: limit, closed: false}}
      end
    else
      {:error, %Error{} = failure} -> {:error, failure}
      _ -> {:error, Error.new(:invalid_transport_options)}
    end
  rescue
    _ -> {:error, Error.new(:process_start_failed)}
  end

  @impl true
  def send(%{closed: true} = state, _json), do: {:error, Error.new(:transport_closed), state}

  def send(state, json) when is_binary(json) do
    cond do
      byte_size(json) > state.max_message_bytes ->
        {:error, Error.new(:message_too_large), state}

      String.contains?(json, ["\n", "\r", <<0>>]) ->
        {:error, Error.new(:invalid_jsonl_message), state}

      true ->
        if Port.command(state.port, [json, "\n"], [:nosuspend]),
          do: {:ok, state},
          else: {:error, Error.new(:transport_backpressure), state}
    end
  rescue
    _ -> {:error, Error.new(:transport_closed), %{state | closed: true}}
  end

  def send(state, _), do: {:error, Error.new(:invalid_jsonl_message), state}

  @impl true
  def handle_info({port, {:data, data}}, %{port: port, closed: false} = state) do
    case lines(state.buffer <> data, state.max_message_bytes, []) do
      {:ok, messages, buffer} ->
        {:ok, Enum.map(messages, &{:message, &1}), %{state | buffer: buffer}}

      :overflow ->
        closed_state = %{state | buffer: <<>>, closed: true}

        try do
          close(state)
          {:error, Error.new(:message_too_large), closed_state}
        rescue
          failure in Error -> {:error, failure, closed_state}
        end
    end
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    partial = byte_size(state.buffer) > 0

    {:ok, [{:closed, %{"exit_status" => status, "partial_message" => partial}}],
     %{state | closed: true, buffer: <<>>}}
  end

  def handle_info({:EXIT, port, _reason}, %{port: port} = state),
    do: {:ok, [{:closed, %{}}], %{state | closed: true, buffer: <<>>}}

  def handle_info(_, _), do: :unknown

  @impl true
  def close(%{owner: owner}), do: Owner.close(owner)

  @impl true
  def metadata(state),
    do: %{
      "transport" => "stdio",
      "owned_process" => true,
      "max_message_bytes" => state.max_message_bytes
    }

  defp lines(binary, limit, acc) do
    case :binary.match(binary, "\n") do
      {position, 1} when position <= limit + 1 ->
        <<line::binary-size(position), "\n", rest::binary>> = binary

        line =
          if String.ends_with?(line, "\r"),
            do: binary_part(line, 0, byte_size(line) - 1),
            else: line

        if byte_size(line) <= limit,
          do: lines(rest, limit, [line | acc]),
          else: :overflow

      :nomatch when byte_size(binary) <= limit + 1 ->
        # One extra CR may be the first byte of a CRLF terminator.
        if byte_size(binary) <= limit or String.ends_with?(binary, "\r"),
          do: {:ok, Enum.reverse(acc), binary},
          else: :overflow

      _ ->
        :overflow
    end
  end

  defp executable(name) when is_binary(name) and byte_size(name) > 0 do
    case System.find_executable(name) do
      nil -> {:error, Error.new(:executable_unavailable)}
      path -> {:ok, path}
    end
  end

  defp executable(_), do: {:error, Error.new(:invalid_transport_options)}

  defp arguments(args) when is_list(args) do
    if Enum.all?(args, &(is_binary(&1) and not String.contains?(&1, <<0>>))),
      do: {:ok, args},
      else: {:error, Error.new(:invalid_transport_options)}
  end

  defp arguments(_), do: {:error, Error.new(:invalid_transport_options)}
  defp directory(nil), do: {:ok, nil}

  defp directory(path) when is_binary(path),
    do:
      if(File.dir?(path),
        do: {:ok, path},
        else: {:error, Error.new(:invalid_working_directory)}
      )

  defp directory(_), do: {:error, Error.new(:invalid_working_directory)}

  defp environment(opts) do
    names = Keyword.get(opts, :inherit_env, @inherit)
    supplied = Keyword.get(opts, :env, %{})

    if is_list(names) and Enum.all?(names, &is_binary/1) and
         (is_map(supplied) or is_list(supplied)) do
      supplied = Map.new(supplied)

      supplied =
        if opts[:codex_home],
          do: Map.put(supplied, "CODEX_HOME", opts[:codex_home]),
          else: supplied

      selected_environment(names, supplied)
    else
      {:error, Error.new(:invalid_transport_options)}
    end
  end

  defp selected_environment(names, supplied) do
    if absolute_codex_home?(supplied["CODEX_HOME"]) and Enum.all?(supplied, &valid_env_entry?/1) do
      inherited = System.get_env()
      selected = inherited |> Map.take(names) |> Map.merge(supplied)
      keys = Map.keys(inherited) ++ Map.keys(selected)

      {:ok, for(key <- Enum.uniq(keys), do: {String.to_charlist(key), env_value(selected[key])})}
    else
      {:error, Error.new(:invalid_transport_options)}
    end
  end

  defp absolute_codex_home?(path), do: is_binary(path) and Path.type(path) == :absolute

  defp valid_env_entry?({key, value}),
    do:
      is_binary(key) and key != "" and not String.contains?(key, ["=", <<0>>]) and
        (is_nil(value) or (is_binary(value) and not String.contains?(value, <<0>>)))

  defp env_value(nil), do: false
  defp env_value(value), do: String.to_charlist(value)
end
