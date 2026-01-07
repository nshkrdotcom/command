# Synapse Integration Design

**Date**: 2026-01-05
**Version**: 1.0.0

## Overview

This document details the integration design between Command and Synapse, including required enhancements to both libraries and the complete implementation specification for multi-agent orchestration.

---

## 1. Synapse Library Enhancements Required

### 1.1 Signal Router Extension for Command Correlation

**Current State** (`synapse/lib/synapse/signal.ex`):
```elixir
defstruct [
  :id, :type, :source, :target, :payload, :request_id,
  :timestamp, :ttl, :metadata
]
```

**Required Enhancement**:
```elixir
# synapse/lib/synapse/signal.ex
defstruct [
  :id, :type, :source, :target, :payload, :request_id,
  :timestamp, :ttl, :metadata,
  # NEW: Command integration fields
  :command_session_id,      # UUID linking to Command session
  :command_workflow_id,     # UUID linking to Command workflow instance
  :command_user_id,         # UUID of executing user
  :correlation_id,          # External correlation ID for tracing
  :parent_signal_id         # For signal chain tracking
]

@type t :: %__MODULE__{
  # ... existing types ...
  command_session_id: Ecto.UUID.t() | nil,
  command_workflow_id: Ecto.UUID.t() | nil,
  command_user_id: Ecto.UUID.t() | nil,
  correlation_id: String.t() | nil,
  parent_signal_id: String.t() | nil
}

@doc """
Create signal with Command context inherited from parent.
"""
def derive(parent_signal, type, payload, opts \\ []) do
  %__MODULE__{
    id: Ecto.UUID.generate(),
    type: type,
    source: opts[:source],
    target: opts[:target],
    payload: payload,
    request_id: parent_signal.request_id,
    timestamp: DateTime.utc_now(),
    ttl: opts[:ttl],
    metadata: opts[:metadata] || %{},
    # Inherit Command context
    command_session_id: parent_signal.command_session_id,
    command_workflow_id: parent_signal.command_workflow_id,
    command_user_id: parent_signal.command_user_id,
    correlation_id: parent_signal.correlation_id,
    parent_signal_id: parent_signal.id
  }
end
```

### 1.2 Enhanced Signal Router with External Bridge

**Current State**: `SignalRouter` is an in-memory GenServer.

**Required Enhancement** (`synapse/lib/synapse/signal_router.ex`):
```elixir
defmodule Synapse.SignalRouter do
  use GenServer

  # ... existing code ...

  # NEW: External signal bridge support
  @external_bridges_table :synapse_external_bridges

  def init(opts) do
    :ets.new(@external_bridges_table, [:set, :public, :named_table])

    state = %{
      subscriptions: %{},
      pending_signals: :queue.new(),
      external_bridges: []  # List of {module, config} tuples
    }

    {:ok, state}
  end

  @doc """
  Register an external signal bridge.

  Bridges receive all signals and can forward them to external systems
  (e.g., Phoenix PubSub, HTTP webhooks, message queues).
  """
  def register_bridge(bridge_module, config \\ %{}) do
    GenServer.call(__MODULE__, {:register_bridge, bridge_module, config})
  end

  @doc """
  Emit a signal with automatic bridge forwarding.
  """
  def emit(signal) do
    GenServer.cast(__MODULE__, {:emit, signal})
  end

  def handle_cast({:emit, signal}, state) do
    # Route to local subscribers
    route_signal(signal, state.subscriptions)

    # Forward to external bridges
    Enum.each(state.external_bridges, fn {module, config} ->
      Task.start(fn ->
        module.forward_signal(signal, config)
      end)
    end)

    {:noreply, state}
  end

  def handle_call({:register_bridge, module, config}, _from, state) do
    bridges = [{module, config} | state.external_bridges]
    {:reply, :ok, %{state | external_bridges: bridges}}
  end

  @doc """
  Receive signal from external source (HTTP, PubSub, etc).
  """
  def receive_external(signal_attrs) do
    signal = Synapse.Signal.new(signal_attrs)
    emit(signal)
  end
end
```

### 1.3 Phoenix PubSub Bridge

**New Module** (`synapse/lib/synapse/bridges/phoenix_pubsub.ex`):
```elixir
defmodule Synapse.Bridges.PhoenixPubSub do
  @moduledoc """
  Bridge between Synapse signals and Phoenix PubSub.

  Enables:
  - LiveView components to subscribe to agent signals
  - External systems to inject signals via PubSub
  - Cross-node signal propagation
  """

  @behaviour Synapse.Bridge

  @impl true
  def forward_signal(signal, config) do
    pubsub = config[:pubsub] || raise "pubsub module required"

    # Publish to type-based topic
    topic = signal_topic(signal)
    Phoenix.PubSub.broadcast(pubsub, topic, {:synapse_signal, signal})

    # Publish to session topic if Command session exists
    if signal.command_session_id do
      session_topic = "command:session:#{signal.command_session_id}"
      Phoenix.PubSub.broadcast(pubsub, session_topic, {:synapse_signal, signal})
    end

    # Publish to workflow topic if exists
    if signal.command_workflow_id do
      workflow_topic = "command:workflow:#{signal.command_workflow_id}"
      Phoenix.PubSub.broadcast(pubsub, workflow_topic, {:synapse_signal, signal})
    end

    :ok
  end

  @doc """
  Subscribe a process to Synapse signals via PubSub.
  """
  def subscribe(pubsub, signal_type) do
    Phoenix.PubSub.subscribe(pubsub, "synapse:signals:#{signal_type}")
  end

  @doc """
  Subscribe to all signals for a Command session.
  """
  def subscribe_session(pubsub, session_id) do
    Phoenix.PubSub.subscribe(pubsub, "command:session:#{session_id}")
  end

  @doc """
  Subscribe to all signals for a Command workflow.
  """
  def subscribe_workflow(pubsub, workflow_id) do
    Phoenix.PubSub.subscribe(pubsub, "command:workflow:#{workflow_id}")
  end

  defp signal_topic(%{type: type}) do
    "synapse:signals:#{type}"
  end
end
```

### 1.4 HTTP Signal Gateway

**New Module** (`synapse/lib/synapse/bridges/http_gateway.ex`):
```elixir
defmodule Synapse.Bridges.HTTPGateway do
  @moduledoc """
  HTTP gateway for external signal injection and webhook delivery.

  Provides:
  - REST endpoint for external systems to send signals
  - Webhook delivery for signal forwarding
  - Authentication via signed tokens
  """

  @behaviour Synapse.Bridge

  alias Synapse.Signal
  alias Synapse.SignalRouter

  @impl true
  def forward_signal(signal, config) do
    if webhook_url = config[:webhook_url] do
      deliver_webhook(signal, webhook_url, config)
    else
      :ok
    end
  end

  defp deliver_webhook(signal, url, config) do
    headers = build_headers(signal, config)

    body = %{
      signal_id: signal.id,
      type: signal.type,
      source: signal.source,
      target: signal.target,
      payload: signal.payload,
      request_id: signal.request_id,
      command_session_id: signal.command_session_id,
      command_workflow_id: signal.command_workflow_id,
      timestamp: signal.timestamp
    }

    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok
      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_headers(signal, config) do
    base_headers = [
      {"content-type", "application/json"},
      {"x-synapse-signal-id", signal.id},
      {"x-synapse-signal-type", to_string(signal.type)}
    ]

    if secret = config[:webhook_secret] do
      signature = compute_signature(signal, secret)
      [{"x-synapse-signature", signature} | base_headers]
    else
      base_headers
    end
  end

  defp compute_signature(signal, secret) do
    payload = Jason.encode!(signal)
    :crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower)
  end

  # Plug for receiving external signals

  defmodule Plug do
    @moduledoc """
    Plug for receiving external signals via HTTP POST.

    Usage in Phoenix Router:
        forward "/api/synapse/signals", Synapse.Bridges.HTTPGateway.Plug
    """

    use Plug.Router

    plug :match
    plug Plug.Parsers, parsers: [:json], json_decoder: Jason
    plug :dispatch

    post "/" do
      with {:ok, signal_attrs} <- validate_request(conn),
           :ok <- authenticate_request(conn),
           signal <- Synapse.Signal.new(signal_attrs) do
        Synapse.SignalRouter.emit(signal)
        send_resp(conn, 202, Jason.encode!(%{status: "accepted", signal_id: signal.id}))
      else
        {:error, reason} ->
          send_resp(conn, 400, Jason.encode!(%{error: reason}))
      end
    end

    defp validate_request(conn) do
      required_fields = ["type", "payload"]

      if Enum.all?(required_fields, &Map.has_key?(conn.body_params, &1)) do
        {:ok, %{
          type: String.to_atom(conn.body_params["type"]),
          source: conn.body_params["source"],
          target: conn.body_params["target"],
          payload: conn.body_params["payload"],
          command_session_id: conn.body_params["command_session_id"],
          command_workflow_id: conn.body_params["command_workflow_id"],
          metadata: conn.body_params["metadata"] || %{}
        }}
      else
        {:error, "missing required fields: type, payload"}
      end
    end

    defp authenticate_request(conn) do
      # Implement authentication based on config
      # e.g., API key, JWT, HMAC signature
      :ok
    end
  end
end
```

