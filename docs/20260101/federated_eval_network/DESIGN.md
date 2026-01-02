# Federated Eval Network (FEN)

**Collective Intelligence for Agent Evaluation**

> "I'm not going to sit around making evals. The AI should make evals."

---

## Executive Summary

FEN is a federated learning system where developer agent workflows automatically generate evaluation signal as a byproduct of normal work. Individual developers contribute anonymized task patterns and success criteria; the network aggregates these into a shared intelligence layer that improves agent performance for everyone.

No manual eval creation. No manual scoring. Human involvement is limited to natural workflow actions: approving/rejecting agent work, running tests, accepting commits.

---

## The Problem

### Traditional Eval Approach (Broken)

```
Human creates eval task → Human defines success criteria → Human scores output
                ↓
        Doesn't scale for solo devs
        Becomes stale immediately
        Overfits to creator's patterns
```

### Why Solo Dev Evals Fail

| Issue | Impact |
|-------|--------|
| Sparse signal | One dev's work = tiny, biased dataset |
| Time cost | Creating evals competes with actual work |
| Staleness | Static evals don't track evolving codebases |
| Overfitting | Evals reflect one person's coding style |

### The Network Effect Solution

```
N developers working naturally
        ↓
N * tasks/day of implicit eval signal
        ↓
Aggregated patterns benefit everyone
        ↓
More developers → better evals → better agents → more developers
```

---

## Core Principles

### 1. Work IS Evaluation

Every interaction with an agent generates signal:

| Action | Signal Type | Value |
|--------|-------------|-------|
| Accept first try | Strong positive | Task pattern + success criteria |
| Edit before accept | Weak positive | Correction data |
| Reject/redo | Negative | Failure mode |
| Tests pass | Objective positive | Automated criterion |
| Build fails | Objective negative | Failure mode |
| Approval granted | Safety positive | Risk assessment |
| Approval denied | Safety negative | Dangerous pattern |

### 2. Agents Generate Eval Definitions

After successful task completion, the agent extracts:
- Abstract task pattern (not specific code)
- Success criteria that were satisfied
- Quality gates that passed

### 3. Privacy by Design

```
Shared (anonymized):              Stays Local:
├── Task patterns                 ├── Actual code
├── Success criteria schemas      ├── File paths
├── Failure mode clusters         ├── Repository names
├── Tool sequences                ├── Business logic
└── Difficulty distributions      └── Credentials
```

### 4. Cheap Models for Meta-Work

```
Expensive agents (Claude, Codex) → Actual coding work
Cheap models (Gemini Flash, Haiku) → Pattern extraction
                                  → Variation generation
                                  → Counterfactual analysis
```

---

## Architecture

### System Layers

```
┌─────────────────────────────────────────────────────────────────┐
│                    Layer 5: Global Intelligence                 │
│         (Aggregated patterns, success rates, failure modes)     │
└─────────────────────────────────────────────────────────────────┘
                                ▲
                                │ Federated sync
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Layer 4: Regional Aggregators                 │
│            (Optional: org-level, community clusters)            │
└─────────────────────────────────────────────────────────────────┘
                                ▲
                                │ Anonymized patterns
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Layer 3: Local Pattern Store                 │
│              (Per-instance eval seeds and patterns)             │
└─────────────────────────────────────────────────────────────────┘
                                ▲
                                │ Pattern extraction
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Layer 2: Signal Collection                    │
│         (Approval events, test results, workflow outcomes)      │
└─────────────────────────────────────────────────────────────────┘
                                ▲
                                │ Natural workflow
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Layer 1: Command Instance                    │
│              (Agent sessions, tool uses, workflows)             │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
Developer works normally
        │
        ▼
┌───────────────────────────────────────┐
│  Command captures everything          │
│  (agent_calls, tool_uses, approvals)  │
└───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│  Natural quality gates execute        │
│  (tests, builds, lints, type checks)  │
└───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│  Developer approves/rejects           │
│  (implicit signal, no extra work)     │
└───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│  Pattern Extractor (cheap model)      │
│  "What task was this? What criteria   │
│   made it succeed/fail?"              │
└───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│  Local Pattern Store                  │
│  (eval_seeds, task_patterns)          │
└───────────────────────────────────────┘
        │
        ▼ (async, batched)
┌───────────────────────────────────────┐
│  Anonymization Layer                  │
│  - Strip PII, paths, code             │
│  - Abstract to patterns               │
│  - Differential privacy               │
└───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│  Network Aggregation                  │
│  - Cluster similar patterns           │
│  - Compute success rates              │
│  - Identify failure modes             │
└───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│  Back to all instances                │
│  (improved patterns, predictions)     │
└───────────────────────────────────────┘
```

