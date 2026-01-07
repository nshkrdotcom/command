# Component Analysis

**Date**: 2026-01-05
**Version**: 1.0.0

## Overview

This document provides a detailed analysis of each component in the Command ecosystem, including their purpose, current implementation status, key interfaces, and integration points.

---

## 1. FlowStone - Pipeline Orchestration

### Purpose
DAG-based data pipeline framework for building reliable, auditable workflows with first-class support for persistence, lineage tracking, and operational visibility.

### Version & Status
- **Version**: 0.5.2
- **Status**: Alpha (core execution complete, safety hardening in progress)
- **Lines of Code**: ~4,500+

### Key Modules

| Module | Purpose | Key Functions |
|--------|---------|---------------|
| `FlowStone` | Main API | `run/3`, `get/3`, `materialize/2`, `backfill/3` |
| `FlowStone.API` | High-level operations | `run/3`, `get/3`, `graph/2` |
| `FlowStone.Pipeline` | DSL for asset definitions | `asset/2` macro |
| `FlowStone.DAG` | Dependency graph | `from_assets/1`, `topological_names/1` |
| `FlowStone.Executor` | Asset execution | `materialize/2` |
| `FlowStone.Scatter` | Fan-out execution | `create_barrier/1` |
| `FlowStone.Parallel` | Branch coordination | `start_execution/3` |
| `FlowStone.SignalGate` | External suspension | `create/1`, `receive_signal/3` |

### Key Features

1. **Asset-First Design**
   - Named data artifacts with dependencies
   - Declarative execution via `asset` macro
   - Automatic dependency resolution

2. **Execution Patterns**
   - Sequential DAG execution
   - Scatter/Gather for dynamic fan-out
   - Parallel branches with join
   - Signal gates for webhooks/callbacks

3. **Persistence**
   - Materialization tracking
   - Lineage recording
   - Approval checkpoints

### Database Schema

| Table | Purpose |
|-------|---------|
| `flowstone_materializations` | Execution records |
| `flowstone_approvals` | Checkpoint approvals |
| `flowstone_lineage` | Dependency tracking |
| `flowstone_scatter_barriers` | Scatter coordination |
| `flowstone_signal_gates` | External signal state |
| `flowstone_route_decisions` | Conditional routing |
| `flowstone_parallel_executions` | Parallel branch tracking |

### Extension Points

1. **I/O Managers** - `FlowStone.IO.Manager` behaviour
2. **Resources** - `FlowStone.Resource` behaviour
3. **Sensors** - `FlowStone.Sensor` behaviour
4. **Item Readers** - `FlowStone.Scatter.ItemReader` behaviour

### Integration with Command

```elixir
# Command.Pipelines context
defmodule Command.Pipelines.Pipeline do
  use FlowStone.Pipeline

  # Convert Command workflow template to FlowStone assets
  def from_template(template) do
    # Generate asset definitions from template.steps
  end
end

# Execute with Command tracking
def run_pipeline(template_id, partition, opts) do
  template = Workflows.get_template!(template_id)
  pipeline = Pipeline.from_template(template)

  # Create workflow instance for tracking
  {:ok, instance} = Workflows.create_instance(template, partition)

  # Execute via FlowStone
  result = FlowStone.run(pipeline, :final_asset, partition: partition)

  # Record costs from telemetry
  # Store artifacts
  # Update instance status

  result
end
```

---

## 2. Synapse - Multi-Agent Orchestration

### Purpose
Declarative, headless multi-agent orchestration framework with signal-based communication, workflow persistence, and domain-specific agent definitions.

### Version & Status
- **Version**: 0.1.0 (Alpha)
- **Status**: Core implementation complete
- **Lines of Code**: ~3,000+

### Key Modules

| Module | Purpose | Key Functions |
|--------|---------|---------------|
| `Synapse` | Entry point | Delegates to subsystems |
| `Synapse.SignalRouter` | Pub/Sub messaging | `publish/3`, `subscribe/3` |
| `Synapse.Signal.Registry` | Topic management | `register_topic/3` |
| `Synapse.Orchestrator.Runtime` | Agent lifecycle | `reload/1`, `list_agents/1` |
| `Synapse.Orchestrator.AgentConfig` | Config validation | `new/1` |
| `Synapse.Orchestrator.DynamicAgent` | Agent worker | Signal handling |
| `Synapse.Workflow.Engine` | Step execution | `execute/2` |
| `Synapse.AgentRegistry` | Process tracking | `get_or_spawn/4` |

