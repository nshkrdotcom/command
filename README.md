<p align="center">
  <img src="assets/command.svg" alt="Command" width="500">
</p>

<h1 align="center">Command</h1>

<p align="center">
  <strong>Core Library for AI Agent Orchestration</strong>
</p>

<p align="center">
  <a href="https://hex.pm/packages/command"><img src="https://img.shields.io/hexpm/v/command.svg?style=flat-square" alt="Hex Version"></a>
  <a href="https://hexdocs.pm/command"><img src="https://img.shields.io/badge/hex-docs-blue.svg?style=flat-square" alt="Hex Docs"></a>
  <a href="https://github.com/nshkrdotcom/command/actions"><img src="https://img.shields.io/github/actions/workflow/status/nshkrdotcom/command/ci.yml?branch=main&style=flat-square" alt="CI Status"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square" alt="License"></a>
</p>

<p align="center">
  <a href="#features">Features</a> |
  <a href="#installation">Installation</a> |
  <a href="#usage">Usage</a> |
  <a href="#architecture">Architecture</a> |
  <a href="#contributing">Contributing</a>
</p>

---

Command is an Elixir library for AI agent orchestration. It provides persistent session management, multi-provider LLM integration, tool approval workflows, DAG-based workflow execution, and RAG context management with pgvector-backed vector search.

## Features

- **Sessions**: Persistent, resumable agent work contexts with branching/forking support
- **Agent Calls**: Multi-provider LLM integration (Anthropic, OpenAI, Google, Cohere) with full lifecycle tracking
- **Unified AI Layer**: Altar.AI-powered generation, embeddings, classification, and streaming
- **Tool Uses**: Track and approve tool invocations with human-in-the-loop workflows
- **Policy Metadata**: Jido.Action.Tool schemas with approval_class, side_effects, cost, and capabilities
- **Workflows**: DAG-based orchestration with step dependencies and approval gates
- **Plan Runs**: Persisted plan executions linked to RunIndex and Lineage IDs
- **Pipelines**: FlowStone-backed pipeline templates and executions
- **Orchestration**: Synapse multi-agent runtimes with signal bridging
- **RunIndex + Lineage Sink**: Canonical run/step query layer plus LineageIR ingestion
- **Indexes**: RAG context management with pgvector-backed vector search via Portfolio ecosystem
- **Approvals**: Configurable auto-approval rules and manual review queues
- **Artifacts**: Versioned file/output storage with diff tracking
- **Cost Tracking**: Per-call cost tracking with daily summaries and provider/model breakdowns
- **Scheduling**: Cron, interval, and one-time job scheduling
- **Presence**: Multi-user awareness and activity audit logging
- **Phoenix Integration**: LiveView components and PubSub helpers for real-time UIs

## Installation

Add `command` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:command, "~> 0.1.0"}
  ]
end
```

## Configuration

### Database

Command requires PostgreSQL with the following extensions:

- `citext` - Case-insensitive text for emails
- `pg_trgm` - Trigram matching for full-text search
- `btree_gin` - GIN index support
- `vector` - pgvector for embeddings

Configure your database in `config/config.exs`:

```elixir
config :command, Command.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "command_dev"
```

### Encryption

Command encrypts sensitive data (API credentials) using Cloak. Configure the vault:

```elixir
config :command, Command.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1",
      key: Base.decode64!("your-32-byte-key-base64-encoded"),
      iv_length: 12
    }
  ]