---

## Integration with NSAI Ecosystem

### Command (Agent Management)

The existing Command schema provides the raw signal:

```elixir
# Already captured:
agent_calls     → What the agent did, tokens, timing, cost
tool_uses       → Tool invocations, inputs, outputs, approval status
workflow_runs   → Pipeline executions with snapshots
approval_items  → Human decisions with reasons
activity_logs   → Full audit trail
```

### eval_ex (Evaluation Framework)

Extend eval_ex for federated patterns:

```elixir
defmodule EvalEx.Federation do
  @moduledoc """
  Federated eval pattern management.
  """

  @doc "Extract eval seed from completed workflow"
  def extract_seed(workflow_run) do
    %EvalEx.Seed{
      task_pattern: abstract_task(workflow_run),
      success_criteria: extract_criteria(workflow_run),
      failure_modes: extract_failures(workflow_run),
      quality_gates: extract_gates(workflow_run),
      confidence: compute_confidence(workflow_run),
      derived_from: workflow_run.id
    }
  end

  @doc "Anonymize seed for network sharing"
  def anonymize(seed) do
    seed
    |> strip_paths()
    |> abstract_identifiers()
    |> apply_differential_privacy()
  end
end
```

### crucible_bench (Statistical Testing)

Use crucible_bench for aggregate analysis:

```elixir
# Compare success rates across task patterns
CrucibleBench.compare(
  pattern_a_outcomes,
  pattern_b_outcomes
)

# Analyze network-wide metrics
CrucibleBench.experiment(:ab_test,
  control: baseline_agent_outcomes,
  treatment: improved_agent_outcomes,
  name: "Network-wide agent improvement"
)
```

### forge/anvil (HITL When Needed)

Minimal human curation through existing anvil workflows:

```elixir
# Only surface high-value review opportunities
defmodule FEN.Curation do
  use Anvil.Queue

  # Pattern with high variance → human review
  def should_surface?(pattern) do
    pattern.confidence < 0.6 or
    pattern.disagreement_rate > 0.3
  end
end
```

---

## Data Structures

### Local: Eval Seed

```elixir
defmodule FEN.EvalSeed do
  @moduledoc """
  Raw eval signal extracted from a single workflow.
  Stored locally, never shared directly.
  """

  defstruct [
    :id,
    :workflow_run_id,
    :session_id,

    # Task abstraction
    :task_type,           # "add_feature", "fix_bug", "refactor"
    :task_pattern,        # "Add {component} to {location}"
    :input_schema,        # %{component: :string, location: :string}

    # Success criteria (what made this succeed)
    :success_criteria,    # [{:file_exists, pattern}, {:tests_pass, pattern}]
    :quality_gates,       # [:build, :lint, :typecheck]
    :human_approval,      # :accepted | :edited | :rejected

    # Metrics
    :tokens_used,
    :duration_ms,
    :tool_sequence,       # [:read, :edit, :bash, :edit]
    :iteration_count,

    # Failure modes (if failed)
    :failure_type,
    :failure_context,

    # Provenance
    :agent_model,
    :extracted_at,
    :confidence
  ]
end
```

### Shared: Anonymized Pattern