### 1.5 Persistent Agent Configuration

**Current State**: Agent configuration is code-based only.

**Required Enhancement** (`synapse/lib/synapse/agent_config.ex`):
```elixir
defmodule Synapse.AgentConfig do
  @moduledoc """
  Persistent agent configuration management.

  Allows dynamic agent creation and configuration without code changes.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "synapse_agent_configs" do
    field :name, :string
    field :type, Ecto.Enum, values: [:specialist, :orchestrator, :hybrid]
    field :module, :string  # Optional: custom module to use
    field :status, Ecto.Enum, values: [:active, :inactive, :deprecated]
    field :config, :map, default: %{}

    # Agent behavior configuration
    field :system_prompt, :string
    field :capabilities, {:array, :string}, default: []
    field :signal_subscriptions, {:array, :string}, default: []
    field :response_signals, {:array, :string}, default: []

    # AI model configuration
    field :model_provider, :string
    field :model_name, :string
    field :model_params, :map, default: %{}

    # Rate limiting and quotas
    field :rate_limit_rpm, :integer  # Requests per minute
    field :rate_limit_tpm, :integer  # Tokens per minute
    field :max_concurrent, :integer, default: 10

    # Command integration
    field :command_agent_id, :binary_id
    field :approval_required, :boolean, default: false
    field :cost_budget_usd, :decimal

    timestamps()
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [
      :name, :type, :module, :status, :config, :system_prompt,
      :capabilities, :signal_subscriptions, :response_signals,
      :model_provider, :model_name, :model_params,
      :rate_limit_rpm, :rate_limit_tpm, :max_concurrent,
      :command_agent_id, :approval_required, :cost_budget_usd
    ])
    |> validate_required([:name, :type])
    |> unique_constraint(:name)
  end

  # Query helpers

  def active do
    from(c in __MODULE__, where: c.status == :active)
  end

  def by_type(query \\ __MODULE__, type) do
    from(c in query, where: c.type == ^type)
  end

  def subscribing_to(query \\ __MODULE__, signal_type) do
    from(c in query, where: ^to_string(signal_type) in c.signal_subscriptions)
  end
end
```

### 1.6 Dynamic Agent Supervisor

**New Module** (`synapse/lib/synapse/agent_supervisor.ex`):
```elixir
defmodule Synapse.AgentSupervisor do
  @moduledoc """
  Dynamic supervisor for agent processes.

  Manages agent lifecycle based on persistent configuration.
  """

  use DynamicSupervisor

  alias Synapse.{AgentConfig, SignalRouter}

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start an agent from persistent configuration.
  """
  def start_agent(config_id) when is_binary(config_id) do
    config = Synapse.Repo.get!(AgentConfig, config_id)
    start_agent(config)
  end

  def start_agent(%AgentConfig{} = config) do
    child_spec = build_child_spec(config)
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  @doc """
  Stop a running agent.
  """
  def stop_agent(config_id) do
    case find_agent_pid(config_id) do
      nil -> {:error, :not_running}
      pid -> DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end

  @doc """
  Restart an agent with updated configuration.
  """
  def restart_agent(config_id) do
    with :ok <- stop_agent(config_id),
         {:ok, _pid} <- start_agent(config_id) do
      :ok
    end
  end

  @doc """
  Start all active agents from database configuration.
  """
  def start_all_active do
    AgentConfig
    |> AgentConfig.active()
    |> Synapse.Repo.all()
    |> Enum.map(&start_agent/1)
  end

  @doc """
  List running agents.
  """
  def list_running do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, _} ->
      GenServer.call(pid, :get_config)
    end)
  end

  # Private

  defp build_child_spec(%AgentConfig{} = config) do
    module = resolve_agent_module(config)

    # Agent uses Altar.AI.Integrations.Synapse for LLM calls
    # See 07_ai_layer_consolidation.md for unified AI layer details
    agent_opts = %{
      config_id: config.id,
      name: config.name,
      system_prompt: config.system_prompt,
      capabilities: config.capabilities,
      signal_subscriptions: config.signal_subscriptions,
      response_signals: config.response_signals,
      model: {config.model_provider, config.model_name, config.model_params},
      rate_limit: %{
        rpm: config.rate_limit_rpm,
        tpm: config.rate_limit_tpm
      },
      max_concurrent: config.max_concurrent,
      command_integration: %{
        agent_id: config.command_agent_id,
        approval_required: config.approval_required,
        cost_budget: config.cost_budget_usd
      }
    }

    %{
      id: {:agent, config.id},
      start: {module, :start_link, [agent_opts]},
      restart: :transient
    }
  end

  defp resolve_agent_module(%{module: nil, type: :specialist}), do: Synapse.Agents.Specialist
  defp resolve_agent_module(%{module: nil, type: :orchestrator}), do: Synapse.Agents.Orchestrator
  defp resolve_agent_module(%{module: nil, type: :hybrid}), do: Synapse.Agents.Hybrid
  defp resolve_agent_module(%{module: module}), do: String.to_existing_atom(module)

  defp find_agent_pid(config_id) do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.find_value(fn
      {{:agent, ^config_id}, pid, _, _} -> pid
      _ -> nil
    end)
  end
end
```

### 1.7 Enhanced Workflow Persistence

**Current State**: `SynapseWorkflow` uses ETS for single execution.

**Required Enhancement** (`synapse/lib/synapse/workflow_persistence.ex`):
```elixir
defmodule Synapse.WorkflowPersistence do
  @moduledoc """
  Database-backed workflow persistence for multi-turn conversations
  and crash recovery.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Synapse.{Repo, Signal}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "synapse_workflow_states" do
    field :request_id, :string
    field :status, Ecto.Enum,
      values: [:pending, :running, :waiting, :completed, :failed, :cancelled]
    field :state_data, :map, default: %{}
    field :checkpoints, {:array, :map}, default: []
    field :signal_history, {:array, :map}, default: []
    field :error, :map

    # Command integration
    field :command_session_id, :binary_id
    field :command_workflow_id, :binary_id
    field :command_user_id, :binary_id

    # Workflow metadata
    field :workflow_module, :string
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :last_activity_at, :utc_datetime_usec

    timestamps()
  end

  def changeset(state, attrs) do
    state
    |> cast(attrs, [
      :request_id, :status, :state_data, :checkpoints, :signal_history, :error,
      :command_session_id, :command_workflow_id, :command_user_id,
      :workflow_module, :started_at, :completed_at, :last_activity_at
    ])
    |> validate_required([:request_id, :status])
    |> unique_constraint(:request_id)
  end

  # State management

  @doc """
  Create or resume workflow state.
  """
  def get_or_create(request_id, opts \\ []) do
    case Repo.get_by(__MODULE__, request_id: request_id) do
      nil ->
        create_new(request_id, opts)
      existing ->
        {:ok, existing}
    end
  end

  defp create_new(request_id, opts) do
    %__MODULE__{}
    |> changeset(%{
      request_id: request_id,
      status: :pending,
      command_session_id: opts[:command_session_id],
      command_workflow_id: opts[:command_workflow_id],
      command_user_id: opts[:command_user_id],
      workflow_module: opts[:workflow_module] && to_string(opts[:workflow_module]),
      started_at: DateTime.utc_now(),
      last_activity_at: DateTime.utc_now()
    })
    |> Repo.insert()
  end

  @doc """
  Update workflow state with checkpoint.
  """
  def checkpoint(workflow_state, checkpoint_name, data) do
    checkpoint = %{
      name: checkpoint_name,
      data: data,
      timestamp: DateTime.utc_now()
    }

    workflow_state
    |> changeset(%{
      status: :running,
      checkpoints: workflow_state.checkpoints ++ [checkpoint],
      state_data: Map.merge(workflow_state.state_data, data),
      last_activity_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @doc """
  Record signal in history.
  """
  def record_signal(workflow_state, %Signal{} = signal) do
    signal_record = %{
      signal_id: signal.id,
      type: signal.type,
      source: signal.source,
      target: signal.target,
      timestamp: signal.timestamp,
      payload_summary: summarize_payload(signal.payload)
    }

    workflow_state
    |> changeset(%{
      signal_history: workflow_state.signal_history ++ [signal_record],
      last_activity_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @doc """
  Mark workflow as waiting for external input.
  """
  def await_input(workflow_state, await_type, context) do
    workflow_state
    |> changeset(%{
      status: :waiting,
      state_data: Map.merge(workflow_state.state_data, %{
        awaiting: await_type,
        await_context: context
      }),
      last_activity_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @doc """
  Resume workflow from waiting state.
  """
  def resume(workflow_state, input) do
    workflow_state
    |> changeset(%{
      status: :running,
      state_data: Map.merge(workflow_state.state_data, %{
        resume_input: input,
        resumed_at: DateTime.utc_now()
      })
      |> Map.drop([:awaiting, :await_context]),
      last_activity_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @doc """
  Complete workflow.
  """
  def complete(workflow_state, result) do
    workflow_state
    |> changeset(%{
      status: :completed,
      state_data: Map.put(workflow_state.state_data, :result, result),
      completed_at: DateTime.utc_now(),
      last_activity_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @doc """
  Fail workflow with error.
  """
  def fail(workflow_state, error) do
    workflow_state
    |> changeset(%{
      status: :failed,
      error: serialize_error(error),
      completed_at: DateTime.utc_now(),
      last_activity_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  # Query helpers

  def for_session(session_id) do
    from(w in __MODULE__, where: w.command_session_id == ^session_id)
  end

  def active do
    from(w in __MODULE__, where: w.status in [:pending, :running, :waiting])
  end

  def stale(since) do
    from(w in __MODULE__,
      where: w.status in [:running, :waiting],
      where: w.last_activity_at < ^since
    )
  end

  # Recovery

  @doc """
  Recover stale workflows (e.g., after node restart).
  """
  def recover_stale(timeout_minutes \\ 30) do
    cutoff = DateTime.add(DateTime.utc_now(), -timeout_minutes, :minute)

    stale(cutoff)
    |> Repo.all()
    |> Enum.each(fn workflow ->
      fail(workflow, %{reason: :timeout, message: "Workflow stale recovery"})
    end)
  end

  defp summarize_payload(payload) when is_binary(payload) and byte_size(payload) > 500 do
    String.slice(payload, 0, 500) <> "..."
  end
  defp summarize_payload(payload), do: payload

  defp serialize_error(%{__struct__: struct} = error) do
    %{type: struct, message: Exception.message(error)}
  end
  defp serialize_error(error) when is_binary(error) do
    %{message: error}
  end
  defp serialize_error(error) do
    %{message: inspect(error)}
  end
end
```

