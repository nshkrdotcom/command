# Portfolio Core/Index Technical Assessment for Command Integration

**Date:** 2026-01-01
**Purpose:** Critical analysis of portfolio_core and portfolio_index for suitability as Command's adapter layer
**Verdict:** **SUITABLE WITH CAVEATS** - Recommended for integration with specific mitigations

---

## Executive Summary

| Aspect | portfolio_core | portfolio_index | Fit for Command |
|--------|---------------|-----------------|-----------------|
| **Architecture** | Excellent | Good | YES |
| **Production Readiness** | 8/10 | 7/10 | YES (with hardening) |
| **API Stability** | Stable | Stable | YES |
| **Integration Complexity** | Low | Medium | ACCEPTABLE |
| **Risk Level** | Low | Medium | ACCEPTABLE |

**Recommendation:** Integrate both libraries. Command should depend on portfolio_core for port definitions and portfolio_index for adapter implementations. Delete Command's duplicated indexes/ code.

---

## Part 1: portfolio_core Analysis

### 1.1 What It Provides

portfolio_core is a **hexagonal architecture foundation** providing:

- **21 Port Definitions** (Elixir behaviors) - contracts for adapters
- **ETS-Based Registry** - runtime adapter lookup with health tracking
- **Manifest Engine** - YAML-based configuration with env var expansion
- **Telemetry Integration** - observability hooks

### 1.2 Port Inventory

| Category | Ports | Relevance to Command |
|----------|-------|---------------------|
| **Storage** | VectorStore, VectorStore.Hybrid, GraphStore, GraphStore.Community, DocumentStore | HIGH - replaces Command.Indexes |
| **AI** | Embedder, LLM, Chunker | HIGH - needed for agent calls |
| **Retrieval** | Retriever, Reranker | HIGH - RAG context |
| **Query Processing** | QueryRewriter, QueryExpander, QueryDecomposer, CollectionSelector | MEDIUM - optional enhancement |
| **Infrastructure** | Router, Cache, Pipeline | MEDIUM - optional |
| **Orchestration** | Agent, Tool | LOW - Command has its own tracking |
| **Evaluation** | Evaluation, RetrievalMetrics | LOW - optional |

### 1.3 Registry Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    ETS Table: :portfolio_core_adapters       │
│                                                              │
│  Key (atom)          Value (map)                            │
│  ─────────────────   ─────────────────────────────────────  │
│  :vector_store   →   %{module: Pgvector, config: [...],     │
│                        healthy: true, call_count: 1234}     │
│  :embedder       →   %{module: Gemini, config: [...]}       │
│  :llm            →   %{module: Claude, config: [...]}       │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ PortfolioCore.adapter!(:vector_store)
                              ▼
                    {PortfolioIndex.Adapters.Pgvector, config}