```elixir
defmodule FEN.Pattern do
  @moduledoc """
  Anonymized, aggregated pattern safe for network sharing.
  No PII, no code, no paths.
  """

  defstruct [
    :pattern_hash,        # Deterministic hash for dedup

    # Abstract task
    :task_type,
    :abstracted_input,    # "Add {X} to {Y}" with slots
    :complexity_tier,     # :simple | :moderate | :complex

    # Success criteria (schematized)
    :criteria_schema,     # [{:file_exists, {:slot, :X}}, ...]
    :quality_gates,

    # Aggregate stats (no individual data)
    :sample_count,
    :success_rate,
    :avg_tokens,
    :avg_duration_ms,
    :p50_duration_ms,
    :p95_duration_ms,

    # Failure modes
    :failure_modes,       # [%{type: :missing_import, rate: 0.12}]

    # Tool patterns
    :common_tool_sequences,

    # Network metadata
    :contributing_instances,  # Count, not IDs
    :last_updated_at,
    :version
  ]
end
```

### Network: Aggregated Intelligence

```elixir
defmodule FEN.Intelligence do
  @moduledoc """
  Network-wide aggregated knowledge.
  """

  defstruct [
    # Pattern clusters
    :task_type_taxonomy,   # Hierarchical task classification
    :pattern_embeddings,   # For similarity search

    # Success predictors
    :difficulty_model,     # Predict tokens/time from task pattern
    :success_model,        # Predict success probability

    # Failure prevention
    :failure_mode_library, # Known failure patterns
    :mitigation_strategies,# What helps avoid each failure

    # Agent recommendations
    :model_performance,    # Which models do well on which tasks
    :tool_strategies,      # Optimal tool sequences by task type

    # Metadata
    :total_samples,
    :active_instances,
    :last_sync_at
  ]
end
```

---

## Protocol Design

### Pattern Submission

```elixir
defmodule FEN.Protocol.Submit do
  @moduledoc """
  Privacy-preserving pattern submission.
  """

  @type submission :: %{
    patterns: [FEN.Pattern.t()],
    instance_id: binary(),        # Pseudonymous, rotates
    submission_nonce: binary(),   # Prevent replay
    signature: binary()           # Verify authenticity
  }

  def submit(patterns, config) do
    patterns
    |> Enum.map(&anonymize/1)
    |> batch()
    |> add_noise(config.epsilon)  # Differential privacy
    |> sign(config.instance_key)
    |> encrypt(config.aggregator_pubkey)
    |> send_to_aggregator()
  end
end
```

### Pattern Retrieval

```elixir
defmodule FEN.Protocol.Retrieve do
  @moduledoc """
  Fetch aggregated intelligence.
  """

  def fetch_relevant(task_description, config) do
    embedding = embed(task_description, config.embed_model)

    # Query network for similar patterns
    patterns = query_aggregator(embedding, config)

    # Local enrichment with own history
    local_patterns = query_local(embedding)

    merge_and_rank(patterns, local_patterns)
  end
end
```

### Sync Protocol

```elixir
defmodule FEN.Protocol.Sync do
  @moduledoc """
  Periodic bidirectional sync with network.
  """

  @sync_interval :timer.hours(1)

  def sync(state) do
    # Upload new local patterns (anonymized)
    new_patterns = get_pending_patterns(state)
    submit_result = FEN.Protocol.Submit.submit(new_patterns, state.config)

    # Download network updates
    network_updates = fetch_updates_since(state.last_sync_at)

    # Merge into local intelligence
    updated_intelligence = merge(state.intelligence, network_updates)

    %{state |
      intelligence: updated_intelligence,
      last_sync_at: DateTime.utc_now(),
      pending_patterns: []
    }
  end
end
```

---

## Privacy Model

### What's Protected

| Data Type | Protection | Rationale |
|-----------|------------|-----------|
| Source code | Never leaves instance | Core IP |
| File paths | Stripped, abstracted | Reveals project structure |
| Repository names | Never shared | Identifies projects |
| User identities | Pseudonymous, rotating | Privacy |
| Specific errors | Abstracted to types | May contain secrets |
| API keys/secrets | Never captured | Security |

### Anonymization Pipeline

