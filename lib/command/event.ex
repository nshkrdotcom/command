defmodule Command.Event do
  @moduledoc """
  Normalized event schema for multi-provider agent interactions.

  Every event from Claude Agent SDK or Codex SDK is transformed into this
  structure before being consumed by downstream components.

  ## Event Types

  The following event types are supported:

  ### Message Lifecycle
  - `:message_start` - Beginning of assistant response
  - `:text_delta` - Incremental text content
  - `:message_stop` - End of assistant response

  ### Tool Lifecycle
  - `:tool_use_start` - Tool invocation begins
  - `:tool_use_delta` - Streaming tool input
  - `:tool_use_end` - Tool invocation complete
  - `:tool_result` - Tool execution result

  ### Side Effects
  - `:file_change` - File system modification

  ### Structured Data
  - `:structured_output` - JSON/schema output block
  - `:reasoning` - Model reasoning/thinking blocks

  ### Metrics
  - `:usage_update` - Token/cost metrics

  ### Errors
  - `:error` - Error during processing

  ### Fallback
  - `:raw` - Unrecognized event (triggers telemetry)

  ## Data Shapes

  Each event type has a specific data shape:

  ### :message_start
      %{
        message_id: String.t(),
        model: String.t(),
        role: :assistant
      }

  ### :text_delta
      %{
        content: String.t(),
        content_block_index: non_neg_integer()
      }

  ### :tool_use_start
      %{
        tool_use_id: String.t(),
        tool_name: String.t(),
        input_partial: map() | nil
      }

  ### :tool_use_delta
      %{
        tool_use_id: String.t(),
        input_delta: String.t()
      }

  ### :tool_use_end
      %{
        tool_use_id: String.t(),
        tool_name: String.t(),
        input: map()
      }

  ### :tool_result
      %{
        tool_use_id: String.t(),
        success: boolean(),
        output: term(),
        error: String.t() | nil,
        duration_ms: non_neg_integer() | nil
      }

  ### :file_change
      %{
        path: String.t(),
        operation: :create | :modify | :delete | :rename,
        content: String.t() | nil,
        diff: String.t() | nil,
        old_path: String.t() | nil
      }

  ### :structured_output
      %{
        schema_name: String.t() | nil,
        content: map()
      }

  ### :reasoning
      %{
        text: String.t(),
        summary: String.t() | nil
      }

  ### :usage_update
      %{
        input_tokens: non_neg_integer(),
        output_tokens: non_neg_integer(),
        cache_read_tokens: non_neg_integer() | nil,
        cache_write_tokens: non_neg_integer() | nil,
        cost_usd: float() | nil
      }

  ### :message_stop
      %{
        stop_reason: :end_turn | :tool_use | :max_tokens | :stop_sequence | :error
      }

  ### :error
      %{
        error_type: atom(),
        message: String.t(),
        code: String.t() | nil,
        recoverable: boolean(),
        retry_after_ms: non_neg_integer() | nil
      }

  ### :raw
      %{
        original_type: String.t() | atom(),
        payload: term()
      }
  """

  # Message lifecycle
  @type event_type ::
          :message_start
          | :text_delta
          | :message_stop
          # Tool lifecycle
          | :tool_use_start
          | :tool_use_delta
          | :tool_use_end
          | :tool_result
          # Side effects
          | :file_change
          # Structured data
          | :structured_output
          | :reasoning
          # Metrics
          | :usage_update
          # Errors
          | :error
          # Fallback
          | :raw

  @type provider :: :claude | :codex

  @type t :: %__MODULE__{
          # Event classification
          type: event_type(),
          provider: provider(),
          # Identity chain
          session_id: String.t() | nil,
          run_id: String.t() | nil,
          prompt_id: String.t() | nil,
          event_id: String.t() | nil,
          # Ordering
          sequence: non_neg_integer() | nil,
          timestamp: DateTime.t() | nil,
          # Payload
          data: map() | nil,
          # Original event (for debugging/advanced use)
          raw: term()
        }

  defstruct [
    :type,
    :provider,
    :session_id,
    :run_id,
    :prompt_id,
    :event_id,
    :sequence,
    :timestamp,
    :data,
    :raw
  ]
end