### 1.8 Enhanced Telemetry for Cost Tracking

**New Module** (`synapse/lib/synapse/telemetry.ex`):
```elixir
defmodule Synapse.Telemetry do
  @moduledoc """
  Telemetry events for Synapse operations.
  """

  @doc """
  Emit signal routing telemetry.
  """
  def signal_routed(signal, duration_ns) do
    :telemetry.execute(
      [:synapse, :signal, :routed],
      %{duration: duration_ns, count: 1},
      %{
        signal_type: signal.type,
        source: signal.source,
        target: signal.target,
        command_session_id: signal.command_session_id,
        command_workflow_id: signal.command_workflow_id
      }
    )
  end

  @doc """
  Emit agent execution telemetry.
  """
  def agent_execution(agent_name, measurements, metadata) do
    :telemetry.execute(
      [:synapse, :agent, :execution],
      Map.merge(measurements, %{
        duration: measurements[:duration] || 0,
        tokens_in: measurements[:tokens_in] || 0,
        tokens_out: measurements[:tokens_out] || 0,
        cost_usd: measurements[:cost_usd] || 0.0
      }),
      Map.merge(metadata, %{
        agent_name: agent_name,
        command_session_id: metadata[:command_session_id],
        command_workflow_id: metadata[:command_workflow_id]
      })
    )
  end

  @doc """
  Emit workflow step telemetry.
  """
  def workflow_step(step_name, status, measurements, metadata) do
    :telemetry.execute(
      [:synapse, :workflow, :step],
      measurements,
      Map.merge(metadata, %{
        step_name: step_name,
        status: status
      })
    )
  end

  @doc """
  Span wrapper for agent execution.
  """
  defmacro span_agent(agent_name, metadata, do: block) do
    quote do
      start_time = System.monotonic_time()

      try do
        result = unquote(block)

        duration = System.monotonic_time() - start_time
        Synapse.Telemetry.agent_execution(
          unquote(agent_name),
          %{duration: duration},
          Map.merge(unquote(metadata), %{status: :ok})
        )

        result
      rescue
        error ->
          duration = System.monotonic_time() - start_time
          Synapse.Telemetry.agent_execution(
            unquote(agent_name),
            %{duration: duration},
            Map.merge(unquote(metadata), %{status: :error, error: error})
          )

          reraise error, __STACKTRACE__
      end
    end
  end
end
```

---

## 2. Command Integration Modules

### 2.1 Command.Orchestration Context

**File**: `command/lib/command/orchestration.ex`