```

**Key Properties:**
- Thread-safe concurrent access (ETS read_concurrency + write_concurrency)
- Health tracking per adapter (mark_healthy/mark_unhealthy)
- Call metrics (call_count, error_count, error_rate)
- Single global instance per BEAM node

### 1.4 Strengths

1. **Clean Separation of Concerns**
   - Ports define WHAT (behaviors)
   - Adapters define HOW (implementations)
   - Registry provides WHERE (lookup)

2. **Well-Typed APIs**
   - Comprehensive @type and @spec definitions
   - Dialyzer-friendly

3. **Flexible Configuration**
   - YAML manifest with env var expansion
   - Runtime adapter registration
   - Hot-reload support

4. **Observable**
   - Telemetry events on adapter operations
   - Built-in metrics tracking

### 1.5 Concerns & Mitigations

| Concern | Severity | Mitigation |
|---------|----------|------------|
| **No compile-time adapter validation** - Registry accepts any module | Medium | Add runtime validation in Command's startup |
| **Single global registry** - No multi-tenancy | Low | Acceptable for Command's use case |
| **Hot-reload race conditions** - Clients may see inconsistent state | Low | Don't hot-reload in production |
| **No adapter dependency resolution** - Missing deps fail at runtime | Medium | Validate required adapters at Command startup |

### 1.6 Code Quality: 8/10

- Well-documented with examples
- Consistent error handling patterns
- Good test coverage
- Minor: Some optional callbacks inconsistently documented

---

## Part 2: portfolio_index Analysis

### 2.1 What It Provides

portfolio_index provides **production-ready adapter implementations**:

- **22+ Adapter Modules** implementing portfolio_core ports
- **5 RAG Strategies** (Hybrid, Agentic, GraphRAG, Self-RAG)
- **Broadway Pipelines** for streaming ingestion
- **Database Schemas** for persistence

### 2.2 Adapter Inventory

#### Storage Adapters
| Adapter | Port | Backend | Production Ready |
|---------|------|---------|------------------|
| Pgvector | VectorStore | PostgreSQL + pgvector | YES |
| Memory (HNSW) | VectorStore | In-memory HNSWLib | DEV ONLY |
| Neo4j | GraphStore | Neo4j Bolt | YES |
| Postgres | DocumentStore | PostgreSQL | YES |

#### AI Adapters
| Adapter | Port | Provider | Production Ready |
|---------|------|----------|------------------|
| OpenAI Embedder | Embedder | OpenAI API | YES |
| Gemini Embedder | Embedder | Google AI | YES |
| Bumblebee | Embedder | Local (Nx) | YES |
| OpenAI LLM | LLM | OpenAI API | YES |
| Anthropic LLM | LLM | Anthropic API | YES |
| Gemini LLM | LLM | Google AI | YES |
| Codex LLM | LLM | OpenRouter | YES |

#### Processing Adapters
| Adapter | Port | Production Ready |
|---------|------|------------------|
| Recursive Chunker | Chunker | YES |
| Semantic Chunker | Chunker | YES |
| Sentence/Paragraph/Character Chunkers | Chunker | YES |
| LLM Reranker | Reranker | YES |
| LLM Query Rewriter | QueryRewriter | YES |
| LLM Query Expander | QueryExpander | YES |
| LLM Query Decomposer | QueryDecomposer | YES |

### 2.3 RAG Strategies

| Strategy | Description | Production Ready |
|----------|-------------|------------------|
| **Hybrid** | Vector + Fulltext with RRF fusion | YES |
| **Agentic** | Iterative tool-using agent loop | CAUTION - needs timeout handling |
| **GraphRAG** | Entity extraction + community detection | PARTIAL - stubs incomplete |
| **Self-RAG** | Self-reflective quality assessment | YES |

### 2.4 Database Schema

portfolio_index uses Ecto schemas:

```
portfolio_collections (1) ──┬── portfolio_documents (N)
                            │
                            └── portfolio_chunks (N)
                                 └── embedding: vector(384)

