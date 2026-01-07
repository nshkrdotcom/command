# Integration Patterns

**Date**: 2026-01-05
**Version**: 1.0.0

## Overview

This document details the integration patterns for combining FlowStone, Synapse, ALTAR, and Portfolio ecosystems under Command's unified orchestration layer.

---

## 1. Pipeline Orchestration Pattern (FlowStone)

### Use Case
Execute complex, multi-step data processing workflows with AI capabilities, tracking all costs and requiring approvals for sensitive operations.

### Integration Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              Command.Pipelines                                   │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                        Workflow Templates                                │   │
│  │                                                                         │   │
│  │  Command.Workflows.Template                                             │   │
│  │  - name, description                                                    │   │
│  │  - steps (DAG definition)                                               │   │
│  │  - approval_rules                                                       │   │
│  │  - cost_limits                                                          │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                      │                                          │
│                                      ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                        Pipeline Generator                                │   │
│  │                                                                         │   │
│  │  Convert Command template → FlowStone pipeline module                   │   │
│  │  - Template steps → FlowStone assets                                    │   │
│  │  - Dependencies → depends_on                                            │   │
│  │  - AI operations → requires [:ai] resource                              │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                      │                                          │
│                                      ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                        FlowStone Execution                               │   │
│  │                                                                         │   │
│  │  FlowStone.run(pipeline, :final, partition: partition)                  │   │
│  │                                                                         │   │
│  │  ┌───────────────────────────────────────────────────────────────────┐ │   │
│  │  │ Asset Execution                                                    │ │   │
│  │  │                                                                   │ │   │
│  │  │ 1. Load dependencies                                              │ │   │
│  │  │ 2. Check approval (via Command.Approvals)                        │ │   │
│  │  │ 3. Execute with AI resource (via FlowStone.AI)                   │ │   │
│  │  │ 4. Record costs (via telemetry → Command.Costs)                  │ │   │
│  │  │ 5. Store artifacts (via Command.Artifacts)                       │ │   │
│  │  └───────────────────────────────────────────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Implementation

```elixir
defmodule Command.Pipelines do
  @moduledoc """
  FlowStone pipeline orchestration with Command tracking.
  """

  alias Command.{Workflows, Costs, Artifacts, Approvals}
  alias FlowStone.AI

  @doc """
  Create a pipeline from a workflow template.
  """
  def create_pipeline(template_id) do
    template = Workflows.get_template!(template_id)

    # Generate FlowStone module dynamically
    pipeline_module = generate_pipeline_module(template)

    {:ok, %{
      template_id: template_id,
      module: pipeline_module,
      created_at: DateTime.utc_now()
    }}
  end

  @doc """
  Execute a pipeline with full Command tracking.
  """
  def run(pipeline, partition, opts \\ []) do
    user_id = opts[:user_id]
    session_id = opts[:session_id]

    # Create workflow instance
    {:ok, instance} = Workflows.create_instance(pipeline.template_id, %{
      partition: partition,
      user_id: user_id,
      status: :running
    })

    # Set up telemetry handlers for cost tracking
    handler_id = attach_cost_handler(instance.id)

    try do
      # Execute via FlowStone
      result = FlowStone.run(
        pipeline.module,
        :final,
        partition: partition,
        io: [repo: Command.Repo]
      )

      # Handle result
      case result do
        {:ok, data} ->
          # Store final artifact
          {:ok, artifact} = Artifacts.create(instance.id, data)

          # Update instance
          Workflows.update_instance(instance, %{
            status: :completed,
            artifact_id: artifact.id
          })

          {:ok, %{instance: instance, artifact: artifact, data: data}}

        {:error, reason} ->
          Workflows.update_instance(instance, %{
            status: :failed,
            error: inspect(reason)
          })

          {:error, reason}
      end
    after
      detach_cost_handler(handler_id)
    end
  end

  defp generate_pipeline_module(template) do
    # Dynamic module generation from template
    module_name = Module.concat([Command.Pipelines.Generated, template.name])

    Module.create(module_name, quote do
      use FlowStone.Pipeline

      # Generate assets from template steps
      unquote(generate_assets(template.steps))
    end, Macro.Env.location(__ENV__))

    module_name
  end

  defp attach_cost_handler(instance_id) do
    handler_id = "command-cost-#{instance_id}"

    :telemetry.attach(
      handler_id,
      [:flowstone, :ai, :generate, :stop],
      fn _event, measurements, metadata, _config ->
        Costs.record(%{
          instance_id: instance_id,
          provider: metadata[:provider],
          model: metadata[:model],
          tokens: measurements[:tokens],
          duration_ms: measurements[:duration] / 1_000_000
        })
      end,
      nil
    )

    handler_id
  end
end
```