```elixir
defmodule Command.Orchestration do
  @moduledoc """
  Multi-agent orchestration context integrating Synapse.

  Provides:
  - Agent configuration and lifecycle management
  - Workflow execution with Command session tracking
  - Signal routing and history
  - Cost tracking per agent execution
  """

  alias Command.{Repo, Sessions, Costs, Agents}
  alias Command.Orchestration.{AgentInstance, WorkflowRun, AgentExecution}
  alias Synapse.{SignalRouter, AgentSupervisor, WorkflowPersistence}

  import Ecto.Query

  # ============================================
  # Agent Instance Management
  # ============================================

  @doc """
  Create an agent instance from Command agent template.
  """
  def create_agent_instance(agent_id, opts \\ []) do
    agent = Agents.get_agent!(agent_id)

    # Create Synapse agent config
    {:ok, synapse_config} = Synapse.AgentConfig.changeset(%Synapse.AgentConfig{}, %{
      name: opts[:name] || "#{agent.name}-#{short_id()}",
      type: map_agent_type(agent.type),
      system_prompt: agent.system_prompt,
      capabilities: agent.capabilities,
      signal_subscriptions: opts[:subscriptions] || default_subscriptions(agent),
      response_signals: opts[:responses] || default_responses(agent),
      model_provider: agent.model_provider || "anthropic",
      model_name: agent.model_name || "claude-sonnet-4-20250514",
      model_params: agent.model_params || %{},
      rate_limit_rpm: opts[:rate_limit_rpm],
      rate_limit_tpm: opts[:rate_limit_tpm],
      max_concurrent: opts[:max_concurrent] || 10,
      command_agent_id: agent_id,
      approval_required: agent.requires_approval,
      cost_budget_usd: opts[:budget]
    })
    |> Synapse.Repo.insert()

    # Create Command agent instance record
    attrs = %{
      agent_id: agent_id,
      synapse_config_id: synapse_config.id,
      name: synapse_config.name,
      status: :created,
      config: %{
        subscriptions: synapse_config.signal_subscriptions,
        responses: synapse_config.response_signals,
        model: %{
          provider: synapse_config.model_provider,
          name: synapse_config.model_name
        }
      }
    }

    %AgentInstance{}
    |> AgentInstance.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Start an agent instance.
  """
  def start_agent_instance(instance_id) do
    instance = get_agent_instance!(instance_id)

    case AgentSupervisor.start_agent(instance.synapse_config_id) do
      {:ok, pid} ->
        instance
        |> AgentInstance.changeset(%{
          status: :running,
          pid: inspect(pid),
          started_at: DateTime.utc_now()
        })
        |> Repo.update()

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Stop an agent instance.
  """
  def stop_agent_instance(instance_id) do
    instance = get_agent_instance!(instance_id)

    case AgentSupervisor.stop_agent(instance.synapse_config_id) do
      :ok ->
        instance
        |> AgentInstance.changeset(%{
          status: :stopped,
          stopped_at: DateTime.utc_now()
        })
        |> Repo.update()

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  List agent instances.
  """
  def list_agent_instances(opts \\ []) do
    AgentInstance
    |> filter_by_status(opts[:status])
    |> filter_by_agent(opts[:agent_id])
    |> order_by([i], desc: i.inserted_at)
    |> Repo.all()
    |> Repo.preload(:agent)
  end

  @doc """
  Get agent instance by ID.
  """
  def get_agent_instance!(id) do
    AgentInstance
    |> Repo.get!(id)
    |> Repo.preload(:agent)
  end

  # ============================================
  # Workflow Execution
  # ============================================

  @doc """
  Start a workflow with Command tracking.

  Options:
  - :session_id - Command session to associate
  - :user_id - Executing user
  - :input - Initial workflow input
  - :timeout - Workflow timeout in milliseconds
  """
  def run_workflow(workflow_module, opts \\ []) do
    request_id = opts[:request_id] || Ecto.UUID.generate()

    # Create Command workflow run
    {:ok, run} = create_workflow_run(workflow_module, request_id, opts)

    # Create or resume Synapse workflow state
    {:ok, synapse_state} = WorkflowPersistence.get_or_create(request_id, %{
      command_session_id: run.session_id,
      command_workflow_id: run.id,
      command_user_id: run.user_id,
      workflow_module: workflow_module
    })

    # Attach telemetry handlers
    handler_id = attach_workflow_telemetry(run.id)

    try do
      # Build initial signal with Command context
      initial_signal = build_initial_signal(run, opts[:input])

      # Execute workflow
      result = execute_workflow(workflow_module, initial_signal, synapse_state, opts)

      # Finalize run
      finalize_workflow_run(run, result)
    after
      detach_workflow_telemetry(handler_id)
    end
  end

  @doc """
  Resume a waiting workflow.
  """
  def resume_workflow(run_id, input) do
    run = get_workflow_run!(run_id)

    {:ok, synapse_state} = WorkflowPersistence.get_or_create(run.request_id)
    {:ok, synapse_state} = WorkflowPersistence.resume(synapse_state, input)

    # Build continuation signal
    signal = %Synapse.Signal{
      id: Ecto.UUID.generate(),
      type: :workflow_resume,
      payload: input,
      request_id: run.request_id,
      command_session_id: run.session_id,
      command_workflow_id: run.id,
      command_user_id: run.user_id,
      timestamp: DateTime.utc_now()
    }

    # Emit to workflow
    SignalRouter.emit(signal)

    {:ok, run}
  end

  @doc """
  Cancel a running workflow.
  """
  def cancel_workflow(run_id, reason \\ "cancelled by user") do
    run = get_workflow_run!(run_id)

    # Emit cancellation signal
    signal = %Synapse.Signal{
      id: Ecto.UUID.generate(),
      type: :workflow_cancel,
      payload: %{reason: reason},
      request_id: run.request_id,
      command_session_id: run.session_id,
      command_workflow_id: run.id,
      timestamp: DateTime.utc_now()
    }

    SignalRouter.emit(signal)

    run
    |> WorkflowRun.changeset(%{
      status: :cancelled,
      completed_at: DateTime.utc_now(),
      error: %{reason: reason}
    })
    |> Repo.update()
  end

  @doc """
  Get workflow status and details.
  """
  def get_workflow_status(run_id) do
    run = get_workflow_run!(run_id)

    %{
      id: run.id,
      status: run.status,
      started_at: run.started_at,
      completed_at: run.completed_at,
      duration_ms: calculate_duration(run),
      error: run.error,
      agent_executions: list_run_executions(run),
      signal_count: count_signals(run),
      total_cost: calculate_workflow_cost(run)
    }
  end

  # ============================================
  # Signal Bridging
  # ============================================

  @doc """
  Subscribe a Phoenix channel/LiveView to workflow signals.
  """
  def subscribe_to_workflow(workflow_run_id) do
    Synapse.Bridges.PhoenixPubSub.subscribe_workflow(
      Command.PubSub,
      workflow_run_id
    )
  end

  @doc """
  Subscribe to session signals.
  """
  def subscribe_to_session(session_id) do
    Synapse.Bridges.PhoenixPubSub.subscribe_session(
      Command.PubSub,
      session_id
    )
  end

  @doc """
  Send a signal from external source (API, LiveView, etc).
  """
  def send_signal(type, payload, opts \\ []) do
    signal = %Synapse.Signal{
      id: Ecto.UUID.generate(),
      type: type,
      source: opts[:source] || :external,
      target: opts[:target],
      payload: payload,
      request_id: opts[:request_id],
      command_session_id: opts[:session_id],
      command_workflow_id: opts[:workflow_id],
      command_user_id: opts[:user_id],
      timestamp: DateTime.utc_now(),
      metadata: opts[:metadata] || %{}
    }

    SignalRouter.emit(signal)
    {:ok, signal}
  end

  # ============================================
  # Cost Tracking
  # ============================================

  @doc """
  Record an agent execution.
  """
  def record_agent_execution(attrs) do
    %AgentExecution{}
    |> AgentExecution.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Calculate total cost for a workflow run.
  """
  def calculate_workflow_cost(run_or_id) do
    run_id = if is_struct(run_or_id), do: run_or_id.id, else: run_or_id

    AgentExecution
    |> where([e], e.workflow_run_id == ^run_id)
    |> select([e], sum(e.cost_usd))
    |> Repo.one() || Decimal.new(0)
  end

  # ============================================
  # Private Functions
  # ============================================

  defp create_workflow_run(workflow_module, request_id, opts) do
    attrs = %{
      workflow_module: to_string(workflow_module),
      request_id: request_id,
      session_id: opts[:session_id],
      user_id: opts[:user_id],
      status: :pending,
      input: opts[:input],
      started_at: DateTime.utc_now()
    }

    %WorkflowRun{}
    |> WorkflowRun.changeset(attrs)
    |> Repo.insert()
  end

  defp build_initial_signal(run, input) do
    %Synapse.Signal{
      id: Ecto.UUID.generate(),
      type: :workflow_start,
      source: :command,
      payload: input || %{},
      request_id: run.request_id,
      command_session_id: run.session_id,
      command_workflow_id: run.id,
      command_user_id: run.user_id,
      timestamp: DateTime.utc_now()
    }
  end

  defp execute_workflow(module, signal, synapse_state, opts) do
    try do
      # Update state to running
      {:ok, _} = WorkflowPersistence.checkpoint(synapse_state, :started, %{})

      # Run workflow
      result = apply(module, :run, [signal, opts])

      # Complete state
      {:ok, _} = WorkflowPersistence.complete(synapse_state, result)

      {:ok, result}
    rescue
      error ->
        {:ok, _} = WorkflowPersistence.fail(synapse_state, error)
        {:error, error}
    end
  end

  defp finalize_workflow_run(run, result) do
    case result do
      {:ok, output} ->
        run
        |> WorkflowRun.changeset(%{
          status: :completed,
          completed_at: DateTime.utc_now(),
          output: output
        })
        |> Repo.update()

      {:error, error} ->
        run
        |> WorkflowRun.changeset(%{
          status: :failed,
          completed_at: DateTime.utc_now(),
          error: serialize_error(error)
        })
        |> Repo.update()

      {:waiting, await_info} ->
        run
        |> WorkflowRun.changeset(%{
          status: :waiting,
          state: %{awaiting: await_info}
        })
        |> Repo.update()
    end
  end

  defp attach_workflow_telemetry(run_id) do
    handler_id = "command-orchestration-#{run_id}"

    # Agent execution tracking
    :telemetry.attach(
      "#{handler_id}-agent",
      [:synapse, :agent, :execution],
      fn _event, measurements, metadata, _config ->
        if metadata[:command_workflow_id] == run_id do
          record_agent_execution(%{
            workflow_run_id: run_id,
            agent_name: metadata[:agent_name],
            signal_type: metadata[:signal_type],
            tokens_in: measurements[:tokens_in],
            tokens_out: measurements[:tokens_out],
            cost_usd: measurements[:cost_usd],
            duration_ms: div(measurements[:duration], 1_000_000),
            status: metadata[:status]
          })
        end
      end,
      nil
    )

    handler_id
  end

  defp detach_workflow_telemetry(handler_id) do
    :telemetry.detach("#{handler_id}-agent")
  end

  defp map_agent_type(:assistant), do: :specialist
  defp map_agent_type(:orchestrator), do: :orchestrator
  defp map_agent_type(:specialist), do: :specialist
  defp map_agent_type(_), do: :specialist

  defp default_subscriptions(agent) do
    base = ["task_request", "user_message"]
    if agent.type == :orchestrator do
      base ++ ["agent_response", "task_complete", "task_failed"]
    else
      base
    end
  end

  defp default_responses(agent) do
    if agent.type == :orchestrator do
      ["task_delegated", "orchestration_complete"]
    else
      ["agent_response", "task_complete"]
    end
  end

  defp short_id, do: :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

  defp serialize_error(%{__struct__: _} = error), do: %{message: Exception.message(error)}
  defp serialize_error(error), do: %{message: inspect(error)}

  defp calculate_duration(%{started_at: nil}), do: nil
  defp calculate_duration(%{completed_at: nil}), do: nil
  defp calculate_duration(%{started_at: started, completed_at: completed}) do
    DateTime.diff(completed, started, :millisecond)
  end
end
```

### 2.2 Orchestration Schemas

**File**: `command/lib/command/orchestration/agent_instance.ex`

```elixir
defmodule Command.Orchestration.AgentInstance do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "command_agent_instances" do
    field :name, :string
    field :synapse_config_id, :binary_id
    field :status, Ecto.Enum,
      values: [:created, :starting, :running, :stopping, :stopped, :failed],
      default: :created
    field :pid, :string
    field :config, :map, default: %{}
    field :started_at, :utc_datetime_usec
    field :stopped_at, :utc_datetime_usec
    field :error, :map

    belongs_to :agent, Command.Agents.Agent
    has_many :executions, Command.Orchestration.AgentExecution

    timestamps()
  end

  def changeset(instance, attrs) do
    instance
    |> cast(attrs, [
      :name, :synapse_config_id, :status, :pid, :config,
      :started_at, :stopped_at, :error, :agent_id
    ])
    |> validate_required([:name, :agent_id])
    |> foreign_key_constraint(:agent_id)
  end
end
```

