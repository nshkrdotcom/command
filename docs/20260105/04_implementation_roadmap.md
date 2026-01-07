# Implementation Roadmap

**Date**: 2026-01-05
**Version**: 1.0.0

## Overview

This document outlines the implementation phases for integrating FlowStone, Synapse, ALTAR, and Portfolio ecosystems under Command's unified orchestration layer.

---

## Phase 1: Foundation

### Goals
- Establish integration infrastructure
- Set up unified telemetry
- Create database migrations for new contexts

### Tasks

#### 1.1 Telemetry Infrastructure

**Files to Create:**
- `lib/command/telemetry/handlers.ex` - Unified event handlers
- `lib/command/telemetry/metrics.ex` - Metric definitions

```elixir
# lib/command/telemetry/handlers.ex
defmodule Command.Telemetry.Handlers do
  @moduledoc """
  Unified telemetry handlers for FlowStone, Synapse, Portfolio, and ALTAR.
  """

  def attach_all do
    attach_flowstone_handlers()
    attach_synapse_handlers()
    attach_portfolio_handlers()
    attach_altar_handlers()
  end

  # ... implementation
end
```

**Deliverables:**
- [ ] Create telemetry handler module
- [ ] Add to application startup
- [ ] Test event capture from all sources
- [ ] Create telemetry documentation

#### 1.2 Database Migrations

**Migrations to Create:**

```elixir
# priv/repo/migrations/YYYYMMDD_create_pipelines.exs
defmodule Command.Repo.Migrations.CreatePipelines do
  use Ecto.Migration

  def change do
    create table(:pipelines, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :template_id, references(:workflow_templates, type: :binary_id)
      add :name, :string, null: false
      add :status, :string, default: "active"
      add :module_code, :text  # Generated FlowStone module
      add :config, :map, default: %{}
      timestamps()
    end

    create table(:pipeline_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :pipeline_id, references(:pipelines, type: :binary_id)
      add :partition, :string
      add :status, :string, default: "pending"
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :result, :map
      add :error, :text
      timestamps()
    end

    create index(:pipeline_runs, [:pipeline_id, :status])
    create index(:pipeline_runs, [:partition])
  end
end
```

```elixir
# priv/repo/migrations/YYYYMMDD_create_agent_orchestration.exs
defmodule Command.Repo.Migrations.CreateAgentOrchestration do
  use Ecto.Migration

  def change do
    create table(:orchestration_agents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :type, :string, null: false  # specialist, orchestrator, custom
      add :config, :map, null: false   # Full Synapse config
      add :status, :string, default: "active"
      add :signals, :map, default: %{}
      add :approval_rules, {:array, :map}, default: []
      timestamps()
    end

    create unique_index(:orchestration_agents, [:name])

    create table(:orchestration_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :agent_id, references(:orchestration_agents, type: :binary_id)
      add :session_id, references(:sessions, type: :binary_id)
      add :event_type, :string  # signal_received, action_executed, result_emitted
      add :topic, :string
      add :payload, :map
      add :metadata, :map, default: %{}
      timestamps()
    end

    create index(:orchestration_events, [:agent_id, :inserted_at])
    create index(:orchestration_events, [:session_id])
  end
end
```

```elixir
# priv/repo/migrations/YYYYMMDD_create_tools.exs
defmodule Command.Repo.Migrations.CreateTools do
  use Ecto.Migration

  def change do
    create table(:tools, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :declaration, :map, null: false  # ADM FunctionDeclaration
      add :implementation_module, :string
      add :status, :string, default: "active"
      add :approval_rules, {:array, :map}, default: []
      add :cost_config, :map, default: %{}
      timestamps()
    end

    create unique_index(:tools, [:name])

    create table(:tool_calls, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tool_id, references(:tools, type: :binary_id)
      add :session_id, references(:sessions, type: :binary_id)
      add :call_id, :string, null: false
      add :args, :map, default: %{}
      add :result, :map
      add :is_error, :boolean, default: false
      add :duration_ms, :integer
      add :approval_status, :string
      timestamps()
    end

    create index(:tool_calls, [:tool_id, :inserted_at])
    create index(:tool_calls, [:session_id])
    create unique_index(:tool_calls, [:call_id])
  end
end
```

**Deliverables:**
- [ ] Create pipeline migrations
- [ ] Create orchestration migrations
- [ ] Create tool migrations
- [ ] Run migrations and verify schema

#### 1.3 Configuration Updates

