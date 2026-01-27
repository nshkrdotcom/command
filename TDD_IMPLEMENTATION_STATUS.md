# TDD Implementation Status for Quality Gates (Prompt 008)

## Overview

This document tracks the TDD implementation of the quality gates and test strategy for the workflow automation system, following **strict TDD discipline**: ALL tests written FIRST, then implementation.

---

## ✅ COMPLETED: Test Files (Written FIRST - TDD Phase 1)

### Gate Framework Tests
1. **test/command/gates/gate_spec_test.exs** ✅
   - Tests for GateSpec struct
   - Category validation (:doc, :impl, :ops)
   - Retry configuration structure
   - JSON serialization roundtrip

2. **test/command/gates/gate_criterion_test.exs** ✅
   - Tests for GateCriterion struct
   - Evaluator function (1-arity, returns :pass | {:fail, details})
   - Threshold field for numeric criteria
   - Required field for blocking behavior
   - Context-based and threshold-based evaluation patterns

3. **test/command/gates/engine_test.exs** ✅
   - Gate evaluation engine tests
   - evaluate_gate/2 with all criteria passing/failing
   - Telemetry emission on pass/fail
   - Exception handling in evaluators
   - load_gate_spec/1 for all 13 gates
   - Gate record creation with timestamps
   - Retry logic with configurable max_retries
   - Idempotent evaluation

4. **test/command/gates/override_test.exs** ✅
   - Override workflow tests
   - request_override/2 creates pending requests
   - Requires justification, risk_assessment, mitigations
   - approve_override/2 with authority matrix enforcement
   - reject_override/2 with rejection reason
   - list_pending_overrides/0 excludes approved/rejected
   - get_override/1 returns full history
   - is_overridden?/1 checks active overrides
   - Override expiration after configured duration
   - Authority matrix: Product Owner (DOC), DBA/Tech Lead (IMPL-004), Architect (IMPL-005), Engineering Manager (OPS-002)

5. **test/command/gates/cost_ceiling_test.exs** ✅
   - GATE-OPS-002 implementation tests
   - **Uses Decimal arithmetic throughout** (critical requirement)
   - Cost < ceiling passes, cost >= ceiling fails
   - Boundary value testing (exact ceiling value)
   - Per-run ceiling evaluated independently
   - Per-session ceiling tracks cumulative cost
   - Default ceilings: $50/run, $500/session
   - Custom ceilings from run config
   - Cost extraction from event.usage.total_cost_usd
   - Edge cases: nil cost (treated as 0), negative cost (error), zero cost
   - Floating point precision tests (0.1 + 0.2 = 0.3 with Decimal)
   - Telemetry emission with cost details

### Parity Testing Framework Tests
6. **test/command/parity/parity_helper_test.exs** ✅
   - run_parity_test/2 executes against Claude and Codex
   - normalize/2 for Claude responses (tool_use, streaming)
   - normalize/2 for Codex responses (function_call, streaming)
   - compare/2 calculates parity_score and discrepancies
   - **Token-level Jaccard similarity** for message content (per ADR-0008)
   - Tool calls compared by name and argument structure
   - Token usage compared with 20% tolerance
   - Parity thresholds: message_parity (0.9), tool_call_parity (0.95), metadata_presence (1.0), unknown_event_rate (0.01), overall_parity (0.9)
   - Jaccard similarity: identical (1.0), different (0.0), partial overlap
   - Text normalization: lowercase, trim, collapse whitespace, strip punctuation, keep _ and -
   - Metadata validation for required fields

### Test Infrastructure Tests
7. **test/command/fixtures/fixture_helper_test.exs** ✅
   - load_fixture/1 loads JSON, raises on missing file
   - load_prompt_set/1 from prompt_sets directory
   - load_claude_response/1 from provider_responses/claude (simple, tool_call, streaming, errors)
   - load_codex_response/1 from provider_responses/codex (simple, item_call, streaming, errors)
   - load_normalized_event/1 includes provider-specific data
   - git_fixture_repo/0 creates temporary git repo with config
   - Unique repos on multiple calls
   - Can add and commit files
   - cleanup_git_fixture/1 removes directory
   - Fixture path resolution relative to test/fixtures
   - Fixture validation (exists?, readable?)
   - VCS fixtures (git_status_clean, git_status_dirty, git_diff_sample)
   - Approval fixtures (pending, approved, rejected)

