# Command System Architecture

**Date**: 2026-01-05
**Version**: 1.0.0

## Overview

This document defines the complete system architecture for Command as the unified orchestration layer for AI agent operations, integrating FlowStone pipelines, Synapse multi-agent systems, ALTAR tool contracts, and Portfolio RAG infrastructure.

## Architectural Layers

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    PRESENTATION LAYER                                    │
│                                                                                         │
│  Phoenix LiveView Dashboard  │  REST/GraphQL API  │  CLI Tools  │  WebSocket Events    │
└─────────────────────────────────────────────────────────────────────────────────────────┘
                                              │
                                              ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                     COMMAND CORE                                         │
│                                                                                         │
│  ┌───────────────┐ ┌───────────────┐ ┌───────────────┐ ┌───────────────┐ ┌───────────┐ │
│  │   Accounts    │ │   Sessions    │ │    Agents     │ │   Workflows   │ │  Indexes  │ │
│  │               │ │               │ │               │ │               │ │           │ │
│  │ Users         │ │ Conversations │ │ Providers     │ │ Templates     │ │ RAG Ctx   │ │
│  │ API Keys      │ │ Messages      │ │ Interactions  │ │ Instances     │ │ Embeddings│ │
│  │ Credentials   │ │ Branches      │ │ Tool Calls    │ │ Steps         │ │ pgvector  │ │
│  └───────────────┘ └───────────────┘ └───────────────┘ └───────────────┘ └───────────┘ │
│                                                                                         │
│  ┌───────────────┐ ┌───────────────┐ ┌───────────────┐ ┌───────────────┐               │
│  │   Approvals   │ │   Artifacts   │ │     Costs     │ │  Scheduling   │               │
│  │               │ │               │ │               │ │               │               │
│  │ Rules         │ │ Files         │ │ Per-Call      │ │ Cron Jobs     │               │
│  │ Requests      │ │ Versions      │ │ Daily Agg     │ │ Intervals     │               │
│  │ Decisions     │ │ Diffs         │ │ Attribution   │ │ One-time      │               │
│  └───────────────┘ └───────────────┘ └───────────────┘ └───────────────┘               │
│                                                                                         │
│  ┌───────────────┐                                                                      │
│  │   Presence    │  ◄── Real-time user activity & PubSub events                        │
│  └───────────────┘                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────────┘
                                              │
                    ┌─────────────────────────┼─────────────────────────┐
                    │                         │                         │
                    ▼                         ▼                         ▼