### Agent Types

| Type | Purpose | Key Config |
|------|---------|------------|
| **Specialist** | Execute specific actions | `actions`, `signals.subscribes` |
| **Orchestrator** | Coordinate specialists | `orchestration.*` functions |
| **Custom** | Application-specific | `custom_handler` function |

### Key Features

1. **Signal-Based Communication**
   - Topic registration with schemas
   - Runtime topic creation
   - Payload validation via NimbleOptions

2. **Declarative Agents**
   - Configuration-driven (no GenServer boilerplate)
   - Hot-reload support
   - Dependency ordering

3. **Workflow Engine**
   - Step-based execution
   - Retry with backoff
   - Postgres persistence

4. **Orchestration Patterns**
   - Classify incoming requests
   - Spawn specialists dynamically
   - Aggregate and negotiate results
   - Fast-path for simple cases

### Signal Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                       Synapse.SignalRouter                       │
│                                                                 │
│  Topics:                                                        │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │ :review_request │  │ :review_result  │  │ :review_summary │ │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘ │
│           │                    │                    │          │
│           ▼                    ▼                    ▼          │
│  Subscribers:                                                   │
│  - Coordinator (orchestrator)                                   │
│  - Security Specialist                                          │
│  - Performance Specialist                                       │
│  - Style Specialist                                             │
└─────────────────────────────────────────────────────────────────┘
```

### Integration with Command

```elixir
# Command.Orchestration context
defmodule Command.Orchestration do
  alias Synapse.{SignalRouter, Orchestrator.Runtime}

  def publish_signal(topic, payload, opts \\ []) do
    session_id = opts[:session_id]

    # Track in Command session
    {:ok, _message} = Sessions.add_message(session_id, %{
      role: :system,
      content: "Signal published: #{topic}",
      metadata: %{signal_payload: payload}
    })

    # Publish via Synapse
    SignalRouter.publish(router(), topic, payload)
  end

  def register_agent(config) do
    # Store config in Command database
    {:ok, agent} = Agents.create_agent_config(config)

    # Register with Synapse runtime
    Runtime.add_agent(runtime(), config)

    {:ok, agent}
  end
end
```

---

## 3. ALTAR - AI Tool Contracts

### Purpose
Universal, language-agnostic data model for AI tool contracts with local execution runtime and future distributed capabilities.

### Version & Status
- **Version**: 0.2.0
- **Status**: ADM 90% complete, LATER 50% complete, GRID spec only
- **Lines of Code**: ~1,800+

### Architecture Layers

```
Layer 3: GRID (Specification only)
    - Distributed execution
    - STRICT/DEVELOPMENT modes
    - Cross-node orchestration

Layer 2: LATER (50% implemented)
    - Local execution
    - Registry (GenServer)
    - Executor (stateless)

Layer 1: ADM (90% implemented)
    - Universal contracts
    - JSON serialization
    - Validation
```

### Key ADM Structures

| Structure | Purpose | Key Fields |
|-----------|---------|------------|
| `FunctionDeclaration` | Tool contract | `name`, `description`, `parameters` |
| `FunctionCall` | Invocation request | `call_id`, `name`, `args` |
| `ToolResult` | Execution response | `call_id`, `content`, `is_error` |
| `ToolConfig` | Mode configuration | `mode`, `function_names` |
| `Schema` | Parameter validation | Full OpenAPI 3.0 types |
| `Tool` | Function grouping | `function_declarations` |
| `ToolManifest` | Deployment bundle | `version`, `tools`, `metadata` |

### LATER Components

| Component | Purpose | Key Functions |
|-----------|---------|---------------|
| `Altar.LATER.Registry` | Tool storage | `register_tool/3`, `lookup_tool/2` |
| `Altar.LATER.Executor` | Tool execution | `execute_tool/2` |

### Integration with Command

```elixir
# Command.Tools context
defmodule Command.Tools do
  alias Altar.ADM
  alias Altar.LATER.{Registry, Executor}

  def register_tool(name, description, params_schema, implementation) do
    # Create ADM declaration
    {:ok, decl} = ADM.new_function_declaration(%{
      name: name,
      description: description,
      parameters: params_schema
    })

    # Store in Command database
    {:ok, tool} = Repo.insert(%Tool{
      name: name,
      declaration: ADM.FunctionDeclaration.to_map(decl),
      status: :active
    })

    # Register with ALTAR
    :ok = Registry.register_tool(registry(), decl, implementation)

    {:ok, tool}
  end

  def execute(call_id, name, args) do
    # Create ADM call
    {:ok, call} = ADM.new_function_call(%{
      call_id: call_id,
      name: name,
      args: args
    })

    # Check approvals
    case Approvals.check_tool_call(call) do
      :approved ->
        # Execute via ALTAR
        {:ok, result} = Executor.execute_tool(registry(), call)

        # Record cost
        Costs.record_tool_call(call, result)

        {:ok, result}

      :pending ->
        {:pending, :awaiting_approval}

      :denied ->
        {:error, :denied}
    end
  end
