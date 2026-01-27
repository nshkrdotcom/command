defmodule Command.FlowStone.Resources.VCSTest do
  use ExUnit.Case, async: true

  alias Command.FlowStone.Resources.VCS

  # Mock VCS adapter for testing
  defmodule MockVCS do
    @behaviour PortfolioCore.Ports.VCS

    @impl true
    def status(_repo) do
      {:ok,
       %{
         changed_files: ["file1.txt"],
         staged_files: [],
         untracked_files: [],
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
       %{patch: "diff content", stats: %{additions: 5, deletions: 3, files_changed: 1, files: []}}}
    end

    @impl true
    def diff_uncommitted(_repo) do
      {:ok,
       %{
         patch: "uncommitted diff",
         stats: %{additions: 2, deletions: 1, files_changed: 1, files: []}
       }}
    end

    @impl true
    def stage(_repo, _files), do: :ok

    @impl true
    def stage_all(_repo), do: :ok

    @impl true
    def unstage(_repo, _files), do: :ok

    @impl true
    def commit(_repo, _message, _opts), do: {:ok, "abc1234567890123456789012345678901234567"}

    @impl true
    def log(_repo, _opts), do: {:ok, []}

    @impl true
    def show(_repo, _ref) do
      {:ok,
       %{
         hash: "abc1234567890123456789012345678901234567",
         short_hash: "abc1234",
         author: "Test User",
         author_email: "test@example.com",
         message: "Test commit",
         subject: "Test commit",
         timestamp: DateTime.utc_now(),
         parents: []
       }}
    end

    @impl true
    def current_branch(_repo), do: {:ok, "main"}

    @impl true
    def is_repo?(_repo), do: true

    # Optional callbacks
    @impl true
    def push(_repo, _opts), do: :ok

    @impl true
    def pull(_repo, _opts), do: :ok

    @impl true
    def branch_create(_repo, _name, _opts), do: :ok

    @impl true
    def branch_delete(_repo, _name, _opts), do: :ok

    @impl true
    def checkout(_repo, _ref), do: :ok
  end

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
    def diff_uncommitted(_repo), do: {:ok, %{patch: "", stats: %{}}}

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

    # Optional callbacks
    @impl true
    def push(_repo, _opts), do: :ok

    @impl true
    def pull(_repo, _opts), do: :ok

    @impl true
    def branch_create(_repo, _name, _opts), do: :ok

    @impl true
    def branch_delete(_repo, _name, _opts), do: :ok

    @impl true
    def checkout(_repo, _ref), do: :ok
  end

  describe "setup/1" do
    test "accepts adapter and repo config" do
      config = %{adapter: MockVCS, repo: "/tmp/test_repo"}

      assert {:ok, state} = VCS.setup(config)

      assert state.adapter == MockVCS
      assert state.repo == "/tmp/test_repo"
    end

    test "uses default adapter if not specified" do
      config = %{repo: "/tmp/test_repo"}

      assert {:ok, state} = VCS.setup(config)

      assert state.adapter == PortfolioIndex.Adapters.VCS.Git
    end

    test "returns error if repo not specified" do
      config = %{}

      assert {:error, :repo_required} = VCS.setup(config)
    end
  end

  describe "teardown/1" do
    test "returns :ok" do
      state = %{adapter: MockVCS, repo: "/tmp/test_repo"}

      assert :ok = VCS.teardown(state)
    end
  end

  describe "health_check/1" do
    test "returns :healthy for valid repo" do
      state = %{adapter: MockVCS, repo: "/tmp/test_repo"}

      assert :healthy = VCS.health_check(state)
    end
  end

  describe "convenience functions" do
    setup do
      {:ok, state} = VCS.setup(%{adapter: MockVCS, repo: "/tmp/test_repo"})
      %{state: state}
    end

    test "status/1 delegates to adapter", %{state: state} do
      assert {:ok, status} = VCS.status(state)

      assert status.is_dirty == true
      assert status.current_branch == "main"
    end

    test "stage_all/1 delegates to adapter", %{state: state} do
      assert :ok = VCS.stage_all(state)
    end

    test "stage/2 delegates to adapter", %{state: state} do
      assert :ok = VCS.stage(state, ["file.txt"])
    end

    test "unstage/2 delegates to adapter", %{state: state} do
      assert :ok = VCS.unstage(state, ["file.txt"])
    end

    test "commit/3 delegates to adapter", %{state: state} do
      assert {:ok, hash} = VCS.commit(state, "Test commit", [])

      assert is_binary(hash)
      assert String.length(hash) == 40
    end

    test "diff_uncommitted/1 delegates to adapter", %{state: state} do
      assert {:ok, diff} = VCS.diff_uncommitted(state)

      assert diff.patch == "uncommitted diff"
    end

    test "diff/3 delegates to adapter", %{state: state} do
      assert {:ok, diff} = VCS.diff(state, "HEAD~1", "HEAD")

      assert diff.patch == "diff content"
    end

    test "log/2 delegates to adapter", %{state: state} do
      assert {:ok, commits} = VCS.log(state, limit: 10)

      assert is_list(commits)
    end

    test "show/2 delegates to adapter", %{state: state} do
      assert {:ok, commit} = VCS.show(state, "HEAD")

      assert commit.author == "Test User"
    end

    test "current_branch/1 delegates to adapter", %{state: state} do
      assert {:ok, branch} = VCS.current_branch(state)

      assert branch == "main"
    end

    test "is_repo?/1 delegates to adapter", %{state: state} do
      assert true = VCS.is_repo?(state)
    end
  end

  describe "optional callbacks" do
    setup do
      {:ok, state} = VCS.setup(%{adapter: MockVCS, repo: "/tmp/test_repo"})
      %{state: state}
    end

    test "push/2 delegates to adapter", %{state: state} do
      assert :ok = VCS.push(state, remote: "origin")
    end

    test "pull/2 delegates to adapter", %{state: state} do
      assert :ok = VCS.pull(state, remote: "origin")
    end

    test "branch_create/3 delegates to adapter", %{state: state} do
      assert :ok = VCS.branch_create(state, "feature", from: "main")
    end

    test "branch_delete/3 delegates to adapter", %{state: state} do
      assert :ok = VCS.branch_delete(state, "old-feature", [])
    end

    test "checkout/2 delegates to adapter", %{state: state} do
      assert :ok = VCS.checkout(state, "main")
    end
  end

  describe "with clean repo mock" do
    setup do
      {:ok, state} = VCS.setup(%{adapter: MockVCSClean, repo: "/tmp/test_repo"})
      %{state: state}
    end

    test "status shows clean repo", %{state: state} do
      {:ok, status} = VCS.status(state)

      assert status.is_dirty == false
    end

    test "commit returns nothing_to_commit error", %{state: state} do
      assert {:error, :nothing_to_commit} = VCS.commit(state, "Test", [])
    end
  end
end