```

Generate a production key:

```elixir
:crypto.strong_rand_bytes(32) |> Base.encode64()
```

### Portfolio Adapters

Command uses the Portfolio ecosystem for RAG/LLM operations. Register adapters in your application startup:

```elixir
# In your application.ex or config
PortfolioCore.register(:embedder, MyApp.Embedder, %{model: "text-embedding-3-small"})
PortfolioCore.register(:llm, MyApp.LLM, %{model: "claude-sonnet-4-20250514"})
PortfolioCore.register(:vector_store, MyApp.VectorStore, %{})
PortfolioCore.register(:retriever, MyApp.Retriever, %{})
```

### Altar.AI Profiles

Command integrates with `altar_ai` through `Command.AI`. Configure profiles like:

```elixir
config :command,
  default_profile: :openai,
  profiles: %{
    openai: [
      adapter: Altar.AI.Adapters.OpenAI,
      adapter_opts: [api_key: System.get_env("OPENAI_API_KEY")],
      model: "gpt-4o"
    ],
    fallback: [
      adapter: Altar.AI.Adapters.Fallback
    ]
  }
```

## Setup

```bash
# Install dependencies
mix deps.get

# Create and migrate database
mix ecto.setup

# Run tests
mix test

# Check code quality
mix lint
```

## Usage

### Users and API Credentials

```elixir
# Create a user
{:ok, user} = Command.Accounts.create_user(%{
  email: "dev@example.com",
  name: "Developer"
})

# Store an encrypted API credential
{:ok, credential} = Command.Accounts.create_api_credential(user, %{
  name: "My Anthropic Key",
  provider: "anthropic",
  api_key: "sk-ant-..."
})

# Retrieve and decrypt
{:ok, key} = Command.Accounts.get_decrypted_key(credential)
```

### Sessions and Messages

```elixir
# Create a session
{:ok, session} = Command.Sessions.create_session(user, %{
  name: "Code Review",
  purpose: "Review PR #123",
  default_agent: "claude",
  default_model: "claude-sonnet-4-20250514"
})

# Add messages
{:ok, _msg} = Command.Sessions.create_message(session, %{
  role: "user",
  content: "Please review the authentication module"
})

# Get conversation history
messages = Command.Sessions.list_messages(session)

# Fork a session at a specific message
{:ok, forked} = Command.Sessions.fork_session(session, message, %{
  name: "Alternative approach"
})

# Archive a session
{:ok, _} = Command.Sessions.archive_session(session)
```

### Agent Calls

```elixir
# Create an agent call
{:ok, call} = Command.Agents.create_agent_call(session, %{
  provider: "anthropic",
  model: "claude-sonnet-4-20250514",
  prompt_messages: [
    %{"role" => "user", "content" => "Review this code..."}
  ],
  system_prompt: "You are a code reviewer.",
  temperature: 0.7,
  max_tokens: 4096,
  tools_provided: ["bash", "read_file", "write_file"]
})

# Mark as streaming
{:ok, _} = Command.Agents.start_streaming(call)

# Complete the call
{:ok, completed} = Command.Agents.complete_agent_call(call, %{
  response_content: "The code looks good...",
  stop_reason: "end_turn",
  tokens_in: 150,
  tokens_out: 200,
  cost_cents: 5
})

# Handle failure
{:ok, failed} = Command.Agents.fail_agent_call(call, %{
  error_type: "rate_limit",
  error_message: "Too many requests"
})
```

### Altar.AI Calls

```elixir
{:ok, response} = Command.AI.generate("Summarize the workflow")
IO.puts(response.content)
```

### FlowStone Pipelines

```elixir
{:ok, template} =
  Command.Pipelines.create_template(%{
    name: "Daily Summary",
    config: %{module: "MyApp.Pipelines.Summary", final_asset: :report}
  })

{:ok, execution} = Command.Pipelines.run(template, "2026-01-05")
```

### Synapse Orchestration

```elixir
{:ok, config} = Command.Orchestration.register_agent(%{
  id: :coordinator,
  type: :orchestrator,
  signals: %{subscribes: [:review_request], emits: [:review_summary]}
})

{:ok, signal} = Command.Orchestration.publish(:review_request, %{review_id: "PR-123"})
```

### Tool Uses and Approvals

Tool schemas follow the `Jido.Action.Tool` format (for Jido actions, call `MyAction.to_tool()`).

```elixir
tool_schema = %{
  name: "bash",
  description: "Execute a shell command",
  parameters_schema: %{
    "type" => "object",
    "properties" => %{"command" => %{"type" => "string"}},
    "required" => ["command"]
  },
  policy: %{
    approval_class: "high",
    side_effects: ["filesystem"],
    cost: %{usd: 0.02},
    capabilities: ["shell"]
  }
}

