defmodule Command.Steps.Git do
  @moduledoc """
  FlowStone step handlers for Git VCS operations.

  This module provides discrete VCS operations that can be used within
  FlowStone asset `execute_fn` functions. Each operation extracts the
  `:git` resource from the FlowStone context and delegates to the
  VCS resource wrapper.

  ## Supported Operations

  | Operation  | Inputs                                       | Outputs                              |
  |------------|----------------------------------------------|--------------------------------------|
  | `:status`  | `%{operation: :status}`                      | `%{status: status_map}`              |
  | `:commit`  | `%{operation: :commit, message: String.t()}` | `%{commit_hash: hash}` or `%{status: :no_changes}` |
  | `:diff`    | `%{operation: :diff, from: ref, to: ref}`    | `%{patch: String.t(), stats: map()}` |
  | `:diff`    | `%{operation: :diff}`                        | `%{patch: String.t(), stats: map()}` (uncommitted) |

  ## Usage in FlowStone Pipeline

      # Define an asset that uses Git operations
      asset :check_status do
        requires [:git]
        execute fn context, _deps ->
          Command.Steps.Git.run(%{operation: :status}, context)
        end
      end

      asset :commit_changes do
        requires [:git]
        execute fn context, _deps ->
          Command.Steps.Git.run(
            %{operation: :commit, message: "Automated commit"},
            context
          )
        end
      end

  ## Resource Requirements

  The `:git` resource must be registered in the FlowStone context as a
  `Command.FlowStone.Resources.VCS` state map containing `:adapter` and `:repo` keys.
  """

  alias Command.FlowStone.Resources.VCS

  @typedoc "Input map for a Git step operation"
  @type input :: map()

  @typedoc "Result of a successful Git step operation"
  @type result ::
          %{status: PortfolioCore.Ports.VCS.status()}
          | %{commit_hash: String.t()}
          | %{status: :no_changes}
          | %{patch: String.t(), stats: map()}

  @doc """
  Execute a Git step operation.

  ## Parameters

  - `input` - Map containing `:operation` key and operation-specific parameters
  - `context` - FlowStone context with `:git` resource in `context.resources`

  ## Returns

  - `{:ok, result}` on success
  - `{:error, reason}` on failure

  ## Operations

  ### `:status`

  Returns the current repository status.

      Git.run(%{operation: :status}, context)
      #=> {:ok, %{status: %{is_dirty: true, ...}}}

  ### `:commit`

  Stages all changes and creates a commit. Returns `:no_changes` if repo is clean.

      Git.run(%{operation: :commit, message: "Fix bug"}, context)
      #=> {:ok, %{commit_hash: "abc123..."}}

      Git.run(%{operation: :commit, message: "Fix bug", opts: [allow_empty: true]}, context)
      #=> {:ok, %{commit_hash: "def456..."}}

  ### `:diff`

  Returns diff between refs, or uncommitted diff if no refs provided.

      Git.run(%{operation: :diff, from: "HEAD~1", to: "HEAD"}, context)
      #=> {:ok, %{patch: "...", stats: %{additions: 5, ...}}}

      Git.run(%{operation: :diff}, context)
      #=> {:ok, %{patch: "...", stats: %{additions: 2, ...}}}
  """
  @spec run(input(), FlowStone.Context.t()) :: {:ok, result()} | {:error, term()}
  def run(%{operation: :status} = _input, context) do
    with {:ok, git} <- get_git_resource(context),
         {:ok, status} <- VCS.status(git) do
      {:ok, %{status: status}}
    end
  end

  def run(%{operation: :commit, message: message} = input, context) do
    opts = Map.get(input, :opts, [])

    with {:ok, git} <- get_git_resource(context),
         {:ok, status} <- VCS.status(git) do
      if status.is_dirty do
        with :ok <- VCS.stage_all(git),
             {:ok, hash} <- VCS.commit(git, message, opts) do
          {:ok, %{commit_hash: hash}}
        end
      else
        {:ok, %{status: :no_changes}}
      end
    end
  end

  def run(%{operation: :diff, from: from, to: to} = _input, context) do
    with {:ok, git} <- get_git_resource(context),
         {:ok, diff} <- VCS.diff(git, from, to) do
      {:ok, %{patch: diff.patch, stats: diff.stats}}
    end
  end

  def run(%{operation: :diff} = _input, context) do
    with {:ok, git} <- get_git_resource(context),
         {:ok, diff} <- VCS.diff_uncommitted(git) do
      {:ok, %{patch: diff.patch, stats: diff.stats}}
    end
  end

  def run(%{operation: operation}, _context) do
    {:error, {:unknown_operation, operation}}
  end

  @spec get_git_resource(FlowStone.Context.t()) ::
          {:ok, VCS.t()} | {:error, :git_resource_not_found}
  defp get_git_resource(%{resources: resources}) do
    case Map.get(resources, :git) do
      nil -> {:error, :git_resource_not_found}
      git -> {:ok, git}
    end
  end
end
