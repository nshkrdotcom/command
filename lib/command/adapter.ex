defmodule Command.Adapter do
  @moduledoc """
  Behaviour for provider stream adapters.

  Adapters transform provider-specific events (from Claude Agent SDK or Codex SDK)
  into the unified `Command.Event` schema. Each provider has a dedicated adapter
  implementing this behaviour.

  ## Callbacks

  ### normalize_stream/2

  Takes a raw event stream from a provider and returns a stream of normalized
  `Command.Event` structs. This is the primary entry point for stream processing.

  Options:
  - `:mode` - `:strict` or `:compatibility` (default based on environment)
  - `:prompt_id` - UUID for the prompt (generated if not provided)
  - `:context` - Map with `run_id` and `session_id` for strict mode

  ### normalize_event/2

  Processes a single raw event and returns a list of normalized events plus
  updated state. Used internally by `normalize_stream/2`.

  The state map tracks:
  - `session_id` - Session identifier
  - `run_id` - Run identifier
  - `prompt_id` - Prompt identifier
  - `sequence` - Event sequence counter
  - `mode` - Normalization mode
  - Provider-specific state (e.g., tool input accumulation)

  ### supports_event?/1

  Returns `true` if the adapter can handle the given raw event type.

  ## Normalization Modes

  ### Strict Mode (Default in Production)

  - All provider-required fields must be present
  - Context-derived fields (`run_id`, `session_id`) must be provided via options
  - Invalid events raise errors
  - No automatic fallback generation

  ### Compatibility Mode (Default in Development/Test)

  - Missing context fields are auto-generated with telemetry warnings
  - Enables testing with partial provider responses
  - Events pass through even if incomplete

  ## Mode Selection

  Mode is selected in this order:
  1. Explicit `:mode` option
  2. Application config `:adapter_mode`
  3. Based on `Mix.env()` - `:strict` for `:prod`, `:compatibility` otherwise

  ## Example

      # Strict mode (production)
      raw_stream
      |> Command.Adapter.Claude.normalize_stream(
        mode: :strict,
        context: %{
          run_id: "run-uuid",
          session_id: "session-uuid"
        }
      )
      |> Enum.to_list()

      # Compatibility mode (development)
      raw_stream
      |> Command.Adapter.Codex.normalize_stream(mode: :compatibility)
      |> Enum.to_list()
  """

  alias Command.Event

  @doc """
  Normalizes a stream of provider events to `Command.Event` structs.

  Returns a stream that lazily transforms raw provider events.
  """
  @callback normalize_stream(Enumerable.t(), keyword()) :: Enumerable.t(Event.t())

  @doc """
  Normalizes a single provider event.

  Returns a tuple of `{[Command.Event.t()], new_state}`. Multiple events
  may be emitted for a single raw event (e.g., tool lifecycle events).
  """
  @callback normalize_event(term(), state :: map()) :: {[Event.t()], state :: map()}

  @doc """
  Returns true if the adapter can handle the given event type.
  """
  @callback supports_event?(term()) :: boolean()

  @doc """
  Selects the normalization mode based on options and environment.

  Order of precedence:
  1. Explicit `:mode` in options
  2. Application config `:adapter_mode`
  3. Environment-based default (`:strict` for prod, `:compatibility` otherwise)

  ## Examples

      iex> Command.Adapter.select_mode(mode: :strict)
      :strict

      iex> Command.Adapter.select_mode([])
      :compatibility  # or :strict depending on environment
  """
  @default_mode Application.compile_env(:command, :adapter_default_mode, :compatibility)

  @spec select_mode(keyword()) :: :strict | :compatibility
  def select_mode(opts) do
    cond do
      mode = Keyword.get(opts, :mode) ->
        mode

      mode = Application.get_env(:command, :adapter_mode) ->
        mode

      true ->
        @default_mode
    end
  end
end
