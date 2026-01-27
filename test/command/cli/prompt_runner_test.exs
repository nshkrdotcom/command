defmodule Command.CLI.PromptRunnerTest do
  use ExUnit.Case, async: true

  alias Command.CLI.PromptRunner

  describe "execute/3" do
    test "executes single prompt successfully in file-only mode" do
      prompt = %{
        num: "01",
        name: "Test prompt",
        file: "prompts/01-test.md",
        phase: 1,
        sp: 3,
        target_repos: nil
      }

      config = %{
        project_dir: "/tmp/test",
        model: "claude-sonnet-4",
        provider: :claude,
        log_dir: "/tmp/logs",
        db_enabled: false,
        file_mirror: false,
        no_commit: true
      }

      # In file-only mode with no_commit, execute returns a result struct
      result = PromptRunner.execute(prompt, config, dry_run: true)
      assert result.prompt_num == "01"
      assert result.status in [:dry_run, :skipped]
    end
  end

  describe "execute_targets/3" do
    test "builds execution plan for multiple prompt numbers" do
      config = %{
        project_dir: "/tmp/test",
        model: "claude-sonnet-4",
        provider: :claude,
        log_dir: "/tmp/logs",
        db_enabled: false,
        file_mirror: false,
        no_commit: true
      }

      prompts = [
        %{num: "01", name: "First", file: "01.md", phase: 1, sp: 3, target_repos: nil},
        %{num: "02", name: "Second", file: "02.md", phase: 1, sp: 5, target_repos: nil}
      ]

      plan = PromptRunner.build_plan(prompts, config)
      assert length(plan) == 2
      assert Enum.map(plan, & &1.prompt_num) == ["01", "02"]
    end
  end

  describe "no-commit mode" do
    test "with --no-commit, result has commit_status of no_commit" do
      prompt = %{
        num: "01",
        name: "Test",
        file: "01.md",
        phase: 1,
        sp: 3,
        target_repos: nil
      }

      config = %{
        project_dir: "/tmp/test",
        model: "claude-sonnet-4",
        provider: :claude,
        log_dir: "/tmp/logs",
        db_enabled: false,
        file_mirror: false,
        no_commit: true
      }

      result = PromptRunner.execute(prompt, config, dry_run: true)
      assert result.commit_status == :no_commit
    end
  end

  describe "resume_point_detection/1" do
    test "detects first incomplete prompt as resume point" do
      states = [
        %{num: "01", status: :completed},
        %{num: "02", status: :completed},
        %{num: "03", status: :pending},
        %{num: "04", status: :pending}
      ]

      assert PromptRunner.find_resume_point(states) == "03"
    end

    test "returns nil when all completed" do
      states = [
        %{num: "01", status: :completed},
        %{num: "02", status: :completed}
      ]

      assert PromptRunner.find_resume_point(states) == nil
    end

    test "treats failed as resume point" do
      states = [
        %{num: "01", status: :completed},
        %{num: "02", status: :failed}
      ]

      assert PromptRunner.find_resume_point(states) == "02"
    end

    test "treats stale running as resume point" do
      ten_mins_ago = DateTime.add(DateTime.utc_now(), -601, :second)

      states = [
        %{num: "01", status: :completed},
        %{num: "02", status: :running, started_at: ten_mins_ago}
      ]

      assert PromptRunner.find_resume_point(states, stale_timeout_seconds: 600) == "02"
    end
  end

  describe "build_plan/2" do
    test "creates execution plan entries" do
      prompts = [
        %{num: "01", name: "First", file: "01.md", phase: 1, sp: 3, target_repos: nil},
        %{
          num: "02",
          name: "Second",
          file: "02.md",
          phase: 1,
          sp: 5,
          target_repos: ["command", "flowstone"]
        }
      ]

      config = %{
        project_dir: "/tmp/test",
        model: "claude-sonnet-4",
        provider: :claude,
        no_commit: false
      }

      plan = PromptRunner.build_plan(prompts, config)
      assert length(plan) == 2

      [p1, p2] = plan
      assert p1.prompt_num == "01"
      assert p1.target_repos == nil
      assert p2.prompt_num == "02"
      assert p2.target_repos == ["command", "flowstone"]
    end
  end

  describe "telemetry events" do
    test "emits start telemetry event" do
      ref =
        :telemetry.attach(
          "test-prompt-started",
          [:command, :prompt, :started],
          fn _event, _measurements, metadata, _config ->
            send(self(), {:telemetry, :started, metadata})
          end,
          nil
        )

      PromptRunner.emit_telemetry(:started, %{prompt_num: "01", prompt_name: "Test"})

      assert_receive {:telemetry, :started, %{prompt_num: "01"}}

      :telemetry.detach("test-prompt-started")
    end

    test "emits completed telemetry event" do
      ref =
        :telemetry.attach(
          "test-prompt-completed",
          [:command, :prompt, :completed],
          fn _event, measurements, metadata, _config ->
            send(self(), {:telemetry, :completed, metadata, measurements})
          end,
          nil
        )

      PromptRunner.emit_telemetry(:completed, %{prompt_num: "01"}, %{duration_ms: 5000})

      assert_receive {:telemetry, :completed, %{prompt_num: "01"}, %{duration_ms: 5000}}

      :telemetry.detach("test-prompt-completed")
    end
  end
end
