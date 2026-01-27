defmodule Command.PromptSets.ExecutionPlan do
  @moduledoc """
  Represents an execution plan for a prompt set.

  An execution plan groups prompts into waves based on dependency analysis
  and repo conflict detection. Each wave contains prompts that can execute
  concurrently. Waves execute sequentially - all prompts in wave N must
  complete before wave N+1 begins.

  ## Fields

  - `version` - Schema version for the plan format
  - `prompt_set_id` - UUID of the prompt set being planned
  - `workspace_repos` - All repos configured in the workspace
  - `affected_repos` - Repos actually touched by prompts in this plan
  - `prompt_repo_map` - Map of prompt_num to list of target repos
  - `repo_conflicts` - List of repo conflict descriptors
  - `execution_waves` - Ordered list of wave descriptors
  - `branch_plan` - Branch strategy resolution
  - `changeset_plan` - Changeset coordination plan
  - `partial_success_plan` - Partial success policy resolution
  - `max_concurrency` - Maximum concurrent prompts per wave
  - `fail_fast` - Whether to abort on first failure

  ## Wave Structure

  Each wave in `execution_waves` is a map:

      %{wave: 0, prompts: ["01", "03"], parallel: true}

  - `wave` - Zero-based wave index
  - `prompts` - List of prompt numbers in this wave
  - `parallel` - Whether prompts in this wave can run concurrently

  ## Repo Conflict Structure

  Each entry in `repo_conflicts`:

      %{repo: "command", prompts: ["01", "04"], serialized: true}

  - `repo` - Repository name
  - `prompts` - Prompt numbers that target this repo
  - `serialized` - Whether these prompts were serialized into separate waves
  """

  @type wave :: %{
          wave: non_neg_integer(),
          prompts: [String.t()],
          parallel: boolean()
        }

  @type repo_conflict :: %{
          repo: String.t(),
          prompts: [String.t()],
          serialized: boolean()
        }

  @type branch_plan :: %{
          strategy: String.t(),
          pr_requested: boolean(),
          pr_effective: boolean(),
          pr_warning: String.t() | nil
        }

  @type changeset_plan :: %{
          run_changeset: boolean(),
          prompt_changesets: boolean()
        }

  @type partial_success_plan :: %{
          mode: String.t(),
          min_repos_percent: non_neg_integer(),
          exit_code_on_partial: non_neg_integer()
        }

  @type t :: %__MODULE__{
          version: String.t(),
          prompt_set_id: String.t() | nil,
          workspace_repos: [String.t()],
          affected_repos: [String.t()],
          prompt_repo_map: %{String.t() => [String.t()]},
          repo_conflicts: [repo_conflict()],
          execution_waves: [wave()],
          branch_plan: branch_plan(),
          changeset_plan: changeset_plan(),
          partial_success_plan: partial_success_plan(),
          max_concurrency: pos_integer(),
          fail_fast: boolean()
        }

  @enforce_keys [:execution_waves]
  defstruct [
    :prompt_set_id,
    version: "1.0.0",
    workspace_repos: [],
    affected_repos: [],
    prompt_repo_map: %{},
    repo_conflicts: [],
    execution_waves: [],
    branch_plan: %{
      strategy: "direct",
      pr_requested: false,
      pr_effective: false,
      pr_warning: nil
    },
    changeset_plan: %{
      run_changeset: true,
      prompt_changesets: true
    },
    partial_success_plan: %{
      mode: "continue",
      min_repos_percent: 50,
      exit_code_on_partial: 6
    },
    max_concurrency: 3,
    fail_fast: false
  ]
end
