defmodule SamgitaCodexDriver.LegacyApprovalContractTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ScriptedTransport, Session}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.{Error, Wire}

  @methods ["applyPatchApproval", "execCommandApproval"]
  @conversation "67e55044-10b1-426f-9247-bb680e5fe0c8"
  @decisions [
    "approved",
    "approved_for_session",
    "approved_mcp_policy_amendment",
    "timed_out",
    "abort",
    %{"approved_execpolicy_amendment" => %{"proposed_execpolicy_amendment" => ["printf"]}},
    %{
      "network_policy_amendment" => %{
        "network_policy_amendment" => %{"action" => "allow", "host" => "fixture.invalid"}
      }
    },
    %{
      "network_policy_amendment" => %{
        "network_policy_amendment" => %{"action" => "deny", "host" => "fixture.invalid"}
      }
    },
    %{"denied" => %{"rejection" => "Synthetic rejection"}}
  ]

  test "synthetic legacy requests require explicit decisions and preserve every ReviewDecision" do
    for experimental <- [false, true], method <- @methods do
      pid = ready(experimental)

      for {decision, index} <- Enum.with_index(@decisions) do
        id = if rem(index, 2) == 0, do: index, else: Integer.to_string(index)
        wire = request(method, id)
        assert {:ok, encoded} = Wire.encode(wire)
        assert {:ok, ^wire} = Wire.decode(encoded)
        handle = incoming(pid, wire)
        assert Session.status(pid).interactions == 1
        refute_receive {:sent, ^pid, %{"id" => ^id, "result" => _}}, 0

        result = %{"decision" => decision}
        assert :ok = Session.respond(pid, handle, {:ok, result})
        assert_receive {:sent, ^pid, %{"id" => ^id, "result" => ^result}}, 2_000
        assert [outcome] = Session.interaction_outcomes(pid)
        assert outcome.thread_id == @conversation
        assert :ok = Session.acknowledge_interaction_outcome(pid, handle)

        assert {:error, %Error{code: :stale_interaction}} =
                 Session.respond(pid, handle, {:ok, result})

        refute_receive {:sent, ^pid, %{"id" => ^id, "result" => _}}, 0
      end

      assert :ok = Session.close(pid)
    end
  end

  test "synthetic legacy optional fields retain omitted, null and present values" do
    pid = ready(false)

    for method <- @methods, presence <- [:omitted, nil, :present] do
      id = "#{method}-#{inspect(presence)}"
      field = if method == "execCommandApproval", do: "approvalId", else: "grantRoot"
      present = if method == "execCommandApproval", do: "synthetic-approval", else: "/synthetic"
      wire = request(method, id)

      params =
        if presence == :omitted,
          do: Map.delete(wire["params"], field),
          else: Map.put(wire["params"], field, if(presence == :present, do: present, else: nil))

      wire = Map.put(wire, "params", params)
      handle = incoming(pid, wire)
      assert :ok = Session.respond(pid, handle, {:ok, %{"decision" => "abort"}})
      assert_receive {:sent, ^pid, %{"id" => ^id, "result" => %{"decision" => "abort"}}}
      assert :ok = Session.acknowledge_interaction_outcome(pid, handle)
    end
  end

  test "synthetic invalid legacy decisions leave the request pending for a valid explicit reply" do
    pid = ready(true)

    for method <- @methods do
      handle = incoming(pid, request(method, method))

      for decision <- [
            "accept",
            "decline",
            %{"denied" => %{}},
            %{
              "network_policy_amendment" => %{
                "network_policy_amendment" => %{
                  "host" => "fixture.invalid",
                  "action" => "execute"
                }
              }
            }
          ] do
        assert {:error, %Error{code: :schema_violation}} =
                 Session.respond(pid, handle, {:ok, %{"decision" => decision}})

        assert Session.status(pid).interactions == 1
        refute_receive {:sent, ^pid, %{"id" => ^method, "result" => _}}, 0
      end

      result = %{"decision" => %{"denied" => %{"rejection" => "Explicit synthetic denial"}}}
      assert :ok = Session.respond(pid, handle, {:ok, result})
      assert_receive {:sent, ^pid, %{"id" => ^method, "result" => ^result}}
    end
  end

  test "synthetic legacy approval handles cannot authorize a reused ID after reconnect" do
    for method <- @methods do
      pid = ready(false)
      wire = request(method, "same-id")
      previous = incoming(pid, wire)
      send(pid, :drop_connection)
      assert %{phase: :disconnected, interactions: 0} = Session.status(pid)
      assert :ok = Session.reconnect(pid)
      assert_receive {:transport_opened, ^pid}
      initialize(pid, false)
      current = incoming(pid, wire)
      refute current == previous

      assert {:error, %Error{code: :stale_interaction}} =
               Session.respond(pid, previous, {:ok, %{"decision" => "approved"}})

      assert Session.status(pid).interactions == 1
      refute_receive {:sent, ^pid, %{"id" => "same-id", "result" => _}}, 0
      assert :ok = Session.respond(pid, current, {:ok, %{"decision" => "abort"}})
      assert_receive {:sent, ^pid, %{"id" => "same-id", "result" => %{"decision" => "abort"}}}
      assert :ok = Session.close(pid)
    end
  end

  for experimental <- [false, true] do
    @tag :real_codex
    @tag timeout: 30_000
    test "pinned binary rejects removed legacy turn methods with experimentalApi=#{experimental}" do
      binary = System.get_env("CODEX_BINARY")

      assert is_binary(binary) and File.regular?(binary),
             "BLOCKED_ENV: CODEX_BINARY must select the immutable pinned executable"

      dir =
        Path.join(
          System.tmp_dir!(),
          "samgita-legacy-rejection-#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      {:ok, state} =
        Stdio.open(
          executable: binary,
          args: ["app-server", "--listen", "stdio://"],
          cwd: dir,
          env: %{"HOME" => dir, "CODEX_HOME" => dir, "CODEX_DISABLE_REMOTE_CONTROL" => "1"}
        )

      on_exit(fn -> assert :ok = Stdio.close(state) end)

      {response, state} =
        raw_call(state, "init", "initialize", %{
          "clientInfo" => %{"name" => "samgita_legacy_rejection", "version" => "0.1.0"},
          "capabilities" => %{"experimentalApi" => unquote(experimental)}
        })

      assert %{"result" => %{"userAgent" => _}} = response
      {:ok, state} = Stdio.send(state, JSON.encode!(%{"method" => "initialized"}))

      state =
        Enum.reduce(["sendUserTurn", "sendUserMessage"], state, fn method, state ->
          {response, state} = raw_call(state, method, method, %{})

          assert %{"id" => ^method, "error" => %{"code" => -32_600, "message" => message}} =
                   response

          assert message =~ "unknown variant"
          assert message =~ method
          refute Map.has_key?(response, "result")
          state
        end)

      # A rejection leaves the same real connection initialized and usable.
      {response, state} = raw_call(state, "after-rejection", "thread/list", %{})
      assert %{"result" => %{"data" => data}} = response
      assert is_list(data)
      assert :ok = Stdio.close(state)
    end
  end

  defp ready(experimental) do
    {:ok, pid} = Session.start_link(transport: {ScriptedTransport, observer: self()})
    assert_receive {:transport_opened, ^pid}
    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    initialize(pid, experimental)
    pid
  end

  defp initialize(pid, experimental) do
    task =
      Task.async(fn ->
        Session.initialize(pid, %{"name" => "legacy_contract", "version" => "0.1.0"}, %{
          "experimentalApi" => experimental
        })
      end)

    assert_receive {:sent, ^pid, %{"method" => "initialize", "id" => id}}, 2_000

    send(
      pid,
      {:incoming,
       %{
         "id" => id,
         "result" => %{
           "userAgent" => "synthetic",
           "codexHome" => "/isolated",
           "platformFamily" => "unix",
           "platformOs" => "linux"
         }
       }}
    )

    assert {:ok, _} = Task.await(task)
    assert_receive {:sent, ^pid, %{"method" => "initialized"}}
  end

  defp incoming(pid, wire) do
    send(pid, {:incoming, wire})
    assert_receive {:codex_driver, ^pid, :events_available}, 2_000
    assert {:ok, [%{kind: :server_request, wire: ^wire, handle: handle}]} = Session.drain(pid)
    handle
  end

  defp request(method, id) do
    common = %{"conversationId" => @conversation, "callId" => "synthetic-call", "reason" => nil}

    params =
      case method do
        "applyPatchApproval" ->
          Map.merge(common, %{
            "grantRoot" => nil,
            "fileChanges" => %{
              "/synthetic/add.txt" => %{"type" => "add", "content" => "synthetic\n"},
              "/synthetic/delete.txt" => %{"type" => "delete", "content" => "previous\n"},
              "/synthetic/update.txt" => %{
                "type" => "update",
                "unified_diff" => "@@ -1 +1 @@\n-old\n+new",
                "move_path" => "/synthetic/moved.txt"
              }
            }
          })

        "execCommandApproval" ->
          Map.merge(common, %{
            "approvalId" => nil,
            "command" => ["printf", "synthetic"],
            "cwd" => "/synthetic",
            "parsedCmd" => [
              %{
                "type" => "read",
                "cmd" => "cat input.txt",
                "name" => "cat",
                "path" => "/synthetic/input.txt"
              },
              %{"type" => "list_files", "cmd" => "ls", "path" => nil},
              %{
                "type" => "search",
                "cmd" => "rg synthetic",
                "query" => "synthetic",
                "path" => "/synthetic"
              },
              %{"type" => "unknown", "cmd" => "printf synthetic"}
            ]
          })
      end

    %{"id" => id, "method" => method, "params" => params}
  end

  defp raw_call(state, id, method, params) do
    {:ok, state} =
      Stdio.send(state, JSON.encode!(%{"id" => id, "method" => method, "params" => params}))

    raw_reply(state, id, System.monotonic_time(:millisecond) + 10_000)
  end

  defp raw_reply(state, id, deadline) do
    receive do
      message ->
        case Stdio.handle_info(message, state) do
          {:ok, events, state} ->
            refute Enum.any?(events, &match?({:closed, _}, &1)),
                   "Codex closed before its response"

            response =
              Enum.find_value(events, fn
                {:message, body} ->
                  decoded = JSON.decode!(body)
                  if decoded["id"] == id, do: decoded

                _ ->
                  nil
              end)

            if response, do: {response, state}, else: raw_reply(state, id, deadline)

          :unknown ->
            raw_reply(state, id, deadline)

          other ->
            flunk("Unexpected raw transport result: #{inspect(other)}")
        end
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        flunk("Pinned Codex response deadline")
    end
  end
end
