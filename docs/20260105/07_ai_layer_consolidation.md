# AI Layer Consolidation Design

**Date**: 2026-01-06
**Version**: 1.0.0

## Overview

This document outlines the consolidation of fragmented AI abstraction layers into a unified architecture under `Altar.AI`.

---

## 1. Current State (Fragmented)

### 1.1 The Problem

The ecosystem currently has **three separate AI abstraction layers**:

```
┌─────────────────────┐    ┌─────────────────────┐    ┌────────────────┐
│   Synapse.ReqLLM    │    │      Altar.AI       │    │  FlowStone.AI  │
│  (~650 lines)       │    │  (~500 lines)       │    │  (~68 lines)   │
├─────────────────────┤    ├─────────────────────┤    ├────────────────┤
│ • Req HTTP client   │    │ • Protocol-based    │    │ • Thin bridge  │
│ • OpenAI provider   │    │ • Gemini adapter    │    │ • Wraps        │
│ • Gemini provider   │    │ • Claude adapter    │    │   Altar.AI     │
│ • Profiles/retries  │    │ • Codex adapter     │    │ • FlowStone    │
│ • Token tracking    │    │ • Composite/fallback│    │   Resource     │
│ • System prompts    │    │ • Embeddings        │    │ • Telemetry    │
│                     │    │ • Classification    │    │   bridge       │
└─────────────────────┘    └─────────────────────┘    └────────────────┘
         │                          │                         │
         ▼                          ▼                         ▼
  Used by Synapse           Used by Portfolio          Used by FlowStone
  agents internally         Core/Index                 pipelines
```

Additionally, **ALTAR** (the repo) contains tool contracts (ADM) and local execution (LATER), creating naming confusion with `Altar.AI`.

### 1.2 Specific Issues

| Issue | Impact |
|-------|--------|
| **Duplicate HTTP clients** | Synapse.ReqLLM and Altar.AI adapters both implement OpenAI/Gemini calls |
| **Inconsistent interfaces** | `ReqLLM.chat_completion/2` vs `Altar.AI.generate/3` |
| **Separate telemetry** | `[:synapse, :llm, ...]` vs `[:altar, :ai, ...]` - no unified cost tracking |
| **FlowStone.AI overhead** | Entire repo for 68 lines of glue code |
| **Naming confusion** | ALTAR (tools) vs Altar.AI (AI) - unrelated but similar names |
| **No shared token/cost tracking** | Each layer tracks differently |

### 1.3 Current Repository Structure

```
../ALTAR/           # Tool contracts (ADM) + local executor (LATER)
../altar_ai/        # Protocol-based AI abstraction
../flowstone_ai/    # Thin bridge (68 lines) to FlowStone Resource
../synapse/         # Contains Synapse.ReqLLM internally
```

---

## 2. Target State (Consolidated)

### 2.1 Unified Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Altar.AI (Unified AI Layer)                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      Altar.AI.Client (enhanced)                      │   │
│  │                                                                     │   │
│  │  Protocols:                    Adapters:                            │   │
│  │  • Generator                   • Altar.AI.Adapters.Gemini           │   │
│  │  • Embedder                    • Altar.AI.Adapters.Claude           │   │
│  │  • Classifier                  • Altar.AI.Adapters.OpenAI (new)     │   │
│  │  • CodeGenerator               • Altar.AI.Adapters.Composite        │   │
│  │                                • Altar.AI.Adapters.Mock             │   │
│  │                                                                     │   │
│  │  Features (merged from ReqLLM):                                     │   │
│  │  • Profile-based configuration                                      │   │
│  │  • Automatic retries with exponential backoff                       │   │
│  │  • Token tracking and cost calculation                              │   │
│  │  • System prompt management                                         │   │
│  │  • Request timeout configuration                                    │   │
│  │                                                                     │   │
│  │  Telemetry (unified):                                               │   │
│  │  • [:altar, :ai, :generate, :start/:stop/:exception]                │   │
│  │  • [:altar, :ai, :embed, :start/:stop/:exception]                   │   │
│  │  • [:altar, :ai, :classify, :start/:stop/:exception]                │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    Altar.AI.Integrations (new)                       │   │
│  │                                                                     │   │
│  │  • Altar.AI.Integrations.FlowStone  - FlowStone Resource impl       │   │
│  │  • Altar.AI.Integrations.Synapse    - Synapse agent adapter         │   │
│  │  • Altar.AI.Integrations.Command    - Command cost tracking         │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                    Altar.Tools (renamed from ALTAR)                          │
├─────────────────────────────────────────────────────────────────────────────┤
│  • ADM: Tool contracts (FunctionDeclaration, FunctionCall, ToolResult)      │
│  • LATER: Local Agent & Tool Execution Runtime                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 New Repository Structure

