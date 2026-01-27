defmodule Command.PromptSets.PromptSet do
  @moduledoc """
  Schema for prompt set definitions.

  A prompt set defines a sequence of prompts to be executed in order, along with
  configuration for how they should be executed (target directories, models, tools, etc.).

  ## Fields

  - `name` - Human-readable name for the prompt set
  - `slug` - URL-safe unique identifier
  - `doc_set_id` - Optional reference to source document set
  - `doc_set_version` - Version of source document set
  - `prompts` - Array of prompt definitions (JSONB)
  - `commit_messages` - Map of prompt_num to commit message text
  - `phase_names` - Map of phase number to phase name
  - `config` - Execution configuration (JSONB)
  - `status` - Lifecycle status: active, archived, draft

  ## Prompt Definition Structure

  Each prompt in the `prompts` array contains:
  - `num` - Prompt number (e.g., "01", "02")
  - `phase` - Phase number
  - `sp` - Story points
  - `name` - Prompt name
  - `file` - Path to prompt file
  - `provider` - Optional provider override
  - `model` - Optional model override
  - `tools` - Optional tools list
  - `target_repos` - Optional list of target repository names
  - `execution_mode` - Optional: "per_repo" (default) or "workspace"
  - `permission_mode` - Optional permission mode override
  - `claude_opts` - Optional Claude-specific options
  - `codex_opts` - Optional Codex-specific options
  - `codex_thread_opts` - Optional Codex thread options

  ## Config Structure

  The `config` map contains:
  - `project_dir` - Legacy single-repo mode path
  - `target_repos` - Array of {name, path, default?} repository definitions
  - `prompts_dir` - Path to prompts directory
  - `log_dir` - Path to log directory
  - `default_model` - Default model to use
  - `default_provider` - Default provider (claude, codex)
  - `allowed_tools` - List of allowed tools
  - `permission_mode` - Default permission mode
  - `log_mode` - Logging mode
  - `log_meta` - Log metadata mode
  - `events_mode` - Events capture mode
  - `auto_commit` - Whether to auto-commit changes
  - `cost_ceiling_usd` - Maximum cost allowed
  - `workspace_root` - Shared workspace directory for workspace execution mode
  - `repo_groups` - Named groups of repositories
  - `branch_strategy` - Branch management configuration
  - `partial_success_policy` - Partial success handling policy
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          slug: String.t() | nil,
          doc_set_id: String.t() | nil,
          doc_set_version: String.t() | nil,
          prompts: list(map()),
          commit_messages: map(),
          phase_names: map(),
          config: map(),
          status: String.t(),
          runs: [Command.PromptSets.PromptSetRun.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_statuses ["active", "archived", "draft"]

  schema "prompt_sets" do
    field :name, :string
    field :slug, :string
    field :doc_set_id, :string
    field :doc_set_version, :string
    field :prompts, {:array, :map}, default: []
    field :commit_messages, :map, default: %{}
    field :phase_names, :map, default: %{}
    field :config, :map, default: %{}
    field :status, :string, default: "active"

    has_many :runs, Command.PromptSets.PromptSetRun

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Creates a changeset for a prompt set.

  ## Required Fields

  - `name` - Human-readable name
  - `slug` - URL-safe unique identifier

  ## Optional Fields

  - `doc_set_id` - Reference to source document set
  - `doc_set_version` - Version of source document set
  - `prompts` - Array of prompt definitions
  - `commit_messages` - Map of prompt numbers to commit messages
  - `phase_names` - Map of phase numbers to phase names
  - `config` - Execution configuration
  - `status` - Lifecycle status (default: "active")
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(prompt_set, attrs) do
    prompt_set
    |> cast(attrs, [
      :name,
      :slug,
      :doc_set_id,
      :doc_set_version,
      :prompts,
      :commit_messages,
      :phase_names,
      :config,
      :status
    ])
    |> validate_required([:name, :slug])
    |> unique_constraint(:slug)
    |> validate_inclusion(:status, @valid_statuses)
  end
end
