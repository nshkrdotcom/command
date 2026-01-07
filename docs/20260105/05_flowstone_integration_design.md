# FlowStone Integration Design

**Date**: 2026-01-05
**Version**: 1.0.0

## Overview

This document details the integration design between Command and FlowStone, including required enhancements to both libraries and the complete implementation specification.

---

## 1. FlowStone Library Enhancements Required

### 1.1 Context Extension for Command Correlation

**Current State** (`flowstone/lib/flowstone/context.ex`):
```elixir
defstruct [
  :asset,
  :partition,
  :run_id,
  :resources,
  :metadata,
  :started_at,
  :scatter_key,
  :batch_index,
  :batch_count,
  :batch_items,
  :batch_input
]
```

**Required Enhancement**:
```elixir
# flowstone/lib/flowstone/context.ex
defstruct [
  :asset,
  :partition,
  :run_id,
  :resources,
  :metadata,
  :started_at,
  :scatter_key,
  :batch_index,
  :batch_count,
  :batch_items,
  :batch_input,
  # NEW: Command integration fields
  :command_session_id,      # UUID linking to Command session
  :command_workflow_id,     # UUID linking to Command workflow instance
  :command_user_id,         # UUID of executing user
  :correlation_id           # External correlation ID for tracing
]

@type t :: %__MODULE__{
  # ... existing types ...
  command_session_id: Ecto.UUID.t() | nil,
  command_workflow_id: Ecto.UUID.t() | nil,
  command_user_id: Ecto.UUID.t() | nil,
  correlation_id: String.t() | nil
}
```

**Migration Required** (`flowstone/priv/repo/migrations/XXXXXX_add_command_correlation.exs`):
```elixir
defmodule FlowStone.Repo.Migrations.AddCommandCorrelation do
  use Ecto.Migration

  def change do
    alter table(:flowstone_materializations) do
      add :command_session_id, :uuid
      add :command_workflow_id, :uuid
      add :command_user_id, :uuid
      add :correlation_id, :string
    end

    create index(:flowstone_materializations, [:command_session_id])
    create index(:flowstone_materializations, [:command_workflow_id])
    create index(:flowstone_materializations, [:command_user_id])
    create index(:flowstone_materializations, [:correlation_id])
  end
end
```

### 1.2 Enhanced Telemetry for Cost Tracking

**Current State**: Telemetry emits `duration` and `size_bytes` but no AI-specific metrics.

**Required Enhancement** (`flowstone/lib/flowstone/telemetry.ex`):
```elixir
defmodule FlowStone.Telemetry do
  # Add new event types
  @ai_events [
    [:flowstone, :ai, :generate, :start],
    [:flowstone, :ai, :generate, :stop],
    [:flowstone, :ai, :generate, :exception],
    [:flowstone, :ai, :embed, :start],
    [:flowstone, :ai, :embed, :stop],
    [:flowstone, :ai, :embed, :exception],
    [:flowstone, :ai, :classify, :start],
    [:flowstone, :ai, :classify, :stop],
    [:flowstone, :ai, :classify, :exception]
  ]

  @doc """
  Emit AI operation telemetry with cost-tracking metadata.
  """
  def emit_ai_operation(operation, measurements, metadata) do
    :telemetry.execute(
      [:flowstone, :ai, operation, :stop],
      Map.merge(measurements, %{
        duration: measurements[:duration] || 0,
        tokens_in: measurements[:tokens_in] || 0,
        tokens_out: measurements[:tokens_out] || 0,
        cost_usd: measurements[:cost_usd] || 0.0
      }),
      Map.merge(metadata, %{
        provider: metadata[:provider],
        model: metadata[:model],
        run_id: metadata[:run_id],
        asset: metadata[:asset],
        command_session_id: metadata[:command_session_id],
        command_workflow_id: metadata[:command_workflow_id]
      })
    )
  end
end
```

### 1.3 Approval Webhook Integration

**Current State**: `Checkpoint.Notifier` is sync-only callback.

**Required Enhancement** (`flowstone/lib/flowstone/checkpoint/webhook_notifier.ex`):
```elixir
defmodule FlowStone.Checkpoint.WebhookNotifier do
  @moduledoc """
  Webhook-based approval notifier for external system integration.
  """
  @behaviour FlowStone.Checkpoint.Notifier

  alias FlowStone.SignalGate.Token

  @impl true
  def notify(event, %{approval: approval}) do
    case event do
      :requested ->
        # Generate signed callback token
        {:ok, token} = Token.generate(%{
          approval_id: approval.id,
          type: :approval_callback
        })

        callback_url = build_callback_url(token)

        # Dispatch async notification
        dispatch_webhook(approval, callback_url)

      :approved ->
        notify_decision(approval, :approved)

      :rejected ->
        notify_decision(approval, :rejected)

      :timeout ->
        notify_decision(approval, :timeout)
    end

    :ok
  end

  defp build_callback_url(token) do
    base_url = Application.get_env(:flowstone, :webhook_base_url, "http://localhost:4000")
    "#{base_url}/api/flowstone/approvals/callback?token=#{token}"
  end

  defp dispatch_webhook(approval, callback_url) do
    # Use Oban for reliable delivery
    %{
      approval_id: approval.id,
      checkpoint_name: approval.checkpoint_name,
      message: approval.message,
      context: approval.context,
      callback_url: callback_url,
      timeout_at: approval.timeout_at
    }
    |> FlowStone.Workers.ApprovalNotification.new()
    |> Oban.insert()
  end
end
```

**New Oban Worker** (`flowstone/lib/flowstone/workers/approval_notification.ex`):
```elixir
defmodule FlowStone.Workers.ApprovalNotification do
  use Oban.Worker,
    queue: :notifications,
    max_attempts: 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{
      "approval_id" => approval_id,
      "callback_url" => callback_url
    } = args

    webhook_url = get_webhook_url()

    case Req.post(webhook_url, json: %{
      type: "approval_requested",
      approval_id: approval_id,
      callback_url: callback_url,
      context: args["context"],
      message: args["message"]
    }) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_webhook_url do
    Application.get_env(:flowstone, :approval_webhook_url)
  end
end
```

