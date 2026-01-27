defmodule Command.PromptSets.Template.Compiler do
  @moduledoc """
  Validates and normalizes the template AST produced by the parser.

  The compiler performs structural validation on the AST to ensure it is
  well-formed before rendering. This includes checking that all nodes
  have valid structure, paths are non-empty, and nested nodes are valid.

  No EEx or Code.eval is used. The compiled AST is a validated version
  of the parser's output, ready for the renderer to walk.
  """

  alias Command.PromptSets.Template.Parser

  @doc """
  Compiles (validates and normalizes) a parsed AST.

  Returns `{:ok, validated_ast}` if the AST is valid, or
  `{:error, reason}` if validation fails.

  ## Examples

      iex> Compiler.compile([{:text, "hello"}, {:var, [:name], nil}])
      {:ok, [{:text, "hello"}, {:var, [:name], nil}]}

      iex> Compiler.compile([{:var, [], nil}])
      {:error, {:compile, "variable node has empty path"}}
  """
  @spec compile([Parser.ast_node()]) :: {:ok, [Parser.ast_node()]} | {:error, term()}
  def compile(ast) when is_list(ast) do
    case validate_nodes(ast, 1) do
      :ok -> {:ok, ast}
      {:error, _} = error -> error
    end
  end

  def compile(_), do: {:error, {:compile, "AST must be a list of nodes"}}

  # ============================================================================
  # Validation
  # ============================================================================

  defp validate_nodes([], _line), do: :ok

  defp validate_nodes([node | rest], line) do
    case validate_node(node, line) do
      {:ok, next_line} -> validate_nodes(rest, next_line)
      {:error, _} = error -> error
    end
  end

  defp validate_node({:text, text}, line) when is_binary(text) do
    # Count newlines for line tracking
    newlines = text |> String.graphemes() |> Enum.count(&(&1 == "\n"))
    {:ok, line + newlines}
  end

  defp validate_node({:text, _}, line) do
    {:error, {:compile, "text node value must be a string at line #{line}"}}
  end

  defp validate_node({:var, path, default}, line) do
    cond do
      not is_list(path) ->
        {:error, {:compile, "variable path must be a list at line #{line}"}}

      path == [] ->
        {:error, {:compile, "variable node has empty path at line #{line}"}}

      not Enum.all?(path, &is_atom/1) ->
        {:error, {:compile, "variable path segments must be atoms at line #{line}"}}

      length(path) > 3 ->
        {:error, {:compile, "variable path exceeds max depth of 3 at line #{line}"}}

      not valid_default?(default) ->
        {:error, {:compile, "invalid default value at line #{line}"}}

      true ->
        {:ok, line}
    end
  end

  defp validate_node({:if, path, true_body, else_body}, line) do
    with {:ok, _} <- validate_condition_path(path, "if", line),
         :ok <- validate_nodes(true_body, line),
         :ok <- validate_nodes(else_body, line) do
      {:ok, line}
    end
  end

  defp validate_node({:unless, path, body}, line) do
    with {:ok, _} <- validate_condition_path(path, "unless", line),
         :ok <- validate_nodes(body, line) do
      {:ok, line}
    end
  end

  defp validate_node({:partial, name}, line) when is_binary(name) do
    if name == "" do
      {:error, {:compile, "partial name cannot be empty at line #{line}"}}
    else
      {:ok, line}
    end
  end

  defp validate_node({:partial, _}, line) do
    {:error, {:compile, "partial name must be a string at line #{line}"}}
  end

  defp validate_node(node, line) do
    {:error, {:compile, "unknown node type: #{inspect(node)} at line #{line}"}}
  end

  defp validate_condition_path(path, block_type, line) do
    cond do
      not is_list(path) ->
        {:error, {:compile, "#{block_type} condition path must be a list at line #{line}"}}

      path == [] ->
        {:error, {:compile, "#{block_type} condition has empty path at line #{line}"}}

      not Enum.all?(path, &is_atom/1) ->
        {:error,
         {:compile, "#{block_type} condition path segments must be atoms at line #{line}"}}

      true ->
        {:ok, line}
    end
  end

  defp valid_default?(nil), do: true
  defp valid_default?(v) when is_binary(v), do: true
  defp valid_default?(v) when is_boolean(v), do: true
  defp valid_default?(v) when is_integer(v), do: true
  defp valid_default?(_), do: false
end
