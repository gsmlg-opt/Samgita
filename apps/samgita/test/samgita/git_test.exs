defmodule Samgita.GitTest do
  use ExUnit.Case, async: true

  alias Samgita.Git

  describe "extract_repo_name/1" do
    test "extracts from SSH URL" do
      assert "repo" = Git.extract_repo_name("git@github.com:org/repo.git")
    end

    test "extracts from HTTPS URL" do
      assert "repo" = Git.extract_repo_name("https://github.com/org/repo.git")
    end

    test "handles URL without .git suffix" do
      assert "repo" = Git.extract_repo_name("https://github.com/org/repo")
    end
  end

  describe "normalize_url/1" do
    test "normalizes SSH and HTTPS URLs to comparable form" do
      ssh = Git.normalize_url("git@github.com:org/repo.git")
      https = Git.normalize_url("https://github.com/org/repo.git")
      assert ssh == https
    end

    test "strips trailing .git" do
      assert Git.normalize_url("https://github.com/org/repo.git") ==
               Git.normalize_url("https://github.com/org/repo")
    end
  end

  describe "find_local_repo/1" do
    test "returns :not_found for unknown repos" do
      assert :not_found =
               Git.find_local_repo(
                 "git@github.com:nonexistent/repo-#{System.unique_integer([:positive])}.git"
               )
    end
  end

  describe "get_remote_url/1" do
    test "returns remote URL for current repo" do
      assert {:ok, url} = Git.get_remote_url(".")
      assert is_binary(url)
      assert String.contains?(url, "Samgita")
    end

    test "returns error for non-git directory" do
      assert {:error, :no_remote} = Git.get_remote_url("/tmp")
    end
  end

  describe "extract_repo_name/1 (additional)" do
    test "handles deeply nested paths" do
      assert "repo" = Git.extract_repo_name("https://gitlab.com/group/subgroup/repo.git")
    end

    test "handles bare name" do
      assert "repo" = Git.extract_repo_name("repo")
    end
  end

  describe "normalize_url/1 (additional)" do
    test "normalizes GitLab SSH URLs" do
      ssh = Git.normalize_url("git@gitlab.com:group/repo.git")
      https = Git.normalize_url("https://gitlab.com/group/repo.git")
      assert ssh == https
    end

    test "handles whitespace in URLs" do
      assert Git.normalize_url("  https://github.com/org/repo.git  ") ==
               Git.normalize_url("https://github.com/org/repo")
    end
  end
end