┌─────────────────────────────┐ ┌─────────────────────────────┐ ┌─────────────────────────┐
│    PIPELINE ORCHESTRATION   │ │    MULTI-AGENT SYSTEMS      │ │    DIRECT AI ACCESS     │
│         (FlowStone)         │ │        (Synapse)            │ │      (Portfolio)        │
│                             │ │                             │ │                         │
│  ┌─────────────────────┐    │ │  ┌─────────────────────┐    │ │  ┌─────────────────┐    │
│  │ DAG Execution       │    │ │  │ Signal Router       │    │ │  │ Embedder        │    │
│  │ - Asset deps        │    │ │  │ - Pub/Sub           │    │ │  │ - embed()       │    │
│  │ - Topological sort  │    │ │  │ - Topic registry    │    │ │  │ - embed_batch() │    │
│  └─────────────────────┘    │ │  └─────────────────────┘    │ │  └─────────────────┘    │
│                             │ │                             │ │                         │
│  ┌─────────────────────┐    │ │  ┌─────────────────────┐    │ │  ┌─────────────────┐    │
│  │ Scatter/Gather      │    │ │  │ Agent Registry      │    │ │  │ VectorStore     │    │
│  │ - Fan-out execution │    │ │  │ - Lifecycle mgmt    │    │ │  │ - search()      │    │
│  │ - Barrier sync      │    │ │  │ - Process tracking  │    │ │  │ - store()       │    │
│  └─────────────────────┘    │ │  └─────────────────────┘    │ │  └─────────────────┘    │
│                             │ │                             │ │                         │
│  ┌─────────────────────┐    │ │  ┌─────────────────────┐    │ │  ┌─────────────────┐    │
│  │ Parallel Branches   │    │ │  │ Workflow Engine     │    │ │  │ LLM             │    │
│  │ - Heterogeneous     │    │ │  │ - Step execution    │    │ │  │ - complete()    │    │
│  │ - Join function     │    │ │  │ - Persistence       │    │ │  │ - stream()      │    │
│  └─────────────────────┘    │ │  └─────────────────────┘    │ │  └─────────────────┘    │
│                             │ │                             │ │                         │
│  ┌─────────────────────┐    │ │  ┌─────────────────────┐    │ │  ┌─────────────────┐    │
│  │ Signal Gates        │    │ │  │ Agent Types         │    │ │  │ Retriever       │    │
│  │ - External suspend  │    │ │  │ - Orchestrators     │    │ │  │ - Hybrid RAG    │    │
│  │ - Webhook triggers  │    │ │  │ - Specialists       │    │ │  │ - GraphRAG      │    │
│  └─────────────────────┘    │ │  │ - Custom handlers   │    │ │  │ - Self-RAG      │    │
│                             │ │  └─────────────────────┘    │ │  └─────────────────┘    │
│  ┌─────────────────────┐    │ │                             │ │                         │
│  │ FlowStone.AI        │    │ │  ┌─────────────────────┐    │ │  ┌─────────────────┐    │
│  │ - AI as Resource    │    │ │  │ Domains             │    │ │  │ Router          │    │
│  │ - classify_each()   │    │ │  │ - Code Review       │    │ │  │ - Multi-provider│    │
│  │ - enrich_each()     │    │ │  │ - Custom domains    │    │ │  │ - Fallback      │    │
│  └─────────────────────┘    │ │  └─────────────────────┘    │ │  │ - Cost-optimized│    │
│                             │ │                             │ │  └─────────────────┘    │
└─────────────────────────────┘ └─────────────────────────────┘ └─────────────────────────┘
                    │                         │                         │
                    └─────────────────────────┼─────────────────────────┘
                                              │
                                              ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                AI PROVIDER ABSTRACTION                                   │
│                                                                                         │
│  ┌───────────────────────────────────────────────────────────────────────────────────┐  │
│  │                                  Altar.AI                                          │  │
│  │                                                                                    │  │
│  │  Protocols:  Generator │ Embedder │ Classifier │ CodeGenerator                    │  │
│  │                                                                                    │  │
│  │  Adapters:   Gemini │ Claude │ Codex │ Composite │ Fallback │ Mock               │  │
│  │                                                                                    │  │
│  │  Features:   Capability detection │ Automatic fallback │ Telemetry               │  │
│  └───────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                         │
│  ┌───────────────────────────────────────────────────────────────────────────────────┐  │
│  │                                  ALTAR ADM                                         │  │
│  │                                                                                    │  │
│  │  Contracts:  FunctionDeclaration │ FunctionCall │ ToolResult │ Schema            │  │
│  │                                                                                    │  │
│  │  Features:   JSON-native │ Validation │ Tool organization │ Manifests            │  │
│  └───────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                         │
│  ┌───────────────────────────────────────────────────────────────────────────────────┐  │
│  │                                  ALTAR LATER                                       │  │
│  │                                                                                    │  │
│  │  Registry:   Tool function registration │ Runtime lookup                          │  │
│  │                                                                                    │  │
│  │  Executor:   Validated execution │ Error normalization │ Telemetry               │  │
│  └───────────────────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────┘
                                              │
                                              ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                  STORAGE LAYER                                           │
│                                                                                         │
│  ┌───────────────┐ ┌───────────────┐ ┌───────────────┐ ┌───────────────────────────────┐│
│  │  PostgreSQL   │ │   pgvector    │ │    Neo4j      │ │       Redis/ETS              ││
│  │               │ │               │ │               │ │                               ││
│  │ Ecto schemas  │ │ Embeddings    │ │ Knowledge     │ │ Caching                       ││
│  │ Transactions  │ │ Similarity    │ │ Graphs        │ │ Rate limiting                 ││
│  │ Audit logs    │ │ Hybrid search │ │ Relationships │ │ Sessions                      ││
│  └───────────────┘ └───────────────┘ └───────────────┘ └───────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

