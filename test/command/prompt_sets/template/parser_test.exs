defmodule Command.PromptSets.Template.ParserTest do
  use ExUnit.Case, async: true

  alias Command.PromptSets.Template.Parser

  describe "parse/1 - simple variables" do
    test "parses simple variable" do
      assert {:ok, [{:var, [:name], nil}]} = Parser.parse("{{name}}")
    end

    test "parses variable with surrounding text" do
      assert {:ok, [{:text, "Hello "}, {:var, [:name], nil}, {:text, "!"}]} =
               Parser.parse("Hello {{name}}!")
    end

    test "parses nested variable with dot notation" do
      assert {:ok, [{:var, [:a, :b, :c], nil}]} = Parser.parse("{{a.b.c}}")
    end

    test "parses two-level nested variable" do
      assert {:ok, [{:var, [:config, :model], nil}]} = Parser.parse("{{config.model}}")
    end

    test "parses plain text without any template syntax" do
      assert {:ok, [{:text, "just plain text"}]} = Parser.parse("just plain text")
    end

    test "parses empty string" do
      assert {:ok, []} = Parser.parse("")
    end
  end

  describe "parse/1 - default values" do
    test "parses variable with string default" do
      assert {:ok, [{:var, [:name], "World"}]} =
               Parser.parse(~s[{{name | default: "World"}}])
    end

    test "parses variable with single-quoted default" do
      assert {:ok, [{:var, [:name], "World"}]} =
               Parser.parse("{{name | default: 'World'}}")
    end

    test "parses variable with integer default" do
      assert {:ok, [{:var, [:count], 0}]} =
               Parser.parse("{{count | default: 0}}")
    end

    test "parses variable with boolean default" do
      assert {:ok, [{:var, [:flag], true}]} =
               Parser.parse("{{flag | default: true}}")
    end

    test "parses nested variable with default" do
      assert {:ok, [{:var, [:config, :model], "gpt-4"}]} =
               Parser.parse(~s[{{config.model | default: "gpt-4"}}])
    end
  end

  describe "parse/1 - if conditionals" do
    test "parses simple if block" do
      assert {:ok, [{:if, [:show], [{:text, "visible"}], []}]} =
               Parser.parse("{{#if show}}visible{{/if}}")
    end

    test "parses if-else block" do
      assert {:ok, [{:if, [:show], [{:text, "yes"}], [{:text, "no"}]}]} =
               Parser.parse("{{#if show}}yes{{else}}no{{/if}}")
    end

    test "parses if with nested variable condition" do
      assert {:ok, [{:if, [:config, :debug], [{:text, "debug mode"}], []}]} =
               Parser.parse("{{#if config.debug}}debug mode{{/if}}")
    end

    test "parses if block with template variables inside" do
      assert {:ok,
              [
                {:if, [:show], [{:text, "Hello "}, {:var, [:name], nil}], []}
              ]} = Parser.parse("{{#if show}}Hello {{name}}{{/if}}")
    end

    test "parses nested if blocks" do
      template = "{{#if a}}{{#if b}}inner{{/if}}{{/if}}"

      assert {:ok,
              [
                {:if, [:a], [{:if, [:b], [{:text, "inner"}], []}], []}
              ]} = Parser.parse(template)
    end
  end

  describe "parse/1 - unless conditionals" do
    test "parses simple unless block" do
      assert {:ok, [{:unless, [:hidden], [{:text, "shown"}]}]} =
               Parser.parse("{{#unless hidden}}shown{{/unless}}")
    end

    test "parses unless with nested condition" do
      assert {:ok, [{:unless, [:config, :disabled], [{:text, "enabled"}]}]} =
               Parser.parse("{{#unless config.disabled}}enabled{{/unless}}")
    end
  end

  describe "parse/1 - partials" do
    test "parses partial include" do
      assert {:ok, [{:partial, "header"}]} = Parser.parse("{{> header}}")
    end

    test "parses partial with hyphenated name" do
      assert {:ok, [{:partial, "tdd-instructions"}]} =
               Parser.parse("{{> tdd-instructions}}")
    end

    test "parses partial with underscored name" do
      assert {:ok, [{:partial, "code_conventions"}]} =
               Parser.parse("{{> code_conventions}}")
    end
  end

  describe "parse/1 - mixed content" do
    test "parses template with multiple features" do
      template = """
      # {{prompt_name}}

      {{#if run_tests}}
      ## TDD Instructions
      {{> tdd-instructions}}
      {{/if}}

      Project: {{project_name | default: "Unknown"}}
      """

      assert {:ok, nodes} = Parser.parse(template)
      assert length(nodes) > 1

      # Verify structure contains expected node types
      node_types =
        Enum.map(nodes, fn
          {type, _} -> type
          {type, _, _} -> type
          {type, _, _, _} -> type
        end)

      assert :text in node_types
      assert :var in node_types
      assert :if in node_types
    end
  end

  describe "parse/1 - error cases" do
    test "returns error for unclosed if block" do
      assert {:error, {:parse, msg}} = Parser.parse("{{#if show}}text")
      assert msg =~ "unclosed"
    end

    test "returns error for unclosed unless block" do
      assert {:error, {:parse, msg}} = Parser.parse("{{#unless show}}text")
      assert msg =~ "unclosed"
    end

    test "returns error for invalid variable name" do
      assert {:error, {:parse, _msg}} = Parser.parse("{{123invalid}}")
    end

    test "returns error for invalid condition" do
      assert {:error, {:parse, _msg}} = Parser.parse("{{#if 123}}")
    end

    test "returns error for invalid default syntax" do
      assert {:error, {:parse, _msg}} = Parser.parse("{{name | invalid}}")
    end

    test "returns error for non-string input" do
      assert {:error, {:parse, "template must be a string"}} = Parser.parse(123)
    end

    test "returns error for unquoted default value" do
      assert {:error, {:parse, _msg}} = Parser.parse("{{name | default: unquoted}}")
    end
  end
end
