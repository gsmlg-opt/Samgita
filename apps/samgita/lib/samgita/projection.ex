defmodule Samgita.Projection do
  @moduledoc "Explicit public projections. Historical raw payloads and credential material are never serialized."
  def project(r) do
    fields(r, ~w(id name description state version inserted_at updated_at)a)
    |> Map.put(
      "git_url",
      if(Samgita.Repositories.normalize(r.git_url) == :invalid, do: nil, else: r.git_url)
    )
  end

  def agent(r),
    do:
      fields(
        r,
        ~w(id name implementation enabled capacity advertised_capabilities approved_capabilities protocol protocol_version endpoint_metadata generation version inserted_at updated_at)a
      )

  def credential(r), do: fields(r, ~w(id agent_id reference expires_at revoked_at inserted_at)a)
  def connection(r), do: fields(r, ~w(id agent_id generation state expires_at version)a)

  def session(r),
    do: fields(r, ~w(id agent_id project_id connection_id external_id state version)a)

  def member(r), do: fields(r, ~w(id project_id agent_id roles enabled version)a)

  def repository(r),
    do: fields(r, ~w(id kind provider host external_id display_name verification version)a)

  def association(r), do: fields(r, ~w(id project_id repository_id role primary version)a)

  def task(r) do
    fields(
      r,
      ~w(id project_id parent_task_id title description state version adopted execution_hold required_capabilities accepted_at inserted_at updated_at)a
    )
    |> Map.put(
      "legacy",
      if(!r.adopted || r.migration_metadata != %{},
        do: fields(r, ~w(type status attempts agent_id queued_at started_at completed_at)a),
        else: nil
      )
    )
  end

  def attempt(r),
    do:
      fields(
        r,
        ~w(id task_id project_id agent_id session_id connection_id connection_generation number state version fence execution_epoch proof_key_id lease_expires_at start_deadline execution_deadline terminal_at outcome effects_resolved)a
      )

  def decision(r),
    do:
      fields(
        r,
        ~w(id project_id task_id attempt_id author_agent_id kind verdict summary metadata inserted_at)a
      )

  def artifact(r),
    do:
      fields(
        r,
        ~w(id project_id task_id attempt_id created_by_agent_id kind locator digest metadata inserted_at)a
      )

  def authority(r), do: fields(r, ~w(owner admission_open epoch version)a)

  def fields(record, fields), do: Map.new(fields, &{to_string(&1), value(Map.get(record, &1))})
  defp value(%DateTime{} = v), do: DateTime.to_iso8601(v)
  defp value(%NaiveDateTime{} = v), do: NaiveDateTime.to_iso8601(v)
  defp value(v), do: v
end