### Approval Integration

```elixir
defmodule Command.Pipelines.ApprovalResource do
  @moduledoc """
  FlowStone resource for Command approval integration.
  """
  use FlowStone.Resource

  def setup(config) do
    {:ok, %{user_id: config[:user_id], rules: load_rules(config)}}
  end

  def teardown(_state), do: :ok

  def health_check(_state), do: :healthy

  def check_approval(state, operation, context) do
    case Approvals.check(state.user_id, operation, context) do
      :approved -> :ok
      :pending -> {:wait, :approval_required}
      :denied -> {:error, :denied}
    end
  end
end
```

---

## 2. Multi-Agent Orchestration Pattern (Synapse)

### Use Case
Coordinate multiple specialized AI agents to complete complex tasks through signal-based communication, with Command providing session tracking and approval workflows.

### Integration Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            Command.Orchestration                                 │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                        Agent Configurations                              │   │
│  │                                                                         │   │
│  │  Command.Agents.AgentConfig (persisted)                                 │   │
│  │  - id, type (:specialist | :orchestrator)                               │   │
│  │  - signals (subscribes, emits)                                          │   │
│  │  - actions (Jido action modules)                                        │   │
│  │  - orchestration (for orchestrators)                                    │   │
│  │  - approval_rules                                                       │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                      │                                          │
│                                      ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                        Synapse Runtime                                   │   │
│  │                                                                         │   │
│  │  ┌─────────────────────────────────────────────────────────────────┐   │   │
│  │  │ SignalRouter                                                     │   │   │
│  │  │ - Topic registry                                                 │   │   │
│  │  │ - Message validation                                             │   │   │
│  │  │ - Subscriber delivery                                            │   │   │
│  │  └─────────────────────────────────────────────────────────────────┘   │   │
│  │                                                                         │   │
│  │  ┌─────────────────────────────────────────────────────────────────┐   │   │
│  │  │ Orchestrator.Runtime                                             │   │   │
│  │  │ - Agent lifecycle management                                     │   │   │
│  │  │ - Hot reload support                                             │   │   │
│  │  │ - Health monitoring                                              │   │   │
│  │  └─────────────────────────────────────────────────────────────────┘   │   │
│  │                                                                         │   │
│  │  ┌─────────────────────────────────────────────────────────────────┐   │   │
│  │  │ DynamicAgent (per agent)                                         │   │   │
│  │  │ - Subscribe to signals                                           │   │   │
│  │  │ - Execute actions via Workflow.Engine                            │   │   │
│  │  │ - Emit results                                                   │   │   │
│  │  └─────────────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                      │                                          │
│                                      ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                        Command Integration                               │   │
│  │                                                                         │   │
│  │  Sessions: Track agent conversations                                    │   │
│  │  Costs: Attribute LLM usage to agents                                   │   │
│  │  Approvals: Gate sensitive agent actions                                │   │
│  │  PubSub: Bridge Synapse signals to Phoenix channels                     │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Implementation

