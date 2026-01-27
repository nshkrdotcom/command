defmodule Command.PromptSets.TemplateContextTest do
  use ExUnit.Case, async: true

  alias Command.PromptSets.TemplateContext
  alias Command.PromptSets.{PromptSet, PromptSetRun}

  defp build_run(opts \\ %{}) do
    prompt_set = %PromptSet{
      id: Ecto.UUID.generate(),
      name: "Test Set",
      slug: "test-set",
      prompts:
        opts[:prompts] ||
          [
            %{
              "num" => "01",
              "name" => "First Prompt",
              "phase" => 1,
              "target_repos" => ["command"],
              "template_vars" => opts[:template_vars]
            }
          ],
      phase_names: opts[:phase_names] || %{"1" => "Foundation"},
      config:
        opts[:config] ||
          %{
            "project_dir" => "/tmp/test",
            "default_model" => "claude-sonnet-4-20250514",
            "workspace_root" => "/home/workspace"
          },
      status: "active"
    }

    %PromptSetRun{
      id: opts[:run_id] || Ecto.UUID.generate(),
      prompt_set_id: prompt_set.id,
      prompt_set: prompt_set,
      status: "running",
      config_snapshot: opts[:run_config] || %{},
      total_prompts: length(prompt_set.prompts)
    }
  end

  describe "build/3 - built-in variables" do
    test "includes timestamp" do
      run = build_run()
      context = TemplateContext.build(run, "01")

      assert is_binary(context[:timestamp])
      assert context[:timestamp] =~ ~r/^\d{4}-\d{2}-\d{2}T/
    end

    test "includes date" do
      run = build_run()
      context = TemplateContext.build(run, "01")

      assert is_binary(context[:date])
      assert context[:date] =~ ~r/^\d{4}-\d{2}-\d{2}$/
    end

    test "includes prompt_num" do
      run = build_run()
      context = TemplateContext.build(run, "01")

      assert context[:prompt_num] == "01"
    end

    test "includes prompt_name from prompt definition" do
      run = build_run()
      context = TemplateContext.build(run, "01")

      assert context[:prompt_name] == "First Prompt"
    end

    test "includes run_id" do
      run = build_run(%{run_id: "test-run-id"})
      context = TemplateContext.build(run, "01")

      assert context[:run_id] == "test-run-id"
    end

    test "includes phase and phase_name" do
      run = build_run()
      context = TemplateContext.build(run, "01")

      assert context[:phase] == 1
      assert context[:phase_name] == "Foundation"
    end

    test "includes target_repos" do
      run = build_run()
      context = TemplateContext.build(run, "01")

      assert context[:target_repos] == ["command"]
    end

    test "includes workspace_root from config" do
      run = build_run()
      context = TemplateContext.build(run, "01")

      assert context[:workspace_root] == "/home/workspace"
    end

    test "includes repo context when provided" do
      run = build_run()

      repo_ctx = %{
        current_repo: "command",
        current_repo_path: "/home/repos/command",
        workspace_root: "/home/override"
      }

      context = TemplateContext.build(run, "01", repo_ctx)

      assert context[:current_repo] == "command"
      assert context[:current_repo_path] == "/home/repos/command"
      assert context[:workspace_root] == "/home/override"
    end
  end

  describe "build/3 - config merge" do
    test "prompt set config merged into context" do
      run = build_run(%{config: %{"project_dir" => "/tmp/test", "model" => "gpt-4"}})
      context = TemplateContext.build(run, "01")

      assert context[:project_dir] == "/tmp/test"
      assert context[:model] == "gpt-4"
    end

    test "run config overrides prompt set config" do
      run =
        build_run(%{
          config: %{"model" => "gpt-4"},
          run_config: %{"model" => "claude-sonnet"}
        })

      context = TemplateContext.build(run, "01")

      assert context[:model] == "claude-sonnet"
    end

    test "step config (template_vars) overrides run config" do
      run =
        build_run(%{
          config: %{"model" => "gpt-4"},
          run_config: %{"model" => "claude-sonnet"},
          template_vars: %{"model" => "custom-model"}
        })

      context = TemplateContext.build(run, "01")

      assert context[:model] == "custom-model"
    end

    test "nested configs merged correctly" do
      run =
        build_run(%{
          config: %{
            "nested" => %{"a" => 1, "b" => 2}
          },
          run_config: %{
            "nested" => %{"b" => 3, "c" => 4}
          }
        })

      context = TemplateContext.build(run, "01")

      assert context[:nested] == %{a: 1, b: 3, c: 4}
    end

    test "resolved config exposed under config key" do
      run =
        build_run(%{
          config: %{"model" => "gpt-4", "debug" => false},
          run_config: %{"debug" => true}
        })

      context = TemplateContext.build(run, "01")

      assert is_map(context[:config])
      assert context[:config][:model] == "gpt-4"
      assert context[:config][:debug] == true
    end

    test "string keys converted to atoms" do
      run = build_run(%{config: %{"string_key" => "value"}})
      context = TemplateContext.build(run, "01")

      assert context[:string_key] == "value"
      refute Map.has_key?(context, "string_key")
    end

    test "empty configs handled gracefully" do
      run = build_run(%{config: %{}, run_config: %{}, template_vars: nil})
      context = TemplateContext.build(run, "01")

      # Should still have built-in vars
      assert is_binary(context[:timestamp])
      assert context[:prompt_num] == "01"
    end

    test "missing prompt definition returns empty defaults" do
      run = build_run()
      context = TemplateContext.build(run, "99")

      assert context[:prompt_num] == "99"
      assert context[:prompt_name] == nil
    end
  end

  describe "built_in_vars/3" do
    test "returns map of built-in variables" do
      run = build_run()
      vars = TemplateContext.built_in_vars(run, "01")

      assert is_map(vars)
      assert Map.has_key?(vars, :timestamp)
      assert Map.has_key?(vars, :date)
      assert Map.has_key?(vars, :prompt_num)
      assert Map.has_key?(vars, :prompt_name)
      assert Map.has_key?(vars, :run_id)
      assert Map.has_key?(vars, :phase)
      assert Map.has_key?(vars, :phase_name)
    end
  end

  describe "deep_merge/2" do
    test "merges flat maps" do
      assert %{a: 1, b: 2} = TemplateContext.deep_merge(%{a: 1}, %{b: 2})
    end

    test "right overrides left" do
      assert %{a: 2} = TemplateContext.deep_merge(%{a: 1}, %{a: 2})
    end

    test "deep merges nested maps" do
      left = %{nested: %{a: 1, b: 2}}
      right = %{nested: %{b: 3, c: 4}}

      assert %{nested: %{a: 1, b: 3, c: 4}} = TemplateContext.deep_merge(left, right)
    end
  end

  describe "atomize_keys/1" do
    test "converts string keys to atoms" do
      assert %{name: "test"} = TemplateContext.atomize_keys(%{"name" => "test"})
    end

    test "handles nested maps" do
      input = %{"outer" => %{"inner" => "value"}}
      assert %{outer: %{inner: "value"}} = TemplateContext.atomize_keys(input)
    end

    test "preserves atom keys" do
      assert %{name: "test"} = TemplateContext.atomize_keys(%{name: "test"})
    end

    test "handles non-map values" do
      assert "string" = TemplateContext.atomize_keys("string")
      assert 42 = TemplateContext.atomize_keys(42)
    end

    test "handles lists" do
      input = [%{"a" => 1}, %{"b" => 2}]
      assert [%{a: 1}, %{b: 2}] = TemplateContext.atomize_keys(input)
    end
  end
end
