defmodule Samgita.CodexHosts do
  @moduledoc """
  Operator-configured Codex app-server hosts (design §11).

  Configuration is durable and versioned; only credential reference names are
  stored. Live connection state belongs to `Samgita.CodexHosts.Runtime` and is
  evidence of reachability, never of Task progress or completion.
  """
  import Ecto.Query
  import Ecto.Changeset
  alias Samgita.{Commands, Error, Events, Params, Principal, Projection, Repo}
  alias Samgita.CodexHosts.Runtime
  alias SamgitaCodexDriver.Session
  alias Samgita.Domain.{Agent, CodexHost}

  @websocket_fields ~w(url connect_address token_ref allow_insecure)a
  @ssh_fields ~w(ssh_user ssh_host ssh_port ssh_key_ref known_hosts remote_codex_path remote_socket_path ensure_daemon use_ssh_config)a
  @ssh_host ~r/\A[A-Za-z0-9][A-Za-z0-9.:-]{0,252}\z/
  @ssh_user ~r/\A[A-Za-z_][A-Za-z0-9_.-]{0,31}\z/
  @remote_path ~r/\A[A-Za-z0-9_.\/~+-]{1,512}\z/
  @secret_keys ~w(token password secret private_key key passphrase authorization)
  @reference ~r/\A[A-Za-z0-9][A-Za-z0-9._:\/-]{0,199}\z/
  @projection ~w(id agent_id installation_id machine_name transport url connect_address token_ref allow_insecure ssh_user ssh_host ssh_port ssh_key_ref known_hosts remote_codex_path remote_socket_path ensure_daemon use_ssh_config enabled generation server_version last_connected_at version inserted_at updated_at)a

  def list(principal) do
    with :ok <- operator(principal) do
      rows =
        Repo.all(
          from h in CodexHost,
            join: a in Agent,
            on: a.id == h.agent_id,
            order_by: [asc: h.inserted_at, asc: h.id],
            select: {h, a.name}
        )

      names = Map.new(rows, fn {host, name} -> {host.id, name} end)

      {:ok,
       Enum.map(rows, fn {host, name} ->
         same = for {other, _} <- rows, same_machine?(host, other), do: names[other.id]

         host
         |> projection()
         |> Map.put("agent_name", name)
         |> Map.put("same_machine_as", same)
       end)}
    end
  end

  def get(principal, id) do
    with :ok <- operator(principal),
         %CodexHost{} = host <- fetch(id) do
      {:ok, projection(host)}
    else
      nil -> {:error, Error.new(:not_found)}
      error -> error
    end
  end

  def for_agent(principal, agent_id) do
    with :ok <- operator(principal) do
      host = Params.uuid?(agent_id) && Repo.get_by(CodexHost, agent_id: agent_id)
      {:ok, host && projection(host)}
    end
  end

  @doc "Create or update the host configuration of one Codex Agent. New hosts start disabled."
  def configure(principal, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      nil,
      attrs,
      [operation: "codex_host.configure", agent_ids: [attrs["agent_id"]]],
      fn ctx ->
        Commands.operator!(principal)
        if Enum.any?(@secret_keys, &Map.has_key?(attrs, &1)), do: Commands.fail!(:invalid)
        if !Params.uuid?(attrs["agent_id"]), do: Commands.fail!(:invalid, %{field: "agent_id"})

        agent = Repo.get(Agent, attrs["agent_id"]) || Commands.fail!(:not_found)
        if agent.runtime_driver != "codex", do: Commands.fail!(:invalid, %{field: "agent_id"})

        existing =
          Repo.one(from h in CodexHost, where: h.agent_id == ^agent.id, lock: "FOR UPDATE")

        {host, previous} =
          case existing do
            nil ->
              {%CodexHost{agent_id: agent.id} |> settings(attrs) |> Commands.insert!(), nil}

            host ->
              Commands.expect!(host, attrs)

              {host |> settings(attrs) |> change(version: host.version + 1) |> Commands.update!(),
               host}
          end

        audit!(ctx, host, "codex_host.configured", previous)
        projection(host)
      end
    )
    |> after_commit()
  end

  @doc """
  The projects Codex reports on this host (its `project/list`). Codex owns them;
  Samgita keeps no copy. Requires a connected host.
  """
  def projects(principal, id) do
    with :ok <- operator(principal),
         {:ok, session} <- live_session(id) do
      list_projects(session, nil, [])
    end
  end

  @doc """
  Add a project to Codex on this host (`project/create`). The command ID is the
  idempotency key, so a retry cannot create a second project.
  """
  def create_project(principal, id, attrs) do
    attrs = Params.strings(attrs)
    name = String.trim(attrs["name"] || "")
    path = String.trim(attrs["path"] || "")

    with :ok <- operator(principal),
         :ok <- validate_project(attrs["command_id"], name, path),
         {:ok, session} <- live_session(id),
         {:ok, %{"result" => %{"project" => created}}} <-
           codex_request(session, "project/create", %{
             "idempotencyKey" => attrs["command_id"],
             "name" => name,
             "roots" => [%{"path" => path}]
           }) do
      project = project(created)

      system(id, fn ctx, host ->
        Events.append!(nil, "codex_host.project_created", ctx, "codex_host", host.id, %{
          "agent_id" => host.agent_id,
          "project_id" => project["id"],
          "name" => project["name"]
        })
      end)

      {:ok, project}
    else
      {:ok, _} -> {:error, Error.new(:codex_request_failed)}
      error -> error
    end
  end

  @doc """
  List the folders in one directory on the Codex machine (`fs/readDirectory`),
  for choosing a project folder. Visible folders first, then hidden ones.
  """
  def read_directory(principal, id, path) do
    path = String.trim(path || "")

    with :ok <- operator(principal),
         :ok <- absolute_path(path),
         {:ok, session} <- live_session(id),
         {:ok, %{"result" => %{"entries" => entries}}} when is_list(entries) <-
           codex_request(session, "fs/readDirectory", %{"path" => path}) do
      folders =
        for %{"fileName" => name, "isDirectory" => true} <- entries, is_binary(name), do: name

      {hidden, visible} = Enum.split_with(folders, &String.starts_with?(&1, "."))
      {:ok, Enum.sort_by(visible, &String.downcase/1) ++ Enum.sort_by(hidden, &String.downcase/1)}
    else
      {:ok, _} -> {:error, Error.new(:codex_request_failed)}
      error -> error
    end
  end

  @doc """
  Folders and files in one directory on the Codex machine (`fs/readDirectory`),
  folders first, hidden entries last. Used to reference files in a message.
  """
  def list_entries(principal, id, path) do
    path = String.trim(path || "")

    with :ok <- operator(principal),
         :ok <- absolute_path(path),
         {:ok, session} <- live_session(id),
         {:ok, %{"result" => %{"entries" => entries}}} when is_list(entries) <-
           codex_request(session, "fs/readDirectory", %{"path" => path}) do
      entries =
        for %{"fileName" => name} = entry <- entries, is_binary(name) do
          %{
            "name" => name,
            "path" => Path.join(path, name),
            "dir" => entry["isDirectory"] == true
          }
        end

      {:ok,
       Enum.sort_by(entries, fn e ->
         {String.starts_with?(e["name"], "."), not e["dir"], String.downcase(e["name"])}
       end)}
    else
      {:ok, _} -> {:error, Error.new(:codex_request_failed)}
      error -> error
    end
  end

  @doc """
  Plugins installed in Codex on this host, as mention targets
  (`plugin://<plugin-name>@<marketplace-name>`, the plugin ID).
  """
  def plugins(principal, id, cwd) do
    with :ok <- operator(principal),
         {:ok, session} <- live_session(id),
         {:ok, %{"result" => %{"marketplaces" => markets}}} when is_list(markets) <-
           codex_request(session, "plugin/installed", %{"cwds" => List.wrap(cwd)}, 20_000) do
      {:ok,
       for market <- markets,
           %{"id" => plugin_id} = plugin <- List.wrap(market["plugins"]),
           plugin["installed"] == true and plugin["enabled"] == true do
         interface = plugin["interface"] || %{}

         %{
           "name" => interface["displayName"] || plugin["name"],
           "description" => interface["shortDescription"],
           "path" => "plugin://" <> plugin_id
         }
       end}
    else
      {:ok, _} -> {:error, Error.new(:codex_request_failed)}
      error -> error
    end
  end

  @doc "Enabled skills Codex finds for a working directory (`skills/list`)."
  def skills(principal, id, cwd) do
    with :ok <- operator(principal),
         {:ok, session} <- live_session(id),
         {:ok, %{"result" => %{"data" => entries}}} when is_list(entries) <-
           codex_request(session, "skills/list", %{"cwds" => List.wrap(cwd)}, 20_000) do
      {:ok,
       for entry <- entries,
           %{"name" => name, "path" => path} = skill <- List.wrap(entry["skills"]),
           skill["enabled"] == true do
         %{"name" => name, "description" => skill["description"], "path" => path}
       end
       |> Enum.uniq_by(& &1["path"])}
    else
      {:ok, _} -> {:error, Error.new(:codex_request_failed)}
      error -> error
    end
  end

  @doc "Set the goal Codex keeps pursuing in a session (`thread/goal/set`)."
  def set_goal(principal, id, thread_id, objective) do
    objective = String.trim(objective || "")

    with :ok <- operator(principal),
         :ok <- thread_id!(thread_id),
         :ok <-
           if(objective != "" and byte_size(objective) <= 4_000,
             do: :ok,
             else: {:error, Error.new(:invalid, %{fields: [:objective]})}
           ),
         {:ok, session} <- live_session(id),
         {:ok, %{"result" => %{"goal" => goal}}} <-
           codex_request(session, "thread/goal/set", %{
             "threadId" => thread_id,
             "objective" => objective,
             # Set by the operator in the browser, an explicit user action.
             "origin" => "user"
           }) do
      {:ok, goal(goal)}
    else
      {:ok, _} -> {:error, Error.new(:codex_request_failed)}
      error -> error
    end
  end

  @doc "The session's current goal, or nil (`thread/goal/get`)."
  def goal(principal, id, thread_id) do
    with :ok <- operator(principal),
         :ok <- thread_id!(thread_id),
         {:ok, session} <- live_session(id),
         {:ok, %{"result" => result}} <-
           codex_request(session, "thread/goal/get", %{"threadId" => thread_id}) do
      {:ok, goal(result["goal"])}
    else
      {:ok, _} -> {:error, Error.new(:codex_request_failed)}
      error -> error
    end
  end

  @doc "Remove the session's goal (`thread/goal/clear`)."
  def clear_goal(principal, id, thread_id) do
    with :ok <- operator(principal),
         :ok <- thread_id!(thread_id),
         {:ok, session} <- live_session(id),
         {:ok, _} <-
           codex_request(session, "thread/goal/clear", %{
             "threadId" => thread_id,
             "origin" => "user"
           }) do
      :ok
    end
  end

  defp goal(%{"objective" => objective} = goal),
    do: %{"objective" => objective, "status" => goal["status"]}

  defp goal(_), do: nil

  @doc "The user's home folder on a connected Codex machine, when Codex reported it."
  def home(id), do: Runtime.status(id)["home"]

  defp absolute_path(path) do
    if Path.type(path) == :absolute and byte_size(path) <= 4096 and
         not String.contains?(path, <<0>>),
       do: :ok,
       else: {:error, Error.new(:invalid, %{fields: [:path]})}
  end

  @doc """
  Recent Codex sessions (threads) of one project on this host, newest first.
  Codex leaves `projectId` unset on most threads, so sessions are matched by
  their working directory against the project's folders (`thread/list` `cwd`).
  """
  def sessions(principal, id, roots) do
    roots = Enum.filter(List.wrap(roots), &(is_binary(&1) and Path.type(&1) == :absolute))

    with :ok <- operator(principal),
         :ok <-
           if(roots == [], do: {:error, Error.new(:invalid, %{fields: [:roots]})}, else: :ok),
         {:ok, session} <- live_session(id),
         {:ok, %{"result" => %{"data" => threads}}} when is_list(threads) <-
           codex_request(session, "thread/list", %{
             "cwd" => roots,
             "limit" => 50,
             "sortKey" => "updated_at",
             "useStateDbOnly" => true
           }) do
      {:ok, Enum.map(threads, &thread/1)}
    else
      {:ok, _} -> {:error, Error.new(:codex_request_failed)}
      error -> error
    end
  end

  # Interactive sessions use the Codex desktop app defaults: Codex may write in
  # the project folder and asks before anything else.
  @session_settings %{"approvalPolicy" => "on-request", "sandbox" => "workspace-write"}
  @decisions ~w(accept acceptForSession decline cancel)

  @doc "Start a new Codex session (thread) in a folder on this host."
  def start_thread(principal, id, cwd) do
    with :ok <- operator(principal),
         :ok <- absolute_path(cwd || ""),
         {:ok, session} <- live_session(id),
         {:ok, %{"result" => %{"thread" => thread} = result}} <-
           codex_request(session, "thread/start", Map.put(@session_settings, "cwd", cwd)) do
      {:ok, thread |> thread() |> Map.put("settings", settings_of(result))}
    else
      {:ok, _} -> {:error, Error.new(:codex_request_failed)}
      error -> error
    end
  end

  @doc """
  Continue an existing session: `thread/resume` returns its turns and subscribes
  this host connection to the thread's live events.
  """
  def resume_thread(principal, id, thread_id) do
    with :ok <- operator(principal),
         :ok <- thread_id!(thread_id),
         {:ok, session} <- live_session(id),
         {:ok, %{"result" => %{"thread" => thread} = result}} <-
           codex_request(
             session,
             "thread/resume",
             Map.put(@session_settings, "threadId", thread_id),
             60_000
           ) do
      {:ok,
       thread
       |> thread()
       |> Map.put("turns", List.wrap(thread["turns"]))
       |> Map.put("settings", settings_of(result))}
    else
      {:ok, _} -> {:error, Error.new(:codex_request_failed)}
      error -> error
    end
  end

  # Access modes of the Codex app: sandbox plus when Codex asks for approval.
  @access %{
    "read_only" => {%{"type" => "readOnly"}, "on-request"},
    "default" => {%{"type" => "workspaceWrite"}, "on-request"},
    "full" => {%{"type" => "dangerFullAccess"}, "never"}
  }
  @model_pages 10
  @setting_value ~r/\A[A-Za-z0-9][A-Za-z0-9._:\/-]{0,199}\z/

  @doc "The access mode (`read_only`, `default`, `full`) of a sandbox type Codex reports."
  def access_mode("readOnly"), do: "read_only"
  def access_mode("dangerFullAccess"), do: "full"
  def access_mode(_), do: "default"

  @doc """
  The models Codex offers on this host for the picker (`model/list`), with the
  reasoning efforts each supports.
  """
  def models(principal, id) do
    with :ok <- operator(principal),
         {:ok, session} <- live_session(id) do
      list_models(session, nil, [], 0)
    end
  end

  defp list_models(session, cursor, acc, page) do
    params = if cursor, do: %{"cursor" => cursor}, else: %{}

    case codex_request(session, "model/list", params) do
      {:ok, %{"result" => %{"data" => data} = result}} ->
        acc = acc ++ for(m <- data, m["hidden"] != true, do: model(m))

        if is_binary(result["nextCursor"]) and page < @model_pages,
          do: list_models(session, result["nextCursor"], acc, page + 1),
          else: {:ok, acc}

      {:ok, _} ->
        {:error, Error.new(:codex_request_failed)}

      error ->
        error
    end
  end

  defp model(m),
    do: %{
      "id" => m["model"] || m["id"],
      "name" => m["displayName"] || m["model"],
      "default" => m["isDefault"] == true,
      "default_effort" => m["defaultReasoningEffort"],
      "efforts" =>
        for(%{"reasoningEffort" => e} <- List.wrap(m["supportedReasoningEfforts"]), do: e)
    }

  @doc """
  Send a user message. Without a running turn it starts a new turn, applying
  `settings` (`"model"`, `"effort"`, `"access"`) to it and later turns, as the
  Codex app does; while a turn runs the message steers it and settings wait.
  """
  def send_message(
        principal,
        id,
        thread_id,
        text,
        running_turn \\ nil,
        settings \\ %{},
        attachments \\ []
      ) do
    text = String.trim(text || "")

    with :ok <- operator(principal),
         :ok <- thread_id!(thread_id),
         :ok <-
           if(text != "" and byte_size(text) <= 100_000,
             do: :ok,
             else: {:error, Error.new(:invalid, %{fields: [:message]})}
           ),
         {:ok, overrides} <- turn_overrides(settings),
         {:ok, extra} <- attachment_inputs(attachments),
         input = [%{"type" => "text", "text" => text} | extra],
         {:ok, session} <- live_session(id),
         {:ok, turn_id} <- start_or_steer(session, thread_id, input, running_turn, overrides) do
      {:ok, turn_id}
    else
      {:ok, _} -> {:error, Error.new(:codex_request_failed)}
      error -> error
    end
  end

  # A message sent while a turn runs joins that turn (`turn/steer`), as in the
  # Codex app; otherwise it starts a new turn.
  defp turn_overrides(settings) do
    Enum.reduce_while(settings || %{}, {:ok, %{}}, fn
      {"access", mode}, {:ok, acc} when is_map_key(@access, mode) ->
        {sandbox, approval} = @access[mode]

        {:cont,
         {:ok, Map.merge(acc, %{"sandboxPolicy" => sandbox, "approvalPolicy" => approval})}}

      # Plan mode (Codex collaboration mode) for this and later turns. It takes
      # precedence over model and effort, so it carries them; `null`
      # instructions select Codex's built-in ones for the mode.
      {"mode", %{"mode" => mode, "model" => model} = m}, {:ok, acc}
      when mode in ["plan", "default"] and is_binary(model) ->
        if model =~ @setting_value and (is_nil(m["effort"]) or m["effort"] =~ @setting_value),
          do:
            {:cont,
             {:ok,
              Map.put(acc, "collaborationMode", %{
                "mode" => mode,
                "settings" => %{
                  "model" => model,
                  "reasoning_effort" => m["effort"],
                  "developer_instructions" => nil
                }
              })}},
          else: {:halt, {:error, Error.new(:invalid, %{fields: [:mode]})}}

      {key, value}, {:ok, acc} when key in ["model", "effort"] and is_binary(value) ->
        if value =~ @setting_value,
          do: {:cont, {:ok, Map.put(acc, key, value)}},
          else: {:halt, {:error, Error.new(:invalid, %{fields: [String.to_atom(key)]})}}

      {key, _}, _ ->
        {:halt, {:error, Error.new(:invalid, %{fields: [key]})}}
    end)
  end

  # Plugins are mentioned by ID (`plugin://name@marketplace`), skills by the
  # absolute path of their SKILL.md, as in the Codex app.
  defp attachment_inputs(attachments) do
    Enum.reduce_while(List.wrap(attachments), {:ok, []}, fn
      %{"type" => "mention", "name" => name, "path" => "plugin://" <> plugin = path}, {:ok, acc}
      when is_binary(name) and byte_size(name) in 1..200 ->
        if plugin =~ ~r/\A[A-Za-z0-9][A-Za-z0-9._@:-]{0,199}\z/,
          do: {:cont, {:ok, acc ++ [%{"type" => "mention", "name" => name, "path" => path}]}},
          else: {:halt, {:error, Error.new(:invalid, %{fields: [:attachments]})}}

      %{"type" => "skill", "name" => name, "path" => path}, {:ok, acc}
      when is_binary(name) and byte_size(name) in 1..200 and is_binary(path) ->
        if absolute_path(path) == :ok and Path.basename(path) == "SKILL.md",
          do: {:cont, {:ok, acc ++ [%{"type" => "skill", "name" => name, "path" => path}]}},
          else: {:halt, {:error, Error.new(:invalid, %{fields: [:attachments]})}}

      _, _ ->
        {:halt, {:error, Error.new(:invalid, %{fields: [:attachments]})}}
    end)
  end

  defp start_or_steer(session, thread_id, input, nil, overrides) do
    case codex_request(
           session,
           "turn/start",
           Map.merge(overrides, %{"threadId" => thread_id, "input" => input})
         ) do
      {:ok, %{"result" => %{"turn" => %{"id" => turn_id}}}} -> {:ok, turn_id}
      {:ok, _} -> {:error, Error.new(:codex_request_failed)}
      error -> error
    end
  end

  defp start_or_steer(session, thread_id, input, running_turn, _overrides) do
    case codex_request(session, "turn/steer", %{
           "threadId" => thread_id,
           "expectedTurnId" => running_turn,
           "input" => input
         }) do
      {:ok, %{"result" => %{"turnId" => turn_id}}} -> {:ok, turn_id}
      {:ok, _} -> {:error, Error.new(:codex_request_failed)}
      error -> error
    end
  end

  @doc "Stop the running turn."
  def interrupt(principal, id, thread_id, turn_id) do
    with :ok <- operator(principal),
         :ok <- thread_id!(thread_id),
         :ok <- thread_id!(turn_id),
         {:ok, session} <- live_session(id),
         {:ok, _} <-
           codex_request(session, "turn/interrupt", %{
             "threadId" => thread_id,
             "turnId" => turn_id
           }) do
      :ok
    end
  end

  @doc "Approval requests Codex is waiting on for this session."
  def pending_requests(principal, id, thread_id) do
    with :ok <- operator(principal),
         requests when is_list(requests) <-
           Runtime.call(id, &Samgita.CodexHosts.Connection.pending_requests(&1, thread_id)) do
      {:ok, requests}
    else
      {:error, _} -> {:ok, []}
      error -> error
    end
  end

  @doc "Answer an approval request with a Codex decision (accept, acceptForSession, decline, cancel)."
  def respond_request(principal, id, key, decision) do
    with :ok <- operator(principal),
         :ok <- if(decision in @decisions, do: :ok, else: {:error, Error.new(:invalid)}),
         :ok <-
           Runtime.call(
             id,
             &Samgita.CodexHosts.Connection.respond(&1, key, {:ok, %{"decision" => decision}})
           ) do
      :ok
    else
      {:error, %Error{}} = error -> error
      {:error, _} -> {:error, Error.new(:codex_request_failed)}
    end
  end

  defp thread_id!(value) when is_binary(value) and byte_size(value) in 1..200, do: :ok
  defp thread_id!(_), do: {:error, Error.new(:invalid)}

  # The effective session settings Codex reports for a started or resumed thread.
  defp settings_of(result),
    do: %{
      "model" => result["model"],
      "reasoning_effort" => result["reasoningEffort"],
      "sandbox" => get_in(result, ["sandbox", "type"]),
      "approval_policy" => result["approvalPolicy"],
      # Experimental: plan or default collaboration mode, when reported.
      "mode" => get_in(result, ["collaborationMode", "mode"])
    }

  defp thread(t) when is_map(t) do
    title =
      case {t["name"], to_string(t["preview"])} do
        {name, _} when is_binary(name) and name != "" -> name
        {_, ""} -> nil
        {_, preview} -> String.slice(preview, 0, 120)
      end

    %{
      "id" => t["id"],
      "title" => title,
      "status" => get_in(t, ["status", "type"]),
      "cwd" => t["cwd"],
      "updated_at" => t["updatedAt"]
    }
  end

  @project_pages 10

  defp list_projects(session, cursor, acc) do
    params = if cursor, do: %{"limit" => 100, "cursor" => cursor}, else: %{"limit" => 100}

    case codex_request(session, "project/list", params) do
      {:ok, %{"result" => %{"data" => data} = result}} when is_list(data) ->
        acc = acc ++ Enum.map(data, &project/1)
        next = result["nextCursor"]

        if is_binary(next) and length(acc) < 100 * @project_pages,
          do: list_projects(session, next, acc),
          else: {:ok, acc}

      {:ok, _} ->
        {:error, Error.new(:codex_request_failed)}

      error ->
        error
    end
  end

  defp project(p) when is_map(p),
    do: %{
      "id" => p["id"],
      "name" => p["name"],
      "roots" => for(%{"path" => path} <- List.wrap(p["roots"]), is_binary(path), do: path),
      "updated_at" => p["updatedAt"]
    }

  defp validate_project(command_id, name, path) do
    cond do
      !Params.uuid?(command_id) ->
        {:error, Error.new(:invalid, %{fields: [:command_id]})}

      name == "" or byte_size(name) > 200 ->
        {:error, Error.new(:invalid, %{fields: [:name]})}

      Path.type(path) != :absolute or byte_size(path) > 4096 or String.contains?(path, <<0>>) ->
        {:error, Error.new(:invalid, %{fields: [:path]})}

      true ->
        :ok
    end
  end

  defp live_session(id) do
    case fetch(id) && Runtime.session(id) do
      nil -> {:error, Error.new(:codex_unavailable)}
      false -> {:error, Error.new(:not_found)}
      session -> {:ok, session}
    end
  end

  defp codex_request(session, method, params, timeout \\ 15_000) do
    case Session.request(session, method, params, timeout_ms: timeout) do
      {:ok, %{"result" => _} = wire} -> {:ok, wire}
      _ -> {:error, Error.new(:codex_request_failed)}
    end
  catch
    :exit, _ -> {:error, Error.new(:codex_unavailable)}
  end

  @doc """
  Before adding a WebSocket host, connect to it once and report the Codex
  machine that answers, plus already configured Agents on the same machine
  (same Codex installation) or the same address. One machine should be one
  Agent; callers warn rather than create a duplicate silently.
  """
  def check_new(principal, attrs) do
    attrs = Params.strings(attrs)

    with :ok <- operator(principal),
         :ok <- validate_settings(attrs) do
      host = %CodexHost{} |> settings(attrs) |> apply_changes()

      identity =
        case probe(host) do
          {:ok, identity} -> identity
          _ -> %{installation_id: nil, machine_name: nil}
        end

      address =
        case host.transport do
          "ssh" -> dynamic([h], h.ssh_host == ^host.ssh_host)
          "local" -> dynamic([h], h.transport == "local")
          _ -> dynamic([h], h.url == ^host.url)
        end

      same =
        case identity.installation_id do
          nil -> address
          id -> dynamic([h], ^address or h.installation_id == ^id)
        end

      existing =
        Repo.all(
          from h in CodexHost,
            join: a in Agent,
            on: a.id == h.agent_id,
            where: ^same,
            select: a.name
        )

      {:ok,
       %{
         "reachable" => identity.installation_id != nil,
         "machine_name" => identity.machine_name,
         "same_machine_as" => existing
       }}
    end
  end

  @probe_timeout 8_000

  defp probe(host) do
    task =
      Task.Supervisor.async_nolink(Samgita.CodexHosts.ProbeSupervisor, fn ->
        Samgita.CodexHosts.Connection.identify(host)
      end)

    case Task.yield(task, @probe_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, identity}} -> {:ok, identity}
      _ -> {:error, :unreachable}
    end
  end

  defp same_machine?(host, other),
    do:
      other.id != host.id &&
        ((host.installation_id != nil && other.installation_id == host.installation_id) ||
           (host.url != nil && other.url == host.url) ||
           (host.ssh_host != nil && other.ssh_host == host.ssh_host) ||
           (host.transport == "local" && other.transport == "local"))

  @doc "Validate host settings without writing, so a caller can check them before creating an Agent."
  def validate_settings(attrs) do
    changeset = settings(%CodexHost{}, Params.strings(attrs))

    if changeset.valid?,
      do: :ok,
      else: {:error, Error.new(:invalid, %{fields: Keyword.keys(changeset.errors)})}
  end

  def enable(principal, id, attrs), do: set_enabled(principal, id, attrs, true)
  def disable(principal, id, attrs), do: set_enabled(principal, id, attrs, false)

  @doc "Ask a running connection to reconnect now. Runtime only; changes no durable state."
  def reconnect(principal, id) do
    with :ok <- operator(principal),
         %CodexHost{} = host <- fetch(id) do
      Runtime.reconnect(host.id)
    else
      nil -> {:error, Error.new(:not_found)}
      error -> error
    end
  end

  def status(id), do: Runtime.status(id)

  @doc false
  def enabled_ids,
    do: Repo.all(from h in CodexHost, where: h.enabled, order_by: h.id, select: h.id)

  @doc false
  def load(id), do: fetch(id)

  @doc false
  def record_connected(host_id, server_version, identity \\ %{}) do
    system(host_id, fn ctx, host ->
      host =
        host
        |> change(
          generation: host.generation + 1,
          server_version: server_version,
          installation_id: identity[:installation_id] || host.installation_id,
          machine_name: identity[:machine_name] || host.machine_name,
          last_connected_at: DateTime.utc_now()
        )
        |> Repo.update!()

      Events.append!(nil, "codex_host.connected", ctx, "codex_host", host.id, %{
        "agent_id" => host.agent_id,
        "generation" => host.generation,
        "server_version" => host.server_version
      })

      host
    end)
  end

  @doc false
  def record_disconnected(host_id, generation, reason) when is_atom(reason) do
    system(host_id, fn ctx, host ->
      Events.append!(nil, "codex_host.disconnected", ctx, "codex_host", host.id, %{
        "agent_id" => host.agent_id,
        "generation" => generation,
        "reason" => to_string(reason)
      })

      host
    end)
  end

  defp set_enabled(principal, id, attrs, enabled) do
    attrs = Params.strings(attrs)

    agent_id =
      Params.uuid?(id) && Repo.one(from h in CodexHost, where: h.id == ^id, select: h.agent_id)

    operation =
      if(enabled, do: "codex_host.enable:", else: "codex_host.disable:") <> to_string(id)

    Commands.run(
      principal,
      nil,
      attrs,
      [operation: operation, agent_ids: List.wrap(agent_id || [])],
      fn ctx ->
        Commands.operator!(principal)
        host = (agent_id && lock!(id)) || Commands.fail!(:not_found)
        Commands.expect!(host, attrs)

        if host.enabled == enabled do
          projection(host)
        else
          previous = host
          host = host |> change(enabled: enabled, version: host.version + 1) |> Commands.update!()
          type = if enabled, do: "codex_host.enabled", else: "codex_host.disabled"
          audit!(ctx, host, type, previous)
          projection(host)
        end
      end
    )
    |> after_commit()
  end

  # Supervisor changes happen only after the configuration commits.
  defp after_commit({:ok, %{"id" => id}} = result) do
    Runtime.sync(id)
    result
  end

  defp after_commit(result), do: result

  defp settings(host, attrs) do
    changeset =
      host
      |> cast(attrs, [:transport | @websocket_fields ++ @ssh_fields])
      |> validate_required([:transport])
      |> validate_inclusion(:transport, ["websocket", "ssh", "local"])

    # A host uses exactly one transport; the other transport's settings are cleared.
    case get_field(changeset, :transport) do
      "websocket" -> changeset |> clear(@ssh_fields) |> validate_websocket()
      "ssh" -> changeset |> clear(@websocket_fields) |> validate_ssh()
      # The Codex daemon of the machine Samgita runs on, through its control socket.
      "local" -> changeset |> clear(@websocket_fields) |> clear(@ssh_fields)
      _ -> changeset
    end
  end

  defp clear(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, acc ->
      default = if field in [:allow_insecure, :ensure_daemon, :use_ssh_config], do: false
      put_change(acc, field, default)
    end)
  end

  # With the operator's SSH configuration, OpenSSH resolves the host alias and
  # checks the host key against the operator's own known_hosts.
  defp validate_ssh(changeset) do
    required =
      if get_field(changeset, :use_ssh_config), do: [:ssh_host], else: [:ssh_host, :known_hosts]

    changeset
    |> validate_required(required)
    |> validate_format(:ssh_host, @ssh_host)
    |> validate_format(:ssh_user, @ssh_user)
    |> validate_number(:ssh_port, greater_than: 0, less_than: 65_536)
    |> validate_format(:ssh_key_ref, @reference)
    |> validate_format(:remote_codex_path, @remote_path)
    |> validate_format(:remote_socket_path, @remote_path)
    |> validate_change(:known_hosts, fn :known_hosts, value ->
      if valid_known_hosts?(value), do: [], else: [known_hosts: "invalid"]
    end)
  end

  # OpenSSH known_hosts lines: "<hosts> <key-type> <base64>" with no options or
  # control characters. Private keys are rejected by this shape check.
  defp valid_known_hosts?(value) when byte_size(value) in 1..16_384 do
    lines = value |> String.split("\n", trim: true) |> Enum.map(&String.trim/1)

    lines != [] and
      Enum.all?(lines, fn line ->
        line =~
          ~r/\A[^\s@#][^\s]* (ssh-[a-z0-9-]+|ecdsa-sha2-[a-z0-9-]+|sk-[a-z0-9@.-]+) [A-Za-z0-9+\/]+={0,2}( [^\x00-\x1f]*)?\z/
      end)
  end

  defp valid_known_hosts?(_), do: false

  defp validate_websocket(changeset) do
    changeset
    |> validate_required([:url])
    |> validate_change(:url, fn :url, url ->
      if valid_url?(url), do: [], else: [url: "invalid"]
    end)
    |> validate_change(:connect_address, fn :connect_address, address ->
      if match?({:ok, _}, :inet.parse_strict_address(String.to_charlist(address))),
        do: [],
        else: [connect_address: "invalid"]
    end)
    |> validate_format(:token_ref, @reference)
  end

  defp valid_url?(url) when byte_size(url) <= 2048 do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host, userinfo: nil, fragment: nil}}
      when scheme in ["ws", "wss"] and is_binary(host) and host != "" ->
        true

      _ ->
        false
    end
  end

  defp valid_url?(_), do: false

  defp audit!(ctx, host, type, previous) do
    Events.append!(
      nil,
      type,
      ctx,
      "codex_host",
      host.id,
      %{"agent_id" => host.agent_id, "transport" => host.transport},
      previous: previous,
      current: host
    )
  end

  defp system(host_id, callback) do
    agent_id = Repo.one(from h in CodexHost, where: h.id == ^host_id, select: h.agent_id)

    if agent_id do
      Commands.system(nil, [agent_id], fn ctx ->
        ctx =
          Map.merge(ctx, %{
            command_id: Ecto.UUID.generate(),
            source: "codex_host",
            source_actor: "codex_host:" <> host_id
          })

        callback.(ctx, lock!(host_id))
      end)
    else
      {:error, Error.new(:not_found)}
    end
  end

  defp lock!(id), do: Repo.one!(from h in CodexHost, where: h.id == ^id, lock: "FOR UPDATE")

  defp fetch(id), do: if(Params.uuid?(id), do: Repo.get(CodexHost, id))

  defp operator(%Principal{kind: :operator}), do: :ok
  defp operator(_), do: {:error, Error.new(:forbidden)}

  defp projection(host),
    do: host |> Projection.fields(@projection) |> Map.put("status", Runtime.status(host.id))
end