```elixir
defmodule Command.Orchestration do
  @moduledoc """
  Synapse multi-agent orchestration with Command integration.
  """

  alias Command.{Sessions, Costs, Approvals, PubSub}
  alias Synapse.{SignalRouter, Orchestrator}

  @doc """
  Register a new agent from Command configuration.
  """
  def register_agent(config) do
    # Persist to Command database
    {:ok, agent} = Command.Agents.create_agent(config)

    # Convert to Synapse format
    synapse_config = to_synapse_config(agent)

    # Add to Synapse runtime
    Orchestrator.Runtime.add_agent(runtime(), synapse_config)

    # Subscribe to agent signals for Command tracking
    subscribe_to_agent_signals(agent)

    {:ok, agent}
  end

  @doc """
  Publish a signal with Command session tracking.
  """
  def publish(topic, payload, opts \\ []) do
    session_id = opts[:session_id]
    user_id = opts[:user_id]

    # Create session message for tracking
    if session_id do
      Sessions.add_message(session_id, %{
        role: :system,
        content: "Signal published: #{topic}",
        metadata: %{signal: topic, payload: payload}
      })
    end

    # Check approval if required
    case check_signal_approval(topic, payload, user_id) do
      :approved ->
        # Publish via Synapse
        result = SignalRouter.publish(router(), topic, payload)

        # Broadcast to Phoenix PubSub for UI updates
        PubSub.broadcast("orchestration:#{session_id}", {:signal_published, topic, payload})

        result

      :pending ->
        {:pending, :awaiting_approval}

      :denied ->
        {:error, :signal_denied}
    end
  end

  @doc """
  Get status of all agents.
  """
  def list_agents(opts \\ []) do
    synapse_agents = Orchestrator.Runtime.list_agents(runtime())

    # Enrich with Command metadata
    Enum.map(synapse_agents, fn {id, running_agent} ->
      command_agent = Command.Agents.get_agent(id)

      %{
        id: id,
        status: if(running_agent.pid && Process.alive?(running_agent.pid), do: :running, else: :stopped),
        type: command_agent.type,
        spawn_count: running_agent.spawn_count,
        last_error: running_agent.last_error,
        cost_today: Costs.agent_cost_today(id)
      }
    end)
  end

  defp subscribe_to_agent_signals(agent) do
    # Subscribe to result signals for cost tracking
    for topic <- agent.signals.emits do
      SignalRouter.subscribe(router(), topic, self())
    end

    # Spawn handler process
    spawn_link(fn -> signal_handler_loop(agent) end)
  end

  defp signal_handler_loop(agent) do
    receive do
      {:signal, %{type: type, data: data}} ->
        # Record costs if present
        if data[:tokens] do
          Costs.record(%{
            agent_id: agent.id,
            provider: data[:provider],
            model: data[:model],
            tokens: data[:tokens]
          })
        end

        # Broadcast to UI
        PubSub.broadcast("agent:#{agent.id}", {:result, type, data})

        signal_handler_loop(agent)
    end
  end
end
```

### Domain Integration

```elixir
defmodule Command.Orchestration.Domains.CodeReview do
  @moduledoc """
  Code review domain registration for Command.
  """

  def register do
    # Register Synapse domain signals
    Synapse.Domains.CodeReview.register()

    # Register Command-specific agents
    agents = [
      %{
        id: :code_review_coordinator,
        type: :orchestrator,
        actions: [Command.Actions.ClassifyPR],
        signals: %{
          subscribes: [:review_request, :review_result],
          emits: [:review_summary],
          roles: %{request: :review_request, result: :review_result, summary: :review_summary}
        },
        orchestration: %{
          classify_fn: &classify_pr/1,
          spawn_specialists: [:security_reviewer, :performance_reviewer, :style_reviewer],
          aggregation_fn: &aggregate_reviews/2
        },
        approval_rules: [
          %{action: :approve_pr, requires: :human_approval},
          %{action: :request_changes, requires: :human_approval}
        ]
      },
      %{
        id: :security_reviewer,
        type: :specialist,
        actions: [
          Command.Actions.CheckSQLInjection,
          Command.Actions.CheckXSS,
          Command.Actions.CheckSecrets
        ],
        signals: %{subscribes: [:review_request], emits: [:review_result]}
      }
      # ... more specialists
    ]

    for agent <- agents do
      Command.Orchestration.register_agent(agent)
    end
  end
end
```

---

## 3. Direct AI Interaction Pattern (Portfolio)

### Use Case
Provide RAG-augmented AI interactions through Command's existing session model, using Portfolio for embeddings, retrieval, and completion.

### Integration Architecture