### 1.4 External Run Configuration

**Current State**: `FlowStone.RunConfig` is ETS-based node-local.

**Required Enhancement**: Support external configuration injection.

```elixir
# flowstone/lib/flowstone/run_config.ex additions
defmodule FlowStone.RunConfig do
  # ... existing code ...

  @doc """
  Store run configuration with Command correlation.
  """
  def store_with_command(run_id, config, command_opts) do
    extended_config = Map.merge(config, %{
      command_session_id: command_opts[:session_id],
      command_workflow_id: command_opts[:workflow_id],
      command_user_id: command_opts[:user_id],
      stored_at: DateTime.utc_now()
    })

    :ets.insert(@table, {run_id, extended_config})
    :ok
  end

  @doc """
  Retrieve Command correlation for a run.
  """
  def get_command_context(run_id) do
    case :ets.lookup(@table, run_id) do
      [{^run_id, config}] ->
        {:ok, %{
          session_id: config[:command_session_id],
          workflow_id: config[:command_workflow_id],
          user_id: config[:command_user_id]
        }}

      [] ->
        {:error, :not_found}
    end
  end
end
```

---

## 2. Command Integration Modules

### 2.1 Command.Pipelines Context

**File**: `command/lib/command/pipelines.ex`

```elixir
defmodule Command.Pipelines do
  @moduledoc """
  Pipeline orchestration context integrating FlowStone.

  Provides:
  - Pipeline creation from workflow templates
  - Execution with Command session/cost tracking
  - Approval integration
  - Artifact storage
  """

  alias Command.{Repo, Workflows, Sessions, Costs, Artifacts, Approvals}
  alias Command.Pipelines.{Pipeline, PipelineRun, AIOperation}
  alias FlowStone

  import Ecto.Query

  # ============================================
  # Pipeline Management
  # ============================================

  @doc """
  Create a pipeline from a workflow template.
  """
  def create_pipeline(template_id, opts \\ []) do
    template = Workflows.get_template!(template_id)

    attrs = %{
      template_id: template_id,
      name: opts[:name] || template.name,
      description: opts[:description] || template.description,
      config: build_pipeline_config(template, opts),
      status: :active
    }

    %Pipeline{}
    |> Pipeline.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Get pipeline with stats.
  """
  def get_pipeline!(id) do
    Pipeline
    |> Repo.get!(id)
    |> Repo.preload(:template)
  end

  @doc """
  List pipelines with optional filters.
  """
  def list_pipelines(opts \\ []) do
    Pipeline
    |> filter_by_status(opts[:status])
    |> filter_by_template(opts[:template_id])
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
  end

  # ============================================
  # Pipeline Execution
  # ============================================

  @doc """
  Execute a pipeline with full Command tracking.

  Options:
  - :session_id - Command session to associate
  - :user_id - Executing user
  - :partition - FlowStone partition (e.g., date)
  - :force - Force re-execution even if cached
  - :async - Run asynchronously via Oban
  """
  def run(pipeline_id, opts \\ []) do
    pipeline = get_pipeline!(pipeline_id)
    partition = opts[:partition] || Date.utc_today()

    # Create run record
    {:ok, run} = create_run(pipeline, partition, opts)

    # Attach telemetry handlers for this run
    handler_id = attach_run_telemetry(run.id)

    try do
      # Build FlowStone execution options
      flowstone_opts = build_flowstone_opts(run, opts)

      # Execute pipeline
      result = execute_pipeline(pipeline, partition, flowstone_opts)

      # Handle result
      finalize_run(run, result)
    after
      detach_run_telemetry(handler_id)
    end
  end

  @doc """
  Execute pipeline asynchronously via Oban.
  """
  def run_async(pipeline_id, opts \\ []) do
    %{
      pipeline_id: pipeline_id,
      opts: Map.new(opts)
    }
    |> Command.Pipelines.Workers.ExecutePipeline.new()
    |> Oban.insert()
  end

  @doc """
  Get status of a pipeline run.
  """
  def get_run_status(run_id) do
    run = Repo.get!(PipelineRun, run_id)

    %{
      id: run.id,
      status: run.status,
      started_at: run.started_at,
      completed_at: run.completed_at,
      duration_ms: calculate_duration(run),
      error: run.error,
      materializations: list_run_materializations(run),
      ai_operations: list_run_ai_operations(run),
      total_cost: calculate_run_cost(run)
    }
  end

  # ============================================
  # Cost Tracking
  # ============================================

  @doc """
  Record an AI operation from FlowStone telemetry.
  """
  def record_ai_operation(attrs) do
    %AIOperation{}
    |> AIOperation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Get total cost for a pipeline run.
  """
  def calculate_run_cost(run_or_id) do
    run_id = if is_struct(run_or_id), do: run_or_id.id, else: run_or_id

    AIOperation
    |> where([o], o.pipeline_run_id == ^run_id)
    |> select([o], sum(o.cost_usd))
    |> Repo.one() || Decimal.new(0)
  end

  # ============================================
  # Private Functions
  # ============================================

  defp create_run(pipeline, partition, opts) do
    attrs = %{
      pipeline_id: pipeline.id,
      session_id: opts[:session_id],
      user_id: opts[:user_id],
      partition: serialize_partition(partition),
      status: :pending,
      started_at: DateTime.utc_now()
    }

    %PipelineRun{}
    |> PipelineRun.changeset(attrs)
    |> Repo.insert()
  end

  defp build_flowstone_opts(run, opts) do
    [
      run_id: Ecto.UUID.generate(),
      command_session_id: run.session_id,
      command_workflow_id: run.id,
      command_user_id: run.user_id,
      force: opts[:force] || false,
      io: [repo: FlowStone.Repo],
      resources: build_resources(run, opts)
    ]
  end

  defp build_resources(run, opts) do
    base_resources = %{
      command_context: {Command.Pipelines.Resources.CommandContext, %{
        run_id: run.id,
        session_id: run.session_id,
        user_id: run.user_id
      }}
    }

    # Add AI resource if configured
    # See 07_ai_layer_consolidation.md for unified Altar.AI architecture
    if opts[:ai_enabled] != false do
      Map.put(base_resources, :ai, {Altar.AI.Integrations.FlowStone, %{
        adapter: Altar.AI.Adapters.Composite
      }})
    else
      base_resources
    end
  end

  defp execute_pipeline(pipeline, partition, opts) do
    # Load pipeline module dynamically
    module = load_pipeline_module(pipeline)

    # Get final asset from template
    final_asset = pipeline.config["final_asset"] || :output

    # Execute via FlowStone
    FlowStone.run(module, final_asset, Keyword.put(opts, :partition, partition))
  end

  defp finalize_run(run, result) do
    case result do
      {:ok, data} ->
        # Store artifact if configured
        artifact_id = maybe_store_artifact(run, data)

        # Update run status
        run
        |> PipelineRun.changeset(%{
          status: :completed,
          completed_at: DateTime.utc_now(),
          result: %{artifact_id: artifact_id}
        })
        |> Repo.update()

      {:error, %FlowStone.Error{} = error} ->
        run
        |> PipelineRun.changeset(%{
          status: :failed,
          completed_at: DateTime.utc_now(),
          error: %{
            type: error.type,
            message: error.message,
            asset: error.metadata[:asset]
          }
        })
        |> Repo.update()

      {:error, reason} ->
        run
        |> PipelineRun.changeset(%{
          status: :failed,
          completed_at: DateTime.utc_now(),
          error: %{message: inspect(reason)}
        })
        |> Repo.update()
    end
  end

  defp attach_run_telemetry(run_id) do
    handler_id = "command-pipeline-#{run_id}"

    # AI operation tracking
    :telemetry.attach(
      "#{handler_id}-ai",
      [:flowstone, :ai, :generate, :stop],
      fn _event, measurements, metadata, _config ->
        if metadata[:command_workflow_id] == run_id do
          record_ai_operation(%{
            pipeline_run_id: run_id,
            asset_name: metadata[:asset],
            operation: :generate,
            provider: metadata[:provider],
            model: metadata[:model],
            tokens_in: measurements[:tokens_in],
            tokens_out: measurements[:tokens_out],
            cost_usd: measurements[:cost_usd],
            duration_ms: div(measurements[:duration], 1_000_000)
          })
        end
      end,
      nil
    )

    # Materialization tracking
    :telemetry.attach(
      "#{handler_id}-mat",
      [:flowstone, :materialization, :stop],
      fn _event, measurements, metadata, _config ->
        if metadata[:command_workflow_id] == run_id do
          # Record materialization in Command
          record_materialization(run_id, metadata, measurements)
        end
      end,
      nil
    )

    handler_id
  end

  defp detach_run_telemetry(handler_id) do
    :telemetry.detach("#{handler_id}-ai")
    :telemetry.detach("#{handler_id}-mat")
  end
end
```