## Data Flow Patterns

### Pattern 1: Pipeline Execution with Command Tracking

```
User Request
     │
     ▼
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│  Command    │ ───▶ │  FlowStone  │ ───▶ │  Altar.AI   │
│  Workflows  │      │  Pipeline   │      │  Provider   │
│             │      │             │      │             │
│ - Create    │      │ - Execute   │      │ - Generate  │
│   instance  │      │   DAG       │      │ - Embed     │
│ - Track run │      │ - Materialize│     │ - Classify  │
└─────────────┘      └─────────────┘      └─────────────┘
     │                     │                    │
     ▼                     ▼                    ▼
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│  Command    │      │  FlowStone  │      │  Command    │
│  Costs      │ ◀─── │  Telemetry  │ ───▶ │  Artifacts  │
│             │      │             │      │             │
│ - Tokens    │      │ - Duration  │      │ - Store     │
│ - Model     │      │ - Status    │      │   results   │
│ - Provider  │      │ - Lineage   │      │ - Version   │
└─────────────┘      └─────────────┘      └─────────────┘
```

### Pattern 2: Multi-Agent Orchestration

```
External Signal (e.g., PR webhook)
     │
     ▼
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│  Command    │ ───▶ │  Synapse    │ ───▶ │  Synapse    │
│  Sessions   │      │  Router     │      │  Orchestrator│
│             │      │             │      │             │
│ - Create    │      │ - Publish   │      │ - Classify  │
│   session   │      │   signal    │      │ - Spawn     │
│ - Track     │      │ - Validate  │      │   specialists│
└─────────────┘      └─────────────┘      └─────────────┘
                                               │
                           ┌───────────────────┼───────────────────┐
                           ▼                   ▼                   ▼
                    ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
                    │ Specialist  │     │ Specialist  │     │ Specialist  │
                    │ (Security)  │     │ (Perf)      │     │ (Style)     │
                    │             │     │             │     │             │
                    │ - Actions   │     │ - Actions   │     │ - Actions   │
                    │ - LLM calls │     │ - LLM calls │     │ - LLM calls │
                    └─────────────┘     └─────────────┘     └─────────────┘
                           │                   │                   │
                           └───────────────────┼───────────────────┘
                                               ▼
                    ┌─────────────┐      ┌─────────────┐      ┌─────────────┐
                    │  Command    │ ◀─── │  Synapse    │ ───▶ │  Command    │
                    │  Approvals  │      │  Aggregate  │      │  Costs      │
                    │             │      │             │      │             │
                    │ - Request   │      │ - Merge     │      │ - Attribute │
                    │   approval  │      │   results   │      │   per-agent │
                    │ - Wait      │      │ - Emit      │      │             │
                    └─────────────┘      └─────────────┘      └─────────────┘
```

### Pattern 3: RAG-Augmented Interaction

```
User Query
     │
     ▼
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│  Command    │ ───▶ │  Portfolio  │ ───▶ │  Portfolio  │
│  Sessions   │      │  Retriever  │      │  VectorStore│
│             │      │             │      │             │
│ - Message   │      │ - Embed     │      │ - Search    │
│ - Context   │      │   query     │      │ - RRF       │
│             │      │ - Strategy  │      │ - Hybrid    │
└─────────────┘      └─────────────┘      └─────────────┘
                           │
                           ▼
                    ┌─────────────┐      ┌─────────────┐
                    │  Portfolio  │ ───▶ │  Command    │
                    │  LLM        │      │  Sessions   │
                    │             │      │             │
                    │ - Augment   │      │ - Store     │
                    │   with ctx  │      │   response  │
                    │ - Generate  │      │ - Track     │
                    └─────────────┘      └─────────────┘
```

## Context Boundaries

### Command Contexts (Existing)

