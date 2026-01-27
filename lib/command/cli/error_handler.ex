defmodule Command.CLI.ErrorHandler do
  @moduledoc """
  Error formatting and recovery hints for CLI execution.

  Converts error terms into structured error_info maps with:
  - Error type classification
  - Human-readable messages
  - Recovery hints
  - Retryability information
  - Exit code mapping

  ## Exit Codes

  | Code | Meaning |
  |------|---------|
  | 0 | Success |
  | 1 | General error |
  | 2 | Configuration error |
  | 3 | Provider error |
  | 4 | Git error |
  | 5 | Database error |
  | 6 | Partial success |
  | 7 | Validation error |
  | 8 | Resume blocked |
  """

  @type error_info :: %{
          type: atom(),
          message: String.t(),
          details: term(),
          recovery_hint: String.t(),
          is_retryable: boolean()
        }

  @exit_codes %{
    success: 0,
    general_error: 1,
    config_error: 2,
    provider_error: 3,
    git_error: 4,
    db_error: 5,
    partial_success: 6,
    validation_error: 7,
    resume_blocked: 8
  }

  @doc """
  Convert an error term to a structured error_info map.
  """
  @spec format(term()) :: error_info()
  def format({:file_not_found, path}) do
    %{
      type: :config_error,
      message: "File not found: #{path}",
      details: {:file_not_found, path},
      recovery_hint: "Check that the file exists at the specified path.",
      is_retryable: false
    }
  end

  def format({:file_not_found, path, _reason}) do
    %{
      type: :config_error,
      message: "File not found: #{path}",
      details: {:file_not_found, path},
      recovery_hint: "Check that the file exists at the specified path.",
      is_retryable: false
    }
  end

  def format({:config_error, {:missing_fields, fields}}) do
    field_list = Enum.join(fields, ", ")

    %{
      type: :config_error,
      message: "Configuration missing required fields: #{field_list}",
      details: {:missing_fields, fields},
      recovery_hint: "Add the missing fields to your config file: #{field_list}",
      is_retryable: false
    }
  end

  def format({:config_error, reason}) do
    %{
      type: :config_error,
      message: "Configuration error: #{inspect(reason)}",
      details: reason,
      recovery_hint: "Review your configuration file for syntax or structure errors.",
      is_retryable: false
    }
  end

  def format({:provider_error, :timeout}) do
    %{
      type: :provider_error,
      message: "Provider request timed out",
      details: :timeout,
      recovery_hint: "The request timed out. You can retry with --continue to resume.",
      is_retryable: true
    }
  end

  def format({:provider_error, :rate_limit}) do
    %{
      type: :provider_error,
      message: "Provider rate limit exceeded",
      details: :rate_limit,
      recovery_hint: "Rate limit hit. Wait a moment and retry with --continue to resume.",
      is_retryable: true
    }
  end

  def format({:provider_error, {:api_error, message}}) do
    %{
      type: :provider_error,
      message: "Provider API error: #{message}",
      details: {:api_error, message},
      recovery_hint: "Check provider status and retry with --continue.",
      is_retryable: true
    }
  end

  def format({:provider_error, reason}) do
    %{
      type: :provider_error,
      message: "Provider error: #{inspect(reason)}",
      details: reason,
      recovery_hint: "Check provider configuration and retry.",
      is_retryable: true
    }
  end

  def format({:git_error, :commit_failed, details}) do
    %{
      type: :git_error,
      message: "Git commit failed: #{details}",
      details: {:commit_failed, details},
      recovery_hint: "Resolve the git issue manually, then retry with --continue.",
      is_retryable: false
    }
  end

  def format({:git_error, :merge_conflict}) do
    %{
      type: :git_error,
      message: "Git merge conflict detected",
      details: :merge_conflict,
      recovery_hint: "Resolve merge conflicts manually, then retry with --continue.",
      is_retryable: false
    }
  end

  def format({:git_error, reason}) do
    %{
      type: :git_error,
      message: "Git error: #{inspect(reason)}",
      details: reason,
      recovery_hint: "Check git status and resolve any issues.",
      is_retryable: false
    }
  end

  def format({:db_error, reason}) do
    %{
      type: :db_error,
      message: "Database error: #{inspect(reason)}",
      details: reason,
      recovery_hint: "Check database connectivity. Use --file-only to run without database.",
      is_retryable: false
    }
  end

  def format({:validation_error, reason}) do
    %{
      type: :validation_error,
      message: "Validation failed: #{inspect(reason)}",
      details: reason,
      recovery_hint: "Fix the validation issues and retry.",
      is_retryable: false
    }
  end

  def format({:resume_blocked, reason}) do
    %{
      type: :resume_blocked,
      message: "Resume blocked: #{inspect(reason)}",
      details: reason,
      recovery_hint:
        "Use --partial-continue to retry partial prompts or --force-continue to skip.",
      is_retryable: false
    }
  end

  def format(error) do
    %{
      type: :general_error,
      message: "Error: #{inspect(error)}",
      details: error,
      recovery_hint: "Check the error details and try again.",
      is_retryable: false
    }
  end

  @doc """
  Format and return a printable error string with ANSI colors.
  """
  @spec print(error_info()) :: String.t()
  def print(%{} = error_info) do
    type_label = error_info.type |> to_string() |> String.upcase()

    """
    \e[31m[Error: #{type_label}]\e[0m #{error_info.message}

    #{error_info.recovery_hint}
    """
    |> String.trim()
  end

  @doc """
  Return the appropriate exit code for an error type.
  """
  @spec exit_code(atom()) :: non_neg_integer()
  def exit_code(type) do
    Map.get(@exit_codes, type, 1)
  end

  @doc """
  Check if an error is retryable.
  """
  @spec is_retryable?(error_info()) :: boolean()
  def is_retryable?(%{is_retryable: retryable}), do: retryable
  def is_retryable?(_), do: false
end
