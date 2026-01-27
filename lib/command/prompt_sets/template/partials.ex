defmodule Command.PromptSets.Template.Partials do
  @moduledoc """
  Loads and caches partial templates from a directory.

  Partials are `.md` files in the configured partials directory.
  Each partial is parsed and compiled at load time, and the resulting
  AST is cached by filename (without extension) for rendering.

  ## Example

  Given a partials directory with:

      _partials/
      ├── tdd-instructions.md
      └── conventions.md

  Loading produces:

      %{
        "tdd-instructions" => [{:text, "..."}, ...],
        "conventions" => [{:text, "..."}, ...]
      }
  """

  alias Command.PromptSets.Template.{Parser, Compiler}

  @doc """
  Loads all partial templates from the given directory.

  Returns `{:ok, map}` where map keys are partial names (filename without
  `.md` extension) and values are compiled ASTs.

  If the directory does not exist, returns `{:ok, %{}}`.

  ## Examples

      iex> Partials.load_all("/path/to/partials")
      {:ok, %{"header" => [{:text, "# Header\\n"}], ...}}
  """
  @spec load_all(String.t()) :: {:ok, map()} | {:error, term()}
  def load_all(partials_dir) do
    if File.dir?(partials_dir) do
      partials_dir
      |> Path.join("*.md")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.reduce_while({:ok, %{}}, fn path, {:ok, acc} ->
        name = Path.basename(path, ".md")

        with {:ok, content} <- File.read(path),
             {:ok, ast} <- Parser.parse(content),
             {:ok, compiled} <- Compiler.compile(ast) do
          {:cont, {:ok, Map.put(acc, name, compiled)}}
        else
          {:error, reason} ->
            {:halt, {:error, {:partial, name, reason}}}
        end
      end)
    else
      {:ok, %{}}
    end
  end

  @doc """
  Loads a single partial by name from the given directory.

  The name should not include the `.md` extension.

  ## Examples

      iex> Partials.load_one("/path/to/partials", "header")
      {:ok, [{:text, "# Header\\n"}]}
  """
  @spec load_one(String.t(), String.t()) :: {:ok, [Parser.ast_node()]} | {:error, term()}
  def load_one(partials_dir, name) do
    path = Path.join(partials_dir, "#{name}.md")

    if File.exists?(path) do
      with {:ok, content} <- File.read(path),
           {:ok, ast} <- Parser.parse(content),
           {:ok, compiled} <- Compiler.compile(ast) do
        {:ok, compiled}
      else
        {:error, reason} ->
          {:error, {:partial, name, reason}}
      end
    else
      {:error, {:partial_not_found, name}}
    end
  end
end
