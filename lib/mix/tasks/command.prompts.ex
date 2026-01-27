defmodule Mix.Tasks.Command.Prompts do
  @shortdoc "Execute prompt sets with progress tracking and streaming output"

  @moduledoc """
  Mix task for executing prompt sets.

  ## Usage

      mix command.prompts --config CONFIG [command] [options]

  ## Commands

      --list              List all prompts with status
      --validate          Validate config, prompts, and commit messages
      --dry-run TARGET    Validate and preview without executing
      --run TARGET        Execute prompts with streaming output
      --plan-only TARGET  Generate execution plan without running

  ## Targets (for --run, --dry-run, --plan-only)

      NN                  Single prompt number (e.g., 01)
      --phase N           All prompts in phase N
      --all               All prompts
      --continue          Resume from last completed prompt

  ## Options

      --config PATH       Path to config file (required)
      --provider NAME     Override provider (claude, codex)
      --model NAME        Override model
      --no-commit         Skip git commits after execution
      --verbose           Show detailed output
      --quiet             Suppress non-essential output
      --file-only         Run without database connection
      --repo-override N:P Override repo path (repeatable)
      --partial-mode MODE Partial success mode (fail_fast, continue, require_all)
      --partial-continue  Resume partial_success prompts
      --force-continue    Force continue past partial_success under require_all

  ## Examples

      # List all prompts
      mix command.prompts --config run_prompts.exs --list

      # Validate configuration
      mix command.prompts --config run_prompts.exs --validate

      # Run single prompt
      mix command.prompts --config run_prompts.exs --run 01

      # Run all prompts in phase 2
      mix command.prompts --config run_prompts.exs --run --phase 2

      # Run all prompts
      mix command.prompts --config run_prompts.exs --run --all

      # Resume from last completed
      mix command.prompts --config run_prompts.exs --run --continue

      # Dry run with codex provider
      mix command.prompts --config run_prompts.exs --dry-run --all --provider codex

  ## Exit Codes

      0  Success
      1  General error
      2  Configuration error
      3  Provider error
      4  Git error
      5  Database error
      6  Partial success
      7  Validation error
      8  Resume blocked (require_all + partial_success)
  """

  use Mix.Task

  alias Command.CLI.{ConfigLoader, ErrorHandler, ProgressDisplay, PromptRunner}

  @switches [
    help: :boolean,
    config: :string,
    list: :boolean,
    validate: :boolean,
    dry_run: :boolean,
    run: :boolean,
    plan_only: :boolean,
    all: :boolean,
    continue: :boolean,
    phase: :integer,
    provider: :string,
    model: :string,
    no_commit: :boolean,
    verbose: :boolean,
    quiet: :boolean,
    file_only: :boolean,
    db: :boolean,
    repo_override: :keep,
    partial_mode: :string,
    partial_continue: :boolean,
    force_continue: :boolean
  ]

  @aliases [
    h: :help,
    c: :config,
    v: :verbose,
    q: :quiet
  ]

  @impl Mix.Task
  def run(args) do
    {opts, rest} = parse_args(args)

    cond do
      opts[:help] ->
        show_help()

      opts[:list] ->
        do_list(opts)

      opts[:validate] ->
        do_validate(opts)

      opts[:dry_run] ->
        do_dry_run(opts, rest)

      opts[:run] ->
        do_run(opts, rest)

      opts[:plan_only] ->
        do_plan_only(opts, rest)

      true ->
        show_help()
    end
  end

  @doc """
  Parse command-line arguments.
  """
  @spec parse_args([String.t()]) :: {keyword(), [String.t()]}
  def parse_args(args) do
    {opts, rest, _invalid} =
      OptionParser.parse(args, strict: @switches, aliases: @aliases)

    # Collect :keep values into a list
    repo_overrides =
      opts
      |> Keyword.get_values(:repo_override)

    opts =
      opts
      |> Keyword.delete(:repo_override)
      |> then(fn o ->
        if repo_overrides != [], do: Keyword.put(o, :repo_override, repo_overrides), else: o
      end)

    {opts, rest}
  end

  @doc """
  Validate flag combinations.
  """
  @spec validate_flags(keyword()) :: :ok | {:error, String.t()}
  def validate_flags(opts) do
    cond do
      opts[:db] && opts[:file_only] ->
        {:error, "Cannot use --db and --file-only together"}

      (opts[:run] || opts[:dry_run] || opts[:plan_only] || opts[:list] || opts[:validate]) &&
          !opts[:config] ->
        {:error, "Missing required --config flag"}

      true ->
        :ok
    end
  end

  @doc """
  Build target list from options and remaining args.

  The third argument is either a list of all prompt numbers (for --all)
  or a map of phase => nums (for --phase).
  """
  @spec build_targets(keyword(), [String.t()], [String.t()] | map()) :: [String.t()]
  def build_targets(opts, rest, nums_or_phase_map) do
    cond do
      opts[:all] ->
        case nums_or_phase_map do
          nums when is_list(nums) -> nums
          _ -> []
        end

      opts[:phase] ->
        case nums_or_phase_map do
          %{} = phase_map -> Map.get(phase_map, opts[:phase], [])
          _ -> []
        end

      rest != [] ->
        rest

      true ->
        []
    end
  end

  # ============================================================================
  # Command Implementations
  # ============================================================================

  @doc false
  def show_help do
    Mix.shell().info(@moduledoc)
  end

  @doc false
  def do_list(opts) do
    case load_config(opts) do
      {:ok, config} ->
        case ConfigLoader.get_all_prompts(config) do
          {:ok, prompts} ->
            display = build_display(opts)
            render_prompt_list(prompts, config, display)

          {:error, reason} ->
            handle_error({:config_error, reason})
        end

      {:error, reason} ->
        handle_error(reason)
    end
  end

  @doc false
  def do_validate(opts) do
    case load_config(opts) do
      {:ok, config} ->
        errors = run_validations(config)

        if errors == [] do
          Mix.shell().info("✓ Configuration is valid")
        else
          Mix.shell().error("✗ Configuration has #{length(errors)} error(s):")

          Enum.each(errors, fn error ->
            Mix.shell().error("  - #{error}")
          end)

          System.stop(ErrorHandler.exit_code(:validation_error))
        end

      {:error, reason} ->
        handle_error(reason)
    end
  end

  @doc false
  def do_dry_run(opts, rest) do
    case load_config(opts) do
      {:ok, config} ->
        case resolve_targets(config, opts, rest) do
          {:ok, prompts} ->
            display = build_display(opts)

            Mix.shell().info("Dry run for #{length(prompts)} prompt(s):")
            Mix.shell().info("")

            Enum.each(prompts, fn prompt ->
              result = PromptRunner.execute(prompt, config, dry_run: true)
              ProgressDisplay.prompt_completed(display, prompt, %{status: result.status})
            end)

            Mix.shell().info("")
            Mix.shell().info("✓ Dry run complete. No changes were made.")

          {:error, reason} ->
            handle_error(reason)
        end

      {:error, reason} ->
        handle_error(reason)
    end
  end

  @doc false
  def do_run(opts, rest) do
    case validate_flags(opts) do
      {:error, message} ->
        Mix.shell().error(message)
        System.stop(ErrorHandler.exit_code(:config_error))

      :ok ->
        do_run_validated(opts, rest)
    end
  end

  defp do_run_validated(opts, rest) do
    case load_config(opts) do
      {:ok, config} ->
        config = apply_run_opts(config, opts)

        case resolve_targets(config, opts, rest) do
          {:ok, prompts} ->
            display = build_display(opts)
            start_time = System.monotonic_time(:millisecond)

            results =
              PromptRunner.execute_targets(prompts, config, display: display)

            duration = System.monotonic_time(:millisecond) - start_time
            render_summary(results, duration, display)

            exit_code = determine_exit_code(results)

            if exit_code != 0 do
              System.stop(exit_code)
            end

          {:error, reason} ->
            handle_error(reason)
        end

      {:error, reason} ->
        handle_error(reason)
    end
  end

  @doc false
  def do_plan_only(opts, rest) do
    case load_config(opts) do
      {:ok, config} ->
        case resolve_targets(config, opts, rest) do
          {:ok, prompts} ->
            plan = PromptRunner.build_plan(prompts, config)

            Mix.shell().info("Execution Plan (#{length(plan)} prompts):")
            Mix.shell().info("")

            Enum.each(plan, fn entry ->
              repos_info =
                if entry.target_repos do
                  " -> #{Enum.join(entry.target_repos, ", ")}"
                else
                  ""
                end

              Mix.shell().info(
                "  #{entry.prompt_num}. #{entry.prompt_name} " <>
                  "[#{entry.provider}/#{entry.model}]#{repos_info}"
              )
            end)

            Mix.shell().info("")
            Mix.shell().info("Use --run to execute this plan.")

          {:error, reason} ->
            handle_error(reason)
        end

      {:error, reason} ->
        handle_error(reason)
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  @doc false
  def load_config(opts) do
    config_path = opts[:config]

    unless config_path do
      {:error, {:config_error, "Missing --config flag"}}
    else
      with {:ok, config} <- ConfigLoader.load(config_path),
           :ok <- ConfigLoader.validate(config) do
        config =
          config
          |> ConfigLoader.normalize_events_mode()
          |> ConfigLoader.apply_overrides(opts)

        {:ok, config}
      end
    end
  end

  defp apply_run_opts(config, opts) do
    config
    |> Map.put(:no_commit, opts[:no_commit] || false)
    |> Map.put(:db_enabled, !opts[:file_only])
    |> Map.put(:file_mirror, opts[:file_only] || config[:file_mirror] || false)
  end

  defp resolve_targets(config, opts, rest) do
    cond do
      opts[:continue] ->
        # Resume from last completed - for now just get all and let runner handle
        ConfigLoader.get_all_prompts(config)

      opts[:all] ->
        ConfigLoader.get_all_prompts(config)

      opts[:phase] ->
        case ConfigLoader.get_phase_nums(config, opts[:phase]) do
          {:ok, nums} ->
            get_prompts_by_nums(config, nums)

          error ->
            error
        end

      rest != [] ->
        get_prompts_by_nums(config, rest)

      true ->
        {:error,
         {:config_error, "No target specified. Use --all, --phase N, or provide prompt numbers."}}
    end
  end

  defp get_prompts_by_nums(config, nums) do
    results =
      Enum.map(nums, fn num ->
        ConfigLoader.get_prompt(config, num)
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))

    case errors do
      [] -> {:ok, Enum.map(results, fn {:ok, p} -> p end)}
      [{:error, reason} | _] -> {:error, reason}
    end
  end

  defp build_display(opts) do
    mode =
      cond do
        opts[:quiet] -> :quiet
        opts[:verbose] -> :tui
        true -> ProgressDisplay.auto_mode()
      end

    ProgressDisplay.new(mode: mode, verbose: opts[:verbose] || false)
  end

  defp render_prompt_list(prompts, config, _display) do
    phase_names = config[:phase_names] || %{}

    Mix.shell().info("Prompts (#{length(prompts)} total):")
    Mix.shell().info("")

    Enum.each(prompts, fn prompt ->
      phase_name = Map.get(phase_names, prompt.phase, "")
      phase_label = if phase_name != "", do: " [#{phase_name}]", else: ""

      repos_info =
        if prompt.target_repos do
          " -> #{Enum.join(prompt.target_repos, ", ")}"
        else
          ""
        end

      Mix.shell().info(
        "  #{prompt.num}. #{prompt.name} (Phase #{prompt.phase}#{phase_label}, #{prompt.sp}SP)#{repos_info}"
      )
    end)
  end

  defp run_validations(config) do
    errors = []

    # Check prompts file exists and parses
    errors =
      case ConfigLoader.get_all_prompts(config) do
        {:ok, []} -> ["No prompts found in prompts file" | errors]
        {:ok, _} -> errors
        {:error, reason} -> ["Prompts file error: #{inspect(reason)}" | errors]
      end

    # Check commit messages file
    errors =
      case ConfigLoader.parse_commit_messages(config) do
        {:ok, _} -> errors
        {:error, reason} -> ["Commit messages error: #{inspect(reason)}" | errors]
      end

    # Validate events_mode
    errors =
      case ConfigLoader.validate_events_mode(config) do
        :ok -> errors
        {:error, reason} -> ["Events mode error: #{inspect(reason)}" | errors]
      end

    # Validate workspace_root
    errors =
      case ConfigLoader.validate_workspace_root(config) do
        :ok -> errors
        {:error, reason} -> ["Workspace root error: #{inspect(reason)}" | errors]
      end

    Enum.reverse(errors)
  end

  defp render_summary(results, duration, display) do
    completed = Enum.count(results, &(&1.status in [:completed, :dry_run]))
    failed = Enum.count(results, &(&1.status == :failed))
    skipped = Enum.count(results, &(&1.status == :skipped))
    partial = Enum.count(results, &(&1.status == :partial_success))

    summary = %{
      total: length(results),
      completed: completed,
      failed: failed,
      skipped: skipped,
      partial_success: partial,
      duration_ms: duration,
      total_cost_usd: Decimal.new(0)
    }

    ProgressDisplay.run_completed(display, summary)
  end

  defp determine_exit_code(results) do
    statuses = Enum.map(results, & &1.status)

    cond do
      Enum.any?(statuses, &(&1 == :failed)) ->
        ErrorHandler.exit_code(:general_error)

      Enum.any?(statuses, &(&1 == :partial_success)) ->
        ErrorHandler.exit_code(:partial_success)

      true ->
        0
    end
  end

  defp handle_error(error) do
    error_info = ErrorHandler.format(error)
    Mix.shell().error(ErrorHandler.print(error_info))
    System.stop(ErrorHandler.exit_code(error_info.type))
  end
end