### 2.2 Pipeline Schemas

**File**: `command/lib/command/pipelines/pipeline.ex`

```elixir
defmodule Command.Pipelines.Pipeline do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "command_pipelines" do
    field :name, :string
    field :description, :string
    field :status, Ecto.Enum, values: [:active, :inactive, :archived], default: :active
    field :config, :map, default: %{}

    belongs_to :template, Command.Workflows.Template
    has_many :runs, Command.Pipelines.PipelineRun

    timestamps()
  end

  def changeset(pipeline, attrs) do
    pipeline
    |> cast(attrs, [:name, :description, :status, :config, :template_id])
    |> validate_required([:name, :template_id])
    |> foreign_key_constraint(:template_id)
  end
end
```

**File**: `command/lib/command/pipelines/pipeline_run.ex`

```elixir
defmodule Command.Pipelines.PipelineRun do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "command_pipeline_runs" do
    field :partition, :string
    field :status, Ecto.Enum,
      values: [:pending, :running, :completed, :failed, :cancelled],
      default: :pending
    field :flowstone_run_id, :string
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :result, :map
    field :error, :map

    belongs_to :pipeline, Command.Pipelines.Pipeline
    belongs_to :session, Command.Sessions.Session
    belongs_to :user, Command.Accounts.User
    has_many :ai_operations, Command.Pipelines.AIOperation

    timestamps()
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:partition, :status, :flowstone_run_id, :started_at,
                    :completed_at, :result, :error, :pipeline_id, :session_id, :user_id])
    |> validate_required([:pipeline_id, :partition])
    |> foreign_key_constraint(:pipeline_id)
  end
end
```

**File**: `command/lib/command/pipelines/ai_operation.ex`

```elixir
defmodule Command.Pipelines.AIOperation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "command_pipeline_ai_operations" do
    field :asset_name, :string
    field :operation, Ecto.Enum, values: [:generate, :embed, :classify, :code]
    field :provider, :string
    field :model, :string
    field :tokens_in, :integer, default: 0
    field :tokens_out, :integer, default: 0
    field :cost_usd, :decimal, default: 0
    field :duration_ms, :integer
    field :metadata, :map, default: %{}

    belongs_to :pipeline_run, Command.Pipelines.PipelineRun

    timestamps()
  end

  def changeset(op, attrs) do
    op
    |> cast(attrs, [:asset_name, :operation, :provider, :model, :tokens_in,
                    :tokens_out, :cost_usd, :duration_ms, :metadata, :pipeline_run_id])
    |> validate_required([:asset_name, :operation, :pipeline_run_id])
  end
end
```

### 2.3 Command Context Resource

**File**: `command/lib/command/pipelines/resources/command_context.ex`