**Files to Modify:**
- `config/config.exs` - Add new context configs
- `lib/command/application.ex` - Add new supervisors

```elixir
# config/config.exs additions

# Pipeline orchestration (FlowStone)
config :command, Command.Pipelines,
  enabled: true,
  flowstone_repo: Command.Repo,
  default_io_manager: :postgres

# Multi-agent orchestration (Synapse)
config :command, Command.Orchestration,
  enabled: true,
  synapse_router: Command.Synapse.Router,
  config_source: {:module, Command.Orchestration.AgentConfigs}

# Tool management (ALTAR)
config :command, Command.Tools,
  enabled: true,
  registry: Command.Tools.Registry

# FlowStone configuration
config :flowstone,
  repo: Command.Repo,
  storage: :postgres,
  lineage: true

# Synapse configuration
config :synapse,
  ecto_repos: [Command.Repo]

config :synapse, Synapse.Workflow.Engine,
  persistence: {Command.Orchestration.WorkflowPersistence, []}
```

**Deliverables:**
- [ ] Update config files
- [ ] Add application children
- [ ] Test startup sequence
- [ ] Document configuration options

---

## Phase 2: Pipeline Integration (FlowStone)

### Goals
- Create Command.Pipelines context
- Integrate FlowStone execution with Command tracking
- Connect approval workflows

### Tasks

#### 2.1 Create Pipelines Context

**Files to Create:**
- `lib/command/pipelines.ex` - Main context module
- `lib/command/pipelines/pipeline.ex` - Schema
- `lib/command/pipelines/run.ex` - Run schema
- `lib/command/pipelines/generator.ex` - FlowStone module generator

```elixir
# lib/command/pipelines.ex
defmodule Command.Pipelines do
  @moduledoc """
  Pipeline orchestration context integrating FlowStone.
  """

  alias Command.Pipelines.{Pipeline, Run, Generator}
  alias Command.{Workflows, Costs, Artifacts, Approvals}

  @doc """
  Create a pipeline from a workflow template.
  """
  def create_from_template(template_id, opts \\ []) do
    template = Workflows.get_template!(template_id)

    # Generate FlowStone module
    {:ok, module_code} = Generator.generate(template)

    %Pipeline{}
    |> Pipeline.changeset(%{
      template_id: template_id,
      name: template.name,
      module_code: module_code,
      config: opts[:config] || %{}
    })
    |> Repo.insert()
  end

  @doc """
  Execute a pipeline with full tracking.
  """
  def run(pipeline_id, partition, opts \\ []) do
    pipeline = get_pipeline!(pipeline_id)

    # Create run record
    {:ok, run} = create_run(pipeline, partition)

    # Execute with telemetry
    execute_with_tracking(pipeline, run, partition, opts)
  end

  @doc """
  Get pipeline status and metrics.
  """
  def status(pipeline_id) do
    pipeline = get_pipeline!(pipeline_id)
    runs = list_runs(pipeline_id, limit: 10)

    %{
      pipeline: pipeline,
      recent_runs: runs,
      success_rate: calculate_success_rate(pipeline_id),
      avg_duration: calculate_avg_duration(pipeline_id)
    }
  end
end
```

**Deliverables:**
- [ ] Create Pipeline schema
- [ ] Create Run schema
- [ ] Implement Generator module
- [ ] Implement main context functions
- [ ] Add approval integration
- [ ] Add cost tracking
- [ ] Create tests

#### 2.2 FlowStone Resource Integration

**Files to Create:**
- `lib/command/pipelines/resources/approval.ex` - Approval resource
- `lib/command/pipelines/resources/cost_tracker.ex` - Cost tracking resource

```elixir
# lib/command/pipelines/resources/approval.ex
defmodule Command.Pipelines.Resources.Approval do
  @moduledoc """
  FlowStone resource for Command approval integration.
  """
  use FlowStone.Resource

  alias Command.Approvals

  def setup(config) do
    {:ok, %{
      user_id: config[:user_id],
      pipeline_id: config[:pipeline_id],
      rules: Approvals.rules_for(:pipeline, config[:pipeline_id])
    }}
  end

  def teardown(_state), do: :ok

  def health_check(_state), do: :healthy

  def check(state, operation, context) do
    Approvals.check(state.user_id, :pipeline, operation, context)
  end

  def request_approval(state, operation, context) do
    Approvals.create_request(%{
      user_id: state.user_id,
      resource_type: :pipeline,
      resource_id: state.pipeline_id,
      operation: operation,
      context: context
    })
  end
end
```

