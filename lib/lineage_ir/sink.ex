defmodule LineageIR.Sink do
  @moduledoc """
  LineageIR sink for event ingestion.
  """

  alias LineageIR.{Artifact, Event, ProvenanceEdge, Span, Trace}

  @spec emit(Event.t(), keyword()) :: :ok | {:error, term()}
  def emit(%Event{} = event, opts \\ []) do
    event = normalize(event)

    with :ok <- validate(event),
         :ok <- adapter().write_event(event, opts) do
      write_payload(event, opts)
    end
  end

  @spec emit_many([Event.t()], keyword()) :: :ok | {:error, term()}
  def emit_many(events, opts \\ []) when is_list(events) do
    Enum.reduce_while(events, :ok, fn event, _acc ->
      case emit(event, opts) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  @spec normalize(Event.t()) :: Event.t()
  def normalize(%Event{} = event) do
    %Event{
      event
      | id: event.id || Ecto.UUID.generate(),
        type: normalize_type(event.type),
        source: normalize_string(event.source),
        source_ref: normalize_string(event.source_ref),
        occurred_at: event.occurred_at || DateTime.utc_now()
    }
  end

  defp normalize_type(nil), do: nil
  defp normalize_type(type) when is_atom(type), do: Atom.to_string(type)
  defp normalize_type(type) when is_binary(type), do: type
  defp normalize_type(type), do: to_string(type)

  defp normalize_string(nil), do: nil
  defp normalize_string(value) when is_binary(value), do: value
  defp normalize_string(value), do: to_string(value)

  defp validate(%Event{type: nil}), do: {:error, :missing_type}
  defp validate(%Event{trace_id: nil}), do: {:error, :missing_trace_id}
  defp validate(%Event{occurred_at: nil}), do: {:error, :missing_occurred_at}
  defp validate(_event), do: :ok

  defp write_payload(%Event{type: type, payload: %Trace{} = trace}, opts)
       when type in ["trace_start", "trace_end", "trace"] do
    adapter().write_trace(trace, opts)
  end

  defp write_payload(%Event{type: type, payload: %Span{} = span}, opts)
       when type in ["span_start", "span_end", "span"] do
    adapter().write_span(span, opts)
  end

  defp write_payload(%Event{type: "artifact", payload: %Artifact{} = artifact}, opts) do
    adapter().write_artifact(artifact, opts)
  end

  defp write_payload(%Event{type: "edge", payload: %ProvenanceEdge{} = edge}, opts) do
    adapter().write_edge(edge, opts)
  end

  defp write_payload(_event, _opts), do: :ok

  defp adapter do
    Application.get_env(:command, LineageIR.Sink, [])
    |> Keyword.get(:adapter, LineageIR.Sink.Adapters.Ecto)
  end
end