```elixir
defmodule Command.Pipelines.Resources.CommandContext do
  @moduledoc """
  FlowStone resource providing Command context to pipeline assets.
  """
  @behaviour FlowStone.Resource

  alias Command.{Sessions, Approvals, Costs}

  defstruct [:run_id, :session_id, :user_id, :session, :approval_rules]

  @impl true
  def setup(config) do
    session = if config[:session_id] do
      Sessions.get_session(config[:session_id])
    end

    {:ok, %__MODULE__{
      run_id: config[:run_id],
      session_id: config[:session_id],
      user_id: config[:user_id],
      session: session,
      approval_rules: load_approval_rules(config)
    }}
  end

  @impl true
  def teardown(_resource), do: :ok

  @impl true
  def health_check(_resource), do: :healthy

  # Public API for use in assets

  @doc """
  Check if an operation requires approval.
  """
  def check_approval(%__MODULE__{} = ctx, operation, context \\ %{}) do
    Approvals.check(ctx.user_id, :pipeline, operation, context)
  end

  @doc """
  Request approval for an operation.
  """
  def request_approval(%__MODULE__{} = ctx, operation, message, context \\ %{}) do
    Approvals.create_request(%{
      user_id: ctx.user_id,
      resource_type: :pipeline_operation,
      resource_id: ctx.run_id,
      operation: operation,
      message: message,
      context: context
    })
  end

  @doc """
  Record a cost entry.
  """
  def record_cost(%__MODULE__{} = ctx, cost_attrs) do
    Costs.record(Map.merge(cost_attrs, %{
      session_id: ctx.session_id,
      user_id: ctx.user_id,
      source: :pipeline,
      source_id: ctx.run_id
    }))
  end

  @doc """
  Get conversation history from session.
  """
  def get_conversation_history(%__MODULE__{session: nil}), do: []
  def get_conversation_history(%__MODULE__{session: session}) do
    Sessions.get_messages(session.id, limit: 20)
  end

  defp load_approval_rules(config) do
    if config[:user_id] do
      Approvals.rules_for_user(config[:user_id], :pipeline)
    else
      []
    end
  end
end
```

### 2.4 Approval Integration

**File**: `command/lib/command/pipelines/approval_notifier.ex`

```elixir
defmodule Command.Pipelines.ApprovalNotifier do
  @moduledoc """
  FlowStone approval notifier that integrates with Command.Approvals.
  """
  @behaviour FlowStone.Checkpoint.Notifier

  alias Command.{Approvals, PubSub}

  @impl true
  def notify(:requested, %{approval: fs_approval}) do
    # Create Command approval request
    {:ok, command_approval} = Approvals.create_request(%{
      resource_type: :flowstone_checkpoint,
      resource_id: fs_approval.id,
      operation: fs_approval.checkpoint_name,
      message: fs_approval.message,
      context: Map.merge(fs_approval.context || %{}, %{
        flowstone_approval_id: fs_approval.id,
        materialization_id: fs_approval.materialization_id
      }),
      timeout_at: fs_approval.timeout_at
    })

    # Broadcast to UI
    PubSub.broadcast("approvals:pending", {:new_approval, command_approval})

    :ok
  end

  @impl true
  def notify(:approved, %{approval: fs_approval}) do
    # Update Command approval if exists
    if command_approval = find_command_approval(fs_approval.id) do
      Approvals.approve(command_approval.id, %{
        decided_by: fs_approval.decision_by,
        reason: fs_approval.reason
      })
    end

    PubSub.broadcast("approvals:#{fs_approval.id}", {:approved, fs_approval})
    :ok
  end

  @impl true
  def notify(:rejected, %{approval: fs_approval}) do
    if command_approval = find_command_approval(fs_approval.id) do
      Approvals.reject(command_approval.id, %{
        decided_by: fs_approval.decision_by,
        reason: fs_approval.reason
      })
    end

    PubSub.broadcast("approvals:#{fs_approval.id}", {:rejected, fs_approval})
    :ok
  end

  @impl true
  def notify(:timeout, %{approval: fs_approval}) do
    if command_approval = find_command_approval(fs_approval.id) do
      Approvals.expire(command_approval.id)
    end

    PubSub.broadcast("approvals:#{fs_approval.id}", {:timeout, fs_approval})
    :ok
  end

  defp find_command_approval(flowstone_approval_id) do
    Approvals.get_by_resource(:flowstone_checkpoint, flowstone_approval_id)
  end
end
```

---

## 3. Database Migrations

### 3.1 Command Pipeline Tables

**File**: `command/priv/repo/migrations/XXXXXX_create_pipeline_tables.exs`

```elixir
defmodule Command.Repo.Migrations.CreatePipelineTables do
  use Ecto.Migration

  def change do
    # Pipelines
    create table(:command_pipelines, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :status, :string, default: "active"
      add :config, :map, default: %{}
      add :template_id, references(:workflow_templates, type: :binary_id)
      timestamps()
    end

    create index(:command_pipelines, [:template_id])
    create index(:command_pipelines, [:status])

    # Pipeline Runs
    create table(:command_pipeline_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :partition, :string, null: false
      add :status, :string, default: "pending"
      add :flowstone_run_id, :string
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :result, :map
      add :error, :map
      add :pipeline_id, references(:command_pipelines, type: :binary_id), null: false
      add :session_id, references(:sessions, type: :binary_id)
      add :user_id, references(:users, type: :binary_id)
      timestamps()
    end

    create index(:command_pipeline_runs, [:pipeline_id, :status])
    create index(:command_pipeline_runs, [:session_id])
    create index(:command_pipeline_runs, [:flowstone_run_id])
    create index(:command_pipeline_runs, [:partition])

    # AI Operations (cost tracking)
    create table(:command_pipeline_ai_operations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :asset_name, :string, null: false
      add :operation, :string, null: false
      add :provider, :string
      add :model, :string
      add :tokens_in, :integer, default: 0
      add :tokens_out, :integer, default: 0
      add :cost_usd, :decimal, precision: 10, scale: 6, default: 0
      add :duration_ms, :integer
      add :metadata, :map, default: %{}
      add :pipeline_run_id, references(:command_pipeline_runs, type: :binary_id), null: false
      timestamps()
    end

    create index(:command_pipeline_ai_operations, [:pipeline_run_id])
    create index(:command_pipeline_ai_operations, [:asset_name])
    create index(:command_pipeline_ai_operations, [:provider, :model])
  end
end
```

---

## 4. Configuration

### 4.1 Command Configuration