```
../altar_ai/        # Unified AI layer (absorbs FlowStone.AI, ReqLLM features)
../altar_tools/     # Renamed from ALTAR - tool contracts and execution
../flowstone_ai/    # DEPRECATED - merged into altar_ai
../synapse/         # Uses Altar.AI instead of internal ReqLLM
```

---

## 3. Migration Plan

### 3.1 Phase 1: Enhance Altar.AI

Add ReqLLM features to Altar.AI without breaking existing API:

**File**: `altar_ai/lib/altar/ai/config.ex` (new)

```elixir
defmodule Altar.AI.Config do
  @moduledoc """
  Profile-based configuration for AI adapters.

  Supports named profiles with provider-specific settings,
  inspired by Synapse.ReqLLM's configuration system.
  """

  @type profile :: %{
    adapter: module(),
    adapter_opts: keyword(),
    model: String.t() | nil,
    allowed_models: [String.t()] | nil,
    system_prompt: String.t() | nil,
    retry: retry_config() | nil,
    timeout_ms: pos_integer() | nil,
    rate_limit: rate_limit_config() | nil
  }

  @type retry_config :: %{
    max_attempts: pos_integer(),
    base_backoff_ms: pos_integer(),
    max_backoff_ms: pos_integer(),
    enabled: boolean()
  }

  @type rate_limit_config :: %{
    requests_per_minute: pos_integer() | nil,
    tokens_per_minute: pos_integer() | nil
  }

  @doc """
  Load configuration from application env.

  ## Configuration

      config :altar_ai,
        default_profile: :gemini,
        profiles: %{
          gemini: %{
            adapter: Altar.AI.Adapters.Gemini,
            adapter_opts: [api_key: System.get_env("GEMINI_API_KEY")],
            model: "gemini-pro",
            retry: %{max_attempts: 3, base_backoff_ms: 300}
          },
          claude: %{
            adapter: Altar.AI.Adapters.Claude,
            adapter_opts: [api_key: System.get_env("ANTHROPIC_API_KEY")],
            model: "claude-sonnet-4-20250514"
          },
          openai: %{
            adapter: Altar.AI.Adapters.OpenAI,
            adapter_opts: [api_key: System.get_env("OPENAI_API_KEY")],
            model: "gpt-4o"
          }
        }
  """
  def load do
    Application.get_env(:altar_ai, :profiles, %{})
  end

  def get_profile(name) do
    profiles = load()
    Map.get(profiles, name)
  end

  def default_profile do
    Application.get_env(:altar_ai, :default_profile, :default)
  end

  def get_adapter(profile_name \\ nil) do
    name = profile_name || default_profile()

    case get_profile(name) do
      nil ->
        {:error, "Unknown profile: #{name}"}

      %{adapter: adapter, adapter_opts: opts} ->
        {:ok, adapter.new(opts)}
    end
  end
end
```

**File**: `altar_ai/lib/altar/ai/client.ex` (new)

