defmodule Command.CLI.ProgressDisplay do
  @moduledoc """
  Progress display for CLI execution.

  Supports three modes:
  - `:tui` - Terminal UI with spinner and progress bar (default in TTY)
  - `:json` - Structured JSON events (default in non-TTY/CI)
  - `:quiet` - Suppresses non-essential output

  ## Usage

      display = ProgressDisplay.new(mode: :tui)
      ProgressDisplay.prompt_started(display, prompt)
      ProgressDisplay.prompt_completed(display, prompt, result)
      ProgressDisplay.run_completed(display, summary)
  """

  @type t :: %__MODULE__{
          mode: :tui | :json | :quiet,
          verbose: boolean()
        }

  defstruct mode: :tui, verbose: false

  @doc """
  Create a new progress display with options.

  ## Options

  - `:mode` - Display mode: `:tui`, `:json`, or `:quiet`
  - `:verbose` - Show additional details (default: false)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      mode: Keyword.get(opts, :mode, auto_mode()),
      verbose: Keyword.get(opts, :verbose, false)
    }
  end

  @doc """
  Auto-detect display mode based on TTY availability.
  """
  @spec auto_mode() :: :tui | :json
  def auto_mode do
    if io_is_tty?() do
      :tui
    else
      :json
    end
  end

  @doc """
  Report prompt started.
  """
  @spec prompt_started(t(), map()) :: :ok
  def prompt_started(%{mode: :quiet}, _prompt), do: :ok

  def prompt_started(%{mode: :json}, prompt) do
    event = %{
      type: "prompt:started",
      prompt_num: prompt.num,
      prompt_name: prompt.name,
      timestamp: DateTime.utc_now()
    }

    IO.puts(Command.CLI.ProgressDisplay.JsonEmitter.format(event))
  end

  def prompt_started(%{mode: :tui}, prompt) do
    IO.puts("#{status_symbol(:running)} Running prompt #{prompt.num}: #{prompt.name}")
  end

  @doc """
  Report prompt completed.
  """
  @spec prompt_completed(t(), map(), map()) :: :ok
  def prompt_completed(%{mode: :quiet}, _prompt, _result), do: :ok

  def prompt_completed(%{mode: :json}, prompt, result) do
    event = %{
      type: "prompt:completed",
      prompt_num: prompt.num,
      prompt_name: prompt.name,
      status: result[:status] || "completed",
      duration_ms: result[:duration_ms],
      timestamp: DateTime.utc_now()
    }

    IO.puts(Command.CLI.ProgressDisplay.JsonEmitter.format(event))
  end

  def prompt_completed(%{mode: :tui}, prompt, result) do
    symbol = status_symbol(result[:status] || :completed)
    duration = format_duration(result[:duration_ms])
    IO.puts("#{symbol} Prompt #{prompt.num}: #{prompt.name} #{duration}")
  end

  @doc """
  Report prompt failed.
  """
  @spec prompt_failed(t(), map(), term()) :: :ok
  def prompt_failed(%{mode: :quiet}, _prompt, _error), do: :ok

  def prompt_failed(%{mode: :json}, prompt, error) do
    event = %{
      type: "prompt:failed",
      prompt_num: prompt.num,
      prompt_name: prompt.name,
      error: inspect(error),
      timestamp: DateTime.utc_now()
    }

    IO.puts(Command.CLI.ProgressDisplay.JsonEmitter.format(event))
  end

  def prompt_failed(%{mode: :tui}, prompt, error) do
    IO.puts("#{status_symbol(:error)} Prompt #{prompt.num}: #{prompt.name} - #{inspect(error)}")
  end

  @doc """
  Report run completed.
  """
  @spec run_completed(t(), map()) :: :ok
  def run_completed(%{mode: :quiet}, _summary), do: :ok

  def run_completed(%{mode: :json}, summary) do
    event =
      Map.merge(summary, %{
        type: "run:completed",
        timestamp: DateTime.utc_now()
      })

    IO.puts(Command.CLI.ProgressDisplay.JsonEmitter.format(event))
  end

  def run_completed(%{mode: :tui}, summary) do
    IO.puts(Command.CLI.ProgressDisplay.Summary.render(summary))
  end

  # Private helpers

  defp io_is_tty? do
    case :io.columns() do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp status_symbol(:ok), do: "✓"
  defp status_symbol(:completed), do: "✓"
  defp status_symbol("completed"), do: "✓"
  defp status_symbol(:error), do: "✗"
  defp status_symbol(:failed), do: "✗"
  defp status_symbol("failed"), do: "✗"
  defp status_symbol(:skip), do: "○"
  defp status_symbol(:skipped), do: "○"
  defp status_symbol("skipped"), do: "○"
  defp status_symbol(:running), do: "▸"
  defp status_symbol(:partial_success), do: "◐"
  defp status_symbol("partial_success"), do: "◐"
  defp status_symbol(_), do: "·"

  defp format_duration(nil), do: ""
  defp format_duration(ms) when ms < 1000, do: "(#{ms}ms)"
  defp format_duration(ms), do: "(#{Float.round(ms / 1000, 1)}s)"
end

defmodule Command.CLI.ProgressDisplay.Spinner do
  @moduledoc """
  Animated spinner for TUI progress display.

  Uses a separate process to animate the spinner frames
  while the main process executes work.
  """

  @frames ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

  @type spinner :: %{
          pid: pid() | nil,
          message: String.t(),
          id: atom()
        }

  @doc """
  Start an animated spinner with a message.
  """
  @spec start(atom(), String.t()) :: spinner()
  def start(id, message) do
    # In non-TTY or test environments, just store state
    %{
      id: id,
      message: message,
      pid: nil,
      started_at: System.monotonic_time(:millisecond)
    }
  end

  @doc """
  Stop the spinner with a status symbol.
  """
  @spec stop(spinner(), :ok | :error | :skip) :: :ok
  def stop(%{pid: pid} = _spinner, _status) when is_pid(pid) do
    Process.exit(pid, :normal)
    :ok
  end

  def stop(_spinner, _status), do: :ok

  @doc "Returns the spinner animation frames."
  @spec frames() :: [String.t()]
  def frames, do: @frames
end

defmodule Command.CLI.ProgressDisplay.StatusLine do
  @moduledoc """
  Renders a status line showing current prompt and progress.
  """

  @doc """
  Render a status line with prompt info and progress bar.

  ## Status Fields

  - `current_prompt` - Current prompt number
  - `prompt_name` - Current prompt name
  - `completed` - Number of completed prompts
  - `total` - Total number of prompts
  - `phase` - Current phase number
  - `phase_name` - Current phase name
  """
  @spec render(map()) :: String.t()
  def render(status) do
    progress = progress_bar(status.completed, status.total)
    percent = div(status.completed * 100, max(status.total, 1))

    phase_info =
      if status[:phase_name] do
        " [Phase #{status.phase}: #{status.phase_name}]"
      else
        ""
      end

    "#{progress} #{percent}% | Prompt #{status.current_prompt}: #{status.prompt_name}#{phase_info}"
  end

  defp progress_bar(completed, total) do
    width = 20
    filled = div(completed * width, max(total, 1))
    empty = width - filled

    "[#{String.duplicate("█", filled)}#{String.duplicate("░", empty)}]"
  end
end

defmodule Command.CLI.ProgressDisplay.Summary do
  @moduledoc """
  Renders a completion summary after a run finishes.
  """

  @doc """
  Render a completion summary.

  ## Summary Fields

  - `total` - Total prompts
  - `completed` - Completed prompts
  - `failed` - Failed prompts
  - `skipped` - Skipped prompts
  - `partial_success` - Partial success prompts
  - `duration_ms` - Total duration in milliseconds
  - `total_cost_usd` - Total cost
  """
  @spec render(map()) :: String.t()
  def render(summary) do
    duration = format_duration(summary[:duration_ms])
    cost = format_cost(summary[:total_cost_usd])

    status_line =
      cond do
        summary.failed > 0 ->
          "✗ Run completed with failures"

        summary[:partial_success] && summary.partial_success > 0 ->
          "◐ Run completed with partial success"

        true ->
          "✓ Run completed successfully"
      end

    """
    #{String.duplicate("─", 50)}
    #{status_line}

      Total:    #{summary.total}
      Completed: #{summary.completed}
      Failed:    #{summary.failed}
      Skipped:   #{summary[:skipped] || 0}
      Duration:  #{duration}
      Cost:      #{cost}
    #{String.duplicate("─", 50)}
    """
  end

  defp format_duration(nil), do: "N/A"

  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"

  defp format_duration(ms) when ms < 60_000 do
    "#{Float.round(ms / 1000, 1)}s"
  end

  defp format_duration(ms) do
    minutes = div(ms, 60_000)
    seconds = rem(ms, 60_000) |> div(1000)
    "#{minutes}m #{seconds}s"
  end

  defp format_cost(nil), do: "N/A"

  defp format_cost(%Decimal{} = cost) do
    "$#{Decimal.round(cost, 4)}"
  end

  defp format_cost(cost) when is_number(cost) do
    "$#{Float.round(cost * 1.0, 4)}"
  end
end

defmodule Command.CLI.ProgressDisplay.JsonEmitter do
  @moduledoc """
  Emits structured JSON events to stdout for CI/CD pipelines.
  """

  @doc """
  Format an event as a JSON string.
  """
  @spec format(map()) :: String.t()
  def format(event) do
    event
    |> normalize_values()
    |> Jason.encode!()
  end

  @doc """
  Emit a JSON event to stdout.
  """
  @spec emit(map()) :: :ok
  def emit(event) do
    IO.puts(format(event))
  end

  defp normalize_values(map) when is_map(map) do
    Map.new(map, fn
      {k, %DateTime{} = v} -> {k, DateTime.to_iso8601(v)}
      {k, %Decimal{} = v} -> {k, Decimal.to_string(v)}
      {k, v} when is_atom(k) -> {to_string(k), normalize_values(v)}
      {k, v} -> {k, normalize_values(v)}
    end)
  end

  defp normalize_values(list) when is_list(list) do
    Enum.map(list, &normalize_values/1)
  end

  defp normalize_values(value), do: value
end