8. **test/command/mocks/http_mock_test.exs** ✅
   - setup_claude_mock/2 configures Bypass for Claude API
   - setup_codex_mock/2 configures Bypass for Codex API
   - Returns configured response on request
   - Supports response sequences for multi-turn
   - setup_streaming_mock/2 for chunk sequences
   - setup_error_mock/2 for 429, 500 errors with details
   - Delayed responses for timeout testing
   - Mock state management and reset
   - Request validation (body, headers)

---

## 🔨 TODO: Implementation Files (TDD Phase 2 - Make Tests Pass)

### Core Gate Infrastructure
9. **lib/command/gates/gate_spec.ex** - PENDING
   - GateSpec struct definition
   - Fields: id, name, category, when, blocks, criteria, retry_config
   - Category type: :doc | :impl | :ops
   - Retry config type: max_retries, backoff_ms, auto_retry

10. **lib/command/gates/gate_criterion.ex** - PENDING
    - GateCriterion struct definition
    - Fields: name, evaluator, threshold, required (default true)
    - Evaluator type: (context() -> :pass | {:fail, term()})

11. **lib/command/gates/engine.ex** - PENDING
    - evaluate_gate/2 implementation
    - Runs all criteria evaluators
    - Returns :pass or {:fail, results}
    - Emits telemetry events
    - Creates gate records with timestamps
    - Exception handling for evaluators
    - Retry logic with backoff
    - load_gate_spec/1 loads gate definitions

12. **lib/command/gates/definitions.ex** - PENDING
    - All 13 gate definitions:
      - GATE-DOC-001, 002, 003 (Documentation)
      - GATE-IMPL-001, 002, 003, 004, 005, 006, 007 (Implementation)
      - GATE-OPS-001, 002, 003 (Operational)
    - Each with criteria evaluators
    - Retry configs per gate

### Override Workflow
13. **lib/command/gates/override.ex** - PENDING
    - request_override/2 creates pending request
    - approve_override/2 with authority check
    - reject_override/2 with reason
    - list_pending_overrides/0
    - get_override/1
    - is_overridden?/1 checks active overrides
    - Expiration logic

