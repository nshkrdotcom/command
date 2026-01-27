defmodule Command.Test.FixtureHelper do
  @moduledoc """
  Helpers for loading test fixtures.

  Provides functions for loading JSON fixtures, prompt sets, provider responses,
  normalized events, VCS fixtures, and managing temporary git repositories.

  ## Fixture Directory Structure

      test/fixtures/
        prompt_sets/
        provider_responses/
          claude/
          codex/
        normalized_events/
        vcs/
        approvals/
  """

  @fixture_path Path.join([File.cwd!(), "test", "fixtures"])

  @doc """
  Returns the absolute path to a fixture file.
  """
  @spec fixture_path(String.t(), keyword()) :: String.t()
  def fixture_path(path, opts \\ []) do
    full_path = Path.join(@fixture_path, path)

    if Keyword.get(opts, :absolute, false) do
      Path.expand(full_path)
    else
      full_path
    end
  end

  @doc """
  Check if a fixture file exists.
  """
  @spec fixture_exists?(String.t()) :: boolean()
  def fixture_exists?(path) do
    File.exists?(fixture_path(path))
  end

  @doc """
  Check if a fixture file is readable.
  """
  @spec fixture_readable?(String.t()) :: boolean()
  def fixture_readable?(path) do
    full = fixture_path(path)
    File.exists?(full) and File.regular?(full)
  end

  @doc """
  Load a JSON fixture from the given path relative to test/fixtures/.
  """
  @spec load_fixture(String.t()) :: map() | list()
  def load_fixture(path) do
    full_path = fixture_path(path)
    content = File.read!(full_path)
    Jason.decode!(content)
  end

  @doc """
  Load a prompt set fixture by name (without extension).
  """
  @spec load_prompt_set(String.t()) :: map()
  def load_prompt_set(name) do
    load_fixture("prompt_sets/#{name}.json")
  end

  @doc """
  Load a Claude provider response fixture by name (without extension).
  """
  @spec load_claude_response(String.t()) :: map() | list()
  def load_claude_response(name) do
    load_fixture("provider_responses/claude/#{name}.json")
  end

  @doc """
  Load a Codex provider response fixture by name (without extension).
  """
  @spec load_codex_response(String.t()) :: map() | list()
  def load_codex_response(name) do
    load_fixture("provider_responses/codex/#{name}.json")
  end

  @doc """
  Load a normalized event fixture by name (without extension).
  """
  @spec load_normalized_event(String.t()) :: map()
  def load_normalized_event(name) do
    load_fixture("normalized_events/#{name}.json")
  end

  @doc """
  Load a VCS fixture file (returned as raw string).
  """
  @spec load_vcs_fixture(String.t()) :: String.t()
  def load_vcs_fixture(name) do
    full_path = fixture_path("vcs/#{name}")
    File.read!(full_path)
  end

  @doc """
  Load an approval fixture by name (without extension).
  """
  @spec load_approval_fixture(String.t()) :: map()
  def load_approval_fixture(name) do
    load_fixture("approvals/#{name}.json")
  end

  @doc """
  Create a temporary git repository for testing.

  Returns the path to the repository. The caller is responsible for cleanup.
  """
  @spec git_fixture_repo() :: String.t()
  def git_fixture_repo do
    path = Path.join(System.tmp_dir!(), "git_fixture_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(path)

    System.cmd("git", ["init"], cd: path)
    System.cmd("git", ["config", "user.email", "test@example.com"], cd: path)
    System.cmd("git", ["config", "user.name", "Test User"], cd: path)

    path
  end

  @doc """
  Clean up a git fixture repository.
  """
  @spec cleanup_git_fixture(String.t()) :: :ok
  def cleanup_git_fixture(path) do
    File.rm_rf(path)
    :ok
  end
end
