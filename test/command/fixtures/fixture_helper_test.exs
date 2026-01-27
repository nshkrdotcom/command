defmodule Command.Test.FixtureHelperTest do
  @moduledoc """
  Tests for Command.Test.FixtureHelper - test fixture management.

  Following TDD - these tests are written BEFORE implementation.
  """
  use ExUnit.Case, async: false

  alias Command.Test.FixtureHelper

  describe "load_fixture/1" do
    test "loads JSON from fixture path" do
      # Assuming a test fixture exists
      fixture = FixtureHelper.load_fixture("prompt_sets/simple_set.json")

      assert is_map(fixture)
      assert fixture["id"] != nil
    end

    test "raises on missing file" do
      assert_raise File.Error, fn ->
        FixtureHelper.load_fixture("nonexistent/file.json")
      end
    end

    test "parses JSON correctly" do
      fixture = FixtureHelper.load_fixture("prompt_sets/simple_set.json")

      # Should be parsed JSON, not string
      assert is_map(fixture)
      refute is_binary(fixture)
    end
  end

  describe "load_prompt_set/1" do
    test "loads from prompt_sets directory" do
      prompt_set = FixtureHelper.load_prompt_set("simple_set")

      assert is_map(prompt_set)
      assert prompt_set["prompts"] != nil
    end

    test "returns structured prompt set data" do
      prompt_set = FixtureHelper.load_prompt_set("simple_set")

      assert prompt_set["id"] != nil
      assert prompt_set["name"] != nil
      assert prompt_set["prompts"] != nil
      assert is_map(prompt_set["prompts"])
    end
  end

  describe "load_claude_response/1" do
    test "loads from provider_responses/claude directory" do
      response = FixtureHelper.load_claude_response("simple_completion")

      assert is_map(response)
      assert response["type"] == "message" or response["content"] != nil
    end

    test "loads tool call response" do
      response = FixtureHelper.load_claude_response("tool_call")

      assert is_map(response)
      assert response["content"] != nil

      # Should have tool_use content
      tool_content =
        Enum.find(response["content"], fn item ->
          item["type"] == "tool_use"
        end)

      assert tool_content != nil
    end

    test "loads streaming chunks" do
      chunks = FixtureHelper.load_claude_response("streaming_chunks")

      assert is_list(chunks)
      assert length(chunks) > 0
    end

    test "loads error responses" do
      error_response = FixtureHelper.load_claude_response("error_429")

      assert is_map(error_response)
      assert error_response["type"] == "error" or error_response["error"] != nil
    end
  end

  describe "load_codex_response/1" do
    test "loads from provider_responses/codex directory" do
      response = FixtureHelper.load_codex_response("simple_completion")

      assert is_map(response)
      assert response["object"] == "response" or response["output"] != nil
    end

    test "loads item call (function call) response" do
      response = FixtureHelper.load_codex_response("item_call")

      assert is_map(response)
      assert response["output"] != nil

      # Should have function_call type output
      function_call =
        Enum.find(response["output"], fn item ->
          item["type"] == "function_call"
        end)

      assert function_call != nil
    end

    test "loads streaming chunks" do
      chunks = FixtureHelper.load_codex_response("streaming_chunks")

      assert is_list(chunks)
      assert length(chunks) > 0
    end

    test "loads error responses" do
      error_response = FixtureHelper.load_codex_response("error_500")

      assert is_map(error_response)
      assert error_response["error"] != nil or error_response["type"] == "error"
    end
  end

  describe "load_normalized_event/1" do
    test "loads normalized message event" do
      event = FixtureHelper.load_normalized_event("message_event")

      assert is_map(event)
      assert event["event_type"] == "message" or event["type"] == "message"
      assert event["normalized"] != nil
    end

    test "loads normalized tool event" do
      event = FixtureHelper.load_normalized_event("tool_event")

      assert is_map(event)
      assert event["event_type"] in ["tool_call", "tool_use"]
      assert event["normalized"] != nil
      assert event["normalized"]["name"] != nil
    end

    test "loads normalized usage event" do
      event = FixtureHelper.load_normalized_event("usage_event")

      assert is_map(event)
      assert event["event_type"] == "usage_update" or event["type"] == "usage_update"
      assert event["normalized"]["input_tokens"] != nil
      assert event["normalized"]["output_tokens"] != nil
    end

    test "includes provider-specific data" do
      event = FixtureHelper.load_normalized_event("tool_event")

      assert event["provider_specific"] != nil

      assert event["provider_specific"]["claude"] != nil or
               event["provider_specific"]["codex"] != nil
    end
  end

  describe "git_fixture_repo/0" do
    test "creates temporary git repo" do
      path = FixtureHelper.git_fixture_repo()

      assert File.exists?(path)
      assert File.dir?(path)

      # Verify it's a git repo
      assert File.exists?(Path.join(path, ".git"))

      # Cleanup
      File.rm_rf!(path)
    end

    test "initializes with git config" do
      path = FixtureHelper.git_fixture_repo()

      # Check git config
      {output, 0} = System.cmd("git", ["config", "user.email"], cd: path)
      assert String.trim(output) == "test@example.com"

      {output, 0} = System.cmd("git", ["config", "user.name"], cd: path)
      assert String.trim(output) == "Test User"

      # Cleanup
      File.rm_rf!(path)
    end

    test "creates unique repos on multiple calls" do
      path1 = FixtureHelper.git_fixture_repo()
      path2 = FixtureHelper.git_fixture_repo()

      assert path1 != path2
      assert File.exists?(path1)
      assert File.exists?(path2)

      # Cleanup
      File.rm_rf!(path1)
      File.rm_rf!(path2)
    end

    test "repo is writable" do
      path = FixtureHelper.git_fixture_repo()

      # Create a test file
      test_file = Path.join(path, "test.txt")
      File.write!(test_file, "test content")

      assert File.exists?(test_file)
      assert File.read!(test_file) == "test content"

      # Cleanup
      File.rm_rf!(path)
    end

    test "can add and commit files" do
      path = FixtureHelper.git_fixture_repo()

      # Create and stage a file
      test_file = Path.join(path, "README.md")
      File.write!(test_file, "# Test Repo")

      {_output, 0} = System.cmd("git", ["add", "README.md"], cd: path)
      {_output, 0} = System.cmd("git", ["commit", "-m", "Initial commit"], cd: path)

      # Verify commit was created
      {output, 0} = System.cmd("git", ["log", "--oneline"], cd: path)
      assert output =~ "Initial commit"

      # Cleanup
      File.rm_rf!(path)
    end
  end

  describe "fixture cleanup" do
    test "cleanup happens on test exit" do
      # Register cleanup
      path = FixtureHelper.git_fixture_repo()

      on_exit(fn ->
        File.rm_rf!(path)
      end)

      assert File.exists?(path)
    end

    test "cleanup_git_fixture/1 removes directory" do
      path = FixtureHelper.git_fixture_repo()

      assert File.exists?(path)

      FixtureHelper.cleanup_git_fixture(path)

      refute File.exists?(path)
    end

    test "cleanup is safe when path doesn't exist" do
      fake_path = "/tmp/nonexistent_#{:erlang.unique_integer()}"

      # Should not raise
      assert :ok = FixtureHelper.cleanup_git_fixture(fake_path)
    end
  end

  describe "fixture path resolution" do
    test "resolves path relative to test/fixtures" do
      path = FixtureHelper.fixture_path("prompt_sets/simple_set.json")

      assert path =~ "test/fixtures/prompt_sets/simple_set.json"
    end

    test "handles nested paths correctly" do
      path = FixtureHelper.fixture_path("provider_responses/claude/tool_call.json")

      assert path =~ "test/fixtures/provider_responses/claude/tool_call.json"
    end

    test "absolute path when needed" do
      path = FixtureHelper.fixture_path("test.json", absolute: true)

      assert Path.type(path) == :absolute
    end
  end

  describe "fixture validation" do
    test "validates fixture file exists" do
      assert FixtureHelper.fixture_exists?("prompt_sets/simple_set.json") == true
    end

    test "returns false for non-existent fixture" do
      assert FixtureHelper.fixture_exists?("nonexistent/file.json") == false
    end

    test "validates fixture is readable" do
      assert FixtureHelper.fixture_readable?("prompt_sets/simple_set.json") == true
    end
  end

  describe "VCS fixtures" do
    test "loads git status clean fixture" do
      status = FixtureHelper.load_vcs_fixture("git_status_clean.txt")

      assert is_binary(status)
      assert status != ""
    end

    test "loads git status dirty fixture" do
      status = FixtureHelper.load_vcs_fixture("git_status_dirty.txt")

      assert is_binary(status)
      assert status =~ "modified:" or status =~ "Changes"
    end

    test "loads git diff sample" do
      diff = FixtureHelper.load_vcs_fixture("git_diff_sample.txt")

      assert is_binary(diff)
      assert diff =~ "diff --git" or diff =~ "@@"
    end
  end

  describe "approval fixtures" do
    test "loads pending approval fixture" do
      approval = FixtureHelper.load_approval_fixture("pending_approval")

      assert is_map(approval)
      assert approval["status"] == "pending"
    end

    test "loads approved item fixture" do
      approval = FixtureHelper.load_approval_fixture("approved_item")

      assert is_map(approval)
      assert approval["status"] == "approved"
      assert approval["approved_by"] != nil
    end

    test "loads rejected item fixture" do
      approval = FixtureHelper.load_approval_fixture("rejected_item")

      assert is_map(approval)
      assert approval["status"] == "rejected"
      assert approval["rejection_reason"] != nil
    end
  end
end
