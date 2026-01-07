# AI Layer Consolidation - Multi-Agent Orchestration Prompt

## Objective

Consolidate the fragmented AI abstraction layers across the portfolio ecosystem into a unified `altar_ai` layer. This involves coordinating changes across multiple repositories using parallel agents, TDD methodology, and strict quality gates.

## Reference Documents

- `docs/20260105/07_ai_layer_consolidation.md` - Architecture and migration plan
- `docs/20260105/05_flowstone_integration_design.md` - FlowStone integration details
- `docs/20260105/06_synapse_integration_design.md` - Synapse integration details

## Quality Gates (MANDATORY)

Every repository MUST pass ALL of the following before any PR or completion:

```bash
# All tests pass
mix test

# No compiler warnings
mix compile --warnings-as-errors

# Dialyzer clean
mix dialyzer

# Credo clean
mix credo --strict

# Format check
mix format --check-formatted
```

**DO NOT proceed to the next phase until all quality gates pass.**

---

## Phase 0: Assessment (PARALLEL)

Launch parallel agents to assess the current state of each repository.

### Agent Tasks

```
FOR EACH repo IN [altar_ai, synapse, flowstone, flowstone_ai, ALTAR, command]:
  1. cd ~/p/g/n/{repo}
  2. Run quality gates and record current state
  3. Read existing CLAUDE.md (if exists)
  4. Analyze relevant source files for AI-related code
  5. Document findings in CLAUDE.md
```

### CLAUDE.md Status Template

Each repo's CLAUDE.md should be updated with:

```markdown
# {Repo Name}

## AI Consolidation Status

**Last Updated**: {timestamp}
**Phase**: Assessment | In Progress | Complete
**Quality Gates**:
- [ ] Tests passing
- [ ] No compiler warnings
- [ ] Dialyzer clean
- [ ] Credo clean
- [ ] Formatted

## Current State

{Description of AI-related code in this repo}

## Required Changes

{List of changes needed per consolidation plan}

## Dependencies

{Other repos this depends on for consolidation}

## Blockers

{Any issues blocking progress}
```

---

## Phase 1: altar_ai Foundation (SEQUENTIAL - Critical Path)

This is the foundation that other repos depend on. Must complete first.

### 1.1 TDD: Altar.AI.Client

```elixir
# test/altar/ai/client_test.exs - Write FIRST (RED)
defmodule Altar.AI.ClientTest do
  use ExUnit.Case, async: true

  describe "generate/2" do
    test "returns generated text with metadata"
    test "applies profile configuration"
    test "emits telemetry events"
    test "handles provider errors gracefully"
    test "respects timeout configuration"
  end

  describe "stream/2" do
    test "returns stream of chunks"
    test "emits telemetry on stream start/stop"
  end

  describe "embed/2" do
    test "returns embedding vector"
    test "supports batch embedding"
  end

  describe "chat_completion/2" do
    test "maintains ReqLLM-compatible interface"
    test "tracks token usage"
  end
end
```

**RGR Cycle**:
1. RED: Write failing test
2. GREEN: Implement minimal code to pass
3. REFACTOR: Clean up, run quality gates
4. REPEAT

### 1.2 TDD: Altar.AI.Config

```elixir
# test/altar/ai/config_test.exs - Write FIRST (RED)
defmodule Altar.AI.ConfigTest do
  use ExUnit.Case, async: true

  describe "get_profile/1" do
    test "returns default profile when none specified"
    test "returns named profile from config"
    test "merges profile with defaults"
  end

  describe "adapter_for_provider/1" do
    test "returns Gemini adapter for google provider"
    test "returns Claude adapter for anthropic provider"
    test "raises for unknown provider"
  end
end
```

### 1.3 TDD: Altar.AI.Telemetry

```elixir
# test/altar/ai/telemetry_test.exs - Write FIRST (RED)
defmodule Altar.AI.TelemetryTest do
  use ExUnit.Case, async: true
  import Supertester.TelemetryHelpers

  describe "span/3" do
    test "emits start event with metadata"
    test "emits stop event with duration and result"
    test "emits exception event on error"
    test "includes token counts in metadata"
  end
end
```

### 1.4 TDD: Altar.AI.Integrations.FlowStone