```
Raw workflow data
        │
        ▼
┌───────────────────────────────────────┐
│  1. Path Stripping                    │
│     /home/user/project/lib/foo.ex     │
│     → {project}/lib/{module}.ex       │
│     → lib/{module}.ex                 │
│     → {file}                          │
└───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│  2. Content Abstraction               │
│     "Add logout button to Settings"   │
│     → "Add {component} to {location}" │
└───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│  3. Identifier Hashing                │
│     Instance ID → rotating pseudonym  │
│     Timestamps → bucketed             │
└───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│  4. Differential Privacy              │
│     Add calibrated noise to counts    │
│     Suppress rare patterns            │
└───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│  5. K-Anonymity Check                 │
│     Pattern must have k+ sources      │
│     before entering global pool       │
└───────────────────────────────────────┘
```

### Differential Privacy Parameters

```elixir
defmodule FEN.Privacy do
  # Epsilon budget per sync period
  @epsilon_per_sync 1.0

  # Minimum instances before pattern is shared
  @k_anonymity_threshold 5

  # Noise calibration for counts
  def add_laplace_noise(count, sensitivity \\ 1) do
    noise = Laplace.sample(0, sensitivity / @epsilon_per_sync)
    max(0, count + noise)
  end
end
```

---

## HITL Integration

### When Humans Are Involved (Minimal)

```
Normal workflow → No extra human input required
        │
        ├── Accept agent output → Implicit positive signal
        ├── Reject agent output → Implicit negative signal
        └── Edit before accept → Correction data

High-value curation (optional, surfaced via anvil):
        │
        ├── Pattern disagreement → "Is this the same task type?"
        ├── Low confidence extraction → "What was the success criterion?"
        └── Novel failure mode → "What went wrong here?"
```

### Anvil Integration

```elixir
defmodule FEN.Curation do
  use Anvil.Queue,
    name: :fen_curation,
    priority: :low  # Never interrupt main work

  @doc """
  Surface only high-value review opportunities.
  Target: <1 per day for active developer.
  """
  def maybe_queue_for_review(seed) do
    cond do
      seed.confidence < 0.5 ->
        queue(:low_confidence_extraction, seed)

      seed.task_type == :unknown and seed.success ->
        queue(:novel_task_pattern, seed)

      seed.failure_type == :unknown ->
        queue(:novel_failure_mode, seed)

      true ->
        :skip
    end
  end
end
```

### Curation UI (Ingot Component)

```elixir
defmodule FEN.CurationLive do
  use Phoenix.LiveView
  use Ingot.Components

  @doc """
  Rapid HITL for pattern curation.
  Design goal: <10 seconds per decision.
  """
  def render(assigns) do
    ~H"""
    <Ingot.card>
      <:header>Pattern Review</:header>

      <div class="task-summary">
        <p>Extracted pattern: <%= @seed.task_pattern %></p>
        <p>Confidence: <%= @seed.confidence %></p>
      </div>

      <div class="quick-actions">
        <button phx-click="confirm">Looks right</button>
        <button phx-click="reject">Not quite</button>
        <button phx-click="edit">Edit pattern</button>
      </div>
    </Ingot.card>
    """
  end
end
```

---

## Network Topology

### Deployment Options

#### Option A: Centralized Aggregator (MVP)

```
┌─────────────────────────────────────────┐
│         NSAI Aggregator Service         │
│  (Hosted by North Shore AI initially)   │
└─────────────────────────────────────────┘
        ▲               ▲               ▲
        │               │               │
   Instance A      Instance B      Instance C
```

**Pros:** Simple, fast to deploy, consistent aggregation
**Cons:** Single point of trust, scaling challenges

#### Option B: Federated Aggregators

```
┌─────────────────┐     ┌─────────────────┐
│ Org A Aggregator│◄───►│ Org B Aggregator│
└─────────────────┘     └─────────────────┘
        ▲                       ▲
   ┌────┴────┐             ┌────┴────┐
   │         │             │         │
 Inst A1   Inst A2       Inst B1   Inst B2
```

**Pros:** Org-level control, horizontal scaling
**Cons:** More complex, requires coordination protocol