# Create a tool use (approval derived from policy metadata)
{:ok, tool_use} = Command.Agents.create_tool_use(call, %{
  tool_schema: tool_schema,
  tool_use_id: "toolu_123",
  input: %{"command" => "git diff HEAD~1"}
})

# Approve the tool use
{:ok, approved} = Command.Agents.approve_tool_use(tool_use, %{
  approved_by_id: user.id
})

# Or deny it
{:ok, denied} = Command.Agents.deny_tool_use(tool_use, %{
  denial_reason: "Command too dangerous"
})

# Execute and complete
{:ok, _} = Command.Agents.start_tool_execution(approved)
{:ok, _} = Command.Agents.complete_tool_use(approved, %{
  output: "diff output...",
  exit_code: 0
})
```

### Approval Rules

```elixir
# Create an auto-approval rule
{:ok, rule} = Command.Approvals.create_approval_rule(user, %{
  name: "Auto-approve temp files",
  approval_type: "file_write",
  conditions: %{path_pattern: "/tmp/**", action: "create"},
  action: "approve",
  max_auto_approvals_per_hour: 100
})

# Match rules against an approval item
matching_rules = Command.Approvals.find_matching_rules(user, approval_item)
```

### Workflows

```elixir
# Create a workflow
{:ok, workflow} = Command.Workflows.create_workflow(user, %{
  name: "Code Review Pipeline",
  slug: "code-review",
  steps: [
    %{
      "id" => "analyze",
      "name" => "Analyze Code",
      "type" => "agent_call",
      "config" => %{"agent" => "claude", "prompt_template" => "Analyze: {{code}}"}
    },
    %{
      "id" => "review",
      "name" => "Generate Review",
      "type" => "agent_call",
      "depends_on" => ["analyze"]
    }
  ],
  input_schema: %{
    "pr_url" => %{"type" => "string", "required" => true}
  }
})

# Start a workflow run
{:ok, run} = Command.Workflows.start_workflow_run(workflow, user, %{
  input: %{"pr_url" => "https://github.com/..."},
  trigger_type: "manual"
})

# Progress through steps
{:ok, step} = Command.Workflows.start_step(run, "analyze")
{:ok, _} = Command.Workflows.complete_step(step, %{
  output: %{"analysis" => "..."}
})
```

### RunIndex + Lineage

```elixir
trace_id = Ecto.UUID.generate()

{:ok, run} =
  Command.RunIndex.create_run(%{
    runtime: "command",
    runtime_ref: "plan-run-1",
    status: "queued",
    session_id: session.id
  })

:ok =
  LineageIR.Sink.emit(%LineageIR.Event{
    type: "trace_start",
    trace_id: trace_id,
    source: "command",
    source_ref: "plan-run-1",
    payload: %LineageIR.Trace{id: trace_id, status: "running", started_at: DateTime.utc_now()}
  })

{:ok, _plan_run} =
  Command.PlanRuns.create_plan_run(user, %{
    session_id: session.id,
    plan_id: Ecto.UUID.generate(),
    status: "queued",
    run_index_run_id: run.id,
    trace_id: trace_id
  })
```

### RAG Indexes

```elixir
# Create an index
{:ok, index} = Command.Indexes.create_index(user, %{
  name: "My Codebase",
  slug: "my-codebase",
  source_type: "local_repo",
  source_config: %{
    path: "/home/user/project",
    include: ["**/*.ex", "**/*.exs"],
    exclude: ["deps/**", "_build/**"]
  },
  embedding_provider: "openai",
  embedding_model: "text-embedding-3-small"
})

