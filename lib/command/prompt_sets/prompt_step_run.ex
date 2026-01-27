defmodule Command.PromptSets.PromptStepRun do
  @moduledoc """
  Schema for individual prompt step executions.

  A step run tracks the execution of a single prompt within a prompt set run,
  including provider details, token usage, cost, timing, and error state.

  ## Status State Machine

  ```
  pending -> running -> completed (terminal)
                    |-> partial_success (resumable)
                    |-> failed (terminal)
  pending -> skipped (terminal)
  ```

  Terminal states: completed, failed, skipped
  Resumable states: partial_success

  ## Commit Status Values

  - `committed` - Changes were committed (commit_hash required)
  - `no_commit` - Execution chose not to commit (no hash)
  - `no_changes` - No changes to commit (no hash)
  - `failed` - Commit attempt failed
  - `skipped` - Commit was skipped

  ## Fields

  - `prompt_set_run_id` - Reference to the parent run
  - `prompt_num` - Prompt number (e.g., "01", "02")
  - `status` - Execution status
  - `provider` - Provider used (claude, codex)
  - `model` - Model identifier
  - `commit_hash` - Git commit hash (single-repo legacy)
  - `commit_status` - Commit result status
  - `target_repo` - Target repository name (multi-repo, deprecated)
  - `commit_hashes` - Array of per-repo commit results (deprecated)
  - `input_tokens` - Input tokens consumed
  - `output_tokens` - Output tokens generated
  - `cost_usd` - Execution cost in USD
  - `duration_ms` - Execution duration in milliseconds
  - `log_artifact_id` - Reference to text log artifact
  - `events_artifact_id` - Reference to JSONL events artifact
  - `error_message` - Error message if failed
  - `error_type` - Error classification
  - `retry_count` - Number of retry attempts
  - `started_at` - When step started
  - `completed_at` - When step finished
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          prompt_set_run_id: Ecto.UUID.t() | nil,
          prompt_num: String.t() | nil,
          status: String.t(),
          provider: String.t() | nil,
          model: String.t() | nil,
          commit_hash: String.t() | nil,
          commit_status: String.t() | nil,
          target_repo: String.t() | nil,
          commit_hashes: list(map()),
          input_tokens: integer(),
          output_tokens: integer(),
          cost_usd: Decimal.t(),
          duration_ms: integer() | nil,
          log_artifact_id: Ecto.UUID.t() | nil,
          events_artifact_id: Ecto.UUID.t() | nil,
          error_message: String.t() | nil,
          error_type: String.t() | nil,
          retry_count: integer(),
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          prompt_set_run: Command.PromptSets.PromptSetRun.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_statuses ["pending", "running", "completed", "partial_success", "failed", "skipped"]
  @valid_commit_statuses [nil, "committed", "no_commit", "no_changes", "failed", "skipped"]

  schema "prompt_step_runs" do
    belongs_to :prompt_set_run, Command.PromptSets.PromptSetRun

    field :prompt_num, :string
    field :status, :string, default: "pending"
    field :provider, :string
    field :model, :string

    # Single-repo legacy fields
    field :commit_hash, :string
    field :commit_status, :string

    # Multi-repo fields (deprecated - use prompt_repo_results instead)
    field :target_repo, :string
    field :commit_hashes, {:array, :map}, default: []

    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :cost_usd, :decimal, default: Decimal.new(0)
    field :duration_ms, :integer
    field :log_artifact_id, :binary_id
    field :events_artifact_id, :binary_id
    field :error_message, :string
    field :error_type, :string
    field :retry_count, :integer, default: 0
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Creates a changeset for a prompt step run.

  ## Required Fields

  - `prompt_set_run_id` - Reference to the parent run
  - `prompt_num` - Prompt number

  ## Optional Fields

  See module documentation for full list of fields.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(step_run, attrs) do
    step_run
    |> cast(attrs, [
      :prompt_set_run_id,
      :prompt_num,
      :status,
      :provider,
      :model,
      :commit_hash,
      :commit_status,
      :target_repo,
      :commit_hashes,
      :input_tokens,
      :output_tokens,
      :cost_usd,
      :duration_ms,
      :log_artifact_id,
      :events_artifact_id,
      :error_message,
      :error_type,
      :retry_count,
      :started_at,
      :completed_at
    ])
    |> validate_required([:prompt_set_run_id, :prompt_num])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:commit_status, @valid_commit_statuses)
    |> unique_constraint([:prompt_set_run_id, :prompt_num],
      name: :prompt_step_runs_prompt_set_run_id_prompt_num_index,
      message: "has already been taken"
    )
    |> foreign_key_constraint(:prompt_set_run_id)
  end
end