**File**: `command/lib/command/orchestration/workflow_run.ex`

```elixir
defmodule Command.Orchestration.WorkflowRun do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "command_workflow_runs" do
    field :workflow_module, :string
    field :request_id, :string
    field :status, Ecto.Enum,
      values: [:pending, :running, :waiting, :completed, :failed, :cancelled],
      default: :pending
    field :input, :map
    field :output, :map
    field :state, :map, default: %{}
    field :error, :map
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    belongs_to :session, Command.Sessions.Session
    belongs_to :user, Command.Accounts.User
    has_many :agent_executions, Command.Orchestration.AgentExecution

    timestamps()
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :workflow_module, :request_id, :status, :input, :output,
      :state, :error, :started_at, :completed_at, :session_id, :user_id
    ])
    |> validate_required([:workflow_module, :request_id])
    |> unique_constraint(:request_id)
  end
end
```

**File**: `command/lib/command/orchestration/agent_execution.ex`

```elixir
defmodule Command.Orchestration.AgentExecution do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "command_agent_executions" do
    field :agent_name, :string
    field :signal_type, :string
    field :status, Ecto.Enum, values: [:ok, :error, :timeout]
    field :tokens_in, :integer, default: 0
    field :tokens_out, :integer, default: 0
    field :cost_usd, :decimal, default: 0
    field :duration_ms, :integer
    field :input_summary, :string
    field :output_summary, :string
    field :error, :map
    field :metadata, :map, default: %{}

    belongs_to :workflow_run, Command.Orchestration.WorkflowRun
    belongs_to :agent_instance, Command.Orchestration.AgentInstance

    timestamps()
  end

  def changeset(execution, attrs) do
    execution
    |> cast(attrs, [
      :agent_name, :signal_type, :status, :tokens_in, :tokens_out,
      :cost_usd, :duration_ms, :input_summary, :output_summary,
      :error, :metadata, :workflow_run_id, :agent_instance_id
    ])
    |> validate_required([:agent_name, :workflow_run_id])
  end
end
```

### 2.3 Signal Bridge for Phoenix

**File**: `command/lib/command/orchestration/signal_bridge.ex`

```elixir
defmodule Command.Orchestration.SignalBridge do
  @moduledoc """
  Bridges Synapse signals to Command's Phoenix PubSub.

  Enables:
  - LiveView components to receive real-time agent signals
  - Session-scoped signal routing
  - Workflow observation
  """

  use GenServer

  alias Synapse.SignalRouter

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    pubsub = opts[:pubsub] || Command.PubSub

    # Register as Synapse bridge
    SignalRouter.register_bridge(Synapse.Bridges.PhoenixPubSub, %{
      pubsub: pubsub
    })

    {:ok, %{pubsub: pubsub}}
  end

  # Public API for LiveView/Channel integration

  @doc """
  Subscribe current process to all signals for a session.
  """
  def subscribe_session(session_id) do
    Phoenix.PubSub.subscribe(Command.PubSub, "command:session:#{session_id}")
  end

  @doc """
  Subscribe to workflow signals.
  """
  def subscribe_workflow(workflow_id) do
    Phoenix.PubSub.subscribe(Command.PubSub, "command:workflow:#{workflow_id}")
  end

  @doc """
  Subscribe to specific signal types.
  """
  def subscribe_signal_type(type) do
    Phoenix.PubSub.subscribe(Command.PubSub, "synapse:signals:#{type}")
  end

  @doc """
  Broadcast a signal from external source.
  """
  def broadcast_signal(signal) do
    SignalRouter.emit(signal)
  end
end
```

### 2.4 LiveView Helper

**File**: `command/lib/command_web/live/orchestration_helpers.ex`

```elixir
defmodule CommandWeb.OrchestrationHelpers do
  @moduledoc """
  Helper functions for LiveView integration with Synapse orchestration.
  """

  import Phoenix.LiveView

  alias Command.Orchestration
  alias Command.Orchestration.SignalBridge

  @doc """
  Subscribe LiveView to workflow signals and set up handler.

  Usage in mount/3:
      socket = subscribe_to_workflow(socket, workflow_run_id)
  """
  def subscribe_to_workflow(socket, workflow_run_id) do
    if connected?(socket) do
      SignalBridge.subscribe_workflow(workflow_run_id)
    end

    assign(socket, :workflow_run_id, workflow_run_id)
  end

  @doc """
  Subscribe to session signals.
  """
  def subscribe_to_session(socket, session_id) do
    if connected?(socket) do
      SignalBridge.subscribe_session(session_id)
    end

    assign(socket, :session_id, session_id)
  end

  @doc """
  Handle incoming Synapse signal in LiveView.

  Usage in handle_info/2:
      def handle_info({:synapse_signal, signal}, socket) do
        socket = handle_synapse_signal(socket, signal)
        {:noreply, socket}
      end
  """
  def handle_synapse_signal(socket, signal) do
    case signal.type do
      :agent_response ->
        handle_agent_response(socket, signal)

      :task_complete ->
        handle_task_complete(socket, signal)

      :task_failed ->
        handle_task_failed(socket, signal)

      :workflow_waiting ->
        handle_workflow_waiting(socket, signal)

      :workflow_complete ->
        handle_workflow_complete(socket, signal)

      _ ->
        # Store in signal history
        update(socket, :signal_history, fn history ->
          [signal | history] |> Enum.take(100)
        end)
    end
  end

  defp handle_agent_response(socket, signal) do
    socket
    |> assign(:last_response, signal.payload)
    |> push_event("agent_response", %{
      agent: signal.source,
      content: signal.payload[:content],
      timestamp: signal.timestamp
    })
  end

  defp handle_task_complete(socket, signal) do
    socket
    |> assign(:task_status, :complete)
    |> push_event("task_complete", signal.payload)
  end

  defp handle_task_failed(socket, signal) do
    socket
    |> assign(:task_status, :failed)
    |> assign(:task_error, signal.payload[:error])
    |> push_event("task_failed", signal.payload)
  end

  defp handle_workflow_waiting(socket, signal) do
    socket
    |> assign(:workflow_status, :waiting)
    |> assign(:await_info, signal.payload)
  end

  defp handle_workflow_complete(socket, signal) do
    socket
    |> assign(:workflow_status, :complete)
    |> assign(:workflow_result, signal.payload)
  end

  @doc """
  Send user input to workflow.
  """
  def send_to_workflow(socket, input) do
    workflow_run_id = socket.assigns[:workflow_run_id]

    if workflow_run_id do
      Orchestration.send_signal(:user_input, input, %{
        workflow_id: workflow_run_id,
        session_id: socket.assigns[:session_id]
      })
    end

    socket
  end
end
```

---

## 3. Database Migrations

### 3.1 Synapse Tables

**File**: `synapse/priv/repo/migrations/XXXXXX_create_synapse_tables.exs`

```elixir
defmodule Synapse.Repo.Migrations.CreateSynapseTables do
  use Ecto.Migration

  def change do
    # Agent configurations
    create table(:synapse_agent_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :type, :string, null: false
      add :module, :string
      add :status, :string, default: "active"
      add :config, :map, default: %{}

      # Agent behavior
      add :system_prompt, :text
      add :capabilities, {:array, :string}, default: []
      add :signal_subscriptions, {:array, :string}, default: []
      add :response_signals, {:array, :string}, default: []

      # Model config
      add :model_provider, :string
      add :model_name, :string
      add :model_params, :map, default: %{}

      # Rate limiting
      add :rate_limit_rpm, :integer
      add :rate_limit_tpm, :integer
      add :max_concurrent, :integer, default: 10

      # Command integration
      add :command_agent_id, :binary_id
      add :approval_required, :boolean, default: false
      add :cost_budget_usd, :decimal, precision: 10, scale: 2

      timestamps()
    end

    create unique_index(:synapse_agent_configs, [:name])
    create index(:synapse_agent_configs, [:status])
    create index(:synapse_agent_configs, [:command_agent_id])

    # Workflow state persistence
    create table(:synapse_workflow_states, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :request_id, :string, null: false
      add :status, :string, default: "pending"
      add :state_data, :map, default: %{}
      add :checkpoints, {:array, :map}, default: []
      add :signal_history, {:array, :map}, default: []
      add :error, :map

      # Command integration
      add :command_session_id, :binary_id
      add :command_workflow_id, :binary_id
      add :command_user_id, :binary_id

      # Metadata
      add :workflow_module, :string
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :last_activity_at, :utc_datetime_usec

      timestamps()
    end

    create unique_index(:synapse_workflow_states, [:request_id])
    create index(:synapse_workflow_states, [:status])
    create index(:synapse_workflow_states, [:command_session_id])
    create index(:synapse_workflow_states, [:command_workflow_id])
    create index(:synapse_workflow_states, [:last_activity_at])
  end
end
```

### 3.2 Command Orchestration Tables

