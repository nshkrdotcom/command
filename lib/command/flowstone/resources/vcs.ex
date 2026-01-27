defmodule Command.FlowStone.Resources.VCS do
  @moduledoc """
  FlowStone resource wrapper for VCS operations.

  This resource provides context injection for version control system operations
  within FlowStone workflows. It wraps a VCS adapter (implementing
  `PortfolioCore.Ports.VCS`) and provides convenient access to VCS operations.

  ## Configuration

  Required config keys:
  - `:repo` - Path to the repository root directory

  Optional config keys:
  - `:adapter` - VCS adapter module (default: `PortfolioIndex.Adapters.VCS.Git`)

  ## Example

      # Setup resource
      config = %{
        repo: "/path/to/repo",
        adapter: PortfolioIndex.Adapters.VCS.Git
      }

      {:ok, vcs} = VCS.setup(config)

      # Use in workflow
      {:ok, status} = VCS.status(vcs)
      if status.is_dirty do
        :ok = VCS.stage_all(vcs)
        {:ok, hash} = VCS.commit(vcs, "Automated commit", [])
      end

      # Cleanup
      :ok = VCS.teardown(vcs)

  ## Usage in FlowStone Pipeline

      resources = [
        {:git, Command.FlowStone.Resources.VCS, %{repo: "/path/to/repo"}}
      ]

      steps = [
        %{step: Command.Steps.Git, operation: :status},
        %{step: Command.Steps.Git, operation: :commit, message: "Update files"}
      ]

      {:ok, result} = FlowStone.Pipeline.run(steps, resources: resources)
  """

  use FlowStone.Resource

  @typedoc "VCS resource state"
  @type t :: %{
          adapter: module(),
          repo: Path.t()
        }

  @doc """
  Setup the VCS resource with configuration.

  ## Options

  - `:repo` - (required) Path to the repository root
  - `:adapter` - (optional) VCS adapter module (default: PortfolioIndex.Adapters.VCS.Git)

  ## Examples

      {:ok, vcs} = VCS.setup(%{repo: "/path/to/repo"})
      {:ok, vcs} = VCS.setup(%{repo: "/path/to/repo", adapter: MyCustomAdapter})
  """
  @impl true
  def setup(config) do
    repo = Map.get(config, :repo)

    if repo do
      adapter = Map.get(config, :adapter, PortfolioIndex.Adapters.VCS.Git)

      {:ok, %{adapter: adapter, repo: repo}}
    else
      {:error, :repo_required}
    end
  end

  @doc """
  Teardown the VCS resource.

  Currently a no-op as VCS resources don't require cleanup.
  """
  @impl true
  def teardown(_state), do: :ok

  @doc """
  Health check for the VCS resource.

  Returns `:healthy` if the repository exists and is accessible.
  """
  @impl true
  def health_check(state) do
    if state.adapter.is_repo?(state.repo) do
      :healthy
    else
      {:unhealthy, :repository_not_found}
    end
  end

  ## Convenience Functions
  ## These delegate to the adapter with the repo from state

  @doc """
  Get repository status.

  Returns status information including changed files, staged files, branch info, etc.

  ## Examples

      {:ok, status} = VCS.status(vcs)
      if status.is_dirty do
        IO.puts("Repository has uncommitted changes")
      end
  """
  @spec status(t()) :: {:ok, PortfolioCore.Ports.VCS.status()} | {:error, term()}
  def status(%{adapter: adapter, repo: repo}) do
    adapter.status(repo)
  end

  @doc """
  Stage specific files for commit.

  ## Examples

      :ok = VCS.stage(vcs, ["file1.txt", "file2.txt"])
  """
  @spec stage(t(), [Path.t()]) :: :ok | {:error, term()}
  def stage(%{adapter: adapter, repo: repo}, files) do
    adapter.stage(repo, files)
  end

  @doc """
  Stage all changes for commit.

  ## Examples

      :ok = VCS.stage_all(vcs)
  """
  @spec stage_all(t()) :: :ok | {:error, term()}
  def stage_all(%{adapter: adapter, repo: repo}) do
    adapter.stage_all(repo)
  end

  @doc """
  Unstage files.

  ## Examples

      :ok = VCS.unstage(vcs, ["file1.txt"])
  """
  @spec unstage(t(), [Path.t()]) :: :ok | {:error, term()}
  def unstage(%{adapter: adapter, repo: repo}, files) do
    adapter.unstage(repo, files)
  end

  @doc """
  Create a commit with the given message.

  ## Options

  - `:allow_empty` - Allow creating an empty commit
  - `:amend` - Amend the previous commit
  - `:no_verify` - Skip pre-commit hooks

  ## Examples

      {:ok, hash} = VCS.commit(vcs, "Fix bug in parser", [])
      {:ok, hash} = VCS.commit(vcs, "Empty commit", allow_empty: true)
  """
  @spec commit(t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def commit(%{adapter: adapter, repo: repo}, message, opts \\ []) do
    adapter.commit(repo, message, opts)
  end

  @doc """
  Get diff of uncommitted changes.

  ## Examples

      {:ok, diff} = VCS.diff_uncommitted(vcs)
      IO.puts(diff.patch)
  """
  @spec diff_uncommitted(t()) :: {:ok, PortfolioCore.Ports.VCS.diff_result()} | {:error, term()}
  def diff_uncommitted(%{adapter: adapter, repo: repo}) do
    adapter.diff_uncommitted(repo)
  end

  @doc """
  Get diff between two refs.

  ## Examples

      {:ok, diff} = VCS.diff(vcs, "main", "feature")
      IO.puts("Changed \#{diff.stats.files_changed} files")
  """
  @spec diff(t(), String.t(), String.t()) ::
          {:ok, PortfolioCore.Ports.VCS.diff_result()} | {:error, term()}
  def diff(%{adapter: adapter, repo: repo}, from, to) do
    adapter.diff(repo, from, to)
  end

  @doc """
  Get commit history.

  ## Options

  - `:limit` - Maximum number of commits to return
  - `:skip` - Number of commits to skip

  ## Examples

      {:ok, commits} = VCS.log(vcs, limit: 10)
      Enum.each(commits, fn c -> IO.puts("\#{c.short_hash} \#{c.subject}") end)
  """
  @spec log(t(), keyword()) :: {:ok, [PortfolioCore.Ports.VCS.commit()]} | {:error, term()}
  def log(%{adapter: adapter, repo: repo}, opts \\ []) do
    adapter.log(repo, opts)
  end

  @doc """
  Show details for a specific commit.

  ## Examples

      {:ok, commit} = VCS.show(vcs, "abc123")
      IO.puts("Author: \#{commit.author}")
  """
  @spec show(t(), String.t()) :: {:ok, PortfolioCore.Ports.VCS.commit()} | {:error, term()}
  def show(%{adapter: adapter, repo: repo}, ref) do
    adapter.show(repo, ref)
  end

  @doc """
  Get the name of the current branch.

  ## Examples

      {:ok, branch} = VCS.current_branch(vcs)
      IO.puts("On branch: \#{branch}")
  """
  @spec current_branch(t()) :: {:ok, String.t() | nil} | {:error, term()}
  def current_branch(%{adapter: adapter, repo: repo}) do
    adapter.current_branch(repo)
  end

  @doc """
  Check if the path is a VCS repository.

  ## Examples

      if VCS.is_repo?(vcs) do
        IO.puts("Valid repository")
      end
  """
  @spec is_repo?(t()) :: boolean()
  def is_repo?(%{adapter: adapter, repo: repo}) do
    adapter.is_repo?(repo)
  end

  ## Optional Operations

  @doc """
  Push commits to remote repository.

  ## Options

  - `:remote` - Remote name (default: "origin")
  - `:branch` - Branch to push
  - `:force` - Force push (requires approval gate)
  - `:set_upstream` - Set upstream tracking

  ## Examples

      :ok = VCS.push(vcs, remote: "origin", branch: "main")
  """
  @spec push(t(), keyword()) :: :ok | {:error, term()}
  def push(%{adapter: adapter, repo: repo}, opts \\ []) do
    adapter.push(repo, opts)
  end

  @doc """
  Pull commits from remote repository.

  ## Options

  - `:remote` - Remote name (default: "origin")
  - `:branch` - Branch to pull
  - `:rebase` - Use rebase instead of merge

  ## Examples

      :ok = VCS.pull(vcs, rebase: true)
  """
  @spec pull(t(), keyword()) :: :ok | {:error, term()}
  def pull(%{adapter: adapter, repo: repo}, opts \\ []) do
    adapter.pull(repo, opts)
  end

  @doc """
  Create a new branch.

  ## Options

  - `:from` - Starting ref for new branch (default: HEAD)
  - `:checkout` - Checkout the branch after creating

  ## Examples

      :ok = VCS.branch_create(vcs, "feature", from: "main")
  """
  @spec branch_create(t(), String.t(), keyword()) :: :ok | {:error, term()}
  def branch_create(%{adapter: adapter, repo: repo}, name, opts \\ []) do
    adapter.branch_create(repo, name, opts)
  end

  @doc """
  Delete a branch.

  ## Options

  - `:force` - Force delete unmerged branch
  - `:remote` - Delete remote branch instead of local

  ## Examples

      :ok = VCS.branch_delete(vcs, "old-feature", [])
  """
  @spec branch_delete(t(), String.t(), keyword()) :: :ok | {:error, term()}
  def branch_delete(%{adapter: adapter, repo: repo}, name, opts \\ []) do
    adapter.branch_delete(repo, name, opts)
  end

  @doc """
  Checkout a ref (branch, tag, or commit).

  ## Examples

      :ok = VCS.checkout(vcs, "feature-branch")
  """
  @spec checkout(t(), String.t()) :: :ok | {:error, term()}
  def checkout(%{adapter: adapter, repo: repo}, ref) do
    adapter.checkout(repo, ref)
  end
end
