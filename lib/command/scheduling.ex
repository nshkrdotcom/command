defmodule Command.Scheduling do
  @moduledoc """
  The Scheduling context.

  Manages scheduled jobs for workflows, reindexing, and other tasks.
  """

  import Ecto.Query

  alias Command.Accounts.User
  alias Command.Repo
  alias Command.Scheduling.ScheduledJob

  @doc """
  Creates a scheduled job.
  """
  @spec create_scheduled_job(User.t(), map()) ::
          {:ok, ScheduledJob.t()} | {:error, Ecto.Changeset.t()}
  def create_scheduled_job(user, attrs) do
    attrs = Map.put(attrs, :user_id, user.id)

    %ScheduledJob{}
    |> ScheduledJob.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a scheduled job by ID.
  """
  @spec get_scheduled_job(Ecto.UUID.t()) :: ScheduledJob.t() | nil
  def get_scheduled_job(id), do: Repo.get(ScheduledJob, id)

  @doc """
  Updates a scheduled job.
  """
  @spec update_scheduled_job(ScheduledJob.t(), map()) ::
          {:ok, ScheduledJob.t()} | {:error, Ecto.Changeset.t()}
  def update_scheduled_job(job, attrs) do
    job
    |> ScheduledJob.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists scheduled jobs for a user.
  """
  @spec list_scheduled_jobs(User.t(), keyword()) :: [ScheduledJob.t()]
  def list_scheduled_jobs(user, opts \\ []) do
    ScheduledJob
    |> where([j], j.user_id == ^user.id)
    |> apply_job_filters(opts)
    |> order_by([j], asc: j.next_run_at)
    |> Repo.all()
  end

  @doc """
  Lists jobs due to run.
  """
  @spec list_due_jobs() :: [ScheduledJob.t()]
  def list_due_jobs do
    now = DateTime.utc_now()

    ScheduledJob
    |> where([j], j.status == "active")
    |> where([j], j.currently_running == false)
    |> where([j], j.next_run_at <= ^now)
    |> where([j], is_nil(j.expires_at) or j.expires_at > ^now)
    |> order_by([j], asc: j.next_run_at)
    |> Repo.all()
  end

  @doc """
  Starts a job run.
  """
  @spec start_job_run(ScheduledJob.t()) ::
          {:ok, ScheduledJob.t()} | {:error, Ecto.Changeset.t()}
  def start_job_run(job) do
    job
    |> ScheduledJob.run_start_changeset()
    |> Repo.update()
  end

  @doc """
  Records a successful job run.
  """
  @spec complete_job_run(ScheduledJob.t()) ::
          {:ok, ScheduledJob.t()} | {:error, Ecto.Changeset.t()}
  def complete_job_run(job) do
    job
    |> ScheduledJob.run_success_changeset()
    |> Repo.update()
  end

  @doc """
  Records a failed job run.
  """
  @spec fail_job_run(ScheduledJob.t(), String.t()) ::
          {:ok, ScheduledJob.t()} | {:error, Ecto.Changeset.t()}
  def fail_job_run(job, error) do
    job
    |> ScheduledJob.run_failure_changeset(%{last_run_error: error})
    |> Repo.update()
  end

  @doc """
  Pauses a scheduled job.
  """
  @spec pause_job(ScheduledJob.t()) :: {:ok, ScheduledJob.t()} | {:error, Ecto.Changeset.t()}
  def pause_job(job) do
    job
    |> ScheduledJob.status_changeset(%{status: "paused"})
    |> Repo.update()
  end

  @doc """
  Resumes a paused job.
  """
  @spec resume_job(ScheduledJob.t()) :: {:ok, ScheduledJob.t()} | {:error, Ecto.Changeset.t()}
  def resume_job(job) do
    job
    |> ScheduledJob.status_changeset(%{status: "active"})
    |> Repo.update()
  end

  @doc """
  Cancels a scheduled job.
  """
  @spec cancel_job(ScheduledJob.t()) :: {:ok, ScheduledJob.t()} | {:error, Ecto.Changeset.t()}
  def cancel_job(job) do
    job
    |> ScheduledJob.status_changeset(%{status: "cancelled"})
    |> Repo.update()
  end

  @doc """
  Deletes a scheduled job.
  """
  @spec delete_scheduled_job(ScheduledJob.t()) ::
          {:ok, ScheduledJob.t()} | {:error, Ecto.Changeset.t()}
  def delete_scheduled_job(job) do
    Repo.delete(job)
  end

  # Private helpers

  defp apply_job_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:status, status}, query ->
        where(query, [j], j.status == ^status)

      {:job_type, job_type}, query ->
        where(query, [j], j.job_type == ^job_type)

      {:limit, limit}, query ->
        limit(query, ^limit)

      _, query ->
        query
    end)
  end
end
