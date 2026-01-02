defmodule Command.Workflows.Workflow do
  @moduledoc """
  Schema for workflow definitions.

  Workflows are reusable DAGs of steps that chain agent calls,
  RAG queries, shell commands, and approval gates.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          slug: String.t() | nil,
          description: String.t() | nil,
          version: integer(),
          status: String.t(),
          is_template: boolean(),
          forked_from_id: Ecto.UUID.t() | nil,
          steps: [map()],
          input_schema: map(),
          output_schema: map(),
          default_config: map(),
          triggers: [map()],
          run_count: integer(),
          success_count: integer(),
          failure_count: integer(),
          avg_duration_ms: integer() | nil,
          avg_cost_cents: integer() | nil,
          tags: [String.t()],
          category: String.t() | nil,
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(draft active deprecated archived)
  @categories ~w(code_review refactor documentation testing deployment custom)

  schema "workflows" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :version, :integer, default: 1
    field :status, :string, default: "draft"
    field :is_template, :boolean, default: false
    field :steps, {:array, :map}, default: []
    field :input_schema, :map, default: %{}
    field :output_schema, :map, default: %{}
    field :default_config, :map, default: %{}
    field :triggers, {:array, :map}, default: []
    field :run_count, :integer, default: 0
    field :success_count, :integer, default: 0
    field :failure_count, :integer, default: 0
    field :avg_duration_ms, :integer
    field :avg_cost_cents, :integer
    field :tags, {:array, :string}, default: []
    field :category, :string
    field :metadata, :map, default: %{}

    belongs_to :user, Command.Accounts.User
    belongs_to :forked_from, Command.Workflows.Workflow

    has_many :runs, Command.Workflows.WorkflowRun
    has_many :forks, Command.Workflows.Workflow, foreign_key: :forked_from_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new workflow.
  """
  @spec create_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(workflow, attrs) do
    workflow
    |> cast(attrs, [
      :user_id,
      :name,
      :slug,
      :description,
      :is_template,
      :forked_from_id,
      :steps,
      :input_schema,
      :output_schema,
      :default_config,
      :triggers,
      :tags,
      :category,
      :metadata
    ])
    |> validate_required([:user_id, :name, :slug])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_length(:slug, min: 1, max: 100)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/,
      message: "must be lowercase alphanumeric with dashes"
    )
    |> validate_inclusion(:category, @categories ++ [nil])
    |> validate_steps()
    |> unique_constraint([:user_id, :slug])
  end

  @doc """
  Changeset for updating workflow definition.
  """
  @spec update_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def update_changeset(workflow, attrs) do
    workflow
    |> cast(attrs, [
      :name,
      :description,
      :steps,
      :input_schema,
      :output_schema,
      :default_config,
      :triggers,
      :tags,
      :category,
      :metadata
    ])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_inclusion(:category, @categories ++ [nil])
    |> validate_steps()
    |> increment_version()
  end

  @doc """
  Changeset for updating workflow status.
  """
  @spec status_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def status_changeset(workflow, attrs) do
    workflow
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end

  @doc """
  Changeset for updating workflow stats.
  """
  @spec stats_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def stats_changeset(workflow, attrs) do
    workflow
    |> cast(attrs, [
      :run_count,
      :success_count,
      :failure_count,
      :avg_duration_ms,
      :avg_cost_cents
    ])
  end

  defp validate_steps(changeset) do
    case get_field(changeset, :steps) do
      nil ->
        changeset

      steps when is_list(steps) ->
        if Enum.all?(steps, &valid_step?/1) do
          changeset
        else
          add_error(changeset, :steps, "contains invalid step definitions")
        end

      _ ->
        add_error(changeset, :steps, "must be a list")
    end
  end

  defp valid_step?(step) when is_map(step) do
    Map.has_key?(step, "id") || Map.has_key?(step, :id)
  end

  defp valid_step?(_), do: false

  defp increment_version(changeset) do
    case get_field(changeset, :version) do
      nil -> put_change(changeset, :version, 1)
      v -> put_change(changeset, :version, v + 1)
    end
  end
end