Command already has this integration via `Command.Portfolio`. The pattern is:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              Command.Sessions                                    │
│                                                                                 │
│  User Message                                                                   │
│       │                                                                         │
│       ▼                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                        RAG Augmentation                                  │   │
│  │                                                                         │   │
│  │  1. Command.Portfolio.embed(message.content)                            │   │
│  │  2. Command.Portfolio.retrieve(query, context)                          │   │
│  │  3. Build augmented prompt with retrieved context                       │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│       │                                                                         │
│       ▼                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                        LLM Completion                                    │   │
│  │                                                                         │   │
│  │  Command.Portfolio.complete(messages, opts)                             │   │
│  │  - Routed via PortfolioCore.Router                                      │   │
│  │  - Fallback across providers                                            │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│       │                                                                         │
│       ▼                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                        Response Handling                                 │   │
│  │                                                                         │   │
│  │  1. Store response in Session                                           │   │
│  │  2. Record costs in Command.Costs                                       │   │
│  │  3. Broadcast via PubSub                                                │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Enhanced Integration

```elixir
defmodule Command.Sessions.Completions do
  @moduledoc """
  AI completion handling with RAG augmentation.
  """

  alias Command.{Sessions, Portfolio, Costs, Indexes}

  @doc """
  Process a user message with RAG augmentation.
  """
  def complete(session_id, user_message, opts \\ []) do
    session = Sessions.get!(session_id)

    # Store user message
    {:ok, _msg} = Sessions.add_message(session, %{
      role: :user,
      content: user_message
    })

    # Retrieve relevant context
    context = retrieve_context(session, user_message, opts)

    # Build messages with context
    messages = build_messages(session, context)

    # Complete via Portfolio
    case Portfolio.complete(messages, opts) do
      {:ok, response} ->
        # Store assistant message
        {:ok, assistant_msg} = Sessions.add_message(session, %{
          role: :assistant,
          content: response.content,
          metadata: %{
            model: response.model,
            tokens: response.usage,
            sources: context.sources
          }
        })

        # Record costs
        Costs.record(%{
          session_id: session_id,
          user_id: session.user_id,
          provider: provider_from_model(response.model),
          model: response.model,
          input_tokens: response.usage.input_tokens,
          output_tokens: response.usage.output_tokens
        })

        {:ok, assistant_msg}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp retrieve_context(session, query, opts) do
    # Get relevant indexes for this session
    index_ids = Indexes.session_indexes(session.id)

    # Embed query
    {:ok, %{vector: query_vector}} = Portfolio.embed(query)

    # Retrieve from each index
    results = Enum.flat_map(index_ids, fn index_id ->
      case Portfolio.search_vectors(index_id, query_vector, opts[:k] || 5, opts) do
        {:ok, items} -> items
        _ -> []
      end
    end)

    # Rerank if available
    reranked = case Portfolio.rerank(query, results, opts) do
      {:ok, items} -> items
      _ -> results
    end

    %{
      items: Enum.take(reranked, opts[:top_k] || 3),
      sources: Enum.map(reranked, & &1.metadata.source)
    }
  end

  defp build_messages(session, context) do
    # Get conversation history
    history = Sessions.get_messages(session.id, limit: 10)

    # Build system message with context
    system_message = %{
      role: :system,
      content: """
      You are a helpful assistant. Use the following context to answer questions:

      #{format_context(context.items)}

      If the context doesn't contain relevant information, say so.
      """
    }

    [system_message | history]
  end
end
```

---

## 4. Tool Execution Pattern (ALTAR)

### Use Case
Provide unified tool contracts that work across FlowStone pipelines, Synapse agents, and direct interactions, with Command managing approvals and cost tracking.

### Integration Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              Command.Tools                                       │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                        Tool Registry                                     │   │
│  │                                                                         │   │
│  │  Command.Tools.Tool (persisted)                                         │   │
│  │  - name, description                                                    │   │
│  │  - declaration (ADM FunctionDeclaration)                                │   │
│  │  - implementation_module                                                │   │
│  │  - approval_rules                                                       │   │
│  │  - cost_config                                                          │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                      │                                          │
│                                      ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                        ALTAR Integration                                 │   │
│  │                                                                         │   │
│  │  ┌─────────────────────────────────────────────────────────────────┐   │   │
│  │  │ Altar.LATER.Registry                                             │   │   │
│  │  │ - register_tool(declaration, implementation)                     │   │   │
│  │  │ - lookup_tool(name)                                              │   │   │
│  │  └─────────────────────────────────────────────────────────────────┘   │   │
│  │                                                                         │   │
│  │  ┌─────────────────────────────────────────────────────────────────┐   │   │
│  │  │ Altar.LATER.Executor                                             │   │   │
│  │  │ - execute_tool(registry, function_call)                          │   │   │
│  │  │ - Always returns {:ok, ToolResult}                               │   │   │
│  │  └─────────────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                      │                                          │
│                                      ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                        Command Integration                               │   │
│  │                                                                         │   │
│  │  1. Pre-execution: Check approval rules                                 │   │
│  │  2. Execution: Via ALTAR with telemetry                                 │   │
│  │  3. Post-execution: Record costs, store artifacts                       │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Implementation