```elixir
defmodule Altar.AI.Client do
  @moduledoc """
  High-level client with automatic profile resolution, retries, and telemetry.

  This is the recommended entry point for most use cases.
  """

  alias Altar.AI
  alias Altar.AI.{Config, Telemetry}

  @type opts :: [
    profile: atom(),
    model: String.t(),
    temperature: float(),
    max_tokens: pos_integer(),
    timeout: pos_integer(),
    system_prompt: String.t()
  ]

  @doc """
  Generate text using the configured profile.

  ## Options

  - `:profile` - Named profile to use (default: default_profile)
  - `:model` - Override profile model
  - `:temperature` - Sampling temperature
  - `:max_tokens` - Maximum tokens in response
  - `:timeout` - Request timeout in ms
  - `:system_prompt` - Override system prompt

  ## Examples

      # Use default profile
      {:ok, response} = Altar.AI.Client.generate("Hello!")

      # Use specific profile
      {:ok, response} = Altar.AI.Client.generate("Hello!", profile: :claude)

      # Override model
      {:ok, response} = Altar.AI.Client.generate("Hello!",
        profile: :openai,
        model: "gpt-4-turbo"
      )
  """
  @spec generate(String.t(), opts()) :: {:ok, AI.Response.t()} | {:error, term()}
  def generate(prompt, opts \\ []) do
    with {:ok, adapter} <- resolve_adapter(opts),
         {:ok, merged_opts} <- merge_options(opts) do

      request_id = generate_request_id()
      profile = Keyword.get(opts, :profile, Config.default_profile())

      Telemetry.span_generate(profile, request_id, fn ->
        execute_with_retry(fn ->
          AI.generate(adapter, prompt, merged_opts)
        end, opts)
      end)
    end
  end

  @doc """
  Stream text generation.
  """
  @spec stream(String.t(), opts()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream(prompt, opts \\ []) do
    with {:ok, adapter} <- resolve_adapter(opts),
         {:ok, merged_opts} <- merge_options(opts) do
      AI.stream(adapter, prompt, merged_opts)
    end
  end

  @doc """
  Generate embeddings.
  """
  @spec embed(String.t(), opts()) :: {:ok, [float()]} | {:error, term()}
  def embed(text, opts \\ []) do
    with {:ok, adapter} <- resolve_adapter(opts),
         {:ok, merged_opts} <- merge_options(opts) do

      request_id = generate_request_id()
      profile = Keyword.get(opts, :profile, Config.default_profile())

      Telemetry.span_embed(profile, request_id, fn ->
        AI.embed(adapter, text, merged_opts)
      end)
    end
  end

  @doc """
  Chat completion (OpenAI-style messages API).

  This provides compatibility with Synapse.ReqLLM's chat_completion interface.
  """
  @spec chat_completion(map(), opts()) :: {:ok, map()} | {:error, term()}
  def chat_completion(params, opts \\ []) do
    with {:ok, adapter} <- resolve_adapter(opts),
         {:ok, merged_opts} <- merge_options(opts) do

      prompt = build_prompt_from_messages(params)

      request_id = generate_request_id()
      profile = Keyword.get(opts, :profile, Config.default_profile())

      Telemetry.span_generate(profile, request_id, fn ->
        execute_with_retry(fn ->
          AI.generate(adapter, prompt, merged_opts)
        end, opts)
      end)
      |> format_chat_response()
    end
  end

  # Private helpers

  defp resolve_adapter(opts) do
    profile = Keyword.get(opts, :profile)
    Config.get_adapter(profile)
  end

  defp merge_options(opts) do
    profile_name = Keyword.get(opts, :profile, Config.default_profile())
    profile = Config.get_profile(profile_name) || %{}

    merged = opts
    |> Keyword.put_new(:model, Map.get(profile, :model))
    |> Keyword.put_new(:system_prompt, Map.get(profile, :system_prompt))
    |> Keyword.put_new(:timeout, Map.get(profile, :timeout_ms))

    {:ok, merged}
  end

  defp execute_with_retry(fun, opts) do
    profile_name = Keyword.get(opts, :profile, Config.default_profile())
    profile = Config.get_profile(profile_name) || %{}
    retry_config = Map.get(profile, :retry, %{enabled: false})

    if retry_config[:enabled] do
      do_retry(fun, retry_config, 1)
    else
      fun.()
    end
  end

  defp do_retry(fun, config, attempt) do
    case fun.() do
      {:ok, _} = success ->
        success

      {:error, %{retryable: true}} = error when attempt < config.max_attempts ->
        backoff = calculate_backoff(attempt, config)
        Process.sleep(backoff)
        do_retry(fun, config, attempt + 1)

      error ->
        error
    end
  end

  defp calculate_backoff(attempt, config) do
    base = Map.get(config, :base_backoff_ms, 300)
    max = Map.get(config, :max_backoff_ms, 5000)

    delay = trunc(base * :math.pow(2, attempt - 1))
    jitter = :rand.uniform(base)

    min(delay + jitter, max)
  end

  defp build_prompt_from_messages(%{messages: messages}) when is_list(messages) do
    messages
    |> Enum.map(fn
      %{role: "system", content: c} -> "[System]: #{c}"
      %{role: "user", content: c} -> "[User]: #{c}"
      %{role: "assistant", content: c} -> "[Assistant]: #{c}"
      %{"role" => r, "content" => c} -> "[#{String.capitalize(r)}]: #{c}"
    end)
    |> Enum.join("\n\n")
  end

  defp build_prompt_from_messages(%{prompt: prompt}), do: prompt

  defp format_chat_response({:ok, response}) do
    {:ok, %{
      content: response.content,
      model: response.model,
      metadata: %{
        total_tokens: response.usage[:total_tokens],
        prompt_tokens: response.usage[:input_tokens],
        completion_tokens: response.usage[:output_tokens],
        finish_reason: response.finish_reason
      }
    }}
  end

  defp format_chat_response(error), do: error

  defp generate_request_id do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string(36)
    |> String.downcase()
  end
end
```

