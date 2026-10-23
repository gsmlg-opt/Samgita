defmodule Samgita.Repositories do
  @moduledoc "Repository identity and associations are independent of Project identity."
  import Ecto.Query
  import Ecto.Changeset
  alias Samgita.{Commands, Events, Params, Projection, Repo}
  alias Samgita.Domain.{ProjectRepository, Repository, RepositoryAlias}

  def associate(principal, project_id, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      project_id,
      attrs,
      [operation: "repository.associate", roles: ["manager"]],
      fn ctx ->
        Commands.expect!(ctx.project, attrs)
        if ctx.project.state not in ~w(active paused), do: Commands.fail!(:invalid_transition)

        repository = repository!(attrs)

        if attrs["url"], do: add_alias!(repository.id, attrs["url"], "operator")

        record =
          Repo.get_by(ProjectRepository, project_id: project_id, repository_id: repository.id) ||
            %ProjectRepository{project_id: project_id, repository_id: repository.id}

        previous = if record.id, do: record

        changeset =
          record
          |> cast(attrs, [:role, :primary])
          |> validate_inclusion(:role, ~w(source documentation reference))
          |> put_change(:version, if(record.id, do: record.version + 1, else: 1))
          |> unique_constraint(:primary, name: :one_primary_repository)

        record = if record.id, do: Commands.update!(changeset), else: Commands.insert!(changeset)
        project = ctx.project |> change(version: ctx.project.version + 1) |> Commands.update!()

        Events.append!(
          project_id,
          "project.repository_associated",
          ctx,
          "project_repository",
          record.id,
          %{
            "project_before" => Events.snapshot(ctx.project),
            "project_after" => Events.snapshot(project)
          },
          previous: previous,
          current: record
        )

        Projection.association(record)
        |> Map.put("repository", Projection.repository(repository))
        |> Map.put("project_version", project.version)
      end
    )
  end

  defp repository!(%{"repository_id" => id}) when not is_nil(id) do
    if !Params.uuid?(id), do: Commands.fail!(:not_found)
    Repo.get(Repository, id) || Commands.fail!(:not_found)
  end

  defp repository!(attrs) do
    # Provider identity is not verified merely because a caller supplies it.
    %Repository{}
    |> cast(attrs, [:kind, :provider, :host, :display_name])
    |> validate_inclusion(:kind, ["git", "local"])
    |> validate_length(:display_name, max: 500)
    |> Commands.insert!()
  end

  def list(principal, id, params \\ %{}) do
    Commands.read(principal, id, ~w(observer worker manager reviewer), fn _ ->
      {limit, offset} = Params.page(params)
      %{"data" => list_locked(id, params), "limit" => limit, "offset" => offset}
    end)
  end

  def list_locked(id, params \\ %{}) do
    {limit, offset} = Params.page(params)

    Repo.all(
      from a in ProjectRepository,
        join: r in Repository,
        on: a.repository_id == r.id,
        where: a.project_id == ^id,
        order_by: a.id,
        limit: ^limit,
        offset: ^offset,
        select: {a, r}
    )
    |> Enum.map(fn {a, r} ->
      Projection.association(a) |> Map.put("repository", Projection.repository(r))
    end)
  end

  def add_alias!(repository_id, url, source) do
    normalized = normalize(url)
    if normalized == :invalid, do: Commands.fail!(:invalid, %{field: "url"})

    %RepositoryAlias{}
    |> change(repository_id: repository_id, url: url, normalized_url: normalized, source: source)
    |> unique_constraint([:repository_id, :url])
    |> Commands.insert!()
  end

  def normalize(url) when is_binary(url) and byte_size(url) <= 4096 do
    if Regex.match?(~r/^[\w.-]+@[\w.-]+:[^\s]+$/, url) do
      [_, host, path] = Regex.run(~r/^[\w.-]+@([\w.-]+):(.+)$/, url)
      normalize_git(host, path)
    else
      normalize_uri(url)
    end
  end

  def normalize(_), do: :invalid

  defp normalize_uri(url) do
    uri = URI.parse(url)

    cond do
      git_uri?(uri) -> normalize_git(uri.host, uri.path || "")
      uri.scheme == nil && !String.contains?(url, "\n") && url != "" -> "local:" <> url
      true -> :invalid
    end
  end

  defp git_uri?(uri) do
    uri.scheme in ~w(https http ssh git) && is_binary(uri.host) &&
      uri.query == nil && uri.fragment == nil && safe_userinfo?(uri)
  end

  defp safe_userinfo?(%{userinfo: nil}), do: true
  defp safe_userinfo?(%{scheme: "ssh", userinfo: value}), do: !String.contains?(value, ":")
  defp safe_userinfo?(_), do: false

  defp normalize_git(host, path),
    do:
      String.downcase(host) <> "/" <> (path |> String.trim("/") |> String.replace(~r/\.git$/, ""))
end
