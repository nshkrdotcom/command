defmodule Command.PromptSets.Template.Parser do
  @moduledoc """
  Parses `{{}}` template syntax into an internal AST.

  The parser converts template strings containing `{{variable}}`, `{{#if cond}}`,
  `{{#unless cond}}`, `{{> partial}}`, and `{{var | default: "value"}}` constructs
  into a list of AST nodes for compilation and rendering.

  ## Supported Syntax

  | Construct        | Syntax                                  |
  |------------------|-----------------------------------------|
  | Variable         | `{{name}}`                              |
  | Nested variable  | `{{config.model}}`                      |
  | Default value    | `{{name \\| default: "value"}}`         |
  | If block         | `{{#if var}}...{{/if}}`                 |
  | If-else block    | `{{#if var}}...{{else}}...{{/if}}`      |
  | Unless block     | `{{#unless var}}...{{/unless}}`         |
  | Partial include  | `{{> partial_name}}`                    |

  ## Security

  Only the above constructs are allowed. No arbitrary code execution is permitted.
  The parser rejects any syntax that does not match the defined grammar.
  """

  @type path :: [atom()]

  @type ast_node ::
          {:text, String.t()}
          | {:var, path(), String.t() | nil}
          | {:if, path(), [ast_node()], [ast_node()]}
          | {:unless, path(), [ast_node()]}
          | {:partial, String.t()}

  @type token ::
          {:text, String.t()}
          | {:var, String.t()}
          | {:open_if, String.t()}
          | {:else_tag}
          | {:close_if}
          | {:open_unless, String.t()}
          | {:close_unless}
          | {:partial, String.t()}

  # Regex to match {{ ... }} tags, allowing balanced content inside
  @tag_regex ~r/\{\{(.*?)\}\}/s

  @doc """
  Parses a template string into a list of AST nodes.

  Returns `{:ok, [node()]}` on success, or `{:error, reason}` on failure.

  ## Examples

      iex> Parser.parse("Hello {{name}}!")
      {:ok, [{:text, "Hello "}, {:var, [:name], nil}, {:text, "!"}]}

      iex> Parser.parse("{{#if show}}visible{{/if}}")
      {:ok, [{:if, [:show], [{:text, "visible"}], []}]}
  """
  @spec parse(String.t()) :: {:ok, [ast_node()]} | {:error, term()}
  def parse(template) when is_binary(template) do
    case tokenize(template) do
      {:ok, tokens} -> build_ast(tokens)
      {:error, _} = error -> error
    end
  end

  def parse(_), do: {:error, {:parse, "template must be a string"}}

  # ============================================================================
  # Tokenization
  # ============================================================================

  @doc false
  @spec tokenize(String.t()) :: {:ok, [token()]} | {:error, term()}
  def tokenize(template) do
    parts = Regex.split(@tag_regex, template, include_captures: true)

    tokens =
      Enum.reduce_while(parts, {:ok, []}, fn part, {:ok, acc} ->
        case classify_part(part) do
          {:ok, token} -> {:cont, {:ok, acc ++ List.wrap(token)}}
          {:error, _} = error -> {:halt, error}
        end
      end)

    tokens
  end

  defp classify_part(""), do: {:ok, []}

  defp classify_part("{{" <> _ = tag) do
    # Strip the {{ and }} delimiters
    inner = tag |> String.trim_leading("{{") |> String.trim_trailing("}}")
    inner = String.trim(inner)
    classify_tag(inner)
  end

  defp classify_part(text), do: {:ok, {:text, text}}

  defp classify_tag("#if " <> condition) do
    condition = String.trim(condition)

    if valid_identifier_path?(condition) do
      {:ok, {:open_if, condition}}
    else
      {:error, {:parse, "invalid condition in #if: #{condition}"}}
    end
  end

  defp classify_tag("#unless " <> condition) do
    condition = String.trim(condition)

    if valid_identifier_path?(condition) do
      {:ok, {:open_unless, condition}}
    else
      {:error, {:parse, "invalid condition in #unless: #{condition}"}}
    end
  end

  defp classify_tag("/if"), do: {:ok, {:close_if}}
  defp classify_tag("/unless"), do: {:ok, {:close_unless}}
  defp classify_tag("else"), do: {:ok, {:else_tag}}

  defp classify_tag("> " <> name) do
    name = String.trim(name)

    if valid_partial_name?(name) do
      {:ok, {:partial, name}}
    else
      {:error, {:parse, "invalid partial name: #{name}"}}
    end
  end

  defp classify_tag(expression) do
    cond do
      String.contains?(expression, "|") ->
        parse_default_expression(expression)

      valid_identifier_path?(expression) ->
        {:ok, {:var, expression}}

      true ->
        {:error, {:parse, "invalid template expression: {{#{expression}}}"}}
    end
  end

  defp parse_default_expression(expression) do
    case String.split(expression, "|", parts: 2) do
      [var_part, default_part] ->
        var_name = String.trim(var_part)
        default_part = String.trim(default_part)

        with true <- valid_identifier_path?(var_name),
             {:ok, default_value} <- parse_default_value(default_part) do
          {:ok, {:var_with_default, var_name, default_value}}
        else
          false ->
            {:error, {:parse, "invalid variable name in default expression: #{var_name}"}}

          {:error, _} = error ->
            error
        end

      _ ->
        {:error, {:parse, "invalid default expression: #{expression}"}}
    end
  end

  defp parse_default_value("default:" <> rest) do
    value = String.trim(rest)

    cond do
      String.starts_with?(value, "\"") and String.ends_with?(value, "\"") ->
        {:ok, String.slice(value, 1..-2//1)}

      String.starts_with?(value, "'") and String.ends_with?(value, "'") ->
        {:ok, String.slice(value, 1..-2//1)}

      value == "true" ->
        {:ok, true}

      value == "false" ->
        {:ok, false}

      value == "nil" ->
        {:ok, nil}

      Regex.match?(~r/^\d+$/, value) ->
        {:ok, String.to_integer(value)}

      true ->
        {:error,
         {:parse,
          "invalid default value: #{value}. Must be a quoted string, boolean, nil, or integer"}}
    end
  end

  defp parse_default_value(other) do
    {:error, {:parse, "expected 'default:' in pipe expression, got: #{other}"}}
  end

  # ============================================================================
  # AST Building
  # ============================================================================

  @spec build_ast([token()]) :: {:ok, [node()]} | {:error, term()}
  defp build_ast(tokens) do
    case build_nodes(tokens, []) do
      {:ok, nodes, []} ->
        {:ok, nodes}

      {:ok, _nodes, remaining} ->
        {:error, {:parse, "unexpected token: #{inspect(hd(remaining))}"}}

      {:error, _} = error ->
        error
    end
  end

  defp build_nodes([], acc), do: {:ok, Enum.reverse(acc), []}

  defp build_nodes([{:text, text} | rest], acc) do
    build_nodes(rest, [{:text, text} | acc])
  end

  defp build_nodes([{:var, name} | rest], acc) do
    path = parse_path(name)
    build_nodes(rest, [{:var, path, nil} | acc])
  end

  defp build_nodes([{:var_with_default, name, default} | rest], acc) do
    path = parse_path(name)
    build_nodes(rest, [{:var, path, default} | acc])
  end

  defp build_nodes([{:partial, name} | rest], acc) do
    build_nodes(rest, [{:partial, name} | acc])
  end

  defp build_nodes([{:open_if, condition} | rest], acc) do
    path = parse_path(condition)

    case collect_if_body(rest) do
      {:ok, true_body, else_body, remaining} ->
        build_nodes(remaining, [{:if, path, true_body, else_body} | acc])

      {:error, _} = error ->
        error
    end
  end

  defp build_nodes([{:open_unless, condition} | rest], acc) do
    path = parse_path(condition)

    case collect_unless_body(rest) do
      {:ok, body, remaining} ->
        build_nodes(remaining, [{:unless, path, body} | acc])

      {:error, _} = error ->
        error
    end
  end

  # Stop markers for nested blocks
  defp build_nodes([{:close_if} | _] = tokens, acc) do
    {:ok, Enum.reverse(acc), tokens}
  end

  defp build_nodes([{:close_unless} | _] = tokens, acc) do
    {:ok, Enum.reverse(acc), tokens}
  end

  defp build_nodes([{:else_tag} | _] = tokens, acc) do
    {:ok, Enum.reverse(acc), tokens}
  end

  defp build_nodes([token | _], _acc) do
    {:error, {:parse, "unexpected token: #{inspect(token)}"}}
  end

  defp collect_if_body(tokens) do
    case build_nodes(tokens, []) do
      {:ok, true_body, [{:close_if} | remaining]} ->
        {:ok, true_body, [], remaining}

      {:ok, true_body, [{:else_tag} | rest]} ->
        case build_nodes(rest, []) do
          {:ok, else_body, [{:close_if} | remaining]} ->
            {:ok, true_body, else_body, remaining}

          {:ok, _else_body, _remaining} ->
            {:error, {:parse, "unclosed {{#if}} block: missing {{/if}} after {{else}}"}}

          {:error, _} = error ->
            error
        end

      {:ok, _body, _remaining} ->
        {:error, {:parse, "unclosed {{#if}} block: missing {{/if}}"}}

      {:error, _} = error ->
        error
    end
  end

  defp collect_unless_body(tokens) do
    case build_nodes(tokens, []) do
      {:ok, body, [{:close_unless} | remaining]} ->
        {:ok, body, remaining}

      {:ok, _body, _remaining} ->
        {:error, {:parse, "unclosed {{#unless}} block: missing {{/unless}}"}}

      {:error, _} = error ->
        error
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  @spec parse_path(String.t()) :: [atom()]
  defp parse_path(name) do
    name
    |> String.split(".")
    |> Enum.map(&String.to_atom/1)
  end

  defp valid_identifier_path?(name) do
    Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)*$/, name)
  end

  defp valid_partial_name?(name) do
    Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_\-]*$/, name)
  end
end