**Deliverables:**
- [ ] Implement Approval resource
- [ ] Implement CostTracker resource
- [ ] Register resources with FlowStone
- [ ] Test resource lifecycle

#### 2.3 AI Integration via FlowStone.AI

**Configuration:**

```elixir
# lib/command/pipelines/ai_resource.ex
defmodule Command.Pipelines.AIResource do
  @moduledoc """
  Configure FlowStone.AI for Command pipelines.
  """

  def configure(opts \\ []) do
    # Set up telemetry bridge
    FlowStone.AI.setup_telemetry()

    # Configure AI resource
    {:ok, resource} = FlowStone.AI.resource_init(
      adapter: Altar.AI.Adapters.Composite,
      adapter_opts: composite_config(opts)
    )

    resource
  end

  defp composite_config(opts) do
    providers = [
      {Altar.AI.Adapters.Gemini, [api_key: get_api_key(:gemini, opts)]},
      {Altar.AI.Adapters.Claude, [api_key: get_api_key(:anthropic, opts)]},
      {Altar.AI.Adapters.Codex, [api_key: get_api_key(:openai, opts)]},
      {Altar.AI.Adapters.Fallback, []}
    ]

    [strategy: :fallback, providers: providers]
  end
end
```

**Deliverables:**
- [ ] Configure FlowStone.AI integration
- [ ] Set up credential resolution
- [ ] Test AI operations in pipelines
- [ ] Document AI resource usage

---

## Phase 3: Agent Orchestration (Synapse)

### Goals
- Create Command.Orchestration context
- Integrate Synapse runtime with Command
- Connect signals to PubSub

### Tasks

#### 3.1 Create Orchestration Context

**Files to Create:**
- `lib/command/orchestration.ex` - Main context
- `lib/command/orchestration/agent.ex` - Agent schema
- `lib/command/orchestration/event.ex` - Event schema
- `lib/command/orchestration/signal_bridge.ex` - PubSub bridge

```elixir
# lib/command/orchestration.ex
defmodule Command.Orchestration do
  @moduledoc """
  Multi-agent orchestration context integrating Synapse.
  """

  alias Command.Orchestration.{Agent, Event, SignalBridge}
  alias Synapse.{SignalRouter, Orchestrator}

  @doc """
  Register an agent with Command and Synapse.
  """
  def register_agent(attrs) do
    # Persist to database
    {:ok, agent} = create_agent(attrs)

    # Register with Synapse runtime
    synapse_config = to_synapse_config(agent)
    Orchestrator.Runtime.add_agent(runtime(), synapse_config)

    # Set up signal bridge for this agent
    SignalBridge.subscribe(agent)

    {:ok, agent}
  end

  @doc """
  Publish a signal with Command tracking.
  """
  def publish(topic, payload, opts \\ []) do
    session_id = opts[:session_id]

    # Record event
    record_event(:signal_published, topic, payload, session_id)

    # Publish via Synapse
    SignalRouter.publish(router(), topic, payload)
  end

  @doc """
  List all agents with status.
  """
  def list_agents(opts \\ []) do
    agents = Repo.all(Agent)

    Enum.map(agents, fn agent ->
      synapse_status = Orchestrator.Runtime.agent_status(runtime(), agent.name)

      %{
        agent: agent,
        running: synapse_status.alive?,
        spawn_count: synapse_status.spawn_count,
        last_error: synapse_status.last_error,
        costs_today: Command.Costs.for_agent(agent.id)
      }
    end)
  end
end
```

**Deliverables:**
- [ ] Create Agent schema
- [ ] Create Event schema
- [ ] Implement main context functions
- [ ] Create tests

#### 3.2 Signal Bridge Implementation

**Files to Create:**
- `lib/command/orchestration/signal_bridge.ex`