```elixir
defmodule Command.Tools do
  @moduledoc """
  ALTAR tool management with Command integration.
  """

  alias Altar.ADM
  alias Altar.LATER.{Registry, Executor}
  alias Command.{Approvals, Costs, Agents}

  @doc """
  Register a tool with both Command and ALTAR.
  """
  def register(name, description, params_schema, implementation, opts \\ []) do
    # Create ADM declaration
    {:ok, decl} = ADM.new_function_declaration(%{
      name: name,
      description: description,
      parameters: params_schema
    })

    # Persist to Command
    {:ok, tool} = Command.Repo.insert(%Command.Tools.Tool{
      name: name,
      description: description,
      declaration: ADM.FunctionDeclaration.to_map(decl),
      implementation_module: implementation,
      approval_rules: opts[:approval_rules] || [],
      cost_config: opts[:cost_config] || %{}
    })

    # Register with ALTAR
    :ok = Registry.register_tool(registry(), decl, wrap_implementation(tool, implementation))

    {:ok, tool}
  end

  @doc """
  Execute a tool call with approval and cost tracking.
  """
  def execute(call_id, name, args, opts \\ []) do
    user_id = opts[:user_id]
    session_id = opts[:session_id]

    # Get tool config
    tool = get_tool!(name)

    # Check approval
    case check_approval(tool, args, user_id) do
      :approved ->
        execute_approved(tool, call_id, name, args, session_id)

      :pending ->
        # Create pending approval request
        {:ok, request} = Approvals.create_request(%{
          user_id: user_id,
          resource_type: :tool_call,
          resource_id: call_id,
          context: %{tool: name, args: args}
        })

        {:pending, request}

      :denied ->
        {:error, :denied}
    end
  end

  defp execute_approved(tool, call_id, name, args, session_id) do
    # Create ADM call
    {:ok, call} = ADM.new_function_call(%{
      call_id: call_id,
      name: name,
      args: args
    })

    # Execute via ALTAR
    start_time = System.monotonic_time()
    {:ok, result} = Executor.execute_tool(registry(), call)
    duration = System.monotonic_time() - start_time

    # Record in session if present
    if session_id do
      Agents.record_tool_call(session_id, %{
        call_id: call_id,
        name: name,
        args: args,
        result: result.content,
        is_error: result.is_error,
        duration_ms: System.convert_time_unit(duration, :native, :millisecond)
      })
    end

    # Record costs if configured
    if tool.cost_config[:per_call] do
      Costs.record(%{
        resource_type: :tool_call,
        resource_id: call_id,
        amount: tool.cost_config.per_call
      })
    end

    {:ok, result}
  end

  defp wrap_implementation(tool, implementation) do
    fn args ->
      # Emit telemetry
      :telemetry.span([:command, :tool, :execute], %{tool: tool.name}, fn ->
        result = implementation.(args)
        {result, %{}}
      end)
    end
  end
end
```

### Cross-System Tool Availability

```elixir
defmodule Command.Tools.Providers do
  @moduledoc """
  Expose Command tools to different execution contexts.
  """

  @doc """
  Get tools for FlowStone pipeline context.
  """
  def for_flowstone(opts \\ []) do
    tools = list_tools(opts)

    # Return as FlowStone resource config
    %{
      tools: Enum.map(tools, &to_flowstone_tool/1),
      executor: &Command.Tools.execute/4
    }
  end

  @doc """
  Get tools for Synapse agent context.
  """
  def for_synapse(agent_id, opts \\ []) do
    agent = Command.Agents.get_agent!(agent_id)
    tools = list_tools(Keyword.merge(opts, allowed: agent.allowed_tools))

    # Return as Jido actions
    Enum.map(tools, &to_jido_action/1)
  end

  @doc """
  Get tool declarations for LLM function calling.
  """
  def for_llm(opts \\ []) do
    tools = list_tools(opts)

    # Return as LLM-compatible declarations
    Enum.map(tools, fn tool ->
      %{
        name: tool.name,
        description: tool.description,
        parameters: tool.declaration["parameters"]
      }
    end)
  end
end
```

