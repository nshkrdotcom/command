defmodule Command.PromptSets.Template do
  @moduledoc """
  Prompt template compilation and rendering.

  Provides a high-level API for compiling `{{}}` template syntax into an
  internal AST and rendering it with context variables. This module is the
  main entry point for the templating system.

  ## Template Syntax

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

  Only the above constructs are supported. No arbitrary code execution
  is permitted — the system uses AST-based evaluation, not `EEx` or
  `Code.eval`.

  ## Examples

      iex> {:ok, compiled} = Template.compile("Hello {{name}}!")
      iex> Template.render(compiled, %{name: "World"})
      {:ok, "Hello World!"}

      iex> Template.compile_and_render("Hello {{name}}!", %{name: "World"})
      {:ok, "Hello World!"}
  """

  alias Command.PromptSets.Template.{Parser, Compiler, Renderer, Partials}

  @type compiled :: [Parser.ast_node()]
  @type context :: map()
  @type options :: [strict: boolean(), partials_dir: String.t() | nil]

  @doc """
  Compiles a template string into a reusable compiled form.

  ## Options

  - `:strict` — passed through for validation (currently unused at compile time)

  ## Examples

      iex> Template.compile("Hello {{name}}!")
      {:ok, [{:text, "Hello "}, {:var, [:name], nil}, {:text, "!"}]}

      iex> Template.compile("{{#if bad")
      {:error, _}
  """
  @spec compile(String.t(), options()) :: {:ok, compiled()} | {:error, term()}
  def compile(template_string, _opts \\ []) do
    with {:ok, ast} <- Parser.parse(template_string),
         {:ok, compiled} <- Compiler.compile(ast) do
      {:ok, compiled}
    end
  end

  @doc """
  Renders a compiled template with the given context.

  ## Options

  - `:strict` — If `true` (default), missing variables return an error.
    If `false`, missing variables produce empty strings.

  ## Examples

      iex> {:ok, compiled} = Template.compile("Hello {{name}}!")
      iex> Template.render(compiled, %{name: "World"})
      {:ok, "Hello World!"}
  """
  @spec render(compiled(), context(), options()) :: {:ok, String.t()} | {:error, term()}
  def render(compiled, context, opts \\ []) do
    Renderer.render(compiled, context, opts)
  end

  @doc """
  Compiles and renders a template string in one call.

  This is a convenience function that combines `compile/2` and `render/3`.
  It also handles loading partials from the configured directory.

  ## Options

  - `:strict` — If `true` (default), missing variables return an error.
  - `:partials_dir` — Directory to load partials from (optional).

  ## Examples

      iex> Template.compile_and_render("Hello {{name}}!", %{name: "World"})
      {:ok, "Hello World!"}
  """
  @spec compile_and_render(String.t(), context(), options()) ::
          {:ok, String.t()} | {:error, term()}
  def compile_and_render(template_string, context, opts \\ []) do
    partials_dir = Keyword.get(opts, :partials_dir)

    with {:ok, partials} <- load_partials(partials_dir),
         {:ok, compiled} <- compile(template_string, opts) do
      context = Map.put(context, :__partials__, partials)
      render(compiled, context, opts)
    end
  end

  @doc """
  Validates a template string without rendering it.

  Returns `:ok` if the template syntax is valid, or `{:error, reason}` if not.

  ## Examples

      iex> Template.validate("Hello {{name}}!")
      :ok

      iex> Template.validate("{{#if unclosed}}")
      {:error, _}
  """
  @spec validate(String.t()) :: :ok | {:error, term()}
  def validate(template_string) do
    case compile(template_string) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp load_partials(nil), do: {:ok, %{}}
  defp load_partials(dir), do: Partials.load_all(dir)
end