### 3.2 Phase 2: Unified Telemetry

**File**: `altar_ai/lib/altar/ai/telemetry.ex` (enhanced)

```elixir
defmodule Altar.AI.Telemetry do
  @moduledoc """
  Unified telemetry for all AI operations.

  Events:
  - [:altar, :ai, :generate, :start]
  - [:altar, :ai, :generate, :stop]
  - [:altar, :ai, :generate, :exception]
  - [:altar, :ai, :embed, :start/:stop/:exception]
  - [:altar, :ai, :classify, :start/:stop/:exception]

  All events include:
  - request_id: Unique identifier for correlation
  - profile: Named profile used
  - adapter: Adapter module
  - model: Model identifier

  Stop events include:
  - duration: Time in native units
  - tokens_in: Input tokens
  - tokens_out: Output tokens
  - cost_usd: Estimated cost (if calculable)
  """

  @doc """
  Wrap a generate operation with telemetry.
  """
  def span_generate(profile, request_id, fun) do
    metadata = %{
      request_id: request_id,
      profile: profile,
      operation: :generate
    }

    start_time = System.monotonic_time()

    :telemetry.execute(
      [:altar, :ai, :generate, :start],
      %{system_time: System.system_time()},
      metadata
    )

    try do
      case fun.() do
        {:ok, response} = success ->
          duration = System.monotonic_time() - start_time

          :telemetry.execute(
            [:altar, :ai, :generate, :stop],
            %{
              duration: duration,
              tokens_in: get_in(response, [:usage, :input_tokens]) || 0,
              tokens_out: get_in(response, [:usage, :output_tokens]) || 0,
              cost_usd: calculate_cost(response)
            },
            Map.merge(metadata, %{
              model: response.model,
              finish_reason: response.finish_reason
            })
          )

          success

        {:error, error} = failure ->
          duration = System.monotonic_time() - start_time

          :telemetry.execute(
            [:altar, :ai, :generate, :exception],
            %{duration: duration},
            Map.merge(metadata, %{
              error_type: error_type(error),
              error_message: error_message(error)
            })
          )

          failure
      end
    rescue
      exception ->
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:altar, :ai, :generate, :exception],
          %{duration: duration},
          Map.merge(metadata, %{
            error_type: :exception,
            error_message: Exception.message(exception)
          })
        )

        reraise exception, __STACKTRACE__
    end
  end

  @doc """
  Wrap an embed operation with telemetry.
  """
  def span_embed(profile, request_id, fun) do
    metadata = %{
      request_id: request_id,
      profile: profile,
      operation: :embed
    }

    start_time = System.monotonic_time()

    :telemetry.execute([:altar, :ai, :embed, :start], %{system_time: System.system_time()}, metadata)

    try do
      result = fun.()
      duration = System.monotonic_time() - start_time

      case result do
        {:ok, _} ->
          :telemetry.execute([:altar, :ai, :embed, :stop], %{duration: duration}, metadata)
        {:error, error} ->
          :telemetry.execute([:altar, :ai, :embed, :exception], %{duration: duration},
            Map.merge(metadata, %{error_type: error_type(error), error_message: error_message(error)}))
      end

      result
    rescue
      exception ->
        duration = System.monotonic_time() - start_time
        :telemetry.execute([:altar, :ai, :embed, :exception], %{duration: duration},
          Map.merge(metadata, %{error_type: :exception, error_message: Exception.message(exception)}))
        reraise exception, __STACKTRACE__
    end
  end

  # Cost calculation based on model
  defp calculate_cost(%{model: model, usage: usage}) when is_map(usage) do
    input = Map.get(usage, :input_tokens, 0)
    output = Map.get(usage, :output_tokens, 0)

    {input_price, output_price} = model_pricing(model)

    (input * input_price + output * output_price) / 1_000_000
  end
  defp calculate_cost(_), do: nil

  # Pricing per million tokens (approximate)
  defp model_pricing("gemini-pro"), do: {0.50, 1.50}
  defp model_pricing("gemini-1.5-pro" <> _), do: {3.50, 10.50}
  defp model_pricing("claude-3-opus" <> _), do: {15.0, 75.0}
  defp model_pricing("claude-3-sonnet" <> _), do: {3.0, 15.0}
  defp model_pricing("claude-sonnet-4" <> _), do: {3.0, 15.0}
  defp model_pricing("gpt-4o"), do: {5.0, 15.0}
  defp model_pricing("gpt-4o-mini"), do: {0.15, 0.60}
  defp model_pricing("gpt-4-turbo" <> _), do: {10.0, 30.0}
  defp model_pricing(_), do: {0.0, 0.0}

  defp error_type(%{type: type}), do: type
  defp error_type(_), do: :unknown

  defp error_message(%{message: msg}), do: msg
  defp error_message(error), do: inspect(error)
end
```