# Add documents
{:ok, doc} = Command.Indexes.create_context_document(index, %{
  uri: "lib/my_app/core.ex",
  title: "Core Module",
  source_type: "file",
  content_hash: :crypto.hash(:sha256, content) |> Base.encode16()
})

# Add chunks with embeddings
{:ok, chunk} = Command.Indexes.create_context_chunk(doc, %{
  content: "defmodule MyApp.Core do...",
  chunk_index: 0,
  token_count: 150,
  embedding: embedding_vector,  # [float, ...]
  language: "elixir"
})

# Search for similar chunks
chunks = Command.Indexes.search_chunks(index, query_embedding, k: 10)
```

### Portfolio Integration

Command integrates with the Portfolio ecosystem for RAG operations:

```elixir
# Generate embeddings
{:ok, embedding} = Command.Portfolio.embed("text to embed")

# LLM completion
{:ok, response} = Command.Portfolio.complete([
  %{role: "user", content: "Hello"}
])

# RAG retrieval
{:ok, chunks} = Command.Portfolio.retrieve("search query", %{}, k: 10)

# Store in vector index
:ok = Command.Portfolio.store_embedding("my-index", "doc-1", embedding, %{source: "file.ex"})

# Search vectors
{:ok, results} = Command.Portfolio.search_vectors("my-index", query_embedding, 10)
```

### Cost Tracking

```elixir
# Record a cost
{:ok, _} = Command.Costs.record_cost(user, %{
  source_type: "agent_call",
  source_id: call.id,
  provider: "anthropic",
  service: "chat",
  model: "claude-sonnet-4-20250514",
  tokens_in: 150,
  tokens_out: 200,
  cost_cents: 5
})

# Get cost summaries
daily_cost = Command.Costs.get_daily_cost(user)
weekly_cost = Command.Costs.get_weekly_cost(user)
monthly_cost = Command.Costs.get_monthly_cost(user)

# Breakdown by provider/model
by_provider = Command.Costs.get_cost_by_provider(user, days: 7)
by_model = Command.Costs.get_cost_by_model(user, days: 30)

# Daily summaries
summaries = Command.Costs.list_daily_summaries(user, days: 30)
```

### Artifacts

```elixir
# Create an artifact
{:ok, artifact} = Command.Artifacts.create_artifact(user, %{
  name: "generated_code.ex",
  artifact_type: "code",
  storage_backend: "local",
  storage_path: "/tmp/artifacts/abc123.ex",
  language: "elixir",
  size_bytes: 1024
})

# Create a new version
{:ok, v2} = Command.Artifacts.create_artifact_version(artifact, %{
  name: "generated_code.ex",
  storage_backend: "local",
  storage_path: "/tmp/artifacts/def456.ex"
})

# Create a diff
{:ok, diff} = Command.Artifacts.create_diff(user, artifact, %{
  name: "Changes v1 to v2",
  diff_content: "@@ -1,3 +1,5 @@...",
  additions: 10,
  deletions: 2
})

# Get version history
history = Command.Artifacts.get_version_history(artifact)
```

### Scheduled Jobs

```elixir
# Create a scheduled job
{:ok, job} = Command.Scheduling.create_scheduled_job(user, %{
  job_type: "workflow",
  job_config: %{workflow_id: workflow.id, input: %{}},
  schedule_type: "cron",
  cron_expression: "0 9 * * *",
  timezone: "America/New_York"
})

# Or interval-based
{:ok, job} = Command.Scheduling.create_scheduled_job(user, %{
  job_type: "reindex",
  job_config: %{index_id: index.id},
  schedule_type: "interval",
  interval_seconds: 3600
})

# Manage job lifecycle
{:ok, _} = Command.Scheduling.pause_job(job)
{:ok, _} = Command.Scheduling.resume_job(job)
{:ok, _} = Command.Scheduling.cancel_job(job)
```

### Presence and Activity

```elixir
# Join a resource
{:ok, presence} = Command.Presence.join_resource(user, "session", session.id, %{
  client_id: "browser-tab-123",
  device_type: "desktop"
})

