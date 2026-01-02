defmodule Command.Workflows do
  @moduledoc """
  The Workflows context.

  Manages workflow definitions and executions.
  """

  import Ecto.Query

  alias Command.Accounts.User
  alias Command.Repo
  alias Command.Workflows.{Workflow, WorkflowRun, WorkflowStep}

  # Workflows

  @doc """
  Creates a workflow.
  """
  @spec create_workflow(User.t(), map()) :: {:ok, Workflow.t()} | {:error, Ecto.Changeset.t()}
  def create_workflow(user, attrs) do
    attrs = Map.put(attrs, :user_id, user.id)

    %Workflow{}
    |> Workflow.create_changeset(attrs)
    |> Repo.insert()
    |> broadcast_workflow_change(:workflow_created)
  end

  @doc """
  Returns a changeset for tracking workflow changes.

  ## Examples

      iex> change_workflow(workflow)
      %Ecto.Changeset{data: %Workflow{}}

      iex> change_workflow(workflow, %{name: "New Name"})
      %Ecto.Changeset{data: %Workflow{}}
  """
  @spec change_workflow(Workflow.t(), map()) :: Ecto.Changeset.t()
  def change_workflow(%Workflow{} = workflow, attrs \\ %{}) do
    Workflow.create_changeset(workflow, attrs)
  end

  @doc """
  Gets a workflow by ID.
  """
  @spec get_workflow(Ecto.UUID.t()) :: Workflow.t() | nil
  def get_workflow(id), do: Repo.get(Workflow, id)

  @doc """
  Gets a workflow by slug for a user.
  """
  @spec get_workflow_by_slug(User.t(), String.t()) :: Workflow.t() | nil
  def get_workflow_by_slug(user, slug) do
    Repo.get_by(Workflow, user_id: user.id, slug: slug)
  end

  @doc """
  Updates a workflow.
  """
  @spec update_workflow(Workflow.t(), map()) ::
          {:ok, Workflow.t()} | {:error, Ecto.Changeset.t()}
  def update_workflow(workflow, attrs) do
    workflow
    |> Workflow.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists workflows for a user.
  """
  @spec list_workflows(User.t(), keyword()) :: [Workflow.t()]
  def list_workflows(user, opts \\ []) do
    Workflow
    |> where([w], w.user_id == ^user.id)
    |> apply_workflow_filters(opts)
    |> order_by([w], desc: w.updated_at)
    |> Repo.all()
  end

  @doc """
  Activates a workflow.
  """
  @spec activate_workflow(Workflow.t()) :: {:ok, Workflow.t()} | {:error, Ecto.Changeset.t()}
  def activate_workflow(workflow) do
    workflow
    |> Workflow.status_changeset(%{status: "active"})
    |> Repo.update()
  end

  # Workflow Runs

  @doc """
  Starts a workflow run.
  """
  @spec start_workflow_run(Workflow.t(), User.t(), map()) ::
          {:ok, WorkflowRun.t()} | {:error, Ecto.Changeset.t()}
  def start_workflow_run(workflow, user, attrs \\ %{}) do
    snapshot = %{
      id: workflow.id,
      name: workflow.name,
      version: workflow.version,
      steps: workflow.steps
    }

    attrs =
      attrs
      |> Map.put(:workflow_id, workflow.id)
      |> Map.put(:user_id, user.id)
      |> Map.put(:workflow_snapshot, snapshot)

    %WorkflowRun{}
    |> WorkflowRun.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns a changeset for tracking workflow run changes.

  ## Examples

      iex> change_workflow_run(run)
      %Ecto.Changeset{data: %WorkflowRun{}}

      iex> change_workflow_run(run, %{trigger_type: "manual"})
      %Ecto.Changeset{data: %WorkflowRun{}}
  """
  @spec change_workflow_run(WorkflowRun.t(), map()) :: Ecto.Changeset.t()
  def change_workflow_run(%WorkflowRun{} = run, attrs \\ %{}) do
    WorkflowRun.create_changeset(run, attrs)
  end

  @doc """
  Gets a workflow run by ID.
  """
  @spec get_workflow_run(Ecto.UUID.t()) :: WorkflowRun.t() | nil
  def get_workflow_run(id), do: Repo.get(WorkflowRun, id)

  @doc """
  Starts execution of a workflow run.
  """
  @spec begin_workflow_run(WorkflowRun.t(), map()) ::
          {:ok, WorkflowRun.t()} | {:error, Ecto.Changeset.t()}
  def begin_workflow_run(run, attrs \\ %{}) do
    run
    |> WorkflowRun.start_changeset(attrs)
    |> Repo.update()
    |> broadcast_workflow_run_change(:workflow_run_started)
  end

  @doc """
  Completes a workflow run successfully.
  """
  @spec complete_workflow_run(WorkflowRun.t(), map()) ::
          {:ok, WorkflowRun.t()} | {:error, Ecto.Changeset.t()}
  def complete_workflow_run(run, attrs) do
    run
    |> WorkflowRun.complete_changeset(attrs)
    |> Repo.update()
    |> broadcast_workflow_run_change(:workflow_run_completed)
  end

  @doc """
  Fails a workflow run.
  """
  @spec fail_workflow_run(WorkflowRun.t(), map()) ::
          {:ok, WorkflowRun.t()} | {:error, Ecto.Changeset.t()}
  def fail_workflow_run(run, attrs) do
    run
    |> WorkflowRun.failure_changeset(attrs)
    |> Repo.update()
    |> broadcast_workflow_run_change(:workflow_run_failed)
  end

  @doc """
  Lists workflow runs.
  """
  @spec list_workflow_runs(Workflow.t(), keyword()) :: [WorkflowRun.t()]
  def list_workflow_runs(workflow, opts \\ []) do
    WorkflowRun
    |> where([r], r.workflow_id == ^workflow.id)
    |> apply_run_filters(opts)
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
  end

  # Workflow Steps

  @doc """
  Creates a workflow step.
  """
  @spec create_workflow_step(WorkflowRun.t(), map()) ::
          {:ok, WorkflowStep.t()} | {:error, Ecto.Changeset.t()}
  def create_workflow_step(run, attrs) do
    attrs = Map.put(attrs, :workflow_run_id, run.id)

    %WorkflowStep{}
    |> WorkflowStep.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns a changeset for tracking workflow step changes.

  ## Examples

      iex> change_workflow_step(step)
      %Ecto.Changeset{data: %WorkflowStep{}}

      iex> change_workflow_step(step, %{step_name: "Fetch data"})
      %Ecto.Changeset{data: %WorkflowStep{}}
  """
  @spec change_workflow_step(WorkflowStep.t(), map()) :: Ecto.Changeset.t()
  def change_workflow_step(%WorkflowStep{} = step, attrs \\ %{}) do
    WorkflowStep.create_changeset(step, attrs)
  end

  @doc """
  Gets a workflow step by ID.
  """
  @spec get_workflow_step(Ecto.UUID.t()) :: WorkflowStep.t() | nil
  def get_workflow_step(id), do: Repo.get(WorkflowStep, id)

  @doc """
  Starts a workflow step.
  """
  @spec start_workflow_step(WorkflowStep.t(), map()) ::
          {:ok, WorkflowStep.t()} | {:error, Ecto.Changeset.t()}
  def start_workflow_step(step, attrs \\ %{}) do
    step
    |> WorkflowStep.start_changeset(attrs)
    |> Repo.update()
    |> broadcast_workflow_step_change(:workflow_step_started)
  end

  @doc """
  Completes a workflow step.
  """
  @spec complete_workflow_step(WorkflowStep.t(), map()) ::
          {:ok, WorkflowStep.t()} | {:error, Ecto.Changeset.t()}
  def complete_workflow_step(step, attrs) do
    step
    |> WorkflowStep.complete_changeset(attrs)
    |> Repo.update()
    |> broadcast_workflow_step_change(:workflow_step_completed)
  end

  @doc """
  Fails a workflow step.
  """
  @spec fail_workflow_step(WorkflowStep.t(), map()) ::
          {:ok, WorkflowStep.t()} | {:error, Ecto.Changeset.t()}
  def fail_workflow_step(step, attrs) do
    step
    |> WorkflowStep.failure_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists steps for a workflow run.
  """
  @spec list_workflow_steps(WorkflowRun.t()) :: [WorkflowStep.t()]
  def list_workflow_steps(run) do
    WorkflowStep
    |> where([s], s.workflow_run_id == ^run.id)
    |> order_by([s], asc: s.sequence)
    |> Repo.all()
  end

  # Private helpers

  defp broadcast_workflow_change(result, event) do
    case result do
      {:ok, workflow} = success ->
        _ = Command.PubSub.broadcast("workflow:#{workflow.id}", event, workflow)
        _ = Command.PubSub.broadcast("user:#{workflow.user_id}:workflows", event, workflow)
        success

      error ->
        error
    end
  end

  defp broadcast_workflow_run_change(result, event) do
    case result do
      {:ok, run} = success ->
        _ = Command.PubSub.broadcast("workflow:#{run.workflow_id}:runs", event, run)
        _ = Command.PubSub.broadcast("workflow_run:#{run.id}", event, run)
        success

      error ->
        error
    end
  end

  defp broadcast_workflow_step_change(result, event) do
    case result do
      {:ok, step} = success ->
        _ = Command.PubSub.broadcast("workflow_run:#{step.workflow_run_id}:steps", event, step)
        success

      error ->
        error
    end
  end

  defp apply_workflow_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:status, status}, query ->
        where(query, [w], w.status == ^status)

      {:category, category}, query ->
        where(query, [w], w.category == ^category)

      {:is_template, true}, query ->
        where(query, [w], w.is_template == true)

      {:limit, limit}, query ->
        limit(query, ^limit)

      _, query ->
        query
    end)
  end

  defp apply_run_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:status, status}, query ->
        where(query, [r], r.status == ^status)

      {:limit, limit}, query ->
        limit(query, ^limit)

      _, query ->
        query
    end)
  end
end