```elixir
# lib/command/orchestration/signal_bridge.ex
defmodule Command.Orchestration.SignalBridge do
  @moduledoc """
  Bridges Synapse signals to Command PubSub.
  """
  use GenServer

  alias Synapse.SignalRouter
  alias Command.{PubSub, Costs}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def subscribe(agent) do
    GenServer.call(__MODULE__, {:subscribe, agent})
  end

  @impl true
  def init(_opts) do
    {:ok, %{subscriptions: %{}}}
  end

  @impl true
  def handle_call({:subscribe, agent}, _from, state) do
    # Subscribe to agent's emit topics
    for topic <- agent.signals.emits do
      {:ok, ref} = SignalRouter.subscribe(router(), topic, self())
      state = put_in(state, [:subscriptions, {agent.id, topic}], ref)
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:signal, signal}, state) do
    # Extract metadata
    %{type: type, data: data, source: source} = signal

    # Record costs if present
    if data[:tokens] do
      Costs.record(%{
        source: :synapse,
        agent_id: source,
        provider: data[:provider],
        model: data[:model],
        tokens: data[:tokens]
      })
    end

    # Broadcast to Phoenix PubSub
    PubSub.broadcast("orchestration:signals", {:signal, signal})
    PubSub.broadcast("agent:#{source}", {:signal, signal})

    {:noreply, state}
  end
end
```

**Deliverables:**
- [ ] Implement SignalBridge GenServer
- [ ] Add to supervision tree
- [ ] Test signal forwarding
- [ ] Test cost extraction

#### 3.3 Domain Registration

**Files to Create:**
- `lib/command/orchestration/domains/code_review.ex`
- `lib/command/orchestration/domains/data_processing.ex`

```elixir
# lib/command/orchestration/domains/code_review.ex
defmodule Command.Orchestration.Domains.CodeReview do
  @moduledoc """
  Code review domain for Command.
  """

  alias Command.Orchestration

  def register do
    # Register Synapse domain
    Synapse.Domains.CodeReview.register()

    # Register Command agents
    register_agents()
  end

  defp register_agents do
    agents = [
      coordinator_config(),
      security_specialist_config(),
      performance_specialist_config(),
      style_specialist_config()
    ]

    for config <- agents do
      Orchestration.register_agent(config)
    end
  end

  defp coordinator_config do
    %{
      name: :code_review_coordinator,
      type: :orchestrator,
      signals: %{
        subscribes: [:review_request, :review_result],
        emits: [:review_summary]
      },
      config: %{
        classify_fn: &classify_pr/1,
        spawn_specialists: &select_specialists/1,
        aggregation_fn: &aggregate_reviews/2
      },
      approval_rules: [
        %{action: :approve_pr, requires: :human_approval}
      ]
    }
  end

  # ... specialist configs
end
```

**Deliverables:**
- [ ] Create CodeReview domain
- [ ] Create DataProcessing domain
- [ ] Document domain creation pattern
- [ ] Test domain registration

---

## Phase 4: Tool Management (ALTAR)

### Goals
- Create Command.Tools context
- Integrate ALTAR ADM and LATER
- Connect tools to approval system

### Tasks

#### 4.1 Create Tools Context

**Files to Create:**
- `lib/command/tools.ex` - Main context
- `lib/command/tools/tool.ex` - Schema
- `lib/command/tools/call.ex` - Call schema
- `lib/command/tools/executor.ex` - Execution wrapper

```elixir
# lib/command/tools.ex
defmodule Command.Tools do
  @moduledoc """
  Tool management context integrating ALTAR.
  """

  alias Altar.ADM
  alias Altar.LATER.{Registry, Executor}
  alias Command.Tools.{Tool, Call}
  alias Command.{Approvals, Costs}

  @doc """
  Register a new tool.
  """
  def register(name, description, params_schema, implementation, opts \\ []) do
    # Create ADM declaration
    {:ok, decl} = ADM.new_function_declaration(%{
      name: name,
      description: description,
      parameters: params_schema
    })

    # Persist to Command
    {:ok, tool} = create_tool(%{
      name: name,
      description: description,
      declaration: ADM.FunctionDeclaration.to_map(decl),
      implementation_module: inspect(implementation),
      approval_rules: opts[:approval_rules] || [],
      cost_config: opts[:cost_config] || %{}
    })

    # Register with ALTAR
    wrapped = wrap_with_telemetry(tool, implementation)
    :ok = Registry.register_tool(registry(), decl, wrapped)

    {:ok, tool}
  end

  @doc """
  Execute a tool call.
  """
  def execute(call_id, name, args, opts \\ []) do
    tool = get_tool_by_name!(name)

    # Check approval
    case check_approval(tool, args, opts[:user_id]) do
      :approved ->
        do_execute(tool, call_id, args, opts)

      :pending ->
        create_pending_call(tool, call_id, args, opts)

      :denied ->
        {:error, :denied}
    end
  end

  @doc """
  Get tool declarations for LLM function calling.
  """
  def for_llm(opts \\ []) do
    list_tools(opts)
    |> Enum.map(fn tool ->
      tool.declaration
    end)
  end
end
```