### 3.3 Phase 3: FlowStone Integration Module

**File**: `altar_ai/lib/altar/ai/integrations/flowstone.ex` (new)

```elixir
defmodule Altar.AI.Integrations.FlowStone do
  @moduledoc """
  FlowStone Resource implementation for Altar.AI.

  This replaces the standalone flowstone_ai repository.

  ## Usage

      # Register the resource
      FlowStone.Resources.register(:ai, Altar.AI.Integrations.FlowStone, [
        profile: :gemini
      ])

      # Use in assets
      asset :enriched do
        requires [:ai]
        execute fn ctx, deps ->
          {:ok, response} = Altar.AI.Integrations.FlowStone.generate(
            ctx.resources.ai,
            "Summarize: \#{deps.raw_data}"
          )
          {:ok, %{summary: response.content}}
        end
      end
  """

  @behaviour FlowStone.Resource

  alias Altar.AI.Client

  defstruct [:profile, :adapter, :opts]

  @type t :: %__MODULE__{
    profile: atom(),
    adapter: struct(),
    opts: keyword()
  }

  # FlowStone.Resource callbacks

  @impl true
  def setup(opts) do
    profile = Keyword.get(opts, :profile, Altar.AI.Config.default_profile())

    case Altar.AI.Config.get_adapter(profile) do
      {:ok, adapter} ->
        {:ok, %__MODULE__{
          profile: profile,
          adapter: adapter,
          opts: opts
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def cleanup(_resource) do
    :ok
  end

  # AI operations

  @doc """
  Generate text using this resource's configured adapter.
  """
  @spec generate(t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def generate(%__MODULE__{} = resource, prompt, opts \\ []) do
    merged_opts = Keyword.merge([profile: resource.profile], opts)
    Client.generate(prompt, merged_opts)
  end

  @doc """
  Generate embeddings using this resource's configured adapter.
  """
  @spec embed(t(), String.t(), keyword()) :: {:ok, [float()]} | {:error, term()}
  def embed(%__MODULE__{} = resource, text, opts \\ []) do
    merged_opts = Keyword.merge([profile: resource.profile], opts)
    Client.embed(text, merged_opts)
  end

  @doc """
  Chat completion API for compatibility.
  """
  @spec chat_completion(t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def chat_completion(%__MODULE__{} = resource, params, opts \\ []) do
    merged_opts = Keyword.merge([profile: resource.profile], opts)
    Client.chat_completion(params, merged_opts)
  end
end
```