```elixir
# test/altar/ai/integrations/flowstone_test.exs - Write FIRST (RED)
defmodule Altar.AI.Integrations.FlowStoneTest do
  use ExUnit.Case, async: true

  describe "FlowStone.Resource behaviour" do
    test "setup/1 initializes resource with config"
    test "cleanup/1 releases resources"
  end

  describe "generate/3" do
    test "delegates to Altar.AI.Client"
    test "includes flowstone context in telemetry"
  end

  describe "embed/3" do
    test "delegates to Altar.AI.Client"
  end
end
```

### 1.5 TDD: Altar.AI.Integrations.Synapse

```elixir
# test/altar/ai/integrations/synapse_test.exs - Write FIRST (RED)
defmodule Altar.AI.Integrations.SynapseTest do
  use ExUnit.Case, async: true

  describe "chat_completion/2 (ReqLLM compatibility)" do
    test "accepts ReqLLM-style params"
    test "returns ReqLLM-compatible response"
    test "tracks tokens for cost calculation"
  end

  describe "generate/2" do
    test "simplified interface for agents"
  end

  describe "stream/2" do
    test "returns enumerable stream"
  end
end
```

### 1.6 Update CLAUDE.md

After each module completes RGR cycle:
```bash
mix test
mix compile --warnings-as-errors
mix dialyzer
mix credo --strict
```

Update CLAUDE.md with completed items.

---

## Phase 2: Synapse Migration (After Phase 1)

### 2.1 Add altar_ai Dependency

```elixir
# mix.exs
{:altar_ai, path: "../altar_ai"}
```

### 2.2 TDD: Update Agent Base

```elixir
# test/synapse/agents/base_test.exs - Extend existing tests
defmodule Synapse.Agents.BaseTest do
  # Add tests for Altar.AI integration
  test "uses Altar.AI.Integrations.Synapse for LLM calls"
  test "emits unified telemetry events"
end
```

### 2.3 Deprecate ReqLLM

```elixir
# lib/synapse/req_llm.ex
@deprecated "Use Altar.AI.Integrations.Synapse instead"
defdelegate chat_completion(params, opts \\ []),
  to: Altar.AI.Integrations.Synapse
```

### 2.4 Run Full Quality Gates

```bash
mix test
mix compile --warnings-as-errors
mix dialyzer
mix credo --strict
```

---

## Phase 3: FlowStone Migration (After Phase 1)

### 3.1 Add altar_ai Dependency

```elixir
# mix.exs
{:altar_ai, path: "../altar_ai"}
```

### 3.2 TDD: Update Resource References

```elixir
# test/flowstone/ai_resource_test.exs
defmodule FlowStone.AIResourceTest do
  test "Altar.AI.Integrations.FlowStone implements Resource behaviour"
  test "generate/3 produces expected output format"
  test "embed/3 produces expected vector format"
end
```

### 3.3 Deprecate FlowStone.AI.Resource (if exists internally)

Point all references to `Altar.AI.Integrations.FlowStone`.

### 3.4 Run Full Quality Gates

---

## Phase 4: flowstone_ai Deprecation (After Phase 3)

### 4.1 Verify All Code Migrated

```bash
# Ensure no external deps on flowstone_ai
grep -r "flowstone_ai" ~/p/g/n/*/mix.exs
```

### 4.2 Update CLAUDE.md

```markdown
## AI Consolidation Status

**Phase**: DEPRECATED
**Reason**: Code migrated to altar_ai as Altar.AI.Integrations.FlowStone
**Migration Date**: {date}
**Successor**: altar_ai >= x.x.x
```

### 4.3 Archive Repository

Mark as archived, do not delete.

---

## Phase 5: Command Integration (After Phases 2 & 3)

### 5.1 Verify Dependencies

```elixir
# mix.exs should have:
{:altar_ai, path: "../altar_ai"}
# Should NOT have:
# {:flowstone_ai, path: "../flowstone_ai"}  # REMOVED
```

### 5.2 TDD: Integration Tests

```elixir
# test/command/pipelines/ai_integration_test.exs
defmodule Command.Pipelines.AIIntegrationTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation
  import Supertester.TelemetryHelpers

  test "pipeline AI operations use unified Altar.AI layer"
  test "cost tracking receives Altar.AI telemetry events"
  test "altar_ai_operations table populated correctly"
end

# test/command/orchestration/ai_integration_test.exs
defmodule Command.Orchestration.AIIntegrationTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  test "agent instances use Altar.AI.Integrations.Synapse"
  test "workflow runs emit unified telemetry"
end
```

