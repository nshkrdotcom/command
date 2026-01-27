defmodule Command.PlanRuns do
  @moduledoc """
  Context for plan run persistence.
  """

  alias Command.Accounts.User
  alias Command.PlanRuns.PlanRun
  alias Command.Repo

  @doc """
  Creates a plan run.
  """
  @spec create_plan_run(User.t(), map()) :: {:ok, PlanRun.t()} | {:error, Ecto.Changeset.t()}
  def create_plan_run(%User{} = user, attrs) do
    attrs = Map.put(attrs, :user_id, user.id)

    %PlanRun{}
    |> PlanRun.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns a changeset for tracking plan run changes.
  """
  @spec change_plan_run(PlanRun.t(), map()) :: Ecto.Changeset.t()
  def change_plan_run(%PlanRun{} = plan_run, attrs \\ %{}) do
    PlanRun.changeset(plan_run, attrs)
  end
end
