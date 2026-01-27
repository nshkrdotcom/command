defmodule LineageIR.Event do
  @moduledoc """
  Lineage event envelope for sink ingestion.
  """

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          type: String.t() | nil,
          trace_id: Ecto.UUID.t() | nil,
          span_id: Ecto.UUID.t() | nil,
          run_id: Ecto.UUID.t() | nil,
          step_id: Ecto.UUID.t() | nil,
          work_id: Ecto.UUID.t() | nil,
          occurred_at: DateTime.t() | nil,
          source: String.t() | nil,
          source_ref: String.t() | nil,
          payload: map() | struct() | nil
        }

  defstruct [
    :id,
    :type,
    :trace_id,
    :span_id,
    :run_id,
    :step_id,
    :work_id,
    :occurred_at,
    :source,
    :source_ref,
    :payload
  ]
end