#### Option C: Fully Decentralized (Future)

```
┌─────────────────────────────────────────┐
│           Gossip Protocol Layer         │
│    (DHT-based pattern distribution)     │
└─────────────────────────────────────────┘
    ▲       ▲       ▲       ▲       ▲
    │       │       │       │       │
  Inst A  Inst B  Inst C  Inst D  Inst E
```

**Pros:** No central trust, maximum resilience
**Cons:** Consistency challenges, slower convergence

### Recommended Path

1. **Phase 1:** Centralized aggregator (NSAI-hosted)
2. **Phase 2:** Federated aggregators for orgs
3. **Phase 3:** Decentralized gossip (if scale demands)

---

## Implementation Phases

### Phase 1: Local Pattern Extraction (Solo Dev Value)

No network required. Immediate value for single developer.

```elixir
# Post-workflow hook in Command
defmodule Command.Hooks.PatternExtraction do
  def after_workflow_complete(workflow_run) do
    if workflow_run.status == :completed do
      seed = FEN.EvalSeed.extract(workflow_run)
      FEN.LocalStore.save(seed)

      # Optional: generate variations for self-testing
      variations = FEN.Variation.generate(seed)
      FEN.LocalStore.save_variations(variations)
    end
  end
end
```

**Deliverables:**
- [ ] EvalSeed struct and extraction logic
- [ ] Local pattern store (ETS + Postgres)
- [ ] Post-workflow hook integration
- [ ] Basic pattern similarity search

### Phase 2: Network Sync (Multi-Dev Value)

Enable sharing between instances.

```elixir
# Periodic sync GenServer
defmodule FEN.SyncWorker do
  use GenServer

  @sync_interval :timer.hours(1)

  def handle_info(:sync, state) do
    # Anonymize and submit local patterns
    local_patterns = FEN.LocalStore.pending_for_sync()
    anonymized = Enum.map(local_patterns, &FEN.Anonymize.process/1)
    FEN.Network.submit(anonymized)

    # Fetch network updates
    updates = FEN.Network.fetch_since(state.last_sync)
    FEN.LocalStore.merge_network_patterns(updates)

    schedule_next_sync()
    {:noreply, %{state | last_sync: DateTime.utc_now()}}
  end
end
```

**Deliverables:**
- [ ] Anonymization pipeline
- [ ] Network protocol (submit/fetch)
- [ ] Aggregator service (MVP)
- [ ] Sync worker
- [ ] Differential privacy implementation

### Phase 3: Intelligence Application

Use network knowledge to improve agent performance.

```elixir
# Pre-task intelligence lookup
defmodule FEN.Advisor do
  def advise(task_description) do
    patterns = FEN.Intelligence.find_similar(task_description)

    %{
      predicted_difficulty: predict_difficulty(patterns),
      recommended_approach: best_tool_sequence(patterns),
      common_pitfalls: failure_modes(patterns),
      success_criteria: likely_criteria(patterns),
      estimated_tokens: token_estimate(patterns)
    }
  end
end

# Integration with Command workflow
defmodule Command.Workflow.Runner do
  def before_step(step, context) do
    advice = FEN.Advisor.advise(step.description)

    # Inject advice into agent context
    enriched_context = Map.put(context, :fen_advice, advice)

    # Optionally adjust timeout based on predicted difficulty
    adjusted_step = adjust_timeout(step, advice.predicted_difficulty)

    {adjusted_step, enriched_context}
  end
end
```

**Deliverables:**
- [ ] Intelligence query API
- [ ] Pre-task advisor
- [ ] Workflow runner integration
- [ ] Success criteria suggestion
- [ ] Failure mode warnings

### Phase 4: Active Learning

The network identifies high-value data to collect.

