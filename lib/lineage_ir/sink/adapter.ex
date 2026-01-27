defmodule LineageIR.Sink.Adapter do
  @moduledoc """
  Behaviour for lineage sink adapters.
  """

  @callback write_event(LineageIR.Event.t(), keyword()) :: :ok | {:error, term()}
  @callback write_trace(LineageIR.Trace.t(), keyword()) :: :ok | {:error, term()}
  @callback write_span(LineageIR.Span.t(), keyword()) :: :ok | {:error, term()}
  @callback write_artifact(LineageIR.Artifact.t(), keyword()) :: :ok | {:error, term()}
  @callback write_edge(LineageIR.ProvenanceEdge.t(), keyword()) :: :ok | {:error, term()}
end