**Deliverables:**
- [ ] Create Tool schema
- [ ] Create Call schema
- [ ] Implement main context functions
- [ ] Add approval integration
- [ ] Create tests

#### 4.2 Built-in Tools

**Files to Create:**
- `lib/command/tools/builtins/file_operations.ex`
- `lib/command/tools/builtins/web_search.ex`
- `lib/command/tools/builtins/code_execution.ex`

```elixir
# lib/command/tools/builtins/file_operations.ex
defmodule Command.Tools.Builtins.FileOperations do
  @moduledoc """
  File operation tools for agents.
  """

  alias Command.Tools

  def register_all do
    Tools.register(
      "read_file",
      "Read contents of a file",
      %{
        type: :OBJECT,
        properties: %{
          "path" => %{type: :STRING, description: "File path to read"}
        },
        required: ["path"]
      },
      &read_file/1,
      approval_rules: [
        %{pattern: "**/.env*", requires: :human_approval},
        %{pattern: "**/secrets/**", requires: :deny}
      ]
    )

    Tools.register(
      "write_file",
      "Write contents to a file",
      %{
        type: :OBJECT,
        properties: %{
          "path" => %{type: :STRING},
          "content" => %{type: :STRING}
        },
        required: ["path", "content"]
      },
      &write_file/1,
      approval_rules: [%{action: :write, requires: :human_approval}]
    )

    Tools.register(
      "list_directory",
      "List files in a directory",
      %{
        type: :OBJECT,
        properties: %{
          "path" => %{type: :STRING}
        },
        required: ["path"]
      },
      &list_directory/1
    )
  end

  defp read_file(%{"path" => path}) do
    case File.read(path) do
      {:ok, content} -> %{content: content, path: path}
      {:error, reason} -> %{error: inspect(reason)}
    end
  end

  defp write_file(%{"path" => path, "content" => content}) do
    case File.write(path, content) do
      :ok -> %{success: true, path: path, bytes: byte_size(content)}
      {:error, reason} -> %{error: inspect(reason)}
    end
  end

  defp list_directory(%{"path" => path}) do
    case File.ls(path) do
      {:ok, files} -> %{files: files, path: path}
      {:error, reason} -> %{error: inspect(reason)}
    end
  end
end
```

**Deliverables:**
- [ ] Implement FileOperations tools
- [ ] Implement WebSearch tools
- [ ] Implement CodeExecution tools
- [ ] Register on startup
- [ ] Create tests

---

## Phase 5: Dashboard & API

### Goals
- Create unified monitoring dashboard
- Expose REST/GraphQL API
- Real-time updates via WebSocket

### Tasks

#### 5.1 LiveView Dashboard

**Files to Create:**
- `lib/command_web/live/dashboard_live.ex`
- `lib/command_web/live/pipelines_live.ex`
- `lib/command_web/live/agents_live.ex`
- `lib/command_web/live/tools_live.ex`

```elixir
# lib/command_web/live/dashboard_live.ex
defmodule CommandWeb.DashboardLive do
  use CommandWeb, :live_view

  alias Command.{Pipelines, Orchestration, Tools, Costs}

  def mount(_params, session, socket) do
    if connected?(socket) do
      subscribe_to_events()
    end

    {:ok, assign(socket,
      pipelines: Pipelines.list_active(),
      agents: Orchestration.list_agents(),
      tools: Tools.list_tools(status: :active),
      costs_today: Costs.today_summary(),
      recent_events: []
    )}
  end

  def handle_info({:pipeline_update, pipeline_id, status}, socket) do
    {:noreply, update_pipeline(socket, pipeline_id, status)}
  end

  def handle_info({:agent_event, agent_id, event}, socket) do
    socket = socket
    |> update_agent(agent_id, event)
    |> prepend_event(event)

    {:noreply, socket}
  end

  def handle_info({:cost_recorded, cost}, socket) do
    {:noreply, update_costs(socket, cost)}
  end

  defp subscribe_to_events do
    Command.PubSub.subscribe("pipeline:*")
    Command.PubSub.subscribe("orchestration:*")
    Command.PubSub.subscribe("costs:*")
  end
end
```

**Deliverables:**
- [ ] Create main dashboard
- [ ] Create pipelines view
- [ ] Create agents view
- [ ] Create tools view
- [ ] Add real-time updates
- [ ] Create tests

