# Integration Concerns and Architectural Decisions

**Date:** 2026-01-01
**Document:** Detailed concerns, trade-offs, and decisions for Command + portfolio_* integration

---

## Critical Concerns

### 1. No Compile-Time Adapter Validation

**Problem:** portfolio_core's Registry accepts any module without verifying it implements the correct behavior. Mis-wired adapters only fail at runtime.

**Example of the Problem:**
```elixir
# This will succeed at registration time
PortfolioCore.Registry.register(:vector_store, SomeRandomModule, [])

# But fail later when called
{adapter, config} = PortfolioCore.adapter!(:vector_store)
adapter.search(config, ...)  # ** (UndefinedFunctionError)
```

**Decision:** Add validation in Command.Application.start/2

```elixir
defmodule Command.Application do
  def start(_type, _args) do
    # Validate required adapters before starting
    validate_required_adapters!()

    children = [...]
    Supervisor.start_link(children, opts)
  end

  defp validate_required_adapters! do
    required = [:vector_store, :embedder, :llm, :retriever]

    for port <- required do
      case PortfolioCore.adapter(port) do
        nil ->
          raise "Missing required adapter: #{port}"
        {module, _config} ->
          # Verify module implements expected callbacks
          validate_adapter_callbacks!(port, module)
      end
    end
  end

  defp validate_adapter_callbacks!(:vector_store, module) do
    unless function_exported?(module, :search, 4) do
      raise "Adapter #{module} does not implement VectorStore.search/4"
    end
  end
  # ... other ports
end
```

---

### 2. Single Global Registry (No Multi-Tenancy)

**Problem:** PortfolioCore.Registry is a single ETS table per BEAM node. All applications share the same adapter registrations.

**Implications:**
- Cannot run tests with different adapter configurations in parallel
- Cannot have per-user or per-tenant adapter routing
- All Command instances on a node share the same adapters

**Decision:** Accept this limitation for now.

**Rationale:**
- Command's use case is single-tenant (one deployment = one configuration)
- Multi-tenancy can be added later via adapter wrapper that routes based on context
- Test isolation can use Mox to replace adapters per-test

**Future Option:** If multi-tenancy needed, create Command.AdapterRouter:
```elixir
defmodule Command.AdapterRouter do
  def get_adapter(port, %{tenant_id: tenant_id}) do
    # Look up tenant-specific configuration
    config = get_tenant_config(tenant_id, port)
    {adapter_module, config}
  end
end
```

---

### 3. Agentic RAG Can Get Stuck

**Problem:** PortfolioIndex.RAG.Strategies.Agentic uses an iterative loop that can hang if:
- LLM doesn't produce valid tool calls
- Tool execution fails silently
- Agent decides it needs "more information" indefinitely

**Code Path:**
```elixir
# In agentic.ex
defp agent_loop(state, iteration) when iteration < state.max_iterations do
  # No external timeout! Just iteration count
  case analyze_and_execute(state) do
    {:continue, new_state} -> agent_loop(new_state, iteration + 1)
    {:done, result} -> {:ok, result}
  end
end
```

**Decision:** Wrap Agentic RAG calls with Task.await timeout

```elixir
defmodule Command.RAG do
  @agentic_timeout :timer.minutes(2)

  def retrieve_with_agent(query, opts) do
    task = Task.async(fn ->
      {retriever, config} = PortfolioCore.adapter!(:retriever)
      retriever.retrieve(config, query, opts)
    end)

    case Task.yield(task, @agentic_timeout) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end
end
```

---

### 4. GraphRAG Is Incomplete

**Problem:** The GraphRAG strategy exists but community detection is a stub:

```elixir
# In community_detector.ex
def detect_communities(graph_id, opts) do
  # TODO: Implement actual community detection algorithm
  # Currently returns empty communities
  {:ok, []}
end
```

**Decision:** Do not use GraphRAG until upstream completes it.

**Alternative:** Use Hybrid RAG strategy which is fully implemented.

---

### 5. Dynamic SQL Tables (Pgvector)

**Problem:** Pgvector adapter creates tables dynamically:

