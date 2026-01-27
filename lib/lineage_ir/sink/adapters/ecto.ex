defmodule LineageIR.Sink.Adapters.Ecto do
  @moduledoc """
  Ecto-backed LineageIR sink adapter using Command.Repo.
  """

  @behaviour LineageIR.Sink.Adapter

  alias LineageIR.{Artifact, Event, EventRecord, ProvenanceEdge, Span, Trace}

  @impl true
  def write_event(%Event{} = event, opts) do
    attrs = %{
      id: event.id,
      trace_id: event.trace_id,
      span_id: event.span_id,
      event_type: event.type,
      occurred_at: event.occurred_at,
      source: event.source,
      source_ref: event.source_ref,
      payload: payload_map(event.payload)
    }

    %EventRecord{}
    |> EventRecord.changeset(attrs)
    |> repo(opts).insert(on_conflict: :nothing, conflict_target: :id)
    |> normalize_write()
  end

  @impl true
  def write_trace(%Trace{} = trace, opts) do
    trace
    |> Trace.changeset(struct_to_attrs(trace))
    |> repo(opts).insert(
      on_conflict: {:replace, trace_upsert_fields()},
      conflict_target: :id
    )
    |> normalize_write()
  end

  @impl true
  def write_span(%Span{} = span, opts) do
    span
    |> Span.changeset(struct_to_attrs(span))
    |> repo(opts).insert(
      on_conflict: {:replace, span_upsert_fields()},
      conflict_target: :id
    )
    |> normalize_write()
  end

  @impl true
  def write_artifact(%Artifact{} = artifact, opts) do
    %Artifact{}
    |> Artifact.changeset(struct_to_attrs(artifact))
    |> repo(opts).insert(on_conflict: :nothing, conflict_target: :id)
    |> normalize_write()
  end

  @impl true
  def write_edge(%ProvenanceEdge{} = edge, opts) do
    %ProvenanceEdge{}
    |> ProvenanceEdge.changeset(struct_to_attrs(edge))
    |> repo(opts).insert(on_conflict: :nothing, conflict_target: :id)
    |> normalize_write()
  end

  defp repo(opts) do
    Keyword.get(opts, :repo, Command.Repo)
  end

  defp normalize_write({:ok, _}), do: :ok
  defp normalize_write({:error, reason}), do: {:error, reason}

  defp payload_map(nil), do: nil

  defp payload_map(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.drop([:__meta__])
  end

  defp payload_map(%{} = map), do: map

  defp struct_to_attrs(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.drop([:__meta__])
  end

  defp trace_upsert_fields do
    [
      :root_trace_id,
      :parent_trace_id,
      :run_id,
      :work_id,
      :origin,
      :origin_ref,
      :status,
      :attributes,
      :started_at,
      :finished_at,
      :updated_at
    ]
  end

  defp span_upsert_fields do
    [
      :trace_id,
      :parent_span_id,
      :run_id,
      :step_id,
      :work_id,
      :name,
      :kind,
      :status,
      :attributes,
      :metrics,
      :error_type,
      :error_message,
      :error_details,
      :started_at,
      :finished_at,
      :updated_at
    ]
  end
end