### 3.4 Phase 4: Synapse Integration

**File**: `altar_ai/lib/altar/ai/integrations/synapse.ex` (new)

```elixir
defmodule Altar.AI.Integrations.Synapse do
  @moduledoc """
  Synapse agent adapter for Altar.AI.

  Provides drop-in replacement for Synapse.ReqLLM using Altar.AI.

  ## Migration

  Replace in Synapse configuration:

      # Before (in synapse config)
      config :synapse, Synapse.ReqLLM,
        profiles: %{...}

      # After (in altar_ai config)
      config :altar_ai,
        profiles: %{...}

  ## Usage in Synapse Agents

      defmodule MyAgent do
        use Synapse.Agent

        def handle_signal(signal, state) do
          {:ok, response} = Altar.AI.Integrations.Synapse.chat_completion(%{
            messages: [
              %{role: "system", content: state.system_prompt},
              %{role: "user", content: signal.payload.message}
            ]
          }, profile: :openai)

          emit_signal(:agent_response, %{content: response.content})
        end
      end
  """

  alias Altar.AI.Client

  @doc """
  Chat completion with Synapse.ReqLLM-compatible interface.

  ## Parameters

  - `params` - Map with `:messages` or `:prompt`
  - `opts` - Options including `:profile`, `:model`, `:temperature`, etc.

  ## Examples

      {:ok, response} = chat_completion(%{
        messages: [
          %{role: "user", content: "Hello!"}
        ]
      }, profile: :openai)

      response.content
      #=> "Hello! How can I help you today?"
  """
  @spec chat_completion(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def chat_completion(params, opts \\ []) do
    Client.chat_completion(params, opts)
  end

  @doc """
  Generate text with simpler interface.
  """
  @spec generate(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def generate(prompt, opts \\ []) do
    Client.generate(prompt, opts)
  end

  @doc """
  Stream generation for real-time responses.
  """
  @spec stream(String.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream(prompt, opts \\ []) do
    Client.stream(prompt, opts)
  end
end
```

### 3.5 Phase 5: Command Integration

**File**: `altar_ai/lib/altar/ai/integrations/command.ex` (new)