```elixir
defmodule FEN.ActiveLearning do
  @doc """
  Identify gaps in network knowledge.
  Surface tasks that would provide maximum learning value.
  """
  def identify_valuable_tasks(instance_context) do
    # Find patterns with high variance (disagreement)
    uncertain_patterns = FEN.Intelligence.high_variance_patterns()

    # Find under-represented task types
    sparse_regions = FEN.Intelligence.sparse_task_regions()

    # Match to tasks this instance might encounter
    relevant = filter_by_context(uncertain_patterns ++ sparse_regions, instance_context)

    Enum.map(relevant, fn pattern ->
      %{
        pattern: pattern,
        value: compute_information_gain(pattern),
        prompt: "If you encounter a task like '#{pattern.example}', detailed feedback would be valuable"
      }
    end)
  end
end
```

**Deliverables:**
- [ ] Value-of-information computation
- [ ] Gap identification
- [ ] Targeted feedback requests (minimal HITL)
- [ ] Network rebalancing

---

## Database Schema Extensions

### Command Instance (Local)

```elixir
# New tables for local FEN storage

create table(:eval_seeds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :workflow_run_id, references(:workflow_runs, type: :binary_id)
  add :session_id, references(:sessions, type: :binary_id)

  # Task abstraction
  add :task_type, :string
  add :task_pattern, :text
  add :input_schema, :map

  # Success criteria
  add :success_criteria, {:array, :map}
  add :quality_gates, {:array, :string}
  add :human_approval, :string

  # Metrics
  add :tokens_used, :integer
  add :duration_ms, :integer
  add :tool_sequence, {:array, :string}
  add :iteration_count, :integer

  # Failure info
  add :failure_type, :string
  add :failure_context, :map

  # Provenance
  add :agent_model, :string
  add :confidence, :float
  add :extracted_at, :utc_datetime_usec

  # Sync status
  add :synced_at, :utc_datetime_usec
  add :sync_hash, :string

  timestamps(type: :utc_datetime_usec)
end

create table(:local_patterns, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :pattern_hash, :string, null: false

  add :task_type, :string
  add :abstracted_input, :text
  add :complexity_tier, :string

  add :criteria_schema, {:array, :map}
  add :quality_gates, {:array, :string}

  # Local stats
  add :local_sample_count, :integer, default: 0
  add :local_success_rate, :float
  add :local_avg_tokens, :integer
  add :local_avg_duration_ms, :integer

  # Network stats (from sync)
  add :network_sample_count, :integer
  add :network_success_rate, :float
  add :network_avg_tokens, :integer

  add :failure_modes, {:array, :map}
  add :common_tool_sequences, {:array, {:array, :string}}

  # Embedding for similarity search
  add :embedding, :vector, size: 768

  add :last_network_sync, :utc_datetime_usec

  timestamps(type: :utc_datetime_usec)
end

create index(:eval_seeds, [:workflow_run_id])
create index(:eval_seeds, [:task_type])
create index(:eval_seeds, [:synced_at])
create unique_index(:local_patterns, [:pattern_hash])
```

### Aggregator Service (Network)

```elixir
create table(:global_patterns, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :pattern_hash, :string, null: false

  add :task_type, :string
  add :abstracted_input, :text
  add :complexity_tier, :string

  add :criteria_schema, {:array, :map}
  add :quality_gates, {:array, :string}

  # Aggregate stats (with noise for DP)
  add :sample_count, :integer
  add :success_rate, :float
  add :avg_tokens, :integer
  add :p50_duration_ms, :integer
  add :p95_duration_ms, :integer

  add :failure_modes, {:array, :map}
  add :common_tool_sequences, {:array, {:array, :string}}

  # Privacy accounting
  add :contributing_instances, :integer  # Count only
  add :last_contribution_at, :utc_datetime_usec
  add :privacy_budget_used, :float

  add :embedding, :vector, size: 768
  add :version, :integer, default: 1

  timestamps(type: :utc_datetime_usec)
end

create table(:pattern_contributions, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :pattern_id, references(:global_patterns, type: :binary_id)

  # Pseudonymous instance ID (rotates)
  add :instance_pseudonym, :string

  # Contribution data (already anonymized)
  add :sample_count_delta, :integer
  add :success_count_delta, :integer
  add :token_sum_delta, :integer
  add :duration_sum_delta, :integer

  add :contributed_at, :utc_datetime_usec

  timestamps(type: :utc_datetime_usec)
end

create unique_index(:global_patterns, [:pattern_hash])
create index(:global_patterns, [:task_type])
create index(:pattern_contributions, [:pattern_id])
create index(:pattern_contributions, [:instance_pseudonym])
```