---

## 5. Unified Telemetry Pattern

### Overview
All components emit telemetry events that Command aggregates for cost tracking, observability, and dashboards.

### Event Mapping

```elixir
defmodule Command.Telemetry.Handlers do
  @moduledoc """
  Unified telemetry handlers for all subsystems.
  """

  def attach_all do
    # FlowStone events
    :telemetry.attach_many(
      "command-flowstone",
      [
        [:flowstone, :materialization, :stop],
        [:flowstone, :ai, :generate, :stop],
        [:flowstone, :ai, :embed, :stop]
      ],
      &handle_flowstone_event/4,
      nil
    )

    # Synapse events
    :telemetry.attach_many(
      "command-synapse",
      [
        [:synapse, :workflow, :step, :stop],
        [:synapse, :llm, :request, :stop],
        [:synapse, :signal_router, :publish]
      ],
      &handle_synapse_event/4,
      nil
    )

    # Portfolio events
    :telemetry.attach_many(
      "command-portfolio",
      [
        [:portfolio, :embedder, :embed, :stop],
        [:portfolio, :llm, :complete, :stop],
        [:portfolio, :vector_store, :search, :stop]
      ],
      &handle_portfolio_event/4,
      nil
    )

    # ALTAR events
    :telemetry.attach_many(
      "command-altar",
      [
        [:altar, :ai, :generate, :stop],
        [:altar, :ai, :embed, :stop]
      ],
      &handle_altar_event/4,
      nil
    )
  end

  defp handle_flowstone_event([:flowstone, :ai, operation, :stop], measurements, metadata, _) do
    record_ai_cost(metadata, measurements, :flowstone)
  end

  defp handle_synapse_event([:synapse, :llm, :request, :stop], measurements, metadata, _) do
    record_ai_cost(metadata, measurements, :synapse)
  end

  defp handle_portfolio_event([:portfolio, :llm, :complete, :stop], measurements, metadata, _) do
    record_ai_cost(metadata, measurements, :portfolio)
  end

  defp handle_altar_event([:altar, :ai, operation, :stop], measurements, metadata, _) do
    record_ai_cost(metadata, measurements, :altar)
  end

  defp record_ai_cost(metadata, measurements, source) do
    if metadata[:tokens] do
      Command.Costs.record(%{
        source: source,
        provider: metadata[:provider],
        model: metadata[:model],
        input_tokens: metadata[:tokens][:prompt] || metadata[:tokens][:input] || 0,
        output_tokens: metadata[:tokens][:completion] || metadata[:tokens][:output] || 0,
        duration_ms: div(measurements[:duration] || 0, 1_000_000)
      })
    end
  end
end
```

### Dashboard Integration

```elixir
defmodule CommandWeb.DashboardLive do
  use CommandWeb, :live_view

  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to all orchestration events
      Command.PubSub.subscribe("orchestration:*")
      Command.PubSub.subscribe("pipeline:*")
      Command.PubSub.subscribe("agent:*")
    end

    {:ok, assign(socket,
      pipelines: Command.Pipelines.list_active(),
      agents: Command.Orchestration.list_agents(),
      costs_today: Command.Costs.today_summary()
    )}
  end

  def handle_info({:signal_published, topic, payload}, socket) do
    # Update real-time dashboard
    {:noreply, push_event(socket, "signal", %{topic: topic, payload: payload})}
  end

  def handle_info({:pipeline_progress, pipeline_id, status}, socket) do
    {:noreply, update_pipeline_status(socket, pipeline_id, status)}
  end

  def handle_info({:agent_result, agent_id, result}, socket) do
    {:noreply, update_agent_result(socket, agent_id, result)}
  end
end
```