```elixir
defmodule Altar.AI.Integrations.Command do
  @moduledoc """
  Command integration for Altar.AI telemetry and cost tracking.

  Attaches to Altar.AI telemetry events and records costs in Command.
  """

  @doc """
  Attach telemetry handlers for Command cost tracking.

  Call during Command application startup:

      def start(_type, _args) do
        Altar.AI.Integrations.Command.attach_telemetry()
        # ...
      end
  """
  def attach_telemetry do
    events = [
      [:altar, :ai, :generate, :stop],
      [:altar, :ai, :embed, :stop]
    ]

    :telemetry.attach_many(
      "altar-ai-command-integration",
      events,
      &handle_event/4,
      nil
    )
  end

  @doc false
  def handle_event([:altar, :ai, :generate, :stop], measurements, metadata, _config) do
    if session_id = metadata[:command_session_id] do
      record_cost(%{
        session_id: session_id,
        workflow_id: metadata[:command_workflow_id],
        operation: :generate,
        model: metadata[:model],
        tokens_in: measurements[:tokens_in],
        tokens_out: measurements[:tokens_out],
        cost_usd: measurements[:cost_usd],
        duration_ms: native_to_ms(measurements[:duration])
      })
    end
  end

  def handle_event([:altar, :ai, :embed, :stop], measurements, metadata, _config) do
    if session_id = metadata[:command_session_id] do
      record_cost(%{
        session_id: session_id,
        workflow_id: metadata[:command_workflow_id],
        operation: :embed,
        model: metadata[:model],
        tokens_in: measurements[:tokens_in] || 0,
        tokens_out: 0,
        cost_usd: measurements[:cost_usd],
        duration_ms: native_to_ms(measurements[:duration])
      })
    end
  end

  defp record_cost(attrs) do
    # Delegate to Command.Costs context
    if Code.ensure_loaded?(Command.Costs) do
      Command.Costs.record_ai_operation(attrs)
    end
  end

  defp native_to_ms(duration) when is_integer(duration) do
    System.convert_time_unit(duration, :native, :millisecond)
  end
  defp native_to_ms(_), do: nil
end
```

---

## 4. Synapse Migration

### 4.1 Deprecate Synapse.ReqLLM

**File**: `synapse/lib/synapse/req_llm.ex` (add deprecation)

```elixir
defmodule Synapse.ReqLLM do
  @moduledoc """
  DEPRECATED: Use Altar.AI.Client or Altar.AI.Integrations.Synapse instead.

  This module will be removed in Synapse v0.3.0.

  ## Migration

      # Before
      Synapse.ReqLLM.chat_completion(%{messages: [...]}, profile: :openai)

      # After
      Altar.AI.Integrations.Synapse.chat_completion(%{messages: [...]}, profile: :openai)
  """

  @deprecated "Use Altar.AI.Client.chat_completion/2 instead"
  def chat_completion(params, opts \\ []) do
    IO.warn("Synapse.ReqLLM is deprecated. Use Altar.AI.Integrations.Synapse instead.")
    Altar.AI.Integrations.Synapse.chat_completion(params, opts)
  end
end
```

### 4.2 Update Synapse Agents

Agents should use injected adapter or the integration module:

```elixir
defmodule Synapse.Agents.Specialist do
  use GenServer

  defstruct [:config, :ai_client]

  def init(opts) do
    # Use Altar.AI instead of ReqLLM
    ai_profile = Keyword.get(opts, :ai_profile, :default)

    {:ok, %__MODULE__{
      config: opts,
      ai_client: ai_profile
    }}
  end

  def handle_cast({:process_signal, signal}, state) do
    # Use unified AI client
    {:ok, response} = Altar.AI.Client.chat_completion(%{
      messages: build_messages(signal, state)
    }, profile: state.ai_client)

    emit_response(response, signal)
    {:noreply, state}
  end
end
```

---

## 5. ALTAR Rename

### 5.1 Rename ALTAR → Altar.Tools

The ALTAR repository should be renamed to clarify it's about tool contracts, not AI:

```
# Old structure
../ALTAR/
  lib/altar/adm.ex           # Tool contracts
  lib/altar/later/           # Local execution

# New structure
../altar_tools/
  lib/altar/tools.ex         # Main module
  lib/altar/tools/adm.ex     # Tool contracts
  lib/altar/tools/later/     # Local execution
```

**File**: `altar_tools/lib/altar/tools.ex`

