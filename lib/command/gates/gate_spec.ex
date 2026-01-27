defmodule Command.Gates.GateSpec do
  @moduledoc """
  Specification for a quality gate checkpoint.

  A gate spec defines a named checkpoint with one or more criteria that must
  all pass for the gate to pass. Gates are organized into three categories:

  - `:doc` - Documentation gates (GATE-DOC-*)
  - `:impl` - Implementation gates (GATE-IMPL-*)
  - `:ops` - Operational gates (GATE-OPS-*)

  ## Fields

  - `id` - Unique gate identifier (e.g., "GATE-DOC-001")
  - `name` - Human-readable gate name (e.g., "Completeness")
  - `category` - Gate category: `:doc`, `:impl`, or `:ops`
  - `when` - Description of when the gate is evaluated
  - `blocks` - Description of what phase the gate blocks
  - `criteria` - List of `GateCriterion` structs to evaluate
  - `retry_config` - Optional retry configuration map

  ## Retry Config

  The `retry_config` map supports:

  - `max_retries` - Maximum number of retry attempts
  - `backoff_ms` - List of backoff durations in milliseconds
  - `auto_retry` - Whether to automatically retry on failure
  """

  alias Command.Gates.GateCriterion

  @type retry_config :: %{
          max_retries: non_neg_integer(),
          backoff_ms: [non_neg_integer()],
          auto_retry: boolean()
        }

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          category: :doc | :impl | :ops | nil,
          when: String.t() | nil,
          blocks: String.t() | nil,
          criteria: [GateCriterion.t()],
          retry_config: retry_config() | nil
        }

  defstruct [:id, :name, :category, :when, :blocks, criteria: [], retry_config: nil]

  @valid_categories [:doc, :impl, :ops]

  @doc """
  Returns the list of valid gate categories.
  """
  @spec valid_categories() :: [:doc | :impl | :ops]
  def valid_categories, do: @valid_categories

  @doc """
  Validates that a gate spec has all required fields.
  """
  @spec validate(t()) :: :ok | {:error, [String.t()]}
  def validate(%__MODULE__{} = spec) do
    errors =
      []
      |> maybe_add_error(is_nil(spec.id) or spec.id == "", "id is required")
      |> maybe_add_error(is_nil(spec.name) or spec.name == "", "name is required")
      |> maybe_add_error(
        spec.category not in @valid_categories,
        "category must be one of #{inspect(@valid_categories)}"
      )
      |> maybe_add_error(not is_list(spec.criteria), "criteria must be a list")

    case errors do
      [] -> :ok
      errs -> {:error, Enum.reverse(errs)}
    end
  end

  @doc """
  Converts a gate spec to a JSON-serializable map.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = spec) do
    %{
      "id" => spec.id,
      "name" => spec.name,
      "category" => if(spec.category, do: Atom.to_string(spec.category)),
      "when" => spec.when,
      "blocks" => spec.blocks,
      "criteria" => Enum.map(spec.criteria || [], &GateCriterion.to_map/1),
      "retry_config" => serialize_retry_config(spec.retry_config)
    }
  end

  @doc """
  Creates a gate spec from a JSON-deserialized map.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      name: map["name"],
      category: if(map["category"], do: String.to_existing_atom(map["category"])),
      when: map["when"],
      blocks: map["blocks"],
      criteria: Enum.map(map["criteria"] || [], &GateCriterion.from_map/1),
      retry_config: deserialize_retry_config(map["retry_config"])
    }
  end

  defp serialize_retry_config(nil), do: nil

  defp serialize_retry_config(config) when is_map(config) do
    %{
      "max_retries" => config[:max_retries] || config.max_retries,
      "backoff_ms" => config[:backoff_ms] || config.backoff_ms,
      "auto_retry" => config[:auto_retry] || config.auto_retry
    }
  end

  defp deserialize_retry_config(nil), do: nil

  defp deserialize_retry_config(config) when is_map(config) do
    %{
      max_retries: config["max_retries"],
      backoff_ms: config["backoff_ms"],
      auto_retry: config["auto_retry"]
    }
  end

  defp maybe_add_error(errors, true, message), do: [message | errors]
  defp maybe_add_error(errors, false, _message), do: errors
end
