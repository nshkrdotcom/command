defmodule Command.RunIndex do
  @moduledoc """
  Context for RunIndex persistence.
  """

  alias Command.Repo
  alias Command.RunIndex.{Run, Step}

  @doc """
  Creates a run index entry.
  """
  @spec create_run(map()) :: {:ok, Run.t()} | {:error, Ecto.Changeset.t()}
  def create_run(attrs) when is_map(attrs) do
    %Run{}
    |> Run.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a run index step entry.
  """
  @spec create_step(map()) :: {:ok, Step.t()} | {:error, Ecto.Changeset.t()}
  def create_step(attrs) when is_map(attrs) do
    %Step{}
    |> Step.changeset(attrs)
    |> Repo.insert()
  end
end
