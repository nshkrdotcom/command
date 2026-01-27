defmodule Command.Steps.GitTest do
  use ExUnit.Case, async: true

  alias Command.Steps.Git

  # Mock VCS adapter for testing - dirty repo
  defmodule MockVCS do
    @behaviour PortfolioCore.Ports.VCS

    @impl true
    def status(_repo) do
      {:ok,
       %{
         changed_files: ["file1.txt"],
         staged_files: [],
         untracked_files: ["file2.txt"],
         deleted_files: [],
         is_dirty: true,
         current_branch: "main",
         upstream_branch: "origin/main",
         ahead_count: 0,
         behind_count: 0
       }}
    end

    @impl true
    def diff(_repo, _from, _to) do
      {:ok,
       %{
         patch: "diff --git a/file.txt b/file.txt\n-old\n+new",
         stats: %{
           additions: 1,
           deletions: 1,
           files_changed: 1,
           files: [%{path: "file.txt", additions: 1, deletions: 1}]
         }
       }}
    end

    @impl true
    def diff_uncommitted(_repo) do
      {:ok,
       %{
         patch: "diff --git a/file1.txt b/file1.txt\n+new content",
         stats: %{
           additions: 1,
           deletions: 0,
           files_changed: 1,
           files: [%{path: "file1.txt", additions: 1, deletions: 0}]
         }
       }}
    end

    @impl true
    def stage(_repo, _files), do: :ok

    @impl true
    def stage_all(_repo), do: :ok

    @impl true
    def unstage(_repo, _files), do: :ok

    @impl true
    def commit(_repo, _message, _opts),
      do: {:ok, "abc1234567890123456789012345678901234567"}

    @impl true
    def log(_repo, _opts), do: {:ok, []}

    @impl true
    def show(_repo, _ref), do: {:ok, %{}}

    @impl true
    def current_branch(_repo), do: {:ok, "main"}

    @impl true
    def is_repo?(_repo), do: true
  end

  # Mock VCS adapter for clean repo
  defmodule MockVCSClean do
    @behaviour PortfolioCore.Ports.VCS

    @impl true
    def status(_repo) do
      {:ok,
       %{
         changed_files: [],
         staged_files: [],
         untracked_files: [],
         deleted_files: [],
         is_dirty: false,
         current_branch: "main",
         upstream_branch: nil,
         ahead_count: 0,
         behind_count: 0
       }}
    end

    @impl true
    def diff(_repo, _from, _to), do: {:ok, %{patch: "", stats: %{}}}

    @impl true
    def diff_uncommitted(_repo),
      do:
        {:ok,
         %{
           patch: "",
           stats: %{additions: 0, deletions: 0, files_changed: 0, files: []}
         }}

    @impl true
    def stage(_repo, _files), do: :ok

    @impl true
    def stage_all(_repo), do: :ok

    @impl true
    def unstage(_repo, _files), do: :ok

    @impl true
    def commit(_repo, _message, _opts), do: {:error, :nothing_to_commit}

    @impl true
    def log(_repo, _opts), do: {:ok, []}

    @impl true
    def show(_repo, _ref), do: {:error, {:invalid_ref, "HEAD"}}

    @impl true
    def current_branch(_repo), do: {:ok, "main"}

    @impl true
    def is_repo?(_repo), do: true
  end

  # Mock VCS adapter that errors on status
  defmodule MockVCSError do
    @behaviour PortfolioCore.Ports.VCS

    @impl true
    def status(_repo), do: {:error, {:repository_not_found, "/bad/path"}}

    @impl true
    def diff(_repo, _from, _to), do: {:error, {:repository_not_found, "/bad/path"}}

    @impl true
    def diff_uncommitted(_repo), do: {:error, {:repository_not_found, "/bad/path"}}

    @impl true
    def stage(_repo, _files), do: {:error, {:repository_not_found, "/bad/path"}}

    @impl true
    def stage_all(_repo), do: {:error, {:repository_not_found, "/bad/path"}}

    @impl true
    def unstage(_repo, _files), do: {:error, {:repository_not_found, "/bad/path"}}

    @impl true
    def commit(_repo, _message, _opts), do: {:error, {:repository_not_found, "/bad/path"}}

    @impl true
    def log(_repo, _opts), do: {:error, {:repository_not_found, "/bad/path"}}

    @impl true
    def show(_repo, _ref), do: {:error, {:repository_not_found, "/bad/path"}}

    @impl true
    def current_branch(_repo), do: {:error, {:repository_not_found, "/bad/path"}}

    @impl true
    def is_repo?(_repo), do: false
  end

  defp build_context(adapter) do
    {:ok, vcs_state} =
      Command.FlowStone.Resources.VCS.setup(%{adapter: adapter, repo: "/tmp/test_repo"})

    %FlowStone.Context{
      asset: :git_step,
      partition: :default,
      run_id: "test-run-123",
      resources: %{git: vcs_state},
      metadata: %{},
      started_at: DateTime.utc_now()
    }
  end

  describe "status operation" do
    test "returns status map from git resource" do
      context = build_context(MockVCS)
      input = %{operation: :status}

      assert {:ok, result} = Git.run(input, context)

      assert %{status: status} = result
      assert status.is_dirty == true
      assert status.current_branch == "main"
      assert "file1.txt" in status.changed_files
    end

    test "handles clean repo status" do
      context = build_context(MockVCSClean)
      input = %{operation: :status}

      assert {:ok, result} = Git.run(input, context)

      assert %{status: status} = result
      assert status.is_dirty == false
    end

    test "handles missing git resource gracefully" do
      context = %FlowStone.Context{
        asset: :git_step,
        partition: :default,
        run_id: "test-run-123",
        resources: %{},
        metadata: %{},
        started_at: DateTime.utc_now()
      }

      input = %{operation: :status}

      assert {:error, :git_resource_not_found} = Git.run(input, context)
    end

    test "propagates adapter errors" do
      context = build_context(MockVCSError)
      input = %{operation: :status}

      assert {:error, {:repository_not_found, _}} = Git.run(input, context)
    end
  end

  describe "commit operation" do
    test "with dirty repo stages all, commits, returns hash" do
      context = build_context(MockVCS)
      input = %{operation: :commit, message: "Test commit message"}

      assert {:ok, result} = Git.run(input, context)

      assert %{commit_hash: hash} = result
      assert is_binary(hash)
      assert String.length(hash) == 40
    end

    test "with clean repo returns no_changes status" do
      context = build_context(MockVCSClean)
      input = %{operation: :commit, message: "Should not commit"}

      assert {:ok, result} = Git.run(input, context)

      assert %{status: :no_changes} = result
    end

    test "passes commit options through" do
      context = build_context(MockVCS)

      input = %{
        operation: :commit,
        message: "Test commit",
        opts: [allow_empty: true]
      }

      assert {:ok, result} = Git.run(input, context)
      assert %{commit_hash: _hash} = result
    end

    test "handles commit errors" do
      context = build_context(MockVCSError)
      input = %{operation: :commit, message: "Should fail"}

      assert {:error, _} = Git.run(input, context)
    end
  end

  describe "diff operation" do
    test "with from/to refs returns diff between refs" do
      context = build_context(MockVCS)
      input = %{operation: :diff, from: "HEAD~1", to: "HEAD"}

      assert {:ok, result} = Git.run(input, context)

      assert %{patch: patch, stats: stats} = result
      assert is_binary(patch)
      assert patch =~ "diff"
      assert stats.files_changed == 1
    end

    test "without refs returns uncommitted diff" do
      context = build_context(MockVCS)
      input = %{operation: :diff}

      assert {:ok, result} = Git.run(input, context)

      assert %{patch: patch, stats: stats} = result
      assert is_binary(patch)
      assert stats.additions == 1
    end

    test "handles diff errors" do
      context = build_context(MockVCSError)
      input = %{operation: :diff, from: "bad", to: "refs"}

      assert {:error, _} = Git.run(input, context)
    end
  end

  describe "unknown operation" do
    test "returns error for unknown operation" do
      context = build_context(MockVCS)
      input = %{operation: :unknown}

      assert {:error, {:unknown_operation, :unknown}} = Git.run(input, context)
    end
  end
end