| Context | Responsibility | Key Entities |
|---------|---------------|--------------|
| **Accounts** | User identity, API credentials | User, ApiKey, ProviderCredential |
| **Sessions** | Conversation state, branching | Session, Message, Branch |
| **Agents** | LLM provider configuration | Provider, Interaction, ToolCall |
| **Workflows** | DAG templates and instances | Template, Instance, Step |
| **Indexes** | RAG context management | Index, Document, Embedding |
| **Approvals** | Human-in-the-loop | Rule, Request, Decision |
| **Artifacts** | File storage with versioning | Artifact, Version, Diff |
| **Costs** | Usage tracking | ApiCall, DailySummary |
| **Scheduling** | Job scheduling | Schedule, Job |
| **Presence** | Real-time activity | Activity, Channel |

### New Integration Contexts (Proposed)

| Context | Responsibility | Integration Target |
|---------|---------------|-------------------|
| **Pipelines** | FlowStone pipeline orchestration | FlowStone |
| **Orchestration** | Synapse agent coordination | Synapse |
| **Tools** | ALTAR tool contract management | ALTAR ADM/LATER |

## Integration Points

### 1. Command.Pipelines (FlowStone Integration)

```elixir
defmodule Command.Pipelines do
  @moduledoc """
  FlowStone pipeline orchestration context.

  Manages pipeline definitions, execution, and tracking through FlowStone
  while maintaining Command's session, cost, and approval infrastructure.
  """

  # Define pipeline from Command workflow template
  def create_pipeline(workflow_template, opts \\ [])

  # Execute pipeline with tracking
  def run(pipeline_id, partition, opts \\ [])

  # Get pipeline status
  def status(pipeline_id, partition)

  # List materializations
  def list_materializations(pipeline_id, opts \\ [])
end
```

### 2. Command.Orchestration (Synapse Integration)

```elixir
defmodule Command.Orchestration do
  @moduledoc """
  Synapse multi-agent orchestration context.

  Manages agent configurations, signal routing, and workflow execution
  while integrating with Command's session and approval systems.
  """

  # Register agent configuration
  def register_agent(config)

  # Publish signal to trigger agents
  def publish(topic, payload, opts \\ [])

  # Get agent status
  def agent_status(agent_id)

  # List running agents
  def list_agents(opts \\ [])
end
```

### 3. Command.Tools (ALTAR Integration)

```elixir
defmodule Command.Tools do
  @moduledoc """
  ALTAR tool contract management context.

  Provides unified tool definitions that can be used across
  FlowStone assets and Synapse agents.
  """

  # Register tool with ADM contract
  def register(declaration, implementation)

  # Execute tool call
  def execute(function_call)

  # List available tools
  def list_tools(opts \\ [])

  # Get tool manifest for deployment
  def manifest(version, tools)
end
```

## Telemetry Unification

All components emit telemetry events that Command aggregates:

```elixir
# FlowStone events
[:flowstone, :materialization, :start | :stop | :exception]
[:flowstone, :ai, :generate | :embed | :classify, :start | :stop]

# Synapse events
[:synapse, :signal_router, :publish | :deliver]
[:synapse, :workflow, :step, :start | :stop | :exception]
[:synapse, :llm, :request, :start | :stop | :exception]

# Altar.AI events
[:altar, :ai, :generate | :embed | :classify, :start | :stop | :exception]

# Portfolio events
[:portfolio, :embedder, :embed, :start | :stop]
[:portfolio, :vector_store, :search, :start | :stop]
[:portfolio, :llm, :complete, :start | :stop]
[:portfolio, :rag, :search | :rerank | :answer, :start | :stop]

# Command events (aggregated)
[:command, :pipeline, :run, :start | :stop]
[:command, :agent, :execution, :start | :stop]
[:command, :tool, :call, :start | :stop]
[:command, :cost, :recorded]
```

## Configuration

```elixir
# config/config.exs

config :command,
  ecto_repos: [Command.Repo]

# FlowStone integration
config :command, Command.Pipelines,
  enabled: true,
  default_io_manager: :postgres,
  async_execution: true

# Synapse integration
config :command, Command.Orchestration,
  enabled: true,
  config_source: {:module, Command.AgentConfigs},
  signal_router: Command.Synapse.Router

# ALTAR integration
config :command, Command.Tools,
  enabled: true,
  registry: Command.Tools.Registry,
  executor: Command.Tools.Executor

# Portfolio (existing)
config :command, Command.Portfolio,
  enabled: true,
  required_adapters: [:vector_store, :embedder, :llm, :retriever]
```

