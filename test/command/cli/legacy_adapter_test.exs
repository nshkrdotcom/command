defmodule Command.CLI.LegacyAdapterTest do
  use ExUnit.Case, async: true

  alias Command.CLI.LegacyAdapter

  @fixtures_dir Path.expand("../../fixtures/cli", __DIR__)

  describe "load_legacy_config/1" do
    test "loads and converts legacy config to PromptSet struct" do
      config_path = Path.join(@fixtures_dir, "valid_config.exs")
      assert {:ok, prompt_set} = LegacyAdapter.load_legacy_config(config_path)

      assert prompt_set.name
      assert prompt_set.slug
      assert is_list(prompt_set.prompts)
      assert is_map(prompt_set.commit_messages)
      assert is_map(prompt_set.config)
    end

    test "returns error for non-existent config file" do
      assert {:error, {:file_not_found, _}} =
               LegacyAdapter.load_legacy_config("/nonexistent/path.exs")
    end
  end

  describe "parse_prompt_line/1" do
    test "parses standard 5-field prompt line" do
      line = "01|1|3|Database schema|prompts/01-schema.md"
      assert {:ok, prompt} = LegacyAdapter.parse_prompt_line(line)

      assert prompt.num == "01"
      assert prompt.phase == 1
      assert prompt.sp == 3
      assert prompt.name == "Database schema"
      assert prompt.file == "prompts/01-schema.md"
      assert prompt.target_repos == nil
    end

    test "parses 6-field prompt line with target_repos" do
      line = "02|1|5|FlowStone resources|prompts/02-flowstone.md|command,flowstone"
      assert {:ok, prompt} = LegacyAdapter.parse_prompt_line(line)

      assert prompt.num == "02"
      assert prompt.target_repos_raw == ["command", "flowstone"]
      assert prompt.target_repos == ["command", "flowstone"]
    end

    test "handles malformed prompt lines with clear error" do
      line = "not|enough|fields"
      assert {:error, {:malformed_prompt_line, _}} = LegacyAdapter.parse_prompt_line(line)
    end

    test "handles empty line" do
      assert {:error, {:malformed_prompt_line, _}} = LegacyAdapter.parse_prompt_line("")
    end

    test "skips comment lines" do
      line = "# This is a comment"
      assert :skip = LegacyAdapter.parse_prompt_line(line)
    end
  end

  describe "parse_prompt_line/2 with repo_groups" do
    test "expands @group references using repo_groups" do
      line = "02|1|5|Backend work|prompts/02-backend.md|@backend"

      repo_groups = %{
        "backend" => ["command", "flowstone"],
        "frontend" => ["portfolio_core", "portfolio_index"]
      }

      assert {:ok, prompt} = LegacyAdapter.parse_prompt_line(line, repo_groups)

      assert prompt.target_repos_raw == ["@backend"]
      assert prompt.target_repos == ["command", "flowstone"]
    end

    test "mixes direct repos and @group references" do
      line = "04|2|5|Mixed work|prompts/04-mixed.md|command,@frontend"

      repo_groups = %{
        "frontend" => ["portfolio_core", "portfolio_index"]
      }

      assert {:ok, prompt} = LegacyAdapter.parse_prompt_line(line, repo_groups)

      assert prompt.target_repos == ["command", "portfolio_core", "portfolio_index"]
    end
  end

  describe "parse_commit_messages/1" do
    test "parses single commit messages correctly" do
      content = """
      === COMMIT 01 ===
      feat(schema): Add database schema

      - Add tables
      - Add migrations

      === COMMIT 02 ===
      feat(core): Core implementation
      """

      assert {:ok, messages} = LegacyAdapter.parse_commit_messages(content)
      assert Map.has_key?(messages, "01")
      assert Map.has_key?(messages, "02")
      assert messages["01"] =~ "feat(schema)"
    end

    test "parses per-repo commit messages" do
      content = """
      === COMMIT 02:command ===
      feat(command): Add FlowStone bindings

      === COMMIT 02:flowstone ===
      feat(flowstone): Add resources
      """

      assert {:ok, messages} = LegacyAdapter.parse_commit_messages(content)
      assert messages["02:command"] =~ "FlowStone bindings"
      assert messages["02:flowstone"] =~ "resources"
    end

    test "rejects invalid repo names in commit markers" do
      content = """
      === COMMIT 01:invalid repo name! ===
      This should fail
      """

      assert {:error, {:invalid_repo_name, _}} = LegacyAdapter.parse_commit_messages(content)
    end

    test "treats escaped marker lines as content" do
      content = """
      === COMMIT 01 ===
      Test commit

      This contains a literal marker:
      \\=== COMMIT 02 ===

      That should be content.
      """

      assert {:ok, messages} = LegacyAdapter.parse_commit_messages(content)
      assert messages["01"] =~ "=== COMMIT 02 ==="
      refute Map.has_key?(messages, "02")
    end
  end

  describe "to_prompt_set/1" do
    test "converts config map to PromptSet-compatible map" do
      config = %{
        project_dir: "/home/user/project",
        prompts_file: Path.join(@fixtures_dir, "prompts.txt"),
        commit_messages_file: Path.join(@fixtures_dir, "commit-messages.txt"),
        progress_file: ".progress",
        log_dir: "logs",
        model: "claude-sonnet-4-20250514",
        provider: :claude,
        allowed_tools: ["Read", "Write"],
        permission_mode: :accept_edits,
        log_mode: :compact,
        log_meta: :none,
        events_mode: :compact,
        phase_names: %{1 => "Foundation", 2 => "Implementation"}
      }

      assert {:ok, prompt_set} = LegacyAdapter.to_prompt_set(config)

      assert prompt_set.name
      assert prompt_set.slug
      assert is_list(prompt_set.prompts)
      assert length(prompt_set.prompts) == 3
      assert is_map(prompt_set.commit_messages)
      assert prompt_set.config.project_dir == "/home/user/project"
      assert prompt_set.config.default_model == "claude-sonnet-4-20250514"
    end

    test "preserves all config fields during conversion" do
      config = %{
        project_dir: "/tmp/test",
        prompts_file: Path.join(@fixtures_dir, "prompts.txt"),
        commit_messages_file: Path.join(@fixtures_dir, "commit-messages.txt"),
        log_dir: "logs",
        model: "claude-sonnet-4-20250514",
        provider: :claude,
        allowed_tools: ["Read", "Write"],
        permission_mode: :accept_edits,
        log_mode: :compact,
        log_meta: :none,
        events_mode: :compact,
        workspace_root: "/tmp"
      }

      assert {:ok, prompt_set} = LegacyAdapter.to_prompt_set(config)

      assert prompt_set.config.project_dir == "/tmp/test"
      assert prompt_set.config.default_provider == "claude"
      assert prompt_set.config.allowed_tools == ["Read", "Write"]
      assert prompt_set.config.permission_mode == :accept_edits
      assert prompt_set.config.workspace_root == "/tmp"
    end
  end
end