**File**: `command/priv/repo/migrations/XXXXXX_create_orchestration_tables.exs`

```elixir
defmodule Command.Repo.Migrations.CreateOrchestrationTables do
  use Ecto.Migration

  def change do
    # Agent instances
    create table(:command_agent_instances, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :synapse_config_id, :binary_id
      add :status, :string, default: "created"
      add :pid, :string
      add :config, :map, default: %{}
      add :started_at, :utc_datetime_usec
      add :stopped_at, :utc_datetime_usec
      add :error, :map
      add :agent_id, references(:agents, type: :binary_id), null: false

      timestamps()
    end

    create index(:command_agent_instances, [:agent_id])
    create index(:command_agent_instances, [:status])
    create index(:command_agent_instances, [:synapse_config_id])

    # Workflow runs
    create table(:command_workflow_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :workflow_module, :string, null: false
      add :request_id, :string, null: false
      add :status, :string, default: "pending"
      add :input, :map
      add :output, :map
      add :state, :map, default: %{}
      add :error, :map
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :session_id, references(:sessions, type: :binary_id)
      add :user_id, references(:users, type: :binary_id)

      timestamps()
    end

    create unique_index(:command_workflow_runs, [:request_id])
    create index(:command_workflow_runs, [:status])
    create index(:command_workflow_runs, [:session_id])
    create index(:command_workflow_runs, [:user_id])
    create index(:command_workflow_runs, [:workflow_module])

    # Agent executions
    create table(:command_agent_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :agent_name, :string, null: false
      add :signal_type, :string
      add :status, :string
      add :tokens_in, :integer, default: 0
      add :tokens_out, :integer, default: 0
      add :cost_usd, :decimal, precision: 10, scale: 6, default: 0
      add :duration_ms, :integer
      add :input_summary, :text
      add :output_summary, :text
      add :error, :map
      add :metadata, :map, default: %{}
      add :workflow_run_id, references(:command_workflow_runs, type: :binary_id), null: false
      add :agent_instance_id, references(:command_agent_instances, type: :binary_id)

      timestamps()
    end

    create index(:command_agent_executions, [:workflow_run_id])
    create index(:command_agent_executions, [:agent_instance_id])
    create index(:command_agent_executions, [:agent_name])
  end
end
```

---

## 4. Configuration

### 4.1 Command Configuration

```elixir
# config/config.exs

config :command, Command.Orchestration,
  enabled: true,
  signal_bridge: true,
  default_workflow_timeout: :timer.minutes(30),
  max_concurrent_workflows: 100,
  stale_workflow_timeout: :timer.minutes(60)

# Synapse integration
config :synapse,
  repo: Command.Repo,  # Share repo with Command
  signal_router: Synapse.SignalRouter,
  agent_supervisor: Synapse.AgentSupervisor,
  workflow_persistence: Synapse.WorkflowPersistence

# Signal bridges
config :synapse, :bridges, [
  {Synapse.Bridges.PhoenixPubSub, %{pubsub: Command.PubSub}},
  {Synapse.Bridges.HTTPGateway, %{
    webhook_url: System.get_env("SYNAPSE_WEBHOOK_URL"),
    webhook_secret: System.get_env("SYNAPSE_WEBHOOK_SECRET")
  }}
]

# Agent defaults
config :synapse, :agent_defaults,
  model_provider: "anthropic",
  model_name: "claude-sonnet-4-20250514",
  max_concurrent: 10,
  rate_limit_rpm: 60
```

### 4.2 Phoenix Router Configuration

```elixir
# lib/command_web/router.ex

defmodule CommandWeb.Router do
  use CommandWeb, :router

  # ... existing pipelines ...

  # Synapse signal webhook endpoint
  scope "/api/synapse" do
    pipe_through :api

    forward "/signals", Synapse.Bridges.HTTPGateway.Plug
  end
end
```

---

## 5. API Examples

### 5.1 Creating and Running Agent Workflows

```elixir
# Create agent instances from templates
{:ok, researcher} = Command.Orchestration.create_agent_instance(
  researcher_agent_id,
  name: "research-specialist-1",
  subscriptions: ["research_request", "clarification_request"],
  budget: Decimal.new("10.00")
)

{:ok, writer} = Command.Orchestration.create_agent_instance(
  writer_agent_id,
  name: "content-writer-1",
  subscriptions: ["write_request", "edit_request"]
)

# Start agents
{:ok, _} = Command.Orchestration.start_agent_instance(researcher.id)
{:ok, _} = Command.Orchestration.start_agent_instance(writer.id)

# Run a workflow
{:ok, run} = Command.Orchestration.run_workflow(
  MyApp.Workflows.ContentCreation,
  session_id: session_id,
  user_id: user_id,
  input: %{
    topic: "AI Agent Orchestration",
    style: "technical blog post"
  }
)

# Check status
status = Command.Orchestration.get_workflow_status(run.id)
# => %{status: :running, agent_executions: [...], total_cost: #Decimal<0.0456>}

# Resume if waiting
{:ok, run} = Command.Orchestration.resume_workflow(run.id, %{
  user_feedback: "Focus more on practical examples"
})
```

### 5.2 LiveView Integration

```elixir
defmodule CommandWeb.WorkflowLive do
  use CommandWeb, :live_view

  import CommandWeb.OrchestrationHelpers

  def mount(%{"id" => workflow_id}, _session, socket) do
    socket =
      socket
      |> subscribe_to_workflow(workflow_id)
      |> assign(:signals, [])
      |> assign(:workflow_status, :loading)

    # Load initial status
    status = Command.Orchestration.get_workflow_status(workflow_id)

    {:ok, assign(socket, :workflow, status)}
  end

  def handle_info({:synapse_signal, signal}, socket) do
    socket =
      socket
      |> handle_synapse_signal(signal)
      |> update(:signals, fn signals -> [signal | signals] end)

    {:noreply, socket}
  end

  def handle_event("send_input", %{"input" => input}, socket) do
    socket = send_to_workflow(socket, %{user_message: input})
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="workflow-container">
      <h2>Workflow Status: <%= @workflow_status %></h2>

      <div class="signals">
        <%= for signal <- @signals do %>
          <div class="signal">
            <span class="type"><%= signal.type %></span>
            <span class="source"><%= signal.source %></span>
            <p><%= inspect(signal.payload) %></p>
          </div>
        <% end %>
      </div>

      <form phx-submit="send_input">
        <input type="text" name="input" placeholder="Send message..." />
        <button type="submit">Send</button>
      </form>
    </div>
    """
  end
end
```

### 5.3 Custom Workflow Definition

```elixir
defmodule MyApp.Workflows.ContentCreation do
  @moduledoc """
  Multi-agent content creation workflow.
  """

  use Synapse.Workflow

  alias Synapse.{Signal, SignalRouter}

  def run(initial_signal, opts) do
    # Phase 1: Research
    research_signal = Signal.derive(initial_signal, :research_request, %{
      topic: initial_signal.payload.topic,
      depth: :comprehensive
    }, target: "research-specialist")

    SignalRouter.emit(research_signal)

    # Wait for research response
    {:ok, research_result} = await_signal(:research_complete,
      timeout: :timer.minutes(5)
    )

    # Phase 2: Writing
    write_signal = Signal.derive(initial_signal, :write_request, %{
      topic: initial_signal.payload.topic,
      research: research_result.payload,
      style: initial_signal.payload.style
    }, target: "content-writer")

    SignalRouter.emit(write_signal)

    # Wait for draft
    {:ok, draft} = await_signal(:draft_complete,
      timeout: :timer.minutes(10)
    )

    # Phase 3: User review
    emit_signal(:workflow_waiting, %{
      type: :user_review,
      draft: draft.payload.content,
      message: "Please review the draft and provide feedback"
    })

    case await_signal(:user_input, timeout: :timer.hours(24)) do
      {:ok, %{payload: %{approved: true}}} ->
        {:ok, %{content: draft.payload.content, status: :approved}}

      {:ok, %{payload: %{feedback: feedback}}} ->
        # Revision loop
        revision_signal = Signal.derive(initial_signal, :revision_request, %{
          draft: draft.payload.content,
          feedback: feedback
        }, target: "content-writer")

        SignalRouter.emit(revision_signal)

        {:ok, revision} = await_signal(:revision_complete)
        {:ok, %{content: revision.payload.content, status: :revised}}

      {:error, :timeout} ->
        {:error, :user_review_timeout}
    end
  end
end
```

---