vector_index_registry ──── tracks dynamic vector tables
documents ──── content-addressable document store
evaluation_runs ──── RAG evaluation tracking
```

**Compatibility with Command:**
- Both use PostgreSQL + Ecto
- Both use pgvector for embeddings
- Schemas are complementary, not conflicting
- Command tracks sessions/costs, portfolio_index tracks content/embeddings

### 2.5 Strengths

1. **Comprehensive Provider Coverage**
   - 4 embedding providers
   - 4 LLM providers
   - Multiple chunking strategies

2. **Production Features**
   - Rate limiting (Hammer)
   - Telemetry throughout
   - Transactional operations
   - Connection pooling

3. **Advanced RAG**
   - Hybrid search with RRF
   - Query preprocessing pipeline
   - Reranking support

4. **Streaming Support**
   - Broadway for ingestion
   - LLM streaming responses

### 2.6 Concerns & Mitigations

| Concern | Severity | Mitigation |
|---------|----------|------------|
| **Agentic RAG can get stuck** - No timeout in agent loop | High | Set max_iterations, add external timeout in Command |
| **GraphRAG incomplete** - Community detection is stub | Medium | Don't use GraphRAG until completed |
| **Dynamic SQL tables** - Pgvector creates tables dynamically | Medium | Validate index_id format, use migrations |
| **LLM JSON parsing fragile** - Regex-based extraction | Medium | Add fallback parsing, validate outputs |
| **No distributed coordination** - Broadway not clustered | Low | Use Oban for distributed jobs instead |
| **Fixed embedding dimensions** - Chunks table uses 384 | Medium | Use configurable dimensions or separate indexes |

### 2.7 Code Quality: 7/10

- Good separation of concerns
- Comprehensive testing
- Well-documented modules
- Minor: Error recovery strategies could be stronger
- Minor: Some adapters have inconsistent error handling

---

## Part 3: Integration Architecture

### 3.1 How Command Should Use portfolio_*

```
┌─────────────────────────────────────────────────────────────────┐
│                         COMMAND                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                   Command.Agents                            │ │
│  │                                                             │ │
│  │  def execute_agent_call(session, params) do                 │ │
│  │    # 1. Track the call                                      │ │
│  │    {:ok, call} = create_agent_call(session, params)         │ │
│  │                                                             │ │
│  │    # 2. Get RAG context via portfolio                       │ │
│  │    {retriever, cfg} = PortfolioCore.adapter!(:retriever)    │ │
│  │    {:ok, context} = retriever.retrieve(cfg, query, opts)    │ │
│  │                                                             │ │
│  │    # 3. Call LLM via portfolio                              │ │
│  │    {llm, cfg} = PortfolioCore.adapter!(:llm)                │ │
│  │    {:ok, response} = llm.complete(cfg, messages)            │ │
│  │                                                             │ │
│  │    # 4. Track completion and costs                          │ │
│  │    complete_agent_call(call, response)                      │ │
│  │  end                                                        │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              │                                   │
│                              ▼                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              PortfolioCore.adapter!/1                       │ │
│  │              (shared ETS registry)                          │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              │                                   │
│                              ▼                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              PortfolioIndex Adapters                        │ │
│  │              (Pgvector, Claude, Gemini, etc.)               │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Dependency Configuration

```elixir
# command/mix.exs
defp deps do
  [
    # Core persistence (keep)
    {:ecto_sql, "~> 3.11"},
    {:postgrex, "~> 0.18"},

    # REMOVE - duplicated by portfolio_index
    # {:pgvector, "~> 0.3"},

    # ADD - portfolio ecosystem
    {:portfolio_core, "~> 0.3.0"},
    {:portfolio_index, "~> 0.3.0"},

    # OPTIONAL - higher-level APIs
    {:portfolio_manager, "~> 0.3.0", optional: true},
    {:portfolio_coder, "~> 0.3.0", optional: true},

    # Keep rest of deps...
  ]
end
```

### 3.3 Files to Delete from Command

```
lib/command/indexes/
├── index.ex           # DELETE - use portfolio_index schemas
├── context_document.ex # DELETE - use portfolio_index schemas
└── context_chunk.ex    # DELETE - use portfolio_index schemas

lib/command/indexes.ex  # REWRITE - thin wrapper calling portfolio
```

### 3.4 Manifest Configuration

```yaml
# config/portfolio_manifest.yaml
version: "1.0"
environment: ${MIX_ENV:-dev}

adapters:
  vector_store:
    adapter: PortfolioIndex.Adapters.Pgvector
    config:
      repo: Command.Repo

  embedder:
    adapter: PortfolioIndex.Adapters.Gemini
    config:
      api_key: ${GEMINI_API_KEY}
      model: text-embedding-004

  llm:
    adapter: PortfolioIndex.Adapters.Anthropic
    config:
      api_key: ${ANTHROPIC_API_KEY}
      model: claude-sonnet-4-20250514

  retriever:
    adapter: PortfolioIndex.RAG.Strategies.Hybrid
    config:
      vector_store: vector_store
      embedder: embedder
      k: 10

  chunker:
    adapter: PortfolioIndex.Adapters.Chunker.Recursive
    config:
      chunk_size: 1000
      chunk_overlap: 200
```

---

## Part 4: Risk Assessment

### 4.1 Integration Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| API breaking changes in portfolio_* | Low | High | Pin versions, add integration tests |
| Adapter registration timing | Medium | Medium | Validate adapters in Command.Application.start |
| Shared Repo conflicts | Low | Medium | Use separate schemas, different table prefixes |
| Performance regression | Low | Medium | Benchmark before/after integration |
| Complexity increase | Medium | Low | Document architecture, add integration guide |