---

## API Design

### Local API (Command Instance)

```elixir
defmodule FEN do
  @moduledoc """
  Main entry point for Federated Eval Network.
  """

  # Pattern extraction
  def extract_seed(workflow_run), do: EvalSeed.extract(workflow_run)
  def save_seed(seed), do: LocalStore.save(seed)

  # Intelligence queries
  def advise(task_description), do: Advisor.advise(task_description)
  def predict_difficulty(task), do: Intelligence.predict_difficulty(task)
  def likely_failure_modes(task), do: Intelligence.failure_modes(task)

  # Manual curation (rare)
  def pending_curation(), do: Curation.pending()
  def curate(seed_id, decision), do: Curation.decide(seed_id, decision)

  # Sync control
  def sync_now(), do: SyncWorker.sync_now()
  def sync_status(), do: SyncWorker.status()
end
```

### Network API (Aggregator)

```elixir
defmodule FEN.Network.API do
  use Plug.Router

  # Submit anonymized patterns
  post "/v1/patterns" do
    # Verify signature, decrypt, validate
    # Merge into global patterns
    # Return sync token
  end

  # Fetch patterns since timestamp
  get "/v1/patterns" do
    # Return patterns updated since ?since=
    # Apply rate limiting
  end

  # Query similar patterns
  post "/v1/query" do
    # Embedding-based similarity search
    # Return ranked patterns
  end

  # Health and stats
  get "/v1/stats" do
    # Total patterns, instances, etc.
    # No identifying information
  end
end
```

---

## Metrics and Observability

### Instance Metrics

```elixir
defmodule FEN.Telemetry do
  def attach do
    :telemetry.attach_many("fen", [
      [:fen, :seed, :extracted],
      [:fen, :pattern, :matched],
      [:fen, :advice, :generated],
      [:fen, :sync, :completed],
      [:fen, :curation, :queued]
    ], &handle_event/4, nil)
  end

  # Emit on seed extraction
  def emit_extraction(seed) do
    :telemetry.execute(
      [:fen, :seed, :extracted],
      %{confidence: seed.confidence},
      %{task_type: seed.task_type, success: seed.human_approval == :accepted}
    )
  end
end
```

### Network Health Metrics

| Metric | Description |
|--------|-------------|
| `fen.network.patterns.total` | Total patterns in network |
| `fen.network.instances.active` | Instances synced in last 24h |
| `fen.network.contributions.rate` | Patterns submitted per hour |
| `fen.network.queries.rate` | Intelligence queries per hour |
| `fen.network.coverage.task_types` | Distinct task types covered |
| `fen.network.privacy.budget_remaining` | DP budget per pattern |

---

## Security Considerations

### Threat Model

| Threat | Mitigation |
|--------|------------|
| Pattern deanonymization | K-anonymity, differential privacy |
| Aggregator compromise | No raw data stored, only aggregates |
| Malicious patterns | Signature verification, rate limiting |
| Poisoning attacks | Outlier detection, contribution limits |
| Traffic analysis | Batched sync, timing noise |
| Instance impersonation | Rotating pseudonyms, signed submissions |

### Trust Assumptions

1. **Aggregator is honest-but-curious:** Follows protocol but may try to infer information
2. **Instances are mostly honest:** Some may submit bad data, but majority are good
3. **Network is adversarial:** Assume eavesdroppers on all communications

### Cryptographic Primitives