## 6. Integration Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              Command.Orchestration                                   │
│                                                                                     │
│  1. create_agent_instance(agent_id)                                                 │
│     ├── Load Command.Agents.Agent template                                          │
│     ├── Create Synapse.AgentConfig in database                                      │
│     └── Store Command.Orchestration.AgentInstance                                   │
│                                                                                     │
│  2. start_agent_instance(instance_id)                                               │
│     ├── Synapse.AgentSupervisor.start_agent(config_id)                             │
│     │   └── Spawns GenServer process from config                                    │
│     └── Update instance status to :running                                          │
│                                                                                     │
│  3. run_workflow(workflow_module, opts)                                             │
│     ├── Create Command.Orchestration.WorkflowRun                                    │
│     ├── Create/Resume Synapse.WorkflowPersistence state                             │
│     ├── Attach telemetry handlers                                                   │
│     ├── Build initial signal with Command context                                   │
│     │   ├── command_session_id                                                      │
│     │   ├── command_workflow_id                                                     │
│     │   └── command_user_id                                                         │
│     │                                                                               │
│     ├── workflow_module.run(signal, opts)                                           │
│     │   │                                                                           │
│     │   ▼                                                                           │
│     │   ┌─────────────────────────────────────────────────────────────────────┐    │
│     │   │                    Synapse Workflow Execution                        │    │
│     │   │                                                                     │    │
│     │   │  ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐  │    │
│     │   │  │  Emit    │ ──▶ │  Signal  │ ──▶ │  Agent   │ ──▶ │  Emit    │  │    │
│     │   │  │  Signal  │     │  Router  │     │ Process  │     │ Response │  │    │
│     │   │  └──────────┘     └──────────┘     └──────────┘     └──────────┘  │    │
│     │   │       │                │                │                │        │    │
│     │   │       ▼                ▼                ▼                ▼        │    │
│     │   │   PubSub           Route to          AI Call          Telemetry   │    │
│     │   │   Bridge          Subscribers        + Cost           Emission    │    │
│     │   │       │                                                  │        │    │
│     │   │       ▼                                                  ▼        │    │
│     │   │   LiveView                                         Command        │    │
│     │   │   Update                                          Cost Record     │    │
│     │   └─────────────────────────────────────────────────────────────────────┘    │
│     │                         │                                                     │
│     │                         ▼                                                     │
│     ├── Telemetry handlers record:                                                  │
│     │   └── Command.Orchestration.AgentExecution (per agent call)                  │
│     │                                                                               │
│     └── Finalize run (store output, update status)                                 │
└─────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────┐
│                           Phoenix LiveView Integration                               │
│                                                                                     │
│  ┌─────────────┐     ┌──────────────────┐     ┌─────────────────────────────────┐ │
│  │   LiveView  │ ──▶ │  SignalBridge    │ ──▶ │     Synapse.SignalRouter       │ │
│  │  Component  │     │  (PubSub sub)    │     │                                 │ │
│  └─────────────┘     └──────────────────┘     └─────────────────────────────────┘ │
│        │                     │                              │                       │
│        │                     │                              │                       │
│        │◀────────────────────┤                              │                       │
│        │   {:synapse_signal, signal}                        │                       │
│        │                                                    │                       │
│        ├───────────────────────────────────────────────────▶│                       │
│        │              send_to_workflow(input)               │                       │
│                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 7. Summary of Required Changes

### 7.1 Synapse Library Changes

| Change | File | Description |
|--------|------|-------------|
| Signal extension | `signal.ex` | Add Command correlation fields |
| Signal Router bridge | `signal_router.ex` | External bridge support |
| Phoenix PubSub bridge | `bridges/phoenix_pubsub.ex` | New module for PubSub integration |
| HTTP Gateway | `bridges/http_gateway.ex` | New module for external signals |
| Agent Config schema | `agent_config.ex` | Persistent agent configuration |
| Agent Supervisor | `agent_supervisor.ex` | Dynamic agent lifecycle |
| Workflow Persistence | `workflow_persistence.ex` | Database-backed state |
| Telemetry | `telemetry.ex` | Cost tracking events |
| AI Integration | `agents/*.ex` | Use `Altar.AI.Integrations.Synapse` for LLM calls |
| Database migration | `migrations/` | New tables for persistence |

**Note**: Synapse agents use the unified Altar.AI layer for all LLM interactions. The former `Synapse.ReqLLM` module is replaced by `Altar.AI.Integrations.Synapse` which provides the same interface with centralized configuration, telemetry, and cost tracking. See `07_ai_layer_consolidation.md` for details.

### 7.2 Command Library Changes

| Change | File | Description |
|--------|------|-------------|
| Orchestration context | `orchestration.ex` | Main integration module |
| AgentInstance schema | `orchestration/agent_instance.ex` | Instance tracking |
| WorkflowRun schema | `orchestration/workflow_run.ex` | Run tracking |
| AgentExecution schema | `orchestration/agent_execution.ex` | Cost tracking |
| SignalBridge | `orchestration/signal_bridge.ex` | PubSub bridge |
| LiveView helpers | `orchestration_helpers.ex` | UI integration |
| Database migration | `migrations/` | Orchestration tables |

---

## 8. Testing Strategy

All tests use **Supertester** (v0.5.0) for deterministic, zero-sleep testing with proper isolation.

### 8.1 Integration Tests

```elixir
defmodule Command.OrchestrationTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.{OTPHelpers, GenServerHelpers, Assertions}

  alias Command.Orchestration

  describe "agent instances" do
    test "creates and starts agent instance" do
      agent = insert(:agent, type: :specialist)

      {:ok, instance} = Orchestration.create_agent_instance(agent.id)
      assert instance.status == :created

      {:ok, instance} = Orchestration.start_agent_instance(instance.id)
      assert instance.status == :running

      # Verify agent GenServer is responsive
      assert_genserver_responsive(instance.pid)
    end

    test "stops agent instance cleanly" do
      agent = insert(:agent, type: :specialist)
      {:ok, instance} = Orchestration.create_agent_instance(agent.id)
      {:ok, instance} = Orchestration.start_agent_instance(instance.id)

      pid = instance.pid
      assert_process_alive(pid)

      {:ok, stopped_instance} = Orchestration.stop_agent_instance(instance.id)
      assert stopped_instance.status == :stopped
      assert_process_dead(pid)
    end
  end

  describe "workflow execution" do
    test "runs workflow with tracking" do
      session = insert(:session)
      user = insert(:user)

      {:ok, run} = Orchestration.run_workflow(
        TestWorkflow,
        session_id: session.id,
        user_id: user.id,
        input: %{test: true}
      )

      assert run.status in [:completed, :waiting]

      status = Orchestration.get_workflow_status(run.id)
      assert status.total_cost >= Decimal.new(0)
    end
  end
end
```

### 8.2 Signal Bridge Tests

Using Supertester's message harness for deterministic signal testing:

```elixir
defmodule Command.Orchestration.SignalBridgeTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.{OTPHelpers, Assertions}

  alias Command.Orchestration.SignalBridge
  alias Synapse.SignalRouter

  test "forwards signals to PubSub" do
    workflow_id = Ecto.UUID.generate()

    SignalBridge.subscribe_workflow(workflow_id)

    signal = %Synapse.Signal{
      id: Ecto.UUID.generate(),
      type: :test_signal,
      payload: %{data: "test"},
      command_workflow_id: workflow_id,
      timestamp: DateTime.utc_now()
    }

    SignalRouter.emit(signal)

    # Deterministic receive assertion (no arbitrary timeout guessing)
    assert_receive {:synapse_signal, ^signal}, 1000
  end

  test "isolates signals by workflow_id" do
    workflow_1 = Ecto.UUID.generate()
    workflow_2 = Ecto.UUID.generate()

    SignalBridge.subscribe_workflow(workflow_1)
    # Note: NOT subscribed to workflow_2

    signal_1 = %Synapse.Signal{
      id: Ecto.UUID.generate(),
      type: :test_signal,
      payload: %{data: "for_workflow_1"},
      command_workflow_id: workflow_1,
      timestamp: DateTime.utc_now()
    }

    signal_2 = %Synapse.Signal{
      id: Ecto.UUID.generate(),
      type: :test_signal,
      payload: %{data: "for_workflow_2"},
      command_workflow_id: workflow_2,
      timestamp: DateTime.utc_now()
    }

    SignalRouter.emit(signal_1)
    SignalRouter.emit(signal_2)

    # Should receive signal_1
    assert_receive {:synapse_signal, ^signal_1}, 1000

    # Should NOT receive signal_2 (different workflow)
    refute_receive {:synapse_signal, ^signal_2}, 100
  end
end
```

### 8.3 Agent GenServer Tests

Using Supertester for deterministic GenServer testing:

