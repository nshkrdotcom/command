defmodule Command.Adapter.Validation do
  @moduledoc """
  Validates normalized events against schema requirements.

  Provides two validation functions:
  - `validate!/1` - Raises on invalid events (use in strict mode)
  - `validate/1` - Returns `{:ok, event}` or `{:error, reason}` (use for error handling)

  ## Validation Rules

  ### Required Fields (always)
  - `type` - Must be a valid event type atom
  - `provider` - Must be `:claude` or `:codex`
  - `event_id` - Must be present
  - `sequence` - Must be a non-negative integer
  - `timestamp` - Must be a DateTime struct

  ### Critical Fields (in strict mode)
  - `session_id` - Session identifier (context-derived)
  - `run_id` - Run identifier (context-derived)

  ### Data Shape Validation

  Each event type has required data fields that are validated.
  See `Command.Event` documentation for data shapes.

  ## Examples

      # Strict validation (raises on error)
      event = %Command.Event{...}
      Command.Adapter.Validation.validate!(event)

      # Soft validation (returns tuple)
      case Command.Adapter.Validation.validate(event) do
        {:ok, event} -> process(event)
        {:error, reason} -> handle_error(reason)
      end
  """

  alias Command.Event

  @required_fields [:type, :provider, :event_id, :sequence, :timestamp]
  @critical_fields [:session_id, :run_id]

  @doc """
  Validates an event and raises `ArgumentError` if invalid.

  Returns the event unchanged if valid.
  """
  @spec validate!(Event.t()) :: Event.t()
  def validate!(%Event{} = event) do
    case validate(event) do
      {:ok, event} ->
        event

      {:error, reason} ->
        raise ArgumentError, "Invalid event: #{inspect(reason)}"
    end
  end

  @doc """
  Validates an event and returns `{:ok, event}` or `{:error, reason}`.
  """
  @spec validate(Event.t()) :: {:ok, Event.t()} | {:error, term()}
  def validate(%Event{} = event) do
    with :ok <- validate_required(event),
         :ok <- validate_critical(event),
         :ok <- validate_type_data(event) do
      {:ok, event}
    end
  end

  # Validates that required fields are present and non-nil
  defp validate_required(event) do
    missing =
      @required_fields
      |> Enum.filter(fn field -> is_nil(Map.get(event, field)) end)

    case missing do
      [] -> :ok
      fields -> {:error, {:missing_required, fields}}
    end
  end

  # Validates that critical fields are present (for strict mode)
  defp validate_critical(event) do
    missing =
      @critical_fields
      |> Enum.filter(fn field -> is_nil(Map.get(event, field)) end)

    case missing do
      [] -> :ok
      fields -> {:error, {:missing_critical, fields}}
    end
  end

  # Validates data shape based on event type
  defp validate_type_data(%{type: type, data: data}) when is_map(data) do
    case type do
      :message_start ->
        validate_fields(data, [:message_id, :model])

      :text_delta ->
        validate_fields(data, [:content]) &&
          validate_type(data, :content, &is_binary/1)

      :tool_use_start ->
        validate_fields(data, [:tool_use_id, :tool_name])

      :tool_use_delta ->
        validate_fields(data, [:tool_use_id])

      :tool_use_end ->
        validate_fields(data, [:tool_use_id, :input])

      :tool_result ->
        validate_fields(data, [:tool_use_id, :success])

      :file_change ->
        validate_fields(data, [:path, :operation])

      :structured_output ->
        validate_fields(data, [:content])

      :reasoning ->
        validate_fields(data, [:text])

      :usage_update ->
        validate_fields(data, [:input_tokens, :output_tokens])

      :message_stop ->
        validate_fields(data, [:stop_reason])

      :error ->
        validate_fields(data, [:error_type, :message, :recoverable])

      :raw ->
        # Raw events can have any structure
        :ok

      unknown_type ->
        {:error, {:unknown_event_type, unknown_type}}
    end
  end

  defp validate_type_data(%{type: type, data: nil}) do
    {:error, {:missing_data, type}}
  end

  # Helper: Validate that specific fields exist in a map
  defp validate_fields(data, required_fields) do
    missing =
      required_fields
      |> Enum.filter(fn field -> not Map.has_key?(data, field) end)

    case missing do
      [] -> :ok
      fields -> {:error, {:missing_data_fields, fields}}
    end
  end

  # Helper: Validate that a field has a specific type
  defp validate_type(data, field, type_check_fn) do
    value = Map.get(data, field)

    if type_check_fn.(value) do
      :ok
    else
      {:error, {:invalid_field_type, field, value}}
    end
  end
end