```elixir
def create_index(config, index_id, opts) do
  table_name = "vectors_#{index_id}"  # Dynamic!

  Repo.query!("""
    CREATE TABLE #{table_name} (
      id VARCHAR(255) PRIMARY KEY,
      embedding vector(#{dimensions}),
      ...
    )
  """)
end
```

**Risks:**
- SQL injection if index_id not sanitized (mitigated: regex validation exists)
- Tables not tracked by Ecto migrations
- Difficult to manage in production (orphaned tables)

**Decision:** Accept but add guardrails:

```elixir
defmodule Command.Indexes do
  @index_id_pattern ~r/^[a-z0-9_]+$/

  def create_index(name, opts) do
    unless Regex.match?(@index_id_pattern, name) do
      raise ArgumentError, "Invalid index name: #{name}"
    end

    # Track in Command's metadata table
    {:ok, _} = create_index_record(name, opts)

    # Create via portfolio
    {store, config} = PortfolioCore.adapter!(:vector_store)
    store.create_index(config, name, opts)
  end
end
```

---

### 6. LLM JSON Parsing Is Fragile

**Problem:** Agentic RAG extracts structured data from LLM responses using regex:

```elixir
defp extract_json(text) do
  case Regex.run(~r/```json\s*(.*?)\s*```/s, text) do
    [_, json] -> Jason.decode(json)
    nil -> {:error, :no_json_found}
  end
end
```

**Risks:**
- LLM might not format JSON correctly
- Regex might miss valid JSON
- No fallback strategies

**Decision:** Add validation layer in Command:

```elixir
defmodule Command.LLM do
  def complete_with_json(messages, schema, opts) do
    {llm, config} = PortfolioCore.adapter!(:llm)

    # Add JSON instruction to prompt
    messages = append_json_instruction(messages, schema)

    case llm.complete(config, messages, opts) do
      {:ok, response} ->
        case extract_and_validate_json(response.content, schema) do
          {:ok, data} -> {:ok, data}
          {:error, _} -> retry_with_correction(messages, response, schema)
        end
      error -> error
    end
  end
end
```

---

### 7. Fixed Embedding Dimensions

**Problem:** portfolio_index's chunks table hardcodes 384 dimensions:

```elixir
# In migration
field :embedding, Pgvector.Ecto.Vector, size: 384
```

This matches bge-small-en-v1.5 but not:
- OpenAI text-embedding-3-small (1536)
- OpenAI text-embedding-3-large (3072)
- Gemini (configurable 128-3072)

**Decision:** Use portfolio_index's dynamic vector tables instead of chunks table.

```elixir
# Don't use portfolio_chunks table for embeddings
# Instead, use Pgvector adapter's dynamic tables

# Create index with correct dimensions
{store, config} = PortfolioCore.adapter!(:vector_store)
store.create_index(config, "my_index", dimensions: 1536, metric: :cosine)

# Store with full dimensions
store.store(config, "my_index", chunk_id, embedding_1536, metadata)
```

---

## Architectural Decisions

### Decision 1: Command Does NOT Define Its Own Ports

**Options Considered:**
1. Define Command.Ports.* behaviors, write adapters that wrap portfolio
2. Use PortfolioCore.Ports.* directly

**Decision:** Option 2 - Use PortfolioCore ports directly.

**Rationale:**
- No benefit to indirection layer
- portfolio_core's ports are well-designed
- Reduces code duplication
- Enables ecosystem compatibility

---

### Decision 2: Shared Ecto Repo

**Options Considered:**
1. Command.Repo and PortfolioIndex.Repo (separate)
2. Command.Repo only (shared)
3. Configurable repo per library

**Decision:** Option 2 - Share Command.Repo.

**Rationale:**
- Simpler configuration
- Single connection pool
- Enables transactions across both

**Configuration:**
```yaml
# portfolio_manifest.yaml
adapters:
  vector_store:
    adapter: PortfolioIndex.Adapters.Pgvector
    config:
      repo: Command.Repo  # Use Command's repo
```

---

### Decision 3: Separate Schema Namespaces