### 4.2 Technical Debt

| Item | Effort | Priority |
|------|--------|----------|
| Delete Command.Indexes.* files | 1 hour | HIGH |
| Add portfolio deps to mix.exs | 30 min | HIGH |
| Create manifest.yaml | 1 hour | HIGH |
| Rewrite Command.Indexes as thin wrapper | 2 hours | HIGH |
| Add startup validation for required adapters | 2 hours | MEDIUM |
| Add integration tests | 4 hours | MEDIUM |
| Update documentation | 2 hours | LOW |

---

## Part 5: Recommendations

### 5.1 Immediate Actions

1. **Add dependencies** - portfolio_core and portfolio_index to mix.exs
2. **Create manifest** - YAML config for adapter wiring
3. **Delete duplicates** - Remove lib/command/indexes/*
4. **Rewrite wrapper** - Command.Indexes delegates to portfolio adapters
5. **Add validation** - Check required adapters at startup

### 5.2 Architecture Guidelines

1. **Command owns session/tracking state** - Sessions, Messages, AgentCalls, ToolUses, Costs, Approvals
2. **portfolio_index owns content/embedding state** - Collections, Documents, Chunks, Embeddings
3. **Shared Repo is OK** - Both can use Command.Repo, different table prefixes
4. **Telemetry unification** - Both emit telemetry, consolidate handlers

### 5.3 What NOT to Do

- Don't reimplement portfolio_core's ports in Command
- Don't duplicate portfolio_index's adapters
- Don't fork portfolio_* - contribute upstream instead
- Don't use Agentic RAG without timeout wrapper
- Don't use GraphRAG until community detection is complete

---

## Appendix A: Port Callback Reference

### VectorStore (most relevant to Command)

```elixir
@callback create_index(index_id, opts) :: :ok | {:error, term()}
@callback store(index_id, id, embedding, metadata) :: :ok | {:error, term()}
@callback search(index_id, query_embedding, k, opts) :: {:ok, [result]} | {:error, term()}
@callback delete(index_id, id) :: :ok | {:error, term()}
```

### Embedder

```elixir
@callback embed(text, opts) :: {:ok, embedding} | {:error, term()}
@callback embed_batch(texts, opts) :: {:ok, [embedding]} | {:error, term()}
@callback dimensions(model) :: pos_integer()
```

### LLM

```elixir
@callback complete(messages, opts) :: {:ok, response} | {:error, term()}
@callback stream(messages, opts) :: {:ok, stream} | {:error, term()}
@callback model_info(model) :: %{context_window: integer(), ...}
```

### Retriever

```elixir
@callback retrieve(query, context, opts) :: {:ok, [chunk]} | {:error, term()}
@callback strategy_name() :: atom()
@callback required_adapters() :: [atom()]
```

---

## Appendix B: Migration Checklist

- [ ] Add portfolio_core ~> 0.3.0 to deps
- [ ] Add portfolio_index ~> 0.3.0 to deps
- [ ] Remove {:pgvector, "~> 0.3"} (provided by portfolio_index)
- [ ] Create config/portfolio_manifest.yaml
- [ ] Add manifest path to config.exs
- [ ] Delete lib/command/indexes/index.ex
- [ ] Delete lib/command/indexes/context_document.ex
- [ ] Delete lib/command/indexes/context_chunk.ex
- [ ] Rewrite lib/command/indexes.ex as wrapper
- [ ] Add adapter validation to Command.Application
- [ ] Run migrations for portfolio_index tables
- [ ] Add integration tests
- [ ] Update README with architecture diagram
- [ ] Verify telemetry events work together

---

## Conclusion

**portfolio_core and portfolio_index are suitable for Command integration.** The hexagonal architecture provides clean separation, the adapter implementations are production-ready, and the APIs are well-designed. Integration will:

1. **Reduce duplication** - Delete ~500 lines of duplicated code
2. **Increase capability** - Access to 4 LLM providers, 4 embedders, advanced RAG
3. **Improve maintainability** - Single source of truth for RAG/embedding logic
4. **Enable ecosystem** - Compatible with portfolio_manager, portfolio_coder

The main risks are manageable with proper validation and testing. Proceed with integration.
