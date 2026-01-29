defmodule Samgita.Git do
  @moduledoc """
  Git helper module for repository management.
  Handles finding local clones, cloning repos, and getting remote URLs.
  """

  @doc "Find local clone of a git repo by URL"
  def find_local_repo(git_url) do
    repo_name = extract_repo_name(git_url)

    search_paths = [
      Path.expand("~/projects/#{repo_name}"),
      Path.expand("~/code/#{repo_name}"),
      Path.expand("~/dev/#{repo_name}"),
      Path.expand("~/Workspace/#{repo_name}"),
      Path.expand("~/#{repo_name}")
    ]

    Enum.find_value(search_paths, :not_found, fn path ->
      if File.dir?(Path.join(path, ".git")) do
        case get_remote_url(path) do
          {:ok, remote} ->
            if normalize_url(remote) == normalize_url(git_url) do
              {:ok, path}
            end

          _ ->
            nil
        end
      end
    end)
  end

  @doc "Clone a repo to default location"
  def clone(git_url, opts \\ []) do
    target = opts[:path] || default_clone_path(git_url)

    case System.cmd("git", ["clone", git_url, target], stderr_to_stdout: true) do
      {_, 0} -> {:ok, target}
      {err, _} -> {:error, err}
    end
  end

  @doc "Get the remote origin URL of a local repo"
  def get_remote_url(path) do
    case System.cmd("git", ["-C", path, "remote", "get-url", "origin"], stderr_to_stdout: true) do
      {url, 0} -> {:ok, String.trim(url)}
      {_, _} -> {:error, :no_remote}
    end
  end

  @doc "Extract repo name from git URL"
  def extract_repo_name(url) do
    url
    |> String.split("/")
    |> List.last()
    |> String.replace(~r/\.git$/, "")
  end

  @doc "Normalize git URL for comparison"
  def normalize_url(url) do
    url
    |> String.trim()
    |> String.replace(~r/\.git$/, "")
    |> String.replace(~r"^https?://", "")
    |> String.replace(~r"^git@([^:]+):", "\\1/")
  end

  defp default_clone_path(url) do
    Path.expand("~/projects/#{extract_repo_name(url)}")
  end
end
