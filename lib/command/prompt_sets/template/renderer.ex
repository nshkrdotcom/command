defmodule Command.PromptSets.Template.Renderer do
  @moduledoc """
  Renders compiled template AST with a context map.

  The renderer walks the AST and evaluates each node against the provided
  context (assigns). No `Code.eval` or `EEx` is used — rendering is a
  simple recursive tree walk with map lookups.

  ## Modes

  - **Strict mode** (default): Missing variables return an error.
  - **Lenient mode**: Missing variables are replaced with empty strings.

  ## Examples

      iex> Renderer.render([{:text, "Hello "}, {:var, [:name], nil}], %{name: "World"})
      {:ok, "Hello World"}

      iex> Renderer.render([{:var, [:missing], nil}], %{}, strict: false)
      {:ok, ""}
  """

  alias Command.PromptSets.Template.Parser

  @doc """
  Renders a compiled AST with the given context.

  ## Options

  - `:strict` - If `true` (default), missing variables return an error.
    If `false`, missing variables are replaced with empty strings.
  """
  @spec render([Parser.ast_node()], map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def render(compiled, assigns, opts \\ []) when is_list(compiled) and is_map(assigns) do
    strict = Keyword.get(opts, :strict, true)

    case render_nodes(compiled, assigns, strict) do
      {:ok, parts} -> {:ok, IO.iodata_to_binary(parts)}
      {:error, _} = error -> error
    end
  end

  # ============================================================================
  # Node Rendering
  # ============================================================================

  defp render_nodes(nodes, assigns, strict) do
    Enum.reduce_while(nodes, {:ok, []}, fn node, {:ok, acc} ->
      case render_node(node, assigns, strict) do
        {:ok, result} -> {:cont, {:ok, [acc, result]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp render_node({:text, text}, _assigns, _strict) do
    {:ok, text}
  end

  defp render_node({:var, path, default}, assigns, strict) do
    case resolve_path(assigns, path) do
      {:ok, value} ->
        {:ok, to_string(value)}

      :not_found ->
        cond do
          default != nil ->
            {:ok, to_string(default)}

          not strict ->
            {:ok, ""}

          true ->
            {:error, {:render, "undefined variable: #{format_path(path)}"}}
        end
    end
  end

  defp render_node({:if, path, true_body, else_body}, assigns, strict) do
    case resolve_path(assigns, path) do
      {:ok, value} when value in [nil, false] ->
        render_nodes(else_body, assigns, strict)

      {:ok, _truthy} ->
        render_nodes(true_body, assigns, strict)

      :not_found ->
        # Treat missing as falsy
        render_nodes(else_body, assigns, strict)
    end
  end

  defp render_node({:unless, path, body}, assigns, strict) do
    case resolve_path(assigns, path) do
      {:ok, value} when value in [nil, false] ->
        render_nodes(body, assigns, strict)

      {:ok, _truthy} ->
        {:ok, ""}

      :not_found ->
        # Treat missing as falsy (i.e., unless condition is met)
        render_nodes(body, assigns, strict)
    end
  end

  defp render_node({:partial, name}, assigns, strict) do
    partials = Map.get(assigns, :__partials__, %{})

    case Map.get(partials, name) do
      nil ->
        {:error, {:render, "partial not found: #{name}"}}

      partial_ast ->
        render_nodes(partial_ast, assigns, strict)
    end
  end

  # ============================================================================
  # Path Resolution
  # ============================================================================

  @doc false
  @spec resolve_path(map(), [atom()]) :: {:ok, term()} | :not_found
  def resolve_path(assigns, [key]) do
    case Map.fetch(assigns, key) do
      {:ok, value} -> {:ok, value}
      :error -> :not_found
    end
  end

  def resolve_path(assigns, [key | rest]) do
    case Map.fetch(assigns, key) do
      {:ok, nested} when is_map(nested) -> resolve_path(nested, rest)
      {:ok, _non_map} -> :not_found
      :error -> :not_found
    end
  end

  def resolve_path(_assigns, []), do: :not_found

  # ============================================================================
  # Helpers
  # ============================================================================

  defp format_path(path) do
    path
    |> Enum.map(&Atom.to_string/1)
    |> Enum.join(".")
  end
end
