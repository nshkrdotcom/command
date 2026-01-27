defmodule Command.CLI.ConfigLoaderTest do
  use ExUnit.Case, async: true

  alias Command.CLI.ConfigLoader

  @fixtures_dir Path.expand("../../fixtures/cli", __DIR__)

  describe "load/1" do
    test "loads valid config file successfully" do
      config_path = Path.join(@fixtures_dir, "valid_config.exs")
      assert {:ok, config} = ConfigLoader.load(config_path)
      assert config.project_dir
      assert config.prompts_file
      assert config.commit_messages_file
    end

    test "returns error for non-existent file" do
      config_path = Path.join(@fixtures_dir, "nonexistent.exs")
      assert {:error, {:file_not_found, _}} = ConfigLoader.load(config_path)
    end

    test "returns error for invalid config syntax" do
      config_path = Path.join(@fixtures_dir, "invalid_syntax.exs")
      assert {:error, {:config_error, _}} = ConfigLoader.load(config_path)
    end

    test "returns error for non-map config" do
      config_path = Path.join(@fixtures_dir, "non_map_config.exs")
      assert {:error, :invalid_config} = ConfigLoader.load(config_path)
    end
  end

  describe "validate/1" do
    test "validates all required fields are present" do
      config = %{
        project_dir: "/path/to/project",
        prompts_file: "prompts.txt",
        commit_messages_file: "commit-messages.txt",
        log_dir: "logs",
        model: "claude-sonnet-4"
      }

      assert :ok = ConfigLoader.validate(config)
    end

    test "detects missing required fields" do
      config = %{
        project_dir: "/path/to/project"
      }

      assert {:error, {:missing_fields, fields}} = ConfigLoader.validate(config)
      assert :prompts_file in fields
      assert :commit_messages_file in fields
    end
  end

  describe "get_all_prompts/1" do
    test "returns all prompts from prompts file" do
      config_path = Path.join(@fixtures_dir, "valid_config.exs")
      {:ok, config} = ConfigLoader.load(config_path)

      assert {:ok, prompts} = ConfigLoader.get_all_prompts(config)
      assert is_list(prompts)
      assert length(prompts) > 0
    end

    test "parses prompt format correctly" do
      config = %{
        prompts_file: Path.join(@fixtures_dir, "prompts.txt")
      }

      {:ok, prompts} = ConfigLoader.get_all_prompts(config)
      [prompt | _] = prompts

      assert prompt.num
      assert prompt.phase
      assert prompt.sp
      assert prompt.name
      assert prompt.file
    end

    test "parses target_repos when present" do
      config = %{
        prompts_file: Path.join(@fixtures_dir, "multi_repo_prompts.txt")
      }

      {:ok, prompts} = ConfigLoader.get_all_prompts(config)
      multi_repo = Enum.find(prompts, &(&1.target_repos != nil))

      assert multi_repo
      assert is_list(multi_repo.target_repos)
      assert length(multi_repo.target_repos) > 0
    end

    test "expands @group references in target_repos" do
      config = %{
        prompts_file: Path.join(@fixtures_dir, "group_prompts.txt"),
        repo_groups: %{
          "backend" => ["command", "flowstone"],
          "frontend" => ["portfolio_core", "portfolio_index"]
        }
      }

      {:ok, prompts} = ConfigLoader.get_all_prompts(config)
      group_prompt = Enum.find(prompts, &(&1.target_repos && "@backend" in &1.target_repos_raw))

      assert group_prompt
      assert "command" in group_prompt.target_repos
      assert "flowstone" in group_prompt.target_repos
    end
  end

  describe "get_all_nums/1" do
    test "returns sorted list of prompt numbers" do
      config = %{
        prompts_file: Path.join(@fixtures_dir, "prompts.txt")
      }

      {:ok, nums} = ConfigLoader.get_all_nums(config)
      assert is_list(nums)
      assert nums == Enum.sort(nums)
    end
  end

  describe "get_phase_nums/2" do
    test "returns prompt numbers for specific phase" do
      config = %{
        prompts_file: Path.join(@fixtures_dir, "prompts.txt")
      }

      {:ok, nums} = ConfigLoader.get_phase_nums(config, 1)
      assert is_list(nums)
      assert length(nums) > 0
    end

    test "returns empty list for non-existent phase" do
      config = %{
        prompts_file: Path.join(@fixtures_dir, "prompts.txt")
      }

      {:ok, nums} = ConfigLoader.get_phase_nums(config, 999)
      assert nums == []
    end
  end

  describe "get_prompt/2" do
    test "gets single prompt by number" do
      config = %{
        prompts_file: Path.join(@fixtures_dir, "prompts.txt")
      }

      assert {:ok, prompt} = ConfigLoader.get_prompt(config, "01")
      assert prompt.num == "01"
    end

    test "returns error for non-existent prompt" do
      config = %{
        prompts_file: Path.join(@fixtures_dir, "prompts.txt")
      }

      assert {:error, :not_found} = ConfigLoader.get_prompt(config, "999")
    end
  end

  describe "apply_overrides/2" do
    test "applies CLI flag overrides to config" do
      config = %{
        project_dir: "/original/path",
        model: "claude-sonnet-4",
        provider: :claude
      }

      opts = [
        project_dir: "/override/path",
        model: "o3",
        provider: "codex"
      ]

      result = ConfigLoader.apply_overrides(config, opts)
      assert result.project_dir == "/override/path"
      assert result.model == "o3"
      assert result.provider == :codex
    end

    test "applies repo_override flags" do
      config = %{
        target_repos: [
          %{name: "command", path: "/original/command"},
          %{name: "flowstone", path: "/original/flowstone"}
        ]
      }

      opts = [
        repo_override: ["command:/override/command", "flowstone:/override/flowstone"]
      ]

      result = ConfigLoader.apply_overrides(config, opts)
      command_repo = Enum.find(result.target_repos, &(&1.name == "command"))
      assert command_repo.path == "/override/command"
    end

    test "preserves nil overrides" do
      config = %{model: "claude-sonnet-4"}
      opts = [model: nil]

      result = ConfigLoader.apply_overrides(config, opts)
      assert result.model == "claude-sonnet-4"
    end
  end

  describe "commit message parsing" do
    test "parses commit messages file format" do
      config = %{
        commit_messages_file: Path.join(@fixtures_dir, "commit-messages.txt")
      }

      {:ok, messages} = ConfigLoader.parse_commit_messages(config)
      assert is_map(messages)
      assert messages["01"]
    end

    test "parses per-repo commit messages" do
      config = %{
        commit_messages_file: Path.join(@fixtures_dir, "multi_repo_commits.txt")
      }

      {:ok, messages} = ConfigLoader.parse_commit_messages(config)
      assert messages["02:command"]
      assert messages["02:flowstone"]
    end

    test "validates repo names in markers" do
      config = %{
        commit_messages_file: Path.join(@fixtures_dir, "invalid_repo_marker.txt")
      }

      assert {:error, {:invalid_repo_name, _}} = ConfigLoader.parse_commit_messages(config)
    end

    test "treats escaped marker lines as content" do
      config = %{
        commit_messages_file: Path.join(@fixtures_dir, "escaped_markers.txt")
      }

      {:ok, messages} = ConfigLoader.parse_commit_messages(config)
      message = messages["01"]
      assert message =~ "=== COMMIT"
    end

    test "treats lines with leading space as content" do
      config = %{
        commit_messages_file: Path.join(@fixtures_dir, "spaced_markers.txt")
      }

      {:ok, messages} = ConfigLoader.parse_commit_messages(config)
      message = messages["01"]
      assert message =~ "=== COMMIT"
    end
  end

  describe "phase_names validation" do
    test "validates phase_names mapping" do
      config = %{
        phase_names: %{
          1 => "Foundation",
          2 => "Implementation"
        }
      }

      assert :ok = ConfigLoader.validate_phase_names(config)
    end

    test "accepts nil phase_names" do
      config = %{phase_names: nil}
      assert :ok = ConfigLoader.validate_phase_names(config)
    end
  end

  describe "events_mode parsing" do
    test "parses and validates events_mode" do
      config = %{events_mode: "compact"}
      assert :ok = ConfigLoader.validate_events_mode(config)

      config = %{events_mode: "full"}
      assert :ok = ConfigLoader.validate_events_mode(config)

      config = %{events_mode: "off"}
      assert :ok = ConfigLoader.validate_events_mode(config)
    end

    test "rejects invalid events_mode" do
      config = %{events_mode: "invalid"}

      assert {:error, {:invalid_events_mode, "invalid"}} =
               ConfigLoader.validate_events_mode(config)
    end

    test "normalizes events_mode" do
      config = %{events_mode: "COMPACT"}
      normalized = ConfigLoader.normalize_events_mode(config)
      assert normalized.events_mode == :compact
    end
  end

  describe "prompt_overrides parsing" do
    test "parses prompt_overrides with permission_mode" do
      config = %{
        prompt_overrides: %{
          "02" => %{permission_mode: :plan}
        }
      }

      assert :ok = ConfigLoader.validate_prompt_overrides(config)
    end

    test "parses prompt_overrides with execution_mode" do
      config = %{
        prompt_overrides: %{
          "02" => %{execution_mode: :workspace}
        }
      }

      assert :ok = ConfigLoader.validate_prompt_overrides(config)
    end

    test "parses provider option maps" do
      config = %{
        prompt_overrides: %{
          "02" => %{
            claude_opts: %{max_tokens: 1024},
            codex_opts: %{timeout: 60000},
            codex_thread_opts: %{thinking_budget: 10000}
          }
        }
      }

      assert :ok = ConfigLoader.validate_prompt_overrides(config)
    end
  end

  describe "workspace_root validation" do
    test "validates workspace_root when present" do
      config = %{
        workspace_root: "/home/user/workspace",
        target_repos: [
          %{name: "command", path: "/home/user/workspace/command"},
          %{name: "flowstone", path: "/home/user/workspace/flowstone"}
        ]
      }

      assert :ok = ConfigLoader.validate_workspace_root(config)
    end

    test "rejects workspace_root when repos not contained" do
      config = %{
        workspace_root: "/home/user/workspace",
        target_repos: [
          %{name: "command", path: "/other/path/command"}
        ]
      }

      assert {:error, {:repo_not_in_workspace, _}} = ConfigLoader.validate_workspace_root(config)
    end

    test "accepts nil workspace_root" do
      config = %{
        workspace_root: nil,
        target_repos: [
          %{name: "command", path: "/any/path/command"}
        ]
      }

      assert :ok = ConfigLoader.validate_workspace_root(config)
    end
  end
end