## Security Model

### Credential Isolation

```
┌─────────────────────────────────────────────────────────────────┐
│                     Command.Accounts                             │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              ProviderCredential (Encrypted)              │   │
│  │                                                         │   │
│  │  user_id ──────► Cloak-encrypted API keys               │   │
│  │  provider ─────► :anthropic, :openai, :google, :cohere  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                Credential Resolution                     │   │
│  │                                                         │   │
│  │  1. User's personal credential (if exists)             │   │
│  │  2. Organization's shared credential                    │   │
│  │  3. System default (if configured)                      │   │
│  │  4. Error if none available                             │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Approval Flow

```
Tool Call Request
       │
       ▼
┌─────────────────┐
│  Check Rules    │
│                 │
│  - Auto-approve │
│  - Require      │
│  - Deny         │
└─────────────────┘
       │
       ├─── Auto-approve ──────────────────► Execute
       │
       ├─── Require ───┐
       │               ▼
       │        ┌─────────────────┐
       │        │  Create Request │
       │        │                 │
       │        │  - Notify user  │
       │        │  - Set timeout  │
       │        └─────────────────┘
       │               │
       │               ▼
       │        ┌─────────────────┐
       │        │  Await Decision │
       │        │                 │
       │        │  - Approved ────┼──────► Execute
       │        │  - Rejected ────┼──────► Return error
       │        │  - Timeout ─────┼──────► Escalate/Fail
       │        └─────────────────┘
       │
       └─── Deny ──────────────────────────► Return error
```

## Deployment Topology

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              Production Environment                              │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                         Application Nodes                                │   │
│  │                                                                         │   │
│  │  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐               │   │
│  │  │  Phoenix      │  │  Phoenix      │  │  Phoenix      │               │   │
│  │  │  Node 1       │  │  Node 2       │  │  Node 3       │               │   │
│  │  │               │  │               │  │               │               │   │
│  │  │  - Command    │  │  - Command    │  │  - Command    │               │   │
│  │  │  - FlowStone  │  │  - FlowStone  │  │  - FlowStone  │               │   │
│  │  │  - Synapse    │  │  - Synapse    │  │  - Synapse    │               │   │
│  │  │  - Oban       │  │  - Oban       │  │  - Oban       │               │   │
│  │  └───────────────┘  └───────────────┘  └───────────────┘               │   │
│  │           │                 │                 │                         │   │
│  │           └─────────────────┼─────────────────┘                         │   │
│  │                             │                                           │   │
│  │                             ▼                                           │   │
│  │  ┌───────────────────────────────────────────────────────────────────┐ │   │
│  │  │                     Distributed Erlang                            │ │   │
│  │  │                                                                   │ │   │
│  │  │  - PubSub (Phoenix.PubSub)                                       │ │   │
│  │  │  - Presence (Phoenix.Presence)                                   │ │   │
│  │  │  - Synapse SignalRouter (distributed)                            │ │   │
│  │  └───────────────────────────────────────────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                         Data Layer                                       │   │
│  │                                                                         │   │
│  │  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐               │   │
│  │  │  PostgreSQL   │  │    Neo4j      │  │    Redis      │               │   │
│  │  │  + pgvector   │  │               │  │               │               │   │
│  │  │               │  │  - Knowledge  │  │  - Cache      │               │   │
│  │  │  - Ecto       │  │    graphs     │  │  - Sessions   │               │   │
│  │  │  - Oban       │  │  - Entities   │  │  - Rate limit │               │   │
│  │  │  - Embeddings │  │  - Relations  │  │               │               │   │
│  │  └───────────────┘  └───────────────┘  └───────────────┘               │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                     External AI Providers                                │   │
│  │                                                                         │   │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐            │   │
│  │  │ Anthropic │  │  OpenAI   │  │  Google   │  │  Cohere   │            │   │
│  │  │  Claude   │  │  GPT-4    │  │  Gemini   │  │           │            │   │
│  │  └───────────┘  └───────────┘  └───────────┘  └───────────┘            │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```