#### 5.2 GraphQL API

**Files to Create:**
- `lib/command_web/schema.ex`
- `lib/command_web/resolvers/pipelines_resolver.ex`
- `lib/command_web/resolvers/orchestration_resolver.ex`
- `lib/command_web/resolvers/tools_resolver.ex`

```elixir
# lib/command_web/schema.ex (additions)
defmodule CommandWeb.Schema do
  use Absinthe.Schema

  import_types CommandWeb.Schema.PipelinesTypes
  import_types CommandWeb.Schema.OrchestrationTypes
  import_types CommandWeb.Schema.ToolsTypes

  query do
    # Pipelines
    field :pipelines, list_of(:pipeline) do
      resolve &Resolvers.Pipelines.list/3
    end

    field :pipeline, :pipeline do
      arg :id, non_null(:id)
      resolve &Resolvers.Pipelines.get/3
    end

    # Agents
    field :agents, list_of(:agent) do
      resolve &Resolvers.Orchestration.list_agents/3
    end

    # Tools
    field :tools, list_of(:tool) do
      resolve &Resolvers.Tools.list/3
    end
  end

  mutation do
    field :run_pipeline, :pipeline_run do
      arg :pipeline_id, non_null(:id)
      arg :partition, :string
      resolve &Resolvers.Pipelines.run/3
    end

    field :publish_signal, :signal_result do
      arg :topic, non_null(:string)
      arg :payload, non_null(:json)
      resolve &Resolvers.Orchestration.publish/3
    end

    field :execute_tool, :tool_result do
      arg :name, non_null(:string)
      arg :args, non_null(:json)
      resolve &Resolvers.Tools.execute/3
    end
  end

  subscription do
    field :pipeline_events, :pipeline_event do
      arg :pipeline_id, non_null(:id)
      config fn args, _ -> {:ok, topic: "pipeline:#{args.pipeline_id}"} end
    end

    field :agent_events, :agent_event do
      arg :agent_id, :id
      config fn args, _ ->
        topic = if args.agent_id, do: "agent:#{args.agent_id}", else: "orchestration:*"
        {:ok, topic: topic}
      end
    end
  end
end
```

**Deliverables:**
- [ ] Create GraphQL schema
- [ ] Implement resolvers
- [ ] Add subscriptions
- [ ] Create API documentation
- [ ] Create tests

---

## Phase 6: Testing & Documentation

### Goals
- Comprehensive test coverage
- API documentation
- User guides

### Tasks

#### 6.1 Integration Tests

**Files to Create:**
- `test/command/pipelines_test.exs`
- `test/command/orchestration_test.exs`
- `test/command/tools_test.exs`
- `test/integration/full_workflow_test.exs`

**Deliverables:**
- [ ] Unit tests for all contexts
- [ ] Integration tests for cross-context flows
- [ ] End-to-end tests
- [ ] Performance tests

#### 6.2 Documentation

**Files to Create:**
- `docs/guides/pipelines.md`
- `docs/guides/orchestration.md`
- `docs/guides/tools.md`
- `docs/api/graphql.md`

**Deliverables:**
- [ ] Context documentation
- [ ] API documentation
- [ ] Getting started guide
- [ ] Example applications

---

## Summary

### Phase Dependencies

```
Phase 1: Foundation
    │
    ├──► Phase 2: Pipelines (FlowStone)
    │
    ├──► Phase 3: Orchestration (Synapse)
    │
    └──► Phase 4: Tools (ALTAR)
              │
              └──► Phase 5: Dashboard & API
                        │
                        └──► Phase 6: Testing & Docs
```

### Effort Estimates (Relative)

| Phase | Complexity | Dependencies |
|-------|------------|--------------|
| Phase 1 | Low | None |
| Phase 2 | Medium | FlowStone |
| Phase 3 | Medium | Synapse |
| Phase 4 | Low | ALTAR |
| Phase 5 | Medium | Phases 2-4 |
| Phase 6 | Low | All phases |

### Success Criteria

1. **Pipeline Execution**: Successfully run FlowStone pipelines with Command cost/approval tracking
2. **Agent Orchestration**: Deploy multi-agent workflows with signal routing and session tracking
3. **Tool Management**: Register and execute tools with approval workflows
4. **Unified Dashboard**: Monitor all subsystems in real-time
5. **API Access**: GraphQL/REST access to all operations
6. **Test Coverage**: >80% coverage with integration tests