# Update status
{:ok, _} = Command.Presence.update_presence(presence, %{status: "editing"})

# Heartbeat
{:ok, _} = Command.Presence.heartbeat(presence)

# List who's present
present_users = Command.Presence.list_resource_presence("session", session.id)

# Log activity
{:ok, _} = Command.Presence.log_user_activity(
  user,
  "session.update",
  "session",
  session.id,
  %{changes: ["name"]}
)

# Query activity
activities = Command.Presence.list_user_activity(user, limit: 50)
```

### Phoenix LiveView Integration

```elixir
defmodule MyAppWeb.SessionLive do
  use MyAppWeb, :live_view
  import Command.Phoenix.LiveHelpers

  def mount(%{"id" => id}, _session, socket) do
    session = Command.Sessions.get_session!(id)

    socket =
      socket
      |> assign(:session, session)
      |> subscribe_to_session(id)
      |> subscribe_to_user(socket.assigns.current_user.id)
      |> stream(:messages, Command.Sessions.list_messages(session))

    {:ok, socket}
  end

  def handle_info(msg, socket) do
    case handle_command_event(msg, socket) do
      {:handled, socket} -> {:noreply, socket}
      {:unhandled, _msg} -> {:noreply, socket}
    end
  end
end
```

Use the included components:

```heex
<Command.Phoenix.Components.session_status status={@session.status} />
<Command.Phoenix.Components.cost_display cents={@session.total_cost_cents} />
<Command.Phoenix.Components.token_usage
  tokens_in={@call.tokens_in}
  tokens_out={@call.tokens_out}
/>
<Command.Phoenix.Components.approval_status status={@approval.status} />
```

### PubSub Events

Subscribe to real-time updates:

```elixir
# Session events
Command.PubSub.subscribe("session:#{session_id}")
Command.PubSub.subscribe("session:#{session_id}:messages")
Command.PubSub.subscribe("session:#{session_id}:agent_calls")

# User events
Command.PubSub.subscribe("user:#{user_id}:sessions")
Command.PubSub.subscribe("user:#{user_id}:approvals")
Command.PubSub.subscribe("user:#{user_id}:costs")

# Handle events
def handle_info({Command.PubSub, :message_created, message}, socket) do
  {:noreply, stream_insert(socket, :messages, message)}