```elixir
defmodule FEN.Crypto do
  # Instance identity (rotates monthly)
  def generate_pseudonym(instance_secret, epoch) do
    :crypto.mac(:hmac, :sha256, instance_secret, "#{epoch}")
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  # Submission signing
  def sign_submission(data, private_key) do
    :public_key.sign(data, :sha256, private_key)
  end

  # Encrypted submission to aggregator
  def encrypt_for_aggregator(data, aggregator_pubkey) do
    # Hybrid encryption: symmetric key + RSA
    symmetric_key = :crypto.strong_rand_bytes(32)
    encrypted_data = :crypto.crypto_one_time(:aes_256_gcm, symmetric_key, data)
    encrypted_key = :public_key.encrypt_public(symmetric_key, aggregator_pubkey)
    {encrypted_key, encrypted_data}
  end
end
```

---

## Success Metrics

### Phase 1 (Local Only)

| Metric | Target |
|--------|--------|
| Seeds extracted per workflow | 95%+ |
| Pattern match rate | >50% of new tasks match existing pattern |
| Advice accuracy | Predicted difficulty within 2x of actual |
| Curation queue size | <1 item per day |

### Phase 2 (Network)

| Metric | Target |
|--------|--------|
| Active instances | 10+ |
| Network patterns | 1000+ |
| Sync success rate | 99%+ |
| Privacy budget per pattern | <0.1 epsilon |

### Phase 3 (Intelligence)

| Metric | Target |
|--------|--------|
| Success rate improvement | +10% on tasks with network data |
| Time-to-completion improvement | -15% with advice |
| Failure prevention rate | 20% of known failure modes avoided |

---

## Open Questions

1. **Incentive alignment:** How to encourage contribution without gaming?
2. **Pattern granularity:** What's the right abstraction level for tasks?
3. **Cross-language patterns:** Do patterns transfer across Elixir/Python/etc.?
4. **Competitive dynamics:** How to handle competing users on same tasks?
5. **Versioning:** How to handle pattern evolution over time?
6. **Cold start:** How to bootstrap with minimal initial data?

---

## References

- Differential Privacy: Dwork, C. (2006). "Differential Privacy"
- Federated Learning: McMahan et al. (2017). "Communication-Efficient Learning of Deep Networks from Decentralized Data"
- K-Anonymity: Sweeney, L. (2002). "k-anonymity: a model for protecting privacy"
- Active Learning: Settles, B. (2009). "Active Learning Literature Survey"

---

## Appendix: Example Patterns

### Pattern: Add UI Component

```json
{
  "pattern_hash": "a1b2c3d4",
  "task_type": "add_feature",
  "abstracted_input": "Add {component_type} to {location}",
  "complexity_tier": "moderate",
  "criteria_schema": [
    {"type": "file_exists", "pattern": "{location}/{component_type}.ex"},
    {"type": "test_passes", "pattern": "test/{location}/{component_type}_test.exs"},
    {"type": "no_regressions", "command": "mix test"}
  ],
  "quality_gates": ["build", "lint", "typecheck"],
  "sample_count": 847,
  "success_rate": 0.82,
  "avg_tokens": 3420,
  "p50_duration_ms": 45000,
  "failure_modes": [
    {"type": "missing_import", "rate": 0.08},
    {"type": "incorrect_module_path", "rate": 0.05},
    {"type": "test_not_created", "rate": 0.03}
  ],
  "common_tool_sequences": [
    ["read", "edit", "write", "bash"],
    ["glob", "read", "edit", "bash", "edit"]
  ]
}
```

### Pattern: Fix Type Error

```json
{
  "pattern_hash": "e5f6g7h8",
  "task_type": "fix_bug",
  "abstracted_input": "Fix {error_type} in {location}",
  "complexity_tier": "simple",
  "criteria_schema": [
    {"type": "typecheck_passes", "command": "mix dialyzer"},
    {"type": "no_regressions", "command": "mix test"}
  ],
  "quality_gates": ["build", "typecheck"],
  "sample_count": 1203,
  "success_rate": 0.91,
  "avg_tokens": 1850,
  "p50_duration_ms": 22000,
  "failure_modes": [
    {"type": "introduced_new_error", "rate": 0.04},
    {"type": "wrong_fix_location", "rate": 0.03}
  ]
}
```

---

*Document Version: 0.1.0*
*Last Updated: 2026-01-01*
*Status: Draft*
