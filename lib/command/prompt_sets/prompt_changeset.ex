defmodule Command.PromptSets.PromptChangeset do
  @moduledoc """
  Schema for tracking atomic units of related multi-repo changes.

  A changeset binds together all changes from a prompt or prompt set execution,
  enabling atomic rollback, summary generation, and coordinated PR management.

  ## Scope Types

  - `prompt` - Changes from a single prompt execution across repos
  - `run` - Aggregated changes from an entire prompt set run
  - `workspace` - Cross-run changes (future use)

  ## Scope-FK Invariants

  - `scope='prompt'`: `prompt_step_run_id` MUST be set
  - `scope='run'`: `prompt_set_run_id` MUST be set, `prompt_step_run_id` MUST be NULL
  - `scope='workspace'`: Both FKs MUST be NULL

  ## Hierarchy

  - Prompt-level changesets can have a `parent_changeset_id` pointing to a run-level changeset
  - Run-level status and counters are derived by rolling up child prompt changesets

  ## Status Values

  - `pending` - Not yet started
  - `in_progress` - Currently executing
  - `completed` - All repos completed successfully (terminal)
  - `partial_success` - Mix of completed and failed repos (resumable)
  - `failed` - Failed per policy (terminal)
  - `rolled_back` - Changes were reverted (terminal)

  ## Fields

  - `scope` - Changeset scope: prompt, run, or workspace
  - `prompt_set_run_id` - Reference to run (for run-level changesets)
  - `prompt_step_run_id` - Reference to step (for prompt-level changesets)
  - `parent_changeset_id` - Reference to parent changeset (hierarchy)
  - `name` - Optional changeset name
  - `description` - Optional description
  - `status` - Changeset status
  - `repos_total` - Total number of target repositories
  - `repos_completed` - Completed repo count (cached counter)
  - `repos_failed` - Failed repo count (cached counter)
  - `branch_name` - Feature branch name
  - `pr_urls` - Array of PR URLs (informational)
  - `summary` - LLM-generated summary (optional)
  - `summary_generated_at` - When summary was generated
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          scope: String.t(),
          prompt_set_run_id: Ecto.UUID.t() | nil,
          prompt_step_run_id: Ecto.UUID.t() | nil,
          parent_changeset_id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          status: String.t(),
          repos_total: integer(),
          repos_completed: integer(),
          repos_failed: integer(),
          branch_name: String.t() | nil,
          pr_urls: list(String.t()),
          summary: String.t() | nil,
          summary_generated_at: DateTime.t() | nil,
          prompt_set_run: Command.PromptSets.PromptSetRun.t() | Ecto.Association.NotLoaded.t(),
          prompt_step_run: Command.PromptSets.PromptStepRun.t() | Ecto.Association.NotLoaded.t(),
          parent_changeset: t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_scopes ["prompt", "run", "workspace"]
  @valid_statuses [
    "pending",
    "in_progress",
    "completed",
    "partial_success",
    "failed",
    "rolled_back"
  ]

  schema "prompt_changesets" do
    field :scope, :string, default: "prompt"
    field :name, :string
    field :description, :string
    field :status, :string, default: "pending"
    field :repos_total, :integer, default: 0
    field :repos_completed, :integer, default: 0
    field :repos_failed, :integer, default: 0
    field :branch_name, :string
    field :pr_urls, {:array, :string}, default: []
    field :summary, :string
    field :summary_generated_at, :utc_datetime_usec

    belongs_to :prompt_set_run, Command.PromptSets.PromptSetRun
    belongs_to :prompt_step_run, Command.PromptSets.PromptStepRun
    belongs_to :parent_changeset, __MODULE__

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Creates a changeset for a prompt changeset record.

  ## Scope Requirements

  - `scope='prompt'`: `prompt_step_run_id` required
  - `scope='run'`: `prompt_set_run_id` required, `prompt_step_run_id` must be nil
  - `scope='workspace'`: Both FKs must be nil

  ## Optional Fields

  - `parent_changeset_id` - Reference to parent changeset
  - `name` - Changeset name
  - `description` - Description text
  - `status` - Changeset status
  - `repos_total`, `repos_completed`, `repos_failed` - Cached counters
  - `branch_name` - Feature branch name
  - `pr_urls` - Array of PR URLs
  - `summary` - Generated summary
  - `summary_generated_at` - Summary generation timestamp
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(prompt_changeset, attrs) do
    prompt_changeset
    |> cast(attrs, [
      :scope,
      :prompt_set_run_id,
      :prompt_step_run_id,
      :parent_changeset_id,
      :name,
      :description,
      :status,
      :repos_total,
      :repos_completed,
      :repos_failed,
      :branch_name,
      :pr_urls,
      :summary,
      :summary_generated_at
    ])
    |> validate_inclusion(:scope, @valid_scopes)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_scope_fk_invariants()
    |> foreign_key_constraint(:prompt_set_run_id)
    |> foreign_key_constraint(:prompt_step_run_id)
    |> foreign_key_constraint(:parent_changeset_id)
    |> unique_constraint(:prompt_set_run_id,
      name: :idx_prompt_changesets_unique_run,
      message: "already has a run-level changeset"
    )
    |> unique_constraint(:prompt_step_run_id,
      name: :idx_prompt_changesets_unique_step,
      message: "already has a prompt-level changeset"
    )
  end

  # Validates scope-FK invariants at the application level
  defp validate_scope_fk_invariants(changeset) do
    scope = get_field(changeset, :scope)
    step_run_id = get_field(changeset, :prompt_step_run_id)
    run_id = get_field(changeset, :prompt_set_run_id)

    case scope do
      "prompt" ->
        if is_nil(step_run_id) do
          add_error(changeset, :prompt_step_run_id, "is required for prompt scope")
        else
          changeset
        end

      "run" ->
        changeset =
          if is_nil(run_id) do
            add_error(changeset, :prompt_set_run_id, "is required for run scope")
          else
            changeset
          end

        if not is_nil(step_run_id) do
          add_error(changeset, :prompt_step_run_id, "must be nil for run scope")
        else
          changeset
        end

      "workspace" ->
        changeset =
          if not is_nil(run_id) do
            add_error(changeset, :prompt_set_run_id, "must be nil for workspace scope")
          else
            changeset
          end

        if not is_nil(step_run_id) do
          add_error(changeset, :prompt_step_run_id, "must be nil for workspace scope")
        else
          changeset
        end

      _ ->
        changeset
    end
  end
end
