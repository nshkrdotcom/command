defmodule Command.Gates.OverrideRequest do
  @moduledoc """
  Struct representing a gate override request.

  An override request is created when a gate fails and the team wants to
  proceed despite the failure. The request must include justification,
  risk assessment, and mitigations.

  ## Lifecycle

  1. Created as `:pending` via `Override.request_override/2`
  2. Approved (`:approved`) or rejected (`:rejected`) by an authorized approver
  3. Approved overrides may expire after a configured duration

  ## Fields

  - `id` - Unique override identifier
  - `gate_id` - The gate being overridden
  - `status` - Current status: `:pending`, `:approved`, or `:rejected`
  - `justification` - Why the override is needed
  - `risk_assessment` - Assessment of risk from proceeding
  - `mitigations` - List of mitigating actions
  - `requested_by` - User ID who requested the override
  - `requested_at` - When the override was requested
  - `decision` - Decision details (set on approve/reject)
  - `expires_at` - When the override expires (optional)
  """

  @type decision :: %{
          approved: boolean(),
          decided_by: String.t(),
          decided_at: DateTime.t(),
          reason: String.t() | nil,
          conditions: [String.t()]
        }

  @type t :: %__MODULE__{
          id: String.t(),
          gate_id: String.t(),
          status: :pending | :approved | :rejected,
          justification: String.t(),
          risk_assessment: String.t(),
          mitigations: [String.t()],
          requested_by: String.t() | nil,
          requested_at: DateTime.t(),
          decision: decision() | nil,
          expires_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :gate_id,
    :justification,
    :risk_assessment,
    :requested_by,
    :requested_at,
    :decision,
    :expires_at,
    status: :pending,
    mitigations: []
  ]
end