```elixir
# config/config.exs

config :command, Command.Pipelines,
  enabled: true,
  # Uses unified Altar.AI layer (see 07_ai_layer_consolidation.md)
  default_ai_resource: Altar.AI.Integrations.FlowStone,
  approval_notifier: Command.Pipelines.ApprovalNotifier,
  artifact_storage: :database,  # or :s3
  cost_tracking: true

# FlowStone configuration for shared use
config :flowstone,
  repo: Command.Repo,  # Share repo with Command
  storage: :postgres,
  lineage: true,
  approval_notifier: Command.Pipelines.ApprovalNotifier,
  webhook_base_url: "https://app.example.com"

config :flowstone, Oban,
  repo: Command.Repo,
  queues: [
    assets: 10,
    notifications: 5,
    checkpoints: 5
  ]
```

---

## 5. API Examples

### 5.1 Creating and Running a Pipeline

```elixir
# Create pipeline from template
{:ok, pipeline} = Command.Pipelines.create_pipeline(template_id, name: "Daily ETL")

# Run synchronously
{:ok, run} = Command.Pipelines.run(pipeline.id,
  session_id: session_id,
  user_id: user_id,
  partition: ~D[2026-01-05]
)

# Run asynchronously
{:ok, job} = Command.Pipelines.run_async(pipeline.id,
  session_id: session_id,
  partition: ~D[2026-01-05]
)

# Check status
status = Command.Pipelines.get_run_status(run.id)
# => %{status: :completed, total_cost: #Decimal<0.0234>, ...}
```

### 5.2 Using Command Context in Assets

```elixir
defmodule MyApp.Pipeline do
  use FlowStone.Pipeline

  asset :analyze_data do
    requires [:command_context, :ai]

    execute fn ctx, deps ->
      # Check approval for sensitive operation
      case deps.command_context.check_approval(:analyze_pii) do
        :approved ->
          # Use unified Altar.AI layer for analysis
          {:ok, response} = Altar.AI.Integrations.FlowStone.generate(
            deps.ai,
            "Analyze this data: #{inspect(ctx.metadata.data)}",
            []
          )

          # Record cost
          deps.command_context.record_cost(%{
            provider: response.provider,
            model: response.model,
            tokens: response.tokens.total
          })

          {:ok, response.content}

        :pending ->
          {:wait_for_approval, %{
            message: "PII analysis requires approval",
            context: %{data_sample: "..."}
          }}

        :denied ->
          {:error, :approval_denied}
      end
    end
  end
end
```

---

## 6. Integration Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              Command.Pipelines                                   │
│                                                                                 │
│  1. create_pipeline(template_id)                                                │
│     ├── Load Command.Workflows.Template                                         │
│     ├── Generate FlowStone pipeline module                                      │
│     └── Store Command.Pipelines.Pipeline                                        │
│                                                                                 │
│  2. run(pipeline_id, opts)                                                      │
│     ├── Create Command.Pipelines.PipelineRun                                    │
│     ├── Attach telemetry handlers                                               │
│     ├── Build FlowStone opts with Command context                               │
│     │   ├── command_session_id                                                  │
│     │   ├── command_workflow_id                                                 │
│     │   └── resources: [command_context, ai]                                    │
│     ├── FlowStone.run(pipeline_module, :final, opts)                           │
│     │   │                                                                       │
│     │   ▼                                                                       │
│     │   ┌─────────────────────────────────────────────────────────────────┐    │
│     │   │                    FlowStone Execution                           │    │
│     │   │                                                                 │    │
│     │   │  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐     │    │
│     │   │  │ Asset 1 │ ─▶ │ Asset 2 │ ─▶ │ Asset 3 │ ─▶ │  Final  │     │    │
│     │   │  └─────────┘    └─────────┘    └─────────┘    └─────────┘     │    │
│     │   │       │              │              │              │          │    │
│     │   │       ▼              ▼              ▼              ▼          │    │
│     │   │  Telemetry:     Telemetry:     Approval?      Telemetry:     │    │
│     │   │  [:flowstone,   [:flowstone,   Wait/Continue  [:flowstone,   │    │
│     │   │   :ai, ...]      :mat, ...]                    :mat, ...]    │    │
│     │   └─────────────────────────────────────────────────────────────────┘    │
│     │                         │                                                 │
│     │                         ▼                                                 │
│     ├── Telemetry handlers record:                                              │
│     │   ├── Command.Pipelines.AIOperation (tokens, cost)                        │
│     │   └── Command materialization record                                       │
│     │                                                                           │
│     └── Finalize run (store result/artifact, update status)                     │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 7. FlowStone Database Migration

### 7.1 FlowStone Command Correlation Tables

**File**: `flowstone/priv/repo/migrations/XXXXXX_add_command_correlation.exs`

```elixir
defmodule FlowStone.Repo.Migrations.AddCommandCorrelation do
  use Ecto.Migration

  def change do
    # Add Command correlation to materializations
    alter table(:flowstone_materializations) do
      add :command_session_id, :uuid
      add :command_workflow_id, :uuid
      add :command_user_id, :uuid
      add :correlation_id, :string
    end

    create index(:flowstone_materializations, [:command_session_id])
    create index(:flowstone_materializations, [:command_workflow_id])
    create index(:flowstone_materializations, [:command_user_id])
    create index(:flowstone_materializations, [:correlation_id])

    # Add Command correlation to approvals
    alter table(:flowstone_approvals) do
      add :command_session_id, :uuid
      add :command_workflow_id, :uuid
      add :command_user_id, :uuid
      add :command_approval_id, :uuid  # Link back to Command approval
    end

    create index(:flowstone_approvals, [:command_session_id])
    create index(:flowstone_approvals, [:command_approval_id])

    # AI operation tracking via unified Altar.AI layer
    # See 07_ai_layer_consolidation.md for architecture details
    create_if_not_exists table(:altar_ai_operations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :run_id, :string, null: false
      add :asset_name, :string, null: false
      add :operation, :string, null: false  # :generate, :embed, :classify, :stream
      add :provider, :string
      add :model, :string
      add :tokens_in, :integer, default: 0
      add :tokens_out, :integer, default: 0
      add :cost_usd, :decimal, precision: 10, scale: 6, default: 0
      add :duration_ms, :integer
      add :metadata, :map, default: %{}

      # Command correlation
      add :command_session_id, :uuid
      add :command_workflow_id, :uuid

      # Source context (flowstone, synapse, direct)
      add :source, :string, default: "flowstone"

      timestamps()
    end

    create_if_not_exists index(:altar_ai_operations, [:run_id])
    create_if_not_exists index(:altar_ai_operations, [:command_session_id])
    create_if_not_exists index(:altar_ai_operations, [:command_workflow_id])
    create_if_not_exists index(:altar_ai_operations, [:source])
  end
end
```

