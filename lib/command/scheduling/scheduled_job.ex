defmodule Command.Scheduling.ScheduledJob do
  @moduledoc """
  Schema for scheduled job configurations.

  Supports one-time, cron, and interval scheduling for
  workflows, reindexing, and custom jobs.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          job_type: String.t() | nil,
          job_config: map() | nil,
          schedule_type: String.t() | nil,
          cron_expression: String.t() | nil,
          interval_seconds: integer() | nil,
          run_at: DateTime.t() | nil,
          timezone: String.t(),
          status: String.t(),
          last_run_at: DateTime.t() | nil,
          last_run_status: String.t() | nil,
          last_run_error: String.t() | nil,
          next_run_at: DateTime.t() | nil,
          run_count: integer(),
          success_count: integer(),
          failure_count: integer(),
          max_runs: integer() | nil,
          expires_at: DateTime.t() | nil,
          allow_concurrent: boolean(),
          currently_running: boolean(),
          retry_on_failure: boolean(),
          max_retries: integer(),
          retry_delay_seconds: integer(),
          notify_on_failure: boolean(),
          notify_on_success: boolean(),
          notification_channels: [String.t()],
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @job_types ~w(workflow reindex cleanup custom)
  @schedule_types ~w(once cron interval)
  @statuses ~w(active paused completed failed cancelled)

  schema "scheduled_jobs" do
    field :job_type, :string
    field :job_config, :map
    field :schedule_type, :string
    field :cron_expression, :string
    field :interval_seconds, :integer
    field :run_at, :utc_datetime_usec
    field :timezone, :string, default: "UTC"
    field :status, :string, default: "active"
    field :last_run_at, :utc_datetime_usec
    field :last_run_status, :string
    field :last_run_error, :string
    field :next_run_at, :utc_datetime_usec
    field :run_count, :integer, default: 0
    field :success_count, :integer, default: 0
    field :failure_count, :integer, default: 0
    field :max_runs, :integer
    field :expires_at, :utc_datetime_usec
    field :allow_concurrent, :boolean, default: false
    field :currently_running, :boolean, default: false
    field :retry_on_failure, :boolean, default: true
    field :max_retries, :integer, default: 3
    field :retry_delay_seconds, :integer, default: 60
    field :notify_on_failure, :boolean, default: true
    field :notify_on_success, :boolean, default: false
    field :notification_channels, {:array, :string}, default: []
    field :metadata, :map, default: %{}

    belongs_to :user, Command.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new scheduled job.
  """
  @spec create_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(job, attrs) do
    job
    |> cast(attrs, [
      :user_id,
      :job_type,
      :job_config,
      :schedule_type,
      :cron_expression,
      :interval_seconds,
      :run_at,
      :timezone,
      :max_runs,
      :expires_at,
      :allow_concurrent,
      :retry_on_failure,
      :max_retries,
      :retry_delay_seconds,
      :notify_on_failure,
      :notify_on_success,
      :notification_channels,
      :metadata
    ])
    |> validate_required([:user_id, :job_type, :job_config, :schedule_type])
    |> validate_inclusion(:job_type, @job_types)
    |> validate_inclusion(:schedule_type, @schedule_types)
    |> validate_schedule()
    |> calculate_next_run()
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for updating job configuration.
  """
  @spec update_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def update_changeset(job, attrs) do
    job
    |> cast(attrs, [
      :job_config,
      :cron_expression,
      :interval_seconds,
      :run_at,
      :timezone,
      :max_runs,
      :expires_at,
      :allow_concurrent,
      :retry_on_failure,
      :max_retries,
      :retry_delay_seconds,
      :notify_on_failure,
      :notify_on_success,
      :notification_channels,
      :metadata
    ])
    |> validate_schedule()
    |> calculate_next_run()
  end

  @doc """
  Changeset for updating job status.
  """
  @spec status_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def status_changeset(job, attrs) do
    job
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end

  @doc """
  Changeset for recording a job run start.
  """
  @spec run_start_changeset(t() | Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def run_start_changeset(job) do
    job
    |> change(%{currently_running: true})
  end

  @doc """
  Changeset for recording a successful job run.
  """
  @spec run_success_changeset(t() | Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def run_success_changeset(job) do
    job
    |> change(%{
      currently_running: false,
      last_run_at: DateTime.utc_now(),
      last_run_status: "success",
      last_run_error: nil,
      run_count: (job.run_count || 0) + 1,
      success_count: (job.success_count || 0) + 1
    })
    |> calculate_next_run()
    |> maybe_complete()
  end

  @doc """
  Changeset for recording a failed job run.
  """
  @spec run_failure_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def run_failure_changeset(job, attrs) do
    job
    |> cast(attrs, [:last_run_error])
    |> change(%{
      currently_running: false,
      last_run_at: DateTime.utc_now(),
      last_run_status: "failure",
      run_count: (job.run_count || 0) + 1,
      failure_count: (job.failure_count || 0) + 1
    })
    |> calculate_next_run()
    |> maybe_complete()
  end

  defp validate_schedule(changeset) do
    schedule_type = get_field(changeset, :schedule_type)

    case schedule_type do
      "cron" ->
        validate_required(changeset, [:cron_expression])

      "interval" ->
        changeset
        |> validate_required([:interval_seconds])
        |> validate_number(:interval_seconds, greater_than: 0)

      "once" ->
        validate_required(changeset, [:run_at])

      _ ->
        changeset
    end
  end

  defp calculate_next_run(changeset) do
    schedule_type = get_field(changeset, :schedule_type)

    next_run =
      case schedule_type do
        "once" ->
          get_field(changeset, :run_at)

        "interval" ->
          interval = get_field(changeset, :interval_seconds) || 60
          DateTime.add(DateTime.utc_now(), interval, :second)

        "cron" ->
          # In real implementation, would parse cron and calculate next run
          # For now, default to 1 hour from now
          DateTime.add(DateTime.utc_now(), 3600, :second)

        _ ->
          nil
      end

    put_change(changeset, :next_run_at, next_run)
  end

  defp maybe_complete(changeset) do
    max_runs = get_field(changeset, :max_runs)
    run_count = get_field(changeset, :run_count)
    schedule_type = get_field(changeset, :schedule_type)

    cond do
      schedule_type == "once" ->
        put_change(changeset, :status, "completed")

      max_runs && run_count >= max_runs ->
        put_change(changeset, :status, "completed")

      true ->
        changeset
    end
  end
end