end
```

## Architecture

Command follows an Elixir contexts pattern with multiple bounded contexts:

```
lib/
├── command.ex                    # Main module, delegates to contexts
├── command/
│   ├── application.ex            # OTP application
│   ├── repo.ex                   # Ecto repository
│   ├── repo/
│   │   └── paginator.ex          # Cursor-based pagination
│   ├── vault.ex                  # Cloak vault for encryption
│   ├── encrypted_binary.ex       # Ecto type for encrypted fields
│   ├── pubsub.ex                 # PubSub wrapper
│   │
│   ├── accounts.ex               # User management context
│   ├── accounts/
│   │   ├── user.ex               # User schema
│   │   └── api_credential.ex     # Encrypted API key schema
│   │
│   ├── sessions.ex               # Session management context
│   ├── sessions/
│   │   ├── session.ex            # Session schema (branchable)
│   │   └── message.ex            # Conversation message schema
│   │
│   ├── agents.ex                 # Agent execution context
│   ├── agents/
│   │   ├── agent_call.ex         # LLM API call schema
│   │   └── tool_use.ex           # Tool invocation schema
│   │
│   ├── workflows.ex              # Workflow orchestration context
│   ├── workflows/
│   │   ├── workflow.ex           # Workflow definition (DAG)
│   │   ├── workflow_run.ex       # Workflow execution instance
│   │   └── workflow_step.ex      # Step execution record
│   │
│   ├── indexes.ex                # RAG index context
│   ├── indexes/
│   │   ├── index.ex              # Index configuration
│   │   ├── context_document.ex   # Source document
│   │   └── context_chunk.ex      # Embedded chunk (pgvector)
│   │
│   ├── approvals.ex              # Approval workflow context
│   ├── approvals/
│   │   ├── approval_item.ex      # Approval queue item
│   │   └── approval_rule.ex      # Auto-approval rule
│   │
│   ├── plan_runs.ex              # Plan run persistence
│   ├── plan_runs/
│   │   └── plan_run.ex           # Plan run schema
│   │
│   ├── run_index.ex              # RunIndex persistence
│   ├── run_index/
│   │   ├── run.ex                # RunIndex run schema
│   │   └── step.ex               # RunIndex step schema
│   │
│   ├── artifacts.ex              # File/output management context
│   ├── artifacts/
│   │   └── artifact.ex           # Versioned artifact schema
│   │
│   ├── costs.ex                  # Cost tracking context
│   ├── costs/
│   │   ├── cost_record.ex        # Individual cost entry
│   │   └── cost_daily_summary.ex # Aggregated daily summary
│   │
│   ├── scheduling.ex             # Job scheduling context
│   ├── scheduling/
│   │   └── scheduled_job.ex      # Scheduled job schema
│   │
│   ├── presence.ex               # Presence/activity context
│   ├── presence/
│   │   ├── presence_record.ex    # User presence tracking
│   │   └── activity_log.ex       # Audit log schema
│   │
│   ├── portfolio.ex              # Portfolio ecosystem integration
│   ├── policy.ex                 # Policy metadata helpers
│   ├── flowstone/
│   │   └── approval_bridge.ex    # Flowstone approval bridge
│   │
│   └── phoenix/                  # Phoenix integration
│       ├── components.ex         # HEEx components
│       └── live_helpers.ex       # LiveView helpers
│
├── lineage_ir/                   # Lineage sink + schemas
│   ├── event.ex                  # Lineage event envelope
│   ├── trace.ex                  # Trace schema
│   ├── span.ex                   # Span schema
│   ├── artifact.ex               # Artifact schema
│   ├── provenance_edge.ex        # Edge schema
│   └── sink/                     # Sink behaviour + adapter
```

## Database Schema

Command uses 35 tables across 13 domains. See [SCHEMA.md](SCHEMA.md) for complete documentation.

| Domain | Tables |
|--------|--------|
| Accounts | `users`, `api_credentials` |
| Sessions | `sessions`, `messages` |
| Agents | `agent_calls`, `tool_uses` |
| Workflows | `workflows`, `workflow_runs`, `workflow_steps` |
| Indexes | `indexes`, `context_documents`, `context_chunks` |
| Approvals | `approval_items`, `approval_rules` |
| Plan Runs | `plan_runs` |
| RunIndex | `run_index.runs`, `run_index.steps` |
| Lineage | `lineage.traces`, `lineage.spans`, `lineage.artifacts`, `lineage.edges`, `lineage.events` |
| Artifacts | `artifacts` |
| Costs | `cost_records`, `cost_daily_summaries`, `ai_costs` |
| Scheduling | `scheduled_jobs` |
| Presence | `presence_records`, `activity_logs` |
| Pipelines | `command_pipelines`, `command_pipeline_runs`, `command_pipeline_ai_operations` |
| Orchestration | `command_agent_configs`, `command_agent_sessions` |

All tables use UUIDs for distributed-friendly operation.

## Dependencies

Command builds on:

- **Ecto SQL** - Database layer with PostgreSQL
- **Phoenix** - Web framework integration
- **Phoenix LiveView** - Real-time UI components
- **Phoenix PubSub** - Event broadcasting
- **Cloak Ecto** - Field-level encryption
- **Portfolio Core/Index** - Hexagonal RAG/LLM integration
- **Oban** (optional) - Background job processing

## License

MIT License - see LICENSE file for details.

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Run tests and linting (`mix test && mix lint`)
4. Commit your changes (`git commit -m 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request