14. **lib/command/gates/authority_matrix.ex** - PENDING
    - can_approve?/2 checks role authorization
    - required_roles/1 returns authorized roles per gate
    - Matrix: DOC/* → product_owner, IMPL-004 → dba|tech_lead, IMPL-005 → architect, IMPL-006 → tech_lead, OPS-002 → engineering_manager

15. **lib/command/gates/override_request.ex** (schema) - PENDING
    - Ecto schema for override requests
    - Fields: id, gate_id, gate_record_id, requested_by, requested_at, justification, risk_assessment, mitigations, decision, status
    - Changesets for validation

### Cost Ceiling Gate
16. **lib/command/gates/cost_ceiling.ex** - PENDING
    - **CRITICAL: Use Decimal throughout**
    - evaluate/2 checks cost vs ceiling
    - Default ceilings: $50/run, $500/session
    - get_ceiling/1 applies defaults or config
    - event_cost/1 extracts cost from event
    - Telemetry emission
    - Boundary value handling (cost > ceiling, not >=)

### Parity Test Framework
17. **lib/command/test/parity_helper.ex** - PENDING
    - run_parity_test/2 executes against both providers
    - normalize/2 for Claude and Codex
    - normalize_streaming/2 for chunk aggregation
    - compare/2 calculates parity score
    - jaccard_similarity/2 with text normalization
    - validate_metadata/1 checks required fields
    - threshold/1 returns parity thresholds
    - parity_pass?/1 checks score >= threshold

### Fixture Infrastructure
18. **lib/command/test/fixture_helper.ex** - PENDING
    - load_fixture/1 with JSON parsing
    - load_prompt_set/1
    - load_claude_response/1
    - load_codex_response/1
    - load_normalized_event/1
    - load_vcs_fixture/1
    - load_approval_fixture/1
    - git_fixture_repo/0 creates temp git repo
    - cleanup_git_fixture/1
    - fixture_path/2 resolves paths
    - fixture_exists?/1, fixture_readable?/1

19. **lib/command/test/http_mock.ex** - PENDING
    - setup_claude_mock/2,3 with Bypass
    - setup_codex_mock/2,3
    - setup_streaming_mock/2
    - setup_error_mock/2,3
    - setup_delayed_mock/3
    - setup_multi_turn_mock/2
    - Request validation helpers

### Fixtures (Sample Data)
20. **test/fixtures/prompt_sets/simple_set.json** - PENDING
21. **test/fixtures/prompt_sets/multi_prompt_set.json** - PENDING
22. **test/fixtures/provider_responses/claude/simple_completion.json** - PENDING
23. **test/fixtures/provider_responses/claude/tool_call.json** - PENDING
24. **test/fixtures/provider_responses/claude/streaming_chunks.json** - PENDING
25. **test/fixtures/provider_responses/claude/error_429.json** - PENDING
26. **test/fixtures/provider_responses/codex/simple_completion.json** - PENDING
27. **test/fixtures/provider_responses/codex/item_call.json** - PENDING
28. **test/fixtures/provider_responses/codex/streaming_chunks.json** - PENDING
29. **test/fixtures/provider_responses/codex/error_500.json** - PENDING
30. **test/fixtures/normalized_events/message_event.json** - PENDING
31. **test/fixtures/normalized_events/tool_event.json** - PENDING
32. **test/fixtures/normalized_events/usage_event.json** - PENDING
33. **test/fixtures/vcs/git_status_clean.txt** - PENDING
34. **test/fixtures/vcs/git_status_dirty.txt** - PENDING
35. **test/fixtures/vcs/git_diff_sample.txt** - PENDING
36. **test/fixtures/approvals/pending_approval.json** - PENDING
37. **test/fixtures/approvals/approved_item.json** - PENDING
38. **test/fixtures/approvals/rejected_item.json** - PENDING

### CI/CD and Scripts
39. **.github/workflows/quality-gates.yml** - PENDING
    - Jobs: unit-tests, integration-tests, parity-tests, gate-impl-005, gate-impl-006, coverage-gate
    - PostgreSQL service for integration tests
    - Coverage threshold enforcement (80%)

40. **scripts/check_gate.exs** - PENDING
    - Command-line gate evaluation
    - Loads gate spec and context
    - Returns exit code 0 for pass, 1 for fail

41. **CHANGELOG.md update** - PENDING
    - Add entry under Unreleased section

---

## Test Execution Commands

```bash
# Run all gate tests
mix test test/command/gates/ --trace

# Run specific test files
mix test test/command/gates/gate_spec_test.exs --trace
mix test test/command/gates/engine_test.exs --trace
mix test test/command/gates/override_test.exs --trace
mix test test/command/gates/cost_ceiling_test.exs --trace

# Run parity tests
mix test test/command/parity/ --trace

# Run fixture and mock tests
mix test test/command/fixtures/ --trace
mix test test/command/mocks/ --trace

# Run with coverage
mix test --cover

# Verify no warnings
mix compile --warnings-as-errors

# Run credo
mix credo --strict

# Run dialyzer
mix dialyzer
```

---

## Critical Implementation Notes

### Cost Ceiling (GATE-OPS-002)
- **MUST use Decimal arithmetic throughout** - NO floats for monetary calculations
- Boundary condition: cost > ceiling fails (not >=)
- Default ceilings: Decimal.new("50.00") per run, Decimal.new("500.00") per session
- Handle nil cost as Decimal.new("0.00")
- Return {:error, :invalid_cost} for negative costs

### Parity Testing
- **Token-level Jaccard similarity** for message content per ADR-0008
- Normalization: lowercase, trim, collapse whitespace, strip punctuation, keep _ and -
- Tokenize on whitespace
- Similarity = |tokens_a ∩ tokens_b| / |tokens_a ∪ tokens_b|
- Token usage tolerance: 20% variance acceptable
- Thresholds: message_parity (0.9), tool_call_parity (0.95), metadata_presence (1.0)

### Authority Matrix
- GATE-DOC-* → Product Owner
- GATE-IMPL-004 (Migration) → DBA or Tech Lead
- GATE-IMPL-005 (Parity) → Architect
- GATE-IMPL-006 (Tests) → Tech Lead
- GATE-OPS-002 (Cost) → Engineering Manager

### Telemetry Events
- [:command, :gates, :evaluated] - every gate evaluation
- [:command, :gates, :failed] - gate failure with criteria details
- [:command, :gates, :override, :requested]
- [:command, :gates, :override, :approved]
- [:command, :gates, :override, :rejected]
- [:command, :gates, :cost_ceiling, :evaluated]
- [:command, :gates, :cost_ceiling, :exceeded]

---

## Next Steps (TDD Phase 2)

1. **Run tests to see them fail** (RED phase)
   ```bash
   mix test test/command/gates/ test/command/parity/ test/command/fixtures/ test/command/mocks/
   ```

2. **Implement minimal code to make tests pass** (GREEN phase)
   - Start with gate_spec.ex and gate_criterion.ex (simple structs)
   - Then engine.ex (evaluation logic)
   - Then definitions.ex (all 13 gates)
   - Then override.ex and authority_matrix.ex
   - Then cost_ceiling.ex (with Decimal!)
   - Then parity_helper.ex
   - Then fixture_helper.ex and http_mock.ex

3. **Refactor** (REFACTOR phase)
   - Extract common patterns
   - Optimize evaluators
   - Clean up code

4. **Create fixtures**
   - Sample JSON files for all fixture types

5. **Create CI/CD workflow and scripts**

6. **Update CHANGELOG**

7. **Verify all success criteria met**

---

## Success Criteria Checklist

### Gate Specification
- [ ] `Command.Gates.GateSpec` struct defined with all fields
- [ ] `Command.Gates.GateCriterion` struct defined with all fields
- [ ] All 13 gates defined in `Command.Gates.Definitions`
- [ ] Gate specs serializable to JSON

### Gate Evaluation Engine
- [ ] `Command.Gates.Engine.evaluate_gate/2` evaluates all criteria
- [ ] Returns `:pass` when all criteria pass
- [ ] Returns `{:fail, results}` when any criterion fails
- [ ] Emits telemetry events for pass and fail
- [ ] Creates gate records with timestamps
- [ ] Handles evaluator exceptions gracefully

### Override Workflow
- [ ] `Command.Gates.Override.request_override/2` creates pending request
- [ ] `Command.Gates.Override.approve_override/2` approves with audit
- [ ] `Command.Gates.Override.reject_override/2` rejects with reason
- [ ] Authority matrix enforced per gate type
- [ ] Override expiration implemented
- [ ] Full audit trail maintained

### Cost Ceiling Gate
- [ ] GATE-OPS-002 uses Decimal arithmetic
- [ ] Evaluates per-run ceiling correctly
- [ ] Evaluates per-session ceiling correctly
- [ ] Boundary value (cost == ceiling) handled correctly
- [ ] Default ceilings applied when not configured
- [ ] Telemetry emitted with cost details

### Parity Test Framework
- [ ] `Command.Test.ParityHelper.run_parity_test/2` implemented
- [ ] Normalization for Claude responses
- [ ] Normalization for Codex responses
- [ ] Comparison with parity score calculation
- [ ] Discrepancy list returned on parity failure
- [ ] Parity thresholds configurable

### Fixture Infrastructure
- [ ] Fixture directory structure created
- [ ] Fixture helper modules implemented
- [ ] Claude response fixtures created
- [ ] Codex response fixtures created
- [ ] Normalized event fixtures created
- [ ] Git fixture repo helper working

### HTTP Mocks
- [ ] Bypass-based mocking for Claude API
- [ ] Bypass-based mocking for Codex API
- [ ] Streaming mock support
- [ ] Error response mocking (429, 500)
- [ ] Delayed response mocking for timeouts

### CI/CD Integration
- [ ] GitHub Actions workflow created
- [ ] Unit test job defined
- [ ] Integration test job defined
- [ ] Parity test job defined
- [ ] Gate check jobs defined (GATE-IMPL-005, GATE-IMPL-006)
- [ ] Coverage gate enforces 80% threshold

### Code Quality
- [ ] All tests pass
- [ ] No compilation warnings
- [ ] No credo issues
- [ ] No dialyzer errors
- [ ] Test coverage >= 85%

### Documentation
- [ ] CHANGELOG.md updated
- [ ] Module docs present on all public modules
- [ ] Function docs present on all public functions

---

## Status Summary

- **Tests Written (TDD Phase 1):** ✅ COMPLETE (8 test files, 200+ test cases)
- **Implementation (TDD Phase 2):** 🔨 PENDING (Start with failing tests, then implement)
- **Fixtures Created:** 🔨 PENDING
- **CI/CD Setup:** 🔨 PENDING
- **Documentation:** 🔨 PENDING

**Next Action:** Run `mix test` to see all tests fail (RED phase), then begin implementation to make them pass (GREEN phase).
