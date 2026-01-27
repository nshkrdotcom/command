defmodule Command.CLI.ErrorHandlerTest do
  use ExUnit.Case, async: true

  alias Command.CLI.ErrorHandler

  describe "format/1" do
    test "formats config errors with recovery hints" do
      error = {:config_error, {:missing_fields, [:prompts_file, :commit_messages_file]}}
      error_info = ErrorHandler.format(error)

      assert error_info.type == :config_error
      assert error_info.message =~ "missing"
      assert error_info.recovery_hint
      assert is_binary(error_info.recovery_hint)
    end

    test "formats file not found error" do
      error = {:file_not_found, "/path/to/config.exs"}
      error_info = ErrorHandler.format(error)

      assert error_info.type == :config_error
      assert error_info.message =~ "/path/to/config.exs"
      assert error_info.recovery_hint =~ "file"
    end

    test "formats provider timeout error" do
      error = {:provider_error, :timeout}
      error_info = ErrorHandler.format(error)

      assert error_info.type == :provider_error
      assert error_info.is_retryable == true
      assert error_info.recovery_hint =~ "retry"
    end

    test "formats provider rate limit error" do
      error = {:provider_error, :rate_limit}
      error_info = ErrorHandler.format(error)

      assert error_info.type == :provider_error
      assert error_info.is_retryable == true
    end

    test "formats provider API error" do
      error = {:provider_error, {:api_error, "Internal Server Error"}}
      error_info = ErrorHandler.format(error)

      assert error_info.type == :provider_error
      assert error_info.message =~ "API"
    end

    test "formats git commit failed error" do
      error = {:git_error, :commit_failed, "merge conflict in file.ex"}
      error_info = ErrorHandler.format(error)

      assert error_info.type == :git_error
      assert error_info.message =~ "commit"
      assert error_info.recovery_hint
    end

    test "formats git merge conflict error" do
      error = {:git_error, :merge_conflict}
      error_info = ErrorHandler.format(error)

      assert error_info.type == :git_error
      assert error_info.is_retryable == false
    end

    test "formats database error" do
      error = {:db_error, :connection_refused}
      error_info = ErrorHandler.format(error)

      assert error_info.type == :db_error
      assert error_info.recovery_hint
    end
  end

  describe "exit_code/1" do
    test "returns 0 for success" do
      assert ErrorHandler.exit_code(:success) == 0
    end

    test "returns 1 for general error" do
      assert ErrorHandler.exit_code(:general_error) == 1
    end

    test "returns 2 for config error" do
      assert ErrorHandler.exit_code(:config_error) == 2
    end

    test "returns 3 for provider error" do
      assert ErrorHandler.exit_code(:provider_error) == 3
    end

    test "returns 4 for git error" do
      assert ErrorHandler.exit_code(:git_error) == 4
    end

    test "returns 5 for database error" do
      assert ErrorHandler.exit_code(:db_error) == 5
    end

    test "returns 6 for partial_success" do
      assert ErrorHandler.exit_code(:partial_success) == 6
    end

    test "returns 7 for validation failures" do
      assert ErrorHandler.exit_code(:validation_error) == 7
    end

    test "returns 8 for resume blocked under require_all" do
      assert ErrorHandler.exit_code(:resume_blocked) == 8
    end
  end

  describe "is_retryable?/1" do
    test "provider timeout is retryable" do
      error_info = ErrorHandler.format({:provider_error, :timeout})
      assert ErrorHandler.is_retryable?(error_info)
    end

    test "provider rate limit is retryable" do
      error_info = ErrorHandler.format({:provider_error, :rate_limit})
      assert ErrorHandler.is_retryable?(error_info)
    end

    test "config error is not retryable" do
      error_info = ErrorHandler.format({:config_error, {:missing_fields, [:prompts_file]}})
      refute ErrorHandler.is_retryable?(error_info)
    end

    test "git merge conflict is not retryable" do
      error_info = ErrorHandler.format({:git_error, :merge_conflict})
      refute ErrorHandler.is_retryable?(error_info)
    end
  end

  describe "print/1" do
    test "returns formatted string with error details" do
      error_info = ErrorHandler.format({:config_error, {:missing_fields, [:prompts_file]}})
      output = ErrorHandler.print(error_info)
      assert is_binary(output)
      assert output =~ "Error"
    end
  end
end