```elixir
defmodule Altar.Tools do
  @moduledoc """
  ALTAR Tools - Universal tool contracts and local execution runtime.

  This library provides:

  - **ADM (ALTAR Data Model)**: Validated data structures for tool definitions
    - `Altar.Tools.ADM.FunctionDeclaration` - Tool function signatures
    - `Altar.Tools.ADM.FunctionCall` - Tool invocation requests
    - `Altar.Tools.ADM.ToolResult` - Tool execution results
    - `Altar.Tools.ADM.ToolConfig` - Tool configuration

  - **LATER (Local Agent & Tool Execution Runtime)**: Local tool execution
    - `Altar.Tools.Later.Executor` - Execute tools locally
    - `Altar.Tools.Later.Registry` - Tool registration and discovery

  ## Note

  For AI/LLM operations, see `Altar.AI` instead.
  """

  alias Altar.Tools.ADM

  defdelegate new_function_declaration(attrs), to: ADM
  defdelegate new_function_call(attrs), to: ADM
  defdelegate new_tool_result(attrs), to: ADM
  defdelegate new_tool_config(attrs), to: ADM
end
```

---

## 6. Updated Dependency Graph

### 6.1 After Consolidation

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Command                                         │
│                                                                             │
│  deps:                                                                      │
│    {:altar_ai, path: "../altar_ai"}                                        │
│    {:altar_tools, path: "../altar_tools"}                                  │
│    {:flowstone, path: "../flowstone"}                                      │
│    {:synapse, path: "../synapse"}                                          │
│    {:portfolio_core, path: "../portfolio_core"}                            │
│    {:portfolio_index, path: "../portfolio_index"}                          │
│    # NO flowstone_ai - merged into altar_ai                                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
          │
          ├──────────────────┬──────────────────┬──────────────────┐
          ▼                  ▼                  ▼                  ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐
│    Altar.AI     │  │  Altar.Tools    │  │    FlowStone    │  │   Synapse    │
│  (unified AI)   │  │  (tool layer)   │  │  (pipelines)    │  │  (agents)    │
└─────────────────┘  └─────────────────┘  └─────────────────┘  └──────────────┘
                              │                    │                  │
                              │                    │                  │
                              └────────────────────┴──────────────────┘
                                          │
                                          ▼
                                    Altar.AI (shared)
```

### 6.2 Updated mix.exs

```elixir
defp deps do
  [
    # ... other deps ...

    # Pipeline orchestration
    {:flowstone, path: "../flowstone"},
    # REMOVED: {:flowstone_ai, path: "../flowstone_ai"},

    # Multi-agent orchestration
    {:synapse, path: "../synapse"},

    # Unified AI layer
    {:altar_ai, path: "../altar_ai"},

    # Tool contracts and execution (renamed from ALTAR)
    {:altar_tools, path: "../altar_tools"},

    # Portfolio ecosystem
    {:portfolio_core, path: "../portfolio_core"},
    {:portfolio_index, path: "../portfolio_index"},
    {:portfolio_coder, path: "../portfolio_coder"},

    # ...
  ]
end
```

---

## 7. Summary

### 7.1 Changes by Repository

| Repository | Action |
|------------|--------|
| `altar_ai` | **Enhance**: Add Client, Config, Integrations modules |
| `flowstone_ai` | **Deprecate**: Merge into `altar_ai` as integration module |
| `ALTAR` | **Rename**: To `altar_tools` for clarity |
| `synapse` | **Update**: Deprecate ReqLLM, use Altar.AI |
| `command` | **Update**: Remove flowstone_ai dep, add integration setup |

### 7.2 Benefits

| Benefit | Description |
|---------|-------------|
| **Single AI layer** | One place for all AI operations |
| **Unified telemetry** | `[:altar, :ai, ...]` for everything |
| **Consistent cost tracking** | Automatic across FlowStone, Synapse, Command |
| **Reduced maintenance** | 3 repos → 1 for AI functionality |
| **Clear naming** | Altar.AI = AI ops, Altar.Tools = tool contracts |
| **Profile-based config** | Easy multi-provider setup |

### 7.3 Migration Path

1. **Phase 1**: Enhance Altar.AI with Client, Config, Telemetry
2. **Phase 2**: Add integration modules for FlowStone, Synapse, Command
3. **Phase 3**: Deprecate Synapse.ReqLLM with forwarding
4. **Phase 4**: Deprecate flowstone_ai repo
5. **Phase 5**: Rename ALTAR → altar_tools
6. **Phase 6**: Update all consumers, remove deprecated code
