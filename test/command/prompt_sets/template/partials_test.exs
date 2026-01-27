defmodule Command.PromptSets.Template.PartialsTest do
  use ExUnit.Case, async: true

  alias Command.PromptSets.Template.Partials

  @tmp_dir System.tmp_dir!()

  setup do
    # Create a unique temp directory for each test
    dir = Path.join(@tmp_dir, "partials_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, partials_dir: dir}
  end

  describe "load_all/1" do
    test "loads a single partial from directory", %{partials_dir: dir} do
      File.write!(Path.join(dir, "header.md"), "# Header\n")

      assert {:ok, partials} = Partials.load_all(dir)
      assert Map.has_key?(partials, "header")
      assert [{:text, "# Header\n"}] = partials["header"]
    end

    test "loads multiple partials", %{partials_dir: dir} do
      File.write!(Path.join(dir, "header.md"), "# Header")
      File.write!(Path.join(dir, "footer.md"), "---\nFooter")
      File.write!(Path.join(dir, "tdd-instructions.md"), "Use TDD")

      assert {:ok, partials} = Partials.load_all(dir)
      assert map_size(partials) == 3
      assert Map.has_key?(partials, "header")
      assert Map.has_key?(partials, "footer")
      assert Map.has_key?(partials, "tdd-instructions")
    end

    test "loads partial with template syntax", %{partials_dir: dir} do
      File.write!(Path.join(dir, "greeting.md"), "Hello {{name}}!")

      assert {:ok, partials} = Partials.load_all(dir)
      assert Map.has_key?(partials, "greeting")

      # The AST should contain a variable node
      ast = partials["greeting"]
      assert [{:text, "Hello "}, {:var, [:name], nil}, {:text, "!"}] = ast
    end

    test "returns empty map for non-existent directory" do
      assert {:ok, %{}} = Partials.load_all("/non/existent/path")
    end

    test "returns empty map for empty directory", %{partials_dir: dir} do
      assert {:ok, %{}} = Partials.load_all(dir)
    end

    test "returns error for partial with invalid syntax", %{partials_dir: dir} do
      File.write!(Path.join(dir, "bad.md"), "{{#if unclosed}}")

      assert {:error, {:partial, "bad", _reason}} = Partials.load_all(dir)
    end

    test "only loads .md files", %{partials_dir: dir} do
      File.write!(Path.join(dir, "valid.md"), "content")
      File.write!(Path.join(dir, "ignored.txt"), "not loaded")

      assert {:ok, partials} = Partials.load_all(dir)
      assert map_size(partials) == 1
      assert Map.has_key?(partials, "valid")
    end
  end

  describe "load_one/2" do
    test "loads a single partial by name", %{partials_dir: dir} do
      File.write!(Path.join(dir, "header.md"), "# Header")

      assert {:ok, ast} = Partials.load_one(dir, "header")
      assert [{:text, "# Header"}] = ast
    end

    test "returns error for missing partial", %{partials_dir: dir} do
      assert {:error, {:partial_not_found, "missing"}} = Partials.load_one(dir, "missing")
    end

    test "returns error for partial with invalid syntax", %{partials_dir: dir} do
      File.write!(Path.join(dir, "bad.md"), "{{#if unclosed}}")

      assert {:error, {:partial, "bad", _reason}} = Partials.load_one(dir, "bad")
    end
  end
end
