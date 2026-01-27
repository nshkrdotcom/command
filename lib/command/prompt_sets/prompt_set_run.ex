defmodule Command.PromptSets.PromptSetRun do
  @moduledoc """
  Schema for prompt set execution instances.

  A prompt set run tracks the execution of a prompt set, including progress,
  timing, aggregate metrics, and error state.

  ## Status State Machine

  ```
  pending -> running -> completed (terminal)
                    |-> partial_success (resumable)
                    |-> failed (terminal)
                    |-> paused -> running
                    |           |-> aborted (terminal)
                    |-> aborted (terminal)
  pending -> aborted (terminal)
  ```

  Terminal states: completed, failed, aborted
  Resumable states: partial_success, paused

  ## Fields

  - `prompt_set_id` - Reference to the prompt set definition
  - `pipeline_run_id` - Optional reference to FlowStone pipeline run
  - `status` - Execution status
  - `current_prompt` - Currently executing prompt number
  - `last_completed_prompt` - Last successfully completed prompt
  - `branch_name` - Feature branch name (if branch strategy used)
  - `branch_strategy` - Branch strategy mode snapshot
  - `config_snapshot` - Config captured at execution time
  - `started_at` - When execution started
  - `completed_at` - When execution finished
  - `total_prompts` - Total number of prompts in the set
  - `completed_prompts` - Count of successfully completed prompts
  - `failed_prompts` - Count of failed prompts
  - `total_input_tokens` - Sum of input tokens across all steps
  - `total_output_tokens` - Sum of output tokens across all steps
  - `total_cost_usd` - Sum of costs across all steps
  - `error_summary` - Summary of errors if run failed
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          prompt_set_id: Ecto.UUID.t() | nil,
          pipeline_run_id: Ecto.UUID.t() | nil,
          status: String.t(),
          current_prompt: String.t() | nil,
          last_completed_prompt: String.t() | nil,
          branch_name: String.t() | nil,
          branch_strategy: String.t() | nil,
          config_snapshot: map(),
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          total_prompts: integer(),
          completed_prompts: integer(),
          failed_prompts: integer(),
          total_input_tokens: integer(),
          total_output_tokens: integer(),
          total_cost_usd: Decimal.t(),
          error_summary: String.t() | nil,
          prompt_set: Command.PromptSets.PromptSet.t() | Ecto.Association.NotLoaded.t(),
          pipeline_run: any() | Ecto.Association.NotLoaded.t(),
          step_runs: [Command.PromptSets.PromptStepRun.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_statuses [
    "pending",
    "running",
    "paused",
    "completed",
    "partial_success",
    "failed",
    "aborted"
  ]

  schema "prompt_set_runs" do
    belongs_to :prompt_set, Command.PromptSets.PromptSet
    belongs_to :pipeline_run, Command.Pipelines.Execution, foreign_key: :pipeline_run_id

    field :status, :string, default: "pending"
    field :current_prompt, :string
    field :last_completed_prompt, :string
    field :branch_name, :string
    field :branch_strategy, :string
    field :config_snapshot, :map, default: %{}
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :total_prompts, :integer, default: 0
    field :completed_prompts, :integer, default: 0
    field :failed_prompts, :integer, default: 0
    field :total_input_tokens, :integer, default: 0
    field :total_output_tokens, :integer, default: 0
    field :total_cost_usd, :decimal, default: Decimal.new(0)
    field :error_summary, :string

    has_many :step_runs, Command.PromptSets.PromptStepRun

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Creates a changeset for a prompt set run.

  ## Required Fields

  - `prompt_set_id` - Reference to the prompt set definition

  ## Optional Fields

  - `pipeline_run_id` - Reference to FlowStone pipeline run
  - `status` - Execution status (default: "pending")
  - `current_prompt` - Currently executing prompt number
  - `last_completed_prompt` - Last completed prompt number
  - `branch_name` - Feature branch name
  - `branch_strategy` - Branch strategy mode
  - `config_snapshot` - Configuration snapshot
  - `started_at` - Execution start time
  - `completed_at` - Execution completion time
  - `total_prompts` - Total prompts count
  - `completed_prompts` - Completed prompts count
  - `failed_prompts` - Failed prompts count
  - `total_input_tokens` - Aggregate input tokens
  - `total_output_tokens` - Aggregate output tokens
  - `total_cost_usd` - Aggregate cost
  - `error_summary` - Error summary text
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :prompt_set_id,
      :pipeline_run_id,
      :status,
      :current_prompt,
      :last_completed_prompt,
      :branch_name,
      :branch_strategy,
      :config_snapshot,
      :started_at,
      :completed_at,
      :total_prompts,
      :completed_prompts,
      :failed_prompts,
      :total_input_tokens,
      :total_output_tokens,
      :total_cost_usd,
      :error_summary
    ])
    |> validate_required([:prompt_set_id])
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:prompt_set_id)
    |> foreign_key_constraint(:pipeline_run_id)
  end
end