### 5.3 Run Full Quality Gates

---

## Phase 6: Final Validation (PARALLEL)

Launch parallel agents to validate each repo.

### Validation Script (Run in Each Repo)

```bash
#!/bin/bash
set -e

echo "=== Quality Gate Validation ==="

echo "1. Fetching deps..."
mix deps.get

echo "2. Compiling (warnings as errors)..."
mix compile --warnings-as-errors

echo "3. Running tests..."
mix test

echo "4. Running Dialyzer..."
mix dialyzer

echo "5. Running Credo..."
mix credo --strict

echo "6. Checking format..."
mix format --check-formatted

echo "=== ALL GATES PASSED ==="
```

### Cross-Repo Integration Test

```bash
# From command repo
cd ~/p/g/n/command
mix deps.get
mix test test/integration/
```

---

## Multi-Agent Coordination Strategy

### Parallel Execution Map

```
Phase 0 (Assessment):
  [Agent 1: altar_ai] ──┐
  [Agent 2: synapse]  ──┼── All parallel
  [Agent 3: flowstone]──┤
  [Agent 4: ALTAR]    ──┤
  [Agent 5: command]  ──┘

Phase 1 (altar_ai foundation):
  [Agent 1: altar_ai] ── Sequential (critical path)

Phase 2-3 (Synapse + FlowStone):
  [Agent 2: synapse]  ──┬── Parallel after Phase 1
  [Agent 3: flowstone]──┘

Phase 4 (flowstone_ai deprecation):
  [Agent 4: flowstone_ai] ── After Phase 3

Phase 5 (Command integration):
  [Agent 5: command] ── After Phases 2 & 3

Phase 6 (Validation):
  [All Agents] ── Parallel final validation
```

### Agent Communication

Each agent updates its repo's CLAUDE.md. Coordinator checks:

```bash
# Check all repos ready for next phase
for repo in altar_ai synapse flowstone command; do
  grep "Phase.*Complete" ~/p/g/n/$repo/CLAUDE.md || echo "$repo not ready"
done
```

---

## Error Handling

### If Quality Gates Fail

1. DO NOT proceed to next phase
2. Document failure in CLAUDE.md under "Blockers"
3. Fix issue using RGR cycle
4. Re-run all quality gates
5. Only proceed when ALL pass

### If Integration Fails

1. Check dependency order (altar_ai must complete Phase 1 first)
2. Verify correct version/path in mix.exs
3. Run `mix deps.clean --all && mix deps.get`
4. Document in CLAUDE.md

### Rollback Procedure

If consolidation causes critical issues:

1. Revert to pre-consolidation commits
2. Document failure mode
3. Create issue for investigation
4. Re-attempt with fix

---

## Success Criteria

Consolidation is complete when:

- [ ] `altar_ai` has unified Client, Config, Telemetry modules
- [ ] `altar_ai` has FlowStone and Synapse integrations
- [ ] `synapse` uses `Altar.AI.Integrations.Synapse` (ReqLLM deprecated)
- [ ] `flowstone` uses `Altar.AI.Integrations.FlowStone`
- [ ] `flowstone_ai` is archived/deprecated
- [ ] `command` has no `flowstone_ai` dependency
- [ ] ALL repos pass ALL quality gates
- [ ] Cross-repo integration tests pass
- [ ] All CLAUDE.md files show "Phase: Complete"

---

## Commands Reference

```bash
# Run in any repo
mix test                           # Run tests
mix test --cover                   # With coverage
mix compile --warnings-as-errors   # Strict compile
mix dialyzer                       # Type checking
mix credo --strict                 # Linting
mix format --check-formatted       # Format check
mix format                         # Auto-format

# Full validation
mix do compile --warnings-as-errors, test, dialyzer, credo --strict

# Deps management
mix deps.get                       # Fetch deps
mix deps.clean --all               # Clean all deps
mix deps.update --all              # Update all deps
```

---

## Notes

- Use `Supertester` for all new tests (v0.5.0)
- No `Process.sleep` - use `cast_and_sync` or `TelemetryHelpers`
- Prefer small, focused commits
- Update CLAUDE.md after each RGR cycle
- When in doubt, write a test first