---

## 8. Phoenix Router Configuration

### 8.1 Approval Callback Routes

**File**: `command/lib/command_web/router.ex`

```elixir
defmodule CommandWeb.Router do
  use CommandWeb, :router

  # ... existing pipelines ...

  # FlowStone approval callback endpoint
  scope "/api/flowstone" do
    pipe_through :api

    # Approval callbacks from external systems
    post "/approvals/callback", CommandWeb.FlowStone.ApprovalController, :callback

    # Approval status endpoint
    get "/approvals/:id", CommandWeb.FlowStone.ApprovalController, :show
  end

  # Pipeline management API
  scope "/api/pipelines", CommandWeb do
    pipe_through [:api, :authenticated]

    resources "/", PipelineController, except: [:new, :edit] do
      post "/run", PipelineController, :run
      get "/runs/:run_id", PipelineController, :show_run
      post "/runs/:run_id/cancel", PipelineController, :cancel_run
    end
  end
end
```

### 8.2 Approval Controller

**File**: `command/lib/command_web/controllers/flowstone/approval_controller.ex`

```elixir
defmodule CommandWeb.FlowStone.ApprovalController do
  use CommandWeb, :controller

  alias Command.Approvals
  alias FlowStone.SignalGate.Token

  @doc """
  Handle approval callback from external systems.
  """
  def callback(conn, %{"token" => token} = params) do
    with {:ok, claims} <- Token.verify(token),
         {:ok, approval} <- process_callback(claims, params) do
      json(conn, %{status: "ok", approval_id: approval.id})
    else
      {:error, :invalid_token} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid or expired token"})

      {:error, :already_decided} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "Approval already decided"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: inspect(reason)})
    end
  end

  def show(conn, %{"id" => id}) do
    case Approvals.get_by_resource(:flowstone_checkpoint, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Approval not found"})

      approval ->
        json(conn, %{
          id: approval.id,
          status: approval.status,
          message: approval.message,
          context: approval.context,
          timeout_at: approval.timeout_at,
          decided_at: approval.decided_at,
          decided_by: approval.decided_by
        })
    end
  end

  defp process_callback(%{approval_id: approval_id, type: :approval_callback}, params) do
    decision = params["decision"] || "approved"
    reason = params["reason"]
    decided_by = params["decided_by"]

    case decision do
      "approved" ->
        FlowStone.Approval.approve(approval_id, %{
          reason: reason,
          decided_by: decided_by
        })

      "rejected" ->
        FlowStone.Approval.reject(approval_id, %{
          reason: reason,
          decided_by: decided_by
        })

      _ ->
        {:error, :invalid_decision}
    end
  end
end
```

---

## 9. LiveView Helpers for Pipelines

**File**: `command/lib/command_web/live/pipeline_helpers.ex`

```elixir
defmodule CommandWeb.PipelineHelpers do
  @moduledoc """
  Helper functions for LiveView integration with FlowStone pipelines.
  """

  import Phoenix.LiveView

  alias Command.Pipelines
  alias Command.PubSub

  @doc """
  Subscribe LiveView to pipeline run updates.

  Usage in mount/3:
      socket = subscribe_to_pipeline_run(socket, run_id)
  """
  def subscribe_to_pipeline_run(socket, run_id) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PubSub, "pipeline_run:#{run_id}")
    end

    assign(socket, :pipeline_run_id, run_id)
  end

  @doc """
  Subscribe to approval notifications.
  """
  def subscribe_to_approvals(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PubSub, "approvals:pending")
    end

    socket
  end

  @doc """
  Handle pipeline telemetry events.

  Usage in handle_info/2:
      def handle_info({:pipeline_event, event}, socket) do
        socket = handle_pipeline_event(socket, event)
        {:noreply, socket}
      end
  """
  def handle_pipeline_event(socket, event) do
    case event do
      {:materialization_complete, data} ->
        update(socket, :materializations, fn mats ->
          [data | mats]
        end)

      {:ai_operation, data} ->
        socket
        |> update(:ai_operations, fn ops -> [data | ops] end)
        |> update(:total_cost, fn cost ->
          Decimal.add(cost || Decimal.new(0), data.cost_usd || Decimal.new(0))
        end)

      {:run_complete, result} ->
        socket
        |> assign(:run_status, :completed)
        |> assign(:run_result, result)

      {:run_failed, error} ->
        socket
        |> assign(:run_status, :failed)
        |> assign(:run_error, error)

      {:approval_required, approval} ->
        socket
        |> assign(:pending_approval, approval)
        |> push_event("approval_required", %{
          id: approval.id,
          message: approval.message,
          checkpoint: approval.checkpoint_name
        })

      _ ->
        socket
    end
  end

  @doc """
  Respond to an approval from LiveView.
  """
  def respond_to_approval(socket, approval_id, decision, opts \\ []) do
    case decision do
      :approve ->
        Pipelines.approve_checkpoint(approval_id, opts)

      :reject ->
        Pipelines.reject_checkpoint(approval_id, opts)
    end

    assign(socket, :pending_approval, nil)
  end
end
```

---

## 10. Summary of Required Changes

### 10.1 FlowStone Library Changes

| Change | File | Description |
|--------|------|-------------|
| Context extension | `context.ex` | Add Command correlation fields |
| Enhanced telemetry | `telemetry.ex` | AI operation cost tracking events |
| Webhook notifier | `checkpoint/webhook_notifier.ex` | Async approval notifications |
| Approval worker | `workers/approval_notification.ex` | Oban worker for webhooks |
| Run config extension | `run_config.ex` | Command context storage |
| Database migration | `migrations/` | Add correlation columns |

