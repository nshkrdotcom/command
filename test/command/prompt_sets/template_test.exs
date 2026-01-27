defmodule Command.PromptSets.TemplateTest do
  use ExUnit.Case, async: true

  alias Command.PromptSets.Template

  @tmp_dir System.tmp_dir!()

  describe "compile/1" do
    test "compiles a simple template" do
      assert {:ok, compiled} = Template.compile("Hello {{name}}!")
      assert is_list(compiled)
    end

    test "compile returns error for invalid syntax" do
      assert {:error, _} = Template.compile("{{#if unclosed}}")
    end

    test "compile returns error for invalid variable" do
      assert {:error, _} = Template.compile("{{123bad}}")
    end
  end

  describe "render/3" do
    test "renders compiled template with context" do
      {:ok, compiled} = Template.compile("Hello {{name}}!")
      assert {:ok, "Hello World!"} = Template.render(compiled, %{name: "World"})
    end

    test "renders with strict mode (default)" do
      {:ok, compiled} = Template.compile("{{missing}}")
      assert {:error, _} = Template.render(compiled, %{})
    end

    test "renders with lenient mode" do
      {:ok, compiled} = Template.compile("Hello {{missing}}!")
      assert {:ok, "Hello !"} = Template.render(compiled, %{}, strict: false)
    end
  end

  describe "compile_and_render/3" do
    test "compiles and renders in one call" do
      assert {:ok, "Hello World!"} =
               Template.compile_and_render("Hello {{name}}!", %{name: "World"})
    end

    test "handles conditionals" do
      template = "{{#if show}}visible{{else}}hidden{{/if}}"

      assert {:ok, "visible"} =
               Template.compile_and_render(template, %{show: true})

      assert {:ok, "hidden"} =
               Template.compile_and_render(template, %{show: false})
    end

    test "handles defaults" do
      assert {:ok, "Hello Default!"} =
               Template.compile_and_render(
                 ~s[Hello {{name | default: "Default"}}!],
                 %{}
               )
    end

    test "handles partials from directory" do
      dir = Path.join(@tmp_dir, "partials_facade_test_#{:erlang.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "greeting.md"), "Hi there!")

      on_exit(fn -> File.rm_rf!(dir) end)

      assert {:ok, result} =
               Template.compile_and_render(
                 "Start {{> greeting}} End",
                 %{},
                 partials_dir: dir
               )

      assert result =~ "Hi there!"
    end

    test "returns error for invalid template" do
      assert {:error, _} = Template.compile_and_render("{{#if bad}}", %{})
    end

    test "strict mode fails on missing variable" do
      assert {:error, _} =
               Template.compile_and_render("{{missing}}", %{}, strict: true)
    end

    test "lenient mode allows missing variables" do
      assert {:ok, ""} =
               Template.compile_and_render("{{missing}}", %{}, strict: false)
    end
  end

  describe "validate/1" do
    test "returns :ok for valid template" do
      assert :ok = Template.validate("Hello {{name}}!")
    end

    test "returns :ok for template with conditionals" do
      assert :ok = Template.validate("{{#if show}}text{{/if}}")
    end

    test "returns :ok for template with partials" do
      assert :ok = Template.validate("{{> header}}")
    end

    test "returns :ok for template with defaults" do
      assert :ok = Template.validate(~s[{{name | default: "x"}}])
    end

    test "returns :ok for plain text" do
      assert :ok = Template.validate("just plain text")
    end

    test "returns error for invalid syntax" do
      assert {:error, _} = Template.validate("{{#if unclosed}}")
    end

    test "returns error for invalid variable" do
      assert {:error, _} = Template.validate("{{123}}")
    end
  end

  describe "end-to-end template rendering" do
    test "complex template with all features" do
      dir = Path.join(@tmp_dir, "partials_e2e_test_#{:erlang.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "conventions.md"), "Follow TDD principles.")

      on_exit(fn -> File.rm_rf!(dir) end)

      template = """
      # {{prompt_name}}

      Phase: {{phase_name | default: "Unknown"}}

      {{#if run_tests}}
      ## Testing
      {{> conventions}}
      {{/if}}

      {{#unless skip_review}}
      ## Code Review Required
      {{/unless}}

      Project: {{project_name | default: "MyProject"}}
      """

      context = %{
        prompt_name: "Implementation",
        run_tests: true,
        skip_review: false
      }

      assert {:ok, result} =
               Template.compile_and_render(template, context, partials_dir: dir)

      assert result =~ "# Implementation"
      assert result =~ "Phase: Unknown"
      assert result =~ "## Testing"
      assert result =~ "Follow TDD principles."
      assert result =~ "## Code Review Required"
      assert result =~ "Project: MyProject"
    end
  end
end