end
```

---

## 4. Altar.AI - Multi-Provider AI Abstraction

### Purpose
Protocol-based AI provider abstraction enabling seamless switching between providers with automatic fallback and capability detection.

### Version & Status
- **Version**: 0.1.0
- **Status**: Production ready
- **Lines of Code**: ~1,100

### Protocol Hierarchy

```
┌─────────────────────────────────────────────────────────────────┐
│                        Altar.AI Protocols                        │
│                                                                 │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐       │
│  │   Generator   │  │   Embedder    │  │  Classifier   │       │
│  │               │  │               │  │               │       │
│  │ generate/3    │  │ embed/3       │  │ classify/4    │       │
│  │ stream/3      │  │ batch_embed/3 │  │               │       │
│  └───────────────┘  └───────────────┘  └───────────────┘       │
│                                                                 │
│  ┌───────────────┐                                              │
│  │ CodeGenerator │                                              │
│  │               │                                              │
│  │ generate_code/3                                              │
│  │ explain_code/3                                               │
│  └───────────────┘                                              │
└─────────────────────────────────────────────────────────────────┘
```

### Adapters

| Adapter | Protocols | Features |
|---------|-----------|----------|
| **Gemini** | Generator, Embedder | Full streaming, batch embed |
| **Claude** | Generator | Via ClaudeAgentSDK |
| **Codex** | Generator, CodeGenerator | OpenAI GPT models |
| **Composite** | All | Multi-provider fallback |
| **Fallback** | Generator, Classifier | Heuristic-based |
| **Mock** | All | Testing with configurable responses |

### Capability Matrix

| Capability | Gemini | Claude | Codex | Fallback | Mock |
|------------|--------|--------|-------|----------|------|
| generate | ✓ | ✓ | ✓ | ✓ | ✓ |
| stream | ✓ | ✗ | ✗ | ✗ | ✓ |
| embed | ✓ | ✗ | ✗ | ✗ | ✓ |
| batch_embed | ✓ | ✗ | ✗ | ✗ | ✓ |
| classify | ✗ | ✗ | ✗ | ✓ | ✓ |
| generate_code | ✗ | ✗ | ✓ | ✗ | ✓ |
| explain_code | ✗ | ✗ | ✓ | ✗ | ✓ |

### Composite Fallback Pattern

```elixir
# Automatic fallback chain
composite = Altar.AI.Adapters.Composite.default()
# Creates: Gemini → Claude → Codex → Fallback

# On failure with retryable error:
# 1. Try Gemini - fails with rate_limit
# 2. Try Claude - fails with timeout
# 3. Try Codex - succeeds
# Returns: {:ok, response}
```

---

## 5. FlowStone.AI - Pipeline AI Integration

### Purpose
Thin integration layer bridging Altar.AI into FlowStone's resource system for AI-powered data pipelines.

### Version & Status
- **Version**: 0.1.0
- **Status**: Complete
- **Lines of Code**: 549

### Key Modules

| Module | Purpose | Key Functions |
|--------|---------|---------------|
| `FlowStone.AI` | Facade | `setup_telemetry/0`, `resource_init/1` |
| `FlowStone.AI.Resource` | FlowStone.Resource impl | `generate/3`, `embed/3`, `classify/4` |
| `FlowStone.AI.Assets` | DSL helpers | `classify_each/5`, `enrich_each/4`, `embed_each/4` |
| `FlowStone.AI.Telemetry` | Event bridge | `attach/0`, `detach/0` |

### Resource Pattern

```elixir
# Register AI as FlowStone resource
FlowStone.Resources.register(:ai, FlowStone.AI.Resource, [
  adapter: Altar.AI.Adapters.Composite,
  adapter_opts: [strategy: :fallback]
])

