alias StandaloneCodex.Workflows

root =
  Path.join(
    System.tmp_dir!(),
    "standalone-ordinary-example-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
  )

File.mkdir!(root)

try do
  report =
    Workflows.run(
      System.get_env("CODEX_BINARY"),
      root,
      System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    )

  for {name, workflow} <- [completed: report.completed, interrupted: report.interrupted] do
    IO.puts(
      "#{name}: thread=#{workflow.thread} turn=#{workflow.turn} " <>
        "events=#{length(workflow.events)} tool_call=#{workflow.tool.wire["params"]["callId"]}"
    )
  end

  recovery = report.completed.recovery

  IO.puts(
    "Recovery: explicit generation #{recovery.before.generation} -> #{recovery.after.generation}; " <>
      "original history retained; model requests=#{length(report.completed.provider_after_recovery)}"
  )

  if Workflows.cleaned_up?(report) do
    File.rm_rf!(root)

    IO.puts(
      "Owned Sessions, native processes and provider Ports closed; disposable files removed."
    )

    IO.puts("Ordinary functional example completed. Full compatibility remains incomplete.")
  else
    raise "Cleanup unconfirmed; retain #{root}"
  end
rescue
  failure ->
    IO.puts(:stderr, "Example failed; disposable evidence retained at #{root}")
    reraise failure, __STACKTRACE__
end
