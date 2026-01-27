defmodule Command.Lineage.Edges do
  @moduledoc """
  Record and query provenance edges for lineage tracking.

  Provenance edges form a directed graph connecting artifacts, runs, steps,
  requirements, and other entities. This module provides functions to:

  - Record individual edges
  - Batch record multiple edges transactionally
  - Query edges by source, target, or relationship type

  ## Example

      # Record a simple edge
      source = %{type: "artifact", id: artifact_id}
      target = %{type: "run", id: run_id}
      Edges.record(source, target, "created_by", %{})

      # Batch record edges
      edges = [
        {source1, target1, "created_by", %{}},
        {source2, target2, "implements", %{}}
      ]
      Edges.record_batch(edges)

      # Query edges
      Edges.query_by_source("artifact", artifact_id)
      Edges.query_by_target("run", run_id)
      Edges.query_by_relationship("created_by")
  """

  import Ecto.Query
  alias Command.Lineage.ProvenanceEdge
  alias Command.Repo

  @relationships ~w(
    implements created_by step_of input_to output_of
    triggered_by released_in derives_from prompt_in
    response_from diff_for
  )

  @doc """
  Record a provenance edge.

  Creates an edge from source to target with the specified relationship type.
  Uses upsert behavior - duplicate edges are ignored.

  ## Parameters

  - `source` - Map with `:type` and `:id` keys
  - `target` - Map with `:type` and `:id` keys
  - `relationship` - One of the valid relationship types (see `@relationships`)
  - `metadata` - Optional metadata map (default: `%{}`)

  ## Examples

      iex> source = %{type: "artifact", id: "abc-123"}
      iex> target = %{type: "run", id: "def-456"}
      iex> Edges.record(source, target, "created_by", %{})
      {:ok, %ProvenanceEdge{}}
  """
  @spec record(map(), map(), String.t(), map()) ::
          {:ok, ProvenanceEdge.t()} | {:error, Ecto.Changeset.t()}
  def record(source, target, relationship, metadata \\ %{}) do
    attrs = %{
      source_type: source.type,
      source_id: to_string(source.id),
      target_type: target.type,
      target_id: to_string(target.id),
      relationship: relationship,
      metadata: metadata
    }

    %ProvenanceEdge{}
    |> ProvenanceEdge.changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [
        :source_type,
        :source_id,
        :target_type,
        :target_id,
        :relationship
      ]
    )
  end

  @doc """
  Record multiple edges in a transaction.

  All edges are recorded atomically - if any edge fails, the entire batch
  is rolled back.

  ## Parameters

  - `edges` - List of `{source, target, relationship, metadata}` tuples

  ## Examples

      iex> edges = [
      ...>   {%{type: "artifact", id: "a1"}, %{type: "run", id: "r1"}, "created_by", %{}},
      ...>   {%{type: "step", id: "s1"}, %{type: "run", id: "r1"}, "step_of", %{}}
      ...> ]
      iex> Edges.record_batch(edges)
      {:ok, :batch_recorded}
  """
  @spec record_batch([{map(), map(), String.t(), map()}]) ::
          {:ok, :batch_recorded} | {:error, term()}
  def record_batch(edges) do
    Repo.transaction(fn ->
      Enum.each(edges, &record_or_rollback/1)
      :batch_recorded
    end)
  end

  defp record_or_rollback({source, target, rel, meta}) do
    case record(source, target, rel, meta) do
      {:ok, _} -> :ok
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @doc """
  Record artifact creation edge.

  Creates an edge from artifact to run with the "created_by" relationship.
  Optionally includes step_id in metadata.

  ## Examples

      iex> Edges.record_created_by("artifact-123", "run-456")
      {:ok, %ProvenanceEdge{}}

      iex> Edges.record_created_by("artifact-123", "run-456", "step-789")
      {:ok, %ProvenanceEdge{metadata: %{"step_id" => "step-789"}}}
  """
  @spec record_created_by(String.t(), String.t(), String.t() | nil) ::
          {:ok, ProvenanceEdge.t()} | {:error, Ecto.Changeset.t()}
  def record_created_by(artifact_id, run_id, step_id \\ nil) do
    source = %{type: "artifact", id: artifact_id}
    target = %{type: "run", id: run_id}
    metadata = if step_id, do: %{"step_id" => step_id}, else: %{}

    record(source, target, "created_by", metadata)
  end

  @doc """
  Record prompt step artifacts.

  Records edges for prompt, response, and diff artifacts associated with
  a prompt step run.

  ## Parameters

  - `prompt_step_run_id` - ID of the prompt step run
  - `opts` - Keyword list with optional artifact IDs:
    - `:prompt_artifact_id`
    - `:response_artifact_id`
    - `:diff_artifact_id`

  ## Examples

      iex> Edges.record_prompt_step_artifacts("step-123", %{
      ...>   prompt_artifact_id: "prompt-456",
      ...>   response_artifact_id: "response-789",
      ...>   diff_artifact_id: "diff-012"
      ...> })
      {:ok, :batch_recorded}
  """
  @spec record_prompt_step_artifacts(String.t(), map()) ::
          {:ok, :batch_recorded} | {:error, term()}
  def record_prompt_step_artifacts(prompt_step_run_id, opts) do
    step_ref = %{type: "prompt_step_run", id: prompt_step_run_id}

    edges = []

    edges =
      if opts[:prompt_artifact_id] do
        prompt_ref = %{type: "artifact", id: opts[:prompt_artifact_id]}
        [{prompt_ref, step_ref, "prompt_in", %{}} | edges]
      else
        edges
      end

    edges =
      if opts[:response_artifact_id] do
        response_ref = %{type: "artifact", id: opts[:response_artifact_id]}
        [{step_ref, response_ref, "response_from", %{}} | edges]
      else
        edges
      end

    edges =
      if opts[:diff_artifact_id] do
        diff_ref = %{type: "artifact", id: opts[:diff_artifact_id]}
        [{diff_ref, step_ref, "diff_for", %{}} | edges]
      else
        edges
      end

    record_batch(edges)
  end

  @doc """
  Query edges by source.

  Returns all edges originating from the specified source type and ID.

  ## Examples

      iex> Edges.query_by_source("artifact", "artifact-123")
      [%ProvenanceEdge{}, ...]
  """
  @spec query_by_source(String.t(), String.t()) :: [ProvenanceEdge.t()]
  def query_by_source(source_type, source_id) do
    from(e in ProvenanceEdge,
      where: e.source_type == ^source_type and e.source_id == ^source_id
    )
    |> Repo.all()
  end

  @doc """
  Query edges by target.

  Returns all edges pointing to the specified target type and ID.

  ## Examples

      iex> Edges.query_by_target("run", "run-123")
      [%ProvenanceEdge{}, ...]
  """
  @spec query_by_target(String.t(), String.t()) :: [ProvenanceEdge.t()]
  def query_by_target(target_type, target_id) do
    from(e in ProvenanceEdge,
      where: e.target_type == ^target_type and e.target_id == ^target_id
    )
    |> Repo.all()
  end

  @doc """
  Query edges by relationship.

  Returns all edges of the specified relationship type.

  ## Examples

      iex> Edges.query_by_relationship("created_by")
      [%ProvenanceEdge{}, ...]
  """
  @spec query_by_relationship(String.t()) :: [ProvenanceEdge.t()]
  def query_by_relationship(relationship) do
    from(e in ProvenanceEdge,
      where: e.relationship == ^relationship
    )
    |> Repo.all()
  end
end
