# Command Workbench

A complete example Phoenix application demonstrating Command library integration.

## Features

- **Session Management**: Create, browse, and interact with AI agent sessions
- **Real-time Updates**: LiveView with PubSub for live message streaming
- **Tool Approvals**: Human-in-the-loop approval workflow for agent tool calls
- **Workflow Builder**: Visual workflow creation and execution monitoring
- **Cost Dashboard**: Track API costs by provider, model, and time period
- **Presence Tracking**: See who's viewing/editing resources

## Quick Start

```bash
# Install dependencies
mix setup

# Start the server
mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000).

## Architecture

### Phoenix + Command Integration

This app demonstrates the recommended patterns for integrating Command with Phoenix:

#### 1. PubSub Configuration

```elixir
# config/config.exs
config :command,
  pubsub: CommandWorkbench.PubSub,
  pubsub_prefix: "command"
```

#### 2. Subscribing in LiveView

```elixir
def mount(%{"id" => id}, _session, socket) do
  if connected?(socket) do
    Command.PubSub.subscribe("session:#{id}")
    Command.PubSub.subscribe("session:#{id}:messages")
  end
  # ...
end
```

#### 3. Handling Events

```elixir
def handle_info({Command.PubSub, :message_created, message}, socket) do
  {:noreply, stream_insert(socket, :messages, message)}
end
```

#### 4. Forms with Changesets

```elixir
# Command exposes changeset functions for form integration
changeset = Command.Sessions.change_session(session, params)

# Use in LiveView
<.simple_form for={@form} phx-change="validate" phx-submit="save">
  <.input field={@form[:name]} type="text" label="Name" />
</.simple_form>
```

### Directory Structure

```
lib/
├── command_workbench/
│   └── application.ex          # Starts PubSub
└── command_workbench_web/
    ├── router.ex               # Routes with demo user assignment
    ├── components/
    │   ├── core_components.ex  # Phoenix components
    │   └── command_components.ex # Command-specific components
    └── live/
        ├── dashboard_live.ex   # Main dashboard
        ├── session_live/       # Session CRUD + conversation
        ├── approval_live/      # Approval queue
        ├── workflow_live/      # Workflow management
        └── cost_live/          # Cost tracking
```

## Key Patterns

### Streaming Updates

Sessions use Phoenix streams for efficient list updates:

```elixir
def mount(_params, _session, socket) do
  sessions = Command.Sessions.list_sessions(user)
  {:ok, stream(socket, :sessions, sessions)}
end

def handle_info({Command.PubSub, :session_created, session}, socket) do
  {:noreply, stream_insert(socket, :sessions, session, at: 0)}
end
```

### Tool Approval Workflow

The approval flow demonstrates human-in-the-loop patterns:

1. Agent requests tool use (e.g., bash command)
2. Tool use created from a `Jido.Action.Tool` schema with policy metadata
3. PubSub broadcasts to session subscribers
4. LiveView shows approval UI
5. User approves/denies
6. Tool executes (if approved)
7. Result sent back to agent

Policy metadata (approval_class, side_effects, cost, capabilities) drives the approval queue.

### Cost Tracking

Costs are automatically tracked when agent calls complete:

```elixir
# In your agent integration
def complete_call(call, response) do
  Command.Agents.complete_agent_call(call, %{
    response_content: response.content,
    tokens_in: response.usage.input_tokens,
    tokens_out: response.usage.output_tokens,
    cost_cents: calculate_cost(response)
  })

  # Cost is automatically recorded and broadcast
end
```

## Customization

### Styling

This example uses Tailwind CSS. Customize in:
- `assets/tailwind.config.js`
- `lib/command_workbench_web/components/`

### Adding Providers

To add a new LLM provider:

1. Create an API credential
2. Implement the adapter
3. Register in portfolio_core

### Authentication

This example uses a simple demo user. For production:

1. Add `mix phx.gen.auth`
2. Update router pipelines
3. Replace `assign_current_user` plug

## Testing

```bash
mix test
```

See `test/command_workbench_web/live/` for LiveView test examples.

## Deployment

Standard Phoenix deployment. Key considerations:

1. Set `SECRET_KEY_BASE`
2. Set `DATABASE_URL`
3. Configure Command vault key for credential encryption
4. Set up PubSub for distributed deployments (Redis adapter recommended)

## License

MIT
