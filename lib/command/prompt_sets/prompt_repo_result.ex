defmodule Command.PromptSets.PromptRepoResult do
  @moduledoc """
  Schema for per-repository execution outcomes within a prompt step.

  This is the **authoritative store** for per-repo execution outcomes. Each multi-repo
  prompt step has one row per target repository.

  ## Status vs Commit Status

  These are two distinct concepts that MUST NOT be conflated:

  - `status` - **Execution lifecycle**: Has the agent finished working?
  - `commit_status` - **Commit outcome**: What happened to git state?

  A repo can have `status='completed'` (agent finished successfully) with
  `commit_status='no_changes'` (no diff to commit). These are NOT the same thing.

  ## Status Values (Execution Lifecycle)

  - `pending` - Not yet started
  - `running` - Currently executing
  - `completed` - Agent finished successfully (terminal)
  - `failed` - Agent crashed or errored (terminal)
  - `skipped` - Repo intentionally not executed (terminal)

  ## Commit Status Values

  - `nil` - Non-terminal status (pending/running)
  - `committed` - Changes were committed (requires commit_hash)
  - `no_commit` - Agent chose not to commit (no hash)
  - `no_changes` - No changes to commit (no hash)
  - `failed` - Commit attempt failed
  - `skipped` - Repo was skipped

  ## Invariants

  Terminal status (`completed`, `failed`, `skipped`) MUST have `commit_status` set.
  Non-terminal status (`pending`, `running`) MUST have `commit_status` NULL.

  ## Status/Commit Status Alignment

  | status | valid commit_status values |
  |--------|---------------------------|
  | pending | nil |
  | running | nil |
  | completed | committed, no_commit, no_changes |
  | failed | failed |
  | skipped | skipped |

  ## Fields

  - `prompt_step_run_id` - Reference to the parent step
  - `changeset_id` - Reference to prompt-scoped changeset
  - `repo_name` - Repository name
  - `repo_path` - Filesystem path
  - `status` - Execution status
  - `commit_hash` - Git commit hash (if committed)
  - `commit_status` - Commit result status
  - `branch_name` - Branch name for this repo
  - `pr_url` - PR URL if created
  - `files_changed` - Number of files changed
  - `insertions` - Lines inserted
  - `deletions` - Lines deleted
  - `error_message` - Error message if failed
  - `error_type` - Error classification
  - `started_at` - When repo execution started
  - `completed_at` - When repo execution finished
  - `duration_ms` - Execution duration
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          prompt_step_run_id: Ecto.UUID.t() | nil,
          changeset_id: Ecto.UUID.t() | nil,
          repo_name: String.t() | nil,
          repo_path: String.t() | nil,
          status: String.t(),
          commit_hash: String.t() | nil,
          commit_status: String.t() | nil,
          branch_name: String.t() | nil,
          pr_url: String.t() | nil,
          files_changed: integer(),
          insertions: integer(),
          deletions: integer(),
          error_message: String.t() | nil,
          error_type: String.t() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          duration_ms: integer() | nil,
          prompt_step_run: Command.PromptSets.PromptStepRun.t() | Ecto.Association.NotLoaded.t(),
          prompt_changeset:
            Command.PromptSets.PromptChangeset.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_statuses ["pending", "running", "completed", "failed", "skipped"]
  @valid_commit_statuses [nil, "committed", "no_commit", "no_changes", "failed", "skipped"]
  @terminal_statuses ["completed", "failed", "skipped"]

  schema "prompt_repo_results" do
    belongs_to :prompt_step_run, Command.PromptSets.PromptStepRun
    belongs_to :prompt_changeset, Command.PromptSets.PromptChangeset, foreign_key: :changeset_id

    field :repo_name, :string
    field :repo_path, :string
    field :status, :string, default: "pending"
    field :commit_hash, :string
    field :commit_status, :string
    field :branch_name, :string
    field :pr_url, :string
    field :files_changed, :integer, default: 0
    field :insertions, :integer, default: 0
    field :deletions, :integer, default: 0
    field :error_message, :string
    field :error_type, :string
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :duration_ms, :integer

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Creates a changeset for a prompt repo result.

  ## Required Fields

  - `prompt_step_run_id` - Reference to the parent step
  - `repo_name` - Repository name

  ## Validation Rules

  1. Terminal status requires commit_status
  2. Status/commit_status must be aligned
  3. committed requires commit_hash
  4. no_changes, no_commit, skipped require NULL hash
  5. failed requires error_type and error_message
  6. Running/terminal states require started_at
  7. Terminal states require completed_at
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(repo_result, attrs) do
    repo_result
    |> cast(attrs, [
      :prompt_step_run_id,
      :changeset_id,
      :repo_name,
      :repo_path,
      :status,
      :commit_hash,
      :commit_status,
      :branch_name,
      :pr_url,
      :files_changed,
      :insertions,
      :deletions,
      :error_message,
      :error_type,
      :started_at,
      :completed_at,
      :duration_ms
    ])
    |> validate_required([:prompt_step_run_id, :repo_name])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:commit_status, @valid_commit_statuses)
    |> validate_terminal_commit_status()
    |> validate_status_commit_status_alignment()
    |> validate_commit_hash_invariants()
    |> validate_failed_requires_error_details()
    |> validate_timing_constraints()
    |> unique_constraint([:prompt_step_run_id, :repo_name],
      name: :prompt_repo_results_prompt_step_run_id_repo_name_index,
      message: "has already been taken"
    )
    |> foreign_key_constraint(:prompt_step_run_id)
    |> foreign_key_constraint(:changeset_id)
  end

  # Terminal status requires commit_status
  defp validate_terminal_commit_status(changeset) do
    status = get_field(changeset, :status)
    commit_status = get_field(changeset, :commit_status)

    cond do
      status in @terminal_statuses and is_nil(commit_status) ->
        add_error(changeset, :commit_status, "is required for terminal status")

      status not in @terminal_statuses and not is_nil(commit_status) ->
        add_error(changeset, :commit_status, "must be nil for non-terminal status")

      true ->
        changeset
    end
  end

  # Status/commit_status alignment
  defp validate_status_commit_status_alignment(changeset) do
    status = get_field(changeset, :status)
    commit_status = get_field(changeset, :commit_status)

    valid_combinations = [
      {"pending", nil},
      {"running", nil},
      {"completed", "committed"},
      {"completed", "no_commit"},
      {"completed", "no_changes"},
      {"failed", "failed"},
      {"skipped", "skipped"}
    ]

    if {status, commit_status} in valid_combinations do
      changeset
    else
      # Only add error if we haven't already added one from terminal validation
      if changeset.errors[:commit_status] do
        changeset
      else
        add_error(changeset, :commit_status, "is not valid for status '#{status}'")
      end
    end
  end

  # Commit hash invariants
  defp validate_commit_hash_invariants(changeset) do
    commit_status = get_field(changeset, :commit_status)
    commit_hash = get_field(changeset, :commit_hash)

    cond do
      commit_status == "committed" and is_nil(commit_hash) ->
        add_error(changeset, :commit_hash, "is required when commit_status is 'committed'")

      commit_status in ["no_changes", "no_commit", "skipped"] and not is_nil(commit_hash) ->
        add_error(changeset, :commit_hash, "must be nil for commit_status '#{commit_status}'")

      true ->
        changeset
    end
  end

  # Failed requires error details
  defp validate_failed_requires_error_details(changeset) do
    status = get_field(changeset, :status)
    error_type = get_field(changeset, :error_type)
    error_message = get_field(changeset, :error_message)

    if status == "failed" do
      changeset =
        if is_nil(error_type) do
          add_error(changeset, :error_type, "is required when status is 'failed'")
        else
          changeset
        end

      if is_nil(error_message) do
        add_error(changeset, :error_message, "is required when status is 'failed'")
      else
        changeset
      end
    else
      changeset
    end
  end

  # Timing constraints
  defp validate_timing_constraints(changeset) do
    status = get_field(changeset, :status)
    started_at = get_field(changeset, :started_at)
    completed_at = get_field(changeset, :completed_at)

    changeset =
      if status != "pending" and is_nil(started_at) do
        add_error(changeset, :started_at, "is required for non-pending status")
      else
        changeset
      end

    if status in @terminal_statuses and is_nil(completed_at) do
      add_error(changeset, :completed_at, "is required for terminal status")
    else
      changeset
    end
  end
end