```elixir
defmodule Command.Orchestration.AgentTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.{OTPHelpers, GenServerHelpers, Assertions}

  alias Synapse.Agents.Specialist

  describe "agent signal handling" do
    test "processes signals deterministically" do
      {:ok, agent} = setup_isolated_genserver(Specialist, "test_agent", [
        name: "test-specialist",
        system_prompt: "You are a test agent",
        subscriptions: [:test_request]
      ])

      # Use cast_and_sync for deterministic async testing
      :ok = cast_and_sync(agent, {:handle_signal, test_signal()})

      # Assert state after signal processed (no Process.sleep!)
      assert_genserver_state(agent, fn state ->
        length(state.processed_signals) == 1
      end)
    end

    test "handles concurrent signals" do
      {:ok, agent} = setup_isolated_genserver(Specialist, "concurrent_test")

      # Stress test with concurrent signal handling
      signals = for i <- 1..10, do: {:handle_signal, test_signal(i)}

      {:ok, results} = concurrent_calls(agent, signals, 5, timeout: 5000)

      # Verify all signals processed
      for %{successes: successes, errors: errors} <- results do
        assert length(errors) == 0
      end

      assert_genserver_responsive(agent)
    end

    test "recovers from crashes" do
      {:ok, agent} = setup_isolated_genserver(Specialist, "crash_test")

      {:ok, info} = test_server_crash_recovery(agent, :simulated_crash)

      assert info.recovered == true
      assert_process_alive(info.new_pid)
    end
  end

  defp test_signal(id \\ 1) do
    %Synapse.Signal{
      id: Ecto.UUID.generate(),
      type: :test_request,
      payload: %{request_id: id},
      timestamp: DateTime.utc_now()
    }
  end
end
```

### 8.4 Telemetry Tests

Using Supertester's `TelemetryHelpers` for isolated, deterministic telemetry testing:

```elixir
defmodule Command.Orchestration.TelemetryTest do
  use Supertester.ExUnitFoundation,
    isolation: :full_isolation,
    telemetry_isolation: true

  import Supertester.Assertions

  alias Command.Orchestration

  @tag telemetry_events: [[:synapse, :agent, :execution]]
  test "records agent executions from telemetry" do
    # Attach isolated handler
    {:ok, _handler} = Supertester.TelemetryHelpers.attach_isolated(
      [:synapse, :agent, :execution],
      buffer: true
    )

    session = insert(:session)
    {:ok, run} = Orchestration.run_workflow(TestWorkflow,
      session_id: session.id,
      input: %{test: true}
    )

    # Emit telemetry event with test context
    Supertester.TelemetryHelpers.emit_with_context(
      [:synapse, :agent, :execution],
      %{
        duration: 500_000_000,
        tokens_in: 150,
        tokens_out: 300,
        cost_usd: 0.002
      },
      %{
        agent_name: "test-specialist",
        command_workflow_id: run.id,
        status: :ok
      }
    )

    # Assert telemetry was received (no Process.sleep!)
    assert Supertester.TelemetryHelpers.assert_telemetry(
      [:synapse, :agent, :execution],
      fn _measurements, metadata ->
        metadata.command_workflow_id == run.id
      end
    )

    # Verify cost was recorded
    cost = Orchestration.calculate_workflow_cost(run.id)
    assert Decimal.compare(cost, Decimal.new("0.002")) == :eq
  end
end
```

### 8.5 Chaos Engineering Tests

```elixir
defmodule Command.Orchestration.ChaosTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.{OTPHelpers, ChaosHelpers, SupervisorHelpers, Assertions}

  describe "orchestration system resilience" do
    test "survives random agent crashes" do
      {:ok, supervisor} = setup_isolated_supervisor(Synapse.AgentSupervisor)

      # Start multiple agents
      for i <- 1..5 do
        Synapse.AgentSupervisor.start_agent(%{
          name: "agent-#{i}",
          type: :specialist
        })
      end

      # Kill 50% of agents over 3 seconds
      report = chaos_kill_children(supervisor,
        kill_rate: 0.5,
        duration_ms: 3000,
        kill_interval_ms: 200
      )

      # Verify system recovered
      assert Process.alive?(supervisor)
      assert report.supervisor_crashed == false

      # Wait for stabilization
      :ok = wait_for_supervisor_stabilization(supervisor)
      assert_all_children_alive(supervisor)
    end

    test "maintains signal routing under chaos" do
      {:ok, supervisor} = setup_isolated_supervisor(Synapse.AgentSupervisor)

      # Run chaos with concurrent signal workload
      scenarios = [
        %{type: :kill_children, kill_rate: 0.3, duration_ms: 2000},
        %{
          type: :concurrent,
          build: fn _sup ->
            Supertester.ConcurrentHarness.simple_genserver_scenario(
              Synapse.SignalRouter,
              [{:cast, {:emit, test_signal()}}, {:call, :get_stats}],
              4,
              invariant: fn router, _ctx ->
                {:ok, state} = Supertester.GenServerHelpers.get_server_state_safely(router)
                assert is_map(state.subscriptions)
              end
            )
          end
        }
      ]

      report = run_chaos_suite(supervisor, scenarios, timeout: 10_000)

      assert report.failed == 0
    end
  end

  defp test_signal do
    %Synapse.Signal{
      id: Ecto.UUID.generate(),
      type: :chaos_test,
      payload: %{test: true},
      timestamp: DateTime.utc_now()
    }
  end
end
```

### 8.6 Performance Tests

```elixir
defmodule Command.Orchestration.PerformanceTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.{OTPHelpers, PerformanceHelpers}

  describe "signal routing performance" do
    test "signal emission meets latency SLA" do
      {:ok, router} = setup_isolated_genserver(Synapse.SignalRouter)

      signal = %Synapse.Signal{
        id: Ecto.UUID.generate(),
        type: :perf_test,
        payload: %{data: "test"},
        timestamp: DateTime.utc_now()
      }

      assert_performance(
        fn -> GenServer.call(router, {:emit_sync, signal}) end,
        max_time_ms: 10,
        max_memory_bytes: 100_000
      )
    end

    test "no memory leak in signal processing" do
      {:ok, router} = setup_isolated_genserver(Synapse.SignalRouter)

      assert_no_memory_leak(10_000, fn ->
        signal = %Synapse.Signal{
          id: Ecto.UUID.generate(),
          type: :leak_test,
          payload: %{data: :crypto.strong_rand_bytes(100)},
          timestamp: DateTime.utc_now()
        }
        GenServer.cast(router, {:emit, signal})
      end, threshold: 0.1)
    end

    test "router mailbox stable under load" do
      {:ok, router} = setup_isolated_genserver(Synapse.SignalRouter)

      assert_mailbox_stable(router,
        during: fn ->
          for _ <- 1..1000 do
            signal = %Synapse.Signal{
              id: Ecto.UUID.generate(),
              type: :load_test,
              payload: %{},
              timestamp: DateTime.utc_now()
            }
            GenServer.cast(router, {:emit, signal})
          end
        end,
        max_size: 100
      )
    end
  end

  describe "workflow execution performance" do
    test "workflow startup meets SLA" do
      assert_performance(
        fn ->
          Command.Orchestration.run_workflow(SimpleTestWorkflow,
            input: %{test: true}
          )
        end,
        max_time_ms: 500,
        max_memory_bytes: 5_000_000
      )
    end
  end
end
```

### 8.7 Concurrent Harness Tests

Using Supertester's ConcurrentHarness for complex multi-agent scenarios:

```elixir
defmodule Command.Orchestration.ConcurrentTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.{OTPHelpers, Assertions}

  describe "multi-agent coordination" do
    test "orchestrator coordinates multiple specialists" do
      scenario = Supertester.ConcurrentHarness.simple_genserver_scenario(
        Synapse.Agents.Orchestrator,
        [
          {:cast, {:delegate_task, :research, %{topic: "test"}}},
          {:cast, {:delegate_task, :write, %{content: "test"}}},
          {:call, :get_task_status}
        ],
        3,
        mailbox: [sampling_interval: 5],
        performance_expectations: [max_time_ms: 5000],
        invariant: fn orchestrator, _ctx ->
          {:ok, state} = Supertester.GenServerHelpers.get_server_state_safely(orchestrator)
          # Verify no tasks stuck in pending forever
          pending_count = Enum.count(state.tasks, fn {_id, t} -> t.status == :pending end)
          assert pending_count < 10
        end
      )

      assert {:ok, report} = Supertester.ConcurrentHarness.run(scenario)
      assert report.metrics.total_operations > 0
    end

    test "signal routing under concurrent load" do
      scenario = Supertester.ConcurrentHarness.simple_genserver_scenario(
        Synapse.SignalRouter,
        [
          {:cast, {:emit, build_signal(:type_a)}},
          {:cast, {:emit, build_signal(:type_b)}},
          {:call, :get_subscription_count}
        ],
        8,  # 8 concurrent threads
        chaos: Supertester.ConcurrentHarness.chaos_inject_crash({:random, 0.1}),
        performance_expectations: [max_time_ms: 2000],
        metadata: %{test: "concurrent_routing"}
      )

      assert {:ok, report} = Supertester.ConcurrentHarness.run(scenario)

      # Verify chaos report
      assert report.chaos.injected_crashes >= 0
    end
  end

  defp build_signal(type) do
    %Synapse.Signal{
      id: Ecto.UUID.generate(),
      type: type,
      payload: %{generated_at: System.monotonic_time()},
      timestamp: DateTime.utc_now()
    }
  end
end
```
