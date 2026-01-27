defmodule Command.PromptSets.Template.RendererTest do
  use ExUnit.Case, async: true

  alias Command.PromptSets.Template.Renderer

  describe "render/3 - variable substitution" do
    test "substitutes simple variable" do
      ast = [{:text, "Hello "}, {:var, [:name], nil}, {:text, "!"}]
      assert {:ok, "Hello World!"} = Renderer.render(ast, %{name: "World"})
    end

    test "substitutes nested variable" do
      ast = [{:var, [:config, :model], nil}]
      assert {:ok, "gpt-4"} = Renderer.render(ast, %{config: %{model: "gpt-4"}})
    end

    test "substitutes deeply nested variable" do
      ast = [{:var, [:a, :b, :c], nil}]
      assert {:ok, "deep"} = Renderer.render(ast, %{a: %{b: %{c: "deep"}}})
    end

    test "converts non-string values to string" do
      ast = [{:var, [:count], nil}]
      assert {:ok, "42"} = Renderer.render(ast, %{count: 42})
    end
  end

  describe "render/3 - default values" do
    test "uses default when variable is missing" do
      ast = [{:var, [:name], "World"}]
      assert {:ok, "World"} = Renderer.render(ast, %{})
    end

    test "uses actual value when variable is present" do
      ast = [{:var, [:name], "Default"}]
      assert {:ok, "Alice"} = Renderer.render(ast, %{name: "Alice"})
    end

    test "uses default with integer value" do
      ast = [{:var, [:count], 0}]
      assert {:ok, "0"} = Renderer.render(ast, %{})
    end
  end

  describe "render/3 - if conditionals" do
    test "renders true branch when condition is truthy" do
      ast = [{:if, [:show], [{:text, "visible"}], []}]
      assert {:ok, "visible"} = Renderer.render(ast, %{show: true})
    end

    test "renders empty when condition is false" do
      ast = [{:if, [:show], [{:text, "visible"}], []}]
      assert {:ok, ""} = Renderer.render(ast, %{show: false})
    end

    test "renders empty when condition is nil" do
      ast = [{:if, [:show], [{:text, "visible"}], []}]
      assert {:ok, ""} = Renderer.render(ast, %{show: nil})
    end

    test "renders else branch when condition is false" do
      ast = [{:if, [:show], [{:text, "yes"}], [{:text, "no"}]}]
      assert {:ok, "no"} = Renderer.render(ast, %{show: false})
    end

    test "renders else branch when condition is missing" do
      ast = [{:if, [:show], [{:text, "yes"}], [{:text, "no"}]}]
      assert {:ok, "no"} = Renderer.render(ast, %{})
    end

    test "string value is truthy" do
      ast = [{:if, [:val], [{:text, "yes"}], []}]
      assert {:ok, "yes"} = Renderer.render(ast, %{val: "non-empty"})
    end

    test "empty string is truthy" do
      # In Elixir, empty string is truthy (not nil or false)
      ast = [{:if, [:val], [{:text, "yes"}], []}]
      assert {:ok, "yes"} = Renderer.render(ast, %{val: ""})
    end

    test "nested if condition" do
      ast = [{:if, [:config, :debug], [{:text, "debug"}], []}]
      assert {:ok, "debug"} = Renderer.render(ast, %{config: %{debug: true}})
    end
  end

  describe "render/3 - unless conditionals" do
    test "renders body when condition is false" do
      ast = [{:unless, [:hidden], [{:text, "shown"}]}]
      assert {:ok, "shown"} = Renderer.render(ast, %{hidden: false})
    end

    test "renders body when condition is nil" do
      ast = [{:unless, [:hidden], [{:text, "shown"}]}]
      assert {:ok, "shown"} = Renderer.render(ast, %{hidden: nil})
    end

    test "renders body when condition is missing" do
      ast = [{:unless, [:hidden], [{:text, "shown"}]}]
      assert {:ok, "shown"} = Renderer.render(ast, %{})
    end

    test "skips body when condition is true" do
      ast = [{:unless, [:hidden], [{:text, "shown"}]}]
      assert {:ok, ""} = Renderer.render(ast, %{hidden: true})
    end

    test "skips body when condition is truthy string" do
      ast = [{:unless, [:hidden], [{:text, "shown"}]}]
      assert {:ok, ""} = Renderer.render(ast, %{hidden: "yes"})
    end
  end

  describe "render/3 - strict mode" do
    test "strict mode returns error for missing variable" do
      ast = [{:var, [:missing], nil}]
      assert {:error, {:render, msg}} = Renderer.render(ast, %{}, strict: true)
      assert msg =~ "undefined variable"
      assert msg =~ "missing"
    end

    test "strict mode is the default" do
      ast = [{:var, [:missing], nil}]
      assert {:error, {:render, _}} = Renderer.render(ast, %{})
    end
  end

  describe "render/3 - lenient mode" do
    test "lenient mode returns empty string for missing variable" do
      ast = [{:var, [:missing], nil}]
      assert {:ok, ""} = Renderer.render(ast, %{}, strict: false)
    end

    test "lenient mode still renders present variables" do
      ast = [{:text, "Hello "}, {:var, [:name], nil}]
      assert {:ok, "Hello World"} = Renderer.render(ast, %{name: "World"}, strict: false)
    end
  end

  describe "render/3 - partials" do
    test "renders partial from context" do
      partial_ast = [{:text, "partial content"}]
      ast = [{:partial, "header"}]
      assigns = %{__partials__: %{"header" => partial_ast}}

      assert {:ok, "partial content"} = Renderer.render(ast, assigns)
    end

    test "renders partial with variables" do
      partial_ast = [{:text, "Hello "}, {:var, [:name], nil}]
      ast = [{:partial, "greeting"}]
      assigns = %{__partials__: %{"greeting" => partial_ast}, name: "World"}

      assert {:ok, "Hello World"} = Renderer.render(ast, assigns)
    end

    test "returns error for missing partial" do
      ast = [{:partial, "missing"}]
      assigns = %{__partials__: %{}}

      assert {:error, {:render, msg}} = Renderer.render(ast, assigns)
      assert msg =~ "partial not found"
    end

    test "returns error when no partials loaded" do
      ast = [{:partial, "header"}]

      assert {:error, {:render, msg}} = Renderer.render(ast, %{})
      assert msg =~ "partial not found"
    end
  end

  describe "render/3 - complex templates" do
    test "renders complex template with multiple features" do
      ast = [
        {:text, "# "},
        {:var, [:prompt_name], nil},
        {:text, "\n\n"},
        {:if, [:run_tests],
         [
           {:text, "## Testing\nRun tests with TDD.\n"}
         ], []},
        {:text, "\nProject: "},
        {:var, [:project], "Unknown"},
        {:text, "\n"}
      ]

      assigns = %{
        prompt_name: "Setup",
        run_tests: true,
        project: "MyApp"
      }

      assert {:ok, result} = Renderer.render(ast, assigns)
      assert result =~ "# Setup"
      assert result =~ "## Testing"
      assert result =~ "Project: MyApp"
    end

    test "renders complex template with false conditional" do
      ast = [
        {:text, "Header\n"},
        {:if, [:run_tests],
         [
           {:text, "Tests section\n"}
         ], [{:text, "No tests\n"}]},
        {:text, "Footer\n"}
      ]

      assigns = %{run_tests: false}

      assert {:ok, result} = Renderer.render(ast, assigns, strict: false)
      assert result =~ "Header"
      assert result =~ "No tests"
      assert result =~ "Footer"
      refute result =~ "Tests section"
    end
  end

  describe "render/3 - text only" do
    test "renders text-only template" do
      ast = [{:text, "Just plain text"}]
      assert {:ok, "Just plain text"} = Renderer.render(ast, %{})
    end

    test "renders empty AST" do
      assert {:ok, ""} = Renderer.render([], %{})
    end
  end
end