**Tables owned by Command:**
- sessions
- messages
- agent_calls
- tool_uses
- cost_records
- cost_daily_summaries
- approval_items
- approval_rules
- workflows
- workflow_runs
- workflow_steps
- artifacts
- users
- api_credentials
- presence_records
- activity_logs
- scheduled_jobs

**Tables owned by portfolio_index:**
- portfolio_collections
- portfolio_documents
- portfolio_chunks
- vector_index_registry
- vectors_* (dynamic)
- documents (document store)
- evaluation_runs

**No conflicts.** Different purposes, different prefixes.

---

### Decision 4: Telemetry Unification

Both libraries emit telemetry. Consolidate handlers:

```elixir
# Command.Telemetry
def attach_handlers do
  # Command events
  :telemetry.attach_many("command", [
    [:command, :agent_call, :start],
    [:command, :agent_call, :stop],
    [:command, :tool_use, :start],
    [:command, :tool_use, :stop]
  ], &handle_command_event/4, nil)

  # Portfolio events
  :telemetry.attach_many("portfolio", [
    [:portfolio_core, :adapter, :call],
    [:portfolio_index, :embedding, :complete],
    [:portfolio_index, :search, :complete]
  ], &handle_portfolio_event/4, nil)
end
```

---

### Decision 5: Error Handling Strategy

**Portfolio errors bubble up.** Command wraps them:

```elixir
defmodule Command.Agents do
  def execute_agent_call(session, params) do
    with {:ok, call} <- create_agent_call(session, params),
         {:ok, context} <- get_rag_context(params),
         {:ok, response} <- call_llm(params, context) do
      complete_agent_call(call, response)
    else
      {:error, %Postgrex.Error{} = e} ->
        fail_agent_call(call, "Database error: #{inspect(e)}")

      {:error, :rate_limited} ->
        fail_agent_call(call, "Rate limited, retry later")

      {:error, reason} ->
        fail_agent_call(call, "Error: #{inspect(reason)}")
    end
  end
end
```

---

## Integration Checklist

### Phase 1: Dependencies (Day 1)
- [ ] Add portfolio_core to mix.exs
- [ ] Add portfolio_index to mix.exs
- [ ] Remove duplicate pgvector dep
- [ ] Run mix deps.get
- [ ] Verify compilation

### Phase 2: Configuration (Day 1)
- [ ] Create config/portfolio_manifest.yaml
- [ ] Add manifest path to config/config.exs
- [ ] Set up environment variables for API keys
- [ ] Verify manifest loads at startup

### Phase 3: Code Changes (Day 2)
- [ ] Delete lib/command/indexes/index.ex
- [ ] Delete lib/command/indexes/context_document.ex
- [ ] Delete lib/command/indexes/context_chunk.ex
- [ ] Rewrite lib/command/indexes.ex as thin wrapper
- [ ] Update any code that imports deleted modules

### Phase 4: Validation (Day 2)
- [ ] Add adapter validation to Application.start
- [ ] Add integration tests for adapter calls
- [ ] Verify existing tests still pass
- [ ] Run full test suite

### Phase 5: Documentation (Day 3)
- [ ] Update README with architecture diagram
- [ ] Document manifest configuration
- [ ] Document how to add new adapters
- [ ] Update SCHEMA.md if needed

---

## Open Questions

1. **Should Command vendor portfolio_* or use hex deps?**
   - Recommendation: Hex deps for now, vendor if need to patch

2. **How to handle portfolio_index migrations?**
   - Recommendation: Run both Command and portfolio_index migrations

3. **Should Command expose portfolio adapters to users?**
   - Recommendation: Yes, via Command.Adapters module that re-exports

4. **What about flowstone/synapse integration?**
   - Recommendation: Separate integration, similar pattern

---

## Conclusion

The integration is feasible with manageable risks. Key decisions:

1. Use PortfolioCore ports directly (no Command.Ports)
2. Share Command.Repo with portfolio_index
3. Validate adapters at startup
4. Wrap Agentic RAG with timeouts
5. Avoid GraphRAG until complete
6. Use dynamic vector tables for flexible dimensions

Estimated effort: **2-3 days** for basic integration, **1 week** for full testing and documentation.
