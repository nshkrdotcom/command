# Command System Architecture: Executive Summary

**Date**: 2026-01-05
**Version**: 1.0.0
**Status**: Design Complete

## Vision

Command is the **unified orchestration layer** for an AI Agent Ecosystem that brings together:

- **Pipeline Orchestration** (FlowStone) - DAG-based data workflow execution
- **Multi-Agent Systems** (Synapse) - Declarative agent coordination via signals
- **AI Provider Abstraction** (Altar.AI/ALTAR) - Universal tool contracts and provider federation
- **RAG Infrastructure** (Portfolio Core/Index) - Retrieval-augmented generation at scale
- **Code Intelligence** (Portfolio Coder) - Repository analysis and semantic search

## The Problem

Building AI-powered applications today requires integrating multiple disparate systems:
- LLM providers with different APIs and capabilities
- Vector databases for semantic search
- Graph databases for knowledge representation
- Pipeline engines for data processing
- Agent frameworks for autonomous operation
- Approval and governance workflows

Each system has its own patterns, forcing developers to write brittle glue code.

## The Solution

Command provides a **single control plane** that orchestrates all these systems through:

1. **Unified Session Management** - Persistent, branching conversation contexts
2. **Multi-Provider LLM Routing** - Intelligent provider selection with fallback
3. **Approval Workflows** - Human-in-the-loop with auto-approval rules
4. **Cost Tracking** - Per-call attribution and daily aggregation
5. **Real-Time Events** - PubSub integration for LiveView UIs

## Component Ecosystem

```
                              ┌─────────────────────────────────────────────────────────────┐
                              │                         COMMAND                              │
                              │   Sessions | Agents | Workflows | Approvals | Costs | Indexes│
                              └─────────────────────────────────────────────────────────────┘
                                        │           │           │           │
              ┌─────────────────────────┼───────────┼───────────┼───────────┼──────────────────┐
              │                         │           │           │           │                  │
              ▼                         ▼           ▼           ▼           ▼                  ▼
    ┌──────────────────┐     ┌──────────────────┐  ┌──────────────────┐   ┌──────────────────────┐
    │    FLOWSTONE     │     │     SYNAPSE      │  │  ALTAR ECOSYSTEM │   │  PORTFOLIO ECOSYSTEM │
    │                  │     │                  │  │                  │   │                      │
    │ DAG Execution    │     │ Signal Bus       │  │ ADM (Contracts)  │   │ Core (Ports)         │
    │ Scatter/Gather   │     │ Agent Registry   │  │ LATER (Local)    │   │ Index (Adapters)     │
    │ Parallel Branches│     │ Workflow Engine  │  │ Altar.AI (Multi) │   │ Coder (Intelligence) │
    │ Signal Gates     │     │ Orchestrators    │  │                  │   │                      │
    │ Approvals        │     │ Specialists      │  │ FlowStone.AI     │   │                      │
    └──────────────────┘     └──────────────────┘  └──────────────────┘   └──────────────────────┘
```

## Key Integration Patterns

### 1. Pipeline Execution (FlowStone)
- Command defines workflow **templates** with DAG-based asset dependencies
- FlowStone executes with scatter/gather for fan-out, signal gates for webhooks
- FlowStone.AI bridges AI capabilities as injectable resources
- Command tracks costs, stores artifacts, manages approvals

### 2. Multi-Agent Orchestration (Synapse)
- Command defines **agent configurations** stored in database
- Synapse provides signal-based pub/sub for inter-agent communication
- Orchestrators coordinate specialists via classify/spawn/aggregate patterns
- Command tracks agent sessions, handles approvals, logs costs

### 3. Direct AI Interactions (Portfolio)
- Command uses Portfolio for **embedding, retrieval, and completion**
- Portfolio Core defines ports (behaviors) for all AI operations
- Portfolio Index provides production adapters (Pgvector, Neo4j, Gemini)
- Command's existing `Command.Portfolio` module already integrates this

### 4. Tool Execution (ALTAR)
- ALTAR ADM provides **universal tool contracts** (FunctionDeclaration, FunctionCall)
- Altar.AI provides **multi-provider abstraction** via protocols
- Command can normalize tool use across FlowStone assets and Synapse agents

## Architecture Layers

| Layer | Component | Responsibility |
|-------|-----------|----------------|
| **Control Plane** | Command | Sessions, workflows, approvals, costs, accounts |
| **Pipeline Execution** | FlowStone | DAG execution, scatter/gather, checkpoints |
| **Agent Coordination** | Synapse | Signal routing, agent lifecycle, workflows |
| **AI Abstraction** | Altar.AI | Multi-provider LLM/embedding with fallback |
| **Tool Contracts** | ALTAR ADM | Universal tool definitions and validation |
| **RAG Infrastructure** | Portfolio | Vector/graph storage, retrieval strategies |
| **Code Intelligence** | Portfolio Coder | Repository indexing, semantic code search |

## Benefits

1. **Unified Control** - Single point for configuration, monitoring, approvals
2. **Provider Flexibility** - Swap LLM providers without code changes
3. **Cost Visibility** - Track spending across all AI operations
4. **Enterprise Ready** - Approval workflows, audit logging, encrypted credentials
5. **Real-Time UIs** - PubSub events enable reactive LiveView dashboards
6. **Extensible** - Hexagonal architecture enables adding new adapters

## Implementation Status

| Component | Status | Integration |
|-----------|--------|-------------|
| Command Core | v0.1.0 | Complete |
| Portfolio Integration | Complete | `Command.Portfolio` module |
| FlowStone | v0.5.2 | Needs integration module |
| Synapse | Alpha | Needs integration module |
| ALTAR | v0.2.0 | Needs integration module |
| Altar.AI | v0.1.0 | Available via FlowStone.AI |
| Portfolio Coder | v0.4.0 | Optional enhancement |

## Next Steps

1. Create `Command.Pipelines` context integrating FlowStone
2. Create `Command.Orchestration` context integrating Synapse
3. Extend `Command.Agents` to use ALTAR tool contracts
4. Add telemetry handlers for unified observability
5. Build LiveView dashboard for monitoring all subsystems
