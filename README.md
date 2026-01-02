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
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#usage">Usage</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#contributing">Contributing</a>
</p>

---

Command is the core library for AI agent orchestration. It provides a unified workbench for running, tracking, and orchestrating AI agents against your data and code.

## Features

- **Sessions**: Persistent, resumable contexts for agent work with branching support
- **Agent Calls**: Multi-provider LLM integration (Anthropic, OpenAI, Google) with full lifecycle tracking
- **Tool Uses**: Track and approve tool invocations with human-in-the-loop workflows
- **Workflows**: DAG-based orchestration with step dependencies and approval gates
- **Indexes**: RAG context management with pgvector-backed vector search
- **Approvals**: Configurable auto-approval rules and manual review queues
- **Cost Tracking**: Detailed per-call cost tracking with daily summaries
- **Presence**: Multi-user awareness and activity logging

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

- `citext` - Case-insensitive text
- `pg_trgm` - Trigram matching for search
- `btree_gin` - GIN index support
- `vector` - pgvector for embeddings

Configure your database in `config/dev.exs`:

```elixir
config :command, Command.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "command_dev"
```

### Encryption

Command encrypts sensitive data (API credentials) using Cloak. Configure the vault key:

```elixir
# Development (DO NOT use in production)
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

## Setup

```bash
# Install dependencies
mix deps.get

# Create and migrate database
mix ecto.setup

# Run tests
mix test

# Check code quality
mix credo --strict
mix dialyzer
```

## Usage

### Creating a User

```elixir
{:ok, user} = Command.Accounts.create_user(%{
  email: "dev@example.com",
  name: "Developer"
})
```

### Managing Sessions

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
history = Command.Sessions.get_conversation_history(session)

# Fork a session at a specific message
{:ok, forked} = Command.Sessions.fork_session(session, message, %{
  name: "Alternative approach"
})
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
  temperature: 0.7,
  max_tokens: 4096
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
```

### Tool Uses and Approvals

```elixir
# Create a tool use
{:ok, tool_use} = Command.Agents.create_tool_use(call, %{
  tool_name: "bash",
  tool_use_id: "toolu_123",
  input: %{"command" => "git diff HEAD~1"},
  requires_approval: true
})

# Approve the tool use
{:ok, approved} = Command.Agents.approve_tool_use(tool_use, %{
  approved_by_id: user.id
})

# Execute and complete
{:ok, _} = Command.Agents.start_tool_execution(approved)
{:ok, _} = Command.Agents.complete_tool_use(approved, %{
  output: "diff output...",
  exit_code: 0
})
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
      "config" => %{"agent" => "claude"}
    },
    %{
      "id" => "review",
      "name" => "Generate Review",
      "type" => "agent_call",
      "depends_on" => ["analyze"]
    }
  ]
})

# Start a workflow run
{:ok, run} = Command.Workflows.start_workflow_run(workflow, user, %{
  input: %{"pr_url" => "https://github.com/..."},
  trigger_type: "manual"
})
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
by_provider = Command.Costs.get_cost_by_provider(user, days: 7)
```

## Architecture

Command follows a hexagonal architecture:

```
lib/
├── command.ex                    # Main module
├── command/
│   ├── repo.ex                   # Ecto repository
│   ├── vault.ex                  # Cloak vault for encryption
│   │
│   ├── accounts.ex               # Accounts context
│   ├── accounts/
│   │   ├── user.ex              # User schema
│   │   └── api_credential.ex    # API credential schema
│   │
│   ├── sessions.ex               # Sessions context
│   ├── sessions/
│   │   ├── session.ex           # Session schema
│   │   └── message.ex           # Message schema
│   │
│   ├── agents.ex                 # Agents context
│   ├── agents/
│   │   ├── agent_call.ex        # Agent call schema
│   │   └── tool_use.ex          # Tool use schema
│   │
│   ├── workflows.ex              # Workflows context
│   ├── workflows/
│   │   ├── workflow.ex          # Workflow definition schema
│   │   ├── workflow_run.ex      # Workflow run schema
│   │   └── workflow_step.ex     # Workflow step schema
│   │
│   ├── indexes.ex                # Indexes context
│   ├── indexes/
│   │   ├── index.ex             # Index configuration schema
│   │   ├── context_document.ex  # Document schema
│   │   └── context_chunk.ex     # Chunk with embedding schema
│   │
│   ├── approvals.ex              # Approvals context
│   ├── approvals/
│   │   ├── approval_item.ex     # Approval queue item schema
│   │   └── approval_rule.ex     # Auto-approval rule schema
│   │
│   ├── artifacts.ex              # Artifacts context
│   ├── artifacts/
│   │   └── artifact.ex          # Versioned artifact schema
│   │
│   ├── costs.ex                  # Costs context
│   ├── costs/
│   │   ├── cost_record.ex       # Individual cost record
│   │   └── cost_daily_summary.ex # Daily aggregation
│   │
│   ├── scheduling.ex             # Scheduling context
│   ├── scheduling/
│   │   └── scheduled_job.ex     # Scheduled job schema
│   │
│   ├── presence.ex               # Presence context
│   └── presence/
│       ├── presence_record.ex   # User presence schema
│       └── activity_log.ex      # Activity audit log schema
```

## Database Schema

Command uses 21 tables across these domains:

| Domain | Tables |
|--------|--------|
| Accounts | `users`, `api_credentials` |
| Sessions | `sessions`, `messages` |
| Agents | `agent_calls`, `tool_uses` |
| Workflows | `workflows`, `workflow_runs`, `workflow_steps` |
| Indexes | `indexes`, `context_documents`, `context_chunks` |
| Approvals | `approval_items`, `approval_rules` |
| Artifacts | `artifacts` |
| Costs | `cost_records`, `cost_daily_summaries` |
| Scheduling | `scheduled_jobs` |
| Presence | `presence_records`, `activity_logs` |

All tables use UUIDs for distributed-friendly operation.

## Integration with NSAI Stack

Command is designed to integrate with the NSAI ecosystem:

- **portfolio_manager**: Use for RAG queries and multi-provider routing
- **portfolio_coder**: Use for code indexing and semantic search
- **claude_agent_sdk**: LLM provider for Anthropic
- **codex_sdk**: LLM provider for OpenAI
- **gemini_ex**: LLM provider for Google
- **flowstone**: Workflow orchestration engine

Example integration:

```elixir
# Using portfolio_manager for RAG
{:ok, context} = PortfolioManager.RAG.search(query, k: 5, index_id: "my_codebase")

# Inject into Command agent call
{:ok, call} = Command.Agents.create_agent_call(session, %{
  provider: "anthropic",
  model: "claude-sonnet-4-20250514",
  prompt_messages: [
    %{"role" => "system", "content" => format_context(context)},
    %{"role" => "user", "content" => query}
  ]
})
```

## License

MIT License - see LICENSE file for details.

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Run tests and linting (`mix test && mix credo --strict`)
4. Commit your changes (`git commit -m 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request
