defmodule Command.PromptSets.Template.CompilerTest do
  use ExUnit.Case, async: true

  alias Command.PromptSets.Template.{Parser, Compiler}

  describe "compile/1 - valid templates" do
    test "compiles valid text node" do
      ast = [{:text, "hello"}]
      assert {:ok, ^ast} = Compiler.compile(ast)
    end

    test "compiles valid variable node" do
      ast = [{:var, [:name], nil}]
      assert {:ok, ^ast} = Compiler.compile(ast)
    end

    test "compiles variable with default" do
      ast = [{:var, [:name], "default"}]
      assert {:ok, ^ast} = Compiler.compile(ast)
    end

    test "compiles valid if node" do
      ast = [{:if, [:show], [{:text, "visible"}], []}]
      assert {:ok, ^ast} = Compiler.compile(ast)
    end

    test "compiles valid if-else node" do
      ast = [{:if, [:show], [{:text, "yes"}], [{:text, "no"}]}]
      assert {:ok, ^ast} = Compiler.compile(ast)
    end

    test "compiles valid unless node" do
      ast = [{:unless, [:hidden], [{:text, "shown"}]}]
      assert {:ok, ^ast} = Compiler.compile(ast)
    end

    test "compiles valid partial node" do
      ast = [{:partial, "header"}]
      assert {:ok, ^ast} = Compiler.compile(ast)
    end

    test "compiles complex mixed AST" do
      ast = [
        {:text, "Hello "},
        {:var, [:name], nil},
        {:if, [:show], [{:text, "visible"}], [{:text, "hidden"}]},
        {:unless, [:disabled], [{:partial, "footer"}]},
        {:var, [:count], 0}
      ]

      assert {:ok, ^ast} = Compiler.compile(ast)
    end

    test "compiled AST is idempotent" do
      ast = [{:text, "hello"}, {:var, [:name], nil}]
      assert {:ok, first} = Compiler.compile(ast)
      assert {:ok, second} = Compiler.compile(first)
      assert first == second
    end
  end

  describe "compile/1 - integration with parser" do
    test "parser output compiles successfully" do
      {:ok, ast} = Parser.parse("Hello {{name}}! {{#if show}}visible{{/if}}")
      assert {:ok, _compiled} = Compiler.compile(ast)
    end

    test "compiled output is executable by renderer" do
      {:ok, ast} = Parser.parse("Hello {{name}}!")
      assert {:ok, compiled} = Compiler.compile(ast)
      assert is_list(compiled)
      assert length(compiled) == 3
    end
  end

  describe "compile/1 - error cases" do
    test "rejects empty variable path" do
      ast = [{:var, [], nil}]
      assert {:error, {:compile, msg}} = Compiler.compile(ast)
      assert msg =~ "empty path"
    end

    test "rejects variable path exceeding max depth" do
      ast = [{:var, [:a, :b, :c, :d], nil}]
      assert {:error, {:compile, msg}} = Compiler.compile(ast)
      assert msg =~ "max depth"
    end

    test "rejects non-atom path segments" do
      ast = [{:var, ["name"], nil}]
      assert {:error, {:compile, msg}} = Compiler.compile(ast)
      assert msg =~ "atoms"
    end

    test "rejects empty if condition path" do
      ast = [{:if, [], [{:text, "x"}], []}]
      assert {:error, {:compile, msg}} = Compiler.compile(ast)
      assert msg =~ "empty path"
    end

    test "rejects empty unless condition path" do
      ast = [{:unless, [], [{:text, "x"}]}]
      assert {:error, {:compile, msg}} = Compiler.compile(ast)
      assert msg =~ "empty path"
    end

    test "rejects empty partial name" do
      ast = [{:partial, ""}]
      assert {:error, {:compile, msg}} = Compiler.compile(ast)
      assert msg =~ "empty"
    end

    test "rejects non-list AST" do
      assert {:error, {:compile, msg}} = Compiler.compile("not a list")
      assert msg =~ "list"
    end

    test "rejects unknown node type" do
      ast = [{:unknown, "data"}]
      assert {:error, {:compile, msg}} = Compiler.compile(ast)
      assert msg =~ "unknown node type"
    end

    test "error includes line information" do
      ast = [{:text, "line1\nline2\n"}, {:var, [], nil}]
      assert {:error, {:compile, msg}} = Compiler.compile(ast)
      assert msg =~ "line 3"
    end
  end
end