# Use in pipeline asset
asset :classified_feedback do
  depends_on [:raw_feedback]
  requires [:ai]

  execute fn ctx, %{raw_feedback: feedback} ->
    FlowStone.AI.Assets.classify_each(
      ctx.resources.ai,
      feedback,
      & &1.text,
      ["positive", "negative", "neutral"]
    )
  end
end
```

---

## 6. Portfolio Core - RAG Port Specifications

### Purpose
Hexagonal architecture foundation defining port specifications (behaviours) for RAG systems, with manifest-based configuration and adapter registry.

### Version & Status
- **Version**: 0.3.1
- **Status**: Stable
- **Lines of Code**: ~3,000+

### Port Specifications

| Port | Purpose | Key Callbacks |
|------|---------|---------------|
| `Embedder` | Text vectorization | `embed/2`, `embed_batch/2` |
| `VectorStore` | Similarity search | `search/4`, `store/4` |
| `VectorStore.Hybrid` | Hybrid search | `hybrid_search/6` |
| `GraphStore` | Knowledge graphs | `create_node/3`, `query/2` |
| `GraphStore.Community` | GraphRAG clustering | `detect_communities/2` |
| `LLM` | Text generation | `complete/2`, `stream/2` |
| `Router` | Multi-provider routing | `route/2`, `execute/2` |
| `Retriever` | RAG strategies | `retrieve/3` |
| `Chunker` | Document splitting | `chunk/3` |
| `Reranker` | Result reranking | `rerank/3` |
| `Cache` | Caching abstraction | `get/2`, `put/3` |
| `Pipeline` | Workflow steps | `execute/2` |
| `Agent` | Tool-using agents | `run/2` |
| `Tool` | Individual tools | `execute/2` |
| `Evaluation` | RAG quality | `evaluate_rag_triad/2` |
| `QueryRewriter` | Query cleanup | `rewrite/2` |
| `QueryExpander` | Query expansion | `expand/2` |
| `QueryDecomposer` | Multi-query | `decompose/2` |
| `CollectionSelector` | Index routing | `select/3` |

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      PortfolioCore                               │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                     Manifest.Engine                        │ │
│  │                                                           │ │
│  │  - Load YAML manifests                                    │ │
│  │  - Environment variable expansion                         │ │
│  │  - Adapter wiring                                         │ │
│  └───────────────────────────────────────────────────────────┘ │
│                              │                                  │
│                              ▼                                  │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                       Registry                             │ │
│  │                                                           │ │
│  │  - ETS-based lookup                                       │ │
│  │  - Health tracking                                        │ │
│  │  - Call/error metrics                                     │ │
│  └───────────────────────────────────────────────────────────┘ │
│                              │                                  │
│                              ▼                                  │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                        Ports                               │ │
│  │                                                           │ │
│  │  Embedder │ VectorStore │ LLM │ Retriever │ ...          │ │
│  └───────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Existing Command Integration

Command already integrates Portfolio Core via `Command.Portfolio`:

```elixir
# lib/command/portfolio.ex (348 lines)
defmodule Command.Portfolio do
  @required_adapters [:vector_store, :embedder, :llm, :retriever]

  # Adapter access
  def adapter!(port_name), do: PortfolioCore.adapter!(port_name)

  # Embedding operations
  def embed(text, opts \\ [])
  def embed_batch(texts, opts \\ [])

  # LLM operations
  def complete(messages, opts \\ [])
  def stream(messages, opts \\ [])

  # Retrieval
  def retrieve(query, context \\ %{}, opts \\ [])

  # Vector store
  def store_embedding(index_id, id, embedding, metadata)
  def search_vectors(index_id, query_embedding, k, opts)
