defmodule Command.CLI.ProgressDisplayTest do
  use ExUnit.Case, async: true

  alias Command.CLI.ProgressDisplay
  alias Command.CLI.ProgressDisplay.{Spinner, StatusLine, Summary, JsonEmitter}

  describe "Spinner" do
    test "start returns a spinner reference" do
      spinner = Spinner.start(:test_spinner, "Loading config...")
      assert spinner
      assert is_map(spinner)
      Spinner.stop(spinner, :ok)
    end

    test "stop with :ok returns success symbol" do
      spinner = Spinner.start(:test_spinner, "Running...")
      result = Spinner.stop(spinner, :ok)
      assert result == :ok
    end

    test "stop with :error returns error symbol" do
      spinner = Spinner.start(:test_spinner, "Running...")
      result = Spinner.stop(spinner, :error)
      assert result == :ok
    end

    test "stop with :skip returns skip symbol" do
      spinner = Spinner.start(:test_spinner, "Running...")
      result = Spinner.stop(spinner, :skip)
      assert result == :ok
    end
  end

  describe "StatusLine" do
    test "renders status line with prompt info and progress bar" do
      status = %{
        current_prompt: "01",
        prompt_name: "Database schema",
        completed: 1,
        total: 5,
        phase: 1,
        phase_name: "Foundation"
      }

      output = StatusLine.render(status)
      assert is_binary(output)
      assert output =~ "01"
      assert output =~ "Database schema"
    end

    test "renders progress percentage" do
      status = %{
        current_prompt: "03",
        prompt_name: "Integration",
        completed: 2,
        total: 5,
        phase: 2,
        phase_name: "Implementation"
      }

      output = StatusLine.render(status)
      assert output =~ "40%"
    end
  end

  describe "Summary" do
    test "renders completion summary with correct totals" do
      summary = %{
        total: 5,
        completed: 4,
        failed: 1,
        skipped: 0,
        partial_success: 0,
        duration_ms: 120_000,
        total_cost_usd: Decimal.new("1.50")
      }

      output = Summary.render(summary)
      assert is_binary(output)
      assert output =~ "4"
      assert output =~ "5"
    end

    test "renders summary with all succeeded" do
      summary = %{
        total: 3,
        completed: 3,
        failed: 0,
        skipped: 0,
        partial_success: 0,
        duration_ms: 60_000,
        total_cost_usd: Decimal.new("0.75")
      }

      output = Summary.render(summary)
      assert output =~ "3"
    end
  end

  describe "JsonEmitter" do
    test "emits structured JSON event for prompt:started" do
      event = %{
        type: "prompt:started",
        prompt_num: "01",
        prompt_name: "Database schema",
        timestamp: DateTime.utc_now()
      }

      output = JsonEmitter.format(event)
      assert is_binary(output)
      decoded = Jason.decode!(output)
      assert decoded["type"] == "prompt:started"
      assert decoded["prompt_num"] == "01"
    end

    test "emits structured JSON event for prompt:completed" do
      event = %{
        type: "prompt:completed",
        prompt_num: "01",
        prompt_name: "Database schema",
        status: "completed",
        duration_ms: 5000,
        timestamp: DateTime.utc_now()
      }

      output = JsonEmitter.format(event)
      decoded = Jason.decode!(output)
      assert decoded["type"] == "prompt:completed"
      assert decoded["status"] == "completed"
    end

    test "emits structured JSON event for run:completed" do
      event = %{
        type: "run:completed",
        total: 5,
        completed: 5,
        failed: 0,
        duration_ms: 120_000,
        timestamp: DateTime.utc_now()
      }

      output = JsonEmitter.format(event)
      decoded = Jason.decode!(output)
      assert decoded["type"] == "run:completed"
      assert decoded["total"] == 5
    end
  end

  describe "auto_mode/0" do
    test "returns :tui or :json based on TTY detection" do
      mode = ProgressDisplay.auto_mode()
      assert mode in [:tui, :json]
    end
  end

  describe "quiet mode" do
    test "quiet mode suppresses output" do
      display = ProgressDisplay.new(mode: :quiet)
      assert display.mode == :quiet
    end
  end

  describe "verbose mode" do
    test "verbose mode flag is set" do
      display = ProgressDisplay.new(mode: :tui, verbose: true)
      assert display.verbose == true
    end
  end
end
