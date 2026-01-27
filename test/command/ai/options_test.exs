defmodule Command.AI.OptionsTest do
  use ExUnit.Case, async: true

  alias Command.AI.Options

  describe "merge/3" do
    test "applies prompt-set defaults, run overrides, then prompt overrides in order" do
      defaults = %{permission_mode: :auto, allowed_tools: ["Read", "Write"]}
      run_opts = %{permission_mode: :confirm}
      prompt_opts = %{permission_mode: :deny}

      result = Options.merge(defaults, run_opts, prompt_opts)

      # Prompt overrides win
      assert result.permission_mode == :deny
      # Defaults preserved when not overridden
      assert result.allowed_tools == ["Read", "Write"]
    end

    test "preserves permission_mode overrides per prompt" do
      defaults = %{permission_mode: :auto}
      run_opts = %{}
      prompt_opts = %{permission_mode: :confirm}

      result = Options.merge(defaults, run_opts, prompt_opts)

      assert result.permission_mode == :confirm
    end

    test "deep-merges claude_opts across layers" do
      defaults = %{
        claude_opts: %{model: "claude-sonnet-4-20250514", max_tokens: 4096}
      }

      run_opts = %{
        claude_opts: %{max_tokens: 8192}
      }

      prompt_opts = %{
        claude_opts: %{temperature: 0.5}
      }

      result = Options.merge(defaults, run_opts, prompt_opts)

      # All three layers merged
      assert result.claude_opts.model == "claude-sonnet-4-20250514"
      assert result.claude_opts.max_tokens == 8192
      assert result.claude_opts.temperature == 0.5
    end

    test "deep-merges codex_opts across layers" do
      defaults = %{
        codex_opts: %{model: "gpt-4.1", temperature: 0.7}
      }

      run_opts = %{
        codex_opts: %{temperature: 0.9}
      }

      prompt_opts = %{}

      result = Options.merge(defaults, run_opts, prompt_opts)

      assert result.codex_opts.model == "gpt-4.1"
      assert result.codex_opts.temperature == 0.9
    end

    test "deep-merges codex_thread_opts across layers" do
      defaults = %{
        codex_thread_opts: %{sandbox: true, timeout: 30_000}
      }

      run_opts = %{
        codex_thread_opts: %{timeout: 60_000}
      }

      prompt_opts = %{}

      result = Options.merge(defaults, run_opts, prompt_opts)

      assert result.codex_thread_opts.sandbox == true
      assert result.codex_thread_opts.timeout == 60_000
    end

    test "leaves provider-specific option maps intact for the adapter layer" do
      defaults = %{
        claude_opts: %{model: "claude-sonnet-4"},
        codex_opts: %{model: "gpt-4.1"},
        codex_thread_opts: %{sandbox: true}
      }

      result = Options.merge(defaults, %{}, %{})

      assert is_map(result.claude_opts)
      assert is_map(result.codex_opts)
      assert is_map(result.codex_thread_opts)
    end

    test "handles empty maps gracefully" do
      result = Options.merge(%{}, %{}, %{})
      assert result == %{}
    end

    test "scalar keys use last-wins override" do
      defaults = %{allowed_tools: ["Read"]}
      run_opts = %{allowed_tools: ["Read", "Write"]}
      prompt_opts = %{allowed_tools: ["Bash"]}

      result = Options.merge(defaults, run_opts, prompt_opts)

      assert result.allowed_tools == ["Bash"]
    end
  end

  describe "merge_layer/2" do
    test "merges two layers with override precedence" do
      base = %{permission_mode: :auto, claude_opts: %{model: "a", max_tokens: 100}}
      overrides = %{claude_opts: %{max_tokens: 200}}

      result = Options.merge_layer(base, overrides)

      assert result.permission_mode == :auto
      assert result.claude_opts.model == "a"
      assert result.claude_opts.max_tokens == 200
    end

    test "handles nil-like inputs gracefully" do
      assert Options.merge_layer(%{a: 1}, %{b: 2}) == %{a: 1, b: 2}
    end
  end

  describe "provider_opts/2" do
    test "extracts claude options as keyword list" do
      opts = %{
        claude_opts: %{model: "claude-sonnet-4", max_tokens: 4096},
        permission_mode: :confirm
      }

      result = Options.provider_opts(opts, :claude)

      assert Keyword.get(result, :model) == "claude-sonnet-4"
      assert Keyword.get(result, :max_tokens) == 4096
      assert Keyword.get(result, :permission_mode) == :confirm
    end

    test "extracts codex options with thread_opts" do
      opts = %{
        codex_opts: %{model: "gpt-4.1"},
        codex_thread_opts: %{sandbox: true},
        permission_mode: :auto
      }

      result = Options.provider_opts(opts, :codex)

      assert Keyword.get(result, :model) == "gpt-4.1"
      assert Keyword.get(result, :permission_mode) == :auto

      thread_opts = Keyword.get(result, :thread_opts)
      assert Keyword.get(thread_opts, :sandbox) == true
    end

    test "returns empty keyword list when no provider opts set" do
      opts = %{}

      claude_result = Options.provider_opts(opts, :claude)
      codex_result = Options.provider_opts(opts, :codex)

      assert is_list(claude_result)
      assert is_list(codex_result)
    end
  end

  describe "permission_mode/1" do
    test "returns permission mode from options" do
      assert Options.permission_mode(%{permission_mode: :confirm}) == :confirm
      assert Options.permission_mode(%{permission_mode: :deny}) == :deny
      assert Options.permission_mode(%{permission_mode: :auto}) == :auto
    end

    test "defaults to :auto when not set" do
      assert Options.permission_mode(%{}) == :auto
    end
  end

  describe "allowed_tools/1" do
    test "returns allowed tools list" do
      opts = %{allowed_tools: ["Read", "Write", "Bash"]}
      assert Options.allowed_tools(opts) == ["Read", "Write", "Bash"]
    end

    test "returns nil when not set" do
      assert Options.allowed_tools(%{}) == nil
    end
  end
end
