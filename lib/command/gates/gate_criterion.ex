defmodule Command.Gates.GateCriterion do
  @moduledoc """
  Individual criterion within a quality gate.

  A criterion defines a single check that must pass for a gate to succeed.
  Each criterion has an evaluator function that receives a context map and
  returns either `:pass` or `{:fail, details}`.

  ## Fields

  - `name` - Unique name identifying this criterion within a gate
  - `evaluator` - 1-arity function `(context -> :pass | {:fail, term()})`
  - `threshold` - Optional numeric threshold for numeric criteria
  - `required` - Whether failure of this criterion blocks the gate (default: `true`)

  ## Examples

      %GateCriterion{
        name: "coverage_check",
        evaluator: fn ctx ->
          if ctx[:coverage] >= 80, do: :pass, else: {:fail, "Below threshold"}
        end,
        threshold: 80.0,
        required: true
      }
  """

  @type t :: %__MODULE__{
          name: String.t() | nil,
          evaluator: (map() -> :pass | {:fail, term()}) | nil,
          threshold: float() | nil,
          required: boolean()
        }

  defstruct [:name, :evaluator, :threshold, required: true]

  @doc """
  Converts a criterion to a JSON-serializable map.

  Note: The evaluator function cannot be serialized; it is excluded.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = criterion) do
    %{
      "name" => criterion.name,
      "threshold" => criterion.threshold,
      "required" => criterion.required
    }
  end

  @doc """
  Creates a criterion from a JSON-deserialized map.

  Note: The evaluator must be set separately as functions cannot be deserialized from JSON.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      name: map["name"],
      threshold: map["threshold"],
      required: Map.get(map, "required", true)
    }
  end
end
