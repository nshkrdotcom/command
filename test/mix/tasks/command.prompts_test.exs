defmodule Mix.Tasks.Command.PromptsTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Command.Prompts

  describe "argument parsing" do
    test "parsing --help flag" do
      {opts, _} = Prompts.parse_args(["--help"])
      assert opts[:help] == true
    end

    test "parsing --config flag correctly" do
      {opts, _} = Prompts.parse_args(["--config", "my_config.exs"])
      assert opts[:config] == "my_config.exs"
    end

    test "detecting missing --config flag for commands that need it" do
      {opts, _} = Prompts.parse_args(["--list"])
      assert opts[:config] == nil
    end

    test "parsing --list command" do
      {opts, _} = Prompts.parse_args(["--config", "c.exs", "--list"])
      assert opts[:list] == true
    end

    test "parsing --validate command" do
      {opts, _} = Prompts.parse_args(["--config", "c.exs", "--validate"])
      assert opts[:validate] == true
    end

    test "parsing --dry-run with target" do
      {opts, rest} = Prompts.parse_args(["--config", "c.exs", "--dry-run", "01"])
      assert opts[:dry_run] == true
      assert "01" in rest
    end

    test "parsing --run with single target" do
      {opts, rest} = Prompts.parse_args(["--config", "c.exs", "--run", "01"])
      assert opts[:run] == true
      assert "01" in rest
    end

    test "parsing --run --phase N" do
      {opts, _} = Prompts.parse_args(["--config", "c.exs", "--run", "--phase", "2"])
      assert opts[:run] == true
      assert opts[:phase] == 2
    end

    test "parsing --run --all" do
      {opts, _} = Prompts.parse_args(["--config", "c.exs", "--run", "--all"])
      assert opts[:run] == true
      assert opts[:all] == true
    end

    test "parsing --run --continue" do
      {opts, _} = Prompts.parse_args(["--config", "c.exs", "--run", "--continue"])
      assert opts[:run] == true
      assert opts[:continue] == true
    end

    test "parsing --plan-only with target" do
      {opts, rest} = Prompts.parse_args(["--config", "c.exs", "--plan-only", "01"])
      assert opts[:plan_only] == true
      assert "01" in rest
    end

    test "parsing --provider and --model overrides" do
      {opts, _} =
        Prompts.parse_args([
          "--config",
          "c.exs",
          "--run",
          "--all",
          "--provider",
          "codex",
          "--model",
          "o3"
        ])

      assert opts[:provider] == "codex"
      assert opts[:model] == "o3"
    end

    test "parsing --no-commit flag" do
      {opts, _} = Prompts.parse_args(["--config", "c.exs", "--run", "--all", "--no-commit"])
      assert opts[:no_commit] == true
    end

    test "parsing --partial-mode flag" do
      {opts, _} =
        Prompts.parse_args([
          "--config",
          "c.exs",
          "--run",
          "--all",
          "--partial-mode",
          "continue"
        ])

      assert opts[:partial_mode] == "continue"
    end

    test "parsing --partial-continue flag" do
      {opts, _} =
        Prompts.parse_args(["--config", "c.exs", "--run", "--continue", "--partial-continue"])

      assert opts[:partial_continue] == true
    end

    test "parsing --force-continue flag" do
      {opts, _} =
        Prompts.parse_args(["--config", "c.exs", "--run", "--continue", "--force-continue"])

      assert opts[:force_continue] == true
    end

    test "parsing --repo-override NAME:PATH (repeatable)" do
      {opts, _} =
        Prompts.parse_args([
          "--config",
          "c.exs",
          "--run",
          "--all",
          "--repo-override",
          "command:/tmp/cmd",
          "--repo-override",
          "flowstone:/tmp/fs"
        ])

      assert opts[:repo_override] == ["command:/tmp/cmd", "flowstone:/tmp/fs"]
    end

    test "parsing --file-only flag" do
      {opts, _} = Prompts.parse_args(["--config", "c.exs", "--run", "--all", "--file-only"])
      assert opts[:file_only] == true
    end

    test "parsing --verbose flag" do
      {opts, _} = Prompts.parse_args(["--config", "c.exs", "--run", "--all", "--verbose"])
      assert opts[:verbose] == true
    end

    test "parsing --quiet flag" do
      {opts, _} = Prompts.parse_args(["--config", "c.exs", "--run", "--all", "--quiet"])
      assert opts[:quiet] == true
    end
  end

  describe "validate_flags/1" do
    test "detects invalid flag combination --db and --file-only" do
      opts = [db: true, file_only: true]
      assert {:error, _message} = Prompts.validate_flags(opts)
    end

    test "accepts valid flag combinations" do
      opts = [config: "c.exs", run: true, all: true]
      assert :ok = Prompts.validate_flags(opts)
    end

    test "detects missing config for run command" do
      opts = [run: true, all: true]
      assert {:error, _message} = Prompts.validate_flags(opts)
    end
  end

  describe "build_targets/3" do
    test "builds target list from --all flag" do
      opts = [all: true]
      all_nums = ["01", "02", "03"]

      targets = Prompts.build_targets(opts, [], all_nums)
      assert targets == ["01", "02", "03"]
    end

    test "builds target list from --phase flag" do
      opts = [phase: 2]
      phase_nums = %{1 => ["01", "02"], 2 => ["03", "04"]}

      targets = Prompts.build_targets(opts, [], phase_nums)
      assert targets == ["03", "04"]
    end

    test "builds target list from positional args" do
      opts = []
      rest = ["01", "03"]

      targets = Prompts.build_targets(opts, rest, ["01", "02", "03"])
      assert targets == ["01", "03"]
    end
  end
end