end
```

---

## 7. Portfolio Index - Production Adapters

### Purpose
Production-ready adapter implementations for Portfolio Core ports, including vector storage (Pgvector), graph database (Neo4j), and multi-provider AI integrations.

### Version & Status
- **Version**: 0.2.0
- **Status**: Production ready
- **Lines of Code**: ~5,000+

### Adapter Implementations

| Port | Adapters |
|------|----------|
| `VectorStore` | Pgvector, Memory |
| `VectorStore.Hybrid` | Pgvector.Hybrid |
| `GraphStore` | Neo4j |
| `GraphStore.Community` | Neo4j.Community |
| `Embedder` | Gemini, OpenAI, Bumblebee |
| `LLM` | Gemini, Anthropic, OpenAI, Codex |
| `Chunker` | Recursive (17 formats), Character, Sentence, Paragraph |
| `DocumentStore` | Postgres |
| `CollectionSelector` | RuleBased, LLM |
| `Reranker` | Passthrough, LLM |
| `RetrievalMetrics` | Standard |

### RAG Strategies

| Strategy | Description |
|----------|-------------|
| **Hybrid** | Vector + fulltext with RRF fusion |
| **Self-RAG** | Retrieval assessment and critique |
| **GraphRAG** | Entity extraction and graph traversal |
| **Agentic** | Tool-based iterative retrieval |

### Pipelines (Broadway)

| Pipeline | Purpose |
|----------|---------|
| **Ingestion** | File discovery → parsing → chunking |
| **Embedding** | Chunk → embed → store |

### Database Schema

| Table | Purpose |
|-------|---------|
| `portfolio_documents` | Document metadata |
| `portfolio_chunks` | Chunks with pgvector embeddings |
| `portfolio_collections` | Collection metadata |
| `vector_index_registry` | Index configuration |

---

## 8. Portfolio Coder - Code Intelligence

### Purpose
Code intelligence platform providing repository indexing, semantic code search, and project portfolio management.

### Version & Status
- **Version**: 0.4.0
- **Status**: Production ready
- **Lines of Code**: 3,418

### Key Components

| Component | Purpose | Lines |
|-----------|---------|-------|
| **Indexer** | Repository scanning | 282 |
| **Search** | Semantic + text search | 122 |
| **Graph** | Dependency analysis | 85 |
| **Parsers** | Language-specific AST | 832 |
| **Portfolio** | Project management | 1,343 |
| **Tools** | Agent tools | 743 |

### Language Support

| Language | Parser | Features |
|----------|--------|----------|
| **Elixir** | Sourceror AST | Full module/function extraction |
| **Python** | Regex | Class/function/import extraction |
| **JavaScript** | Regex | ES6 module/class extraction |

### Portfolio Management

```
┌─────────────────────────────────────────────────────────────────┐
│                    Portfolio Coder System                        │
│                                                                 │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐       │
│  │   Registry    │  │    Scanner    │  │    Context    │       │
│  │               │  │               │  │               │       │
│  │ registry.yml  │  │ Auto-detect   │  │ Per-repo      │       │
│  │ Master list   │  │ Multi-dir     │  │ metadata      │       │
│  └───────────────┘  └───────────────┘  └───────────────┘       │
│                                                                 │
│  ┌───────────────┐  ┌───────────────┐                          │
│  │ Relationships │  │    Syncer     │                          │
│  │               │  │               │                          │
│  │ Inter-repo    │  │ Keep in sync  │                          │
│  │ dependencies  │  │ with FS       │                          │
│  └───────────────┘  └───────────────┘                          │
└─────────────────────────────────────────────────────────────────┘
```

### CLI Commands

```bash
# Portfolio management
mix portfolio.scan          # Discover repos
mix portfolio.list          # List with filters
mix portfolio.show <id>     # Show details
mix portfolio.sync          # Sync metadata

# Code intelligence
mix code.index <path>       # Index repository
mix code.search <query>     # Semantic search
mix code.ask <question>     # AI-powered Q&A
mix code.deps <cmd> <path>  # Dependency analysis
```

### Integration Opportunity

Portfolio Coder can enhance Command with:
- Codebase-aware RAG context
- Repository relationship tracking
- Semantic code search for tool discovery
- Project portfolio dashboards