### 10.2 Command Library Changes

| Change | File | Description |
|--------|------|-------------|
| Pipelines context | `pipelines.ex` | Main integration module |
| Pipeline schema | `pipelines/pipeline.ex` | Pipeline configuration |
| PipelineRun schema | `pipelines/pipeline_run.ex` | Execution tracking |
| AIOperation schema | `pipelines/ai_operation.ex` | Cost tracking |
| CommandContext resource | `pipelines/resources/command_context.ex` | FlowStone resource |
| ApprovalNotifier | `pipelines/approval_notifier.ex` | Approval bridge |
| ApprovalController | `controllers/flowstone/approval_controller.ex` | HTTP callbacks |
| LiveView helpers | `live/pipeline_helpers.ex` | UI integration |
| Database migration | `migrations/` | Pipeline tables |

---

## 11. Testing Strategy

All tests use **Supertester** (v0.5.0) for deterministic, zero-sleep testing with proper isolation.

### 11.1 Unit Tests

```elixir
defmodule Command.PipelinesTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.{OTPHelpers, GenServerHelpers, Assertions}

  alias Command.Pipelines

  describe "pipeline management" do
    test "creates pipeline from template" do
      template = insert(:workflow_template)

      {:ok, pipeline} = Pipelines.create_pipeline(template.id, name: "Test Pipeline")

      assert pipeline.name == "Test Pipeline"
      assert pipeline.template_id == template.id
      assert pipeline.status == :active
    end
  end

  describe "pipeline execution" do
    test "runs pipeline with tracking" do
      pipeline = insert(:pipeline)
      session = insert(:session)
      user = insert(:user)

      {:ok, run} = Pipelines.run(pipeline.id,
        session_id: session.id,
        user_id: user.id,
        partition: ~D[2026-01-05]
      )

      assert run.status in [:completed, :pending]
      assert run.session_id == session.id
    end

    test "tracks AI operations" do
      pipeline = insert(:pipeline)

      {:ok, run} = Pipelines.run(pipeline.id, partition: ~D[2026-01-05])

      # Simulate telemetry event
      Pipelines.record_ai_operation(%{
        pipeline_run_id: run.id,
        asset_name: "test_asset",
        operation: :generate,
        provider: "anthropic",
        model: "claude-sonnet-4-20250514",
        tokens_in: 100,
        tokens_out: 200,
        cost_usd: Decimal.new("0.0012")
      })

      cost = Pipelines.calculate_run_cost(run.id)
      assert Decimal.compare(cost, Decimal.new("0.0012")) == :eq
    end
  end
end
```

### 11.2 Integration Tests

```elixir
defmodule Command.Pipelines.IntegrationTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.{OTPHelpers, Assertions}

  alias Command.Pipelines
  alias FlowStone

  @moduletag :integration

  describe "FlowStone integration" do
    test "pipeline run creates FlowStone materializations" do
      pipeline = insert(:pipeline, config: %{
        "module" => "TestPipeline",
        "final_asset" => "output"
      })

      {:ok, run} = Pipelines.run(pipeline.id, partition: ~D[2026-01-05])

      # Verify FlowStone materialization has Command context
      mat = FlowStone.Repo.get_by(FlowStone.Materialization,
        command_workflow_id: run.id
      )

      assert mat != nil
      assert mat.command_workflow_id == run.id
    end

    test "approval notifier creates Command approval" do
      pipeline = insert(:pipeline)

      {:ok, run} = Pipelines.run(pipeline.id,
        partition: ~D[2026-01-05],
        user_id: insert(:user).id
      )

      # Simulate approval request from FlowStone
      fs_approval = %{
        id: Ecto.UUID.generate(),
        checkpoint_name: "review_data",
        message: "Please review this data",
        context: %{data_sample: "..."},
        timeout_at: DateTime.add(DateTime.utc_now(), 3600)
      }

      Command.Pipelines.ApprovalNotifier.notify(:requested, %{approval: fs_approval})

      # Verify Command approval was created
      approval = Command.Approvals.get_by_resource(:flowstone_checkpoint, fs_approval.id)
      assert approval != nil
      assert approval.message == "Please review this data"
    end
  end
end
```

### 11.3 Telemetry Tests

Using Supertester's `TelemetryHelpers` for isolated, deterministic telemetry testing:

```elixir
defmodule Command.Pipelines.TelemetryTest do
  use Supertester.ExUnitFoundation,
    isolation: :full_isolation,
    telemetry_isolation: true

  import Supertester.Assertions

  alias Command.Pipelines

  @tag telemetry_events: [[:flowstone, :ai, :generate, :stop]]
  test "records AI operations from telemetry" do
    pipeline = insert(:pipeline)
    {:ok, run} = Pipelines.run(pipeline.id, partition: ~D[2026-01-05])

    # Attach isolated handler that captures events for this test only
    {:ok, _handler} = Supertester.TelemetryHelpers.attach_isolated(
      [:flowstone, :ai, :generate, :stop],
      buffer: true
    )

    # Emit telemetry event with test context
    Supertester.TelemetryHelpers.emit_with_context(
      [:flowstone, :ai, :generate, :stop],
      %{
        duration: 1_500_000_000,
        tokens_in: 100,
        tokens_out: 200,
        cost_usd: 0.0015
      },
      %{
        provider: "anthropic",
        model: "claude-sonnet-4-20250514",
        asset: "analyze_data",
        command_workflow_id: run.id
      }
    )

    # Assert telemetry was received (no Process.sleep needed!)
    assert Supertester.TelemetryHelpers.assert_telemetry(
      [:flowstone, :ai, :generate, :stop],
      fn _measurements, metadata ->
        metadata.command_workflow_id == run.id
      end
    )

    # Verify the handler recorded the operation
    operations = Pipelines.list_run_ai_operations(run.id)
    assert length(operations) == 1
    assert hd(operations).tokens_in == 100
    assert hd(operations).tokens_out == 200
  end

  test "telemetry handler filters by workflow_id" do
    pipeline = insert(:pipeline)
    {:ok, run1} = Pipelines.run(pipeline.id, partition: ~D[2026-01-05])
    {:ok, run2} = Pipelines.run(pipeline.id, partition: ~D[2026-01-06])

    {:ok, _handler} = Supertester.TelemetryHelpers.attach_isolated(
      [:flowstone, :ai, :generate, :stop],
      buffer: true
    )

    # Emit for run1
    Supertester.TelemetryHelpers.emit_with_context(
      [:flowstone, :ai, :generate, :stop],
      %{tokens_in: 50, tokens_out: 100, cost_usd: 0.001, duration: 500_000_000},
      %{provider: "anthropic", model: "claude-sonnet-4-20250514", asset: "asset1", command_workflow_id: run1.id}
    )

    # Emit for run2
    Supertester.TelemetryHelpers.emit_with_context(
      [:flowstone, :ai, :generate, :stop],
      %{tokens_in: 200, tokens_out: 400, cost_usd: 0.005, duration: 1_000_000_000},
      %{provider: "anthropic", model: "claude-sonnet-4-20250514", asset: "asset2", command_workflow_id: run2.id}
    )

    # Verify costs are tracked separately
    cost1 = Pipelines.calculate_run_cost(run1.id)
    cost2 = Pipelines.calculate_run_cost(run2.id)

    assert Decimal.compare(cost1, Decimal.new("0.001")) == :eq
    assert Decimal.compare(cost2, Decimal.new("0.005")) == :eq
  end
end
```

