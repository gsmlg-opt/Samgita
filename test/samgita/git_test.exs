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
end