### 11.4 GenServer Integration Tests

Using Supertester for deterministic GenServer testing:

```elixir
defmodule Command.Pipelines.GenServerTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.{OTPHelpers, GenServerHelpers, Assertions}

  alias Command.Pipelines.Workers.PipelineRunner

  describe "PipelineRunner GenServer" do
    test "processes pipeline run requests deterministically" do
      {:ok, runner} = setup_isolated_genserver(PipelineRunner)

      # Use cast_and_sync for deterministic async testing (no Process.sleep!)
      :ok = cast_and_sync(runner, {:run_pipeline, pipeline_id, opts})

      # Assert state after async operation completed
      assert_genserver_state(runner, fn state ->
        state.active_runs > 0 or state.completed_runs > 0
      end)
    end

    test "handles concurrent pipeline requests" do
      {:ok, runner} = setup_isolated_genserver(PipelineRunner)

      # Stress test with concurrent calls
      {:ok, results} = concurrent_calls(runner,
        [{:run_pipeline, pipeline_id_1, []}, {:run_pipeline, pipeline_id_2, []}],
        10,
        timeout: 5000
      )

      # Verify all calls succeeded
      for %{successes: successes, errors: errors} <- results do
        assert length(errors) == 0
        assert length(successes) == 10
      end

      assert_genserver_responsive(runner)
    end

    test "recovers from crashes" do
      {:ok, runner} = setup_isolated_genserver(PipelineRunner)

      {:ok, info} = test_server_crash_recovery(runner, :test_crash)

      assert info.recovered == true
      assert info.new_pid != info.original_pid
      assert_process_alive(info.new_pid)
    end
  end
end
```

### 11.5 Chaos Engineering Tests

```elixir
defmodule Command.Pipelines.ChaosTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.{OTPHelpers, ChaosHelpers, SupervisorHelpers, Assertions}

  describe "pipeline system resilience" do
    test "survives random worker crashes" do
      {:ok, supervisor} = setup_isolated_supervisor(Command.Pipelines.Supervisor)

      # Kill 50% of workers over 3 seconds
      report = chaos_kill_children(supervisor,
        kill_rate: 0.5,
        duration_ms: 3000,
        kill_interval_ms: 200
      )

      # Verify system recovered
      assert Process.alive?(supervisor)
      assert report.supervisor_crashed == false

      # Wait for stabilization and verify all children alive
      :ok = wait_for_supervisor_stabilization(supervisor)
      assert_all_children_alive(supervisor)
    end

    test "maintains data integrity under chaos" do
      {:ok, supervisor} = setup_isolated_supervisor(Command.Pipelines.Supervisor)

      # Run chaos with concurrent workload
      scenarios = [
        %{type: :kill_children, kill_rate: 0.3, duration_ms: 2000},
        %{
          type: :concurrent,
          build: fn sup ->
            Supertester.ConcurrentHarness.simple_genserver_scenario(
              Command.Pipelines.Workers.PipelineRunner,
              [{:cast, {:run_pipeline, pipeline_id(), []}}, {:call, :get_status}],
              4,
              setup: fn -> {:ok, sup, %{}} end,
              cleanup: fn _, _ -> :ok end
            )
          end
        }
      ]

      report = run_chaos_suite(supervisor, scenarios, timeout: 10_000)

      assert report.failed == 0
    end
  end
end
```

### 11.6 Performance Tests

```elixir
defmodule Command.Pipelines.PerformanceTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.{OTPHelpers, PerformanceHelpers}

  describe "pipeline performance" do
    test "meets execution time SLA" do
      {:ok, runner} = setup_isolated_genserver(Command.Pipelines.Workers.PipelineRunner)

      assert_performance(
        fn -> GenServer.call(runner, {:run_pipeline, simple_pipeline_id(), []}) end,
        max_time_ms: 1000,
        max_memory_bytes: 10_000_000
      )
    end

    test "no memory leak in pipeline processing" do
      {:ok, runner} = setup_isolated_genserver(Command.Pipelines.Workers.PipelineRunner)

      assert_no_memory_leak(1000, fn ->
        GenServer.call(runner, {:run_pipeline, simple_pipeline_id(), []})
      end, threshold: 0.1)
    end

    test "mailbox remains stable under load" do
      {:ok, runner} = setup_isolated_genserver(Command.Pipelines.Workers.PipelineRunner)

      assert_mailbox_stable(runner,
        during: fn ->
          for _ <- 1..100 do
            GenServer.cast(runner, {:run_pipeline, simple_pipeline_id(), []})
          end
        end,
        max_size: 50
      )
    end
  end
end
```
